# Despliegue de laboratorio AWS

Plantillas CloudFormation en JSON (subconjunto válido de YAML). Los ejemplos son Bash y utilizan AWS CLI v2, `jq`, `zip` y credenciales del operador; no guardan credenciales en el repositorio. Verifique cuotas, permisos y región. No se ha desplegado automáticamente. Sustituya identificadores por nombres de bucket globalmente únicos. `parametros/lab.json` es inventario de valores, no un archivo directamente compatible con `--parameter-overrides`.

Se necesita NAT para instalar paquetes y descargar el certificado de RDS y dependencias: los endpoints de interfaz opcionales no sustituyen esa salida a internet. Si se desactiva NAT, aporte una AMI y un proceso de arranque con todos los paquetes e imagen precargados; el user-data suministrado no funcionará sin esa adaptación. Un único NAT es un punto de fallo entre AZ. Permita acceso HTTPS de las instancias a los servicios necesarios. `UsarLabRole=true` requiere que el perfil de Academy ya tenga permisos equivalentes; CloudFormation no puede ampliarlos.

```bash
export AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1
P=ecoraee-lab
RESPONSABLE=REEMPLAZAR
FRONT=REEMPLAZAR-frontend-unico
EVID=REEMPLAZAR-evidencias-unico
CONT=REEMPLAZAR-contenidos-unico
AUDIT=REEMPLAZAR-auditoria-unico
ART=REEMPLAZAR-artefactos-existente
KEY=ecoraee/codigo.zip
EMAIL=REEMPLAZAR@example.org
LOGS=/ecoraee/lab/api
# Genere un secreto alfanumérico de 16–128 caracteres y manténgalo fuera del repositorio.
read -rs -p "Secreto del origen: " ORIGIN_SECRET; echo
CF_PREFIX=$(aws ec2 describe-managed-prefix-lists --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing --query "PrefixLists[0].PrefixListId" --output text)
AMI=ami-REEMPLAZAR # Amazon Linux 2023 x86_64 de la región
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
PART=aws # ajustar en particiones distintas
SVC="arn:$PART:secretsmanager:$AWS_REGION:$ACCOUNT:secret:$P/servicios-*"
JWT="arn:$PART:secretsmanager:$AWS_REGION:$ACCOUNT:secret:$P/jwt-*"
BASE="Prefijo=$P Entorno=lab Responsable=$RESPONSABLE"
# Artefacto privado ya existente, cifrado y versionado. Seleccionar solo código necesario:
zip -qr /tmp/ecoraee-codigo.zip backend/app backend/mcp_server backend/Dockerfile backend/requirements.txt backend/wheels math/ecoraee_flujo.py database infrastructure/scripts -x '*/__pycache__/*' '*.pyc' '*/.env*'
aws s3 cp /tmp/ecoraee-codigo.zip "s3://$ART/$KEY"
rm /tmp/ecoraee-codigo.zip
aws cloudformation deploy --stack-name "$P-red" --template-file infrastructure/cloudformation/01-red.yaml --parameter-overrides $BASE CrearNAT=true CrearEndpoints=false
aws cloudformation deploy --stack-name "$P-seguridad" --template-file infrastructure/cloudformation/02-seguridad.yaml --capabilities CAPABILITY_IAM --parameter-overrides $BASE UsarLabRole=false CloudFrontPrefixListId="$CF_PREFIX" BucketEvidencias="$EVID" BucketContenidos="$CONT" BucketArtefactos="$ART" ClaveArtefacto="$KEY" SecretoServiciosArn="$SVC" SecretoJwtArn="$JWT"
aws cloudformation deploy --stack-name "$P-datos" --template-file infrastructure/cloudformation/03-datos.yaml --parameter-overrides $BASE MultiAZ=false
# Origen temporal válido; se reemplaza cuando se crea la distribución.
ORIGEN=https://example.invalid
aws cloudformation deploy --stack-name "$P-almacenamiento" --template-file infrastructure/cloudformation/04-almacenamiento.yaml --parameter-overrides $BASE BucketFrontend="$FRONT" BucketEvidencias="$EVID" BucketContenidos="$CONT" OrigenWeb="$ORIGEN"
export DB_SECRET_ARN=$(aws cloudformation describe-stacks --stack-name "$P-datos" --query "Stacks[0].Outputs[?OutputKey=='ServiceSecret'].OutputValue" --output text)
export JWT_SECRET_ARN=$(aws cloudformation describe-stacks --stack-name "$P-datos" --query "Stacks[0].Outputs[?OutputKey=='JwtSecret'].OutputValue" --output text)
export MASTER_SECRET_ARN=$(aws cloudformation describe-stacks --stack-name "$P-datos" --query "Stacks[0].Outputs[?OutputKey=='MasterSecret'].OutputValue" --output text)
aws cloudformation deploy --stack-name "$P-computo" --template-file infrastructure/cloudformation/05-computo.yaml --parameter-overrides $BASE OriginVerifySecret="$ORIGIN_SECRET" AmiId="$AMI" BucketArtefactos="$ART" ClaveArtefacto="$KEY" SecretoServiciosArn="$DB_SECRET_ARN" SecretoJwtArn="$JWT_SECRET_ARN" BucketEvidencias="$EVID" BucketContenidos="$CONT" OrigenWeb="$ORIGEN" GrupoLogs="$LOGS"
aws cloudformation deploy --stack-name "$P-cdn" --template-file infrastructure/cloudformation/06-cdn.yaml --parameter-overrides $BASE BucketFrontend="$FRONT" OriginVerifySecret="$ORIGIN_SECRET"
DOMAIN=$(aws cloudformation describe-stacks --stack-name "$P-cdn" --query "Stacks[0].Outputs[?OutputKey=='Domain'].OutputValue" --output text)
export DISTRIBUCION_ID=$(aws cloudformation describe-stacks --stack-name "$P-cdn" --query "Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue" --output text)
ORIGEN="https://$DOMAIN"
aws cloudformation deploy --stack-name "$P-almacenamiento" --template-file infrastructure/cloudformation/04-almacenamiento.yaml --parameter-overrides $BASE BucketFrontend="$FRONT" BucketEvidencias="$EVID" BucketContenidos="$CONT" OrigenWeb="$ORIGEN"
aws cloudformation deploy --stack-name "$P-computo" --template-file infrastructure/cloudformation/05-computo.yaml --parameter-overrides $BASE OriginVerifySecret="$ORIGIN_SECRET" AmiId="$AMI" BucketArtefactos="$ART" ClaveArtefacto="$KEY" SecretoServiciosArn="$DB_SECRET_ARN" SecretoJwtArn="$JWT_SECRET_ARN" BucketEvidencias="$EVID" BucketContenidos="$CONT" OrigenWeb="$ORIGEN" GrupoLogs="$LOGS"
aws cloudformation deploy --stack-name "$P-observabilidad" --template-file infrastructure/cloudformation/07-observabilidad.yaml --parameter-overrides $BASE BucketAuditoria="$AUDIT" CorreoAlerta="$EMAIL" PresupuestoUSD=100
export BUCKET_FRONTEND="$FRONT"
bash infrastructure/scripts/publicar_frontend.sh
```

