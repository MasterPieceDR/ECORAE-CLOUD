#!/bin/bash
# Inicialización de PostgreSQL en Docker (se ejecuta una sola vez, con el volumen vacío).
# Orden: 01–05 base final · 10 integración · 11 logins de servicio · 12 datos de demostración (si DEMO=true)
set -e
cd "${DB_SCRIPTS:-/database}"
for f in 01_estructura.sql 02_logica.sql 03_api_mcp.sql 04_seguridad_indices_diccionario.sql 05_semillas.sql; do
  psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$f"; echo "ok $f"
done
psql -v ON_ERROR_STOP=1 -q -1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f 10_integracion.sql && echo "ok 10_integracion.sql"
psql -v ON_ERROR_STOP=1 -q -1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f 13_mejoras.sql && echo "ok 13_mejoras.sql"
psql -v ON_ERROR_STOP=1 -q -1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f 14_dispositivos.sql && echo "ok 14_dispositivos.sql"
psql -v ON_ERROR_STOP=1 -q -1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f 15_verificacion.sql && echo "ok 15_verificacion.sql"
psql -v ON_ERROR_STOP=1 -q -1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f 16_rendimiento.sql && echo "ok 16_rendimiento.sql"
psql -v ON_ERROR_STOP=1 -q -1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f 17_catalogo_serie_imagenes.sql && echo "ok 17_catalogo_serie_imagenes.sql"
psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v api_pass="$API_DB_PASS" -v mcp_pass="$MCP_DB_PASS" -f 11_logins_servicio.sql && echo "ok 11_logins_servicio.sql"
if [ "${DEMO:-true}" = "true" ]; then
  psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f 12_datos_demo.sql > /dev/null && echo "ok 12_datos_demo.sql"
fi
