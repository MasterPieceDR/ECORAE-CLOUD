# Despliegue AWS

## Inicio de cuenta propia

1. Con la cuenta raíz, en la consola de CloudFormation de `us-east-2`, cree primero el stack `ecoraee-prod-iam` desde `08-iam.yaml`, con `Prefijo=ecoraee-prod`, `Entorno=prod` y `Responsable`; acepte la creación de recursos IAM con nombre. Anote las salidas del rol y del inicio de sesión. Si la cuenta nunca usó acciones de alarma de EC2, cree también una vez el rol vinculado al servicio que necesita la alarma de recuperación (el rol de despliegue no puede crearlo): `aws iam create-service-linked-role --aws-service-name events.amazonaws.com`.
   En el plan gratuito de AWS, despliegue `03-datos` con `DiasRespaldo=1` (el plan limita la retención de respaldos). Desde Git Bash en Windows exporte `MSYS_NO_PATHCONV=1` para que `/ecoraee/prod/api` no se convierta en una ruta de Windows.
2. El titular crea en IAM las contraseñas de consola y las claves de acceso necesarias, y las entrega por un canal seguro. La plantilla no crea credenciales ni fuerza MFA; configure MFA y política de contraseñas en la cuenta. No vuelva a usar la raíz para las operaciones ordinarias.
3. Configure AWS CLI v2 con el usuario de infraestructura. El bucket de artefactos debe existir previamente, ser privado y llamarse `ecoraee-prod-artefactos...`. Los nombres del frontend deben comenzar por `ecoraee-prod-frontend`. El usuario de aplicaciones publica el frontend; el DBA migra por túnel. El rol de CloudFormation opera los stacks 01–07 mediante `--role-arn`.

El rol de despliegue tiene acciones amplias solo para los servicios usados por las plantillas; IAM se limita a roles y perfiles cuyo nombre comience por el prefijo y a roles de servicio necesarios. Los recursos de esos servicios no están todos limitados por nombre: use una cuenta dedicada, revise CloudTrail y refine con Access Analyzer. La política de DBA permite los secretos maestros RDS `rds!db-*` de la cuenta y región (RDS asigna ese nombre), además del secreto de servicios del prefijo; revise este alcance en cuentas compartidas. La política administrada de CloudFormation permite operar stacks con un rol de servicio ya asociado; trate InfraAdmins como privilegiado.


Plantillas CloudFormation en JSON (subconjunto válido de YAML). Los ejemplos son Bash y utilizan AWS CLI v2, `jq`, `zip` y credenciales del operador; no guardan credenciales en el repositorio. Verifique cuotas, permisos y región. No se ha desplegado automáticamente. Sustituya identificadores por nombres de bucket globalmente únicos. `parametros/lab.json` es inventario de valores, no un archivo directamente compatible con `--parameter-overrides`.

La EC2 está en una subred pública con IPv4 pública y salida mediante Internet Gateway; `CrearNAT=false` y `CrearEndpoints=false`. El endpoint gateway de S3 se conserva. Solo CloudFront alcanza el puerto 80; no hay SSH. `UsarLabRole=true` exige permisos equivalentes en el perfil existente. La lista administrada de CloudFront ocupa varias entradas de cuota de SG: compruebe que la cuota regional lo permite.

