-- =====================================================================
-- Script 10: integración con el backend FastAPI y el frontend
--   A. Capacidad de nodos (separación de nodo E_in → E_out del capítulo)
--   B. Red real del capítulo de Matemáticas Discretas (E0–E4)
--   C. Capacitación (esquema edu): contenidos, comentarios y reacciones
--   D. Identidad: autenticación local, autorregistro, Cognito, perfil
--   E. Lecturas para la interfaz: catálogos, dispositivos, lotes,
--      documentos, evidencias, auditoría y administración de roles
--   F. Seguridad, auditoría, diccionario y glosario de lo nuevo
-- Se ejecuta después de 01–05. Las pruebas 06 siguen pasando.
-- =====================================================================
SET client_min_messages = warning;

-- =====================================================================
-- A. CAPACIDAD DE NODOS
-- El capítulo modela la capacidad del laboratorio partiendo el nodo
-- (E_in → E_out). En la base el nodo es uno solo (E1) y su capacidad de
-- procesamiento vive aquí; el módulo matemático lo vuelve a partir.
-- =====================================================================
CREATE TABLE red.capacidad_nodo (                 -- c(v): capacidad de procesamiento de un nodo, con historial
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nodo_id    bigint   NOT NULL REFERENCES red.nodo(id),
  capacidad  cat.d_cantidad NOT NULL,
  unidad_id  smallint NOT NULL REFERENCES cat.unidad_medida(id),
  periodo    varchar(10) NOT NULL CHECK (periodo IN ('DIA','SEMANA','MES')),
  vigencia   tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  fuente     varchar(120) NOT NULL,
  EXCLUDE USING gist (nodo_id WITH =, unidad_id WITH =, vigencia WITH &&)
);

ALTER TABLE red.escenario_nodo
  ADD COLUMN capacidad_ajustada cat.d_cantidad,
  ALTER COLUMN oferta DROP NOT NULL, ALTER COLUMN oferta DROP DEFAULT,
  ALTER COLUMN demanda DROP NOT NULL, ALTER COLUMN demanda DROP DEFAULT;
ALTER TABLE red.escenario_nodo
  ADD CONSTRAINT ck_escenario_nodo_dato CHECK (num_nonnulls(oferta, demanda, capacidad_ajustada) >= 1);

CREATE TABLE red.corte_minimo_nodo (              -- nodos cuya capacidad forma parte de un corte mínimo
  corte_id bigint NOT NULL REFERENCES red.corte_minimo(id) ON DELETE CASCADE,
  nodo_id  bigint NOT NULL REFERENCES red.nodo(id),
  PRIMARY KEY (corte_id, nodo_id)
);

-- Oferta, demanda y capacidad efectivas de un nodo: el escenario hereda de su base (NULL = hereda)
CREATE FUNCTION red.fn_nodo_efectivo(p_escenario bigint, p_nodo bigint)
RETURNS TABLE (oferta numeric, demanda numeric, capacidad numeric) LANGUAGE sql STABLE AS $$
  WITH RECURSIVE cadena AS (
    SELECT e.id, e.escenario_base_id, 0 AS profundidad FROM red.escenario_red e WHERE e.id = p_escenario
    UNION ALL
    SELECT b.id, b.escenario_base_id, c.profundidad + 1 FROM red.escenario_red b JOIN cadena c ON b.id = c.escenario_base_id
  ),
  en AS (SELECT x.*, c.profundidad FROM cadena c JOIN red.escenario_nodo x ON x.escenario_id = c.id AND x.nodo_id = p_nodo),
  esc AS (SELECT * FROM red.escenario_red WHERE id = p_escenario)
  SELECT (SELECT en.oferta  FROM en WHERE en.oferta  IS NOT NULL ORDER BY en.profundidad LIMIT 1),
         (SELECT en.demanda FROM en WHERE en.demanda IS NOT NULL ORDER BY en.profundidad LIMIT 1),
         coalesce((SELECT en.capacidad_ajustada FROM en WHERE en.capacidad_ajustada IS NOT NULL ORDER BY en.profundidad LIMIT 1),
                  (SELECT cn.capacidad FROM red.capacidad_nodo cn, esc
                    WHERE cn.nodo_id = p_nodo AND cn.unidad_id = esc.unidad_id AND cn.periodo = esc.periodo
                      AND cn.vigencia @> esc.fecha_referencia))
$$;

-- Dataset del módulo matemático: ahora incluye la capacidad de los nodos y hereda oferta/demanda
CREATE OR REPLACE FUNCTION api.fn_dataset_flujo(p_escenario text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE e red.escenario_red; v jsonb; v_u bigint := seg.fn_usuario_actual();
BEGIN
  -- el Comité y el auditor analizan escenarios (gobierno); solo quien ejecuta el flujo registra resultados
  IF NOT (seg.fn_tiene_permiso(v_u, 'RED.EJECUTAR_FLUJO') OR seg.fn_tiene_permiso(v_u, 'GOBIERNO.DECIDIR')
          OR seg.fn_tiene_permiso(v_u, 'AUDITORIA.CONSULTAR')) THEN
    PERFORM seg.fn_exigir_permiso(v_u, 'RED.EJECUTAR_FLUJO');
  END IF;
  SELECT * INTO e FROM red.escenario_red WHERE codigo = p_escenario AND ecosistema_id = seg.fn_ecosistema_actual();
  IF NOT FOUND THEN RAISE EXCEPTION 'Escenario % no existe', p_escenario USING ERRCODE = 'EC404'; END IF;
  SELECT jsonb_build_object(
    'escenario', e.codigo,
    'unidad', (SELECT codigo FROM cat.unidad_medida WHERE id = e.unidad_id),
    'periodo', e.periodo,
    'aristas', coalesce((SELECT jsonb_agg(jsonb_build_object('origen', origen, 'destino', destino, 'capacidad', capacidad)
                                 ORDER BY origen, destino) FROM red.fn_dataset_flujo(e.id)), '[]'),
    'fuentes', coalesce((SELECT jsonb_agg(jsonb_build_object('nodo', n.codigo, 'oferta', ne.oferta) ORDER BY n.codigo)
                  FROM red.nodo n JOIN cat.tipo_nodo t ON t.id = n.tipo_nodo_id
                  CROSS JOIN LATERAL red.fn_nodo_efectivo(e.id, n.id) ne
                 WHERE n.ecosistema_id = e.ecosistema_id AND n.activo AND t.es_fuente), '[]'),
    'sumideros', coalesce((SELECT jsonb_agg(jsonb_build_object('nodo', n.codigo, 'demanda', ne.demanda) ORDER BY n.codigo)
                  FROM red.nodo n JOIN cat.tipo_nodo t ON t.id = n.tipo_nodo_id
                  CROSS JOIN LATERAL red.fn_nodo_efectivo(e.id, n.id) ne
                 WHERE n.ecosistema_id = e.ecosistema_id AND n.activo AND t.es_sumidero), '[]'),
    'nodos', coalesce((SELECT jsonb_agg(jsonb_build_object('nodo', n.codigo, 'capacidad', ne.capacidad) ORDER BY n.codigo)
                  FROM red.nodo n CROSS JOIN LATERAL red.fn_nodo_efectivo(e.id, n.id) ne
                 WHERE n.ecosistema_id = e.ecosistema_id AND n.activo AND ne.capacidad IS NOT NULL), '[]')) INTO v;
  RETURN v || jsonb_build_object('hash', encode(digest(v::text, 'sha256'), 'hex'));
END $$;

-- El registro del resultado guarda también los nodos que forman parte de cada corte mínimo
CREATE OR REPLACE FUNCTION api.fn_registrar_resultado_flujo(p_escenario text, p_hash text, p_flujo_maximo numeric, p_flujos jsonb,
                                                 p_cortes jsonb, p_algoritmo text DEFAULT 'EDMONDS_KARP',
                                                 p_version text DEFAULT '1.0', p_iniciado_en timestamptz DEFAULT now())
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); e red.escenario_red; v_ds jsonb := api.fn_dataset_flujo(p_escenario);
        v_ej bigint; c jsonb; v_corte bigint; i int := 0;
BEGIN
  PERFORM seg.fn_exigir_permiso(v_usuario, 'RED.EJECUTAR_FLUJO');
  IF v_ds ->> 'hash' <> p_hash THEN
    RAISE EXCEPTION 'El dataset cambió desde que se leyó (hash distinto): vuelva a ejecutar' USING ERRCODE = 'EC409';
  END IF;
  SELECT * INTO e FROM red.escenario_red WHERE codigo = p_escenario AND ecosistema_id = seg.fn_ecosistema_actual();
  INSERT INTO red.ejecucion_flujo(escenario_id, algoritmo, version_modulo, hash_entrada, flujo_maximo, estado, iniciado_en,
                                  finalizado_en, ejecutado_por, canal)
  VALUES (e.id, p_algoritmo, p_version, p_hash, p_flujo_maximo, 'OK', p_iniciado_en, clock_timestamp(), v_usuario,
          coalesce(nullif(current_setting('app.canal', true), ''), 'WEB'))
  RETURNING id INTO v_ej;
  INSERT INTO red.resultado_flujo_arista(ejecucion_id, arista_id, capacidad, flujo)
  SELECT v_ej, ds.arista_id, ds.capacidad, coalesce((f ->> 'flujo')::numeric, 0)
    FROM red.fn_dataset_flujo(e.id) ds
    LEFT JOIN jsonb_array_elements(p_flujos) f ON f ->> 'origen' = ds.origen AND f ->> 'destino' = ds.destino;
  IF abs((SELECT coalesce(sum(r.flujo), 0) FROM red.resultado_flujo_arista r JOIN red.arista a ON a.id = r.arista_id
           JOIN red.nodo n ON n.id = a.nodo_origen_id JOIN cat.tipo_nodo t ON t.id = n.tipo_nodo_id
          WHERE r.ejecucion_id = v_ej AND t.es_fuente) - p_flujo_maximo) > 0.001 THEN
    RAISE EXCEPTION 'Conservación: el flujo que sale de las fuentes no coincide con el flujo máximo reportado' USING ERRCODE = 'EC422';
  END IF;
  FOR c IN SELECT * FROM jsonb_array_elements(p_cortes) LOOP
    i := i + 1;
    INSERT INTO red.corte_minimo(ejecucion_id, numero_corte, capacidad_corte, lado_fuente)
    VALUES (v_ej, i, (c ->> 'capacidad')::numeric, ARRAY(SELECT jsonb_array_elements_text(c -> 'lado_fuente')))
    RETURNING id INTO v_corte;
    INSERT INTO red.corte_minimo_arista(corte_id, arista_id)
    SELECT v_corte, a.id FROM jsonb_array_elements(coalesce(c -> 'aristas', '[]')) par
      JOIN red.nodo no ON no.codigo = par ->> 0 AND no.ecosistema_id = e.ecosistema_id
      JOIN red.nodo nd ON nd.codigo = par ->> 1 AND nd.ecosistema_id = e.ecosistema_id
      JOIN red.arista a ON a.nodo_origen_id = no.id AND a.nodo_destino_id = nd.id;
    INSERT INTO red.corte_minimo_nodo(corte_id, nodo_id)
    SELECT v_corte, n.id FROM jsonb_array_elements_text(coalesce(c -> 'nodos', '[]')) x
      JOIN red.nodo n ON n.codigo = x AND n.ecosistema_id = e.ecosistema_id;
  END LOOP;
  INSERT INTO integ.outbox_evento(ecosistema_id, agregado, agregado_id, tipo_evento, payload)
  VALUES (e.ecosistema_id, 'EJECUCION_FLUJO', v_ej, 'red.flujo_calculado',
          jsonb_build_object('escenario', e.codigo, 'flujo_maximo', p_flujo_maximo, 'cortes', i));
  RETURN v_ej;
