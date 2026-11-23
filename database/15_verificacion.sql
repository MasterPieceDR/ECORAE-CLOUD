-- =====================================================================
-- EcoRAEE Cloud · Script 15: verificación de la base de datos desde la API
-- psql -1 -f 15_verificacion.sql (después del 14)
--   api.fn_verificar_base()            estructura (PK, FK, CHECK, RLS, auditoría), volumen y 8 comprobaciones de consistencia
--   api.fn_verificar_objeto(codigo)    las filas reales que la base guarda de un equipo: prueba de persistencia
-- No exponen datos personales: solo conteos, códigos y estados.
-- =====================================================================

CREATE FUNCTION api.fn_verificar_base() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_u bigint := seg.fn_usuario_actual(); v_esq text[] := ARRAY['seg','org','cat','trz','ops','inv','evd','red','ind','gob','mcp','aud','meta','integ','edu'];
        v_estructura jsonb; v_volumen jsonb; v_checks jsonb; v_inicio timestamptz := clock_timestamp();
BEGIN
  IF v_u IS NULL THEN RAISE EXCEPTION 'Inicia sesión para verificar la base' USING ERRCODE = 'EC401'; END IF;

  SELECT jsonb_build_object(
    'esquemas', (SELECT count(*) FROM pg_namespace WHERE nspname = ANY(v_esq || 'api'::text)),
    'tablas', (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = ANY(v_esq) AND c.relkind IN ('r','p') AND NOT c.relispartition),
    'vistas_contrato', (SELECT count(*) FROM pg_views WHERE schemaname = 'api'),
    'funciones_contrato', (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'api'),
    'claves_primarias', count(*) FILTER (WHERE c.contype = 'p'),
    'claves_foraneas', count(*) FILTER (WHERE c.contype = 'f'),
    'restricciones_check', count(*) FILTER (WHERE c.contype = 'c'),
    'restricciones_unicas', count(*) FILTER (WHERE c.contype = 'u'),
    'restricciones_exclusion', count(*) FILTER (WHERE c.contype = 'x'),
    'tablas_con_rls', (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                        WHERE n.nspname = ANY(v_esq) AND c.relrowsecurity AND NOT c.relispartition),
    'triggers_auditoria', (SELECT count(*) FROM pg_trigger WHERE tgname = 'tg_auditoria' AND NOT tgisinternal),
    'triggers_reglas', (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
                         WHERE n.nspname = ANY(v_esq) AND NOT t.tgisinternal AND t.tgname <> 'tg_auditoria'))
    INTO v_estructura
    FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace AND NOT EXISTS (
         SELECT 1 FROM pg_class r WHERE r.oid = c.conrelid AND r.relispartition)
   WHERE n.nspname = ANY(v_esq);

  SELECT jsonb_build_object(
    'usuarios', (SELECT count(*) FROM seg.usuario),
    'organizaciones', (SELECT count(*) FROM org.organizacion),
    'centros', (SELECT count(*) FROM org.centro),
    'dispositivos', (SELECT count(*) FROM trz.dispositivo),
    'lotes', (SELECT count(*) FROM trz.objeto_trazable WHERE tipo_objeto = 'LOTE'),
    'cambios_de_estado', (SELECT count(*) FROM trz.historial_estado),
    'documentos', (SELECT count(*) FROM ops.documento_operativo),
    'evidencias', (SELECT count(*) FROM evd.evidencia),
    'nodos_red', (SELECT count(*) FROM red.nodo), 'aristas_red', (SELECT count(*) FROM red.arista),
    'escenarios', (SELECT count(*) FROM red.escenario_red),
    'ejecuciones_flujo', (SELECT count(*) FROM red.ejecucion_flujo),
    'contenidos_capacitacion', (SELECT count(*) FROM edu.contenido),
    'registros_auditoria', (SELECT count(*) FROM aud.log_cambio))
    INTO v_volumen;

  -- Cada comprobación cuenta violaciones: 0 = correcto
  WITH c(id, descripcion, regla, problemas) AS (VALUES
    ('C1', 'El estado guardado de cada objeto coincide con el último de su historial', 'RN-01',
     (SELECT count(*) FROM trz.objeto_trazable o WHERE o.estado_actual_id IS DISTINCT FROM
        (SELECT h.estado_destino_id FROM trz.historial_estado h WHERE h.objeto_id = o.id ORDER BY h.ocurrido_en DESC, h.id DESC LIMIT 1))),
    ('C2', 'Todo objeto tiene su registro inicial en el historial', 'RN-01',
     (SELECT count(*) FROM trz.objeto_trazable o WHERE NOT EXISTS (SELECT 1 FROM trz.historial_estado h WHERE h.objeto_id = o.id AND h.estado_origen_id IS NULL))),
    ('C3', 'Todo dispositivo tiene su objeto trazable (subtipo con supertipo)', 'EER',
     (SELECT count(*) FROM trz.objeto_trazable o WHERE o.tipo_objeto = 'DISPOSITIVO' AND NOT EXISTS (SELECT 1 FROM trz.dispositivo d WHERE d.objeto_id = o.id))),
    ('C4', 'Ningún objeto está en dos lotes vigentes al mismo tiempo', 'Lotes',
     (SELECT count(*) FROM (SELECT objeto_id FROM trz.lote_composicion WHERE upper_inf(vigencia) GROUP BY objeto_id HAVING count(*) > 1) x)),
    ('C5', 'Ningún saldo de inventario es negativo', 'RN-06',
     (SELECT count(*) FROM inv.saldo_ubicacion WHERE unidades < 0 OR peso_kg < 0)),
    ('C6', 'Todo documento cerrado tiene fecha de cierre', 'RN-03',
     (SELECT count(*) FROM ops.documento_operativo WHERE estado_documento = 'CERRADO' AND fecha_cierre IS NULL)),
    ('C7', 'Todo equipo cerrado tiene un documento de cierre', 'RN-08',
     (SELECT count(*) FROM trz.objeto_trazable o JOIN cat.estado_trazabilidad e ON e.id = o.estado_actual_id
       WHERE e.codigo = 'CERRADO' AND NOT EXISTS (SELECT 1 FROM ops.cierre_trazabilidad ct WHERE ct.objeto_id = o.id))),
    ('C8', 'Ningún equipo asignado a un beneficiario con almacenamiento carece de certificado de borrado', 'RN-09',
     (SELECT count(*) FROM api.v1_objeto_operativo v WHERE v.estado IN ('ASIGNADO_BENEFICIARIO','CERRADO') AND v.beneficiario IS NOT NULL
        AND v.contiene_almacenamiento AND NOT v.tiene_certificado_borrado)))
  SELECT jsonb_agg(jsonb_build_object('id', id, 'descripcion', descripcion, 'regla', regla, 'problemas', problemas, 'ok', problemas = 0) ORDER BY id)
    INTO v_checks FROM c;

  RETURN jsonb_build_object(
    'conexion', jsonb_build_object('ok', true, 'motor', split_part(version(), ' on ', 1), 'base', current_database(),
                                   'tamano', pg_size_pretty(pg_database_size(current_database())),
                                   'usuario_conexion', session_user, 'zona_horaria', current_setting('TimeZone')),
    'scripts', jsonb_build_object('10_integracion', to_regprocedure('api.fn_perfil()') IS NOT NULL,
                                  '13_mejoras', to_regclass('seg.solicitud_rol') IS NOT NULL,
                                  '14_dispositivos', to_regprocedure('api.fn_anular_objeto(uuid,text)') IS NOT NULL,
                                  '15_verificacion', true),
    'estructura', v_estructura, 'volumen', v_volumen, 'consistencia', v_checks,
    'todo_correcto', NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_checks) x WHERE NOT (x ->> 'ok')::boolean),
    'duracion_ms', round(extract(epoch FROM clock_timestamp() - v_inicio) * 1000, 1));
