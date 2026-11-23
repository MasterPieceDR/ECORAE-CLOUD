-- Aplica a una base que ya existe (la del contenedor) solo los scripts que le falten. Se puede repetir sin riesgo.
-- docker compose exec -T db psql -U ecoraee_admin -d ecoraee -v ON_ERROR_STOP=1 -f /database/aplicar_cambios.sql
SELECT to_regclass('seg.solicitud_rol') IS NULL AS falta13,
       to_regprocedure('api.fn_anular_objeto(uuid,text)') IS NULL AS falta14,
       to_regprocedure('api.fn_verificar_base()') IS NULL AS falta15,
       to_regprocedure('seg.fn_cache_valida(bigint)') IS NULL AS falta16 \gset
\if :falta13
  \echo 'Aplicando 13_mejoras.sql (editor de escenarios y solicitudes de rol)...'
  BEGIN;
  \i /database/13_mejoras.sql
  COMMIT;
\endif
\if :falta14
  \echo 'Aplicando 14_dispositivos.sql (actualizar y anular equipos)...'
  BEGIN;
  \i /database/14_dispositivos.sql
  COMMIT;
\endif
\if :falta15
  \echo 'Aplicando 15_verificacion.sql (verificación de la base desde la API)...'
  BEGIN;
  \i /database/15_verificacion.sql
  COMMIT;
\endif
\if :falta16
  \echo 'Aplicando 16_rendimiento.sql (seguridad por fila sin cálculos repetidos)...'
  BEGIN;
  \i /database/16_rendimiento.sql
  COMMIT;
\endif
\echo 'La base está al día.'
