-- Catálogo, series e imágenes de equipo. Ejecutar después del script 16.
-- Las modificaciones de las tablas existentes quedan en su auditoría habitual.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'cat.modelo_equipo'::regclass AND attname = 'uid' AND NOT attisdropped) THEN
    ALTER TABLE cat.modelo_equipo ADD COLUMN uid uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
      ADD COLUMN creado_en timestamptz NOT NULL DEFAULT now(),
      ADD COLUMN creado_por bigint REFERENCES seg.usuario(id),
      ADD COLUMN editable_hasta timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
      ADD COLUMN actualizado_en timestamptz, ADD COLUMN imagen_clave text;
    UPDATE cat.modelo_equipo SET editable_hasta = creado_en;
  END IF;
END $$;
ALTER TABLE trz.dispositivo ADD COLUMN IF NOT EXISTS modelo_libre varchar(120);

COMMENT ON COLUMN cat.modelo_equipo.uid IS 'Identificador público del modelo.';
COMMENT ON COLUMN cat.modelo_equipo.creado_en IS 'Instante de creación del modelo.';
COMMENT ON COLUMN cat.modelo_equipo.creado_por IS 'Usuario que creó el modelo; nulo para semillas.';
COMMENT ON COLUMN cat.modelo_equipo.editable_hasta IS 'Fin del plazo de edición decidido por la base de datos.';
COMMENT ON COLUMN cat.modelo_equipo.actualizado_en IS 'Instante de la última modificación.';
COMMENT ON COLUMN cat.modelo_equipo.imagen_clave IS 'Clave relativa de la imagen en el almacén de evidencias.';
COMMENT ON COLUMN trz.dispositivo.modelo_libre IS 'Modelo escrito cuando no se selecciona uno del catálogo.';