END $$;

CREATE OR REPLACE VIEW api.v1_corte_minimo WITH (security_invoker = true) AS
SELECT e.codigo AS escenario, c.ejecucion_id, c.numero_corte, c.capacidad_corte, c.lado_fuente,
       (SELECT string_agg(no.codigo || '→' || nd.codigo, ', ' ORDER BY no.codigo, nd.codigo)
          FROM red.corte_minimo_arista ca JOIN red.arista a ON a.id = ca.arista_id
          JOIN red.nodo no ON no.id = a.nodo_origen_id JOIN red.nodo nd ON nd.id = a.nodo_destino_id
         WHERE ca.corte_id = c.id) AS aristas_corte,
       (SELECT string_agg(n.codigo, ', ' ORDER BY n.codigo) FROM red.corte_minimo_nodo cn JOIN red.nodo n ON n.id = cn.nodo_id
         WHERE cn.corte_id = c.id) AS nodos_corte
  FROM red.corte_minimo c
  JOIN red.ejecucion_flujo j ON j.id = c.ejecucion_id
  JOIN red.escenario_red e ON e.id = j.escenario_id;

-- =====================================================================
-- B. RED REAL DEL CAPÍTULO DE MATEMÁTICAS DISCRETAS (equipos por semana)
-- Sustituye las capacidades de demostración cerrando su vigencia: la
-- historia queda y las capacidades nuevas rigen desde ahora.
-- =====================================================================
-- La entrega directa de grandes generadores al laboratorio (arista G3→E_in del capítulo)
-- es coherente con T (REGISTRADO→RECIBIDO en cualquier centro) y se gobierna como dato.
INSERT INTO cat.arista_tipo_permitida(tipo_nodo_origen_id, tipo_nodo_destino_id, requiere_excepcion, justificacion)
SELECT o.id, d.id, false, 'Entrega directa de grandes generadores al laboratorio (arista G3→E_in del capítulo; ADR-010)' FROM cat.tipo_nodo o, cat.tipo_nodo d WHERE o.codigo = 'GENERADOR' AND d.codigo = 'EVALUACION';

INSERT INTO gob.decision_arquitectura(codigo, titulo, contexto, decision, consecuencias, materias, estado) VALUES
 ('ADR-010', 'Red de la base alineada con el capítulo de Matemáticas Discretas',
  'La base tenía capacidades de demostración; el capítulo fija G=(V,E,c), cinco escenarios y la capacidad del laboratorio como nodo partido E_in→E_out.',
  'Cargar las capacidades del capítulo con vigencia, guardar la capacidad del laboratorio en red.capacidad_nodo, habilitar GENERADOR→EVALUACION (entrega directa) y desactivar E1→B1 y K1→D1, que el capítulo no contempla.',
  'El frontend, el backend y el capítulo usan la misma red; el módulo de flujo parte el nodo y reporta todos los cortes mínimos (E1 tiene 3, E3 tiene 2).',
  '{MD,BD,AE}', 'APROBADA'),
 ('ADR-011', 'Capacitación como módulo de la plataforma',
  'Innovación identificó brechas de alfabetización digital (RNF-07) entre generadores y beneficiarios.',
  'Agregar el esquema edu con contenidos, comentarios y reacciones, con auditoría, RLS por ecosistema y moderación por el administrador.',
  'Los videos dejan de ser un módulo aislado y quedan gobernados como cualquier otro dato.',
  '{INN,BD,NUBE}', 'APROBADA');

DO $$
DECLARE v_eco bigint := (SELECT id FROM seg.ecosistema ORDER BY id LIMIT 1);
        v_und smallint := cat.fn_id('unidad_medida', 'UND');
        v_coord bigint := (SELECT id FROM seg.usuario WHERE alias = 'coordinador');
        v_fuente text := 'Capítulo MD, sección 5 (equipos/semana)';
        r record;
BEGIN
  -- aristas nuevas del capítulo
  INSERT INTO red.arista(ecosistema_id, nodo_origen_id, nodo_destino_id)
  SELECT v_eco, no.id, nd.id FROM (VALUES ('G1','C2'), ('G3','E1')) v(o, d)
    JOIN red.nodo no ON no.codigo = v.o AND no.ecosistema_id = v_eco
    JOIN red.nodo nd ON nd.codigo = v.d AND nd.ecosistema_id = v_eco
   WHERE NOT EXISTS (SELECT 1 FROM red.arista a WHERE a.nodo_origen_id = no.id AND a.nodo_destino_id = nd.id);
  -- aristas que el capítulo no contempla
  UPDATE red.arista a SET activa = false
    FROM red.nodo no, red.nodo nd
   WHERE no.id = a.nodo_origen_id AND nd.id = a.nodo_destino_id AND a.ecosistema_id = v_eco
     AND (no.codigo, nd.codigo) IN (('E1','B1'), ('K1','D1'));
  -- cierre de la vigencia de las capacidades de demostración (UND)
  UPDATE red.capacidad_arista ca SET vigencia = tstzrange(lower(ca.vigencia), now())
    FROM red.arista a WHERE a.id = ca.arista_id AND a.ecosistema_id = v_eco AND ca.unidad_id = v_und AND upper_inf(ca.vigencia);
  INSERT INTO red.capacidad_arista(arista_id, capacidad, unidad_id, periodo, vigencia, fuente)
  SELECT a.id, v.c, v_und, 'SEMANA', tstzrange(now(), NULL), v_fuente
    FROM (VALUES ('G1','C1',80), ('G1','C2',50), ('G2','C1',70), ('G2','C2',90), ('G3','C2',60), ('G3','E1',40),
                 ('C1','E1',110), ('C2','E1',90), ('C2','K1',40), ('E1','R1',70), ('E1','K1',90), ('E1','D1',25),
                 ('R1','B1',60), ('R1','K1',15)) v(o, d, c)
    JOIN red.nodo no ON no.codigo = v.o AND no.ecosistema_id = v_eco
    JOIN red.nodo nd ON nd.codigo = v.d AND nd.ecosistema_id = v_eco
    JOIN red.arista a ON a.nodo_origen_id = no.id AND a.nodo_destino_id = nd.id;
  -- capacidad del laboratorio: arista E_in→E_out del capítulo
  INSERT INTO red.capacidad_nodo(nodo_id, capacidad, unidad_id, periodo, fuente)
  SELECT id, 160, v_und, 'SEMANA', v_fuente FROM red.nodo WHERE codigo = 'E1' AND ecosistema_id = v_eco;

  -- escenarios del capítulo (tabla 7.2): todos derivan de la línea base
  DELETE FROM red.escenario_arista WHERE escenario_id IN (SELECT id FROM red.escenario_red WHERE ecosistema_id = v_eco);
  DELETE FROM red.escenario_nodo   WHERE escenario_id IN (SELECT id FROM red.escenario_red WHERE ecosistema_id = v_eco);
  UPDATE red.escenario_red SET escenario_base_id = NULL WHERE ecosistema_id = v_eco;
  FOR r IN SELECT * FROM (VALUES
      ('E0','Línea base','¿Cuánto procesa hoy la red? La evaluación técnica y la ruta directa de chatarra limitan la red: se procesa el 54 % de lo generado.'),
      ('E1','Segundo turno de evaluación','¿Basta con ampliar el cuello de botella? +70 de capacidad en el laboratorio dan solo +25 de flujo: el límite pasa a las rutas de clasificación y a los destinos finales (tres cortes mínimos).'),
      ('E2','Campaña de recolección','¿Qué pasa si se recolecta más sin ampliar el procesamiento? El flujo sigue en 200: los equipos adicionales se acumulan en los acopios.'),
      ('E3','Mantenimiento del reciclador','¿Qué tan sensible es la red a una falla aguas abajo? El límite ya no es evaluar sino tener a dónde enviar lo evaluado (dos cortes mínimos).'),
      ('E4','Ampliación integral','¿Cuánto mejora una inversión coordinada? El flujo sube a 280 (76 %) y el cuello de botella pasa al transporte hacia evaluación.')) v(c, n, d)
  LOOP
    IF EXISTS (SELECT 1 FROM red.escenario_red WHERE codigo = r.c AND ecosistema_id = v_eco) THEN
      UPDATE red.escenario_red SET nombre = r.n, descripcion = r.d, fecha_referencia = now(), estado = 'APROBADO'
       WHERE codigo = r.c AND ecosistema_id = v_eco;
    ELSE
      INSERT INTO red.escenario_red(ecosistema_id, codigo, nombre, descripcion, unidad_id, periodo, estado, creado_por, fecha_referencia)
      VALUES (v_eco, r.c, r.n, r.d, v_und, 'SEMANA', 'APROBADO', v_coord, now());
    END IF;
  END LOOP;
  UPDATE red.escenario_red SET escenario_base_id = (SELECT id FROM red.escenario_red WHERE codigo = 'E0' AND ecosistema_id = v_eco)
   WHERE ecosistema_id = v_eco AND codigo <> 'E0';

  -- E0: oferta de generadores (s→G) y demanda de destinos (X→t)
  INSERT INTO red.escenario_nodo(escenario_id, nodo_id, oferta, demanda, capacidad_ajustada)
  SELECT e.id, n.id, v.oferta, v.demanda, v.cap
    FROM (VALUES ('E0','G1',120,NULL,NULL), ('E0','G2',150,NULL,NULL), ('E0','G3',100,NULL,NULL),
                 ('E0','B1',NULL,60,NULL), ('E0','K1',NULL,140,NULL), ('E0','D1',NULL,30,NULL),
                 ('E1','E1',NULL,NULL,230),
                 ('E2','G1',156,NULL,NULL), ('E2','G2',195,NULL,NULL), ('E2','G3',130,NULL,NULL),
                 ('E3','K1',NULL,90,NULL),
                 ('E4','E1',NULL,NULL,260), ('E4','B1',NULL,80,NULL), ('E4','K1',NULL,180,NULL)
         ) v(esc, nodo, oferta, demanda, cap)
    JOIN red.escenario_red e ON e.codigo = v.esc AND e.ecosistema_id = v_eco
    JOIN red.nodo n ON n.codigo = v.nodo AND n.ecosistema_id = v_eco;
  INSERT INTO red.escenario_arista(escenario_id, arista_id, capacidad_ajustada, motivo)
  SELECT e.id, a.id, v.c, v.m
    FROM (VALUES ('E4','E1','R1',90,'Ampliación del taller'), ('E4','E1','K1',130,'Segundo gestor de reciclaje'),
                 ('E4','R1','B1',80,'Más convenios con escuelas')) v(esc, o, d, c, m)
    JOIN red.escenario_red e ON e.codigo = v.esc AND e.ecosistema_id = v_eco
    JOIN red.nodo no ON no.codigo = v.o AND no.ecosistema_id = v_eco
    JOIN red.nodo nd ON nd.codigo = v.d AND nd.ecosistema_id = v_eco
    JOIN red.arista a ON a.nodo_origen_id = no.id AND a.nodo_destino_id = nd.id;
