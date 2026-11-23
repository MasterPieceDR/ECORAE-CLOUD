-- Consultas para mostrar en el video que lo hecho en la web quedó guardado en PostgreSQL.
-- Se ejecuta con consultar_bd.bat (doble clic) o:  docker compose exec db psql -U ecoraee_admin -d ecoraee -f /database/demo_consultas.sql
\pset border 2
\pset footer off
\echo
\echo '=== 1. Ultimos equipos registrados (tablas trz.objeto_trazable + trz.dispositivo + cat.*) ==='
SELECT o.codigo, e.codigo AS estado, c.nombre AS categoria, d.peso_kg AS kg, coalesce(d.numero_serie, '-') AS serie,
       u.alias AS registrado_por, to_char(o.registrado_en, 'DD/MM HH24:MI') AS cuando
  FROM trz.objeto_trazable o
  JOIN cat.estado_trazabilidad e ON e.id = o.estado_actual_id
  JOIN trz.dispositivo d ON d.objeto_id = o.id
  JOIN cat.categoria_raee c ON c.id = d.categoria_id
  JOIN seg.usuario u ON u.id = o.registrado_por
 ORDER BY o.registrado_en DESC LIMIT 5;
\echo '=== 2. Historial de estados del ultimo equipo tocado (trz.historial_estado, inmutable) ==='
SELECT to_char(h.ocurrido_en, 'DD/MM HH24:MI:SS') AS cuando, o.codigo, coalesce(eo.codigo, '-') AS desde, ed.codigo AS hacia,
       u.alias AS usuario, h.canal, left(coalesce(h.observacion, ''), 40) AS observacion
  FROM trz.historial_estado h
  JOIN trz.objeto_trazable o ON o.id = h.objeto_id
  LEFT JOIN cat.estado_trazabilidad eo ON eo.id = h.estado_origen_id
  JOIN cat.estado_trazabilidad ed ON ed.id = h.estado_destino_id
  JOIN seg.usuario u ON u.id = h.usuario_id
 WHERE h.objeto_id = (SELECT objeto_id FROM trz.historial_estado ORDER BY ocurrido_en DESC, id DESC LIMIT 1)
 ORDER BY h.ocurrido_en, h.id;
\echo '=== 3. Ultimos cambios auditados: que tabla, que operacion, desde que canal (aud.log_cambio) ==='
SELECT to_char(l.ocurrido_en, 'HH24:MI:SS') AS hora, l.esquema || '.' || l.tabla AS tabla,
       CASE l.operacion WHEN 'I' THEN 'INSERT' WHEN 'U' THEN 'UPDATE' ELSE 'DELETE' END AS operacion,
       coalesce(u.alias, l.usuario_bd) AS usuario, l.canal, left(coalesce(array_to_string(l.campos_cambiados, ', '), ''), 45) AS campos
  FROM aud.log_cambio l LEFT JOIN seg.usuario u ON u.id = l.usuario_id
 ORDER BY l.id DESC LIMIT 10;
\echo '=== 4. Integridad: claves foraneas y restricciones definidas en la base ==='
SELECT count(*) FILTER (WHERE contype = 'p') AS claves_primarias, count(*) FILTER (WHERE contype = 'f') AS claves_foraneas,
       count(*) FILTER (WHERE contype = 'c') AS restricciones_check, count(*) FILTER (WHERE contype = 'u') AS unicas,
       count(*) FILTER (WHERE contype = 'x') AS de_exclusion
  FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
 WHERE n.nspname IN ('seg','org','cat','trz','ops','inv','evd','red','ind','gob','mcp','aud','meta','integ','edu')
   AND NOT EXISTS (SELECT 1 FROM pg_class r WHERE r.oid = c.conrelid AND r.relispartition);   -- sin contar particiones