CREATE TABLE IF NOT EXISTS cat.modelo_reapertura (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  modelo_id integer NOT NULL REFERENCES cat.modelo_equipo(id),
  motivo varchar(300) NOT NULL CHECK (length(btrim(motivo)) BETWEEN 5 AND 300),
  usuario_id bigint NOT NULL REFERENCES seg.usuario(id),
  ocurrido_en timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE cat.modelo_reapertura IS 'Motivo y responsable de cada reapertura de un modelo.';
COMMENT ON COLUMN cat.modelo_reapertura.id IS 'Identificador interno de la reapertura.';
COMMENT ON COLUMN cat.modelo_reapertura.modelo_id IS 'Modelo cuya edición se reabre.';
COMMENT ON COLUMN cat.modelo_reapertura.motivo IS 'Justificación de la reapertura.';
COMMENT ON COLUMN cat.modelo_reapertura.usuario_id IS 'Administrador que autorizó la reapertura.';
COMMENT ON COLUMN cat.modelo_reapertura.ocurrido_en IS 'Instante de la reapertura.';
DROP TRIGGER IF EXISTS tg_auditoria ON cat.modelo_reapertura;
CREATE TRIGGER tg_auditoria AFTER INSERT OR UPDATE OR DELETE ON cat.modelo_reapertura
  FOR EACH ROW EXECUTE FUNCTION aud.fn_auditar('id');

CREATE OR REPLACE VIEW api.v1_modelo_equipo WITH (security_invoker = true) AS
SELECT m.uid, m.nombre, ma.codigo AS marca, ma.nombre AS marca_nombre,
       c.codigo AS categoria, c.nombre AS categoria_nombre, m.anio_lanzamiento, m.peso_kg, m.activo,
       m.creado_en, u.alias AS creado_por, m.editable_hasta, now() < m.editable_hasta AS editable,
       greatest(0, floor(extract(epoch FROM (m.editable_hasta - now()))))::bigint AS segundos_restantes,
       m.imagen_clave IS NOT NULL AS tiene_imagen
  FROM cat.modelo_equipo m JOIN cat.marca ma ON ma.id = m.marca_id
  JOIN cat.categoria_raee c ON c.id = m.categoria_id LEFT JOIN seg.usuario u ON u.id = m.creado_por;
GRANT SELECT ON api.v1_modelo_equipo TO ecoraee_lectura;

CREATE OR REPLACE FUNCTION api.fn_crear_modelo(p_categoria text, p_marca text, p_nombre text, p_anio int, p_peso numeric)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_cat smallint; v_marca integer; v_uid uuid;
BEGIN
  IF NOT (seg.fn_tiene_permiso(seg.fn_usuario_actual(), 'CATALOGO.ADMINISTRAR') OR
          seg.fn_tiene_permiso(seg.fn_usuario_actual(), 'RED.GESTIONAR')) THEN
    RAISE EXCEPTION 'No tienes permiso para administrar el catálogo' USING ERRCODE = 'EC403';
  END IF;
  SELECT c.id INTO v_cat FROM cat.categoria_raee c WHERE c.codigo = p_categoria AND c.activo
    AND NOT EXISTS (SELECT 1 FROM cat.categoria_raee hija WHERE hija.categoria_padre_id = c.id);
  IF v_cat IS NULL THEN RAISE EXCEPTION 'La categoría debe ser una categoría hoja activa' USING ERRCODE = 'EC422'; END IF;
  SELECT id INTO v_marca FROM cat.marca WHERE codigo = p_marca AND activo;
  IF v_marca IS NULL THEN RAISE EXCEPTION 'La marca no existe o está inactiva' USING ERRCODE = 'EC422'; END IF;
  IF length(btrim(coalesce(p_nombre, ''))) NOT BETWEEN 1 AND 120 OR
     (p_anio IS NOT NULL AND p_anio NOT BETWEEN 1970 AND 2100) OR (p_peso IS NOT NULL AND p_peso <= 0) THEN
    RAISE EXCEPTION 'Nombre, año o peso del modelo inválido' USING ERRCODE = 'EC422';
  END IF;
  INSERT INTO cat.modelo_equipo(categoria_id, marca_id, nombre, anio_lanzamiento, peso_kg, creado_por)
  VALUES (v_cat, v_marca, btrim(p_nombre), p_anio, p_peso, seg.fn_usuario_actual()) RETURNING uid INTO v_uid;
  RETURN v_uid;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Ya existe un modelo con ese nombre y marca' USING ERRCODE = 'EC409';
END $$;

CREATE OR REPLACE FUNCTION api.fn_actualizar_modelo(p_modelo uuid, p_nombre text, p_anio int, p_peso numeric, p_activo boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE m cat.modelo_equipo;
BEGIN
  IF NOT (seg.fn_tiene_permiso(seg.fn_usuario_actual(), 'CATALOGO.ADMINISTRAR') OR
          seg.fn_tiene_permiso(seg.fn_usuario_actual(), 'RED.GESTIONAR')) THEN
    RAISE EXCEPTION 'No tienes permiso para administrar el catálogo' USING ERRCODE = 'EC403';
  END IF;
  SELECT * INTO m FROM cat.modelo_equipo WHERE uid = p_modelo FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Modelo no encontrado' USING ERRCODE = 'EC404'; END IF;
  IF now() >= m.editable_hasta THEN
    RAISE EXCEPTION 'El catálogo % está bloqueado desde %', m.nombre, m.editable_hasta USING ERRCODE = 'EC409';
  END IF;
  IF length(btrim(coalesce(p_nombre, ''))) NOT BETWEEN 1 AND 120 OR p_activo IS NULL OR
     (p_anio IS NOT NULL AND p_anio NOT BETWEEN 1970 AND 2100) OR (p_peso IS NOT NULL AND p_peso <= 0) THEN
    RAISE EXCEPTION 'Nombre, año, peso o estado del modelo inválido' USING ERRCODE = 'EC422';
  END IF;
  UPDATE cat.modelo_equipo SET nombre = btrim(p_nombre), anio_lanzamiento = p_anio, peso_kg = p_peso,
    activo = p_activo, actualizado_en = now() WHERE id = m.id;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Ya existe un modelo con ese nombre y marca' USING ERRCODE = 'EC409';
END $$;

CREATE OR REPLACE FUNCTION api.fn_reabrir_modelo(p_modelo uuid, p_motivo text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE m cat.modelo_equipo;
BEGIN
  PERFORM seg.fn_exigir_permiso(seg.fn_usuario_actual(), 'CATALOGO.ADMINISTRAR');
  IF length(btrim(coalesce(p_motivo, ''))) NOT BETWEEN 5 AND 300 THEN
    RAISE EXCEPTION 'El motivo debe tener entre 5 y 300 caracteres' USING ERRCODE = 'EC422';
  END IF;
  SELECT * INTO m FROM cat.modelo_equipo WHERE uid = p_modelo FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Modelo no encontrado' USING ERRCODE = 'EC404'; END IF;
  UPDATE cat.modelo_equipo SET editable_hasta = now() + interval '24 hours', actualizado_en = now() WHERE id = m.id;
  INSERT INTO cat.modelo_reapertura(modelo_id, motivo, usuario_id) VALUES (m.id, btrim(p_motivo), seg.fn_usuario_actual());
END $$;
REVOKE ALL ON FUNCTION api.fn_crear_modelo(text,text,text,int,numeric), api.fn_actualizar_modelo(uuid,text,int,numeric,boolean),
  api.fn_reabrir_modelo(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION api.fn_crear_modelo(text,text,text,int,numeric), api.fn_actualizar_modelo(uuid,text,int,numeric,boolean),
  api.fn_reabrir_modelo(uuid,text) TO ecoraee_app;

-- La tabla de dispositivos copia el ecosistema y si la serie participa en la unicidad.
-- Un trigger los deriva del objeto padre, que se bloquea al escribir; el índice único
-- parcial arbitra también escrituras simultáneas y libera la serie al anular el objeto.
ALTER TABLE trz.dispositivo DROP CONSTRAINT IF EXISTS dispositivo_marca_id_numero_serie_key;
ALTER TABLE trz.dispositivo ADD COLUMN IF NOT EXISTS ecosistema_serie_id bigint REFERENCES seg.ecosistema(id),
  ADD COLUMN IF NOT EXISTS serie_vigente boolean NOT NULL DEFAULT true;
COMMENT ON COLUMN trz.dispositivo.ecosistema_serie_id IS 'Ecosistema copiado del objeto para imponer unicidad concurrente de la serie.';
COMMENT ON COLUMN trz.dispositivo.serie_vigente IS 'Indica si el objeto no está anulado y su serie cuenta para la unicidad.';
COMMENT ON COLUMN trz.dispositivo.numero_serie IS 'Serie normalizada, única en el ecosistema para objetos no anulados.';

-- Los datos históricos de demostración son sintéticos: se conservan las series válidas
-- y se asigna un identificador determinista a las inválidas, faltantes o duplicadas.
DO $$
DECLARE r record; v_serie text; v_candidata text; v_sufijo int;
BEGIN
  CREATE TEMP TABLE IF NOT EXISTS series_migradas_17 (ecosistema_id bigint, serie text, PRIMARY KEY (ecosistema_id, serie)) ON COMMIT DROP;
  TRUNCATE series_migradas_17;
  FOR r IN SELECT d.objeto_id, d.numero_serie, d.contiene_almacenamiento, o.ecosistema_id, e.codigo AS estado
      FROM trz.dispositivo d JOIN trz.objeto_trazable o ON o.id = d.objeto_id
      JOIN cat.estado_trazabilidad e ON e.id = o.estado_actual_id ORDER BY d.objeto_id LOOP
    v_serie := nullif(upper(btrim(r.numero_serie)), '');
    IF (v_serie IS NOT NULL AND v_serie !~ '^[A-Z0-9][A-Z0-9./-]{3,39}$') OR
       (v_serie IS NULL AND r.contiene_almacenamiento) OR
       (r.estado <> 'ANULADO' AND v_serie IS NOT NULL AND EXISTS
         (SELECT 1 FROM series_migradas_17 WHERE ecosistema_id = r.ecosistema_id AND serie = v_serie)) THEN
      v_sufijo := 0;
      LOOP
        v_candidata := 'MIG-' || r.objeto_id::text || '-' || v_sufijo::text;
        EXIT WHEN NOT EXISTS (SELECT 1 FROM trz.dispositivo d JOIN trz.objeto_trazable o ON o.id = d.objeto_id
                               WHERE o.ecosistema_id = r.ecosistema_id AND d.objeto_id <> r.objeto_id
                                 AND upper(btrim(d.numero_serie)) = v_candidata)
                  AND NOT EXISTS (SELECT 1 FROM series_migradas_17 WHERE ecosistema_id = r.ecosistema_id AND serie = v_candidata);
        v_sufijo := v_sufijo + 1;
      END LOOP;
      v_serie := v_candidata;
    END IF;
    UPDATE trz.dispositivo SET numero_serie = v_serie, ecosistema_serie_id = r.ecosistema_id,
      serie_vigente = (r.estado <> 'ANULADO') WHERE objeto_id = r.objeto_id;
    IF r.estado <> 'ANULADO' AND v_serie IS NOT NULL THEN
      INSERT INTO series_migradas_17 VALUES (r.ecosistema_id, v_serie);
    END IF;
  END LOOP;
END $$;
ALTER TABLE trz.dispositivo ALTER COLUMN ecosistema_serie_id SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_dispositivo_serie_ecosistema ON trz.dispositivo(ecosistema_serie_id, numero_serie)
  WHERE serie_vigente AND numero_serie IS NOT NULL;

CREATE OR REPLACE FUNCTION trz.fn_normalizar_serie() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_estado text;
BEGIN
  SELECT o.ecosistema_id, e.codigo INTO NEW.ecosistema_serie_id, v_estado
    FROM trz.objeto_trazable o JOIN cat.estado_trazabilidad e ON e.id = o.estado_actual_id
   WHERE o.id = NEW.objeto_id FOR UPDATE OF o;
  IF NOT FOUND THEN RAISE EXCEPTION 'El objeto no existe' USING ERRCODE = 'EC404'; END IF;
  NEW.serie_vigente := v_estado <> 'ANULADO';
  NEW.numero_serie := nullif(upper(btrim(NEW.numero_serie)), '');
  IF NEW.numero_serie IS NOT NULL AND NEW.numero_serie !~ '^[A-Z0-9][A-Z0-9./-]{3,39}$' THEN
    RAISE EXCEPTION 'Número de serie inválido: use de 4 a 40 letras, números, punto, guion o barra, comenzando por letra o número' USING ERRCODE = 'EC422';
  END IF;
  IF NEW.contiene_almacenamiento AND NEW.numero_serie IS NULL THEN
    RAISE EXCEPTION 'El número de serie es obligatorio para equipos con almacenamiento' USING ERRCODE = 'EC422';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS tg_normalizar_serie ON trz.dispositivo;
CREATE TRIGGER tg_normalizar_serie BEFORE INSERT OR UPDATE ON trz.dispositivo
  FOR EACH ROW EXECUTE FUNCTION trz.fn_normalizar_serie();

CREATE OR REPLACE FUNCTION trz.fn_sincronizar_serie_objeto() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_serie text; v_codigo text; v_restriccion text;
BEGIN
  IF NEW.estado_actual_id IS DISTINCT FROM OLD.estado_actual_id OR NEW.ecosistema_id IS DISTINCT FROM OLD.ecosistema_id THEN
    BEGIN
      UPDATE trz.dispositivo SET ecosistema_serie_id = NEW.ecosistema_id WHERE objeto_id = NEW.id;
    EXCEPTION WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
      IF v_restriccion <> 'ux_dispositivo_serie_ecosistema' THEN RAISE; END IF;
      SELECT d.numero_serie INTO v_serie FROM trz.dispositivo d WHERE d.objeto_id = NEW.id;
      SELECT o.codigo INTO v_codigo FROM trz.dispositivo d JOIN trz.objeto_trazable o ON o.id = d.objeto_id
       WHERE d.ecosistema_serie_id = NEW.ecosistema_id AND d.numero_serie = v_serie AND d.serie_vigente AND d.objeto_id <> NEW.id LIMIT 1;
      RAISE EXCEPTION 'Ya existe un equipo con el número de serie % (código %)', v_serie, v_codigo USING ERRCODE = 'EC409';
    END;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS tg_sincronizar_serie_objeto ON trz.objeto_trazable;
CREATE TRIGGER tg_sincronizar_serie_objeto AFTER UPDATE OF estado_actual_id, ecosistema_id ON trz.objeto_trazable
  FOR EACH ROW EXECUTE FUNCTION trz.fn_sincronizar_serie_objeto();
REVOKE ALL ON FUNCTION trz.fn_normalizar_serie(), trz.fn_sincronizar_serie_objeto() FROM PUBLIC;

-- Al agregar el último parámetro opcional se cambia la firma sin dejar sobrecargas ambiguas.
DROP FUNCTION IF EXISTS api.fn_registrar_dispositivo(text,text,numeric,boolean,text,text,text,integer,jsonb,uuid,uuid);
DROP FUNCTION IF EXISTS api.fn_actualizar_dispositivo(uuid,numeric,boolean,text,text,text,integer,jsonb,text);
CREATE OR REPLACE FUNCTION api.fn_registrar_dispositivo(
  p_codigo text, p_categoria text, p_peso_kg numeric, p_contiene_almacenamiento boolean DEFAULT false,
  p_marca text DEFAULT NULL, p_modelo text DEFAULT NULL, p_numero_serie text DEFAULT NULL, p_anio integer DEFAULT NULL,
  p_atributos jsonb DEFAULT '{}'::jsonb, p_organizacion_origen uuid DEFAULT NULL, p_componente_de uuid DEFAULT NULL, p_modelo_uid uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_usuario bigint := seg.fn_usuario_actual(); v_eco bigint := seg.fn_ecosistema_actual();
  v_org bigint := current_setting('app.organizacion_id')::bigint; v_cat cat.categoria_raee; v_req jsonb;
  v_id bigint; v_uid uuid; v_marca integer; v_modelo integer; v_catalogo cat.modelo_equipo; v_restriccion text; v_codigo text; v_reg smallint := cat.fn_id('estado_trazabilidad','REGISTRADO');
BEGIN
  PERFORM seg.fn_exigir_permiso(v_usuario, 'OBJETO.REGISTRAR');
  IF p_organizacion_origen IS NOT NULL THEN
    SELECT id INTO v_org FROM org.organizacion WHERE uid = p_organizacion_origen AND ecosistema_id = v_eco;
    IF v_org IS NULL THEN RAISE EXCEPTION 'Organización de origen inexistente' USING ERRCODE = 'EC404'; END IF;
    IF v_org <> current_setting('app.organizacion_id')::bigint AND NOT seg.fn_tiene_permiso(v_usuario, 'RECEPCION.REGISTRAR') THEN
      RAISE EXCEPTION 'Un generador solo registra equipos de su propia organización' USING ERRCODE = 'EC403';
    END IF;
  END IF;
  SELECT * INTO v_cat FROM cat.categoria_raee WHERE codigo = p_categoria AND activo;
  IF NOT FOUND THEN RAISE EXCEPTION 'Categoría % no existe', p_categoria USING ERRCODE = 'EC404'; END IF;
  -- atributos obligatorios: esquema de la categoría o del ancestro más cercano que lo defina
  SELECT c.esquema_atributos -> 'required' INTO v_req FROM cat.categoria_raee c
   WHERE v_cat.ruta <@ c.ruta AND c.esquema_atributos ? 'required' ORDER BY c.nivel DESC LIMIT 1;
  IF v_req IS NOT NULL AND NOT p_atributos ?& ARRAY(SELECT jsonb_array_elements_text(v_req)) THEN
    RAISE EXCEPTION 'Faltan atributos obligatorios para %: %', p_categoria, v_req USING ERRCODE = 'EC422';
  END IF;
  IF p_marca IS NOT NULL THEN v_marca := cat.fn_id('marca', p_marca); END IF;
  IF p_modelo_uid IS NOT NULL THEN
    SELECT * INTO v_catalogo FROM cat.modelo_equipo WHERE uid = p_modelo_uid AND activo;
    IF NOT FOUND OR v_catalogo.categoria_id <> v_cat.id OR (v_marca IS NOT NULL AND v_catalogo.marca_id <> v_marca) THEN
      RAISE EXCEPTION 'El modelo no corresponde a la categoría o marca del equipo' USING ERRCODE = 'EC422';
    END IF;
    v_modelo := v_catalogo.id; v_marca := v_catalogo.marca_id;
  ELSIF p_modelo IS NOT NULL THEN
    SELECT id INTO v_modelo FROM cat.modelo_equipo WHERE nombre = p_modelo AND marca_id = v_marca AND categoria_id = v_cat.id;
  END IF;

  INSERT INTO trz.objeto_trazable(ecosistema_id, codigo, tipo_objeto, organizacion_origen_id, estado_actual_id, registrado_por)
  VALUES (v_eco, p_codigo, 'DISPOSITIVO', v_org, v_reg, v_usuario) RETURNING id, uid INTO v_id, v_uid;
  BEGIN
  INSERT INTO trz.dispositivo(objeto_id, categoria_id, marca_id, modelo_id, modelo_libre, numero_serie, anio_fabricacion, peso_kg,
                              contiene_almacenamiento, atributos, componente_de_id)
  VALUES (v_id, v_cat.id, v_marca, v_modelo, CASE WHEN v_modelo IS NULL THEN nullif(btrim(p_modelo), '') END, p_numero_serie, p_anio, p_peso_kg,
          p_contiene_almacenamiento OR v_cat.contiene_almacenamiento, p_atributos,
          CASE WHEN p_componente_de IS NOT NULL THEN trz.fn_id(p_componente_de) END);
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
    IF v_restriccion <> 'ux_dispositivo_serie_ecosistema' THEN RAISE; END IF;
    SELECT o.codigo INTO v_codigo FROM trz.dispositivo d JOIN trz.objeto_trazable o ON o.id = d.objeto_id
     WHERE d.ecosistema_serie_id = v_eco AND d.serie_vigente AND d.numero_serie = upper(btrim(p_numero_serie)) LIMIT 1;
    RAISE EXCEPTION 'Ya existe un equipo con el número de serie % (código %)', upper(btrim(p_numero_serie)), v_codigo USING ERRCODE = 'EC409';
  END;
  INSERT INTO trz.historial_estado(objeto_id, estado_destino_id, usuario_id, canal, observacion)
  VALUES (v_id, v_reg, v_usuario, coalesce(nullif(current_setting('app.canal', true), ''), 'WEB'), 'Registro inicial');
  RETURN v_uid;
END $$;

CREATE OR REPLACE FUNCTION api.fn_actualizar_dispositivo(
  p_objeto uuid, p_peso_kg numeric, p_contiene_almacenamiento boolean, p_marca text, p_modelo text,
  p_numero_serie text, p_anio integer, p_atributos jsonb, p_motivo text, p_modelo_uid uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE o trz.objeto_trazable := trz.fn_exigir_registrado(trz.fn_id(p_objeto)); v_cat cat.categoria_raee; v_req jsonb;
        v_marca integer; v_modelo integer; v_doc bigint; v_catalogo cat.modelo_equipo; v_restriccion text; v_codigo text;
BEGIN
  IF length(btrim(coalesce(p_motivo, ''))) < 5 THEN RAISE EXCEPTION 'Indica qué corriges y por qué' USING ERRCODE = 'EC422'; END IF;
  SELECT c.* INTO v_cat FROM cat.categoria_raee c JOIN trz.dispositivo d ON d.categoria_id = c.id WHERE d.objeto_id = o.id;
  IF v_cat.id IS NULL THEN RAISE EXCEPTION 'Solo los dispositivos se editan; un lote se desagrupa' USING ERRCODE = 'EC422'; END IF;
  SELECT c.esquema_atributos -> 'required' INTO v_req FROM cat.categoria_raee c
   WHERE v_cat.ruta <@ c.ruta AND c.esquema_atributos ? 'required' ORDER BY c.nivel DESC LIMIT 1;
  IF v_req IS NOT NULL AND NOT coalesce(p_atributos, '{}') ?& ARRAY(SELECT jsonb_array_elements_text(v_req)) THEN
    RAISE EXCEPTION 'Faltan atributos obligatorios para %: %', v_cat.codigo, v_req USING ERRCODE = 'EC422';
  END IF;
  IF p_marca IS NOT NULL THEN v_marca := cat.fn_id('marca', p_marca); END IF;
  IF p_modelo_uid IS NOT NULL THEN
    SELECT * INTO v_catalogo FROM cat.modelo_equipo WHERE uid = p_modelo_uid AND activo;
    IF NOT FOUND OR v_catalogo.categoria_id <> v_cat.id OR (v_marca IS NOT NULL AND v_catalogo.marca_id <> v_marca) THEN
      RAISE EXCEPTION 'El modelo no corresponde a la categoría o marca del equipo' USING ERRCODE = 'EC422';
    END IF;
    v_modelo := v_catalogo.id; v_marca := v_catalogo.marca_id;
  ELSIF p_modelo IS NOT NULL THEN
    SELECT id INTO v_modelo FROM cat.modelo_equipo WHERE nombre = p_modelo AND marca_id = v_marca AND categoria_id = v_cat.id;
  END IF;
  BEGIN
  UPDATE trz.dispositivo SET peso_kg = p_peso_kg,
         contiene_almacenamiento = coalesce(p_contiene_almacenamiento, false) OR v_cat.contiene_almacenamiento,
         marca_id = v_marca, modelo_id = v_modelo, modelo_libre = CASE WHEN v_modelo IS NULL THEN nullif(btrim(p_modelo), '') END, numero_serie = nullif(btrim(p_numero_serie), ''), anio_fabricacion = p_anio,
         atributos = coalesce(p_atributos, '{}')
   WHERE objeto_id = o.id;
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
    IF v_restriccion <> 'ux_dispositivo_serie_ecosistema' THEN RAISE; END IF;
    SELECT ob.codigo INTO v_codigo FROM trz.dispositivo d JOIN trz.objeto_trazable ob ON ob.id = d.objeto_id
     WHERE d.ecosistema_serie_id = o.ecosistema_id AND d.serie_vigente AND d.numero_serie = upper(btrim(p_numero_serie))
       AND d.objeto_id <> o.id LIMIT 1;
    RAISE EXCEPTION 'Ya existe un equipo con el número de serie % (código %)', upper(btrim(p_numero_serie)), v_codigo USING ERRCODE = 'EC409';
  END;
  -- el motivo queda en un documento de ajuste vinculado al equipo (se ve en su ficha); la auditoría guarda el antes y el después
  v_doc := ops.fn_nuevo_documento('AJUSTE', NULL, o.organizacion_origen_id, NULL, 'Corrección de datos: ' || btrim(p_motivo));
  INSERT INTO ops.documento_item(documento_id, objeto_id) VALUES (v_doc, o.id);
  PERFORM ops.fn_cerrar_documento(v_doc);
END $$;
REVOKE ALL ON FUNCTION api.fn_registrar_dispositivo(text,text,numeric,boolean,text,text,text,integer,jsonb,uuid,uuid,uuid),
  api.fn_actualizar_dispositivo(uuid,numeric,boolean,text,text,text,integer,jsonb,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION api.fn_registrar_dispositivo(text,text,numeric,boolean,text,text,text,integer,jsonb,uuid,uuid,uuid),
  api.fn_actualizar_dispositivo(uuid,numeric,boolean,text,text,text,integer,jsonb,text,uuid) TO ecoraee_app;
-- La herramienta MCP de registro ya tenía permiso sobre la firma anterior.
GRANT EXECUTE ON FUNCTION api.fn_registrar_dispositivo(text,text,numeric,boolean,text,text,text,integer,jsonb,uuid,uuid,uuid) TO ecoraee_mcp;

CREATE OR REPLACE VIEW api.v1_dispositivo WITH (security_invoker = true) AS
SELECT o.uid, o.codigo, c.codigo AS categoria, c.nombre AS categoria_nombre, ma.nombre AS marca, coalesce(mo.nombre, d.modelo_libre)::varchar(120) AS modelo,
       d.numero_serie, d.anio_fabricacion, d.peso_kg, d.contiene_almacenamiento, d.atributos,
       (SELECT p.codigo FROM trz.objeto_trazable p WHERE p.id = d.componente_de_id) AS componente_de,
       EXISTS (SELECT 1 FROM evd.evidencia_vinculo v JOIN evd.evidencia e ON e.id = v.evidencia_id
                 JOIN cat.tipo_evidencia te ON te.id = e.tipo_evidencia_id
                WHERE v.objeto_id = o.id AND te.codigo = 'CERTIFICADO_BORRADO' AND e.estado = 'ACTIVA') AS tiene_certificado_borrado,
       mo.uid AS modelo_uid, (d.modelo_id IS NOT NULL) AS modelo_en_catalogo
  FROM trz.dispositivo d
  JOIN trz.objeto_trazable o ON o.id = d.objeto_id
  JOIN cat.categoria_raee c ON c.id = d.categoria_id
  LEFT JOIN cat.marca ma ON ma.id = d.marca_id
  LEFT JOIN cat.modelo_equipo mo ON mo.id = d.modelo_id;

CREATE OR REPLACE VIEW api.v1_objeto_operativo WITH (security_invoker = true) AS
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
       o.ecosistema_id, coalesce(mo.nombre, d.modelo_libre)::varchar(120) AS modelo, mo.uid AS modelo_uid,
       (d.modelo_id IS NOT NULL) AS modelo_en_catalogo, d.numero_serie
  FROM trz.objeto_trazable o
  JOIN cat.estado_trazabilidad e ON e.id = o.estado_actual_id
  JOIN org.organizacion og ON og.id = o.organizacion_origen_id
  LEFT JOIN cat.clasificacion_tecnica k ON k.id = o.clasificacion_actual_id
  LEFT JOIN trz.dispositivo d ON d.objeto_id = o.id
  LEFT JOIN cat.categoria_raee c ON c.id = d.categoria_id
  LEFT JOIN cat.marca ma ON ma.id = d.marca_id
  LEFT JOIN cat.modelo_equipo mo ON mo.id = d.modelo_id
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

-- Las fotos de equipo heredan la visibilidad del objeto y las descargas quedan en RN-07.
INSERT INTO cat.tipo_evidencia(codigo, nombre, nivel_acceso, retencion_meses, mime_permitidos)
VALUES ('FOTO_EQUIPO', 'Fotografía del equipo', 'INTERNO', 24, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (codigo) DO UPDATE SET mime_permitidos = EXCLUDED.mime_permitidos;
UPDATE cat.tipo_evidencia SET mime_permitidos = array_append(mime_permitidos, 'image/webp')
 WHERE codigo LIKE 'FOTO%' AND NOT ('image/webp' = ANY(mime_permitidos));
INSERT INTO evd.politica_acceso(rol_id, tipo_evidencia_id, proposito_id, puede_descargar)
SELECT r.id, t.id, p.id, true FROM seg.rol r CROSS JOIN cat.tipo_evidencia t CROSS JOIN cat.proposito_uso p
 WHERE t.codigo = 'FOTO_EQUIPO' AND p.codigo = 'TRAZABILIDAD'
ON CONFLICT (rol_id, tipo_evidencia_id, proposito_id) DO NOTHING;
DROP POLICY IF EXISTS p_foto_equipo_objeto ON evd.evidencia;
CREATE POLICY p_foto_equipo_objeto ON evd.evidencia AS RESTRICTIVE USING (
  tipo_evidencia_id <> (SELECT id FROM cat.tipo_evidencia WHERE codigo = 'FOTO_EQUIPO') OR
  EXISTS (SELECT 1 FROM evd.evidencia_vinculo v JOIN trz.objeto_trazable o ON o.id = v.objeto_id
           WHERE v.evidencia_id = evidencia.id)
);
CREATE OR REPLACE FUNCTION api.fn_registrar_evidencia(p_tipo text, p_bucket text, p_clave text, p_sha256 text, p_mime text,
                                           p_tamano bigint, p_metadatos_limpios boolean, p_objeto uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); te cat.tipo_evidencia; v_id bigint; v_uid uuid; v_objeto bigint; v_origen bigint; v_tipo text;
BEGIN
  PERFORM seg.fn_exigir_permiso(v_usuario, 'EVIDENCIA.CARGAR');
  SELECT * INTO te FROM cat.tipo_evidencia WHERE codigo = p_tipo AND activo;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tipo de evidencia % no existe', p_tipo USING ERRCODE = 'EC404'; END IF;
  IF NOT p_mime = ANY(te.mime_permitidos) THEN
    RAISE EXCEPTION 'Formato % no permitido para %', p_mime, p_tipo USING ERRCODE = 'EC422';
  END IF;
  IF p_mime LIKE 'image/%' AND NOT p_metadatos_limpios THEN
    RAISE EXCEPTION 'RNF-10: las fotografías deben subirse sin metadatos EXIF/GPS' USING ERRCODE = 'EC422';
  END IF;
  IF p_mime LIKE 'image/%' AND p_tamano > 10485760 THEN
    RAISE EXCEPTION 'La imagen supera el límite de 10 MB' USING ERRCODE = 'EC422';
  END IF;
  IF p_tipo = 'FOTO_EQUIPO' THEN
    IF p_objeto IS NULL THEN RAISE EXCEPTION 'La foto debe estar asociada a un equipo' USING ERRCODE = 'EC422'; END IF;
    SELECT id, organizacion_origen_id, tipo_objeto INTO v_objeto, v_origen, v_tipo FROM trz.objeto_trazable
      WHERE uid = p_objeto AND ecosistema_id = seg.fn_ecosistema_actual() FOR UPDATE;
    IF NOT FOUND OR NOT seg.fn_ve_objeto(v_objeto, v_origen) THEN
      RAISE EXCEPTION 'Equipo no encontrado o sin acceso' USING ERRCODE = 'EC404';
    END IF;
    IF v_tipo <> 'DISPOSITIVO' THEN RAISE EXCEPTION 'La foto debe estar asociada a un equipo' USING ERRCODE = 'EC422'; END IF;
    IF (SELECT count(*) FROM evd.evidencia_vinculo v JOIN evd.evidencia e ON e.id = v.evidencia_id
        JOIN cat.tipo_evidencia t ON t.id = e.tipo_evidencia_id
        WHERE v.objeto_id = v_objeto AND t.codigo = 'FOTO_EQUIPO' AND e.estado = 'ACTIVA') >= 5 THEN
      RAISE EXCEPTION 'Un equipo admite como máximo 5 fotos' USING ERRCODE = 'EC422';
    END IF;
  END IF;
  INSERT INTO evd.evidencia(ecosistema_id, tipo_evidencia_id, s3_bucket, s3_clave, sha256, mime, tamano_bytes, nivel_acceso,
                            metadatos_limpios, subido_por, retener_hasta)
  VALUES (seg.fn_ecosistema_actual(), te.id, p_bucket, p_clave, p_sha256, p_mime, p_tamano, te.nivel_acceso,
          p_metadatos_limpios, v_usuario, (current_date + make_interval(months => te.retencion_meses))::date)
  RETURNING id, uid INTO v_id, v_uid;
  IF p_objeto IS NOT NULL THEN
    INSERT INTO evd.evidencia_vinculo(evidencia_id, objeto_id, vinculado_por) VALUES (v_id, trz.fn_id(p_objeto), v_usuario);
  END IF;
  RETURN v_uid;
END $$;

CREATE OR REPLACE FUNCTION api.fn_obtener_evidencia(p_evidencia uuid, p_proposito text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); e evd.evidencia; v_prop smallint := cat.fn_id('proposito_uso', p_proposito);
        v_ok boolean;
BEGIN
  SELECT * INTO e FROM evd.evidencia WHERE uid = p_evidencia AND ecosistema_id = seg.fn_ecosistema_actual() AND estado = 'ACTIVA';
  IF NOT FOUND THEN RAISE EXCEPTION 'Evidencia no encontrada' USING ERRCODE = 'EC404'; END IF;
  SELECT EXISTS (SELECT 1 FROM evd.politica_acceso p JOIN seg.fn_roles_efectivos(v_usuario) r ON r.rol_id = p.rol_id
                  WHERE p.tipo_evidencia_id = e.tipo_evidencia_id AND p.proposito_id = v_prop AND p.puede_descargar) INTO v_ok;
  IF EXISTS (SELECT 1 FROM cat.tipo_evidencia t WHERE t.id = e.tipo_evidencia_id AND t.codigo = 'FOTO_EQUIPO') THEN
    v_ok := v_ok AND EXISTS (SELECT 1 FROM evd.evidencia_vinculo v JOIN trz.objeto_trazable o ON o.id = v.objeto_id
      WHERE v.evidencia_id = e.id AND o.ecosistema_id = seg.fn_ecosistema_actual()
        AND seg.fn_ve_objeto(o.id, o.organizacion_origen_id));
  END IF;
  INSERT INTO evd.acceso_evidencia(evidencia_id, usuario_id, proposito_id, resultado, canal)
  VALUES (e.id, v_usuario, v_prop, CASE WHEN v_ok THEN 'PERMITIDO' ELSE 'DENEGADO' END,
          coalesce(nullif(current_setting('app.canal', true), ''), 'WEB'));
  IF NOT v_ok THEN
    INSERT INTO aud.evento_seguridad(tipo, usuario_id, detalle, request_id)
    VALUES ('ACCESO_DENEGADO', v_usuario, jsonb_build_object('evidencia', e.uid, 'proposito', p_proposito),
            nullif(current_setting('app.request_id', true), ''));
    RETURN jsonb_build_object('permitido', false);
  END IF;
  RETURN jsonb_build_object('permitido', true, 'bucket', e.s3_bucket, 'clave', e.s3_clave, 'version', e.s3_version_id,
                            'sha256', e.sha256, 'ttl_segundos', 300);        -- la API firma una URL de 5 minutos
END $$;

DO $$ BEGIN
  IF to_regprocedure('meta.fn_sincronizar_diccionario()') IS NOT NULL THEN PERFORM meta.fn_sincronizar_diccionario(); END IF;
END $$;