END $$;

-- Marcas usadas por la red de demostración
INSERT INTO cat.marca(codigo, nombre) VALUES ('TP-LINK', 'TP-Link'), ('HUAWEI', 'Huawei'), ('XIAOMI', 'Xiaomi')
ON CONFLICT DO NOTHING;

-- =====================================================================
-- C. CAPACITACIÓN (esquema edu) — ADR-011
-- =====================================================================
CREATE SCHEMA edu;

CREATE TABLE edu.contenido (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  uid            uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  ecosistema_id  bigint NOT NULL REFERENCES seg.ecosistema(id),
  titulo         varchar(160) NOT NULL CHECK (length(btrim(titulo)) >= 3),
  descripcion    text,
  tema           varchar(20) NOT NULL CHECK (tema IN ('CONCEPTOS','RECICLAJE','REPARACION','COMUNIDAD','SEGURIDAD_DATOS')),
  s3_bucket      varchar(63),
  s3_clave       varchar(512),
  mime           varchar(80) CHECK (mime IN ('video/mp4','video/webm','video/quicktime','video/x-msvideo')),
  tamano_bytes   bigint CHECK (tamano_bytes > 0 AND tamano_bytes <= 524288000),
  duracion_seg   integer CHECK (duracion_seg >= 0),
  estado         varchar(10) NOT NULL DEFAULT 'PUBLICADO' CHECK (estado IN ('PUBLICADO','OCULTO')),
  publicado_por  bigint NOT NULL REFERENCES seg.usuario(id),
  publicado_en   timestamptz NOT NULL DEFAULT now(),
  tiene_archivo  boolean GENERATED ALWAYS AS (s3_clave IS NOT NULL) STORED,   -- legible sin exponer la clave S3
  CHECK (num_nulls(s3_bucket, s3_clave, mime, tamano_bytes) IN (0, 4))
);

CREATE TABLE edu.comentario (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  uid          uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  contenido_id bigint NOT NULL REFERENCES edu.contenido(id),
  usuario_id   bigint NOT NULL REFERENCES seg.usuario(id),
  texto        varchar(1000) NOT NULL CHECK (length(btrim(texto)) >= 1),
  creado_en    timestamptz NOT NULL DEFAULT now(),
  oculto       boolean NOT NULL DEFAULT false
);

CREATE TABLE edu.reaccion (
  contenido_id bigint NOT NULL REFERENCES edu.contenido(id),
  usuario_id   bigint NOT NULL REFERENCES seg.usuario(id),
  creado_en    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (contenido_id, usuario_id)
);

