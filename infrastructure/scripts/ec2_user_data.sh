#!/usr/bin/env bash
# Referencia ejecutable con variables de entorno: el Launch Template incorpora su propia versión.
set -euo pipefail
: "${BUCKET_ARTEFACTOS:?}" "${CLAVE_ARTEFACTO:?}" "${AWS_REGION:?}" "${GRUPO_LOGS:?}"
: "${DB_SECRET_ARN:?}" "${JWT_SECRET_ARN:?}" "${BUCKET_EVIDENCIAS:?}" "${BUCKET_CONTENIDOS:?}" "${CORS_ORIGENES:?}"
dnf install -y docker amazon-cloudwatch-agent awscli unzip
systemctl enable --now docker
mkdir -p /opt/ecoraee
aws s3 cp "s3://$BUCKET_ARTEFACTOS/$CLAVE_ARTEFACTO" /tmp/ecoraee.zip --region "$AWS_REGION"
unzip -q /tmp/ecoraee.zip -d /opt/ecoraee
cd /opt/ecoraee
curl --fail --silent --show-error https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o /opt/ecoraee/rds-ca.pem
docker build -f backend/Dockerfile -t ecoraee-api .
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/ecoraee/infrastructure/scripts/cloudwatch-agent.json
IMDS_TOKEN=$(curl --fail --silent --show-error -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" http://169.254.169.254/latest/api/token)
INSTANCE_ID=$(curl --fail --silent --show-error -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
docker run -d --restart unless-stopped --name ecoraee-api -p 8000:8000 \
  --log-driver awslogs --log-opt "awslogs-region=$AWS_REGION" --log-opt "awslogs-group=$GRUPO_LOGS" --log-opt "awslogs-stream=api-$INSTANCE_ID" \
  -v /opt/ecoraee/rds-ca.pem:/etc/ssl/rds-ca.pem:ro -e SSL_CERT_FILE=/etc/ssl/rds-ca.pem \
  -e ENTORNO=produccion -e DEMO=false -e DB_SSL=true -e AUTH_MODO=local \
  -e DB_SECRET_ARN -e JWT_SECRET_ARN -e AWS_REGION -e ALMACEN_MODO=s3 \
  -e BUCKET_EVIDENCIAS -e BUCKET_CONTENIDOS -e CORS_ORIGENES \
  ecoraee-api uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips='*' --no-access-log
