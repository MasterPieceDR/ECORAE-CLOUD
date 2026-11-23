-- =====================================================================
-- Script 03: contrato público (esquema api) — comandos, consultas,
-- vistas v1, indicadores, alertas y capa MCP
-- Lectura: vistas security_invoker (respetan RLS del rol que consulta)
-- Escritura: solo funciones SECURITY DEFINER que aplican RN-01…RN-09
-- =====================================================================
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- Contexto por transacción (la API/MCP lo llama tras validar el JWT)
-- ---------------------------------------------------------------------
CREATE FUNCTION api.fn_iniciar_contexto(p_usuario uuid, p_canal text DEFAULT 'WEB', p_request_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE u seg.usuario;
BEGIN
  SELECT * INTO u FROM seg.usuario WHERE uid = p_usuario AND estado = 'ACTIVO' AND eliminado_en IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Usuario inexistente o inactivo' USING ERRCODE = 'EC401'; END IF;
  IF p_canal NOT IN ('WEB','API','MCP','BATCH') THEN RAISE EXCEPTION 'Canal inválido' USING ERRCODE = 'EC422'; END IF;
  PERFORM set_config('app.usuario_id', u.id::text, true),
          set_config('app.ecosistema_id', u.ecosistema_id::text, true),
          set_config('app.organizacion_id', u.organizacion_id::text, true),
          set_config('app.canal', p_canal, true),
          set_config('app.request_id', coalesce(p_request_id, gen_random_uuid()::text), true);
  RETURN jsonb_build_object('usuario', u.alias, 'ecosistema', u.ecosistema_id,
           'roles', (SELECT jsonb_agg(r.codigo ORDER BY r.codigo) FROM seg.fn_roles_efectivos(u.id) e JOIN seg.rol r ON r.id = e.rol_id));
END $$;

-- Helpers de búsqueda por código dentro del ecosistema del contexto
CREATE FUNCTION org.fn_centro(p_codigo text) RETURNS bigint LANGUAGE plpgsql STABLE AS $$
DECLARE v bigint;
BEGIN
  SELECT c.id INTO v FROM org.centro c JOIN org.organizacion o ON o.id = c.organizacion_id
   WHERE c.codigo = p_codigo AND o.ecosistema_id = seg.fn_ecosistema_actual() AND c.eliminado_en IS NULL;
  IF v IS NULL THEN RAISE EXCEPTION 'Centro % no existe', p_codigo USING ERRCODE = 'EC404'; END IF;
  RETURN v;
END $$;

CREATE FUNCTION org.fn_ubicacion(p_centro bigint, p_codigo text) RETURNS bigint LANGUAGE plpgsql STABLE AS $$
DECLARE v bigint;
BEGIN
  IF p_codigo IS NULL THEN
    SELECT id INTO v FROM org.ubicacion WHERE centro_id = p_centro AND tipo = 'RAIZ' AND activo;
  ELSE
    SELECT id INTO v FROM org.ubicacion WHERE centro_id = p_centro AND codigo = p_codigo AND activo;
  END IF;
  IF v IS NULL THEN RAISE EXCEPTION 'Ubicación % no existe en el centro %', p_codigo, p_centro USING ERRCODE = 'EC404'; END IF;
  RETURN v;
END $$;

CREATE FUNCTION red.fn_nodo(p_codigo text) RETURNS red.nodo LANGUAGE plpgsql STABLE AS $$
DECLARE n red.nodo;
BEGIN
  SELECT * INTO n FROM red.nodo WHERE codigo = p_codigo AND ecosistema_id = seg.fn_ecosistema_actual();
  IF NOT FOUND THEN RAISE EXCEPTION 'Nodo % no existe', p_codigo USING ERRCODE = 'EC404'; END IF;
  RETURN n;
END $$;

CREATE FUNCTION ops.fn_doc(p_uid uuid, p_tipo text) RETURNS ops.documento_operativo LANGUAGE plpgsql STABLE AS $$
DECLARE d ops.documento_operativo;
BEGIN
  SELECT * INTO d FROM ops.documento_operativo WHERE uid = p_uid AND tipo_documento = p_tipo
     AND ecosistema_id = seg.fn_ecosistema_actual();
  IF NOT FOUND THEN RAISE EXCEPTION 'Documento % de tipo % no existe', p_uid, p_tipo USING ERRCODE = 'EC404'; END IF;
  RETURN d;
END $$;

CREATE FUNCTION evd.fn_vincular(p_evidencias uuid[], p_documento bigint, p_objeto bigint DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_n int;
BEGIN
  INSERT INTO evd.evidencia_vinculo(evidencia_id, documento_id, objeto_id, vinculado_por)
  SELECT e.id, p_documento, p_objeto, seg.fn_usuario_actual()
    FROM evd.evidencia e WHERE e.uid = ANY(coalesce(p_evidencias, '{}')) AND e.ecosistema_id = seg.fn_ecosistema_actual()
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n < coalesce(cardinality(p_evidencias), 0) THEN
    RAISE EXCEPTION 'Alguna evidencia no existe o ya estaba vinculada' USING ERRCODE = 'EC404';
  END IF;
  RETURN v_n;
END $$;

-- =====================================================================
-- COMANDOS (escritura)
-- =====================================================================

-- Registro individual de dispositivo (RF-INT-02, RN-01)
CREATE FUNCTION api.fn_registrar_dispositivo(
  p_codigo text, p_categoria text, p_peso_kg numeric, p_contiene_almacenamiento boolean DEFAULT false,
  p_marca text DEFAULT NULL, p_modelo text DEFAULT NULL, p_numero_serie text DEFAULT NULL, p_anio integer DEFAULT NULL,
  p_atributos jsonb DEFAULT '{}'::jsonb, p_organizacion_origen uuid DEFAULT NULL, p_componente_de uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_usuario bigint := seg.fn_usuario_actual(); v_eco bigint := seg.fn_ecosistema_actual();
  v_org bigint := current_setting('app.organizacion_id')::bigint; v_cat cat.categoria_raee; v_req jsonb;
  v_id bigint; v_uid uuid; v_marca integer; v_modelo integer; v_reg smallint := cat.fn_id('estado_trazabilidad','REGISTRADO');
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
  IF p_modelo IS NOT NULL THEN
    SELECT id INTO v_modelo FROM cat.modelo_equipo WHERE nombre = p_modelo AND marca_id = v_marca;
  END IF;

  INSERT INTO trz.objeto_trazable(ecosistema_id, codigo, tipo_objeto, organizacion_origen_id, estado_actual_id, registrado_por)
  VALUES (v_eco, p_codigo, 'DISPOSITIVO', v_org, v_reg, v_usuario) RETURNING id, uid INTO v_id, v_uid;
  INSERT INTO trz.dispositivo(objeto_id, categoria_id, marca_id, modelo_id, numero_serie, anio_fabricacion, peso_kg,
                              contiene_almacenamiento, atributos, componente_de_id)
  VALUES (v_id, v_cat.id, v_marca, v_modelo, p_numero_serie, p_anio, p_peso_kg,
          p_contiene_almacenamiento OR v_cat.contiene_almacenamiento, p_atributos,
          CASE WHEN p_componente_de IS NOT NULL THEN trz.fn_id(p_componente_de) END);
  INSERT INTO trz.historial_estado(objeto_id, estado_destino_id, usuario_id, canal, observacion)
  VALUES (v_id, v_reg, v_usuario, coalesce(nullif(current_setting('app.canal', true), ''), 'WEB'), 'Registro inicial');
  RETURN v_uid;
END $$;

-- Lote: agrupa objetos que comparten estado y ubicación
CREATE FUNCTION api.fn_crear_lote(p_codigo text, p_proposito text, p_objetos uuid[], p_descripcion text DEFAULT NULL,
                                  p_peso_declarado numeric DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); v_eco bigint := seg.fn_ecosistema_actual();
        v_estados int; v_ubics int; v_orgs int; v_estado smallint; v_ubic bigint; v_org bigint; v_id bigint; v_uid uuid;
BEGIN
  PERFORM seg.fn_exigir_permiso(v_usuario, 'LOTE.GESTIONAR');
  SELECT count(DISTINCT estado_actual_id), count(DISTINCT coalesce(ubicacion_actual_id, 0)), count(DISTINCT organizacion_origen_id),
         min(estado_actual_id), min(ubicacion_actual_id), min(organizacion_origen_id)
    INTO v_estados, v_ubics, v_orgs, v_estado, v_ubic, v_org
    FROM trz.objeto_trazable WHERE uid = ANY(p_objetos) AND ecosistema_id = v_eco;
  IF v_estados <> 1 OR v_ubics <> 1 THEN
    RAISE EXCEPTION 'Los objetos de un lote deben compartir estado y ubicación' USING ERRCODE = 'EC422';
  END IF;
  INSERT INTO trz.objeto_trazable(ecosistema_id, codigo, tipo_objeto, organizacion_origen_id, estado_actual_id, registrado_por)
  VALUES (v_eco, p_codigo, 'LOTE', CASE WHEN v_orgs = 1 THEN v_org ELSE current_setting('app.organizacion_id')::bigint END,
          v_estado, v_usuario) RETURNING id, uid INTO v_id, v_uid;
  INSERT INTO trz.lote(objeto_id, proposito, descripcion, peso_declarado_kg) VALUES (v_id, p_proposito, p_descripcion, p_peso_declarado);
  IF v_ubic IS NOT NULL THEN PERFORM trz.fn_actualizar_cache(v_id, 'ubicacion', v_ubic); END IF;
  INSERT INTO trz.lote_composicion(lote_id, objeto_id, agregado_por)
  SELECT v_id, o.id, v_usuario FROM trz.objeto_trazable o WHERE o.uid = ANY(p_objetos);
  INSERT INTO trz.historial_estado(objeto_id, estado_destino_id, usuario_id, canal, observacion)
  VALUES (v_id, v_estado, v_usuario, coalesce(nullif(current_setting('app.canal', true), ''), 'WEB'), 'Creación de lote');
  RETURN v_uid;
END $$;

-- Disolución de un lote: cierra la composición vigente y el lote pasa a DESAGRUPADO
CREATE FUNCTION api.fn_desagrupar_lote(p_lote uuid, p_observacion text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_id bigint := trz.fn_id(p_lote); v_doc bigint; v_centro bigint;
BEGIN
  PERFORM seg.fn_exigir_permiso(seg.fn_usuario_actual(), 'LOTE.GESTIONAR');
  SELECT u.centro_id INTO v_centro FROM trz.objeto_trazable o JOIN org.ubicacion u ON u.id = o.ubicacion_actual_id WHERE o.id = v_id;
  v_doc := ops.fn_nuevo_documento('AJUSTE', v_centro, NULL, NULL, coalesce(p_observacion, 'Desagrupación de lote'));
  INSERT INTO ops.documento_item(documento_id, objeto_id) SELECT v_doc, objeto_id FROM trz.lote_composicion
   WHERE lote_id = v_id AND upper_inf(vigencia);
  UPDATE trz.lote_composicion SET vigencia = tstzrange(lower(vigencia), now()) WHERE lote_id = v_id AND upper_inf(vigencia);
  PERFORM trz.fn_cambiar_estado(v_id, 'DESAGRUPADO', v_doc, p_observacion, false);
  PERFORM trz.fn_actualizar_cache(v_id, 'ubicacion', NULL);
  PERFORM ops.fn_cerrar_documento(v_doc);
END $$;

-- Evidencia: el binario se sube a S3 con URL prefirmada; aquí se registran metadatos y huella
CREATE FUNCTION api.fn_registrar_evidencia(p_tipo text, p_bucket text, p_clave text, p_sha256 text, p_mime text,
                                           p_tamano bigint, p_metadatos_limpios boolean, p_objeto uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); te cat.tipo_evidencia; v_id bigint; v_uid uuid;
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

-- Solicitud de recolección o aviso de entrega directa
CREATE FUNCTION api.fn_solicitar_recoleccion(p_objetos uuid[], p_centro_destino text, p_modalidad text DEFAULT 'RECOLECCION',
                                             p_fecha_preferida date DEFAULT NULL, p_sector text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); v_centro bigint := org.fn_centro(p_centro_destino);
        v_org bigint; v_n_org int; v_doc bigint; u uuid; v_cant int; v_peso numeric;
BEGIN
  PERFORM seg.fn_exigir_permiso(v_usuario, 'SOLICITUD.CREAR');
  SELECT count(DISTINCT o.organizacion_origen_id), min(o.organizacion_origen_id) INTO v_n_org, v_org
    FROM trz.fn_expandir(p_objetos) x JOIN trz.objeto_trazable o ON o.id = x.objeto_id;
  IF v_n_org <> 1 THEN RAISE EXCEPTION 'Una solicitud agrupa objetos de un único generador' USING ERRCODE = 'EC422'; END IF;
  SELECT count(*), sum(d.peso_kg) INTO v_cant, v_peso
    FROM trz.fn_expandir(p_objetos) x JOIN trz.dispositivo d ON d.objeto_id = x.objeto_id;
  v_doc := ops.fn_nuevo_documento('SOLICITUD', v_centro, v_org);
  INSERT INTO ops.solicitud_recoleccion(documento_id, organizacion_generador_id, modalidad, centro_destino_id, fecha_preferida,
                                        sector_referencial, cantidad_estimada, peso_estimado_kg)
  VALUES (v_doc, v_org, p_modalidad, v_centro, p_fecha_preferida, p_sector, v_cant, v_peso);
  INSERT INTO ops.documento_item(documento_id, objeto_id, peso_kg, resultado)
  SELECT v_doc, x.objeto_id, d.peso_kg, 'PENDIENTE' FROM trz.fn_expandir(p_objetos) x LEFT JOIN trz.dispositivo d ON d.objeto_id = x.objeto_id;
  IF p_modalidad = 'RECOLECCION' THEN
    FOREACH u IN ARRAY p_objetos LOOP PERFORM trz.fn_cambiar_estado(trz.fn_id(u), 'RECOLECCION_SOLICITADA', v_doc); END LOOP;
  END IF;
  RETURN (SELECT uid FROM ops.documento_operativo WHERE id = v_doc);
END $$;

-- Programación de la recolección (consume capacidad del arco G→C: RN-05)
CREATE FUNCTION api.fn_programar_recoleccion(p_solicitud uuid, p_fecha timestamptz, p_transportista text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); d ops.documento_operativo := ops.fn_doc(p_solicitud, 'SOLICITUD');
        s ops.solicitud_recoleccion; v_arista bigint; v_doc bigint; v_und int; v_kg numeric; r record;
BEGIN
  SELECT * INTO s FROM ops.solicitud_recoleccion WHERE documento_id = d.id;
  PERFORM seg.fn_exigir_permiso(v_usuario, 'RECOLECCION.PROGRAMAR', s.centro_destino_id);
  SELECT a.id INTO v_arista FROM red.arista a
    JOIN red.nodo g ON g.id = a.nodo_origen_id AND g.organizacion_id = s.organizacion_generador_id
    JOIN red.nodo c ON c.id = a.nodo_destino_id AND c.centro_id = s.centro_destino_id
   WHERE a.activa LIMIT 1;
  SELECT count(*), coalesce(sum(dv.peso_kg), 0) INTO v_und, v_kg
    FROM ops.documento_item i JOIN trz.dispositivo dv ON dv.objeto_id = i.objeto_id WHERE i.documento_id = d.id;
  IF v_arista IS NOT NULL THEN PERFORM red.fn_validar_capacidad(v_arista, v_und, v_kg); END IF;
  v_doc := ops.fn_nuevo_documento('RECOLECCION', s.centro_destino_id, s.organizacion_generador_id, d.id);
  INSERT INTO ops.recoleccion(documento_id, solicitud_id, arista_id, unidades, peso_kg, fecha_programada, transportista_ref)
  VALUES (v_doc, d.id, v_arista, v_und, v_kg, p_fecha, p_transportista);
  INSERT INTO ops.documento_item(documento_id, objeto_id, peso_kg) SELECT v_doc, objeto_id, peso_kg FROM ops.documento_item WHERE documento_id = d.id;
  FOR r IN SELECT i.objeto_id FROM ops.documento_item i
            WHERE i.documento_id = d.id
              AND NOT EXISTS (SELECT 1 FROM trz.lote_composicion lc JOIN ops.documento_item i2 ON i2.objeto_id = lc.lote_id
                               WHERE i2.documento_id = d.id AND lc.objeto_id = i.objeto_id AND lc.vigencia @> now()) LOOP
    PERFORM trz.fn_cambiar_estado(r.objeto_id, 'EN_RECOLECCION', v_doc);
  END LOOP;
  UPDATE ops.documento_operativo SET estado_documento = 'EN_CURSO' WHERE id = d.id;
  RETURN (SELECT uid FROM ops.documento_operativo WHERE id = v_doc);
END $$;

-- Recepción en centro (con solicitud o entrega directa): estado RECIBIDO + ingreso a inventario
CREATE FUNCTION api.fn_recibir(p_objetos uuid[], p_centro text, p_ubicacion text DEFAULT NULL, p_evidencias uuid[] DEFAULT '{}',
                               p_conformidad text DEFAULT 'CONFORME', p_solicitud uuid DEFAULT NULL, p_peso_verificado numeric DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); v_centro bigint := org.fn_centro(p_centro);
        v_ubic bigint := org.fn_ubicacion(v_centro, p_ubicacion); v_sol bigint; v_doc bigint; u uuid; x record; v_org bigint;
BEGIN
  PERFORM seg.fn_exigir_permiso(v_usuario, 'RECEPCION.REGISTRAR', v_centro);
  IF p_solicitud IS NOT NULL THEN v_sol := (ops.fn_doc(p_solicitud, 'SOLICITUD')).id; END IF;
  SELECT min(o.organizacion_origen_id) INTO v_org FROM trz.objeto_trazable o WHERE o.uid = ANY(p_objetos);
  v_doc := ops.fn_nuevo_documento('RECEPCION', v_centro, v_org, v_sol);
  INSERT INTO ops.recepcion(documento_id, centro_id, ubicacion_id, solicitud_id, conformidad, peso_verificado_kg)
  VALUES (v_doc, v_centro, v_ubic, v_sol, p_conformidad, p_peso_verificado);
  INSERT INTO ops.documento_item(documento_id, objeto_id, peso_kg, resultado)
  SELECT v_doc, e.objeto_id, d.peso_kg, CASE p_conformidad WHEN 'RECHAZADA' THEN 'RECHAZADO' WHEN 'CONFORME' THEN 'CONFORME' ELSE 'OBSERVADO' END
    FROM trz.fn_expandir(p_objetos) e LEFT JOIN trz.dispositivo d ON d.objeto_id = e.objeto_id;
  PERFORM evd.fn_vincular(p_evidencias, v_doc);
  IF p_conformidad <> 'RECHAZADA' THEN
    FOREACH u IN ARRAY p_objetos LOOP PERFORM trz.fn_cambiar_estado(trz.fn_id(u), 'RECIBIDO', v_doc); END LOOP;
    FOR x IN SELECT * FROM trz.fn_expandir(p_objetos) LOOP
      IF x.tipo_objeto = 'DISPOSITIVO' THEN
        PERFORM inv.fn_registrar_movimiento(v_doc, x.objeto_id, v_ubic, 1::smallint, 'INGRESO');
      ELSE
        PERFORM trz.fn_actualizar_cache(x.objeto_id, 'ubicacion', v_ubic);
      END IF;
    END LOOP;
  END IF;
  PERFORM ops.fn_cerrar_documento(v_doc);
  IF v_sol IS NOT NULL THEN PERFORM ops.fn_cerrar_documento(v_sol); END IF;
  RETURN (SELECT uid FROM ops.documento_operativo WHERE id = v_doc);
END $$;

-- Evaluación técnica (RN-02): completa, preclasificación o reevaluación
CREATE FUNCTION api.fn_evaluar(p_objeto uuid, p_clasificacion text, p_destino_sugerido text, p_funcional boolean,
                               p_criterios jsonb DEFAULT '[]'::jsonb, p_modalidad text DEFAULT 'COMPLETA',
                               p_requiere_borrado boolean DEFAULT false, p_puntaje numeric DEFAULT NULL,
                               p_motivo text DEFAULT NULL, p_evidencias uuid[] DEFAULT '{}')
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); o trz.objeto_trazable; v_estado text; v_centro bigint;
        v_doc bigint; v_modalidad text := p_modalidad; v_anterior bigint; c jsonb; cr cat.criterio_evaluacion;
BEGIN
  SELECT * INTO o FROM trz.objeto_trazable WHERE id = trz.fn_id(p_objeto) FOR UPDATE;
  IF o.tipo_objeto <> 'DISPOSITIVO' THEN RAISE EXCEPTION 'Solo se evalúan dispositivos individuales' USING ERRCODE = 'EC422'; END IF;
  SELECT codigo INTO v_estado FROM cat.estado_trazabilidad WHERE id = o.estado_actual_id;
  SELECT centro_id INTO v_centro FROM org.ubicacion WHERE id = o.ubicacion_actual_id;
  IF v_centro IS NULL THEN RAISE EXCEPTION 'El objeto % no está físicamente en un centro', o.codigo USING ERRCODE = 'EC409'; END IF;
  IF v_estado IN ('CLASIFICADO','TRATADO') THEN
    v_modalidad := 'REEVALUACION';
    IF p_motivo IS NULL THEN RAISE EXCEPTION 'La reevaluación exige un motivo' USING ERRCODE = 'EC422'; END IF;
  ELSIF v_estado NOT IN ('RECIBIDO','EN_EVALUACION') THEN
    RAISE EXCEPTION 'No se puede evaluar un objeto en estado %', v_estado USING ERRCODE = 'EC409';
  END IF;
  SELECT documento_id INTO v_anterior FROM ops.evaluacion_tecnica WHERE objeto_id = o.id AND vigente;
  v_doc := ops.fn_nuevo_documento('EVALUACION', v_centro, o.organizacion_origen_id, v_anterior);
  PERFORM evd.fn_vincular(p_evidencias, v_doc);
  IF v_estado = 'RECIBIDO' AND v_modalidad = 'COMPLETA' THEN PERFORM trz.fn_cambiar_estado(o.id, 'EN_EVALUACION', v_doc); END IF;

  INSERT INTO ops.evaluacion_tecnica(documento_id, objeto_id, tecnico_id, modalidad, clasificacion_id, tipo_destino_sugerido_id,
                                     funcional, requiere_borrado_datos, puntaje, evaluacion_anterior_id, motivo_reevaluacion_id)
  VALUES (v_doc, o.id, v_usuario, v_modalidad, cat.fn_id('clasificacion_tecnica', p_clasificacion),
          cat.fn_id('tipo_destino', p_destino_sugerido), p_funcional, p_requiere_borrado, p_puntaje, v_anterior,
          CASE WHEN p_motivo IS NOT NULL THEN cat.fn_id('motivo', p_motivo) END);

  FOR c IN SELECT * FROM jsonb_array_elements(p_criterios) LOOP
    SELECT * INTO cr FROM cat.criterio_evaluacion WHERE codigo = c ->> 'criterio';
    IF NOT FOUND THEN RAISE EXCEPTION 'Criterio % no existe', c ->> 'criterio' USING ERRCODE = 'EC404'; END IF;
    INSERT INTO ops.evaluacion_criterio(evaluacion_id, criterio_id, valor_booleano, valor_numero, valor_texto, cumple)
    VALUES (v_doc, cr.id,
            CASE WHEN cr.tipo_valor = 'BOOLEANO' THEN (c ->> 'valor')::boolean END,
            CASE WHEN cr.tipo_valor = 'NUMERO'   THEN (c ->> 'valor')::numeric END,
            CASE WHEN cr.tipo_valor = 'TEXTO'    THEN c ->> 'valor' END,
            (c ->> 'cumple')::boolean);
  END LOOP;

  IF v_modalidad <> 'REEVALUACION' THEN PERFORM trz.fn_cambiar_estado(o.id, 'CLASIFICADO', v_doc); END IF;
  PERFORM ops.fn_cerrar_documento(v_doc);
  RETURN (SELECT uid FROM ops.documento_operativo WHERE id = v_doc);
END $$;

-- Transferencia por una arista de la red (RN-05, RN-06, compatibilidad clasificación ↔ destino)
CREATE FUNCTION api.fn_transferir(p_objetos uuid[], p_nodo_origen text, p_nodo_destino text,
                                  p_ubicacion_destino text DEFAULT NULL, p_criterio_asignacion text DEFAULT NULL,
                                  p_transportista text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); no red.nodo := red.fn_nodo(p_nodo_origen); nd red.nodo := red.fn_nodo(p_nodo_destino);
        a red.arista; tnd cat.tipo_nodo; v_und int; v_kg numeric; v_doc bigint; v_asg bigint; v_ubic_dest bigint;
        v_ubic_origen bigint; x record; u uuid; v_malos text;
BEGIN
  IF no.centro_id IS NULL THEN RAISE EXCEPTION 'El origen de una transferencia debe ser un centro' USING ERRCODE = 'EC422'; END IF;
  PERFORM seg.fn_exigir_permiso(v_usuario, 'TRANSFERENCIA.CREAR', no.centro_id);
  SELECT * INTO a FROM red.arista WHERE nodo_origen_id = no.id AND nodo_destino_id = nd.id AND activa;
  IF NOT FOUND THEN RAISE EXCEPTION 'No existe arista activa % → %', p_nodo_origen, p_nodo_destino USING ERRCODE = 'EC422'; END IF;
  IF a.excepcion_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM gob.excepcion_regla
       WHERE id = a.excepcion_id AND estado = 'APROBADA' AND vigencia @> current_date) THEN
    RAISE EXCEPTION 'La excepción que habilita % → % no está vigente', p_nodo_origen, p_nodo_destino USING ERRCODE = 'EC422';
  END IF;
  SELECT * INTO tnd FROM cat.tipo_nodo WHERE id = nd.tipo_nodo_id;

  -- todos los dispositivos deben estar físicamente en el centro de origen
  SELECT string_agg(o.codigo, ', ') INTO v_malos FROM trz.fn_expandir(p_objetos) e JOIN trz.objeto_trazable o ON o.id = e.objeto_id
    LEFT JOIN org.ubicacion ub ON ub.id = o.ubicacion_actual_id
   WHERE e.tipo_objeto = 'DISPOSITIVO' AND ub.centro_id IS DISTINCT FROM no.centro_id;
  IF v_malos IS NOT NULL THEN RAISE EXCEPTION 'Objetos fuera del centro de origen: %', v_malos USING ERRCODE = 'EC409'; END IF;
  -- la clasificación debe admitir el destino circular del nodo destino
  IF tnd.tipo_destino_id IS NOT NULL THEN
    SELECT string_agg(o.codigo, ', ') INTO v_malos FROM trz.fn_expandir(p_objetos) e JOIN trz.objeto_trazable o ON o.id = e.objeto_id
     WHERE e.tipo_objeto = 'DISPOSITIVO' AND NOT EXISTS (
       SELECT 1 FROM cat.clasificacion_destino_permitido m
        WHERE m.clasificacion_id = o.clasificacion_actual_id AND m.tipo_destino_id = tnd.tipo_destino_id);
    IF v_malos IS NOT NULL THEN
      RAISE EXCEPTION 'RN-02/RN-04: la clasificación de % no admite el destino %', v_malos, tnd.codigo USING ERRCODE = 'EC422';
    END IF;
  END IF;

  SELECT count(*), coalesce(sum(d.peso_kg), 0), min(o.ubicacion_actual_id) INTO v_und, v_kg, v_ubic_origen
    FROM trz.fn_expandir(p_objetos) e JOIN trz.dispositivo d ON d.objeto_id = e.objeto_id JOIN trz.objeto_trazable o ON o.id = e.objeto_id;
  PERFORM red.fn_validar_capacidad(a.id, v_und, v_kg);          -- RN-05 con bloqueo de la fila de capacidad

  IF nd.centro_id IS NOT NULL THEN v_ubic_dest := org.fn_ubicacion(nd.centro_id, p_ubicacion_destino); END IF;
  v_doc := ops.fn_nuevo_documento('TRANSFERENCIA', no.centro_id,
             coalesce(nd.organizacion_id, (SELECT organizacion_id FROM org.centro WHERE id = nd.centro_id)));
  INSERT INTO ops.transferencia(documento_id, arista_id, ubicacion_origen_id, ubicacion_destino_id, unidades, peso_kg,
                                estado_transferencia, transportista_ref, despachado_en)
  VALUES (v_doc, a.id, v_ubic_origen, v_ubic_dest, v_und, v_kg, 'DESPACHADA', p_transportista, now());
  INSERT INTO ops.documento_item(documento_id, objeto_id, peso_kg)
  SELECT v_doc, e.objeto_id, d.peso_kg FROM trz.fn_expandir(p_objetos) e LEFT JOIN trz.dispositivo d ON d.objeto_id = e.objeto_id;

  IF tnd.codigo = 'BENEFICIARIO' THEN                          -- asignación (RN-04 y RN-09 se validan al insertar)
    PERFORM seg.fn_exigir_permiso(v_usuario, 'ASIGNACION.REGISTRAR', no.centro_id);
    v_asg := ops.fn_nuevo_documento('ASIGNACION', no.centro_id, nd.organizacion_id, v_doc);
    INSERT INTO ops.asignacion_beneficiario(documento_id, objeto_id, beneficiario_id, criterio_asignacion)
    SELECT v_asg, e.objeto_id, nd.organizacion_id, coalesce(p_criterio_asignacion, 'Asignación por red')
      FROM trz.fn_expandir(p_objetos) e WHERE e.tipo_objeto = 'DISPOSITIVO';
  END IF;

  FOR x IN SELECT e.objeto_id, e.tipo_objeto, o.ubicacion_actual_id FROM trz.fn_expandir(p_objetos) e
             JOIN trz.objeto_trazable o ON o.id = e.objeto_id LOOP
    IF x.tipo_objeto = 'DISPOSITIVO' THEN
      PERFORM inv.fn_registrar_movimiento(v_doc, x.objeto_id, x.ubicacion_actual_id, -1::smallint, 'TRASLADO_SALIDA');
    ELSE
      PERFORM trz.fn_actualizar_cache(x.objeto_id, 'ubicacion', NULL);
    END IF;
  END LOOP;
  FOREACH u IN ARRAY p_objetos LOOP PERFORM trz.fn_cambiar_estado(trz.fn_id(u), 'EN_TRANSFERENCIA', v_doc); END LOOP;
  UPDATE ops.documento_operativo SET estado_documento = 'EN_CURSO' WHERE id = v_doc;
  RETURN (SELECT uid FROM ops.documento_operativo WHERE id = v_doc);
END $$;

-- Confirmación de recepción del traslado (cierra con RN-03)
CREATE FUNCTION api.fn_recibir_transferencia(p_transferencia uuid, p_evidencias uuid[], p_ubicacion text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); d ops.documento_operativo := ops.fn_doc(p_transferencia, 'TRANSFERENCIA');
        t ops.transferencia; nd red.nodo; tnd text; v_ubic bigint; v_asg bigint; x record; v_dest text; v_sin_clas boolean; v_par bigint;
BEGIN
  SELECT * INTO t FROM ops.transferencia WHERE documento_id = d.id FOR UPDATE;
  IF t.estado_transferencia <> 'DESPACHADA' THEN
    RAISE EXCEPTION 'La transferencia % está en estado %', d.numero, t.estado_transferencia USING ERRCODE = 'EC409';
  END IF;
  SELECT n.* INTO nd FROM red.arista a JOIN red.nodo n ON n.id = a.nodo_destino_id WHERE a.id = t.arista_id;
  SELECT codigo INTO tnd FROM cat.tipo_nodo WHERE id = nd.tipo_nodo_id;
  IF nd.centro_id IS NOT NULL THEN
    PERFORM seg.fn_exigir_permiso(v_usuario, 'TRANSFERENCIA.CONFIRMAR', nd.centro_id);
    v_ubic := coalesce(CASE WHEN p_ubicacion IS NOT NULL THEN org.fn_ubicacion(nd.centro_id, p_ubicacion) END, t.ubicacion_destino_id);
  ELSE
    PERFORM seg.fn_exigir_permiso(v_usuario, 'TRANSFERENCIA.CONFIRMAR');
    IF current_setting('app.organizacion_id')::bigint <> nd.organizacion_id THEN
      RAISE EXCEPTION 'Solo la organización beneficiaria confirma esta entrega' USING ERRCODE = 'EC403';
    END IF;
    SELECT id INTO v_asg FROM ops.documento_operativo WHERE documento_referencia_id = d.id AND tipo_documento = 'ASIGNACION';
  END IF;
  PERFORM evd.fn_vincular(p_evidencias, d.id);
  IF v_asg IS NOT NULL THEN PERFORM evd.fn_vincular(p_evidencias, v_asg); END IF;

  -- entradas de inventario (pareadas con su salida)
  FOR x IN SELECT i.objeto_id FROM ops.documento_item i JOIN trz.dispositivo dv ON dv.objeto_id = i.objeto_id WHERE i.documento_id = d.id LOOP
    IF v_ubic IS NOT NULL THEN
      SELECT id INTO v_par FROM inv.movimiento_inventario WHERE documento_id = d.id AND objeto_id = x.objeto_id AND sentido = -1;
      PERFORM inv.fn_registrar_movimiento(d.id, x.objeto_id, v_ubic, 1::smallint, 'TRASLADO_ENTRADA', v_par);
    END IF;
  END LOOP;
  -- transición de los objetos de nivel superior (los lotes propagan a sus miembros)
  FOR x IN SELECT i.objeto_id, o.tipo_objeto FROM ops.documento_item i JOIN trz.objeto_trazable o ON o.id = i.objeto_id
            WHERE i.documento_id = d.id
              AND NOT EXISTS (SELECT 1 FROM trz.lote_composicion lc JOIN ops.documento_item i2 ON i2.objeto_id = lc.lote_id
                               WHERE i2.documento_id = d.id AND lc.objeto_id = i.objeto_id AND lc.vigencia @> now()) LOOP
    IF x.tipo_objeto = 'LOTE' AND v_ubic IS NOT NULL THEN PERFORM trz.fn_actualizar_cache(x.objeto_id, 'ubicacion', v_ubic); END IF;
    IF tnd IN ('REACONDICIONAMIENTO','RECICLAJE','DISPOSICION') THEN
      v_dest := 'EN_TRATAMIENTO';
    ELSIF tnd = 'BENEFICIARIO' THEN
      v_dest := 'ASIGNADO_BENEFICIARIO';
    ELSE
      SELECT bool_or(o.clasificacion_actual_id IS NULL) INTO v_sin_clas FROM trz.objeto_trazable o
       WHERE o.id = x.objeto_id OR o.id IN (SELECT objeto_id FROM trz.fn_miembros(x.objeto_id) WHERE tipo_objeto = 'DISPOSITIVO');
      v_dest := CASE WHEN x.tipo_objeto = 'DISPOSITIVO' AND v_sin_clas THEN 'RECIBIDO'
                     WHEN x.tipo_objeto = 'LOTE' AND v_sin_clas THEN 'RECIBIDO' ELSE 'CLASIFICADO' END;
    END IF;
    PERFORM trz.fn_cambiar_estado(x.objeto_id, v_dest, CASE WHEN v_dest = 'ASIGNADO_BENEFICIARIO' THEN v_asg ELSE d.id END,
                                  NULL, true, nd.centro_id);
  END LOOP;
  IF v_asg IS NOT NULL THEN
    UPDATE ops.asignacion_beneficiario SET entregado_en = now() WHERE documento_id = v_asg;
    PERFORM ops.fn_cerrar_documento(v_asg);
  END IF;
  UPDATE ops.transferencia SET recibido_en = now(), confirmado_por = v_usuario, ubicacion_destino_id = v_ubic,
                               estado_transferencia = 'RECIBIDA' WHERE documento_id = d.id;
  UPDATE ops.transferencia SET estado_transferencia = 'CERRADA' WHERE documento_id = d.id;   -- dispara RN-03
  PERFORM ops.fn_cerrar_documento(d.id);
END $$;

-- Resultado de reacondicionamiento / reciclaje / disposición
CREATE FUNCTION api.fn_registrar_tratamiento(p_objeto uuid, p_tipo_tratamiento text, p_resultado text,
                                             p_evidencias uuid[] DEFAULT '{}', p_fracciones jsonb DEFAULT '[]'::jsonb,
                                             p_observacion text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); o trz.objeto_trazable; v_estado text; v_centro bigint; v_gestor bigint;
        tt cat.tipo_tratamiento; v_doc bigint; v_inicio timestamptz; v_peso numeric; v_frac numeric;
BEGIN
  SELECT * INTO o FROM trz.objeto_trazable WHERE id = trz.fn_id(p_objeto) FOR UPDATE;
  SELECT codigo INTO v_estado FROM cat.estado_trazabilidad WHERE id = o.estado_actual_id;
  IF v_estado <> 'EN_TRATAMIENTO' THEN RAISE EXCEPTION '% no está en tratamiento (estado %)', o.codigo, v_estado USING ERRCODE = 'EC409'; END IF;
  SELECT u.centro_id, c.organizacion_id INTO v_centro, v_gestor FROM org.ubicacion u JOIN org.centro c ON c.id = u.centro_id
   WHERE u.id = o.ubicacion_actual_id;
  PERFORM seg.fn_exigir_permiso(v_usuario, 'TRATAMIENTO.REGISTRAR', v_centro);
  SELECT * INTO tt FROM cat.tipo_tratamiento WHERE codigo = p_tipo_tratamiento AND activo;
  IF NOT EXISTS (SELECT 1 FROM org.centro_funcion cf JOIN cat.tipo_nodo tn ON tn.tipo_centro_id = cf.tipo_centro_id
                  WHERE cf.centro_id = v_centro AND tn.tipo_destino_id = tt.tipo_destino_id) THEN
    RAISE EXCEPTION 'El centro no está habilitado para el tratamiento %', p_tipo_tratamiento USING ERRCODE = 'EC422';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cat.clasificacion_destino_permitido WHERE clasificacion_id = o.clasificacion_actual_id
                    AND tipo_destino_id = tt.tipo_destino_id) THEN
    RAISE EXCEPTION 'La clasificación del objeto no admite el tratamiento %', p_tipo_tratamiento USING ERRCODE = 'EC422';
  END IF;
  SELECT max(ocurrido_en) INTO v_inicio FROM trz.historial_estado
   WHERE objeto_id = o.id AND estado_destino_id = o.estado_actual_id;
  v_doc := ops.fn_nuevo_documento('TRATAMIENTO', v_centro, v_gestor);
  PERFORM evd.fn_vincular(p_evidencias, v_doc);
  INSERT INTO ops.tratamiento(documento_id, objeto_id, tipo_tratamiento_id, gestor_organizacion_id, iniciado_en, finalizado_en,
                              resultado, observacion)
  VALUES (v_doc, o.id, tt.id, v_gestor, coalesce(v_inicio, now()), now(), p_resultado, p_observacion);
  INSERT INTO ops.tratamiento_fraccion(tratamiento_id, material_id, peso_kg)
  SELECT v_doc, cat.fn_id('material', f ->> 'material'), (f ->> 'peso_kg')::numeric FROM jsonb_array_elements(p_fracciones) f;
  SELECT peso_kg INTO v_peso FROM trz.dispositivo WHERE objeto_id = o.id;
  SELECT coalesce(sum(peso_kg), 0) INTO v_frac FROM ops.tratamiento_fraccion WHERE tratamiento_id = v_doc;
  IF v_frac > v_peso * 1.05 THEN
    RAISE EXCEPTION 'Las fracciones recuperadas (% kg) superan el peso del equipo (% kg)', v_frac, v_peso USING ERRCODE = 'EC422';
  END IF;
  IF p_resultado = 'FALLIDO' THEN
    PERFORM trz.fn_cambiar_estado(o.id, 'EN_EVALUACION', v_doc, 'Tratamiento fallido: requiere reevaluación técnica');
  ELSE
    PERFORM trz.fn_cambiar_estado(o.id, 'TRATADO', v_doc);
    IF tt.tipo_destino_id <> cat.fn_id('tipo_destino', 'REACONDICIONAMIENTO') AND o.ubicacion_actual_id IS NOT NULL THEN
      PERFORM inv.fn_registrar_movimiento(v_doc, o.id, o.ubicacion_actual_id, -1::smallint, 'EGRESO');   -- material consumido
    END IF;
  END IF;
  PERFORM ops.fn_cerrar_documento(v_doc);
  RETURN (SELECT uid FROM ops.documento_operativo WHERE id = v_doc);
END $$;

-- Cierre de trazabilidad (RN-08)
CREATE FUNCTION api.fn_cerrar_trazabilidad(p_objeto uuid, p_fecha_confirmacion timestamptz, p_evidencias uuid[],
                                           p_observacion text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); o trz.objeto_trazable; v_estado text; v_org bigint; v_destino smallint;
        v_centro bigint; v_doc bigint;
BEGIN
  SELECT * INTO o FROM trz.objeto_trazable WHERE id = trz.fn_id(p_objeto) FOR UPDATE;
  SELECT codigo INTO v_estado FROM cat.estado_trazabilidad WHERE id = o.estado_actual_id;
  SELECT centro_id INTO v_centro FROM org.ubicacion WHERE id = o.ubicacion_actual_id;
  IF v_estado = 'ASIGNADO_BENEFICIARIO' THEN
    SELECT a.beneficiario_id INTO v_org FROM ops.asignacion_beneficiario a JOIN ops.documento_operativo d ON d.id = a.documento_id
     WHERE a.objeto_id = o.id ORDER BY d.fecha_documento DESC LIMIT 1;
    v_destino := cat.fn_id('tipo_destino', 'REUTILIZACION');
    IF current_setting('app.organizacion_id')::bigint <> v_org AND NOT seg.fn_tiene_rol(v_usuario, 'COORDINADOR_LOGISTICO') THEN
      RAISE EXCEPTION 'Solo el beneficiario o el coordinador confirman este cierre' USING ERRCODE = 'EC403';
    END IF;
  ELSE
    SELECT tr.gestor_organizacion_id, tt.tipo_destino_id INTO v_org, v_destino
      FROM ops.tratamiento tr JOIN cat.tipo_tratamiento tt ON tt.id = tr.tipo_tratamiento_id
     WHERE tr.objeto_id = o.id AND tr.resultado IN ('EXITOSO','PARCIAL') ORDER BY tr.finalizado_en DESC LIMIT 1;
  END IF;
  PERFORM seg.fn_exigir_permiso(v_usuario, 'CIERRE.CONFIRMAR', v_centro);
  v_doc := ops.fn_nuevo_documento('CIERRE', v_centro, v_org);
  PERFORM evd.fn_vincular(p_evidencias, v_doc);
  INSERT INTO ops.cierre_trazabilidad(documento_id, objeto_id, tipo_destino_final_id, organizacion_destino_id,
                                      fecha_confirmacion, confirmado_por, observacion)
  VALUES (v_doc, o.id, v_destino, v_org, p_fecha_confirmacion, v_usuario, p_observacion);   -- dispara RN-08
  IF o.ubicacion_actual_id IS NOT NULL THEN
    PERFORM inv.fn_registrar_movimiento(v_doc, o.id, o.ubicacion_actual_id, -1::smallint, 'EGRESO');
  END IF;
  PERFORM trz.fn_cambiar_estado(o.id, 'CERRADO', v_doc);
  PERFORM trz.fn_actualizar_cache(o.id, 'cerrado', NULL);
  PERFORM ops.fn_cerrar_documento(v_doc);
  RETURN (SELECT uid FROM ops.documento_operativo WHERE id = v_doc);
END $$;

-- =====================================================================
-- MÓDULO MATEMÁTICO: lectura del dataset y registro de resultados (CP-07…CP-09)
-- =====================================================================
CREATE FUNCTION api.fn_dataset_flujo(p_escenario text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE e red.escenario_red; v jsonb;
BEGIN
  PERFORM seg.fn_exigir_permiso(seg.fn_usuario_actual(), 'RED.EJECUTAR_FLUJO');
  SELECT * INTO e FROM red.escenario_red WHERE codigo = p_escenario AND ecosistema_id = seg.fn_ecosistema_actual();
  IF NOT FOUND THEN RAISE EXCEPTION 'Escenario % no existe', p_escenario USING ERRCODE = 'EC404'; END IF;
  SELECT jsonb_build_object(
    'escenario', e.codigo,
    'unidad', (SELECT codigo FROM cat.unidad_medida WHERE id = e.unidad_id),
    'periodo', e.periodo,
    'aristas', coalesce((SELECT jsonb_agg(jsonb_build_object('origen', origen, 'destino', destino, 'capacidad', capacidad)
                                 ORDER BY origen, destino) FROM red.fn_dataset_flujo(e.id)), '[]'),
    'fuentes', coalesce((SELECT jsonb_agg(jsonb_build_object('nodo', n.codigo, 'oferta', en.oferta) ORDER BY n.codigo)
                  FROM red.nodo n JOIN cat.tipo_nodo t ON t.id = n.tipo_nodo_id
                  LEFT JOIN red.escenario_nodo en ON en.nodo_id = n.id AND en.escenario_id = e.id
                 WHERE n.ecosistema_id = e.ecosistema_id AND n.activo AND t.es_fuente), '[]'),
    'sumideros', coalesce((SELECT jsonb_agg(jsonb_build_object('nodo', n.codigo, 'demanda', en.demanda) ORDER BY n.codigo)
                  FROM red.nodo n JOIN cat.tipo_nodo t ON t.id = n.tipo_nodo_id
                  LEFT JOIN red.escenario_nodo en ON en.nodo_id = n.id AND en.escenario_id = e.id
                 WHERE n.ecosistema_id = e.ecosistema_id AND n.activo AND t.es_sumidero), '[]')) INTO v;
  RETURN v || jsonb_build_object('hash', encode(digest(v::text, 'sha256'), 'hex'));
END $$;

CREATE FUNCTION api.fn_registrar_resultado_flujo(p_escenario text, p_hash text, p_flujo_maximo numeric, p_flujos jsonb,
                                                 p_cortes jsonb, p_algoritmo text DEFAULT 'EDMONDS_KARP',
                                                 p_version text DEFAULT '1.0', p_iniciado_en timestamptz DEFAULT now())
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); e red.escenario_red; v_ds jsonb := api.fn_dataset_flujo(p_escenario);
        v_ej bigint; c jsonb; v_corte bigint; i int := 0;
BEGIN
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
    SELECT v_corte, a.id FROM jsonb_array_elements(c -> 'aristas') par
      JOIN red.nodo no ON no.codigo = par ->> 0 AND no.ecosistema_id = e.ecosistema_id
      JOIN red.nodo nd ON nd.codigo = par ->> 1 AND nd.ecosistema_id = e.ecosistema_id
      JOIN red.arista a ON a.nodo_origen_id = no.id AND a.nodo_destino_id = nd.id;
  END LOOP;
  INSERT INTO integ.outbox_evento(ecosistema_id, agregado, agregado_id, tipo_evento, payload)
  VALUES (e.ecosistema_id, 'EJECUCION_FLUJO', v_ej, 'red.flujo_calculado',
          jsonb_build_object('escenario', e.codigo, 'flujo_maximo', p_flujo_maximo, 'cortes', i));
  RETURN v_ej;
END $$;

-- =====================================================================
-- VISTAS v1 (lectura; RLS aplica al rol que consulta)
-- =====================================================================
CREATE VIEW api.v1_objeto WITH (security_invoker = true) AS
SELECT o.uid, o.codigo, o.tipo_objeto, e.codigo AS estado, k.codigo AS clasificacion, c.codigo AS categoria,
       d.peso_kg, d.contiene_almacenamiento, og.nombre AS organizacion_origen, ce.codigo AS centro_actual,
       u.codigo AS ubicacion_actual, o.registrado_en, o.cerrado_en,
       round(extract(epoch FROM now() - (SELECT max(h.ocurrido_en) FROM trz.historial_estado h WHERE h.objeto_id = o.id)) / 86400, 1)
         AS dias_en_estado,
       o.ecosistema_id
  FROM trz.objeto_trazable o
  JOIN cat.estado_trazabilidad e ON e.id = o.estado_actual_id
  JOIN org.organizacion og ON og.id = o.organizacion_origen_id
  LEFT JOIN cat.clasificacion_tecnica k ON k.id = o.clasificacion_actual_id
  LEFT JOIN trz.dispositivo d ON d.objeto_id = o.id
  LEFT JOIN cat.categoria_raee c ON c.id = d.categoria_id
  LEFT JOIN org.ubicacion u ON u.id = o.ubicacion_actual_id
  LEFT JOIN org.centro ce ON ce.id = u.centro_id;

CREATE VIEW api.v1_linea_trazabilidad WITH (security_invoker = true) AS     -- CP-14
SELECT o.uid AS objeto_uid, o.codigo, h.ocurrido_en, eo.codigo AS estado_origen, ed.codigo AS estado_destino,
       d.tipo_documento, d.numero AS documento, ce.codigo AS centro, us.alias AS usuario, h.canal, h.observacion,
       (SELECT count(*) FROM evd.evidencia_vinculo v WHERE v.documento_id = d.id) AS evidencias,
       row_number() OVER (PARTITION BY o.id ORDER BY h.ocurrido_en, h.id) AS paso
  FROM trz.historial_estado h
  JOIN trz.objeto_trazable o ON o.id = h.objeto_id
  JOIN cat.estado_trazabilidad ed ON ed.id = h.estado_destino_id
  LEFT JOIN cat.estado_trazabilidad eo ON eo.id = h.estado_origen_id
  LEFT JOIN ops.documento_operativo d ON d.id = h.documento_id
  LEFT JOIN org.centro ce ON ce.id = d.centro_id
  JOIN seg.usuario us ON us.id = h.usuario_id;

CREATE VIEW api.v1_inventario WITH (security_invoker = true) AS
SELECT ce.codigo AS centro, ub.codigo AS ubicacion, ub.ruta::text AS ruta, c.codigo AS categoria, cr.codigo AS categoria_raiz,
       k.codigo AS clasificacion, s.unidades, s.peso_kg, s.actualizado_en
  FROM inv.saldo_ubicacion s
  JOIN org.ubicacion ub ON ub.id = s.ubicacion_id
  JOIN org.centro ce ON ce.id = ub.centro_id
  JOIN cat.categoria_raee c ON c.id = s.categoria_id
  JOIN cat.categoria_raee cr ON cr.id = subltree(c.ruta, 0, 1)::text::smallint
  JOIN cat.clasificacion_tecnica k ON k.id = s.clasificacion_id
 WHERE s.unidades > 0;

CREATE VIEW api.v1_lote_resumen WITH (security_invoker = true) AS          -- atributos derivados del lote
SELECT o.uid, o.codigo, l.proposito, e.codigo AS estado,
       count(m.objeto_id) FILTER (WHERE m.tipo_objeto = 'DISPOSITIVO') AS cantidad_dispositivos,
       coalesce(sum(d.peso_kg), 0) AS peso_total_kg,
       l.peso_declarado_kg,
       coalesce(sum(d.peso_kg), 0) - l.peso_declarado_kg AS diferencia_kg,
       max(m.profundidad) AS niveles_anidamiento
  FROM trz.lote l
  JOIN trz.objeto_trazable o ON o.id = l.objeto_id
  JOIN cat.estado_trazabilidad e ON e.id = o.estado_actual_id
  LEFT JOIN LATERAL trz.fn_miembros(l.objeto_id) m ON true
  LEFT JOIN trz.dispositivo d ON d.objeto_id = m.objeto_id
 GROUP BY o.uid, o.codigo, l.proposito, e.codigo, l.peso_declarado_kg;

CREATE VIEW api.v1_utilizacion_arista WITH (security_invoker = true) AS    -- RF-INT-05: capacidad usada en el periodo
SELECT a.id AS arista_id, no.codigo AS origen, nd.codigo AS destino, um.codigo AS unidad, ca.periodo, ca.capacidad,
       coalesce(sum(CASE um.codigo WHEN 'KG' THEN x.peso_kg ELSE x.unidades END), 0) AS consumo,
       round(100 * coalesce(sum(CASE um.codigo WHEN 'KG' THEN x.peso_kg ELSE x.unidades END), 0) / nullif(ca.capacidad, 0), 2) AS utilizacion_pct,
       a.ecosistema_id
  FROM red.arista a
  JOIN red.nodo no ON no.id = a.nodo_origen_id
  JOIN red.nodo nd ON nd.id = a.nodo_destino_id
  JOIN red.capacidad_arista ca ON ca.arista_id = a.id AND ca.vigencia @> now()
  JOIN cat.unidad_medida um ON um.id = ca.unidad_id
  LEFT JOIN LATERAL (
    SELECT t.unidades, t.peso_kg FROM ops.transferencia t JOIN ops.documento_operativo d ON d.id = t.documento_id
     WHERE t.arista_id = a.id AND t.estado_transferencia <> 'ANULADA'
       AND d.fecha_documento >= date_trunc(CASE ca.periodo WHEN 'DIA' THEN 'day' WHEN 'SEMANA' THEN 'week' ELSE 'month' END, now())
    UNION ALL
    SELECT r.unidades, r.peso_kg FROM ops.recoleccion r JOIN ops.documento_operativo d ON d.id = r.documento_id
     WHERE r.arista_id = a.id AND d.estado_documento <> 'ANULADO'
       AND d.fecha_documento >= date_trunc(CASE ca.periodo WHEN 'DIA' THEN 'day' WHEN 'SEMANA' THEN 'week' ELSE 'month' END, now())
  ) x ON true
 GROUP BY a.id, no.codigo, nd.codigo, um.codigo, ca.periodo, ca.capacidad, a.ecosistema_id;

CREATE VIEW api.v1_resultado_flujo WITH (security_invoker = true) AS
SELECT DISTINCT ON (e.id) e.codigo AS escenario, b.codigo AS escenario_base, j.id AS ejecucion_id, j.algoritmo, j.flujo_maximo,
       j.finalizado_en, j.duracion_ms, j.hash_entrada,
       (SELECT count(*) FROM red.corte_minimo c WHERE c.ejecucion_id = j.id) AS cortes_minimos,
       (SELECT string_agg(no.codigo || '→' || nd.codigo, ', ' ORDER BY no.codigo, nd.codigo)
          FROM red.resultado_flujo_arista r JOIN red.arista a ON a.id = r.arista_id
          JOIN red.nodo no ON no.id = a.nodo_origen_id JOIN red.nodo nd ON nd.id = a.nodo_destino_id
         WHERE r.ejecucion_id = j.id AND r.saturada) AS aristas_saturadas,
       e.ecosistema_id
  FROM red.escenario_red e
  JOIN red.ejecucion_flujo j ON j.escenario_id = e.id AND j.estado = 'OK'
  LEFT JOIN red.escenario_red b ON b.id = e.escenario_base_id
 ORDER BY e.id, j.finalizado_en DESC;

CREATE VIEW api.v1_corte_minimo WITH (security_invoker = true) AS
SELECT e.codigo AS escenario, c.ejecucion_id, c.numero_corte, c.capacidad_corte, c.lado_fuente,
       string_agg(no.codigo || '→' || nd.codigo, ', ' ORDER BY no.codigo, nd.codigo) AS aristas_corte
  FROM red.corte_minimo c
  JOIN red.ejecucion_flujo j ON j.id = c.ejecucion_id
  JOIN red.escenario_red e ON e.id = j.escenario_id
  JOIN red.corte_minimo_arista ca ON ca.corte_id = c.id
  JOIN red.arista a ON a.id = ca.arista_id
  JOIN red.nodo no ON no.id = a.nodo_origen_id JOIN red.nodo nd ON nd.id = a.nodo_destino_id
 GROUP BY e.codigo, c.ejecucion_id, c.numero_corte, c.capacidad_corte, c.lado_fuente;

CREATE VIEW api.v1_indicador WITH (security_invoker = true) AS
SELECT DISTINCT ON (i.id, m.centro_id) i.codigo, i.nombre, i.dimension, i.materia_origen, i.unidad, m.valor, i.meta,
       CASE WHEN i.meta IS NULL THEN NULL
            WHEN i.sentido = 'MAYOR_MEJOR' THEN m.valor >= i.meta
            WHEN i.sentido = 'MENOR_MEJOR' THEN m.valor <= i.meta END AS cumple_meta,
       m.periodo, m.calculado_en, m.ecosistema_id
  FROM ind.indicador i JOIN ind.medicion_indicador m ON m.indicador_id = i.id
 ORDER BY i.id, m.centro_id, upper(m.periodo) DESC, m.calculado_en DESC;

CREATE VIEW api.v1_alerta_abierta WITH (security_invoker = true) AS
SELECT a.id, r.codigo AS regla, r.severidad, a.mensaje, a.generada_en, o.codigo AS objeto, a.ecosistema_id
  FROM ind.alerta a JOIN ind.regla_alerta r ON r.id = a.regla_id LEFT JOIN trz.objeto_trazable o ON o.id = a.objeto_id
 WHERE a.estado <> 'RESUELTA';

CREATE VIEW api.v1_diccionario AS
SELECT d.esquema, d.nombre AS dominio, e.nombre_tabla, e.nombre_negocio, e.tipo_entidad, e.clasificacion_datos,
       e.descripcion AS descripcion_tabla, a.posicion, a.nombre_columna, a.tipo_dato, a.nulo, a.es_pk, a.es_fk,
       a.referencia, a.valor_defecto, a.descripcion AS descripcion_columna, a.es_pii, a.es_derivado
  FROM meta.entidad e JOIN meta.dominio d ON d.id = e.dominio_id JOIN meta.atributo a ON a.entidad_id = e.id;

CREATE VIEW api.v1_glosario AS
SELECT termino, definicion, sinonimos, termino_ae, termino_md, termino_bd, termino_nube, termino_inn, entidad_ref
  FROM meta.termino_glosario;

-- Línea de trazabilidad completa como documento JSON (herramienta MCP consultar_trazabilidad)
CREATE FUNCTION api.fn_linea_trazabilidad(p_codigo text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER AS $$
  SELECT jsonb_build_object(
    'objeto', to_jsonb(v) - 'ecosistema_id',
    'pasos', (SELECT jsonb_agg(to_jsonb(l) - 'objeto_uid' - 'codigo' ORDER BY l.paso) FROM api.v1_linea_trazabilidad l WHERE l.codigo = v.codigo),
    'evaluacion_vigente', (SELECT jsonb_build_object('clasificacion', k.codigo, 'destino_sugerido', td.codigo, 'funcional', et.funcional,
                                                     'modalidad', et.modalidad, 'fecha', et.evaluado_en)
                             FROM ops.evaluacion_tecnica et JOIN cat.clasificacion_tecnica k ON k.id = et.clasificacion_id
                             JOIN cat.tipo_destino td ON td.id = et.tipo_destino_sugerido_id
                            WHERE et.objeto_id = (SELECT id FROM trz.objeto_trazable WHERE uid = v.uid) AND et.vigente),
    'cierre', (SELECT jsonb_build_object('destino_final', td.codigo, 'organizacion', og.nombre, 'fecha_confirmacion', c.fecha_confirmacion)
                 FROM ops.cierre_trazabilidad c JOIN cat.tipo_destino td ON td.id = c.tipo_destino_final_id
                 JOIN org.organizacion og ON og.id = c.organizacion_destino_id
                WHERE c.objeto_id = (SELECT id FROM trz.objeto_trazable WHERE uid = v.uid)),
    'trazabilidad_completa', v.estado = 'CERRADO')
  FROM api.v1_objeto v WHERE v.codigo = p_codigo
$$;

-- =====================================================================
-- INDICADORES Y ALERTAS (series históricas)
-- =====================================================================
CREATE FUNCTION ind.fn_calcular_indicadores(p_desde date, p_hasta date) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_eco bigint := seg.fn_ecosistema_actual(); v_per daterange := daterange(p_desde, p_hasta, '[]'); v_n int;
BEGIN
  WITH disp AS (
    SELECT o.id, e.codigo AS estado, o.registrado_en, o.cerrado_en FROM trz.objeto_trazable o
      JOIN cat.estado_trazabilidad e ON e.id = o.estado_actual_id
     WHERE o.ecosistema_id = v_eco AND o.tipo_objeto = 'DISPOSITIVO' AND o.registrado_en::date <@ v_per AND e.codigo <> 'ANULADO'),
  cierres AS (
    SELECT c.*, td.codigo AS destino FROM ops.cierre_trazabilidad c JOIN cat.tipo_destino td ON td.id = c.tipo_destino_final_id
      JOIN disp ON disp.id = c.objeto_id),
  valores(codigo, valor) AS (
    SELECT 'TRZ_COMPLETA', 100.0 * count(*) FILTER (WHERE estado = 'CERRADO') / nullif(count(*), 0) FROM disp
    UNION ALL SELECT 'TASA_REUTILIZACION', 100.0 * count(*) FILTER (WHERE destino = 'REUTILIZACION') / nullif(count(*), 0) FROM cierres
    UNION ALL SELECT 'TASA_RECICLAJE', 100.0 * count(*) FILTER (WHERE destino = 'RECICLAJE') / nullif(count(*), 0) FROM cierres
    UNION ALL SELECT 'TASA_DISPOSICION', 100.0 * count(*) FILTER (WHERE destino = 'DISPOSICION_CONTROLADA') / nullif(count(*), 0) FROM cierres
    UNION ALL SELECT 'KG_MATERIAL_RECUPERADO', coalesce(sum(f.peso_kg), 0) FROM ops.tratamiento_fraccion f
              JOIN ops.tratamiento t ON t.documento_id = f.tratamiento_id JOIN disp ON disp.id = t.objeto_id
    UNION ALL SELECT 'DIAS_CICLO_PROMEDIO', avg(extract(epoch FROM cerrado_en - registrado_en) / 86400) FROM disp WHERE cerrado_en IS NOT NULL
    UNION ALL SELECT 'BENEFICIARIOS_ATENDIDOS', count(DISTINCT organizacion_destino_id) FROM cierres WHERE destino = 'REUTILIZACION'
    UNION ALL SELECT 'FOTOS_SIN_METADATOS_PCT', 100.0 * count(*) FILTER (WHERE metadatos_limpios) / nullif(count(*), 0)
              FROM evd.evidencia WHERE ecosistema_id = v_eco AND mime LIKE 'image/%'
    UNION ALL SELECT 'UTILIZACION_RED_PROMEDIO', avg(utilizacion_pct) FROM api.v1_utilizacion_arista WHERE ecosistema_id = v_eco
  )
  INSERT INTO ind.medicion_indicador(indicador_id, ecosistema_id, centro_id, periodo, valor)
  SELECT i.id, v_eco, NULL, v_per, round(v.valor::numeric, 4) FROM valores v JOIN ind.indicador i ON i.codigo = v.codigo
   WHERE v.valor IS NOT NULL
  ON CONFLICT (indicador_id, ecosistema_id, centro_id, periodo) DO UPDATE SET valor = EXCLUDED.valor, calculado_en = now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;

CREATE FUNCTION ind.fn_generar_alertas() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_eco bigint := seg.fn_ecosistema_actual(); v_n int := 0; v_k int; r ind.regla_alerta;
BEGIN
  SELECT * INTO r FROM ind.regla_alerta WHERE codigo = 'ARISTA_SATURADA' AND activa;
  IF FOUND THEN
    INSERT INTO ind.alerta(regla_id, ecosistema_id, arista_id, mensaje)
    SELECT r.id, v_eco, u.arista_id, format('Arista %s→%s al %s%% de su capacidad %s', u.origen, u.destino, u.utilizacion_pct, lower(u.periodo))
      FROM api.v1_utilizacion_arista u
     WHERE u.ecosistema_id = v_eco AND u.utilizacion_pct >= r.umbral
       AND NOT EXISTS (SELECT 1 FROM ind.alerta a WHERE a.regla_id = r.id AND a.arista_id = u.arista_id AND a.estado <> 'RESUELTA');
    GET DIAGNOSTICS v_k = ROW_COUNT; v_n := v_n + v_k;
  END IF;
  SELECT * INTO r FROM ind.regla_alerta WHERE codigo = 'OBJETO_ESTANCADO' AND activa;
  IF FOUND THEN
    INSERT INTO ind.alerta(regla_id, ecosistema_id, objeto_id, mensaje)
    SELECT r.id, v_eco, o.id, format('%s lleva %s días en %s', v.codigo, v.dias_en_estado, v.estado)
      FROM api.v1_objeto v JOIN trz.objeto_trazable o ON o.uid = v.uid
     WHERE v.ecosistema_id = v_eco AND v.estado NOT IN ('CERRADO','ANULADO') AND v.dias_en_estado >= r.umbral
       AND NOT EXISTS (SELECT 1 FROM ind.alerta a WHERE a.regla_id = r.id AND a.objeto_id = o.id AND a.estado <> 'RESUELTA');
    GET DIAGNOSTICS v_k = ROW_COUNT; v_n := v_n + v_k;
  END IF;
  RETURN v_n;
END $$;

-- =====================================================================
-- CAPA MCP: catálogo dinámico, autorización, límite de uso y bitácora
-- =====================================================================
CREATE VIEW api.v1_mcp_catalogo AS                                  -- tools/list para el usuario del contexto
SELECT h.nombre, h.titulo, h.descripcion, h.tipo, h.esquema_entrada, h.esquema_salida, h.requiere_confirmacion, h.version
  FROM mcp.herramienta h
 WHERE h.activa AND EXISTS (SELECT 1 FROM mcp.herramienta_rol hr
                             JOIN seg.fn_roles_efectivos(nullif(current_setting('app.usuario_id', true), '')::bigint) r ON r.rol_id = hr.rol_id
                            WHERE hr.herramienta_id = h.id);

CREATE FUNCTION mcp.fn_sanear(p_args jsonb) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(jsonb_object_agg(key, CASE WHEN key ~* '(correo|email|password|clave|token|secreto)' THEN '"***"'::jsonb ELSE value END), '{}'::jsonb)
    FROM jsonb_each(coalesce(p_args, '{}'::jsonb))
$$;

CREATE FUNCTION api.fn_mcp_autorizar(p_herramienta text, p_argumentos jsonb, p_sesion text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); h mcp.herramienta; v_estado text; v_recientes int;
BEGIN
  SELECT * INTO h FROM mcp.herramienta WHERE nombre = p_herramienta AND activa;
  IF NOT FOUND THEN
    v_estado := 'DENEGADO';
  ELSIF NOT EXISTS (SELECT 1 FROM mcp.herramienta_rol hr JOIN seg.fn_roles_efectivos(v_usuario) r ON r.rol_id = hr.rol_id
                     WHERE hr.herramienta_id = h.id) THEN
    v_estado := 'DENEGADO';
  ELSE
    SELECT count(*) INTO v_recientes FROM mcp.invocacion
     WHERE usuario_id = v_usuario AND herramienta_id = h.id AND ocurrido_en > now() - interval '1 minute';
    v_estado := CASE WHEN v_recientes >= h.limite_por_minuto THEN 'LIMITE_EXCEDIDO'
                     WHEN h.requiere_confirmacion AND NOT coalesce((p_argumentos ->> '_confirmado')::boolean, false) THEN 'PENDIENTE_CONFIRMACION'
                     ELSE 'AUTORIZADO' END;
  END IF;
  IF v_estado <> 'AUTORIZADO' THEN                                  -- se registra el rechazo o la espera de confirmación
    INSERT INTO mcp.invocacion(herramienta_id, nombre_solicitado, usuario_id, sesion_mcp, argumentos, argumentos_hash, estado, request_id)
    VALUES (h.id, left(p_herramienta, 160), v_usuario, p_sesion, mcp.fn_sanear(p_argumentos), encode(digest(coalesce(p_argumentos, '{}')::text, 'sha256'), 'hex'),
            v_estado, nullif(current_setting('app.request_id', true), ''));
    IF h.id IS NULL THEN                                           -- herramienta inexistente: evento de seguridad
      INSERT INTO aud.evento_seguridad(tipo, usuario_id, detalle, request_id)
      VALUES ('MCP_RECHAZO', v_usuario, jsonb_build_object('herramienta', p_herramienta), nullif(current_setting('app.request_id', true), ''));
    END IF;
  END IF;
  RETURN jsonb_build_object('autorizado', v_estado = 'AUTORIZADO', 'estado', v_estado, 'objeto_sql', h.objeto_sql,
                            'requiere_confirmacion', h.requiere_confirmacion);
END $$;

CREATE FUNCTION api.fn_mcp_registrar(p_herramienta text, p_sesion text, p_argumentos jsonb, p_estado text,
                                     p_filas integer DEFAULT NULL, p_duracion_ms integer DEFAULT NULL, p_error text DEFAULT NULL)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  INSERT INTO mcp.invocacion(herramienta_id, nombre_solicitado, usuario_id, sesion_mcp, argumentos, argumentos_hash, estado, filas, duracion_ms, error, request_id)
  SELECT h.id, h.nombre, seg.fn_usuario_actual(), p_sesion, mcp.fn_sanear(p_argumentos),
         encode(digest(coalesce(p_argumentos, '{}')::text, 'sha256'), 'hex'), p_estado, p_filas, p_duracion_ms, p_error,
         nullif(current_setting('app.request_id', true), '')
    FROM mcp.herramienta h WHERE h.nombre = p_herramienta
$$;

CREATE FUNCTION api.fn_mcp_leer_recurso(p_uri text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER AS $$
DECLARE v_tipo text := split_part(replace(p_uri, 'ecoraee://', ''), '/', 1);
        v_arg  text := split_part(replace(p_uri, 'ecoraee://', ''), '/', 2);
BEGIN
  RETURN CASE v_tipo
    WHEN 'objeto'      THEN api.fn_linea_trazabilidad(v_arg)
    WHEN 'diccionario' THEN (SELECT jsonb_agg(to_jsonb(d) ORDER BY d.posicion) FROM api.v1_diccionario d WHERE d.nombre_tabla = v_arg)
    WHEN 'glosario'    THEN (SELECT jsonb_agg(to_jsonb(g)) FROM api.v1_glosario g)
    WHEN 'escenario'   THEN (SELECT jsonb_build_object('resultado', to_jsonb(r),
                                     'cortes', (SELECT jsonb_agg(to_jsonb(c)) FROM api.v1_corte_minimo c WHERE c.escenario = v_arg AND c.ejecucion_id = r.ejecucion_id))
                               FROM api.v1_resultado_flujo r WHERE r.escenario = v_arg)
    ELSE NULL END;
END $$;