```bash
export AWS_REGION=us-east-2 AWS_DEFAULT_REGION=us-east-2
P=$(jq -r .Prefijo infrastructure/cloudformation/parametros/cuenta-propia.json)
RESPONSABLE=$(jq -r .Responsable infrastructure/cloudformation/parametros/cuenta-propia.json)
FRONT="$P-frontend-REEMPLAZAR-unico"
EVID=REEMPLAZAR-evidencias-unico
CONT=REEMPLAZAR-contenidos-unico
AUDIT=REEMPLAZAR-auditoria-unico
ART="$P-artefactos-REEMPLAZAR-existente"
KEY=ecoraee/codigo.zip
EMAIL=REEMPLAZAR@example.org
LOGS=/ecoraee/prod/api
# Genere un secreto alfanumérico de 16–128 caracteres y manténgalo fuera del repositorio.
read -rs -p "Secreto del origen: " ORIGIN_SECRET; echo
CF_PREFIX=$(aws ec2 describe-managed-prefix-lists --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing --query "PrefixLists[0].PrefixListId" --output text)
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
PART=aws # ajustar en particiones distintas
SVC="arn:$PART:secretsmanager:$AWS_REGION:$ACCOUNT:secret:$P/servicios-*"
JWT="arn:$PART:secretsmanager:$AWS_REGION:$ACCOUNT:secret:$P/jwt-*"
# Convierta el inventario por plantilla: deploy acepta pares Key=Value, no el objeto JSON original.
# Edite previamente Responsable y los valores de cuenta-propia.json; no añada secretos.
PARAMS=infrastructure/cloudformation/parametros/cuenta-propia.json
ROLE_ARN=$(aws cloudformation describe-stacks --stack-name "$P-iam" --query "Stacks[0].Outputs[?OutputKey=='DeployRoleArn'].OutputValue" --output text)
deploy_stack() {
  local stack=$1 template=$2; shift 2
  local -a valores
  mapfile -t valores < <(jq -r --slurpfile t "$template" 'to_entries[] | select(.key as $k | $t[0].Parameters | has($k)) | "\(.key)=\(.value|tostring)"' "$PARAMS")
  aws cloudformation deploy --stack-name "$stack" --template-file "$template" --role-arn "$ROLE_ARN" --capabilities CAPABILITY_IAM --parameter-overrides "${valores[@]}" "$@"
}
# Artefacto privado ya existente, cifrado y versionado. Seleccionar solo código necesario:
zip -qr /tmp/ecoraee-codigo.zip backend/app backend/mcp_server backend/Dockerfile backend/requirements.txt backend/wheels math/ecoraee_flujo.py database infrastructure/scripts -x '*/__pycache__/*' '*.pyc' '*/.env*'
aws s3 cp /tmp/ecoraee-codigo.zip "s3://$ART/$KEY"
rm /tmp/ecoraee-codigo.zip
deploy_stack "$P-red" infrastructure/cloudformation/01-red.yaml
deploy_stack "$P-seguridad" infrastructure/cloudformation/02-seguridad.yaml CorreoEventos="$EMAIL" CloudFrontPrefixListId="$CF_PREFIX" BucketEvidencias="$EVID" BucketContenidos="$CONT" BucketArtefactos="$ART" ClaveArtefacto="$KEY" SecretoServiciosArn="$SVC" SecretoJwtArn="$JWT"
deploy_stack "$P-datos" infrastructure/cloudformation/03-datos.yaml DiasRespaldo=1
# Origen temporal válido; se reemplaza cuando se crea la distribución.
ORIGEN=https://example.invalid
deploy_stack "$P-almacenamiento" infrastructure/cloudformation/04-almacenamiento.yaml BucketFrontend="$FRONT" BucketEvidencias="$EVID" BucketContenidos="$CONT" OrigenWeb="$ORIGEN"
export DB_SECRET_ARN=$(aws cloudformation describe-stacks --stack-name "$P-datos" --query "Stacks[0].Outputs[?OutputKey=='ServiceSecret'].OutputValue" --output text)
export JWT_SECRET_ARN=$(aws cloudformation describe-stacks --stack-name "$P-datos" --query "Stacks[0].Outputs[?OutputKey=='JwtSecret'].OutputValue" --output text)
export MASTER_SECRET_ARN=$(aws cloudformation describe-stacks --stack-name "$P-datos" --query "Stacks[0].Outputs[?OutputKey=='MasterSecret'].OutputValue" --output text)
deploy_stack "$P-computo" infrastructure/cloudformation/05-computo.yaml OriginVerifySecret="$ORIGIN_SECRET" BucketArtefactos="$ART" ClaveArtefacto="$KEY" SecretoServiciosArn="$DB_SECRET_ARN" SecretoJwtArn="$JWT_SECRET_ARN" BucketEvidencias="$EVID" BucketContenidos="$CONT" OrigenWeb="$ORIGEN" GrupoLogs="$LOGS"
DNS_EC2=$(aws cloudformation describe-stacks --stack-name "$P-computo" --query "Stacks[0].Outputs[?OutputKey=='PublicDnsName'].OutputValue" --output text)
deploy_stack "$P-cdn" infrastructure/cloudformation/06-cdn.yaml BucketFrontend="$FRONT" PublicDnsName="$DNS_EC2" OriginVerifySecret="$ORIGIN_SECRET"
DOMAIN=$(aws cloudformation describe-stacks --stack-name "$P-cdn" --query "Stacks[0].Outputs[?OutputKey=='Domain'].OutputValue" --output text)
export DISTRIBUCION_ID=$(aws cloudformation describe-stacks --stack-name "$P-cdn" --query "Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue" --output text)
ORIGEN="https://$DOMAIN"
deploy_stack "$P-almacenamiento" infrastructure/cloudformation/04-almacenamiento.yaml BucketFrontend="$FRONT" BucketEvidencias="$EVID" BucketContenidos="$CONT" OrigenWeb="$ORIGEN"
deploy_stack "$P-computo" infrastructure/cloudformation/05-computo.yaml OriginVerifySecret="$ORIGIN_SECRET" BucketArtefactos="$ART" ClaveArtefacto="$KEY" SecretoServiciosArn="$DB_SECRET_ARN" SecretoJwtArn="$JWT_SECRET_ARN" BucketEvidencias="$EVID" BucketContenidos="$CONT" OrigenWeb="$ORIGEN" GrupoLogs="$LOGS"
# Compruebe el DNS y actualice CDN si cambió. Para aplicar el nuevo OrigenWeb al contenedor,
# reinicie su configuración en la instancia según el procedimiento de actualización de abajo.
DNS_EC2=$(aws cloudformation describe-stacks --stack-name "$P-computo" --query "Stacks[0].Outputs[?OutputKey=='PublicDnsName'].OutputValue" --output text)
deploy_stack "$P-cdn" infrastructure/cloudformation/06-cdn.yaml BucketFrontend="$FRONT" PublicDnsName="$DNS_EC2" OriginVerifySecret="$ORIGIN_SECRET"
deploy_stack "$P-observabilidad" infrastructure/cloudformation/07-observabilidad.yaml BucketAuditoria="$AUDIT" CorreoAlerta="$EMAIL"
# Cambie al perfil del usuario de aplicaciones antes de publicar:
export BUCKET_FRONTEND="$FRONT"
bash infrastructure/scripts/publicar_frontend.sh
```

