-- =====================================================================
-- Script 02: lógica de dominio — utilidades, auditoría, seguridad,
-- máquina de estados, inventario, reglas RN-01…RN-09
-- Códigos de error propios (mapeables a HTTP en la API):
--   EC401 sin contexto · EC403 sin permiso · EC404 no encontrado
--   EC409 transición/estado inválido · EC422 regla de negocio violada
-- =====================================================================
SET client_min_messages = warning;
CREATE SCHEMA IF NOT EXISTS util;

-- ---------------------------------------------------------------------
-- 1. Utilidades genéricas
-- ---------------------------------------------------------------------
CREATE FUNCTION util.fn_marcar_version() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.actualizado_en  := now();
  NEW.version         := OLD.version + 1;
  NEW.actualizado_por := nullif(current_setting('app.usuario_id', true), '')::bigint;
  RETURN NEW;
END $$;

CREATE FUNCTION util.fn_marcar_creacion() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.creado_por := coalesce(NEW.creado_por, nullif(current_setting('app.usuario_id', true), '')::bigint);
  RETURN NEW;
END $$;

CREATE FUNCTION util.fn_inmutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'La tabla %.% es de solo inserción (registro histórico inmutable)', TG_TABLE_SCHEMA, TG_TABLE_NAME
    USING ERRCODE = 'EC422', HINT = 'RN-01 / RNF-04: el historial no se edita ni se elimina';
END $$;

-- Evita ciclos en jerarquías padre-hijo (TG_ARGV: columna pk, columna padre)
CREATE FUNCTION util.fn_evitar_ciclo() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_pk bigint; v_padre bigint; v_ciclo boolean;
BEGIN
  v_pk    := (to_jsonb(NEW) ->> TG_ARGV[0])::bigint;
  v_padre := (to_jsonb(NEW) ->> TG_ARGV[1])::bigint;
  IF v_padre IS NULL THEN RETURN NEW; END IF;
  EXECUTE format($q$
    WITH RECURSIVE sube(id, padre, n) AS (
      SELECT %1$I::bigint, %4$I::bigint, 1 FROM %2$I.%3$I WHERE %1$I = $1
      UNION ALL
      SELECT t.%1$I::bigint, t.%4$I::bigint, s.n + 1 FROM %2$I.%3$I t JOIN sube s ON t.%1$I = s.padre WHERE s.n < 100)
    SELECT EXISTS (SELECT 1 FROM sube WHERE id = $2)$q$,
    TG_ARGV[0], TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_ARGV[1]) INTO v_ciclo USING v_padre, v_pk;
  IF v_ciclo THEN
    RAISE EXCEPTION 'Ciclo detectado en %.%: % no puede descender de sí mismo', TG_TABLE_SCHEMA, TG_TABLE_NAME, v_pk
      USING ERRCODE = 'EC422';
  END IF;
  RETURN NEW;
END $$;

-- Ruta ltree para árboles (TG_ARGV[0] = columna padre). Detecta ciclos y propaga a descendientes.
CREATE FUNCTION util.fn_ruta_jerarquica() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_padre bigint; v_ruta_padre ltree;
BEGIN
  v_padre := (to_jsonb(NEW) ->> TG_ARGV[0])::bigint;
  IF v_padre IS NULL THEN
    NEW.ruta := text2ltree(NEW.id::text);
  ELSE
    EXECUTE format('SELECT ruta FROM %I.%I WHERE id = $1', TG_TABLE_SCHEMA, TG_TABLE_NAME) INTO v_ruta_padre USING v_padre;
    IF v_ruta_padre ~ ('*.' || NEW.id || '.*')::lquery THEN
      RAISE EXCEPTION 'Ciclo detectado en %.%: el nodo % ya es ancestro de su nuevo padre', TG_TABLE_SCHEMA, TG_TABLE_NAME, NEW.id
        USING ERRCODE = 'EC422';
    END IF;
    NEW.ruta := v_ruta_padre || text2ltree(NEW.id::text);
  END IF;
  NEW.nivel := nlevel(NEW.ruta);
  RETURN NEW;
END $$;

CREATE FUNCTION util.fn_propagar_ruta() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.ruta IS DISTINCT FROM OLD.ruta THEN
    EXECUTE format('UPDATE %I.%I SET %I = %I WHERE %I = $1', TG_TABLE_SCHEMA, TG_TABLE_NAME,
                   TG_ARGV[0], TG_ARGV[0], TG_ARGV[0]) USING NEW.id;
  END IF;
  RETURN NULL;
END $$;

CREATE TRIGGER tg_ruta BEFORE INSERT OR UPDATE OF categoria_padre_id ON cat.categoria_raee
  FOR EACH ROW EXECUTE FUNCTION util.fn_ruta_jerarquica('categoria_padre_id');
CREATE TRIGGER tg_ruta_propaga AFTER UPDATE OF categoria_padre_id ON cat.categoria_raee
  FOR EACH ROW EXECUTE FUNCTION util.fn_propagar_ruta('categoria_padre_id');
CREATE TRIGGER tg_ruta BEFORE INSERT OR UPDATE OF ubicacion_padre_id ON org.ubicacion
  FOR EACH ROW EXECUTE FUNCTION util.fn_ruta_jerarquica('ubicacion_padre_id');
CREATE TRIGGER tg_ruta_propaga AFTER UPDATE OF ubicacion_padre_id ON org.ubicacion
  FOR EACH ROW EXECUTE FUNCTION util.fn_propagar_ruta('ubicacion_padre_id');

-- La ubicación hija debe pertenecer al mismo centro que su padre
CREATE FUNCTION org.fn_ubicacion_mismo_centro() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.ubicacion_padre_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM org.ubicacion p WHERE p.id = NEW.ubicacion_padre_id AND p.centro_id = NEW.centro_id) THEN
    RAISE EXCEPTION 'La ubicación padre pertenece a otro centro' USING ERRCODE = 'EC422';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tg_mismo_centro BEFORE INSERT OR UPDATE ON org.ubicacion
  FOR EACH ROW EXECUTE FUNCTION org.fn_ubicacion_mismo_centro();

CREATE TRIGGER tg_ciclo BEFORE INSERT OR UPDATE OF organizacion_padre_id ON org.organizacion
  FOR EACH ROW EXECUTE FUNCTION util.fn_evitar_ciclo('id','organizacion_padre_id');
CREATE TRIGGER tg_ciclo BEFORE INSERT OR UPDATE OF rol_padre_id ON seg.rol
  FOR EACH ROW EXECUTE FUNCTION util.fn_evitar_ciclo('id','rol_padre_id');
CREATE TRIGGER tg_ciclo BEFORE INSERT OR UPDATE OF escenario_base_id ON red.escenario_red
  FOR EACH ROW EXECUTE FUNCTION util.fn_evitar_ciclo('id','escenario_base_id');
CREATE TRIGGER tg_ciclo BEFORE INSERT OR UPDATE OF componente_de_id ON trz.dispositivo
  FOR EACH ROW EXECUTE FUNCTION util.fn_evitar_ciclo('objeto_id','componente_de_id');
CREATE TRIGGER tg_ciclo BEFORE INSERT OR UPDATE OF documento_referencia_id ON ops.documento_operativo
  FOR EACH ROW EXECUTE FUNCTION util.fn_evitar_ciclo('id','documento_referencia_id');
CREATE TRIGGER tg_ciclo BEFORE INSERT OR UPDATE OF sustituida_por_id ON gob.decision_arquitectura
  FOR EACH ROW EXECUTE FUNCTION util.fn_evitar_ciclo('id','sustituida_por_id');

