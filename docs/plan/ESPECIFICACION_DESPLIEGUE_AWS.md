# Especificación: correcciones previas al despliegue en AWS (Parte III)

Fecha: 2026-11-23. Rama: `fase2-mejoras`. Entorno destino: **cuenta propia de AWS, región `us-east-2`**
(no AWS Academy). El enunciado completo está resumido en `docs/aws/GUIA_DESPLIEGUE.md`.

La revisión del enunciado contra el repositorio encontró los huecos de esta lista. Cada tarea indica qué hacer, dónde y
cómo se comprueba. No crear recursos en AWS ni ejecutar el CLI de AWS: solo código, plantillas, scripts y documentación.

## Reglas generales

- No hacer commits. No escribir secretos, contraseñas, ID de cuenta ni ARN reales en el repositorio.
- Las plantillas siguen el estilo actual (JSON dentro de `.yaml`, parámetros `Prefijo`, `Entorno`, `Responsable`,
  etiquetas comunes) y deben pasar `cfn-lint` sin errores ni advertencias.
- Mantener la compatibilidad con AWS Academy cuando ya exista (`UsarLabRole=true`), pero el camino principal ahora es
  la cuenta propia.
- Al terminar, escribir el informe `docs/informes/2026-11-23_correcciones-predespliegue-aws.md` con: qué se cambió por
  tarea, archivos tocados, comandos de verificación ejecutados con su resultado, y límites o decisiones pendientes.

## Tarea A. SNS conectado a eventos reales (Parte 4 y punto 8 de la Parte 6)

Hoy `backend/app/eventos.py::publicar_evento` existe pero nadie lo llama y el rol de EC2 no tiene `sns:Publish`.

1. Publicar, **después de confirmar la transacción** y sin bloquear la respuesta (tarea de fondo de FastAPI), en:
   - `POST /documentos/cierres` → evento `trazabilidad.cerrada` (cierre del ciclo del equipo o lote: destino final).
   - `POST /documentos/transferencias` → `transferencia.enviada`, y `POST /documentos/transferencias/{uid}/recibir`
     → `transferencia.recibida` (movimiento de RAEE entre ecosistemas).
   El mensaje lleva identificadores de negocio (códigos, ecosistema, estado, fecha), nunca datos personales ni
   secretos. Usar `Subject` legible en español y `MessageAttributes` con `tipo` para permitir filtros.
2. Si `SNS_TOPIC_ARN` no está definido (local, pruebas) no hace nada; un fallo de SNS nunca rompe la petición.
3. Infraestructura:
   - Nuevo tema SNS de **eventos de negocio** (separado del tema de alarmas de `07-observabilidad`), con suscripción
     por correo parametrizada (`CorreoEventos`) y cifrado con la clave administrada de SNS.
   - Ubicarlo donde no cree dependencias circulares (sugerencia: en `02-seguridad.yaml`, exportado) y conceder al rol
     de EC2 **solo** `sns:Publish` sobre ese ARN.
   - Pasar `SNS_TOPIC_ARN` al contenedor de la API (`05-computo.yaml` → user-data → `docker run -e`) y documentarlo en
     `.env.aws.example` y `docker-compose.aws.yml`.
4. Pruebas: unitarias con `botocore.stub.Stubber` o `unittest.mock` que comprueben que el cierre y la transferencia
   publican el evento correcto y que sin `SNS_TOPIC_ARN` no se llama a boto3.

## Tarea B. Usuarios, grupos y políticas IAM en plantilla (Parte 5)

Nueva plantilla `infrastructure/cloudformation/08-iam.yaml` (se despliega **primero**, con la cuenta raíz, una sola vez):

- **Usuarios** (parámetros con estos valores por defecto): `iam-user-infra-nicolas`, `iam-user-dba-diego`,
  `iam-user-app-eithan`. **Sin** `LoginProfile` ni claves de acceso: la contraseña y las claves las crea el propio
  usuario o el titular de la cuenta en la consola. Política que obligue MFA es opcional; documentar si no se incluye.
- **Grupos** y pertenencia:

  | Grupo | Miembros | AWS Managed | Customer Managed |
  |---|---|---|---|
  | EcoRAEE-InfraAdmins | nicolas | `AWSCloudFormationFullAccess`, `IAMUserChangePassword` | `EcoRAEE-InfraOpsPolicy` + `iam:PassRole` **solo** sobre el rol de despliegue |
  | EcoRAEE-DBAdmins | diego | `AmazonRDSReadOnlyAccess`, `IAMUserChangePassword` | `DatabaseOpsPolicy` (lectura del secreto maestro y túnel por Session Manager a RDS) |
  | EcoRAEE-AppAdmins | eithan | `AmazonEC2ReadOnlyAccess`, `IAMUserChangePassword` | `AppsOpsPolicy` (publicar el frontend: escribir en el bucket del frontend e invalidar CloudFront; Session Manager a la EC2) |
  | EcoRAEE-Developers | eithan | `AWSCloudFormationReadOnlyAccess` | `DeveloperPolicy` |
  | EcoRAEE-Monitoring | nicolas, diego, eithan | `CloudWatchReadOnlyAccess`, `AWSCloudTrail_ReadOnlyAccess` | `AuditReadPolicy` |

  Ajustar las tablas si un nombre de política administrada no existe; verificar los nombres exactos.
