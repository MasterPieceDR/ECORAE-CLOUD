#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
set -o noclobber
umask 077
for f in .env.produccion .env.produccion.db .env.produccion.api; do
  if [ -e "$f" ]; then echo "Ya existe $f; no se sobrescribirá." >&2; exit 1; fi
done
secret() { openssl rand -hex 32; }
db=$(secret); api=$(secret); mcp=$(secret); jwt=$(secret); admin=$(secret)
cat > .env.produccion <<EOF
POSTGRES_PASSWORD=$db
API_DB_PASS=$api
MCP_DB_PASS=$mcp
DB_CLAVE_API=$api
DB_CLAVE_MCP=$mcp
JWT_SECRETO=$jwt
ADMIN_CORREO=admin@ecoraee.local
ADMIN_ALIAS=admin.produccion
ADMIN_CLAVE=$admin
CLAVE_DEMO=
EOF
printf 'POSTGRES_PASSWORD=%s\nAPI_DB_PASS=%s\nMCP_DB_PASS=%s\n' "$db" "$api" "$mcp" > .env.produccion.db
printf 'DB_CLAVE_API=%s\nDB_CLAVE_MCP=%s\nJWT_SECRETO=%s\n' "$api" "$mcp" "$jwt" > .env.produccion.api
printf 'Creado .env.produccion; conserve sus secretos.\n'
