# Especificación: arquitectura AWS dentro del plan gratuito

Fecha: 2026-11-23. Rama `fase2-mejoras`. Cuenta propia en **plan gratuito** de AWS, región `us-east-2`.

## Por qué

El titular pidió que todo funcione dentro del plan gratuito y que solo se pague lo estrictamente necesario, **sin dejar
de cumplir el enunciado** de la Parte III (S3 frontend + S3 evidencias, EC2 con Security Groups, RDS con migración,
SNS con función real, IAM con mínimo privilegio, validación integrada) y usando CloudWatch, CloudTrail, SNS, Budgets y
Trusted Advisor. Dos piezas del diseño actual no son gratuitas:

| Pieza | Costo aproximado | Decisión |
|---|---|---|
| NAT Gateway | ~1,10 USD/día + datos | **Eliminado** (ya se desplegó `01-red` con `CrearNAT=false`) |
| Application Load Balancer + Auto Scaling | ~0,55 USD/día | **Eliminar**: una sola instancia EC2 (es lo que pide la Parte 2) detrás de CloudFront |

Además, el despliegue real falló porque el plan gratuito limita la retención de respaldos de RDS: ya se añadió el
parámetro `DiasRespaldo` a `03-datos.yaml` (se despliega con `1`). No revertir ese cambio.

Estado actual en AWS: `ecoraee-prod-iam`, `ecoraee-prod-red` (sin NAT) y `ecoraee-prod-seguridad` desplegados. Los
demás stacks aún no existen. Los cambios en 01 y 02 se aplicarán como actualización de esos stacks.

## Diseño objetivo

```
Usuario ─HTTPS─▶ CloudFront ─OAC─▶ S3 frontend (privado)
                     └─/api/* (HTTP, cabecera X-Origin-Verify)─▶ EC2 (subred pública, IP pública,
                                    SG: solo puerto 80 desde la prefix list de CloudFront; sin SSH)
                                          │ 5432 TLS (solo desde el SG de la app)
                                          ▼
                                   RDS PostgreSQL 16 (subredes privadas de datos, sin acceso público)
Navegador ─URL prefirmada─▶ S3 evidencias / S3 contenidos
EC2 ─▶ Secrets Manager, SES, SNS (eventos), CloudWatch Logs (por internet desde la subred pública; S3 por el endpoint gateway)
CloudWatch (alarmas, filtro de métricas 5xx, panel) · CloudTrail · Budgets · SNS (alarmas)
```

Gratuito o dentro de los límites del plan: EC2 `t3.small` o `t3.micro` (750 h), EBS gp3 ≤ 30 GB, IPv4 pública de la
instancia (750 h), RDS `db.t4g.micro` 20 GB, S3, CloudFront, SNS, SES (sandbox), CloudWatch (≤ 10 alarmas, 3 paneles,
5 GB de logs), un trail de CloudTrail de eventos de administración, Budgets. Secrets Manager cuesta 0,40 USD por secreto
y mes tras 30 días de prueba: es el único pago "estrictamente necesario" (no hay credenciales en el código); no crear
secretos adicionales sin necesidad.

## Cambios

1. **`01-red.yaml`**: `CrearNAT` con valor por defecto `false`. Sin NAT, la ruta de las subredes privadas de aplicación
   no debe apuntar a nada inexistente (comprobar las condiciones). La EC2 irá en una subred **pública**.
2. **`02-seguridad.yaml`**: eliminar el SG del ALB. El SG de la app admite **solo TCP 80 desde la prefix list de
   CloudFront** (`CloudFrontPrefixListId`), sin SSH; el SG de RDS solo 5432 desde el SG de la app. Mantener el tema SNS
   de eventos, el rol de instancia y sus permisos mínimos (añadir `secretsmanager:GetSecretValue` sobre el secreto del
   origen si se crea, ver punto 4).
3. **`05-computo.yaml`**: sustituir Launch Template + ALB + Target Group + ASG por **una `AWS::EC2::Instance`**:
   subred pública con IP pública, IMDSv2 obligatorio, EBS gp3 cifrado de 20 GB, perfil de instancia del stack 02,
   `TipoInstancia` con valores permitidos `t3.micro`/`t3.small` (por defecto `t3.small`), AMI por SSM. Conservar el
   user-data actual (Docker, CloudWatch Agent, CA de RDS, logs `awslogs`, variables de entorno), publicando el contenedor
   en el puerto 80 del host. Añadir una alarma `StatusCheckFailed_System` con la acción de **recuperación automática**
   de EC2 (`arn:aws:automate:${AWS::Region}:ec2:recover`) como reemplazo gratuito de la autorreparación del ASG.
   Salidas: `InstanceId`, `PublicDnsName`, nombre del grupo de logs.
