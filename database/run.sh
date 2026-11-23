#!/bin/bash
# Recrea la base desde cero (RNF-09). Uso: ./run.sh [con_pruebas]
set -e
export PGHOST=${PGHOST:-/srv/pg} PGUSER=${PGUSER:-postgres}
cd "$(dirname "$0")"
psql -q -c "DROP DATABASE IF EXISTS ecoraee WITH (FORCE)" -c "CREATE DATABASE ecoraee" >/dev/null
for f in 0[1-5]_*.sql; do psql -d ecoraee -v ON_ERROR_STOP=1 -q -f "$f"; echo "ok $f"; done
