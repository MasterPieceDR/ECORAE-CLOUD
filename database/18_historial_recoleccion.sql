-- Serie sintética reproducible: tendencia, seno estacional y ruido modular determinista.
CREATE TABLE IF NOT EXISTS ind.historial_recoleccion_semanal (
 semana date NOT NULL, categoria_id smallint NOT NULL REFERENCES cat.categoria_raee(id),
 equipos integer NOT NULL CHECK (equipos >= 0), peso_kg numeric(12,2) NOT NULL CHECK (peso_kg >= 0),
 sintetico boolean NOT NULL DEFAULT true, PRIMARY KEY (semana, categoria_id));
COMMENT ON TABLE ind.historial_recoleccion_semanal IS 'Historial semanal sintético de demostración por categoría de nivel 2.';
COMMENT ON COLUMN ind.historial_recoleccion_semanal.semana IS 'Lunes de la semana.';
COMMENT ON COLUMN ind.historial_recoleccion_semanal.categoria_id IS 'Categoría de nivel 2.';
COMMENT ON COLUMN ind.historial_recoleccion_semanal.equipos IS 'Cantidad de equipos.';
COMMENT ON COLUMN ind.historial_recoleccion_semanal.peso_kg IS 'Peso en kilogramos.';
COMMENT ON COLUMN ind.historial_recoleccion_semanal.sintetico IS 'Indica datos sintéticos.';
DROP TRIGGER IF EXISTS tg_auditoria ON ind.historial_recoleccion_semanal;
CREATE TRIGGER tg_auditoria AFTER INSERT OR UPDATE OR DELETE ON ind.historial_recoleccion_semanal FOR EACH ROW EXECUTE FUNCTION aud.fn_auditar('categoria_id');
DELETE FROM ind.historial_recoleccion_semanal WHERE sintetico;
INSERT INTO ind.historial_recoleccion_semanal (semana, categoria_id, equipos, peso_kg, sintetico)
SELECT date_trunc('week', current_timestamp AT TIME ZONE 'America/Guayaquil')::date - (n * 7), c.id,
       v.equipos, round(v.equipos::numeric * 3.5, 2), true
FROM cat.categoria_raee c CROSS JOIN generate_series(1, 52) n
CROSS JOIN LATERAL (SELECT greatest(0, round(
       CASE c.codigo WHEN 'TIC' THEN 16 WHEN 'PEQ_ELECTRO' THEN 9 WHEN 'COMPONENTE' THEN 5 ELSE 5 END
       + (52-n)*0.025 + 1.5*sin(n*2*pi()/26) + ((n*17+c.id*7)%5)-2))::int AS equipos) v
WHERE c.nivel = 2
ON CONFLICT (semana, categoria_id) DO NOTHING;
GRANT SELECT ON ind.historial_recoleccion_semanal TO ecoraee_lectura;
DROP VIEW IF EXISTS api.v1_serie_recoleccion;
CREATE VIEW api.v1_serie_recoleccion WITH (security_invoker=true) AS
WITH reales AS (
 SELECT date_trunc('week', he.ocurrido_en AT TIME ZONE 'America/Guayaquil')::date AS semana,
        raiz.id AS categoria_id, raiz.codigo AS categoria, raiz.nombre AS categoria_nombre,
        count(*)::integer AS equipos, sum(d.peso_kg)::numeric AS peso_kg
 FROM trz.historial_estado he JOIN cat.estado_trazabilidad e ON e.id=he.estado_destino_id
 JOIN trz.dispositivo d ON d.objeto_id=he.objeto_id JOIN cat.categoria_raee c ON c.id=d.categoria_id
 JOIN cat.categoria_raee raiz ON raiz.ruta @> c.ruta AND raiz.nivel = 2
 WHERE e.codigo='RECIBIDO' AND (he.estado_origen_id IS NULL OR he.estado_origen_id IN
  (SELECT id FROM cat.estado_trazabilidad WHERE codigo IN ('REGISTRADO','EN_RECOLECCION')))
 GROUP BY 1, raiz.id, raiz.codigo, raiz.nombre
)
SELECT h.semana, c.codigo AS categoria, c.nombre AS categoria_nombre, h.equipos, h.peso_kg,
       'RED_HISTORICO'::text AS fuente
FROM ind.historial_recoleccion_semanal h JOIN cat.categoria_raee c ON c.id=h.categoria_id
WHERE h.sintetico AND c.nivel = 2
UNION ALL
SELECT semana, categoria, categoria_nombre, equipos, peso_kg, 'PLATAFORMA'::text FROM reales;
GRANT SELECT ON api.v1_serie_recoleccion TO ecoraee_lectura;
