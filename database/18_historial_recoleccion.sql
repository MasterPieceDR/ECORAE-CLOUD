-- Serie sintética reproducible: tendencia, seno estacional y ruido modular determinista.
CREATE TABLE IF NOT EXISTS ind.historial_recoleccion_semanal (
 semana date NOT NULL, categoria_id smallint NOT NULL REFERENCES cat.categoria_raee(id),
 equipos integer NOT NULL CHECK (equipos >= 0), peso_kg numeric(12,2) NOT NULL CHECK (peso_kg >= 0),
 sintetico boolean NOT NULL DEFAULT true, PRIMARY KEY (semana, categoria_id));
COMMENT ON TABLE ind.historial_recoleccion_semanal IS 'Historial semanal sintético de demostración por categoría principal.';
COMMENT ON COLUMN ind.historial_recoleccion_semanal.semana IS 'Lunes de la semana.';
COMMENT ON COLUMN ind.historial_recoleccion_semanal.categoria_id IS 'Categoría principal.';
COMMENT ON COLUMN ind.historial_recoleccion_semanal.equipos IS 'Cantidad de equipos.';
COMMENT ON COLUMN ind.historial_recoleccion_semanal.peso_kg IS 'Peso en kilogramos.';
COMMENT ON COLUMN ind.historial_recoleccion_semanal.sintetico IS 'Indica datos sintéticos.';
DROP TRIGGER IF EXISTS tg_auditoria ON ind.historial_recoleccion_semanal;
CREATE TRIGGER tg_auditoria AFTER INSERT OR UPDATE OR DELETE ON ind.historial_recoleccion_semanal FOR EACH ROW EXECUTE FUNCTION aud.fn_auditar('categoria_id');
INSERT INTO ind.historial_recoleccion_semanal
SELECT (date_trunc('week', current_date)::date - (n * 7)), c.id,
       greatest(0, round(20 + (52-n)*0.18 + 4*sin(n*2*pi()/26) + ((n*17+c.id*7)%7)-3))::int,
       greatest(0, round((20 + (52-n)*0.18 + 4*sin(n*2*pi()/26) + ((n*17+c.id*7)%7)-3)::numeric * 3.5, 2)), true
FROM cat.categoria_raee c CROSS JOIN generate_series(1,52) n WHERE c.categoria_padre_id IS NULL
ON CONFLICT (semana, categoria_id) DO NOTHING;
GRANT SELECT ON ind.historial_recoleccion_semanal TO ecoraee_lectura;
CREATE OR REPLACE VIEW api.v1_serie_recoleccion WITH (security_invoker=true) AS
SELECT h.semana, c.codigo AS categoria, c.nombre AS categoria_nombre, h.equipos, h.peso_kg, h.sintetico
FROM ind.historial_recoleccion_semanal h JOIN cat.categoria_raee c ON c.id=h.categoria_id
UNION ALL
SELECT date_trunc('week', he.ocurrido_en AT TIME ZONE 'America/Guayaquil')::date, raiz.codigo, raiz.nombre,
       count(*)::integer, sum(d.peso_kg)::numeric, false
FROM trz.historial_estado he JOIN cat.estado_trazabilidad e ON e.id=he.estado_destino_id
JOIN trz.dispositivo d ON d.objeto_id=he.objeto_id JOIN cat.categoria_raee c ON c.id=d.categoria_id
JOIN cat.categoria_raee raiz ON raiz.ruta @> c.ruta AND raiz.categoria_padre_id IS NULL
WHERE e.codigo='RECIBIDO' AND (he.estado_origen_id IS NULL OR he.estado_origen_id IN
 (SELECT id FROM cat.estado_trazabilidad WHERE codigo IN ('REGISTRADO','EN_RECOLECCION')))
GROUP BY 1, raiz.codigo, raiz.nombre;
GRANT SELECT ON api.v1_serie_recoleccion TO ecoraee_lectura;
