#!/bin/bash
# Recrea la base completa de la plataforma: 01–05 (base final) + 10 (integración) [+ 12 datos demo]
set -e
export PGHOST=${PGHOST:-/srv/pg} PGUSER=${PGUSER:-postgres}
cd "$(dirname "$0")"
./run.sh
psql -d ecoraee -v ON_ERROR_STOP=1 -q -1 -f 10_integracion.sql && echo "ok 10_integracion.sql"
psql -d ecoraee -v ON_ERROR_STOP=1 -q -1 -f 13_mejoras.sql && echo "ok 13_mejoras.sql"
psql -d ecoraee -v ON_ERROR_STOP=1 -q -1 -f 14_dispositivos.sql && echo "ok 14_dispositivos.sql"
psql -d ecoraee -v ON_ERROR_STOP=1 -q -1 -f 15_verificacion.sql && echo "ok 15_verificacion.sql"
psql -d ecoraee -v ON_ERROR_STOP=1 -q -1 -f 16_rendimiento.sql && echo "ok 16_rendimiento.sql"
psql -d ecoraee -v ON_ERROR_STOP=1 -q -1 -f 17_catalogo_serie_imagenes.sql && echo "ok 17_catalogo_serie_imagenes.sql"
psql -d ecoraee -v ON_ERROR_STOP=1 -q -1 -f 17b_api_catalogo.sql && echo "ok 17b_api_catalogo.sql"
psql -d ecoraee -v ON_ERROR_STOP=1 -q -1 -f 18_historial_recoleccion.sql && echo "ok 18_historial_recoleccion.sql"