CREATE TABLE edu.visualizacion (                  -- solo inserción: no se audita fila a fila (como acceso_evidencia)
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  contenido_id bigint NOT NULL REFERENCES edu.contenido(id),
  usuario_id   bigint NOT NULL REFERENCES seg.usuario(id),
  visto_en     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_contenido_eco_fecha ON edu.contenido (ecosistema_id, publicado_en DESC);
CREATE INDEX ix_comentario_contenido ON edu.comentario (contenido_id, creado_en DESC);
CREATE INDEX ix_visualizacion_contenido ON edu.visualizacion (contenido_id);
CREATE TRIGGER tg_inmutable BEFORE UPDATE OR DELETE ON edu.visualizacion FOR EACH ROW EXECUTE FUNCTION util.fn_inmutable();

INSERT INTO seg.permiso(codigo, recurso, accion, descripcion) VALUES
 ('CONTENIDO.PUBLICAR', 'contenido', 'publicar', 'Publicar contenidos de capacitación'),
 ('CONTENIDO.MODERAR', 'contenido', 'moderar', 'Ocultar o restaurar contenidos y comentarios');
INSERT INTO seg.rol_permiso(rol_id, permiso_id)
SELECT r.id, p.id FROM (VALUES ('USUARIO_BASE','CONTENIDO.PUBLICAR'), ('ADMINISTRADOR','CONTENIDO.MODERAR')) v(r, p)
  JOIN seg.rol r ON r.codigo = v.r JOIN seg.permiso p ON p.codigo = v.p;

CREATE FUNCTION edu.fn_puede_moderar() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT seg.fn_tiene_permiso(nullif(current_setting('app.usuario_id', true), '')::bigint, 'CONTENIDO.MODERAR')
$$;

CREATE FUNCTION edu.fn_contenido(p_uid uuid) RETURNS edu.contenido LANGUAGE plpgsql STABLE AS $$
DECLARE c edu.contenido;
BEGIN
  SELECT * INTO c FROM edu.contenido WHERE uid = p_uid AND ecosistema_id = seg.fn_ecosistema_actual()
     AND (estado = 'PUBLICADO' OR publicado_por = seg.fn_usuario_actual() OR edu.fn_puede_moderar());
  IF NOT FOUND THEN RAISE EXCEPTION 'Contenido no encontrado' USING ERRCODE = 'EC404'; END IF;
  RETURN c;
END $$;

CREATE FUNCTION api.fn_publicar_contenido(p_titulo text, p_descripcion text, p_tema text, p_bucket text DEFAULT NULL,
                                          p_clave text DEFAULT NULL, p_mime text DEFAULT NULL, p_tamano bigint DEFAULT NULL,
                                          p_duracion integer DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); v_uid uuid;
BEGIN
  PERFORM seg.fn_exigir_permiso(v_usuario, 'CONTENIDO.PUBLICAR');
  INSERT INTO edu.contenido(ecosistema_id, titulo, descripcion, tema, s3_bucket, s3_clave, mime, tamano_bytes, duracion_seg, publicado_por)
  VALUES (seg.fn_ecosistema_actual(), btrim(p_titulo), nullif(btrim(p_descripcion), ''), p_tema, p_bucket, p_clave, p_mime,
          p_tamano, p_duracion, v_usuario)
  RETURNING uid INTO v_uid;
  RETURN v_uid;
END $$;

CREATE FUNCTION api.fn_comentar(p_contenido uuid, p_texto text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE c edu.contenido := edu.fn_contenido(p_contenido); v_uid uuid;
BEGIN
  INSERT INTO edu.comentario(contenido_id, usuario_id, texto) VALUES (c.id, seg.fn_usuario_actual(), btrim(p_texto))
  RETURNING uid INTO v_uid;
  RETURN v_uid;
END $$;

CREATE FUNCTION api.fn_reaccionar(p_contenido uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE c edu.contenido := edu.fn_contenido(p_contenido); v_usuario bigint := seg.fn_usuario_actual(); v_on boolean;
BEGIN
  DELETE FROM edu.reaccion WHERE contenido_id = c.id AND usuario_id = v_usuario;
  IF NOT FOUND THEN
    INSERT INTO edu.reaccion(contenido_id, usuario_id) VALUES (c.id, v_usuario);
    v_on := true;
  ELSE
    v_on := false;
  END IF;
  RETURN jsonb_build_object('me_gusta_yo', v_on, 'me_gusta', (SELECT count(*) FROM edu.reaccion WHERE contenido_id = c.id));
END $$;

CREATE FUNCTION api.fn_registrar_vista(p_contenido uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE c edu.contenido := edu.fn_contenido(p_contenido);
BEGIN
  INSERT INTO edu.visualizacion(contenido_id, usuario_id) VALUES (c.id, seg.fn_usuario_actual());
END $$;

CREATE FUNCTION api.fn_media_contenido(p_contenido uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE c edu.contenido := edu.fn_contenido(p_contenido);
BEGIN
  IF c.s3_clave IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('bucket', c.s3_bucket, 'clave', c.s3_clave, 'mime', c.mime, 'ttl_segundos', 900);
END $$;

CREATE FUNCTION api.fn_moderar_contenido(p_contenido uuid, p_estado text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  PERFORM seg.fn_exigir_permiso(seg.fn_usuario_actual(), 'CONTENIDO.MODERAR');
  UPDATE edu.contenido SET estado = p_estado WHERE uid = p_contenido AND ecosistema_id = seg.fn_ecosistema_actual();
  IF NOT FOUND THEN RAISE EXCEPTION 'Contenido no encontrado' USING ERRCODE = 'EC404'; END IF;
END $$;

CREATE VIEW api.v1_contenido WITH (security_invoker = true) AS
SELECT c.uid, c.titulo, c.descripcion, c.tema, c.mime, c.tamano_bytes, c.duracion_seg, c.estado,
       u.alias AS autor, o.nombre AS organizacion_autor, c.publicado_en, c.tiene_archivo,
       (SELECT count(*) FROM edu.visualizacion v WHERE v.contenido_id = c.id) AS vistas,
       (SELECT count(*) FROM edu.reaccion r WHERE r.contenido_id = c.id) AS me_gusta,
       (SELECT count(*) FROM edu.comentario k WHERE k.contenido_id = c.id AND NOT k.oculto) AS comentarios,
       EXISTS (SELECT 1 FROM edu.reaccion r WHERE r.contenido_id = c.id AND r.usuario_id = seg.fn_usuario_actual()) AS me_gusta_yo,
       c.publicado_por = seg.fn_usuario_actual() AS es_mio,
       c.ecosistema_id
  FROM edu.contenido c
  JOIN seg.usuario u ON u.id = c.publicado_por
  JOIN org.organizacion o ON o.id = u.organizacion_id;

CREATE VIEW api.v1_comentario WITH (security_invoker = true) AS
SELECT k.uid, c.uid AS contenido_uid, c.titulo AS contenido_titulo, u.alias AS autor, k.texto, k.creado_en,
       k.usuario_id = seg.fn_usuario_actual() AS es_mio
  FROM edu.comentario k
  JOIN edu.contenido c ON c.id = k.contenido_id
  JOIN seg.usuario u ON u.id = k.usuario_id
 WHERE NOT k.oculto;

-- =====================================================================
-- D. IDENTIDAD: autenticación local (MVP), Cognito, autorregistro y perfil
-- =====================================================================
-- Autenticación local: la API nunca lee el hash; la base compara con crypt() (bcrypt)
CREATE FUNCTION api.fn_autenticar_local(p_correo text, p_password text, p_ip_hash text DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE u seg.usuario;
BEGIN
  SELECT * INTO u FROM seg.usuario
   WHERE lower(correo) = lower(btrim(p_correo)) AND proveedor_identidad = 'LOCAL' AND eliminado_en IS NULL
   ORDER BY id LIMIT 1;
  IF NOT FOUND OR u.estado <> 'ACTIVO' OR u.hash_credencial IS NULL OR crypt(p_password, u.hash_credencial) <> u.hash_credencial THEN
    INSERT INTO aud.evento_seguridad(tipo, usuario_id, detalle, ip_hash)
    VALUES ('LOGIN_FALLIDO', u.id, jsonb_build_object('motivo', CASE WHEN u.id IS NULL THEN 'correo desconocido' ELSE 'credencial inválida' END),
            p_ip_hash);
    RETURN NULL;
  END IF;
  UPDATE seg.usuario SET ultimo_acceso_en = now() WHERE id = u.id;
  INSERT INTO aud.evento_seguridad(tipo, usuario_id, detalle, ip_hash) VALUES ('LOGIN_OK', u.id, '{"proveedor":"LOCAL"}', p_ip_hash);
  RETURN u.uid;
END $$;

-- Cognito: el sub del token se resuelve a un usuario de la base
CREATE FUNCTION api.fn_resolver_identidad(p_proveedor text, p_sub text) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT uid FROM seg.usuario WHERE proveedor_identidad = p_proveedor AND sub_externo = p_sub
     AND estado = 'ACTIVO' AND eliminado_en IS NULL
$$;

-- Autorregistro: cuenta con el rol raíz USUARIO_BASE; el administrador asigna los demás roles (7.6)
CREATE FUNCTION api.fn_registrar_cuenta(p_alias text, p_correo text, p_password text, p_organizacion text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE o org.organizacion; v_id bigint; v_uid uuid;
BEGIN
  IF length(coalesce(p_password, '')) < 10 THEN
    RAISE EXCEPTION 'La contraseña necesita al menos 10 caracteres' USING ERRCODE = 'EC422';
  END IF;
  IF p_alias !~ '^[a-z0-9][a-z0-9._-]{2,40}$' THEN
    RAISE EXCEPTION 'El alias usa de 3 a 40 letras minúsculas, números, punto o guion' USING ERRCODE = 'EC422';
  END IF;
  IF p_correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'Correo electrónico inválido' USING ERRCODE = 'EC422';
  END IF;
  SELECT * INTO o FROM org.organizacion WHERE codigo = p_organizacion AND estado = 'ACTIVA' AND eliminado_en IS NULL
   ORDER BY ecosistema_id LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Organización % no existe', p_organizacion USING ERRCODE = 'EC404'; END IF;
  IF EXISTS (SELECT 1 FROM seg.usuario WHERE ecosistema_id = o.ecosistema_id AND (lower(correo) = lower(p_correo) OR alias = p_alias)) THEN
    RAISE EXCEPTION 'Ya existe una cuenta con ese correo o alias' USING ERRCODE = 'EC409';
  END IF;
  INSERT INTO seg.usuario(ecosistema_id, organizacion_id, alias, correo, proveedor_identidad, hash_credencial)
  VALUES (o.ecosistema_id, o.id, p_alias, lower(p_correo), 'LOCAL', crypt(p_password, gen_salt('bf', 10)))
  RETURNING id, uid INTO v_id, v_uid;
  INSERT INTO seg.usuario_rol(usuario_id, rol_id, motivo)
  SELECT v_id, id, 'Autorregistro: rol base hasta que el administrador asigne funciones' FROM seg.rol WHERE codigo = 'USUARIO_BASE';
  RETURN v_uid;
END $$;

-- Organizaciones que pueden elegirse al registrarse (sin datos sensibles)
CREATE FUNCTION api.fn_organizaciones_publicas() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) ORDER BY nombre), '[]')
    FROM org.organizacion
   WHERE estado = 'ACTIVA' AND eliminado_en IS NULL AND ecosistema_id = (SELECT id FROM seg.ecosistema ORDER BY id LIMIT 1)
$$;

-- Perfil del usuario del contexto: roles con su alcance y permisos efectivos (con herencia)
CREATE FUNCTION api.fn_perfil() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  WITH RECURSIVE u AS (SELECT * FROM seg.usuario WHERE id = seg.fn_usuario_actual()),
  asig AS (SELECT ur.rol_id, ur.centro_id FROM seg.usuario_rol ur, u WHERE ur.usuario_id = u.id AND ur.vigencia @> now()),
  arbol AS (
    SELECT r.id, r.rol_padre_id, a.centro_id FROM seg.rol r JOIN asig a ON a.rol_id = r.id WHERE r.activo
    UNION
    SELECT p.id, p.rol_padre_id, h.centro_id FROM seg.rol p JOIN arbol h ON h.rol_padre_id = p.id WHERE p.activo)
  SELECT jsonb_build_object(
    'uid', u.uid, 'alias', u.alias, 'ecosistema', u.ecosistema_id, 'mfa', u.mfa_habilitado,
    'proveedor', u.proveedor_identidad, 'desde', u.creado_en,
    'organizacion', (SELECT jsonb_build_object('uid', o.uid, 'codigo', o.codigo, 'nombre', o.nombre, 'sector', o.sector)
                       FROM org.organizacion o WHERE o.id = u.organizacion_id),
    'roles', coalesce((SELECT jsonb_agg(jsonb_build_object('codigo', r.codigo, 'nombre', r.nombre, 'centro', c.codigo) ORDER BY r.codigo)
                         FROM asig a JOIN seg.rol r ON r.id = a.rol_id LEFT JOIN org.centro c ON c.id = a.centro_id), '[]'),
    'roles_efectivos', coalesce((SELECT jsonb_agg(DISTINCT r.codigo) FROM arbol a JOIN seg.rol r ON r.id = a.id), '[]'),
    'permisos', coalesce((SELECT jsonb_agg(DISTINCT jsonb_build_object('codigo', p.codigo, 'centro', c.codigo))
                            FROM arbol a JOIN seg.rol_permiso rp ON rp.rol_id = a.id JOIN seg.permiso p ON p.id = rp.permiso_id
                            LEFT JOIN org.centro c ON c.id = a.centro_id), '[]'),
    'operativo', seg.fn_es_operativo(u.id))
  FROM u
$$;

-- =====================================================================
-- E. LECTURAS PARA LA INTERFAZ
-- =====================================================================
-- Todos los catálogos que la interfaz necesita, en una sola llamada (ADR-003: fuente única)
CREATE FUNCTION api.fn_catalogos() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT jsonb_build_object(
    'estados', (SELECT jsonb_agg(to_jsonb(e) - 'id' ORDER BY e.orden) FROM (
                  SELECT id, codigo, nombre, orden, es_inicial, es_final, descripcion FROM cat.estado_trazabilidad WHERE activo) e),
    'transiciones', (SELECT jsonb_agg(jsonb_build_object('origen', eo.codigo, 'destino', ed.codigo, 'tipo_documento', t.tipo_documento,
                                     'permiso', t.permiso_requerido, 'requiere_evidencia', t.requiere_evidencia, 'descripcion', t.descripcion))
                       FROM cat.transicion_estado t JOIN cat.estado_trazabilidad eo ON eo.id = t.estado_origen_id
                       JOIN cat.estado_trazabilidad ed ON ed.id = t.estado_destino_id WHERE t.activo),
    'clasificaciones', (SELECT jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) ORDER BY id) FROM cat.clasificacion_tecnica),
    'destinos', (SELECT jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) ORDER BY id) FROM cat.tipo_destino),
    'matriz_destinos', (SELECT jsonb_agg(jsonb_build_object('clasificacion', k.codigo, 'destino', d.codigo))
                          FROM cat.clasificacion_destino_permitido m JOIN cat.clasificacion_tecnica k ON k.id = m.clasificacion_id
                          JOIN cat.tipo_destino d ON d.id = m.tipo_destino_id),
    'categorias', (SELECT jsonb_agg(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre, 'nivel', c.nivel, 'ruta', c.ruta::text,
                                    'padre', p.codigo, 'contiene_almacenamiento', c.contiene_almacenamiento,
                                    'requeridos', coalesce((SELECT x.esquema_atributos -> 'required' FROM cat.categoria_raee x
                                                            WHERE c.ruta <@ x.ruta AND x.esquema_atributos ? 'required'
                                                            ORDER BY x.nivel DESC LIMIT 1), '[]'),
                                    'propiedades', coalesce(c.esquema_atributos -> 'properties', '{}'))
                                    ORDER BY c.ruta)
                     FROM cat.categoria_raee c LEFT JOIN cat.categoria_raee p ON p.id = c.categoria_padre_id WHERE c.activo),
    'criterios', (SELECT jsonb_agg(jsonb_build_object('codigo', cr.codigo, 'nombre', cr.nombre, 'tipo_valor', cr.tipo_valor,
                                   'categoria', c.codigo, 'obligatorio', cr.obligatorio) ORDER BY cr.id)
                    FROM cat.criterio_evaluacion cr LEFT JOIN cat.categoria_raee c ON c.id = cr.categoria_id WHERE cr.activo),
    'motivos', (SELECT jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) ORDER BY id) FROM cat.motivo),
    'tipos_evidencia', (SELECT jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'mime', mime_permitidos,
                                         'nivel_acceso', nivel_acceso) ORDER BY id) FROM cat.tipo_evidencia WHERE activo),
    'tipos_tratamiento', (SELECT jsonb_agg(jsonb_build_object('codigo', t.codigo, 'nombre', t.nombre, 'destino', d.codigo) ORDER BY t.id)
                            FROM cat.tipo_tratamiento t JOIN cat.tipo_destino d ON d.id = t.tipo_destino_id WHERE t.activo),
    'marcas', (SELECT jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) ORDER BY nombre) FROM cat.marca),
    'materiales', (SELECT jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) ORDER BY id) FROM cat.material),
    'propositos', (SELECT jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) ORDER BY id) FROM cat.proposito_uso),
    'roles', (SELECT jsonb_agg(jsonb_build_object('codigo', r.codigo, 'nombre', r.nombre, 'descripcion', r.descripcion,
                               'padre', p.codigo, 'servicio', r.es_servicio) ORDER BY r.id)
                FROM seg.rol r LEFT JOIN seg.rol p ON p.id = r.rol_padre_id WHERE r.activo),
    'centros', (SELECT jsonb_agg(jsonb_build_object('codigo', c.codigo, 'nombre', c.nombre, 'organizacion', o.nombre,
                                 'funciones', (SELECT jsonb_agg(tc.codigo) FROM org.centro_funcion cf JOIN cat.tipo_centro tc ON tc.id = cf.tipo_centro_id
                                               WHERE cf.centro_id = c.id),
                                 'nodo', (SELECT n.codigo FROM red.nodo n WHERE n.centro_id = c.id LIMIT 1),
                                 'ubicaciones', (SELECT jsonb_agg(jsonb_build_object('codigo', u.codigo, 'nombre', u.nombre, 'tipo', u.tipo,
                                                                  'nivel', u.nivel) ORDER BY u.ruta)
                                                   FROM org.ubicacion u WHERE u.centro_id = c.id AND u.activo))
                                 ORDER BY c.codigo)
                  FROM org.centro c JOIN org.organizacion o ON o.id = c.organizacion_id
                 WHERE o.ecosistema_id = seg.fn_ecosistema_actual() AND c.eliminado_en IS NULL),
    'organizaciones', (SELECT jsonb_agg(jsonb_build_object('uid', o.uid, 'codigo', o.codigo, 'nombre', o.nombre, 'sector', o.sector,
                                        'padre', p.codigo, 'nodo', (SELECT n.codigo FROM red.nodo n WHERE n.organizacion_id = o.id LIMIT 1))
                                        ORDER BY o.nombre)
                         FROM org.organizacion o LEFT JOIN org.organizacion p ON p.id = o.organizacion_padre_id
                        WHERE o.ecosistema_id = seg.fn_ecosistema_actual() AND o.eliminado_en IS NULL),
    'temas', '["CONCEPTOS","RECICLAJE","REPARACION","COMUNIDAD","SEGURIDAD_DATOS"]'::jsonb)