4. **Protección del origen**: sin ALB, la cabecera secreta `X-Origin-Verify` la valida la API. En el backend, un
   middleware que, si está configurado el secreto del origen, responde 403 a cualquier petición sin la cabecera correcta
   (comparación en tiempo constante). El valor llega a la instancia sin quedar en texto plano en el user-data: por
   ejemplo un `AWS::SecretsManager::Secret` en 05 creado a partir del parámetro `NoEcho`, leído por la app con su ARN
   (como ya hace con `DB_SECRET_ARN` y `JWT_SECRET_ARN`). Si se prefiere otra vía sin costo y segura, justificarla.
   Pruebas unitarias del middleware (sin secreto: no filtra; con secreto: 403 sin cabecera o con valor incorrecto, 200
   con el correcto).
5. **`06-cdn.yaml`**: el origen `/api/*` pasa a ser el `PublicDnsName` de la EC2 (parámetro), HTTP puerto 80
   (`OriginProtocolPolicy: http-only`), con la cabecera personalizada `X-Origin-Verify`. Sin caché para `/api/*`, como
   hoy. El resto (OAC, S3 privado, función de rutas del SPA) se mantiene.
6. **`07-observabilidad.yaml`**: sustituir las alarmas basadas en el ALB por:
   CPU de la EC2, `StatusCheckFailed` de la EC2, CPU / almacenamiento libre / conexiones de RDS, y un **filtro de
   métricas** sobre el grupo de logs de la API que cuente respuestas `estado >= 500` con su alarma (los logs son JSON
   de una línea con el campo `estado`). Añadir un **panel de CloudWatch** (`AWS::CloudWatch::Dashboard`) con EC2, RDS,
   errores 5xx y latencia (`ms`). Todas las alarmas notifican al tema SNS de alarmas. Mantener CloudTrail (un trail de
   administración, bucket cifrado y privado) y Budgets. Máximo 10 alarmas en total entre todos los stacks.
7. **`03-datos.yaml`**: sin Performance Insights ni Enhanced Monitoring de pago (dejar desactivados o en la capa
   gratuita), almacenamiento gp3/gp2 de 20 GB, sin Multi-AZ por defecto, `DiasRespaldo` ya existente.
8. **`08-iam.yaml`**: quitar o ajustar permisos que solo tenían sentido con ALB/ASG si quedan colgando; el despliegue
   y Session Manager deben seguir funcionando para la instancia única. Si se cambia, debe seguir pasando `cfn-lint`
   (se actualizará el stack con la cuenta raíz).
9. **Documentación**: nuevo ADR `docs/adr/ADR-016-plan-gratuito.md` (contexto, decisión, alternativas: ALB+ASG+NAT,
   endpoints de interfaz; consecuencias: sin alta disponibilidad multi-instancia, recuperación automática de EC2,
   origen protegido por prefix list + cabecera). Actualizar `docs/aws/GUIA_DESPLIEGUE.md`, `infrastructure/README.md`,
   `docs/aws/costos.md` (tabla del plan gratuito), `docs/aws/arquitectura.mmd` y `evidence/README.md` (CP-10 y CP-14
   con la nueva forma de evidenciar: EC2 con SG solo desde CloudFront, acceso directo a la IP → sin respuesta, panel y
   alarma de 5xx, CloudTrail). Incluir cómo consultar **Trusted Advisor** (comprobaciones gratuitas) como evidencia.

## Reglas

- No ejecutar el CLI de AWS ni crear recursos. No hacer commits. Sin secretos, ID de cuenta ni ARN reales.
- Mantener el estilo de las plantillas (JSON en `.yaml`), etiquetas y parámetros comunes.

## Verificación obligatoria (en serie)

```
docker compose -f docker-compose.pruebas.yml run --rm pruebas
docker compose -f docker-compose.pruebas.yml run --rm pruebas base
docker compose -f docker-compose.pruebas.yml down -v
docker run --rm -v "<repo>/frontend:/web" -w /web node:22-alpine sh -c "npm ci --no-audit --no-fund && npm run build"
cfn-lint infrastructure/cloudformation/*.yaml   (en python:3.13-slim)
```

Informe obligatorio: `docs/informes/2026-11-23_plan-gratuito.md` con cambios, archivos, comandos con resultado real y
límites.
