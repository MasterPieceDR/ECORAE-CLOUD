# Guía de despliegue en AWS y evidencias (Proyecto Integrador III)

> Cuenta propia: cree primero `08-iam` con el titular de la cuenta; el resto se despliega con el usuario de infraestructura y el rol de CloudFormation. La validación en AWS sigue pendiente.

Esta guía lleva EcoRAEE Cloud del entorno local (Docker) a AWS y dice **qué evidencia capturar** para cada caso de
prueba del enunciado (sección 10.1). Los comandos exactos están en [infrastructure/README.md](../../infrastructure/README.md);
aquí se explica el orden, el porqué y cómo comprobar cada paso.

> Regla de oro: ninguna contraseña, token, clave de acceso ni URL prefirmada completa aparece en capturas, en el
> repositorio ni en la memoria técnica (enunciado 10.5). Enmascara los ARN de la cuenta si vas a publicar el documento.

## 1. Arquitectura que se despliega

```
Usuario ──HTTPS──▶ CloudFront ──OAC──▶ S3 (frontend, privado)
                       │
                       └──/api/* (sin caché)──▶ ALB (subredes públicas, 2 AZ)
                                                   │ :8000 (solo desde el SG del ALB)
                                                   ▼
                                    EC2 en Auto Scaling (subredes privadas de app, 2 AZ)
                                     │ rol EcoRAEE-EC2RuntimeRole · IMDSv2 · sin SSH (Session Manager)
                                     │ :5432 TLS (solo desde el SG de la app)
                                     ▼
                                    RDS PostgreSQL 16 (subredes privadas de datos, 2 AZ; Multi-AZ opcional)
Navegador ──PUT/GET prefirmado──▶ S3 evidencias / S3 contenidos (privados, cifrados, versionados)
Observabilidad: CloudWatch Logs + alarmas → SNS (correo) · CloudTrail · AWS Budgets
```

Diagramas editables: [arquitectura.mmd](arquitectura.mmd) e [iam.mmd](iam.mmd). Cambios respecto al diagrama de la Parte II:

| Hallazgo en la Parte II | Corrección |
|---|---|
| EC2 y RDS solo en la AZ A (punto único de fallo, RNF-02; además el ALB y el grupo de subredes de RDS exigen 2 AZ) | Subredes en 2 AZ, ASG de 1 a 2 instancias, RDS con grupo de subredes en 2 AZ y Multi-AZ por parámetro |
| EC2 privada sin salida a Secrets Manager, CloudWatch ni SSM | NAT Gateway (parámetro `CrearNAT`) y endpoints de interfaz opcionales (`CrearEndpoints`) |
| La subida de evidencias se dibujaba desde la EC2 por el endpoint de VPC, pero el código sube desde el navegador con URL prefirmada | El diagrama refleja la subida directa navegador → S3; los buckets tienen CORS y no se restringen al endpoint de VPC |
| ALB fuera de las subredes públicas y sin grupos de seguridad | ALB en las subredes públicas; cadena de SG ALB → EC2:8000 → RDS:5432 |
| CloudTrail conectado a RDS | CloudTrail registra las llamadas a la API de AWS de toda la cuenta; los logs de la app salen de la EC2 por `awslogs` |
| Un solo bucket de evidencias | Dos buckets: evidencias y contenidos (videos de capacitación), como usa el código |

## 2. Requisitos previos

- El titular crea primero el stack `08-iam` desde la consola raíz, acepta IAM con nombre y crea después contraseñas y claves; habilite MFA. Configure AWS CLI v2 con **EcoRAEE-InfraAdmins** para los stacks restantes.
  En AWS Academy (Learner Lab) se usa la sesión del laboratorio y el parámetro `UsarLabRole=true`, porque Academy no
  permite crear usuarios, grupos ni roles IAM: las políticas de [infrastructure/iam/](../../infrastructure/iam/) quedan como
  diseño documentado y el rol de la EC2 es `LabRole` (vía `LabInstanceProfile`).
- Región: `us-east-2`. La AMI Amazon Linux 2023 x86_64 se resuelve por SSM en la región.
- Nombres de bucket globalmente únicos (frontend, evidencias, contenidos, auditoría y artefactos).
- Un correo para las alarmas (hay que confirmar la suscripción SNS que llega por correo).
- Docker Desktop y Node 22 en la PC para compilar el frontend.

## 3. Ensayo en local antes de AWS