END $$;

-- Persistencia: lo que la base guarda de un equipo, tabla por tabla. Respeta la visibilidad del usuario (RLS).
CREATE FUNCTION api.fn_verificar_objeto(p_codigo text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE o trz.objeto_trazable;
BEGIN
  SELECT * INTO o FROM trz.objeto_trazable WHERE codigo = upper(p_codigo) AND ecosistema_id = seg.fn_ecosistema_actual();
  IF o.id IS NULL OR NOT seg.fn_ve_objeto(o.id, o.organizacion_origen_id) THEN
    RAISE EXCEPTION 'El objeto % no existe o no tienes acceso a él', p_codigo USING ERRCODE = 'EC404';
  END IF;
  RETURN jsonb_build_object(
    'trz.objeto_trazable', (SELECT jsonb_build_object('id', o.id, 'uid', o.uid, 'codigo', o.codigo, 'tipo_objeto', o.tipo_objeto,
                              'estado_actual', (SELECT codigo FROM cat.estado_trazabilidad WHERE id = o.estado_actual_id),
                              'clasificacion_actual', (SELECT codigo FROM cat.clasificacion_tecnica WHERE id = o.clasificacion_actual_id),
                              'organizacion_origen_id', o.organizacion_origen_id, 'registrado_en', o.registrado_en, 'cerrado_en', o.cerrado_en)),
    'trz.dispositivo', (SELECT jsonb_build_object('objeto_id', d.objeto_id, 'categoria', c.codigo, 'marca_id', d.marca_id, 'numero_serie', d.numero_serie,
                          'anio_fabricacion', d.anio_fabricacion, 'peso_kg', d.peso_kg, 'contiene_almacenamiento', d.contiene_almacenamiento,
                          'atributos', d.atributos)
                          FROM trz.dispositivo d JOIN cat.categoria_raee c ON c.id = d.categoria_id WHERE d.objeto_id = o.id),
    'trz.historial_estado', (SELECT coalesce(jsonb_agg(jsonb_build_object('ocurrido_en', h.ocurrido_en,
                               'desde', (SELECT codigo FROM cat.estado_trazabilidad WHERE id = h.estado_origen_id),
                               'hacia', (SELECT codigo FROM cat.estado_trazabilidad WHERE id = h.estado_destino_id),
                               'documento_id', h.documento_id, 'canal', h.canal, 'observacion', h.observacion) ORDER BY h.ocurrido_en, h.id), '[]')
                               FROM trz.historial_estado h WHERE h.objeto_id = o.id),
    'ops.documento_item', (SELECT coalesce(jsonb_agg(jsonb_build_object('documento', d.numero, 'tipo', d.tipo_documento, 'estado', d.estado_documento,
                             'fecha', d.fecha_documento) ORDER BY d.fecha_documento), '[]')
                             FROM ops.documento_item i JOIN ops.documento_operativo d ON d.id = i.documento_id WHERE i.objeto_id = o.id),
    'aud.log_cambio', (SELECT coalesce(jsonb_agg(x ORDER BY x ->> 'ocurrido_en' DESC), '[]') FROM (
                         SELECT jsonb_build_object('ocurrido_en', l.ocurrido_en, 'tabla', l.esquema || '.' || l.tabla, 'operacion', l.operacion,
                                'campos_cambiados', l.campos_cambiados, 'canal', l.canal, 'request_id', l.request_id) AS x
                           FROM aud.log_cambio l
                          WHERE l.esquema = 'trz' AND l.tabla IN ('objeto_trazable','dispositivo')
                            AND (l.pk ->> 'id' = o.id::text OR l.pk ->> 'objeto_id' = o.id::text)
                          ORDER BY l.id DESC LIMIT 20) s));
END $$;

COMMENT ON FUNCTION api.fn_verificar_base() IS 'Verificación de la base: estructura, volumen y comprobaciones de consistencia (0 problemas = correcto).';
COMMENT ON FUNCTION api.fn_verificar_objeto(text) IS 'Prueba de persistencia: filas guardadas de un objeto en cada tabla, más su auditoría.';

REVOKE EXECUTE ON FUNCTION api.fn_verificar_base(), api.fn_verificar_objeto(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION api.fn_verificar_base(), api.fn_verificar_objeto(text) TO ecoraee_app;