- **Rol de despliegue de CloudFormation** (`EcoRAEE-CfnDeployRole`, confianza `cloudformation.amazonaws.com`): es el
  que realmente crea los stacks 01–07, de modo que el usuario de infraestructura no necesita permisos directos de
  EC2, RDS, S3, etc. Permisos limitados a los servicios de las plantillas; si se usa una administrada amplia
  (p. ej. `PowerUserAccess`), justificarlo y acotar IAM con una política propia (crear roles e instance profiles solo
  con el prefijo del proyecto).
- Convertir los JSON de `infrastructure/iam/` en `AWS::IAM::ManagedPolicy` dentro de la plantilla, sustituyendo los
  marcadores (`BUCKET_*`, `ARN_*`, `REGION`, `ACCOUNT`) por patrones construidos con `Prefijo`, `AWS::Region` y
  `AWS::AccountId` (los buckets y secretos se crean después, así que usar patrones por nombre con el prefijo). Mínimo
  privilegio: nada de `AdministratorAccess` ni `"Action": "*"`.
- Salidas: ARN de cada grupo, del rol de despliegue y URL de inicio de sesión de la consola.
- Actualizar `infrastructure/iam/README.md` y `docs/aws/iam.mmd` para que coincidan con la plantilla.

## Tarea C. Migración completa a RDS (Parte 3)

1. `infrastructure/scripts/migrar_base.sh` omite `20_verificacion_correo.sql`: agregarlo (y cualquier script posterior
   que exista) en el mismo orden que `database/rebuild.sh`. Hacer que la lista salga de una única fuente si es viable.
2. La opción `--datos` (copiar los datos de la base local) nunca se probó y choca con las semillas que cargan los
   scripts. Rediseñarla para que funcione de verdad: por ejemplo, volcado de las tablas de negocio con
   `--data-only --disable-triggers` excluyendo las tablas que ya llenan las semillas, o volcado completo restaurado
   sobre una base vacía seguido de logins de servicio, script 19 y preparación de producción. Elegir la opción más
   simple que funcione y documentar el porqué.
3. **Probarlo en local** emulando RDS: un contenedor `postgres:16` nuevo donde el usuario que migra **no es
   superusuario** (rol con `CREATEROLE` y `CREATEDB`, como el maestro de RDS), aplicar la migración completa y luego
   `--datos` desde la base de desarrollo. Registrar en el informe los comandos y el resultado (conteos de filas antes y
   después en las tablas principales).
4. Documentar cómo ejecutarlo en AWS sin exponer RDS: túnel de Session Manager
   (`AWS-StartPortForwardingSessionToRemoteHost`) desde la PC a RDS a través de la EC2, con las credenciales del
   usuario DBA, y el CA de RDS para `verify-full`.

## Tarea D. Parámetros para la cuenta propia en `us-east-2`

1. Nuevo `infrastructure/cloudformation/parametros/cuenta-propia.json` (`UsarLabRole=false`, `Entorno=prod`,
   `ClaseDB=db.t4g.micro`, `TipoInstancia=t3.small`, `MultiAZ=false`, `CrearNAT=true`, presupuesto 30 USD).
2. `AmiId` en `05-computo.yaml`: cambiar a `AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>` con valor por defecto
   `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64`, para que funcione en cualquier región.
3. `CloudFrontPrefixListId`: quitar el valor por defecto de us-east-1 y documentar el comando para obtenerlo en la
   región (`aws ec2 describe-managed-prefix-lists --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing`).
4. Actualizar `infrastructure/README.md` y `docs/aws/GUIA_DESPLIEGUE.md`: región `us-east-2`, orden nuevo
   (08-iam con la cuenta raíz → el titular crea contraseñas y claves → CLI con el usuario de infraestructura →
   01…07 con `--role-arn` del rol de despliegue), SES en modo sandbox (verificar remitente y destinatarios), SNS de
   eventos y su comprobación, migración con túnel y orden de destrucción (incluido 08 al final).
5. Actualizar `evidence/README.md`: CP-11 con usuarios y grupos reales y una fila nueva para SNS.

## Tarea E. Detalles de interfaz pendientes (móvil)

1. En el dashboard, el título «¡Hola, …» se corta en pantallas de 375 px: debe ajustarse o partirse en dos líneas.
2. En Equipos, los filtros ocupan toda la pantalla en móvil: colapsarlos detrás de un botón «Filtros» (con contador
   de filtros activos) por debajo de 768 px; en escritorio se ven como hoy.
3. Sin colores fijos fuera de `tokens.css`; temas claro, oscuro y sistema intactos.

## Verificación obligatoria (registrar resultados en el informe)

```
docker compose -f docker-compose.pruebas.yml run --rm pruebas
docker compose -f docker-compose.pruebas.yml run --rm pruebas base
docker compose -f docker-compose.pruebas.yml down -v
docker run --rm -v "<repo>/frontend:/web" -w /web node:22-alpine sh -c "npm ci --no-audit --no-fund && npm run build"
cfn-lint infrastructure/cloudformation/*.yaml   (en un contenedor python:3.13-slim)
```

Más la prueba de migración de la Tarea C.
