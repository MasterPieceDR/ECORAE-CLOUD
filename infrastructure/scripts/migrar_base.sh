#!/usr/bin/env bash
set -euo pipefail
# Ejecutar desde una estaciÃ³n con acceso privado a RDS (p. ej. Session Manager).
: "${MASTER_SECRET_ARN:?}" "${DB_SECRET_ARN:?}" "${AWS_REGION:?}"
command -v jq >/dev/null
root=$(cd "$(dirname "$0")/../.." && pwd)
master=$(aws secretsmanager get-secret-value --secret-id "$MASTER_SECRET_ARN" --region "$AWS_REGION" --query SecretString --output text)
svc=$(aws secretsmanager get-secret-value --secret-id "$DB_SECRET_ARN" --region "$AWS_REGION" --query SecretString --output text)
export PGHOST=$(jq -r .host <<<"$svc") PGPORT=${PGPORT_LOCAL:-$(jq -r .port <<<"$svc")} PGDATABASE=$(jq -r .dbname <<<"$svc") PGUSER=$(jq -r .username <<<"$master") PGPASSWORD=$(jq -r .password <<<"$master") PGSSLMODE=verify-full
: "${PGSSLROOTCERT:?Indique el CA bundle oficial de RDS}"
export API_PASS=$(jq -r .api.password <<<"$svc") MCP_PASS=$(jq -r .mcp.password <<<"$svc")
unset master svc
 : "${ADMIN_CORREO:?}" "${ADMIN_ALIAS:?}" "${ADMIN_CLAVE:?Debe proporcionar una clave de al menos 16 caracteres}"
cd "$root/database"
if [[ ${1:-} == --datos ]]; then
  : "${DATABASE_LOCAL_URL:?URL local; usar PGPASSFILE para contraseña}"
  # Volcado completo: las restricciones y triggers se crean después de los datos.
  if [[ $(psql -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM pg_namespace WHERE nspname IN ('cat','seg','trz','ops','api')") != 0 ]]; then
    echo 'La base destino debe estar vacía para --datos' >&2; exit 1
  fi
  psql -v ON_ERROR_STOP=1 <<'SQL'
DO $$ DECLARE r text; BEGIN
  FOREACH r IN ARRAY ARRAY['ecoraee_lectura','ecoraee_app','ecoraee_mcp','ecoraee_auditor'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('CREATE ROLE %I NOLOGIN',r); END IF;
  END LOOP;
END $$;
GRANT ecoraee_lectura TO ecoraee_app, ecoraee_mcp, ecoraee_auditor;
SQL
  env -u PGPASSWORD -u PGSSLMODE -u PGHOST -u PGHOSTADDR -u PGPORT -u PGDATABASE -u PGUSER pg_dump --no-owner "$DATABASE_LOCAL_URL" | psql -v ON_ERROR_STOP=1 --single-transaction
  if [[ $(psql -At -c "SELECT to_regprocedure('seg.fn_preparar_produccion(text,text,text,text)') IS NOT NULL AND to_regclass('seg.verificacion_correo') IS NOT NULL") != t ]]; then
    echo 'La fuente debe estar actualizada hasta los scripts 19 y 20' >&2; exit 1
  fi
else
  for f in 01_estructura.sql 02_logica.sql 03_api_mcp.sql 04_seguridad_indices_diccionario.sql 05_semillas.sql 10_integracion.sql 13_mejoras.sql 14_dispositivos.sql 15_verificacion.sql 16_rendimiento.sql 17_catalogo_serie_imagenes.sql 17b_api_catalogo.sql 18_historial_recoleccion.sql 19_produccion.sql 20_verificacion_correo.sql; do
    if [[ -f "$f" ]]; then psql -v ON_ERROR_STOP=1 -f "$f"; else echo "No existe $f; revisar la versión de la base" >&2; exit 1; fi
  done
fi
printf '\\getenv api_pass API_PASS\n\\getenv mcp_pass MCP_PASS\n\\i 11_logins_servicio.sql\n' | psql -v ON_ERROR_STOP=1
if [[ ${DEMO:-false} == true && ${1:-} != --datos ]]; then psql -v ON_ERROR_STOP=1 -f 12_datos_demo.sql; fi
export ADMIN_CORREO ADMIN_ALIAS ADMIN_CLAVE CLAVE_DEMO="${CLAVE_DEMO:-}"
printf "\\getenv correo ADMIN_CORREO\n\\getenv alias ADMIN_ALIAS\n\\getenv clave ADMIN_CLAVE\n\\getenv demo CLAVE_DEMO\nSELECT seg.fn_preparar_produccion(:'correo', :'alias', :'clave', nullif(:'demo',''));\n" | psql -v ON_ERROR_STOP=1
unset PGPASSWORD API_PASS MCP_PASS ADMIN_CLAVE CLAVE_DEMO
