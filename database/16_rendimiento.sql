-- =====================================================================
-- EcoRAEE Cloud · Script 16: rendimiento de la seguridad por fila (RLS)
-- psql -1 -f 16_rendimiento.sql (después del 15)
--
-- Problema: las políticas RLS llaman a seg.fn_ve_objeto / seg.fn_es_operativo / seg.fn_tiene_rol por cada fila,
-- y cada llamada recalculaba la jerarquía de roles (consulta recursiva) y, para un generador, el árbol de
-- organizaciones. Con cientos de filas por pantalla eso son miles de consultas recursivas.
-- Solución: api.fn_iniciar_contexto calcula una vez por transacción los roles efectivos, si el usuario es
-- operativo y las organizaciones que puede ver, y los guarda en variables locales de la transacción.
-- Las funciones usan ese resultado solo si corresponde exactamente al usuario actual; si no, hacen el cálculo
-- completo como antes. Las reglas no cambian: solo se evita repetir el mismo cálculo.
-- =====================================================================

CREATE OR REPLACE FUNCTION api.fn_iniciar_contexto(p_usuario uuid, p_canal text DEFAULT 'WEB', p_request_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE u seg.usuario; v_roles text[];
BEGIN
  SELECT * INTO u FROM seg.usuario WHERE uid = p_usuario AND estado = 'ACTIVO' AND eliminado_en IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Usuario inexistente o inactivo' USING ERRCODE = 'EC401'; END IF;
  IF p_canal NOT IN ('WEB','API','MCP','BATCH') THEN RAISE EXCEPTION 'Canal inválido' USING ERRCODE = 'EC422'; END IF;
  PERFORM set_config('app.usuario_id', u.id::text, true),
          set_config('app.ecosistema_id', u.ecosistema_id::text, true),
          set_config('app.organizacion_id', u.organizacion_id::text, true),
          set_config('app.canal', p_canal, true),
          set_config('app.request_id', coalesce(p_request_id, gen_random_uuid()::text), true);
  -- caché de la transacción (se calcula una sola vez)
  SELECT coalesce(array_agg(r.codigo ORDER BY r.codigo), '{}') INTO v_roles
    FROM seg.fn_roles_efectivos(u.id) e JOIN seg.rol r ON r.id = e.rol_id;
  PERFORM set_config('app.ctx_roles', array_to_string(v_roles, ','), true),
          set_config('app.ctx_operativo', (EXISTS (SELECT 1 FROM unnest(v_roles) x WHERE x NOT IN ('USUARIO_BASE','GENERADOR','BENEFICIARIO')))::text, true),
          set_config('app.ctx_orgs', (WITH RECURSIVE baja AS (
                                         SELECT id FROM org.organizacion WHERE id = u.organizacion_id
                                         UNION SELECT o.id FROM org.organizacion o JOIN baja b ON o.organizacion_padre_id = b.id)
                                       SELECT string_agg(id::text, ',') FROM baja), true),
          set_config('app.ctx_usuario', u.id::text, true);
  RETURN jsonb_build_object('usuario', u.alias, 'ecosistema', u.ecosistema_id, 'roles', to_jsonb(v_roles));
END $$;

-- ¿La caché corresponde a este usuario y al usuario actual de la transacción?
CREATE FUNCTION seg.fn_cache_valida(p_usuario bigint) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT p_usuario IS NOT NULL
     AND p_usuario::text = current_setting('app.ctx_usuario', true)
     AND p_usuario::text = current_setting('app.usuario_id', true)
$$;

CREATE OR REPLACE FUNCTION seg.fn_es_operativo(p_usuario bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT CASE WHEN seg.fn_cache_valida(p_usuario) THEN current_setting('app.ctx_operativo', true)::boolean
              ELSE EXISTS (SELECT 1 FROM seg.fn_roles_efectivos(p_usuario) r JOIN seg.rol x ON x.id = r.rol_id
                            WHERE x.codigo NOT IN ('USUARIO_BASE','GENERADOR','BENEFICIARIO')) END
$$;

CREATE OR REPLACE FUNCTION seg.fn_tiene_rol(p_usuario bigint, p_rol text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT CASE WHEN seg.fn_cache_valida(p_usuario) THEN p_rol = ANY(string_to_array(current_setting('app.ctx_roles', true), ','))
              ELSE EXISTS (SELECT 1 FROM seg.fn_roles_efectivos(p_usuario) r JOIN seg.rol x ON x.id = r.rol_id WHERE x.codigo = p_rol) END
$$;

CREATE OR REPLACE FUNCTION seg.fn_ve_objeto(p_objeto bigint, p_org_origen bigint) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := nullif(current_setting('app.usuario_id', true), '')::bigint;
        v_org bigint := nullif(current_setting('app.organizacion_id', true), '')::bigint;
BEGIN
  IF v_usuario IS NULL THEN RETURN false; END IF;
  IF seg.fn_cache_valida(v_usuario) THEN                     -- camino rápido: todo viene calculado del contexto
    IF current_setting('app.ctx_operativo', true)::boolean THEN RETURN true; END IF;
    IF 'GENERADOR' = ANY(string_to_array(current_setting('app.ctx_roles', true), ','))
       AND p_org_origen::text = ANY(string_to_array(current_setting('app.ctx_orgs', true), ',')) THEN
      RETURN true;
    END IF;
    RETURN 'BENEFICIARIO' = ANY(string_to_array(current_setting('app.ctx_roles', true), ','))
       AND EXISTS (SELECT 1 FROM ops.asignacion_beneficiario a WHERE a.objeto_id = p_objeto AND a.beneficiario_id = v_org);
  END IF;
  -- cálculo completo (sin contexto de la API, p. ej. pruebas SQL que cambian de usuario a mano)
  IF seg.fn_es_operativo(v_usuario) THEN RETURN true; END IF;
  IF seg.fn_tiene_rol(v_usuario, 'GENERADOR') AND EXISTS (
       WITH RECURSIVE sube AS (SELECT id, organizacion_padre_id FROM org.organizacion WHERE id = p_org_origen
                               UNION SELECT o.id, o.organizacion_padre_id FROM org.organizacion o JOIN sube s ON o.id = s.organizacion_padre_id)
       SELECT 1 FROM sube WHERE id = v_org) THEN
    RETURN true;
  END IF;
  RETURN seg.fn_tiene_rol(v_usuario, 'BENEFICIARIO') AND EXISTS (
           SELECT 1 FROM ops.asignacion_beneficiario a WHERE a.objeto_id = p_objeto AND a.beneficiario_id = v_org);
END $$;

GRANT EXECUTE ON FUNCTION seg.fn_cache_valida(bigint) TO ecoraee_lectura, ecoraee_app, ecoraee_mcp;
COMMENT ON FUNCTION seg.fn_cache_valida(bigint) IS 'Rendimiento RLS: indica si los roles calculados por api.fn_iniciar_contexto valen para este usuario.';