El parámetro `CloudFrontPrefixListId` identifica la lista administrada de CloudFront en la región (por defecto `pl-3b927c52` en us-east-1); consúltela con el comando del ejemplo. `OriginVerifySecret` es un parámetro NoEcho compartido por los stacks de cómputo y CDN: proporcione el mismo valor alfanumérico secreto a ambos y protéjalo durante su gestión y rotación.

Para usar Compose manualmente, copie `.env.aws.example` a `.env.aws` y ejecute `docker compose --env-file .env.aws -f docker-compose.aws.yml up -d`; proporcione la CA de RDS confiable a la imagen y configure una secuencia de logs única por instancia. El stack utiliza el Launch Template, no Compose.

Para Academy cambie `UsarLabRole=true` y, si es necesario, `LabInstanceProfile=...`; la cuenta debe permitir igualmente los servicios y recursos. Cree el bucket de artefactos fuera de estos stacks, con bloqueo público, cifrado y permisos de subida del operador. Configure `aws cloudformation deploy --tags Proyecto=EcoRAEE Entorno=lab Responsable=...` para propagar etiquetas a los recursos que admitan etiquetas heredadas. El bucket de CloudTrail y el resto se conservan al borrar los stacks. La alarma SNS necesita una suscripción confirmada: `aws sns subscribe --topic-arn ARN --protocol email --notification-endpoint CORREO`.