$$;

-- Ficha del dispositivo (atributos del subtipo)
CREATE VIEW api.v1_dispositivo WITH (security_invoker = true) AS
SELECT o.uid, o.codigo, c.codigo AS categoria, c.nombre AS categoria_nombre, ma.nombre AS marca, mo.nombre AS modelo,
       d.numero_serie, d.anio_fabricacion, d.peso_kg, d.contiene_almacenamiento, d.atributos,
       (SELECT p.codigo FROM trz.objeto_trazable p WHERE p.id = d.componente_de_id) AS componente_de,
       EXISTS (SELECT 1 FROM evd.evidencia_vinculo v JOIN evd.evidencia e ON e.id = v.evidencia_id
                 JOIN cat.tipo_evidencia te ON te.id = e.tipo_evidencia_id
                WHERE v.objeto_id = o.id AND te.codigo = 'CERTIFICADO_BORRADO' AND e.estado = 'ACTIVA') AS tiene_certificado_borrado
  FROM trz.dispositivo d
  JOIN trz.objeto_trazable o ON o.id = d.objeto_id
  JOIN cat.categoria_raee c ON c.id = d.categoria_id
  LEFT JOIN cat.marca ma ON ma.id = d.marca_id
  LEFT JOIN cat.modelo_equipo mo ON mo.id = d.modelo_id;

-- Composición vigente e histórica de los lotes
CREATE VIEW api.v1_lote_miembro WITH (security_invoker = true) AS
SELECT l.uid AS lote_uid, l.codigo AS lote, m.uid AS objeto_uid, m.codigo AS objeto, m.tipo_objeto, e.codigo AS estado,
       lower(lc.vigencia) AS desde, upper(lc.vigencia) AS hasta, upper_inf(lc.vigencia) AS vigente
  FROM trz.lote_composicion lc
  JOIN trz.objeto_trazable l ON l.id = lc.lote_id
  JOIN trz.objeto_trazable m ON m.id = lc.objeto_id
  JOIN cat.estado_trazabilidad e ON e.id = m.estado_actual_id;

-- Documentos operativos con su objeto, ruta y estado de transferencia (bandeja de trabajo)
CREATE VIEW api.v1_documento WITH (security_invoker = true) AS
SELECT d.uid, d.tipo_documento, d.numero, d.estado_documento, d.fecha_documento, d.fecha_cierre,
       c.codigo AS centro, o.nombre AS organizacion, us.alias AS responsable, r.numero AS documento_referencia,
       (SELECT count(*) FROM ops.documento_item i WHERE i.documento_id = d.id) AS items,
       (SELECT jsonb_agg(ob.codigo ORDER BY ob.codigo) FROM ops.documento_item i JOIN trz.objeto_trazable ob ON ob.id = i.objeto_id
         WHERE i.documento_id = d.id) AS objetos,
       t.estado_transferencia, no.codigo AS nodo_origen, nd.codigo AS nodo_destino,
       sr.modalidad, cs.codigo AS centro_destino, sr.fecha_preferida,
       d.observacion, d.ecosistema_id
  FROM ops.documento_operativo d
  LEFT JOIN org.centro c ON c.id = d.centro_id
  LEFT JOIN org.organizacion o ON o.id = d.organizacion_id
  JOIN seg.usuario us ON us.id = d.responsable_id
  LEFT JOIN ops.documento_operativo r ON r.id = d.documento_referencia_id
  LEFT JOIN ops.transferencia t ON t.documento_id = d.id
  LEFT JOIN red.arista a ON a.id = t.arista_id
  LEFT JOIN red.nodo no ON no.id = a.nodo_origen_id
  LEFT JOIN red.nodo nd ON nd.id = a.nodo_destino_id
  LEFT JOIN ops.solicitud_recoleccion sr ON sr.documento_id = d.id
  LEFT JOIN org.centro cs ON cs.id = sr.centro_destino_id;

-- Evidencias visibles (RN-07 aplica por RLS) con su objeto o documento
CREATE VIEW api.v1_evidencia WITH (security_invoker = true) AS
SELECT e.uid, te.codigo AS tipo, te.nombre AS tipo_nombre, e.mime, e.tamano_bytes, e.subido_en, us.alias AS subido_por,
       e.nivel_acceso, e.metadatos_limpios, ob.codigo AS objeto, d.numero AS documento, d.tipo_documento,
       coalesce(ob.codigo, (SELECT string_agg(o2.codigo, ',') FROM ops.documento_item i JOIN trz.objeto_trazable o2 ON o2.id = i.objeto_id
                            WHERE i.documento_id = d.id)) AS objetos_relacionados
  FROM evd.evidencia e
  JOIN cat.tipo_evidencia te ON te.id = e.tipo_evidencia_id
  JOIN seg.usuario us ON us.id = e.subido_por
  LEFT JOIN evd.evidencia_vinculo v ON v.evidencia_id = e.id
  LEFT JOIN trz.objeto_trazable ob ON ob.id = v.objeto_id
  LEFT JOIN ops.documento_operativo d ON d.id = v.documento_id
 WHERE e.estado = 'ACTIVA';

-- Red para dibujar: nodos, aristas con su capacidad vigente y capacidad de nodos
CREATE VIEW api.v1_red_arista WITH (security_invoker = true) AS
SELECT no.codigo AS origen, nd.codigo AS destino, a.activa, a.excepcion_id IS NOT NULL AS requiere_excepcion,
       (SELECT ca.capacidad FROM red.capacidad_arista ca JOIN cat.unidad_medida um ON um.id = ca.unidad_id
         WHERE ca.arista_id = a.id AND um.codigo = 'UND' AND ca.vigencia @> now()) AS capacidad_und,
       (SELECT ca.capacidad FROM red.capacidad_arista ca JOIN cat.unidad_medida um ON um.id = ca.unidad_id
         WHERE ca.arista_id = a.id AND um.codigo = 'KG' AND ca.vigencia @> now()) AS capacidad_kg,
       a.ecosistema_id
  FROM red.arista a JOIN red.nodo no ON no.id = a.nodo_origen_id JOIN red.nodo nd ON nd.id = a.nodo_destino_id;

CREATE VIEW api.v1_red_nodo WITH (security_invoker = true) AS
SELECT n.codigo, n.nombre, t.codigo AS tipo, t.es_fuente, t.es_sumidero, c.codigo AS centro, o.codigo AS organizacion, n.activo,
       (SELECT cn.capacidad FROM red.capacidad_nodo cn JOIN cat.unidad_medida um ON um.id = cn.unidad_id
         WHERE cn.nodo_id = n.id AND um.codigo = 'UND' AND cn.vigencia @> now()) AS capacidad_und,
       n.ecosistema_id
  FROM red.nodo n JOIN cat.tipo_nodo t ON t.id = n.tipo_nodo_id
  LEFT JOIN org.centro c ON c.id = n.centro_id LEFT JOIN org.organizacion o ON o.id = n.organizacion_id;