`docker-compose.produccion.yml` reproduce en la PC la configuración de AWS (`ENTORNO=produccion`, `DEMO=false`, S3 con
LocalStack, nginx con las cabeceras de CloudFront). Ejecuta `iniciar_produccion_local.bat` y comprueba en
http://localhost:8090 lo mismo que comprobarás en AWS. El resultado del ensayo está en
[docs/informes/2026-11-23_produccion-local-y-credenciales.md](../informes/2026-11-23_produccion-local-y-credenciales.md).

## 4. Secuencia de despliegue

| Paso | Qué se hace | Cómo se comprueba |
|---|---|---|
| 0 | Con la cuenta raíz crear `08-iam`, crear contraseñas y claves, configurar el usuario de infraestructura y obtener la salida `DeployRoleArn` | Verificar usuarios, grupos y rol; habilitar MFA |
| 1 | Crear el bucket de artefactos (privado, cifrado) y subir el ZIP del código del backend | `aws s3 ls s3://<artefactos>/ecoraee/` |
| 2 | Stack `red` (VPC, 6 subredes, IGW, NAT, endpoint S3) | Consola VPC → mapa de recursos con 2 AZ |
| 3 | Stack `seguridad` (grupos de seguridad, rol e instance profile) | Reglas de entrada de cada SG; política del rol |
| 4 | Stack `datos` (RDS, secretos generados) | RDS «Disponible», sin acceso público, cifrado activado |
| 5 | Stack `almacenamiento` (buckets con bloqueo público, cifrado, versionado y CORS) | Pestaña Permisos de cada bucket |
| 6 | Stack `computo` (Launch Template, ALB, target group, ASG) | Target group: instancias `healthy` (tras el paso 8) |
| 7 | Stack `cdn` (CloudFront con OAC y origen `/api/*`) y redepliegue de `almacenamiento` y `computo` con el dominio real de CloudFront como `OrigenWeb` | `https://<dominio>/` carga la web |
| 8 | Migrar la base: `infrastructure/scripts/migrar_base.sh` desde una sesión privada (scripts 01–20, logins de servicio y preparación de producción: cuentas sintéticas sin credencial y administrador inicial con clave aleatoria). Para la evaluación, `CLAVE_DEMO=<clave aleatoria>` activa las cuentas sintéticas con esa clave, que se entrega al docente por un canal privado | `https://<dominio>/api/v1/verificacion/conexion` responde `PostgreSQL 16` y el login con la clave del repositorio da 401 |
| 9 | `docker exec ecoraee-api python -m app.cli inicializar` (por Session Manager) para calcular la red E0–E4 | Dashboard muestra la capacidad de la red |
| 10 | Stack `observabilidad` (log group, alarmas, SNS, CloudTrail, Budgets) y confirmar el correo | Alarmas en estado `OK` |
| 11 | Publicar el frontend: `infrastructure/scripts/publicar_frontend.sh` (o `.ps1`) | La web carga desde CloudFront e invalida la caché |

**Datos de la base local.** Si quieres llevar a RDS los datos que creaste en Docker (no solo la demo), usa
`migrar_base.sh --datos` sobre una base RDS recién creada y vacía de datos, como indica `infrastructure/README.md`.

Todos los despliegues 01–07 usan `--role-arn` y los parámetros por plantilla convertidos desde `cuenta-propia.json` como muestra el README. El DBA accede a RDS por el túnel Session Manager con la CA oficial y `verify-full`. En SES sandbox se verifican remitente y destinatarios. Confirme las suscripciones SNS de eventos y alarmas; genere cierre y transferencias y compruebe el correo de eventos. Para destruir, elimine 07–01 en orden inverso y finalmente 08 con el titular, tras retirar credenciales y sesiones.

## 5. Evidencias por caso de prueba

Guarda cada captura en `evidence/<CP>/` con el nombre `<CP>_<AAAA-MM-DD>_<descripcion>.png` y anota en
[evidence/README.md](../../evidence/README.md) la fecha, el stack, los pasos, el resultado esperado y el obtenido.

