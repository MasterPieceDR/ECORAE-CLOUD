-- =====================================================================
-- EcoRAEE Cloud · Script 13: editor de escenarios y solicitudes de rol
-- Se ejecuta después del 10 (y del 11), en una sola transacción: psql -1 -f 13_mejoras.sql
--   A) Escenarios "qué pasaría si": crear un escenario derivado y ajustar capacidades,
--      oferta y demanda sin tocar la red vigente ni los escenarios aprobados del capítulo.
--   B) Solicitud de acceso: un usuario nuevo pide un rol y el administrador la aprueba o rechaza.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A. EDITOR DE ESCENARIOS
-- ---------------------------------------------------------------------
-- Regla: solo se editan escenarios en BORRADOR. E0–E4 están APROBADOS (son los del capítulo y sus
-- resultados están verificados), así que para probar cambios se crea un escenario derivado de uno de ellos.
CREATE FUNCTION red.fn_escenario_editable(p_codigo text) RETURNS red.escenario_red
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE e red.escenario_red; v_u bigint := seg.fn_usuario_actual();
BEGIN
  IF NOT (seg.fn_tiene_permiso(v_u, 'RED.EJECUTAR_FLUJO') OR seg.fn_tiene_permiso(v_u, 'GOBIERNO.DECIDIR')) THEN
    RAISE EXCEPTION 'Acceso denegado: el usuario % no tiene el permiso RED.EJECUTAR_FLUJO', v_u USING ERRCODE = 'EC403';
  END IF;
  SELECT * INTO e FROM red.escenario_red WHERE codigo = upper(p_codigo) AND ecosistema_id = seg.fn_ecosistema_actual();
  IF e.id IS NULL THEN RAISE EXCEPTION 'Escenario % no existe', p_codigo USING ERRCODE = 'EC404'; END IF;
  IF e.estado <> 'BORRADOR' THEN
    RAISE EXCEPTION 'El escenario % está %: crea un escenario derivado para probar cambios', e.codigo, lower(e.estado) USING ERRCODE = 'EC409';
  END IF;
  RETURN e;
END $$;