CREATE VIEW api.v1_escenario WITH (security_invoker = true) AS
SELECT e.codigo, e.nombre, e.descripcion, b.codigo AS escenario_base, e.estado, e.periodo,
       (SELECT um.codigo FROM cat.unidad_medida um WHERE um.id = e.unidad_id) AS unidad,
       coalesce((SELECT jsonb_agg(jsonb_build_object('origen', no.codigo, 'destino', nd.codigo, 'capacidad', ea.capacidad_ajustada,
                                  'activa', ea.activa, 'motivo', ea.motivo))
                   FROM red.escenario_arista ea JOIN red.arista a ON a.id = ea.arista_id
                   JOIN red.nodo no ON no.id = a.nodo_origen_id JOIN red.nodo nd ON nd.id = a.nodo_destino_id
                  WHERE ea.escenario_id = e.id), '[]') AS cambios_aristas,
       coalesce((SELECT jsonb_agg(jsonb_build_object('nodo', n.codigo, 'oferta', en.oferta, 'demanda', en.demanda,
                                  'capacidad', en.capacidad_ajustada))
                   FROM red.escenario_nodo en JOIN red.nodo n ON n.id = en.nodo_id WHERE en.escenario_id = e.id), '[]') AS cambios_nodos,
       e.ecosistema_id
  FROM red.escenario_red e LEFT JOIN red.escenario_red b ON b.id = e.escenario_base_id;