El parámetro `CloudFrontPrefixListId` identifica la lista administrada de CloudFront en la región (sin valor predeterminado); consúltela con el comando del ejemplo. `OriginVerifySecret` es un parámetro NoEcho compartido por los stacks de cómputo y CDN: proporcione el mismo valor alfanumérico secreto a ambos y protéjalo durante su gestión y rotación.

Para usar Compose manualmente, copie `.env.aws.example` a `.env.aws` y ejecute `docker compose --env-file .env.aws -f docker-compose.aws.yml up -d`; proporcione la CA de RDS confiable a la imagen y configure una secuencia de logs única por instancia. El stack utiliza una EC2, no Compose.

Para Academy cambie `UsarLabRole=true` y, si es necesario, `LabInstanceProfile=...`; la cuenta debe permitir igualmente los servicios y recursos. Cree el bucket de artefactos fuera de estos stacks, con bloqueo público, cifrado y permisos de subida del operador. Configure `aws cloudformation deploy --tags Proyecto=EcoRAEE Entorno=lab Responsable=...` para propagar etiquetas a los recursos que admitan etiquetas heredadas. El bucket de CloudTrail y el resto se conservan al borrar los stacks. La alarma SNS necesita una suscripción por correo confirmada; solicítela con el titular si el usuario de infraestructura no tiene permisos directos de SNS.

## Inicialización de la base

Ejecute `infrastructure/scripts/migrar_base.sh` **una sola vez sobre la base vacía**, desde la PC con el perfil DBA, el túnel de Session Manager descrito abajo, `psql` 16, `jq`, AWS CLI y acceso al repositorio. El rol de ejecución de la API no puede leer el maestro. AWS CLI debe alcanzar Secrets Manager y psql debe alcanzar RDS a través del túnel. Descargue el CA oficial `https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem`, exporte `PGSSLROOTCERT` con su ruta y exporte `MASTER_SECRET_ARN`, `DB_SECRET_ARN` y `AWS_REGION`. La API tendrá fallos de salud hasta que la migración termine. Después de que arranque, ejecute `docker exec ecoraee-api python -m app.cli inicializar` desde Session Manager para calcular los escenarios iniciales. No usar la instancia de producción con el rol de runtime para otorgar el secreto maestro de forma permanente. El script exige los archivos 01–20 del orden vigente. Exporte `ADMIN_CORREO`, `ADMIN_ALIAS` y `ADMIN_CLAVE` (mínimo 16 caracteres) antes de migrar; el script prepara el administrador y bloquea las cuentas sintéticas. Defina `CLAVE_DEMO` solo para habilitarlas expresamente en evaluación. `DEMO=true` es opcional y solo para datos sintéticos. El comando `--datos` restaura un volcado completo desde `DATABASE_LOCAL_URL` sobre una base sin los esquemas de la aplicación; requiere una fuente actualizada hasta 19 y 20. Restaura datos antes de restricciones y triggers, conserva permisos, crea logins y prepara producción. No ejecutar primero la migración de esquema en ese destino. Use PGPASSFILE para las credenciales de origen. Probado localmente con PostgreSQL 16 y un maestro sin superusuario; el túnel y TLS reales siguen pendientes.

