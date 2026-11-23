-- =====================================================================
-- EcoRAEE Cloud · Script 14: actualizar y anular equipos (completa el CRUD)
-- psql -1 -f 14_dispositivos.sql (después del 13)
--
-- Un equipo solo se corrige o se anula mientras está REGISTRADO, es decir, antes de que alguien
-- lo recoja. Desde ese momento sus datos forman parte de la trazabilidad y de documentos firmados
-- por otras personas: ya no se editan (RN-01) y los errores se corrigen con documentos de ajuste.
-- "Eliminar" es una anulación lógica: el objeto pasa a ANULADO (relación T: REGISTRADO → ANULADO)
-- con un documento AJUSTE; nada se borra físicamente y la auditoría guarda el antes y el después.
-- =====================================================================

-- Quién puede corregir o anular: quien lo registró, alguien de la organización de origen con
-- permiso para registrar, o un administrador.
CREATE FUNCTION trz.fn_puede_corregir(p_objeto bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT EXISTS (
    SELECT 1 FROM trz.objeto_trazable o
     WHERE o.id = p_objeto AND o.ecosistema_id = seg.fn_ecosistema_actual()
       AND (seg.fn_tiene_permiso(seg.fn_usuario_actual(), 'USUARIO.ADMINISTRAR')
            OR o.registrado_por = seg.fn_usuario_actual()
            OR (o.organizacion_origen_id = nullif(current_setting('app.organizacion_id', true), '')::bigint
                AND seg.fn_tiene_permiso(seg.fn_usuario_actual(), 'OBJETO.REGISTRAR'))))
$$;

-- Para la interfaz: ¿muestro los botones Editar y Anular?
CREATE FUNCTION api.fn_puede_corregir(p_objeto uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT coalesce((SELECT trz.fn_puede_corregir(o.id) AND e.codigo = 'REGISTRADO'
                     FROM trz.objeto_trazable o JOIN cat.estado_trazabilidad e ON e.id = o.estado_actual_id
                    WHERE o.uid = p_objeto), false)
$$;

CREATE FUNCTION trz.fn_exigir_registrado(p_objeto bigint) RETURNS trz.objeto_trazable
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE o trz.objeto_trazable; v_estado text;
BEGIN
  SELECT * INTO o FROM trz.objeto_trazable WHERE id = p_objeto FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'El objeto no existe' USING ERRCODE = 'EC404'; END IF;
  IF NOT trz.fn_puede_corregir(o.id) THEN
    RAISE EXCEPTION 'Acceso denegado: solo quien registró el equipo, su organización o un administrador pueden corregirlo'
      USING ERRCODE = 'EC403';
  END IF;
  SELECT codigo INTO v_estado FROM cat.estado_trazabilidad WHERE id = o.estado_actual_id;
  IF v_estado <> 'REGISTRADO' THEN
    RAISE EXCEPTION '% está en estado %: sus datos ya forman parte de la trazabilidad y no se editan (RN-01)', o.codigo, lower(v_estado)
      USING ERRCODE = 'EC409', HINT = 'Las correcciones posteriores se hacen con una reevaluación o un documento de ajuste';
  END IF;
  RETURN o;
END $$;

-- UPDATE: corrige los datos del equipo (la categoría y el código no cambian: son su identidad)
CREATE FUNCTION api.fn_actualizar_dispositivo(
  p_objeto uuid, p_peso_kg numeric, p_contiene_almacenamiento boolean, p_marca text, p_modelo text,
  p_numero_serie text, p_anio integer, p_atributos jsonb, p_motivo text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE o trz.objeto_trazable := trz.fn_exigir_registrado(trz.fn_id(p_objeto)); v_cat cat.categoria_raee; v_req jsonb;
        v_marca integer; v_modelo integer; v_doc bigint;
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
  IF p_modelo IS NOT NULL AND v_marca IS NOT NULL THEN
    SELECT id INTO v_modelo FROM cat.modelo_equipo WHERE nombre = p_modelo AND marca_id = v_marca;
  END IF;
  UPDATE trz.dispositivo SET peso_kg = p_peso_kg,
         contiene_almacenamiento = coalesce(p_contiene_almacenamiento, false) OR v_cat.contiene_almacenamiento,
         marca_id = v_marca, modelo_id = v_modelo, numero_serie = nullif(btrim(p_numero_serie), ''), anio_fabricacion = p_anio,
         atributos = coalesce(p_atributos, '{}')
   WHERE objeto_id = o.id;
  -- el motivo queda en un documento de ajuste vinculado al equipo (se ve en su ficha); la auditoría guarda el antes y el después
  v_doc := ops.fn_nuevo_documento('AJUSTE', NULL, o.organizacion_origen_id, NULL, 'Corrección de datos: ' || btrim(p_motivo));
  INSERT INTO ops.documento_item(documento_id, objeto_id) VALUES (v_doc, o.id);
  PERFORM ops.fn_cerrar_documento(v_doc);
END $$;

-- DELETE lógico: anula el registro con un documento AJUSTE y deja la huella en el historial
CREATE FUNCTION api.fn_anular_objeto(p_objeto uuid, p_motivo text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE o trz.objeto_trazable := trz.fn_exigir_registrado(trz.fn_id(p_objeto)); v_doc bigint; v_num text;
BEGIN
  IF length(btrim(coalesce(p_motivo, ''))) < 5 THEN RAISE EXCEPTION 'Explica por qué se anula (p. ej. registro duplicado)' USING ERRCODE = 'EC422'; END IF;
  IF EXISTS (SELECT 1 FROM trz.lote_composicion WHERE objeto_id = o.id AND upper_inf(vigencia)) THEN
    RAISE EXCEPTION '% está dentro de un lote: desagrupa el lote antes de anularlo', o.codigo USING ERRCODE = 'EC409';
  END IF;
  v_doc := ops.fn_nuevo_documento('AJUSTE', NULL, o.organizacion_origen_id, NULL, 'Anulación: ' || btrim(p_motivo));
  INSERT INTO ops.documento_item(documento_id, objeto_id) VALUES (v_doc, o.id);
  PERFORM trz.fn_cambiar_estado(o.id, 'ANULADO', v_doc, btrim(p_motivo), false);
  PERFORM ops.fn_cerrar_documento(v_doc);
  SELECT numero INTO v_num FROM ops.documento_operativo WHERE id = v_doc;
  RETURN v_num;
END $$;

COMMENT ON FUNCTION api.fn_actualizar_dispositivo(uuid, numeric, boolean, text, text, text, integer, jsonb, text)
  IS 'Corrige los datos de un dispositivo mientras está REGISTRADO (antes de la recolección); la auditoría guarda el antes y el después.';
COMMENT ON FUNCTION api.fn_anular_objeto(uuid, text)
  IS 'Eliminación lógica: REGISTRADO → ANULADO con documento AJUSTE. Nada se borra físicamente (RN-01).';

-- La transición REGISTRADO → ANULADO exige OBJETO.ANULAR: se concede a quienes registran equipos;
-- la función limita a lo propio y a equipos aún REGISTRADOS.
INSERT INTO seg.rol_permiso(rol_id, permiso_id)
SELECT r.id, p.id FROM seg.rol r, seg.permiso p
 WHERE r.codigo IN ('GENERADOR', 'OPERADOR_CENTRO') AND p.codigo = 'OBJETO.ANULAR'
ON CONFLICT DO NOTHING;

REVOKE EXECUTE ON FUNCTION trz.fn_puede_corregir(bigint), api.fn_puede_corregir(uuid), trz.fn_exigir_registrado(bigint),
  api.fn_actualizar_dispositivo(uuid, numeric, boolean, text, text, text, integer, jsonb, text), api.fn_anular_objeto(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trz.fn_puede_corregir(bigint), api.fn_puede_corregir(uuid),
  api.fn_actualizar_dispositivo(uuid, numeric, boolean, text, text, text, integer, jsonb, text), api.fn_anular_objeto(uuid, text) TO ecoraee_app;

DO $$ BEGIN
  IF to_regprocedure('meta.fn_sincronizar_diccionario()') IS NOT NULL THEN PERFORM meta.fn_sincronizar_diccionario(); END IF;
END $$;