-- Último resultado guardado de un escenario (para quien no ejecuta el flujo: comité, auditor)
CREATE FUNCTION api.fn_resultado_flujo(p_escenario text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER AS $$
  WITH j AS (SELECT j.* FROM red.ejecucion_flujo j JOIN red.escenario_red e ON e.id = j.escenario_id
              WHERE e.codigo = p_escenario AND e.ecosistema_id = seg.fn_ecosistema_actual() AND j.estado = 'OK'
              ORDER BY j.finalizado_en DESC LIMIT 1)
  SELECT jsonb_build_object(
    'ejecucion_id', j.id, 'flujo_maximo', j.flujo_maximo, 'hash', j.hash_entrada, 'calculado_en', j.finalizado_en,
    'algoritmo', j.algoritmo, 'version', j.version_modulo,
    'aristas', (SELECT jsonb_agg(jsonb_build_object('origen', no.codigo, 'destino', nd.codigo, 'capacidad', r.capacidad,
                                 'flujo', r.flujo, 'saturada', r.saturada) ORDER BY no.codigo, nd.codigo)
                  FROM red.resultado_flujo_arista r JOIN red.arista a ON a.id = r.arista_id
                  JOIN red.nodo no ON no.id = a.nodo_origen_id JOIN red.nodo nd ON nd.id = a.nodo_destino_id
                 WHERE r.ejecucion_id = j.id),
    'cortes', (SELECT jsonb_agg(jsonb_build_object('numero', c.numero_corte, 'capacidad', c.capacidad_corte, 'lado_fuente', c.lado_fuente,
                                'aristas', coalesce((SELECT jsonb_agg(jsonb_build_array(no.codigo, nd.codigo) ORDER BY no.codigo, nd.codigo)
                                                       FROM red.corte_minimo_arista ca JOIN red.arista a ON a.id = ca.arista_id
                                                       JOIN red.nodo no ON no.id = a.nodo_origen_id JOIN red.nodo nd ON nd.id = a.nodo_destino_id
                                                      WHERE ca.corte_id = c.id), '[]'),
                                'nodos', coalesce((SELECT jsonb_agg(n.codigo) FROM red.corte_minimo_nodo cn JOIN red.nodo n ON n.id = cn.nodo_id
                                                    WHERE cn.corte_id = c.id), '[]')) ORDER BY c.numero_corte)
                 FROM red.corte_minimo c WHERE c.ejecucion_id = j.id))
  FROM j
$$;

-- Vista operativa del objeto: lo que la interfaz necesita para decidir qué acciones ofrecer
CREATE VIEW api.v1_objeto_operativo WITH (security_invoker = true) AS
SELECT o.uid, o.codigo, o.tipo_objeto, e.codigo AS estado, e.nombre AS estado_nombre, k.codigo AS clasificacion,
       c.codigo AS categoria, c.nombre AS categoria_nombre, d.peso_kg, coalesce(d.contiene_almacenamiento, false) AS contiene_almacenamiento,
       ma.nombre AS marca, og.codigo AS organizacion_origen, og.nombre AS organizacion_origen_nombre,
       ce.codigo AS centro_actual, ub.codigo AS ubicacion_actual, o.registrado_en, o.cerrado_en,
       (SELECT max(h.ocurrido_en) FROM trz.historial_estado h WHERE h.objeto_id = o.id) AS ultimo_movimiento,
       lv.codigo AS lote_codigo, lv.uid AS lote_uid,
       (SELECT count(*) FROM trz.lote_composicion lc WHERE lc.lote_id = o.id AND upper_inf(lc.vigencia)) AS miembros_vigentes,
       sol.uid AS solicitud_uid, sol.numero AS solicitud_numero, sol.estado_documento AS solicitud_estado, sol.centro AS solicitud_centro,
       trf.uid AS transferencia_uid, trf.numero AS transferencia_numero, trf.origen AS transferencia_nodo_origen,
       trf.destino AS transferencia_nodo_destino, trf.centro AS transferencia_centro_destino, trf.organizacion AS transferencia_org_destino,
       (SELECT td.codigo FROM ops.tratamiento tr JOIN cat.tipo_tratamiento tt ON tt.id = tr.tipo_tratamiento_id
          JOIN cat.tipo_destino td ON td.id = tt.tipo_destino_id
         WHERE tr.objeto_id = o.id AND tr.resultado IN ('EXITOSO','PARCIAL') ORDER BY tr.finalizado_en DESC LIMIT 1) AS ultimo_tratamiento_destino,
       (SELECT ob.codigo FROM ops.asignacion_beneficiario a JOIN ops.documento_operativo dd ON dd.id = a.documento_id
          JOIN org.organizacion ob ON ob.id = a.beneficiario_id
         WHERE a.objeto_id = o.id ORDER BY dd.fecha_documento DESC LIMIT 1) AS beneficiario,
       EXISTS (SELECT 1 FROM evd.evidencia_vinculo v JOIN evd.evidencia ev ON ev.id = v.evidencia_id
                 JOIN cat.tipo_evidencia te ON te.id = ev.tipo_evidencia_id
                WHERE v.objeto_id = o.id AND te.codigo = 'CERTIFICADO_BORRADO' AND ev.estado = 'ACTIVA') AS tiene_certificado_borrado,
       o.ecosistema_id
  FROM trz.objeto_trazable o
  JOIN cat.estado_trazabilidad e ON e.id = o.estado_actual_id
  JOIN org.organizacion og ON og.id = o.organizacion_origen_id
  LEFT JOIN cat.clasificacion_tecnica k ON k.id = o.clasificacion_actual_id
  LEFT JOIN trz.dispositivo d ON d.objeto_id = o.id
  LEFT JOIN cat.categoria_raee c ON c.id = d.categoria_id
  LEFT JOIN cat.marca ma ON ma.id = d.marca_id
  LEFT JOIN org.ubicacion ub ON ub.id = o.ubicacion_actual_id
  LEFT JOIN org.centro ce ON ce.id = ub.centro_id
  LEFT JOIN LATERAL (SELECT l.id, l.codigo, l.uid FROM trz.lote_composicion lc JOIN trz.objeto_trazable l ON l.id = lc.lote_id
                      WHERE lc.objeto_id = o.id AND upper_inf(lc.vigencia) LIMIT 1) lv ON true
  LEFT JOIN LATERAL (SELECT dd.uid, dd.numero, dd.estado_documento, cs.codigo AS centro
                       FROM ops.documento_operativo dd JOIN ops.solicitud_recoleccion s ON s.documento_id = dd.id
                       JOIN org.centro cs ON cs.id = s.centro_destino_id
                       JOIN ops.documento_item i ON i.documento_id = dd.id
                      WHERE i.objeto_id IN (o.id, lv.id) AND dd.estado_documento IN ('EMITIDO','EN_CURSO')
                      ORDER BY dd.fecha_documento DESC LIMIT 1) sol ON true
  LEFT JOIN LATERAL (SELECT dd.uid, dd.numero, no.codigo AS origen, nd.codigo AS destino, cd.codigo AS centro, od.codigo AS organizacion
                       FROM ops.transferencia t JOIN ops.documento_operativo dd ON dd.id = t.documento_id
                       JOIN ops.documento_item i ON i.documento_id = dd.id
                       JOIN red.arista a ON a.id = t.arista_id
                       JOIN red.nodo no ON no.id = a.nodo_origen_id JOIN red.nodo nd ON nd.id = a.nodo_destino_id
                       LEFT JOIN org.centro cd ON cd.id = nd.centro_id LEFT JOIN org.organizacion od ON od.id = nd.organizacion_id
                      WHERE i.objeto_id IN (o.id, lv.id) AND t.estado_transferencia = 'DESPACHADA'
                      ORDER BY dd.fecha_documento DESC LIMIT 1) trf ON true;

-- Bitácora del asistente MCP y eventos de seguridad (AUDITORIA.CONSULTAR)
CREATE FUNCTION api.fn_bitacora_mcp(p_limite integer DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  PERFORM seg.fn_exigir_permiso(seg.fn_usuario_actual(), 'AUDITORIA.CONSULTAR');
  RETURN (SELECT coalesce(jsonb_agg(x ORDER BY x.ocurrido_en DESC), '[]') FROM (
    SELECT i.ocurrido_en, i.nombre_solicitado AS herramienta, u.alias AS usuario, i.estado, i.argumentos, i.filas, i.duracion_ms,
           i.error, i.request_id
      FROM mcp.invocacion i JOIN seg.usuario u ON u.id = i.usuario_id
     WHERE u.ecosistema_id = seg.fn_ecosistema_actual()
     ORDER BY i.ocurrido_en DESC LIMIT least(coalesce(p_limite, 100), 500)) x);
END $$;

CREATE FUNCTION api.fn_eventos_seguridad(p_limite integer DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  PERFORM seg.fn_exigir_permiso(seg.fn_usuario_actual(), 'AUDITORIA.CONSULTAR');
  RETURN (SELECT coalesce(jsonb_agg(x ORDER BY x.ocurrido_en DESC), '[]') FROM (
    SELECT ev.ocurrido_en, ev.tipo, u.alias AS usuario, ev.detalle, ev.request_id
      FROM aud.evento_seguridad ev LEFT JOIN seg.usuario u ON u.id = ev.usuario_id
     WHERE u.id IS NULL OR u.ecosistema_id = seg.fn_ecosistema_actual()
     ORDER BY ev.ocurrido_en DESC LIMIT least(coalesce(p_limite, 100), 500)) x);
END $$;

-- Auditoría consultable desde la API (solo con AUDITORIA.CONSULTAR)
CREATE FUNCTION api.fn_auditoria(p_limite integer DEFAULT 100, p_tabla text DEFAULT NULL, p_codigo text DEFAULT NULL,
                                 p_desde timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_obj bigint; v jsonb;
BEGIN
  PERFORM seg.fn_exigir_permiso(seg.fn_usuario_actual(), 'AUDITORIA.CONSULTAR');
  IF p_codigo IS NOT NULL THEN
    SELECT id INTO v_obj FROM trz.objeto_trazable WHERE codigo = p_codigo AND ecosistema_id = seg.fn_ecosistema_actual();
    IF v_obj IS NULL THEN RAISE EXCEPTION 'Objeto % no existe', p_codigo USING ERRCODE = 'EC404'; END IF;
  END IF;
  SELECT coalesce(jsonb_agg(x ORDER BY x.ocurrido_en DESC), '[]') INTO v FROM (
    SELECT l.id, l.ocurrido_en, l.esquema || '.' || l.tabla AS tabla, l.operacion, l.pk, l.campos_cambiados,
           us.alias AS usuario, l.canal, l.request_id, l.usuario_bd, l.hash_registro,
           CASE WHEN l.operacion = 'U' THEN (SELECT jsonb_object_agg(k, jsonb_build_object('antes', l.datos_antes -> k, 'despues', l.datos_despues -> k))
                                               FROM unnest(l.campos_cambiados) k)
                ELSE NULL END AS cambios
      FROM aud.log_cambio l LEFT JOIN seg.usuario us ON us.id = l.usuario_id
     WHERE (p_tabla IS NULL OR l.esquema || '.' || l.tabla = p_tabla)
       AND (p_desde IS NULL OR l.ocurrido_en >= p_desde)
       AND (v_obj IS NULL OR (l.esquema = 'trz' AND l.tabla = 'objeto_trazable' AND l.pk ->> 'id' = v_obj::text)
                          OR coalesce(l.datos_despues, l.datos_antes) ->> 'objeto_id' = v_obj::text)
       AND (us.ecosistema_id IS NULL OR us.ecosistema_id = seg.fn_ecosistema_actual())
     ORDER BY l.ocurrido_en DESC LIMIT least(coalesce(p_limite, 100), 500)) x;
  RETURN v;
END $$;

-- Estado de un objeto en un instante pasado (reconstrucción desde la auditoría)
CREATE FUNCTION api.fn_objeto_en(p_codigo text, p_instante timestamptz) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_obj bigint; v jsonb;
BEGIN
  PERFORM seg.fn_exigir_permiso(seg.fn_usuario_actual(), 'AUDITORIA.CONSULTAR');
  SELECT id INTO v_obj FROM trz.objeto_trazable WHERE codigo = p_codigo AND ecosistema_id = seg.fn_ecosistema_actual();
  IF v_obj IS NULL THEN RAISE EXCEPTION 'Objeto % no existe', p_codigo USING ERRCODE = 'EC404'; END IF;
  v := aud.fn_estado_en('trz', 'objeto_trazable', jsonb_build_object('id', v_obj), p_instante);
  IF v IS NULL THEN RETURN jsonb_build_object('existia', false, 'instante', p_instante); END IF;
  RETURN jsonb_build_object('existia', true, 'instante', p_instante,
    'estado', (SELECT codigo FROM cat.estado_trazabilidad WHERE id = (v ->> 'estado_actual_id')::smallint),
    'clasificacion', (SELECT codigo FROM cat.clasificacion_tecnica WHERE id = (v ->> 'clasificacion_actual_id')::smallint),
    'ubicacion', (SELECT c.codigo || ' / ' || u.codigo FROM org.ubicacion u JOIN org.centro c ON c.id = u.centro_id
                   WHERE u.id = (v ->> 'ubicacion_actual_id')::bigint),
    'version', v -> 'version', 'fila', v);
END $$;

-- Administración de usuarios y roles (USUARIO.ADMINISTRAR; la segregación la valida el trigger)
CREATE FUNCTION api.fn_listar_usuarios() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  PERFORM seg.fn_exigir_permiso(seg.fn_usuario_actual(), 'USUARIO.ADMINISTRAR');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object(
            'uid', u.uid, 'alias', u.alias, 'estado', u.estado, 'proveedor', u.proveedor_identidad, 'mfa', u.mfa_habilitado,
            'organizacion', o.nombre, 'ultimo_acceso', u.ultimo_acceso_en, 'creado_en', u.creado_en,
            'roles', coalesce((SELECT jsonb_agg(jsonb_build_object('codigo', r.codigo, 'nombre', r.nombre, 'centro', c.codigo,
                                                'desde', lower(ur.vigencia), 'motivo', ur.motivo) ORDER BY r.codigo)
                                 FROM seg.usuario_rol ur JOIN seg.rol r ON r.id = ur.rol_id LEFT JOIN org.centro c ON c.id = ur.centro_id
                                WHERE ur.usuario_id = u.id AND ur.vigencia @> now()), '[]')) ORDER BY u.alias), '[]')
            FROM seg.usuario u JOIN org.organizacion o ON o.id = u.organizacion_id
           WHERE u.ecosistema_id = seg.fn_ecosistema_actual() AND u.eliminado_en IS NULL);
END $$;

CREATE FUNCTION api.fn_asignar_rol(p_usuario uuid, p_rol text, p_centro text DEFAULT NULL, p_motivo text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_admin bigint := seg.fn_usuario_actual(); v_u bigint; v_rol smallint; v_centro bigint;
BEGIN
  PERFORM seg.fn_exigir_permiso(v_admin, 'USUARIO.ADMINISTRAR');
  IF coalesce(btrim(p_motivo), '') = '' THEN RAISE EXCEPTION 'La asignación de un rol exige un motivo' USING ERRCODE = 'EC422'; END IF;
  SELECT id INTO v_u FROM seg.usuario WHERE uid = p_usuario AND ecosistema_id = seg.fn_ecosistema_actual();
  IF v_u IS NULL THEN RAISE EXCEPTION 'Usuario no encontrado' USING ERRCODE = 'EC404'; END IF;
  IF v_u = v_admin THEN RAISE EXCEPTION 'Nadie se asigna roles a sí mismo (separación de funciones)' USING ERRCODE = 'EC403'; END IF;
  SELECT id INTO v_rol FROM seg.rol WHERE codigo = p_rol AND activo AND NOT es_servicio;
  IF v_rol IS NULL THEN RAISE EXCEPTION 'Rol % no existe', p_rol USING ERRCODE = 'EC404'; END IF;
  IF p_centro IS NOT NULL THEN v_centro := org.fn_centro(p_centro); END IF;
  IF EXISTS (SELECT 1 FROM seg.usuario_rol WHERE usuario_id = v_u AND rol_id = v_rol AND vigencia @> now()
               AND centro_id IS NOT DISTINCT FROM v_centro) THEN
    RAISE EXCEPTION 'El usuario ya tiene ese rol vigente' USING ERRCODE = 'EC409';
  END IF;
  INSERT INTO seg.usuario_rol(usuario_id, rol_id, centro_id, otorgado_por, motivo) VALUES (v_u, v_rol, v_centro, v_admin, p_motivo);
  INSERT INTO aud.evento_seguridad(tipo, usuario_id, detalle, request_id)
  VALUES ('CAMBIO_ROL', v_admin, jsonb_build_object('usuario', p_usuario, 'rol', p_rol, 'centro', p_centro, 'accion', 'ASIGNAR'),
          nullif(current_setting('app.request_id', true), ''));
END $$;

CREATE FUNCTION api.fn_revocar_rol(p_usuario uuid, p_rol text, p_motivo text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_admin bigint := seg.fn_usuario_actual(); v_u bigint;
BEGIN
  PERFORM seg.fn_exigir_permiso(v_admin, 'USUARIO.ADMINISTRAR');
  SELECT id INTO v_u FROM seg.usuario WHERE uid = p_usuario AND ecosistema_id = seg.fn_ecosistema_actual();
  IF v_u IS NULL THEN RAISE EXCEPTION 'Usuario no encontrado' USING ERRCODE = 'EC404'; END IF;
  IF v_u = v_admin THEN RAISE EXCEPTION 'Nadie modifica sus propios roles' USING ERRCODE = 'EC403'; END IF;
  UPDATE seg.usuario_rol ur SET vigencia = tstzrange(lower(ur.vigencia), now()), motivo = coalesce(ur.motivo, '') || ' · Revocado: ' || p_motivo
    FROM seg.rol r WHERE r.id = ur.rol_id AND ur.usuario_id = v_u AND r.codigo = p_rol AND ur.vigencia @> now();
  IF NOT FOUND THEN RAISE EXCEPTION 'El usuario no tiene ese rol vigente' USING ERRCODE = 'EC404'; END IF;
  INSERT INTO aud.evento_seguridad(tipo, usuario_id, detalle, request_id)
  VALUES ('CAMBIO_ROL', v_admin, jsonb_build_object('usuario', p_usuario, 'rol', p_rol, 'accion', 'REVOCAR', 'motivo', p_motivo),
          nullif(current_setting('app.request_id', true), ''));
END $$;

-- =====================================================================
-- F. SEGURIDAD, AUDITORÍA Y DICCIONARIO DE LO NUEVO
-- =====================================================================
-- Auditoría automática de las tablas nuevas (excepto bitácoras de solo inserción)
DO $$
DECLARE r record; v_cols text;
BEGIN
  FOR r IN SELECT c.oid, n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relkind = 'r' AND (n.nspname, c.relname) IN (('red','capacidad_nodo'), ('edu','contenido'), ('edu','comentario'), ('edu','reaccion'))
  LOOP
    SELECT string_agg(quote_literal(a.attname), ',' ORDER BY array_position(i.indkey, a.attnum)) INTO v_cols
      FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
     WHERE i.indrelid = r.oid AND i.indisprimary;
    EXECUTE format('CREATE TRIGGER tg_auditoria AFTER INSERT OR UPDATE OR DELETE ON %I.%I FOR EACH ROW EXECUTE FUNCTION aud.fn_auditar(%s)',
                   r.nspname, r.relname, v_cols);
  END LOOP;
END $$;

-- RLS: aislamiento por ecosistema y visibilidad de contenidos ocultos solo para su autor y moderadores
ALTER TABLE edu.contenido ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_contenido ON edu.contenido USING (ecosistema_id = seg.fn_ecosistema_actual()
  AND (estado = 'PUBLICADO' OR publicado_por = seg.fn_usuario_actual() OR edu.fn_puede_moderar()));
ALTER TABLE edu.comentario ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_comentario ON edu.comentario USING (EXISTS (SELECT 1 FROM edu.contenido c WHERE c.id = contenido_id));
ALTER TABLE edu.reaccion ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_reaccion ON edu.reaccion USING (EXISTS (SELECT 1 FROM edu.contenido c WHERE c.id = contenido_id));
ALTER TABLE edu.visualizacion ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_visualizacion ON edu.visualizacion USING (EXISTS (SELECT 1 FROM edu.contenido c WHERE c.id = contenido_id));

-- Privilegios: nada público; lectura por vistas; escritura solo por funciones api
REVOKE ALL ON SCHEMA edu FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA api, edu, red FROM PUBLIC;
GRANT USAGE ON SCHEMA edu TO ecoraee_lectura;
GRANT SELECT ON edu.contenido, edu.comentario, edu.reaccion, edu.visualizacion TO ecoraee_lectura;
REVOKE SELECT ON edu.contenido FROM ecoraee_lectura;
GRANT SELECT (id, uid, ecosistema_id, titulo, descripcion, tema, mime, tamano_bytes, duracion_seg, estado, publicado_por, publicado_en, tiene_archivo)
  ON edu.contenido TO ecoraee_lectura;                            -- sin bucket ni clave S3
GRANT SELECT ON red.capacidad_nodo, red.corte_minimo_nodo TO ecoraee_lectura;
GRANT SELECT ON api.v1_contenido, api.v1_comentario, api.v1_dispositivo, api.v1_lote_miembro, api.v1_documento, api.v1_evidencia,
                api.v1_red_arista, api.v1_red_nodo, api.v1_escenario, api.v1_corte_minimo, api.v1_objeto_operativo TO ecoraee_lectura;
GRANT EXECUTE ON FUNCTION edu.fn_puede_moderar(), red.fn_nodo_efectivo(bigint, bigint), api.fn_resultado_flujo(text),
                          api.fn_perfil(), api.fn_catalogos() TO ecoraee_lectura;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO ecoraee_app;
-- la autenticación ocurre antes de tener contexto; solo la API puede llamarla
REVOKE EXECUTE ON FUNCTION api.fn_autenticar_local(text, text, text), api.fn_registrar_cuenta(text, text, text, text),
                           api.fn_resolver_identidad(text, text), api.fn_organizaciones_publicas() FROM ecoraee_mcp, ecoraee_lectura;
-- el servidor MCP conserva exactamente los privilegios derivados del registro mcp.herramienta (script 05)
GRANT EXECUTE ON FUNCTION api.fn_dataset_flujo(text), api.fn_registrar_resultado_flujo(text, text, numeric, jsonb, jsonb, text, text, timestamptz)
  TO ecoraee_mcp;

-- Diccionario: dominio nuevo y comentarios de tablas y columnas
INSERT INTO meta.dominio(esquema, nombre, descripcion, propietario_negocio, custodio_tecnico)
VALUES ('edu', 'Capacitación', 'Contenidos educativos, comentarios y reacciones (Innovación, RNF-07)', 'Coordinación de Innovación', 'Equipo de plataforma');

COMMENT ON TABLE red.capacidad_nodo IS 'Capacidad de procesamiento de un nodo con vigencia (el capítulo la modela como arista E_in→E_out).';
COMMENT ON COLUMN red.capacidad_nodo.nodo_id IS 'Nodo cuya capacidad de procesamiento se limita.';
COMMENT ON COLUMN red.capacidad_nodo.capacidad IS 'Unidades o kg que el nodo procesa por periodo.';
COMMENT ON COLUMN red.capacidad_nodo.unidad_id IS 'Unidad de medida de la capacidad.';
COMMENT ON COLUMN red.capacidad_nodo.periodo IS 'Periodo de la capacidad: DIA, SEMANA o MES.';
COMMENT ON COLUMN red.capacidad_nodo.vigencia IS 'Intervalo de vigencia; no se solapa para el mismo nodo y unidad.';
COMMENT ON COLUMN red.capacidad_nodo.fuente IS 'Origen del dato (capítulo, medición, contrato).';
COMMENT ON COLUMN red.capacidad_nodo.id IS 'Identificador interno.';
COMMENT ON COLUMN red.escenario_nodo.capacidad_ajustada IS 'Capacidad de procesamiento del nodo en el escenario (NULL hereda de la base).';
COMMENT ON TABLE red.corte_minimo_nodo IS 'Nodos cuya capacidad de procesamiento forma parte de un corte mínimo.';
COMMENT ON COLUMN red.corte_minimo_nodo.corte_id IS 'Corte mínimo al que pertenece.';
COMMENT ON COLUMN red.corte_minimo_nodo.nodo_id IS 'Nodo saturado que separa la fuente del sumidero.';
COMMENT ON TABLE edu.contenido IS 'Contenido de capacitación (video en S3) publicado por un usuario.';
COMMENT ON COLUMN edu.contenido.id IS 'Identificador interno.';
COMMENT ON COLUMN edu.contenido.uid IS 'Identificador público del contenido.';
COMMENT ON COLUMN edu.contenido.ecosistema_id IS 'Ecosistema (tenant) del contenido.';
COMMENT ON COLUMN edu.contenido.titulo IS 'Título visible.';
COMMENT ON COLUMN edu.contenido.descripcion IS 'Descripción del contenido.';
COMMENT ON COLUMN edu.contenido.tema IS 'Tema: conceptos, reciclaje, reparación, comunidad o seguridad de datos.';
COMMENT ON COLUMN edu.contenido.s3_bucket IS 'Bucket privado donde vive el video.';
COMMENT ON COLUMN edu.contenido.s3_clave IS 'Clave del objeto en S3 (no expuesta a la lectura).';
COMMENT ON COLUMN edu.contenido.mime IS 'Formato del video.';
COMMENT ON COLUMN edu.contenido.tamano_bytes IS 'Tamaño del archivo (máximo 500 MB).';
COMMENT ON COLUMN edu.contenido.duracion_seg IS 'Duración del video en segundos.';
COMMENT ON COLUMN edu.contenido.estado IS 'PUBLICADO u OCULTO (moderación).';
COMMENT ON COLUMN edu.contenido.publicado_por IS 'Usuario que publicó.';
COMMENT ON COLUMN edu.contenido.publicado_en IS 'Fecha de publicación.';
COMMENT ON COLUMN edu.contenido.tiene_archivo IS 'Derivado: el contenido tiene video en S3 (sin exponer la clave).';
COMMENT ON TABLE edu.comentario IS 'Comentario de un usuario sobre un contenido.';
COMMENT ON COLUMN edu.comentario.id IS 'Identificador interno.';
COMMENT ON COLUMN edu.comentario.uid IS 'Identificador público.';
COMMENT ON COLUMN edu.comentario.contenido_id IS 'Contenido comentado.';
COMMENT ON COLUMN edu.comentario.usuario_id IS 'Autor del comentario.';
COMMENT ON COLUMN edu.comentario.texto IS 'Texto (máximo 1000 caracteres).';
COMMENT ON COLUMN edu.comentario.creado_en IS 'Fecha del comentario.';
COMMENT ON COLUMN edu.comentario.oculto IS 'Ocultado por moderación.';
COMMENT ON TABLE edu.reaccion IS 'Me gusta de un usuario sobre un contenido (uno por usuario).';
COMMENT ON COLUMN edu.reaccion.contenido_id IS 'Contenido.';
COMMENT ON COLUMN edu.reaccion.usuario_id IS 'Usuario que reacciona.';
COMMENT ON COLUMN edu.reaccion.creado_en IS 'Fecha de la reacción.';
COMMENT ON TABLE edu.visualizacion IS 'Bitácora de reproducciones (solo inserción).';
COMMENT ON COLUMN edu.visualizacion.id IS 'Identificador interno.';
COMMENT ON COLUMN edu.visualizacion.contenido_id IS 'Contenido reproducido.';
COMMENT ON COLUMN edu.visualizacion.usuario_id IS 'Usuario que lo reprodujo.';
COMMENT ON COLUMN edu.visualizacion.visto_en IS 'Fecha de la reproducción.';
SELECT meta.fn_sincronizar_diccionario();

INSERT INTO meta.termino_glosario(termino, definicion, sinonimos, termino_ae, termino_md, termino_bd, termino_nube, termino_inn, entidad_ref) VALUES
 ('Capacidad de nodo', 'Máximo que un centro puede procesar por periodo, independiente de las rutas que llegan a él.', '{"capacidad de procesamiento"}',
  'Capacidad del laboratorio', 'Arista E_in→E_out (división de nodo)', 'red.capacidad_nodo', '—', '—', 'red.capacidad_nodo'),
 ('Contenido de capacitación', 'Video educativo publicado en la plataforma para reducir brechas de uso.', '{"video","aprende"}',
  'Servicio de capacitación', '—', 'edu.contenido', 'Objeto en S3', 'Alfabetización digital', 'edu.contenido');

-- =====================================================================
-- G. CREDENCIALES LOCALES DE LOS USUARIOS SINTÉTICOS (solo MVP / demo)
-- En producción los usuarios vienen de Cognito (proveedor COGNITO + sub_externo).
-- Contraseña común de demostración: EcoRAEE-2026 (datos sintéticos, RNF-10)
-- =====================================================================
INSERT INTO seg.usuario(ecosistema_id, organizacion_id, alias, correo, proveedor_identidad, hash_credencial)
SELECT o.ecosistema_id, o.id, 'gestor.d1', 'gestor.d1@ejemplo.invalid', 'LOCAL', 'x' FROM org.organizacion o WHERE o.codigo = 'DISPOSIC';
INSERT INTO seg.usuario_rol(usuario_id, rol_id, centro_id, motivo)
SELECT u.id, r.id, c.id, 'Gestor de la celda de disposición controlada'
  FROM seg.usuario u, seg.rol r, org.centro c WHERE u.alias = 'gestor.d1' AND r.codigo = 'GESTOR_TRATAMIENTO' AND c.codigo = 'D1';
UPDATE seg.usuario SET proveedor_identidad = 'LOCAL', hash_credencial = crypt('EcoRAEE-2026', gen_salt('bf', 10)), sub_externo = NULL;