CREATE FUNCTION api.fn_crear_escenario(p_codigo text, p_nombre text, p_base text, p_descripcion text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_u bigint := seg.fn_usuario_actual(); b red.escenario_red; v_codigo text := upper(btrim(p_codigo));
BEGIN
  IF NOT (seg.fn_tiene_permiso(v_u, 'RED.EJECUTAR_FLUJO') OR seg.fn_tiene_permiso(v_u, 'GOBIERNO.DECIDIR')) THEN
    RAISE EXCEPTION 'Acceso denegado: el usuario % no tiene el permiso RED.EJECUTAR_FLUJO', v_u USING ERRCODE = 'EC403';
  END IF;
  IF v_codigo !~ '^[A-Z][A-Z0-9_-]{1,19}$' THEN
    RAISE EXCEPTION 'Código de escenario inválido: usa letras, números y guiones (p. ej. E5 o PRUEBA-1)' USING ERRCODE = 'EC422';
  END IF;
  IF coalesce(btrim(p_nombre), '') = '' THEN RAISE EXCEPTION 'El escenario necesita un nombre' USING ERRCODE = 'EC422'; END IF;
  SELECT * INTO b FROM red.escenario_red WHERE codigo = upper(p_base) AND ecosistema_id = seg.fn_ecosistema_actual();
  IF b.id IS NULL THEN RAISE EXCEPTION 'Escenario base % no existe', p_base USING ERRCODE = 'EC404'; END IF;
  INSERT INTO red.escenario_red(ecosistema_id, codigo, nombre, descripcion, escenario_base_id, fecha_referencia, unidad_id, periodo, estado, creado_por)
  VALUES (b.ecosistema_id, v_codigo, btrim(p_nombre), p_descripcion, b.id, now(), b.unidad_id, b.periodo, 'BORRADOR', v_u);
  RETURN v_codigo;
END $$;

-- Capacidad o actividad de una arista en el escenario. Ambos NULL = quitar el ajuste (vuelve a heredar de la base).
CREATE FUNCTION api.fn_ajustar_escenario_arista(p_escenario text, p_origen text, p_destino text,
                                                p_capacidad numeric, p_activa boolean, p_motivo text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE e red.escenario_red := red.fn_escenario_editable(p_escenario); v_arista bigint;
BEGIN
  SELECT a.id INTO v_arista FROM red.arista a JOIN red.nodo o ON o.id = a.nodo_origen_id JOIN red.nodo d ON d.id = a.nodo_destino_id
   WHERE o.codigo = p_origen AND d.codigo = p_destino AND a.ecosistema_id = e.ecosistema_id;
  IF v_arista IS NULL THEN RAISE EXCEPTION 'La arista % → % no existe en la red', p_origen, p_destino USING ERRCODE = 'EC404'; END IF;
  IF p_capacidad IS NOT NULL AND (p_capacidad < 0 OR p_capacidad > 100000) THEN
    RAISE EXCEPTION 'La capacidad debe estar entre 0 y 100000' USING ERRCODE = 'EC422';
  END IF;
  IF p_capacidad IS NULL AND p_activa IS NULL THEN
    DELETE FROM red.escenario_arista WHERE escenario_id = e.id AND arista_id = v_arista;
    RETURN;
  END IF;
  IF coalesce(btrim(p_motivo), '') = '' THEN RAISE EXCEPTION 'Explica el motivo del ajuste' USING ERRCODE = 'EC422'; END IF;
  INSERT INTO red.escenario_arista(escenario_id, arista_id, capacidad_ajustada, activa, motivo)
  VALUES (e.id, v_arista, p_capacidad, p_activa, btrim(p_motivo))
  ON CONFLICT (escenario_id, arista_id) DO UPDATE SET capacidad_ajustada = EXCLUDED.capacidad_ajustada,
                                                     activa = EXCLUDED.activa, motivo = EXCLUDED.motivo;
END $$;

-- Procesamiento, oferta o demanda de un nodo en el escenario. Los tres NULL = quitar el ajuste.
CREATE FUNCTION api.fn_ajustar_escenario_nodo(p_escenario text, p_nodo text, p_capacidad numeric, p_oferta numeric, p_demanda numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE e red.escenario_red := red.fn_escenario_editable(p_escenario); v_nodo bigint;
BEGIN
  SELECT id INTO v_nodo FROM red.nodo WHERE codigo = p_nodo AND ecosistema_id = e.ecosistema_id;
  IF v_nodo IS NULL THEN RAISE EXCEPTION 'El nodo % no existe en la red', p_nodo USING ERRCODE = 'EC404'; END IF;
  IF least(p_capacidad, p_oferta, p_demanda) < 0 OR greatest(p_capacidad, p_oferta, p_demanda) > 100000 THEN
    RAISE EXCEPTION 'Los valores deben estar entre 0 y 100000' USING ERRCODE = 'EC422';
  END IF;
  IF num_nonnulls(p_capacidad, p_oferta, p_demanda) = 0 THEN
    DELETE FROM red.escenario_nodo WHERE escenario_id = e.id AND nodo_id = v_nodo;
    RETURN;
  END IF;
  INSERT INTO red.escenario_nodo(escenario_id, nodo_id, capacidad_ajustada, oferta, demanda)
  VALUES (e.id, v_nodo, p_capacidad, p_oferta, p_demanda)
  ON CONFLICT (escenario_id, nodo_id) DO UPDATE SET capacidad_ajustada = EXCLUDED.capacidad_ajustada,
                                                   oferta = EXCLUDED.oferta, demanda = EXCLUDED.demanda;
END $$;

-- Borrar un borrador que nadie usa (sin ejecuciones registradas ni escenarios derivados)
CREATE FUNCTION api.fn_eliminar_escenario(p_escenario text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE e red.escenario_red := red.fn_escenario_editable(p_escenario);
BEGIN
  IF EXISTS (SELECT 1 FROM red.ejecucion_flujo WHERE escenario_id = e.id) THEN
    RAISE EXCEPTION 'El escenario tiene ejecuciones registradas: se conserva como evidencia' USING ERRCODE = 'EC409';
  END IF;
  IF EXISTS (SELECT 1 FROM red.escenario_red WHERE escenario_base_id = e.id) THEN
    RAISE EXCEPTION 'Otro escenario hereda de este' USING ERRCODE = 'EC409';
  END IF;
  DELETE FROM red.escenario_arista WHERE escenario_id = e.id;
  DELETE FROM red.escenario_nodo WHERE escenario_id = e.id;
  DELETE FROM red.escenario_red WHERE id = e.id;
END $$;

COMMENT ON FUNCTION api.fn_crear_escenario(text, text, text, text) IS 'Crea un escenario BORRADOR que hereda de otro (análisis qué pasaría si).';
COMMENT ON FUNCTION api.fn_ajustar_escenario_arista(text, text, text, numeric, boolean, text) IS 'Sobrescribe capacidad/actividad de una arista en un escenario BORRADOR; NULL,NULL quita el ajuste.';
COMMENT ON FUNCTION api.fn_ajustar_escenario_nodo(text, text, numeric, numeric, numeric) IS 'Sobrescribe procesamiento, oferta o demanda de un nodo en un escenario BORRADOR; NULL = hereda.';

-- ---------------------------------------------------------------------
-- B. SOLICITUDES DE ROL
-- ---------------------------------------------------------------------
CREATE TABLE seg.solicitud_rol (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  uid           uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  ecosistema_id bigint NOT NULL REFERENCES seg.ecosistema(id),
  usuario_id    bigint NOT NULL REFERENCES seg.usuario(id),
  rol_id        smallint NOT NULL REFERENCES seg.rol(id),
  centro_id     bigint REFERENCES org.centro(id),
  motivo        varchar(500) NOT NULL CHECK (length(btrim(motivo)) >= 10),
  estado        varchar(10) NOT NULL DEFAULT 'PENDIENTE' CHECK (estado IN ('PENDIENTE','APROBADA','RECHAZADA','CANCELADA')),
  creado_en     timestamptz NOT NULL DEFAULT now(),
  resuelto_por  bigint REFERENCES seg.usuario(id),
  resuelto_en   timestamptz,
  respuesta     varchar(500),
  CHECK ((estado = 'PENDIENTE') = (resuelto_en IS NULL)),
  CHECK (resuelto_por IS NULL OR resuelto_por <> usuario_id)          -- nadie aprueba su propia solicitud
);
-- una sola solicitud abierta por usuario, rol y alcance
CREATE UNIQUE INDEX ux_solicitud_rol_pendiente ON seg.solicitud_rol (usuario_id, rol_id, coalesce(centro_id, 0)) WHERE estado = 'PENDIENTE';
CREATE INDEX ix_solicitud_rol_estado ON seg.solicitud_rol (ecosistema_id, estado, creado_en);
COMMENT ON TABLE seg.solicitud_rol IS 'Pedido de un usuario para recibir un rol; lo resuelve un administrador (mínimo privilegio en el autorregistro).';
COMMENT ON COLUMN seg.solicitud_rol.motivo IS 'Por qué necesita el rol (quién es, para qué organización o centro).';
COMMENT ON COLUMN seg.solicitud_rol.respuesta IS 'Comentario del administrador al aprobar o rechazar.';

CREATE FUNCTION api.fn_solicitar_rol(p_rol text, p_centro text, p_motivo text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_u bigint := seg.fn_usuario_actual(); v_rol smallint; v_centro bigint; v_uid uuid;
BEGIN
  IF v_u IS NULL THEN RAISE EXCEPTION 'Inicia sesión para solicitar un rol' USING ERRCODE = 'EC401'; END IF;
  SELECT id INTO v_rol FROM seg.rol WHERE codigo = p_rol AND activo AND NOT es_servicio AND codigo <> 'USUARIO_BASE';
  IF v_rol IS NULL THEN RAISE EXCEPTION 'Rol % no se puede solicitar', p_rol USING ERRCODE = 'EC422'; END IF;
  IF p_centro IS NOT NULL THEN v_centro := org.fn_centro(p_centro); END IF;
  IF length(btrim(coalesce(p_motivo, ''))) < 10 THEN
    RAISE EXCEPTION 'Explica en al menos 10 caracteres para qué necesitas el rol' USING ERRCODE = 'EC422';
  END IF;
  IF EXISTS (SELECT 1 FROM seg.usuario_rol WHERE usuario_id = v_u AND rol_id = v_rol AND vigencia @> now()
               AND centro_id IS NOT DISTINCT FROM v_centro) THEN
    RAISE EXCEPTION 'Ya tienes ese rol' USING ERRCODE = 'EC409';
  END IF;
  INSERT INTO seg.solicitud_rol(ecosistema_id, usuario_id, rol_id, centro_id, motivo)
  VALUES (seg.fn_ecosistema_actual(), v_u, v_rol, v_centro, btrim(p_motivo)) RETURNING uid INTO v_uid;
  INSERT INTO aud.evento_seguridad(tipo, usuario_id, detalle, request_id)
  VALUES ('CAMBIO_ROL', v_u, jsonb_build_object('rol', p_rol, 'centro', p_centro, 'accion', 'SOLICITAR', 'solicitud', v_uid),
          nullif(current_setting('app.request_id', true), ''));
  RETURN v_uid;
END $$;

CREATE FUNCTION api.fn_cancelar_solicitud_rol(p_solicitud uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  UPDATE seg.solicitud_rol SET estado = 'CANCELADA', resuelto_en = now()
   WHERE uid = p_solicitud AND usuario_id = seg.fn_usuario_actual() AND estado = 'PENDIENTE';
  IF NOT FOUND THEN RAISE EXCEPTION 'No tienes una solicitud pendiente con ese identificador' USING ERRCODE = 'EC404'; END IF;
END $$;

-- Aprobar asigna el rol con api.fn_asignar_rol, así que se aplican las mismas reglas: permiso, motivo,
-- nadie se asigna roles a sí mismo y segregación de funciones (roles incompatibles).
CREATE FUNCTION api.fn_resolver_solicitud_rol(p_solicitud uuid, p_aprobar boolean, p_respuesta text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_admin bigint := seg.fn_usuario_actual(); s seg.solicitud_rol; v_usuario uuid; v_rol text; v_centro text;
BEGIN
  PERFORM seg.fn_exigir_permiso(v_admin, 'USUARIO.ADMINISTRAR');
  SELECT * INTO s FROM seg.solicitud_rol WHERE uid = p_solicitud AND ecosistema_id = seg.fn_ecosistema_actual() FOR UPDATE;
  IF s.id IS NULL THEN RAISE EXCEPTION 'Solicitud no encontrada' USING ERRCODE = 'EC404'; END IF;
  IF s.estado <> 'PENDIENTE' THEN RAISE EXCEPTION 'La solicitud ya fue %', lower(s.estado) USING ERRCODE = 'EC409'; END IF;
  IF NOT p_aprobar AND length(btrim(coalesce(p_respuesta, ''))) < 5 THEN
    RAISE EXCEPTION 'Al rechazar, explica el motivo' USING ERRCODE = 'EC422';
  END IF;
  IF p_aprobar THEN
    SELECT u.uid INTO v_usuario FROM seg.usuario u WHERE u.id = s.usuario_id;
    SELECT codigo INTO v_rol FROM seg.rol WHERE id = s.rol_id;
    SELECT codigo INTO v_centro FROM org.centro WHERE id = s.centro_id;
    PERFORM api.fn_asignar_rol(v_usuario, v_rol, v_centro, 'Solicitud aprobada: ' || coalesce(nullif(btrim(p_respuesta), ''), s.motivo));
  END IF;
  UPDATE seg.solicitud_rol SET estado = CASE WHEN p_aprobar THEN 'APROBADA' ELSE 'RECHAZADA' END,
         resuelto_por = v_admin, resuelto_en = now(), respuesta = nullif(btrim(p_respuesta), '')
   WHERE id = s.id;
END $$;

-- Lista: el administrador ve todas las del ecosistema; cualquier otro usuario, solo las suyas.
CREATE FUNCTION api.fn_solicitudes_rol(p_solo_pendientes boolean DEFAULT false) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'uid', s.uid, 'usuario', u.uid, 'alias', u.alias, 'organizacion', o.nombre, 'rol', r.codigo, 'rol_nombre', r.nombre,
           'centro', c.codigo, 'motivo', s.motivo, 'estado', s.estado, 'creado_en', s.creado_en,
           'resuelto_en', s.resuelto_en, 'resuelto_por', (SELECT alias FROM seg.usuario WHERE id = s.resuelto_por), 'respuesta', s.respuesta)
         ORDER BY (s.estado = 'PENDIENTE') DESC, s.creado_en DESC), '[]')
    FROM seg.solicitud_rol s JOIN seg.usuario u ON u.id = s.usuario_id JOIN org.organizacion o ON o.id = u.organizacion_id
    JOIN seg.rol r ON r.id = s.rol_id LEFT JOIN org.centro c ON c.id = s.centro_id
   WHERE s.ecosistema_id = seg.fn_ecosistema_actual()
     AND (s.usuario_id = seg.fn_usuario_actual() OR seg.fn_tiene_permiso(seg.fn_usuario_actual(), 'USUARIO.ADMINISTRAR'))
     AND (NOT p_solo_pendientes OR s.estado = 'PENDIENTE')
$$;

-- ---------------------------------------------------------------------
-- C. SEGURIDAD, AUDITORÍA Y DICCIONARIO
-- ---------------------------------------------------------------------
DO $$
DECLARE v_cols text;
BEGIN
  SELECT string_agg(quote_literal(a.attname), ',') INTO v_cols
    FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
   WHERE i.indrelid = 'seg.solicitud_rol'::regclass AND i.indisprimary;
  EXECUTE format('CREATE TRIGGER tg_auditoria AFTER INSERT OR UPDATE OR DELETE ON seg.solicitud_rol FOR EACH ROW EXECUTE FUNCTION aud.fn_auditar(%s)', v_cols);
END $$;

ALTER TABLE seg.solicitud_rol ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_solicitud_rol ON seg.solicitud_rol USING (ecosistema_id = seg.fn_ecosistema_actual());
REVOKE ALL ON seg.solicitud_rol FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION red.fn_escenario_editable(text), api.fn_crear_escenario(text, text, text, text),
  api.fn_ajustar_escenario_arista(text, text, text, numeric, boolean, text), api.fn_ajustar_escenario_nodo(text, text, numeric, numeric, numeric),
  api.fn_eliminar_escenario(text), api.fn_solicitar_rol(text, text, text), api.fn_cancelar_solicitud_rol(uuid),
  api.fn_resolver_solicitud_rol(uuid, boolean, text), api.fn_solicitudes_rol(boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION red.fn_escenario_editable(text), api.fn_crear_escenario(text, text, text, text),
  api.fn_ajustar_escenario_arista(text, text, text, numeric, boolean, text), api.fn_ajustar_escenario_nodo(text, text, numeric, numeric, numeric),
  api.fn_eliminar_escenario(text), api.fn_solicitar_rol(text, text, text), api.fn_cancelar_solicitud_rol(uuid),
  api.fn_resolver_solicitud_rol(uuid, boolean, text), api.fn_solicitudes_rol(boolean) TO ecoraee_app;

-- diccionario de datos (si existe el sincronizador del script 10)
DO $$ BEGIN
  IF to_regprocedure('meta.fn_sincronizar_diccionario()') IS NOT NULL THEN PERFORM meta.fn_sincronizar_diccionario(); END IF;
END $$;
