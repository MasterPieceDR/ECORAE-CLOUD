-- Aplica el script 13 sobre una base que ya existe (por ejemplo la del contenedor), solo si falta.
-- docker compose exec -T db psql -U ecoraee_admin -d ecoraee -v ON_ERROR_STOP=1 -f /database/13_aplicar.sql
SELECT to_regclass('seg.solicitud_rol') IS NULL AS falta \gset
\if :falta
  \echo 'Aplicando 13_mejoras.sql...'
  BEGIN;
  \i /database/13_mejoras.sql
  COMMIT;
\else
  \echo 'La base ya tiene el script 13.'
\endif
