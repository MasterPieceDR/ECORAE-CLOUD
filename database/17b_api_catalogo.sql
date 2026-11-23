-- Operaciones de imagen de catálogo y consulta de disponibilidad de serie.
-- El bucket de imágenes de modelos es el bucket de evidencias configurado en la API;
-- únicamente se guarda la clave relativa en el catálogo.
CREATE OR REPLACE FUNCTION api.fn_preparar_imagen_modelo(p_modelo uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
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
END $$;

CREATE OR REPLACE FUNCTION api.fn_asignar_imagen_modelo(p_modelo uuid, p_clave text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  -- La comprobación vuelve a bloquear la fila: la ventana puede haber vencido tras la subida.
  PERFORM api.fn_preparar_imagen_modelo(p_modelo);
  IF p_clave IS NULL OR p_clave !~ ('^catalogo/' || p_modelo::text || '/[0-9]{4}/[0-9]{2}/[0-9a-f]{32}[.](jpg|png|webp)$') THEN
    RAISE EXCEPTION 'Clave de imagen inválida para el modelo' USING ERRCODE = 'EC422';
  END IF;
  UPDATE cat.modelo_equipo SET imagen_clave = p_clave, actualizado_en = now() WHERE uid = p_modelo;
END $$;

-- Lectura con los privilegios del usuario, como el resto de las vistas de la API.
CREATE OR REPLACE VIEW api.v1_modelo_imagen WITH (security_invoker = true) AS
  SELECT uid, imagen_clave FROM cat.modelo_equipo WHERE imagen_clave IS NOT NULL;
GRANT SELECT ON api.v1_modelo_imagen TO ecoraee_lectura;

-- El índice de series abarca todo el ecosistema, incluso objetos ocultos por RLS.
-- Solo se revela el booleano, no el equipo de otra organización.
CREATE OR REPLACE FUNCTION api.fn_serie_disponible(p_serie text, p_excluir uuid DEFAULT NULL) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM trz.dispositivo d JOIN trz.objeto_trazable o ON o.id = d.objeto_id
     WHERE d.ecosistema_serie_id = seg.fn_ecosistema_actual() AND d.serie_vigente
       AND d.numero_serie = nullif(upper(btrim(p_serie)), '')
       AND (p_excluir IS NULL OR o.uid <> p_excluir)
  )
$$;
REVOKE ALL ON FUNCTION api.fn_preparar_imagen_modelo(uuid), api.fn_asignar_imagen_modelo(uuid,text),
  api.fn_serie_disponible(text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION api.fn_preparar_imagen_modelo(uuid), api.fn_asignar_imagen_modelo(uuid,text),
  api.fn_serie_disponible(text,uuid) TO ecoraee_app;