Al cambiar el user-data o el ZIP, actualice la clave del ZIP y despliegue seguridad y cómputo. EC2 no vuelve a ejecutar automáticamente cloud-init al actualizar user-data: para aplicar el arranque actualizado, elimine primero observabilidad (importa la instancia y los logs), elimine y recree cómputo, y vuelva a crear observabilidad; conserve y proteja los logs que necesite. Consulte el nuevo `PublicDnsName` y actualice `PublicDnsName` en CDN. Para el segundo despliegue de cómputo con el dominio real, aplique este procedimiento antes de comprobar CORS. La IPv4 y el DNS también pueden cambiar tras detener/iniciar la instancia; actualice CDN si cambia. El secreto de origen se guarda en Secrets Manager y solo su ARN llega al contenedor; el mismo valor se configura en CDN. Para rotarlo, coordine ambos stacks y reinicie o reemplace la instancia: la aplicación lo carga al iniciar. No incluya valores secretos en capturas o historial de comandos. Los secretos de servicio son compuestos: rotar los generadores no actualiza automáticamente el compuesto ni PostgreSQL; coordine ambas contraseñas y reinicie la API.


## Destrucción

Respaldar y autorizar la eliminación de datos antes de vaciar buckets versionados (incluidos delete markers). Borre primero stacks en orden `observabilidad`, `cdn`, `computo`, `almacenamiento`, `datos`, `seguridad`, `red`, y finalmente `iam` (con el titular, después de cerrar sesiones y retirar credenciales de esos usuarios), esperando `aws cloudformation wait stack-delete-complete --stack-name NOMBRE` en cada uno. RDS deja snapshot final por `DeletionPolicy`; S3 y snapshot siguen facturando y se eliminan explícitamente desde consola o CLI después de verificarlos. Borre también el artefacto y su bucket si son exclusivos del laboratorio. CloudFront puede tardar en deshabilitarse. Revise CloudTrail, presupuestos, secretos pendientes de eliminación y recursos retenidos.


### Correo de verificación
Configure `CorreoModo=ses` y el mismo `CorreoRemitente` en las plantillas 02 y 05; verifique esa identidad en SES de la región. El rol de instancia solo permite enviar desde esa identidad. En el sandbox de SES también deben verificarse los destinatarios y se aplican cuotas reducidas; solicite acceso de producción para enviar a destinatarios no verificados. AWS Academy Learner Lab puede restringir SES, IAM y salida de red; confirme los servicios habilitados y use Mailpit local cuando SES no esté disponible. Si se usa LabRole, sus permisos dependen del laboratorio y CloudFormation no puede modificarlos.

### Acceso privado por túnel

Desde la PC, con Session Manager Plugin y credenciales DBA, inicie una sesión de reenvío remoto hacia el endpoint privado de RDS a través de la instancia de aplicación: `aws ssm start-session --target <id-instancia> --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{"host":["<endpoint-rds>"],"portNumber":["5432"],"localPortNumber":["15432"]}'`. Mantenga la sesión abierta. Para que `verify-full` compruebe el nombre real del endpoint, configure `PGHOSTADDR=127.0.0.1` y `PGHOST` con el endpoint DNS real; configure `PGPORT_LOCAL=15432`. Descargue el CA oficial de RDS y configure `PGSSLROOTCERT`. No se ha validado aún este flujo de extremo a extremo en AWS.

### Comprobación de eventos SNS

El stack 02 crea un tema distinto al de alarmas y envía una invitación a `CorreoEventos`; confirme el enlace recibido. Ejecute una transferencia, su recepción y un cierre en la aplicación; compruebe en el correo tipo, número, datos disponibles de objeto/nodos, estado y fecha, y registre el resultado sin datos personales. La suscripción pendiente no entrega mensajes. En Academy, LabRole debe disponer de `sns:Publish` para el tema.
