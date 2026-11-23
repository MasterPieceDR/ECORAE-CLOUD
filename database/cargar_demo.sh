#!/bin/bash
# Base completa con datos de demostración: 01–05 + 10 + logins (11) + datos (12)
set -e
export PGHOST=${PGHOST:-/srv/pg} PGUSER=${PGUSER:-postgres}
cd "$(dirname "$0")"
./rebuild.sh
psql -d ecoraee -q -v api_pass="${API_DB_PASS:?falta API_DB_PASS}" -v mcp_pass="${MCP_DB_PASS:?falta MCP_DB_PASS}" -f 11_logins_servicio.sql && echo "ok 11_logins_servicio.sql"
psql -d ecoraee -q -f 12_datos_demo.sql > /dev/null && echo "ok 12_datos_demo.sql"