| Caso (enunciado 10.1) | Resultado esperado | Qué capturar |
|---|---|---|
| **CP-01** Acceso por rol | Permite o deniega según la matriz | En la web desplegada: un generador no ve «Usuarios»; respuesta 403 al intentar crear un modelo de catálogo |
| **CP-09** Integración matemática | El algoritmo procesa datos de la red leídos desde RDS | Página «Red» con flujo máximo y corte mínimo; `GET /api/v1/verificacion/base` mostrando el motor en RDS |
| **CP-10** Conectividad cloud | Comunicación autorizada; acceso directo restringido | (1) web → API → RDS funcionando (`/verificacion/conexion`); (2) la EC2 **sin IP pública**; (3) RDS con «Acceso público: No»; (4) intento de abrir el bucket del frontend por su URL S3 directa → `AccessDenied` (solo CloudFront entra por OAC); (5) SG de RDS que solo admite 5432 desde el SG de la app |
| **CP-11** IAM | Aplica mínimo privilegio | (1) política del rol de EC2 limitada a los dos buckets, a los dos secretos y a logs; (2) desde la EC2 por Session Manager, `aws s3 ls` de otro bucket → `AccessDenied`; (3) `aws secretsmanager get-secret-value` del secreto maestro → `AccessDenied`; (4) grupos y usuarios IAM sin `AdministratorAccess` (en Academy, el diseño en `infrastructure/iam/` y su justificación) |
| **CP-12** IaC | Los recursos se recrean sin pasos ocultos | Los 8 stacks en `CREATE_COMPLETE`; la pestaña «Recursos» de cada uno; prueba de recreación: borrar y volver a desplegar `computo` y ver la instancia nueva `healthy` |
| **CP-13** Trazabilidad | Historial ordenado y destino final verificable | Un equipo recorrido de punta a punta en la web desplegada: línea de tiempo, fotos subidas a S3 (galería) y botón «Ver en la base de datos» |
| **CP-14** Monitorización | Log, métrica y alarma observables | (1) CloudWatch Logs Insights con `fields @timestamp, estado, ruta, ms \| filter estado >= 500`; (2) provocar errores 5xx (por ejemplo, detener el contenedor de la API un par de minutos) y ver la alarma pasar a `ALARM` y el correo de SNS; (3) evento en CloudTrail de esa acción |
| **CP-15** Usabilidad | Identifica barreras y aplica mejoras | Fuera del alcance de AWS; ver `innovation/` |

Consulta útil de Logs Insights (los logs de la API son JSON de una línea):

```
fields @timestamp, metodo, ruta, estado, ms, request_id
| filter estado >= 400
| stats count(*) as errores, avg(ms) as ms_promedio by ruta, estado
| sort errores desc
```

## 6. Seguridad aplicada (RNF-03, enunciado 7.6)

- **Sin credenciales en el código ni en el repositorio.** La EC2 usa credenciales temporales del rol de instancia;
  las contraseñas de PostgreSQL y el secreto JWT los genera CloudFormation en Secrets Manager.
- **Logins separados en la base:** `ecoraee_api_svc` y `ecoraee_mcp_svc` sin INSERT/UPDATE directos; el usuario maestro
  de RDS solo se usa para migrar y lo gestiona RDS (`ManageMasterUserPassword`).
- **Cifrado en tránsito:** HTTPS en CloudFront, TLS verificado hacia RDS (`DB_SSL=true` y la CA oficial de RDS).
- **Cifrado en reposo:** RDS, EBS y los buckets S3 cifrados.
- **Red:** EC2 y RDS en subredes privadas; IMDSv2 obligatorio; sin puerto 22 (Session Manager).
- **Evidencias privadas** con URL prefirmadas de 5 minutos y bitácora de cada descarga (RN-07).
- **Auditoría:** CloudTrail para la cuenta y auditoría propia de la base para cada cambio de negocio.

## 7. Costos y apagado

Ver [costos.md](costos.md). Al terminar la evaluación, destruye los stacks en el orden indicado en
`infrastructure/README.md` (sección «Destrucción»). El presupuesto avisa al 80 %, pero **no detiene** recursos.

## 8. Limitaciones conocidas

- Con un solo NAT Gateway, la salida a internet depende de una AZ (se acepta por costo en el laboratorio).
- Sin dominio propio, el HTTPS termina en CloudFront; el tramo CloudFront → ALB va por HTTP dentro de la red de AWS.
  Con un dominio y un certificado de ACM se activaría HTTPS también en el ALB.
- El servidor MCP no se expone en AWS por defecto (perfil `mcp` de `docker-compose.aws.yml`).
- La primera arrancada de cada instancia compila la imagen de Docker (unos minutos). Para producción conviene
  publicar la imagen en Amazon ECR desde un pipeline de CI/CD y que el Launch Template solo la descargue.

El tema SNS de eventos de negocio es independiente del de alarmas: indique `CorreoEventos` en seguridad, confirme la suscripción y compruebe cierre y transferencias con mensajes sin datos personales. En SES sandbox verifique tanto el remitente como los destinatarios.