## Inicialización de la base

Ejecute `infrastructure/scripts/migrar_base.sh` **una sola vez sobre la base vacía**, desde una máquina temporal en la subred privada app con el mismo grupo de seguridad de app, Session Manager, `psql` 16, `jq`, AWS CLI, acceso al repositorio y un perfil de migración temporal que pueda leer exclusivamente el secreto maestro y el de servicios. El rol de ejecución de la API no puede leer el maestro. AWS CLI y psql deben tener conectividad a Secrets Manager y RDS. Descargue el CA oficial `https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem`, exporte `PGSSLROOTCERT` con su ruta y exporte `MASTER_SECRET_ARN`, `DB_SECRET_ARN` y `AWS_REGION`. La API tendrá fallos de salud hasta que la migración termine. Después de que arranque, ejecute `docker exec ecoraee-api python -m app.cli inicializar` desde Session Manager para calcular los escenarios iniciales. No usar la instancia de producción con el rol de runtime para otorgar el secreto maestro de forma permanente. El script exige todos los archivos 01–19 del orden vigente. Exporte `ADMIN_CORREO`, `ADMIN_ALIAS` y `ADMIN_CLAVE` (mínimo 16 caracteres) antes de migrar; el script prepara el administrador y bloquea las cuentas sintéticas. Defina `CLAVE_DEMO` solo para habilitarlas expresamente en evaluación. `DEMO=true` es opcional y solo para datos sintéticos. El comando `--datos` hace un `pg_dump --data-only` desde `DATABASE_LOCAL_URL` y requiere esquema compatible y destino apropiado; evita duplicar semillas y pruebe la importación en una base vacía separada.

Al cambiar parámetros del Launch Template o el ZIP, actualice la clave del ZIP, vuelva a desplegar los stacks de seguridad y cómputo y renueve instancias: `aws autoscaling start-instance-refresh --auto-scaling-group-name NOMBRE_ASG`. Los secretos de servicio se materializan en un secreto compuesto: rotar los secretos generadores **no** actualiza automáticamente el compuesto ni las contraseñas de PostgreSQL; coordinar rotación de ambos y reiniciar la API. El JWT es texto plano en Secrets Manager; el secreto compuesto contiene exactamente `host`, `port`, `dbname`, `api` y `mcp`.

## Destrucción

Respaldar y autorizar la eliminación de datos antes de vaciar buckets versionados (incluidos delete markers). Borre primero stacks en orden `observabilidad`, `cdn`, `computo`, `almacenamiento`, `datos`, `seguridad`, `red`, esperando `aws cloudformation wait stack-delete-complete --stack-name NOMBRE` en cada uno. RDS deja snapshot final por `DeletionPolicy`; S3 y snapshot siguen facturando y se eliminan explícitamente desde consola o CLI después de verificarlos. Borre también el artefacto y su bucket si son exclusivos del laboratorio. CloudFront puede tardar en deshabilitarse. Revise CloudTrail, presupuestos, secretos pendientes de eliminación y recursos retenidos.
