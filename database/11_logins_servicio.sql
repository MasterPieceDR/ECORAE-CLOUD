-- =====================================================================
-- Script 11: logins de servicio (los usa la API y el servidor MCP)
-- En RDS las contraseñas viven en Secrets Manager; aquí llegan como
-- variables de psql:  psql -v api_pass=... -v mcp_pass=... -f 11_logins_servicio.sql
-- Mínimo privilegio: cada login solo hereda su rol de grupo (script 04).
-- =====================================================================
SET client_min_messages = warning;
SELECT format('CREATE ROLE ecoraee_api_svc LOGIN PASSWORD %L IN ROLE ecoraee_app', :'api_pass')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ecoraee_api_svc') \gexec
SELECT format('CREATE ROLE ecoraee_mcp_svc LOGIN PASSWORD %L IN ROLE ecoraee_mcp', :'mcp_pass')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ecoraee_mcp_svc') \gexec
ALTER ROLE ecoraee_api_svc PASSWORD :'api_pass';
ALTER ROLE ecoraee_mcp_svc PASSWORD :'mcp_pass';
ALTER ROLE ecoraee_api_svc SET statement_timeout = '15s';
ALTER ROLE ecoraee_mcp_svc SET statement_timeout = '10s';
GRANT CONNECT ON DATABASE ecoraee TO ecoraee_api_svc, ecoraee_mcp_svc;