-- Versionado optimista y sellos de creación
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['org.organizacion','org.centro','seg.usuario','trz.objeto_trazable','ops.documento_operativo'] LOOP
    EXECUTE format('CREATE TRIGGER tg_version BEFORE UPDATE ON %s FOR EACH ROW EXECUTE FUNCTION util.fn_marcar_version()', t);
    EXECUTE format('CREATE TRIGGER tg_creacion BEFORE INSERT ON %s FOR EACH ROW EXECUTE FUNCTION util.fn_marcar_creacion()', t);
  END LOOP;
END $$;

-- Tablas de solo inserción
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['trz.historial_estado','inv.movimiento_inventario','aud.log_cambio','aud.sello_integridad',
                           'evd.acceso_evidencia','mcp.invocacion','aud.evento_seguridad'] LOOP
    EXECUTE format('CREATE TRIGGER tg_inmutable BEFORE UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION util.fn_inmutable()', t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 2. Auditoría técnica genérica (historia de transacción, as-of)
-- ---------------------------------------------------------------------
CREATE FUNCTION aud.fn_auditar() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_old jsonb; v_new jsonb; v_fila jsonb; v_pk jsonb := '{}'::jsonb; v_campos text[]; k text;
BEGIN
  IF TG_OP <> 'INSERT' THEN v_old := to_jsonb(OLD); END IF;
  IF TG_OP <> 'DELETE' THEN v_new := to_jsonb(NEW); END IF;
  v_fila := coalesce(v_new, v_old);
  FOREACH k IN ARRAY TG_ARGV LOOP v_pk := v_pk || jsonb_build_object(k, v_fila -> k); END LOOP;
  IF TG_OP = 'UPDATE' THEN
    SELECT array_agg(n.key ORDER BY n.key) INTO v_campos
      FROM jsonb_each(v_new) n
     WHERE n.value IS DISTINCT FROM v_old -> n.key AND n.key NOT IN ('actualizado_en','version','actualizado_por');
    IF v_campos IS NULL THEN RETURN NULL; END IF;
  END IF;
  INSERT INTO aud.log_cambio(esquema, tabla, operacion, pk, datos_antes, datos_despues, campos_cambiados,
                             usuario_id, canal, request_id, hash_registro)
  VALUES (TG_TABLE_SCHEMA, TG_TABLE_NAME, left(TG_OP,1), v_pk, v_old, v_new, v_campos,
          nullif(current_setting('app.usuario_id', true), '')::bigint,
          nullif(current_setting('app.canal', true), ''),
          nullif(current_setting('app.request_id', true), ''),
          encode(digest(concat_ws('|', TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, v_pk::text,
                                  v_old::text, v_new::text, txid_current()::text, clock_timestamp()::text), 'sha256'), 'hex'));
  RETURN NULL;
END $$;

-- Adjunta la auditoría a todas las tablas de negocio usando su PK real
DO $$
DECLARE r record; v_cols text;
BEGIN
  FOR r IN
    SELECT c.oid, n.nspname, c.relname
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relkind IN ('r','p') AND NOT c.relispartition
       AND n.nspname IN ('cat','seg','org','trz','ops','evd','red','gob','ind','mcp')
       AND (n.nspname || '.' || c.relname) NOT IN
           ('trz.historial_estado','evd.acceso_evidencia','mcp.invocacion','ind.medicion_indicador',
            'red.resultado_flujo_arista','red.corte_minimo','red.corte_minimo_arista','ops.secuencia_documento')
  LOOP
    SELECT string_agg(quote_literal(a.attname), ',' ORDER BY array_position(i.indkey, a.attnum))
      INTO v_cols
      FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
     WHERE i.indrelid = r.oid AND i.indisprimary;
    EXECUTE format('CREATE TRIGGER tg_auditoria AFTER INSERT OR UPDATE OR DELETE ON %I.%I
                    FOR EACH ROW EXECUTE FUNCTION aud.fn_auditar(%s)', r.nspname, r.relname, v_cols);
  END LOOP;
END $$;

-- Reconstrucción "as-of": estado de una fila en un instante dado
CREATE FUNCTION aud.fn_estado_en(p_esquema name, p_tabla name, p_pk jsonb, p_instante timestamptz)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN l.operacion = 'D' THEN NULL ELSE l.datos_despues END
    FROM aud.log_cambio l
   WHERE l.esquema = p_esquema AND l.tabla = p_tabla AND l.pk = p_pk AND l.ocurrido_en <= p_instante
   ORDER BY l.ocurrido_en DESC, l.id DESC
   LIMIT 1
$$;

-- Sellado periódico encadenado (evidencia de no manipulación sin cuello de botella por fila)
CREATE FUNCTION aud.fn_sellar_periodo(p_desde timestamptz, p_hasta timestamptz)
RETURNS aud.sello_integridad LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_hash text; v_n bigint; v_prev text; v_sello aud.sello_integridad;
BEGIN
  SELECT count(*), encode(digest(coalesce(string_agg(hash_registro, '' ORDER BY id), ''), 'sha256'), 'hex')
    INTO v_n, v_hash
    FROM aud.log_cambio WHERE ocurrido_en >= p_desde AND ocurrido_en < p_hasta;
  SELECT hash_periodo INTO v_prev FROM aud.sello_integridad ORDER BY upper(periodo) DESC LIMIT 1;
  INSERT INTO aud.sello_integridad(periodo, registros, hash_periodo, hash_sello_anterior)
  VALUES (tstzrange(p_desde, p_hasta), v_n,
          encode(digest(v_hash || coalesce(v_prev, ''), 'sha256'), 'hex'), v_prev)
  RETURNING * INTO v_sello;
  RETURN v_sello;
END $$;

CREATE FUNCTION aud.fn_verificar_sello(p_sello_id bigint) RETURNS boolean
LANGUAGE plpgsql STABLE SET search_path = pg_catalog, public AS $$
DECLARE s aud.sello_integridad; v_hash text;
BEGIN
  SELECT * INTO s FROM aud.sello_integridad WHERE id = p_sello_id;
  SELECT encode(digest(coalesce(string_agg(hash_registro, '' ORDER BY id), ''), 'sha256'), 'hex') INTO v_hash
    FROM aud.log_cambio WHERE ocurrido_en <@ s.periodo;
  RETURN encode(digest(v_hash || coalesce(s.hash_sello_anterior, ''), 'sha256'), 'hex') = s.hash_periodo;
END $$;

-- ---------------------------------------------------------------------
-- 3. Contexto de sesión y autorización (RBAC jerárquico con alcance)
-- ---------------------------------------------------------------------
CREATE FUNCTION seg.fn_usuario_actual() RETURNS bigint LANGUAGE plpgsql STABLE AS $$
DECLARE v text := nullif(current_setting('app.usuario_id', true), '');
BEGIN
  IF v IS NULL THEN
    RAISE EXCEPTION 'No hay usuario en el contexto de la transacción' USING ERRCODE = 'EC401',
      HINT = 'Llame a api.fn_iniciar_contexto() al inicio de cada transacción';
  END IF;
  RETURN v::bigint;
END $$;

CREATE FUNCTION seg.fn_ecosistema_actual() RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('app.ecosistema_id', true), '')::bigint
$$;

CREATE FUNCTION seg.fn_roles_efectivos(p_usuario bigint, p_centro bigint DEFAULT NULL)
RETURNS TABLE (rol_id smallint) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  WITH RECURSIVE asignados AS (
    SELECT ur.rol_id
      FROM seg.usuario_rol ur JOIN seg.usuario u ON u.id = ur.usuario_id
     WHERE ur.usuario_id = p_usuario AND u.estado = 'ACTIVO' AND u.eliminado_en IS NULL
       AND ur.vigencia @> now()
       AND (ur.centro_id IS NULL OR p_centro IS NULL OR ur.centro_id = p_centro)
  ), arbol AS (                                    -- un rol hereda los permisos de sus ancestros
    SELECT r.id, r.rol_padre_id FROM seg.rol r JOIN asignados a ON a.rol_id = r.id WHERE r.activo
    UNION
    SELECT p.id, p.rol_padre_id FROM seg.rol p JOIN arbol h ON h.rol_padre_id = p.id WHERE p.activo
  )
  SELECT id FROM arbol
$$;

CREATE FUNCTION seg.fn_tiene_permiso(p_usuario bigint, p_permiso text, p_centro bigint DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT EXISTS (
    SELECT 1 FROM seg.fn_roles_efectivos(p_usuario, p_centro) r
      JOIN seg.rol_permiso rp ON rp.rol_id = r.rol_id
      JOIN seg.permiso p ON p.id = rp.permiso_id
     WHERE p.codigo = p_permiso)
$$;

CREATE FUNCTION seg.fn_exigir_permiso(p_usuario bigint, p_permiso text, p_centro bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF NOT seg.fn_tiene_permiso(p_usuario, p_permiso, p_centro) THEN
    RAISE EXCEPTION 'Acceso denegado: el usuario % no tiene el permiso % %', p_usuario, p_permiso,
      coalesce('en el centro ' || p_centro, '') USING ERRCODE = 'EC403';
  END IF;
END $$;

CREATE FUNCTION seg.fn_tiene_rol(p_usuario bigint, p_rol text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT EXISTS (SELECT 1 FROM seg.fn_roles_efectivos(p_usuario) r JOIN seg.rol x ON x.id = r.rol_id WHERE x.codigo = p_rol)
$$;

-- Segregación de funciones al asignar roles
CREATE FUNCTION seg.fn_validar_segregacion() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_conflicto text;
BEGIN
  SELECT ra.codigo || ' / ' || rb.codigo || ': ' || s.motivo INTO v_conflicto
    FROM seg.usuario_rol ur
    JOIN seg.segregacion_funciones s ON (s.rol_a_id = ur.rol_id AND s.rol_b_id = NEW.rol_id)
                                     OR (s.rol_b_id = ur.rol_id AND s.rol_a_id = NEW.rol_id)
    JOIN seg.rol ra ON ra.id = s.rol_a_id JOIN seg.rol rb ON rb.id = s.rol_b_id
   WHERE ur.usuario_id = NEW.usuario_id AND ur.id IS DISTINCT FROM NEW.id AND ur.vigencia && NEW.vigencia
   LIMIT 1;
  IF v_conflicto IS NOT NULL THEN
    RAISE EXCEPTION 'Segregación de funciones: roles incompatibles (%)', v_conflicto USING ERRCODE = 'EC422';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tg_sod BEFORE INSERT OR UPDATE ON seg.usuario_rol
  FOR EACH ROW EXECUTE FUNCTION seg.fn_validar_segregacion();

-- ---------------------------------------------------------------------
-- 4. Objetos trazables: protección de la caché y composición de lotes
-- ---------------------------------------------------------------------
CREATE FUNCTION trz.fn_proteger_objeto() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (NEW.codigo, NEW.tipo_objeto, NEW.ecosistema_id, NEW.organizacion_origen_id, NEW.registrado_en)
     IS DISTINCT FROM (OLD.codigo, OLD.tipo_objeto, OLD.ecosistema_id, OLD.organizacion_origen_id, OLD.registrado_en) THEN
    RAISE EXCEPTION 'RN-01: la identidad de un objeto trazable es inmutable' USING ERRCODE = 'EC422';
  END IF;
  IF (NEW.estado_actual_id, NEW.clasificacion_actual_id, NEW.ubicacion_actual_id, NEW.cerrado_en)
     IS DISTINCT FROM (OLD.estado_actual_id, OLD.clasificacion_actual_id, OLD.ubicacion_actual_id, OLD.cerrado_en)
     AND coalesce(current_setting('ecoraee.cambio_autorizado', true), 'off') <> 'on' THEN
    RAISE EXCEPTION 'Estado, clasificación y ubicación solo cambian mediante las funciones de dominio'
      USING ERRCODE = 'EC422', HINT = 'Use trz.fn_cambiar_estado, api.fn_evaluar o las funciones de inventario';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tg_proteger BEFORE UPDATE ON trz.objeto_trazable
  FOR EACH ROW EXECUTE FUNCTION trz.fn_proteger_objeto();

CREATE FUNCTION trz.fn_actualizar_cache(p_objeto bigint, p_campo text, p_valor bigint)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('ecoraee.cambio_autorizado', 'on', true);
  CASE p_campo
    WHEN 'estado'        THEN UPDATE trz.objeto_trazable SET estado_actual_id = p_valor::smallint WHERE id = p_objeto;
    WHEN 'clasificacion' THEN UPDATE trz.objeto_trazable SET clasificacion_actual_id = p_valor::smallint WHERE id = p_objeto;
    WHEN 'ubicacion'     THEN UPDATE trz.objeto_trazable SET ubicacion_actual_id = p_valor WHERE id = p_objeto;
    WHEN 'cerrado'       THEN UPDATE trz.objeto_trazable SET cerrado_en = now() WHERE id = p_objeto;
  END CASE;
  PERFORM set_config('ecoraee.cambio_autorizado', 'off', true);
END $$;

-- Lote dentro de lote sin ciclos
CREATE FUNCTION trz.fn_validar_composicion() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_ciclo boolean; v_estado text;
BEGIN
  SELECT e.codigo INTO v_estado FROM trz.objeto_trazable o JOIN cat.estado_trazabilidad e ON e.id = o.estado_actual_id
   WHERE o.id = NEW.lote_id;
  IF v_estado IN ('CERRADO','ANULADO') THEN
    RAISE EXCEPTION 'No se puede modificar un lote en estado %', v_estado USING ERRCODE = 'EC409';
  END IF;
  WITH RECURSIVE contenido AS (
    SELECT lc.objeto_id FROM trz.lote_composicion lc WHERE lc.lote_id = NEW.objeto_id AND lc.vigencia @> now()
    UNION
    SELECT lc.objeto_id FROM trz.lote_composicion lc JOIN contenido c ON lc.lote_id = c.objeto_id WHERE lc.vigencia @> now()
  ) SELECT EXISTS (SELECT 1 FROM contenido WHERE objeto_id = NEW.lote_id) INTO v_ciclo;
  IF v_ciclo THEN
    RAISE EXCEPTION 'Ciclo de lotes: el lote % ya está contenido en %', NEW.lote_id, NEW.objeto_id USING ERRCODE = 'EC422';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tg_composicion BEFORE INSERT ON trz.lote_composicion
  FOR EACH ROW EXECUTE FUNCTION trz.fn_validar_composicion();

CREATE FUNCTION trz.fn_validar_genealogia() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_ciclo boolean;
BEGIN
  WITH RECURSIVE descendientes AS (
    SELECT lote_resultante_id AS id FROM trz.lote_genealogia WHERE lote_origen_id = NEW.lote_resultante_id
    UNION
    SELECT g.lote_resultante_id FROM trz.lote_genealogia g JOIN descendientes d ON g.lote_origen_id = d.id
  ) SELECT EXISTS (SELECT 1 FROM descendientes WHERE id = NEW.lote_origen_id) INTO v_ciclo;
  IF v_ciclo THEN
    RAISE EXCEPTION 'Genealogía de lotes con ciclo' USING ERRCODE = 'EC422';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tg_genealogia BEFORE INSERT ON trz.lote_genealogia
  FOR EACH ROW EXECUTE FUNCTION trz.fn_validar_genealogia();

-- Miembros vigentes de un lote (recursivo: incluye sublotes y sus dispositivos)
CREATE FUNCTION trz.fn_miembros(p_lote bigint)
RETURNS TABLE (objeto_id bigint, tipo_objeto varchar, profundidad int) LANGUAGE sql STABLE AS $$
  WITH RECURSIVE m AS (
    SELECT lc.objeto_id, 1 AS prof FROM trz.lote_composicion lc WHERE lc.lote_id = p_lote AND lc.vigencia @> now()
    UNION ALL
    SELECT lc.objeto_id, m.prof + 1 FROM trz.lote_composicion lc JOIN m ON lc.lote_id = m.objeto_id
     WHERE lc.vigencia @> now() AND m.prof < 20
  )
  SELECT m.objeto_id, o.tipo_objeto, m.prof FROM m JOIN trz.objeto_trazable o ON o.id = m.objeto_id
$$;

-- Expande un arreglo de uids (dispositivos y/o lotes) a objetos internos
CREATE FUNCTION trz.fn_expandir(p_uids uuid[])
RETURNS TABLE (objeto_id bigint, tipo_objeto varchar) LANGUAGE plpgsql STABLE AS $$
DECLARE v_faltan int;
BEGIN
  SELECT count(*) INTO v_faltan FROM unnest(p_uids) u
   WHERE NOT EXISTS (SELECT 1 FROM trz.objeto_trazable o WHERE o.uid = u AND o.ecosistema_id = seg.fn_ecosistema_actual());
  IF v_faltan > 0 THEN
    RAISE EXCEPTION '% objeto(s) no existen en el ecosistema actual', v_faltan USING ERRCODE = 'EC404';
  END IF;
  RETURN QUERY
    WITH raiz AS (SELECT o.id, o.tipo_objeto FROM trz.objeto_trazable o WHERE o.uid = ANY(p_uids))
    SELECT r.id, r.tipo_objeto FROM raiz r
    UNION
    SELECT m.objeto_id, m.tipo_objeto FROM raiz r CROSS JOIN LATERAL trz.fn_miembros(r.id) m WHERE r.tipo_objeto = 'LOTE';
END $$;

CREATE FUNCTION trz.fn_id(p_uid uuid) RETURNS bigint LANGUAGE plpgsql STABLE AS $$
DECLARE v bigint;
BEGIN
  SELECT id INTO v FROM trz.objeto_trazable WHERE uid = p_uid AND ecosistema_id = seg.fn_ecosistema_actual();
  IF v IS NULL THEN RAISE EXCEPTION 'Objeto % no encontrado', p_uid USING ERRCODE = 'EC404'; END IF;
  RETURN v;
END $$;

CREATE FUNCTION cat.fn_id(p_tabla text, p_codigo text) RETURNS smallint LANGUAGE plpgsql STABLE AS $$
DECLARE v smallint;
BEGIN
  EXECUTE format('SELECT id::smallint FROM cat.%I WHERE codigo = $1 AND activo', p_tabla) INTO v USING p_codigo;
  IF v IS NULL THEN RAISE EXCEPTION 'Código % no existe en cat.%', p_codigo, p_tabla USING ERRCODE = 'EC404'; END IF;
  RETURN v;
END $$;

-- ---------------------------------------------------------------------
-- 5. Documentos operativos
-- ---------------------------------------------------------------------
CREATE FUNCTION ops.fn_nuevo_documento(p_tipo text, p_centro bigint, p_organizacion bigint,
                                       p_referencia bigint DEFAULT NULL, p_observacion text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_eco bigint := seg.fn_ecosistema_actual(); v_n int; v_id bigint;
        v_anio smallint := extract(year FROM now())::smallint;
        v_pref text := CASE p_tipo WHEN 'SOLICITUD' THEN 'SOL' WHEN 'RECOLECCION' THEN 'RCL' WHEN 'RECEPCION' THEN 'RCP'
                                   WHEN 'EVALUACION' THEN 'EVA' WHEN 'TRANSFERENCIA' THEN 'TRF' WHEN 'TRATAMIENTO' THEN 'TRT'
                                   WHEN 'ASIGNACION' THEN 'ASG' WHEN 'CIERRE' THEN 'CIE' ELSE 'AJU' END;
BEGIN
  INSERT INTO ops.secuencia_documento AS s (ecosistema_id, tipo_documento, anio, ultimo)
  VALUES (v_eco, p_tipo, v_anio, 1)
  ON CONFLICT (ecosistema_id, tipo_documento, anio) DO UPDATE SET ultimo = s.ultimo + 1
  RETURNING ultimo INTO v_n;
  INSERT INTO ops.documento_operativo(ecosistema_id, tipo_documento, numero, centro_id, organizacion_id,
                                      responsable_id, documento_referencia_id, observacion)
  VALUES (v_eco, p_tipo, v_pref || '-' || v_anio || '-' || lpad(v_n::text, 6, '0'), p_centro, p_organizacion,
          seg.fn_usuario_actual(), p_referencia, p_observacion)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE FUNCTION ops.fn_cerrar_documento(p_documento bigint) RETURNS void LANGUAGE sql AS $$
  UPDATE ops.documento_operativo SET estado_documento = 'CERRADO', fecha_cierre = now() WHERE id = p_documento
$$;

CREATE FUNCTION evd.fn_tiene_evidencia(p_documento bigint, p_objeto bigint DEFAULT NULL) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM evd.evidencia_vinculo v JOIN evd.evidencia e ON e.id = v.evidencia_id
                  WHERE e.estado = 'ACTIVA'
                    AND (v.documento_id = p_documento OR (p_objeto IS NOT NULL AND v.objeto_id = p_objeto)))
$$;

-- ---------------------------------------------------------------------
-- 6. Máquina de estados (RN-01, CP-03): relación T parametrizada
-- ---------------------------------------------------------------------
CREATE FUNCTION trz.fn_cambiar_estado(p_objeto bigint, p_destino text, p_documento bigint DEFAULT NULL,
                                      p_observacion text DEFAULT NULL, p_propagar boolean DEFAULT true,
                                      p_centro_alcance bigint DEFAULT NULL)  -- p. ej. centro destino al confirmar un traslado
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_usuario bigint := seg.fn_usuario_actual();
  o trz.objeto_trazable; t cat.transicion_estado; d ops.documento_operativo;
  v_destino smallint := cat.fn_id('estado_trazabilidad', p_destino);
  v_origen_cod text; v_m record;
BEGIN
  SELECT * INTO o FROM trz.objeto_trazable WHERE id = p_objeto FOR UPDATE;   -- bloqueo de fila: serializa cambios
  IF NOT FOUND THEN RAISE EXCEPTION 'Objeto % no existe', p_objeto USING ERRCODE = 'EC404'; END IF;
  SELECT codigo INTO v_origen_cod FROM cat.estado_trazabilidad WHERE id = o.estado_actual_id;

  SELECT * INTO t FROM cat.transicion_estado
   WHERE estado_origen_id = o.estado_actual_id AND estado_destino_id = v_destino AND activo;
  IF p_destino = 'DESAGRUPADO' AND o.tipo_objeto <> 'LOTE' THEN
    RAISE EXCEPTION 'Solo un lote puede desagruparse' USING ERRCODE = 'EC409';
  END IF;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transición no permitida para %: % → %', o.codigo, v_origen_cod, p_destino
      USING ERRCODE = 'EC409', HINT = 'Consulte cat.transicion_estado (relación T del diccionario maestro)';
  END IF;

  IF p_documento IS NOT NULL THEN SELECT * INTO d FROM ops.documento_operativo WHERE id = p_documento; END IF;
  IF t.tipo_documento IS NOT NULL AND (d.id IS NULL OR d.tipo_documento <> t.tipo_documento) THEN
    RAISE EXCEPTION 'La transición % → % requiere un documento %', v_origen_cod, p_destino, t.tipo_documento
      USING ERRCODE = 'EC422', HINT = 'RN-03';
  END IF;

  PERFORM seg.fn_exigir_permiso(v_usuario, t.permiso_requerido, coalesce(p_centro_alcance, d.centro_id));

  IF t.requiere_clasificacion THEN
    IF o.tipo_objeto = 'DISPOSITIVO' AND o.clasificacion_actual_id IS NULL THEN
      RAISE EXCEPTION '% no tiene clasificación técnica vigente', o.codigo USING ERRCODE = 'EC422', HINT = 'RN-02';
    ELSIF o.tipo_objeto = 'LOTE' AND EXISTS (
        SELECT 1 FROM trz.fn_miembros(o.id) m JOIN trz.objeto_trazable x ON x.id = m.objeto_id
         WHERE m.tipo_objeto = 'DISPOSITIVO' AND x.clasificacion_actual_id IS NULL) THEN
      RAISE EXCEPTION 'El lote % contiene dispositivos sin clasificar', o.codigo USING ERRCODE = 'EC422', HINT = 'RN-02';
    END IF;
  END IF;

  IF t.requiere_evidencia AND NOT evd.fn_tiene_evidencia(p_documento, p_objeto) THEN
    RAISE EXCEPTION 'La transición % → % requiere evidencia vinculada', v_origen_cod, p_destino
      USING ERRCODE = 'EC422', HINT = 'RN-03 / RN-08';
  END IF;

  INSERT INTO trz.historial_estado(objeto_id, estado_origen_id, estado_destino_id, transicion_id, documento_id,
                                   usuario_id, canal, observacion)
  VALUES (p_objeto, o.estado_actual_id, v_destino, t.id, p_documento, v_usuario,
          coalesce(nullif(current_setting('app.canal', true), ''), 'WEB'), p_observacion);
  PERFORM trz.fn_actualizar_cache(p_objeto, 'estado', v_destino);

  INSERT INTO integ.outbox_evento(ecosistema_id, agregado, agregado_id, tipo_evento, payload)
  VALUES (o.ecosistema_id, 'OBJETO', o.id, 'objeto.estado_cambiado',
          jsonb_build_object('uid', o.uid, 'codigo', o.codigo, 'de', v_origen_cod, 'a', p_destino,
                             'documento', d.numero, 'en', now()));

  IF o.tipo_objeto = 'LOTE' AND p_propagar AND p_destino <> 'DESAGRUPADO' THEN          -- el lote arrastra a sus miembros directos (y éstos a los suyos)
    FOR v_m IN SELECT lc.objeto_id FROM trz.lote_composicion lc WHERE lc.lote_id = o.id AND lc.vigencia @> now() LOOP
      PERFORM trz.fn_cambiar_estado(v_m.objeto_id, p_destino, p_documento, 'Propagado desde lote ' || o.codigo, true, p_centro_alcance);
    END LOOP;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 7. Inventario: kardex de doble entrada y saldos atómicos (RN-06, CP-05)
-- ---------------------------------------------------------------------
CREATE FUNCTION inv.fn_registrar_movimiento(p_documento bigint, p_objeto bigint, p_ubicacion bigint,
                                            p_sentido smallint, p_tipo text, p_par bigint DEFAULT NULL,
                                            p_clasificacion smallint DEFAULT NULL, p_actualiza_ubicacion boolean DEFAULT true)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_disp trz.dispositivo; v_clas smallint; v_mov bigint; v_filas int;
BEGIN
  SELECT * INTO v_disp FROM trz.dispositivo WHERE objeto_id = p_objeto;
  IF NOT FOUND THEN RETURN NULL; END IF;                          -- los lotes no tienen saldo propio
  v_clas := coalesce(p_clasificacion,
                     (SELECT clasificacion_actual_id FROM trz.objeto_trazable WHERE id = p_objeto),
                     cat.fn_id('clasificacion_tecnica', 'PENDIENTE'));
  INSERT INTO inv.movimiento_inventario(documento_id, objeto_id, ubicacion_id, sentido, tipo_movimiento, unidades,
                                        peso_kg, categoria_id, clasificacion_id, par_movimiento_id, usuario_id)
  VALUES (p_documento, p_objeto, p_ubicacion, p_sentido, p_tipo, 1, v_disp.peso_kg, v_disp.categoria_id, v_clas,
          p_par, seg.fn_usuario_actual())
  RETURNING id INTO v_mov;

  UPDATE inv.saldo_ubicacion
     SET unidades = unidades + p_sentido, peso_kg = peso_kg + p_sentido * v_disp.peso_kg,
         actualizado_en = now(), version = version + 1
   WHERE ubicacion_id = p_ubicacion AND categoria_id = v_disp.categoria_id AND clasificacion_id = v_clas;
  GET DIAGNOSTICS v_filas = ROW_COUNT;
  IF v_filas = 0 THEN
    IF p_sentido < 0 THEN
      RAISE EXCEPTION 'RN-06: saldo insuficiente en la ubicación % para el objeto %', p_ubicacion, p_objeto
        USING ERRCODE = 'EC422';
    END IF;
    INSERT INTO inv.saldo_ubicacion AS s (ubicacion_id, categoria_id, clasificacion_id, unidades, peso_kg)
    VALUES (p_ubicacion, v_disp.categoria_id, v_clas, 1, v_disp.peso_kg)
    ON CONFLICT (ubicacion_id, categoria_id, clasificacion_id)
      DO UPDATE SET unidades = s.unidades + 1, peso_kg = s.peso_kg + EXCLUDED.peso_kg, version = s.version + 1;
  END IF;

  IF p_actualiza_ubicacion THEN
    PERFORM trz.fn_actualizar_cache(p_objeto, 'ubicacion', CASE WHEN p_sentido > 0 THEN p_ubicacion END);
  END IF;
  RETURN v_mov;
END $$;

-- ---------------------------------------------------------------------
-- 8. RN-02: solo técnico autorizado evalúa / cambia clasificación
-- ---------------------------------------------------------------------
CREATE FUNCTION ops.fn_validar_evaluacion() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_centro bigint; v_ruta_cat ltree; v_estado text;
BEGIN
  SELECT d.centro_id INTO v_centro FROM ops.documento_operativo d WHERE d.id = NEW.documento_id;
  IF NOT seg.fn_tiene_permiso(NEW.tecnico_id, 'EVALUACION.REGISTRAR', v_centro) THEN
    RAISE EXCEPTION 'RN-02: el usuario % no es técnico evaluador autorizado en el centro %', NEW.tecnico_id, v_centro
      USING ERRCODE = 'EC403';
  END IF;
  IF NEW.tecnico_id <> seg.fn_usuario_actual() THEN
    RAISE EXCEPTION 'RN-02: la evaluación debe registrarla el propio técnico' USING ERRCODE = 'EC403';
  END IF;
  SELECT c.ruta INTO v_ruta_cat FROM trz.dispositivo d JOIN cat.categoria_raee c ON c.id = d.categoria_id
   WHERE d.objeto_id = NEW.objeto_id;
  IF NOT EXISTS (SELECT 1 FROM seg.habilitacion_tecnica h JOIN cat.categoria_raee c ON c.id = h.categoria_id
                  WHERE h.usuario_id = NEW.tecnico_id AND h.vigencia @> current_date AND v_ruta_cat <@ c.ruta) THEN
    RAISE EXCEPTION 'RN-02: el técnico no tiene habilitación vigente para esta categoría de RAEE' USING ERRCODE = 'EC403';
  END IF;
  SELECT e.codigo INTO v_estado FROM trz.objeto_trazable o JOIN cat.estado_trazabilidad e ON e.id = o.estado_actual_id
   WHERE o.id = NEW.objeto_id;
  IF NEW.modalidad = 'PRECLASIFICACION' AND v_estado <> 'RECIBIDO' THEN
    RAISE EXCEPTION 'La preclasificación solo aplica a objetos recién recibidos' USING ERRCODE = 'EC409';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cat.clasificacion_tecnica WHERE id = NEW.clasificacion_id AND es_resultado_evaluacion) THEN
    RAISE EXCEPTION 'Clasificación no válida como resultado de evaluación' USING ERRCODE = 'EC422';
  END IF;
  UPDATE ops.evaluacion_tecnica SET vigente = false WHERE objeto_id = NEW.objeto_id AND vigente;  -- solo una vigente
  RETURN NEW;
END $$;
CREATE TRIGGER tg_rn02 BEFORE INSERT ON ops.evaluacion_tecnica
  FOR EACH ROW EXECUTE FUNCTION ops.fn_validar_evaluacion();

-- Evaluación inmutable: solo se permite pasar vigente de true a false
CREATE FUNCTION ops.fn_evaluacion_inmutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' OR (to_jsonb(NEW) - 'vigente') <> (to_jsonb(OLD) - 'vigente') OR (NEW.vigente AND NOT OLD.vigente) THEN
    RAISE EXCEPTION 'Una evaluación técnica no se edita: registre una reevaluación' USING ERRCODE = 'EC422', HINT = 'RN-02';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tg_inmutable BEFORE UPDATE OR DELETE ON ops.evaluacion_tecnica
  FOR EACH ROW EXECUTE FUNCTION ops.fn_evaluacion_inmutable();

-- Al insertar: invalida la anterior, actualiza clasificación y reubica el saldo entre clasificaciones
CREATE FUNCTION ops.fn_aplicar_evaluacion() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE o trz.objeto_trazable; v_pend smallint := cat.fn_id('clasificacion_tecnica','PENDIENTE');
BEGIN
  SELECT * INTO o FROM trz.objeto_trazable WHERE id = NEW.objeto_id;
  IF o.ubicacion_actual_id IS NOT NULL AND coalesce(o.clasificacion_actual_id, v_pend) <> NEW.clasificacion_id THEN
    PERFORM inv.fn_registrar_movimiento(NEW.documento_id, o.id, o.ubicacion_actual_id, -1::smallint, 'AJUSTE', NULL,
                                        coalesce(o.clasificacion_actual_id, v_pend), false);
    PERFORM inv.fn_registrar_movimiento(NEW.documento_id, o.id, o.ubicacion_actual_id,  1::smallint, 'AJUSTE', NULL,
                                        NEW.clasificacion_id, false);
  END IF;
  PERFORM trz.fn_actualizar_cache(NEW.objeto_id, 'clasificacion', NEW.clasificacion_id);
  RETURN NULL;
END $$;
CREATE TRIGGER tg_aplicar AFTER INSERT ON ops.evaluacion_tecnica
  FOR EACH ROW EXECUTE FUNCTION ops.fn_aplicar_evaluacion();

CREATE UNIQUE INDEX ux_evaluacion_vigente ON ops.evaluacion_tecnica(objeto_id) WHERE vigente;

-- Criterios obligatorios: se verifica al confirmar la transacción (trigger diferido)
CREATE FUNCTION ops.fn_criterios_completos() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_faltan text;
BEGIN
  SELECT string_agg(c.codigo, ', ') INTO v_faltan
    FROM cat.criterio_evaluacion c
    JOIN trz.dispositivo d ON d.objeto_id = NEW.objeto_id
    JOIN cat.categoria_raee cd ON cd.id = d.categoria_id
    LEFT JOIN cat.categoria_raee cc ON cc.id = c.categoria_id
   WHERE c.activo AND c.obligatorio AND NEW.modalidad <> 'PRECLASIFICACION'
     AND (c.categoria_id IS NULL OR cd.ruta <@ cc.ruta)
     AND NOT EXISTS (SELECT 1 FROM ops.evaluacion_criterio ec WHERE ec.evaluacion_id = NEW.documento_id AND ec.criterio_id = c.id);
  IF v_faltan IS NOT NULL THEN
    RAISE EXCEPTION 'Evaluación incompleta: faltan criterios obligatorios (%)', v_faltan USING ERRCODE = 'EC422';
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER tg_criterios AFTER INSERT ON ops.evaluacion_tecnica
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ops.fn_criterios_completos();

-- ---------------------------------------------------------------------
-- 9. RN-05: capacidad de la arista en el periodo vigente
-- ---------------------------------------------------------------------
CREATE FUNCTION red.fn_validar_capacidad(p_arista bigint, p_unidades numeric, p_peso numeric,
                                         p_instante timestamptz DEFAULT now(), p_excluir_documento bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record; v_ini timestamptz; v_consumo numeric; v_pedido numeric; v_n int := 0;
BEGIN
  FOR c IN SELECT ca.*, u.codigo AS unidad
             FROM red.capacidad_arista ca JOIN cat.unidad_medida u ON u.id = ca.unidad_id
            WHERE ca.arista_id = p_arista AND ca.vigencia @> p_instante
            FOR UPDATE OF ca                       -- serializa transferencias concurrentes sobre la misma arista
  LOOP
    v_n := v_n + 1;
    v_ini := date_trunc(CASE c.periodo WHEN 'DIA' THEN 'day' WHEN 'SEMANA' THEN 'week' ELSE 'month' END, p_instante);
    SELECT coalesce(sum(CASE c.unidad WHEN 'KG' THEN x.peso_kg ELSE x.unidades END), 0) INTO v_consumo
      FROM (SELECT t.documento_id, t.unidades, t.peso_kg FROM ops.transferencia t WHERE t.arista_id = p_arista
              AND t.estado_transferencia <> 'ANULADA'
            UNION ALL
            SELECT r.documento_id, r.unidades, r.peso_kg FROM ops.recoleccion r WHERE r.arista_id = p_arista) x
      JOIN ops.documento_operativo d ON d.id = x.documento_id
     WHERE d.estado_documento <> 'ANULADO'
       AND d.fecha_documento >= v_ini
       AND d.fecha_documento < v_ini + CASE c.periodo WHEN 'DIA' THEN interval '1 day' WHEN 'SEMANA' THEN interval '1 week' ELSE interval '1 month' END
       AND x.documento_id IS DISTINCT FROM p_excluir_documento;
    v_pedido := CASE c.unidad WHEN 'KG' THEN p_peso ELSE p_unidades END;
    IF v_consumo + v_pedido > c.capacidad THEN
      RAISE EXCEPTION 'RN-05: la arista % no tiene capacidad (% %/% usado + % solicitado > %)',
        p_arista, v_consumo, c.unidad, c.periodo, v_pedido, c.capacidad USING ERRCODE = 'EC422';
    END IF;
  END LOOP;
  IF v_n = 0 THEN
    RAISE EXCEPTION 'RN-05: la arista % no tiene capacidad vigente registrada', p_arista USING ERRCODE = 'EC422';
  END IF;
END $$;

-- Arcos válidos según tipos de nodo; los que requieren excepción necesitan una aprobada y vigente
CREATE FUNCTION red.fn_validar_arista() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_regla cat.arista_tipo_permitida; v_to smallint; v_td smallint;
BEGIN
  SELECT tipo_nodo_id INTO v_to FROM red.nodo WHERE id = NEW.nodo_origen_id;
  SELECT tipo_nodo_id INTO v_td FROM red.nodo WHERE id = NEW.nodo_destino_id;
  SELECT * INTO v_regla FROM cat.arista_tipo_permitida WHERE tipo_nodo_origen_id = v_to AND tipo_nodo_destino_id = v_td;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Arco no permitido entre estos tipos de nodo (coherencia grafo ↔ relación T)' USING ERRCODE = 'EC422';
  END IF;
  IF v_regla.requiere_excepcion AND NOT EXISTS (
       SELECT 1 FROM gob.excepcion_regla x WHERE x.id = NEW.excepcion_id AND x.estado = 'APROBADA') THEN
    RAISE EXCEPTION 'Este arco requiere una excepción aprobada por el Comité de Arquitectura' USING ERRCODE = 'EC422';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tg_arista BEFORE INSERT OR UPDATE ON red.arista
  FOR EACH ROW EXECUTE FUNCTION red.fn_validar_arista();

-- ---------------------------------------------------------------------
-- 10. RN-03: un traslado no se cierra con datos incompletos
-- ---------------------------------------------------------------------
CREATE FUNCTION ops.fn_validar_cierre_transferencia() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE d ops.documento_operativo; a red.arista;
BEGIN
  IF NEW.estado_transferencia = 'CERRADA' AND OLD.estado_transferencia <> 'CERRADA' THEN
    SELECT * INTO d FROM ops.documento_operativo WHERE id = NEW.documento_id;
    SELECT * INTO a FROM red.arista WHERE id = NEW.arista_id;
    IF a.nodo_origen_id IS NULL OR a.nodo_destino_id IS NULL OR d.responsable_id IS NULL
       OR NEW.confirmado_por IS NULL OR NEW.recibido_en IS NULL THEN
      RAISE EXCEPTION 'RN-03: el traslado % tiene origen, destino, responsable o confirmación incompletos', d.numero
        USING ERRCODE = 'EC422';
    END IF;
    IF NOT evd.fn_tiene_evidencia(NEW.documento_id) THEN
      RAISE EXCEPTION 'RN-03: el traslado % no tiene evidencia vinculada', d.numero USING ERRCODE = 'EC422';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tg_rn03 BEFORE UPDATE ON ops.transferencia
  FOR EACH ROW EXECUTE FUNCTION ops.fn_validar_cierre_transferencia();

-- ---------------------------------------------------------------------
-- 11. RN-04 y RN-09 (propuesta de Innovación): asignación a beneficiario
-- ---------------------------------------------------------------------
CREATE FUNCTION ops.fn_validar_asignacion() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE o trz.objeto_trazable; v_disp trz.dispositivo; v_reutil smallint := cat.fn_id('tipo_destino','REUTILIZACION');
BEGIN
  SELECT * INTO o FROM trz.objeto_trazable WHERE id = NEW.objeto_id;
  SELECT * INTO v_disp FROM trz.dispositivo WHERE objeto_id = NEW.objeto_id;
  IF o.clasificacion_actual_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM cat.clasificacion_destino_permitido
        WHERE clasificacion_id = o.clasificacion_actual_id AND tipo_destino_id = v_reutil) THEN
    RAISE EXCEPTION 'RN-04: % tiene una clasificación que no admite asignación a beneficiarios', o.codigo
      USING ERRCODE = 'EC422';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM org.organizacion_actor oa JOIN cat.tipo_actor ta ON ta.id = oa.tipo_actor_id
                  WHERE oa.organizacion_id = NEW.beneficiario_id AND ta.codigo = 'BENEFICIARIO' AND oa.vigencia @> current_date) THEN
    RAISE EXCEPTION 'La organización destino no está registrada como beneficiaria vigente' USING ERRCODE = 'EC422';
  END IF;
  IF (v_disp.contiene_almacenamiento OR EXISTS (SELECT 1 FROM ops.evaluacion_tecnica e
                                                 WHERE e.objeto_id = o.id AND e.vigente AND e.requiere_borrado_datos))
     AND NOT EXISTS (SELECT 1 FROM evd.evidencia_vinculo v JOIN evd.evidencia e ON e.id = v.evidencia_id
                       JOIN cat.tipo_evidencia te ON te.id = e.tipo_evidencia_id
                      WHERE v.objeto_id = o.id AND te.codigo = 'CERTIFICADO_BORRADO' AND e.estado = 'ACTIVA') THEN
    RAISE EXCEPTION 'RN-09: % almacena datos y no tiene certificado de borrado seguro', o.codigo USING ERRCODE = 'EC422';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tg_rn04 BEFORE INSERT ON ops.asignacion_beneficiario
  FOR EACH ROW EXECUTE FUNCTION ops.fn_validar_asignacion();

-- ---------------------------------------------------------------------
-- 12. RN-08: cierre con destino final y fecha de confirmación
-- ---------------------------------------------------------------------
CREATE FUNCTION ops.fn_validar_cierre() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE o trz.objeto_trazable; v_estado text; v_destino_esperado smallint;
BEGIN
  SELECT * INTO o FROM trz.objeto_trazable WHERE id = NEW.objeto_id;
  SELECT codigo INTO v_estado FROM cat.estado_trazabilidad WHERE id = o.estado_actual_id;
  IF v_estado NOT IN ('ASIGNADO_BENEFICIARIO','TRATADO') THEN
    RAISE EXCEPTION 'RN-08: % está en estado % y no puede cerrarse', o.codigo, v_estado USING ERRCODE = 'EC409';
  END IF;
  IF NEW.fecha_confirmacion > now() + interval '5 minutes' OR NEW.fecha_confirmacion < o.registrado_en THEN
    RAISE EXCEPTION 'RN-08: fecha de confirmación fuera de rango' USING ERRCODE = 'EC422';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cat.tipo_destino WHERE id = NEW.tipo_destino_final_id AND es_final) THEN
    RAISE EXCEPTION 'RN-08: el destino indicado no es un destino final' USING ERRCODE = 'EC422';
  END IF;
  IF v_estado = 'ASIGNADO_BENEFICIARIO' THEN
    v_destino_esperado := cat.fn_id('tipo_destino', 'REUTILIZACION');
  ELSE
    SELECT tt.tipo_destino_id INTO v_destino_esperado
      FROM ops.tratamiento tr JOIN cat.tipo_tratamiento tt ON tt.id = tr.tipo_tratamiento_id
     WHERE tr.objeto_id = o.id AND tr.resultado IN ('EXITOSO','PARCIAL')
     ORDER BY tr.finalizado_en DESC LIMIT 1;
  END IF;
  IF NEW.tipo_destino_final_id IS DISTINCT FROM v_destino_esperado THEN
    RAISE EXCEPTION 'RN-08: el destino final no coincide con la ruta registrada del objeto' USING ERRCODE = 'EC422';
  END IF;
  IF NOT evd.fn_tiene_evidencia(NEW.documento_id) THEN
    RAISE EXCEPTION 'RN-08: el cierre requiere evidencia de confirmación' USING ERRCODE = 'EC422';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tg_rn08 BEFORE INSERT ON ops.cierre_trazabilidad
  FOR EACH ROW EXECUTE FUNCTION ops.fn_validar_cierre();

-- ---------------------------------------------------------------------
-- 13. Red: capacidad efectiva con herencia de escenarios (recursivo)
-- ---------------------------------------------------------------------
CREATE FUNCTION red.fn_capacidad_efectiva(p_escenario bigint, p_arista bigint)
RETURNS TABLE (capacidad numeric, activa boolean, origen text) LANGUAGE sql STABLE AS $$
  WITH RECURSIVE cadena AS (                          -- escenario actual y sus ancestros
    SELECT e.id, e.escenario_base_id, 0 AS profundidad FROM red.escenario_red e WHERE e.id = p_escenario
    UNION ALL
    SELECT b.id, b.escenario_base_id, c.profundidad + 1 FROM red.escenario_red b JOIN cadena c ON b.id = c.escenario_base_id
  ),
  esc AS (SELECT * FROM red.escenario_red WHERE id = p_escenario),
  cap_override AS (
    SELECT ea.capacidad_ajustada, c.profundidad, er.codigo FROM cadena c
      JOIN red.escenario_arista ea ON ea.escenario_id = c.id AND ea.arista_id = p_arista
      JOIN red.escenario_red er ON er.id = c.id
     WHERE ea.capacidad_ajustada IS NOT NULL ORDER BY c.profundidad LIMIT 1),
  act_override AS (
    SELECT ea.activa FROM cadena c JOIN red.escenario_arista ea ON ea.escenario_id = c.id AND ea.arista_id = p_arista
     WHERE ea.activa IS NOT NULL ORDER BY c.profundidad LIMIT 1),
  base AS (
    SELECT ca.capacidad FROM red.capacidad_arista ca, esc
     WHERE ca.arista_id = p_arista AND ca.unidad_id = esc.unidad_id AND ca.periodo = esc.periodo
       AND ca.vigencia @> esc.fecha_referencia)
  SELECT coalesce((SELECT capacidad_ajustada FROM cap_override), (SELECT capacidad FROM base), 0),
         coalesce((SELECT activa FROM act_override), (SELECT a.activa FROM red.arista a WHERE a.id = p_arista)),
         coalesce('escenario ' || (SELECT codigo FROM cap_override), CASE WHEN EXISTS (SELECT 1 FROM base) THEN 'capacidad vigente' ELSE 'sin capacidad' END)
$$;

-- Dataset para el módulo matemático (CP-09): aristas activas con capacidad efectiva
CREATE FUNCTION red.fn_dataset_flujo(p_escenario bigint)
RETURNS TABLE (arista_id bigint, origen varchar, destino varchar, tipo_origen varchar, tipo_destino varchar,
               capacidad numeric, fuente_capacidad text) LANGUAGE sql STABLE AS $$
  SELECT a.id, no.codigo, nd.codigo, tno.codigo, tnd.codigo, ce.capacidad, ce.origen
    FROM red.arista a
    JOIN red.escenario_red e ON e.id = p_escenario AND e.ecosistema_id = a.ecosistema_id
    JOIN red.nodo no ON no.id = a.nodo_origen_id JOIN cat.tipo_nodo tno ON tno.id = no.tipo_nodo_id
    JOIN red.nodo nd ON nd.id = a.nodo_destino_id JOIN cat.tipo_nodo tnd ON tnd.id = nd.tipo_nodo_id
    CROSS JOIN LATERAL red.fn_capacidad_efectiva(p_escenario, a.id) ce
   WHERE ce.activa AND ce.capacidad > 0 AND no.activo AND nd.activo
   ORDER BY no.codigo, nd.codigo
$$;

-- ---------------------------------------------------------------------
-- 14. Diccionario de datos vivo (se sincroniza desde el catálogo de PostgreSQL)
-- ---------------------------------------------------------------------
CREATE FUNCTION meta.fn_sincronizar_diccionario() RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_n int := 0; r record; v_ent int;
BEGIN
  FOR r IN
    SELECT d.id AS dominio_id, c.oid, c.relname, obj_description(c.oid, 'pg_class') AS comentario, n.nspname
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace JOIN meta.dominio d ON d.esquema = n.nspname
     WHERE c.relkind IN ('r','p') AND NOT c.relispartition
  LOOP
    INSERT INTO meta.entidad(dominio_id, nombre_tabla, descripcion)
    VALUES (r.dominio_id, r.relname, r.comentario)
    ON CONFLICT (dominio_id, nombre_tabla) DO UPDATE SET descripcion = coalesce(EXCLUDED.descripcion, meta.entidad.descripcion),
                                                         sincronizada_en = now()
    RETURNING id INTO v_ent;
    INSERT INTO meta.atributo(entidad_id, posicion, nombre_columna, tipo_dato, nulo, valor_defecto, es_pk, es_fk, referencia,
                              descripcion, es_derivado)
    SELECT v_ent, a.attnum, a.attname, format_type(a.atttypid, a.atttypmod), NOT a.attnotnull,
           pg_get_expr(ad.adbin, ad.adrelid),
           EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = r.oid AND i.indisprimary AND a.attnum = ANY(i.indkey)),
           fk.ref IS NOT NULL, fk.ref,
           coalesce(col_description(r.oid, a.attnum), CASE WHEN fk.ref IS NOT NULL THEN 'Referencia a ' || fk.ref || '.' END),
           a.attgenerated <> ''
      FROM pg_attribute a
      LEFT JOIN pg_attrdef ad ON ad.adrelid = a.attrelid AND ad.adnum = a.attnum
      LEFT JOIN LATERAL (
        SELECT string_agg(cf.confrelid::regclass::text || '(' || af.attname || ')', ', ') AS ref
          FROM pg_constraint cf
          JOIN pg_attribute af ON af.attrelid = cf.confrelid
                              AND af.attnum = cf.confkey[array_position(cf.conkey, a.attnum)]
         WHERE cf.conrelid = r.oid AND cf.contype = 'f' AND a.attnum = ANY(cf.conkey)) fk ON true
     WHERE a.attrelid = r.oid AND a.attnum > 0 AND NOT a.attisdropped
    ON CONFLICT (entidad_id, nombre_columna) DO UPDATE
      SET posicion = EXCLUDED.posicion, tipo_dato = EXCLUDED.tipo_dato, nulo = EXCLUDED.nulo,
          valor_defecto = EXCLUDED.valor_defecto, es_pk = EXCLUDED.es_pk, es_fk = EXCLUDED.es_fk,
          referencia = EXCLUDED.referencia, descripcion = coalesce(EXCLUDED.descripcion, meta.atributo.descripcion),
          es_derivado = EXCLUDED.es_derivado;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;
