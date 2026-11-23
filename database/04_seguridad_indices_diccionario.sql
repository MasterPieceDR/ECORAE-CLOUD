-- =====================================================================
-- Script 04: roles de base de datos, privilegios, RLS, acceso a
-- evidencias, índices y comentarios (fuente del diccionario de datos)
-- =====================================================================
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 1. Roles de base de datos (grupos NOLOGIN; los logins viven en Secrets Manager)
--    ecoraee_api_svc  IN ROLE ecoraee_app     (FastAPI)
--    ecoraee_mcp_svc  IN ROLE ecoraee_mcp     (servidor MCP)
--    ecoraee_ro_svc   IN ROLE ecoraee_lectura (réplica de lectura / analítica)
-- ---------------------------------------------------------------------
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['ecoraee_lectura','ecoraee_app','ecoraee_mcp','ecoraee_auditor'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN EXECUTE format('CREATE ROLE %I NOLOGIN', r); END IF;
  END LOOP;
END $$;
GRANT ecoraee_lectura TO ecoraee_app, ecoraee_mcp, ecoraee_auditor;

-- Nada es público por defecto (las funciones nacen con EXECUTE para PUBLIC)
DO $$
DECLARE s text;
BEGIN
  FOREACH s IN ARRAY ARRAY['meta','cat','seg','org','trz','ops','inv','evd','red','ind','gob','aud','mcp','integ','api','util'] LOOP
    EXECUTE format('REVOKE ALL ON SCHEMA %I FROM PUBLIC', s);
    EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA %I FROM PUBLIC', s);
    EXECUTE format('REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA %I FROM PUBLIC', s);
  END LOOP;
END $$;

-- Lectura de negocio (filtrada por RLS)
GRANT USAGE ON SCHEMA meta, cat, seg, org, trz, ops, inv, evd, red, ind, gob, api, util TO ecoraee_lectura;
GRANT SELECT ON ALL TABLES IN SCHEMA meta, cat, org, trz, ops, inv, red, ind, gob TO ecoraee_lectura;
GRANT SELECT ON seg.ecosistema, seg.rol, seg.permiso, seg.rol_permiso, seg.usuario_rol, seg.habilitacion_tecnica,
                seg.segregacion_funciones, seg.actor_rol_mapeo TO ecoraee_lectura;
GRANT SELECT (id, uid, ecosistema_id, organizacion_id, alias, estado, mfa_habilitado, creado_en, eliminado_en) ON seg.usuario TO ecoraee_lectura; -- sin correo ni credenciales
GRANT SELECT (id, uid, ecosistema_id, tipo_evidencia_id, sha256, mime, tamano_bytes, nivel_acceso, metadatos_limpios,
              subido_por, subido_en, retener_hasta, estado) ON evd.evidencia TO ecoraee_lectura;               -- sin clave S3
GRANT SELECT ON evd.evidencia_vinculo, evd.politica_acceso TO ecoraee_lectura;
GRANT SELECT ON api.v1_objeto, api.v1_linea_trazabilidad, api.v1_inventario, api.v1_lote_resumen, api.v1_utilizacion_arista,
                api.v1_resultado_flujo, api.v1_corte_minimo, api.v1_indicador, api.v1_alerta_abierta, api.v1_diccionario,
                api.v1_glosario, api.v1_mcp_catalogo TO ecoraee_lectura;
GRANT EXECUTE ON FUNCTION seg.fn_usuario_actual(), seg.fn_ecosistema_actual(), seg.fn_roles_efectivos(bigint, bigint),
                          seg.fn_tiene_permiso(bigint, text, bigint), trz.fn_miembros(bigint),
                          red.fn_capacidad_efectiva(bigint, bigint), red.fn_dataset_flujo(bigint),
                          api.fn_linea_trazabilidad(text), api.fn_mcp_leer_recurso(text), api.fn_iniciar_contexto(uuid, text, text)
      TO ecoraee_lectura;

-- Escritura: solo mediante funciones del esquema api (SECURITY DEFINER)
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO ecoraee_app;
GRANT EXECUTE ON FUNCTION ind.fn_calcular_indicadores(date, date), ind.fn_generar_alertas() TO ecoraee_app;
-- (los permisos de ecoraee_mcp se derivan del registro mcp.herramienta en el script 05)

-- Auditoría
GRANT USAGE ON SCHEMA aud, mcp, integ TO ecoraee_auditor;
GRANT SELECT ON ALL TABLES IN SCHEMA aud TO ecoraee_auditor;
GRANT SELECT ON mcp.invocacion, mcp.herramienta, evd.acceso_evidencia, integ.outbox_evento TO ecoraee_auditor;
GRANT EXECUTE ON FUNCTION aud.fn_estado_en(name, name, jsonb, timestamptz), aud.fn_verificar_sello(bigint) TO ecoraee_auditor;

-- ---------------------------------------------------------------------
-- 2. Funciones de visibilidad usadas por las políticas RLS
-- ---------------------------------------------------------------------
CREATE FUNCTION seg.fn_es_operativo(p_usuario bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT EXISTS (SELECT 1 FROM seg.fn_roles_efectivos(p_usuario) r JOIN seg.rol x ON x.id = r.rol_id
                  WHERE x.codigo NOT IN ('USUARIO_BASE','GENERADOR','BENEFICIARIO'))
$$;

-- Un generador ve solo lo de su organización (y sus sedes); un beneficiario, lo que le fue asignado
CREATE FUNCTION seg.fn_ve_objeto(p_objeto bigint, p_org_origen bigint) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := nullif(current_setting('app.usuario_id', true), '')::bigint;
        v_org bigint := nullif(current_setting('app.organizacion_id', true), '')::bigint;
BEGIN
  IF v_usuario IS NULL THEN RETURN false; END IF;
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

CREATE FUNCTION seg.fn_puede_ver_evidencia(p_tipo smallint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT EXISTS (SELECT 1 FROM evd.politica_acceso p
                   JOIN seg.fn_roles_efectivos(nullif(current_setting('app.usuario_id', true), '')::bigint) r ON r.rol_id = p.rol_id
                  WHERE p.tipo_evidencia_id = p_tipo)
$$;
GRANT EXECUTE ON FUNCTION seg.fn_es_operativo(bigint), seg.fn_ve_objeto(bigint, bigint), seg.fn_puede_ver_evidencia(smallint),
                          seg.fn_tiene_rol(bigint, text) TO ecoraee_lectura;

-- ---------------------------------------------------------------------
-- 3. Row Level Security: aislamiento por ecosistema + visibilidad por rol
-- ---------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['org.organizacion','seg.usuario','red.nodo','red.arista','red.escenario_red','ind.alerta',
                           'ind.medicion_indicador','integ.outbox_evento'] LOOP
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY p_ecosistema ON %s USING (ecosistema_id = seg.fn_ecosistema_actual())', t);
  END LOOP;
END $$;

ALTER TABLE trz.objeto_trazable ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_objeto ON trz.objeto_trazable
  USING (ecosistema_id = seg.fn_ecosistema_actual() AND seg.fn_ve_objeto(id, organizacion_origen_id));

ALTER TABLE trz.historial_estado ENABLE ROW LEVEL SECURITY;          -- hereda la visibilidad del objeto
CREATE POLICY p_historial ON trz.historial_estado
  USING (EXISTS (SELECT 1 FROM trz.objeto_trazable o WHERE o.id = objeto_id));

ALTER TABLE ops.documento_operativo ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_documento ON ops.documento_operativo
  USING (ecosistema_id = seg.fn_ecosistema_actual()
         AND (seg.fn_es_operativo(seg.fn_usuario_actual())
              OR responsable_id = seg.fn_usuario_actual()
              OR organizacion_id = nullif(current_setting('app.organizacion_id', true), '')::bigint));

ALTER TABLE evd.evidencia ENABLE ROW LEVEL SECURITY;                 -- RN-07
CREATE POLICY p_evidencia ON evd.evidencia
  USING (ecosistema_id = seg.fn_ecosistema_actual() AND seg.fn_puede_ver_evidencia(tipo_evidencia_id));

ALTER TABLE inv.saldo_ubicacion ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_saldo ON inv.saldo_ubicacion
  USING (seg.fn_tiene_permiso(seg.fn_usuario_actual(), 'INVENTARIO.CONSULTAR')
         AND EXISTS (SELECT 1 FROM org.ubicacion u JOIN org.centro c ON c.id = u.centro_id
                       JOIN org.organizacion o ON o.id = c.organizacion_id WHERE u.id = ubicacion_id));

-- ---------------------------------------------------------------------
-- 4. Acceso a evidencias con propósito explícito y bitácora (RN-07, RNF-10)
-- ---------------------------------------------------------------------
CREATE FUNCTION api.fn_obtener_evidencia(p_evidencia uuid, p_proposito text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usuario bigint := seg.fn_usuario_actual(); e evd.evidencia; v_prop smallint := cat.fn_id('proposito_uso', p_proposito);
        v_ok boolean;
BEGIN
  SELECT * INTO e FROM evd.evidencia WHERE uid = p_evidencia AND ecosistema_id = seg.fn_ecosistema_actual() AND estado = 'ACTIVA';
  IF NOT FOUND THEN RAISE EXCEPTION 'Evidencia no encontrada' USING ERRCODE = 'EC404'; END IF;
  SELECT EXISTS (SELECT 1 FROM evd.politica_acceso p JOIN seg.fn_roles_efectivos(v_usuario) r ON r.rol_id = p.rol_id
                  WHERE p.tipo_evidencia_id = e.tipo_evidencia_id AND p.proposito_id = v_prop AND p.puede_descargar) INTO v_ok;
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
GRANT EXECUTE ON FUNCTION api.fn_obtener_evidencia(uuid, text) TO ecoraee_app;

-- ---------------------------------------------------------------------
-- 5. Índices (FK, rutas críticas, parciales, GIN, BRIN para bitácoras)
-- ---------------------------------------------------------------------
CREATE INDEX ix_objeto_estado_activo ON trz.objeto_trazable (ecosistema_id, estado_actual_id) WHERE cerrado_en IS NULL;
CREATE INDEX ix_objeto_origen        ON trz.objeto_trazable (organizacion_origen_id);
CREATE INDEX ix_objeto_ubicacion     ON trz.objeto_trazable (ubicacion_actual_id) WHERE ubicacion_actual_id IS NOT NULL;
CREATE INDEX ix_objeto_clasificacion ON trz.objeto_trazable (clasificacion_actual_id);
CREATE INDEX ix_dispositivo_categoria ON trz.dispositivo (categoria_id);
CREATE INDEX ix_dispositivo_componente ON trz.dispositivo (componente_de_id) WHERE componente_de_id IS NOT NULL;
CREATE INDEX ix_dispositivo_atributos ON trz.dispositivo USING gin (atributos jsonb_path_ops);
CREATE INDEX ix_lote_comp_vigente    ON trz.lote_composicion (lote_id) WHERE upper_inf(vigencia);
CREATE INDEX ix_historial_objeto     ON trz.historial_estado (objeto_id, ocurrido_en);
CREATE INDEX ix_historial_brin       ON trz.historial_estado USING brin (ocurrido_en);
CREATE INDEX ix_historial_documento  ON trz.historial_estado (documento_id);
CREATE INDEX ix_doc_tipo_fecha       ON ops.documento_operativo (ecosistema_id, tipo_documento, fecha_documento DESC);
CREATE INDEX ix_doc_centro_fecha     ON ops.documento_operativo (centro_id, fecha_documento DESC);
CREATE INDEX ix_doc_referencia       ON ops.documento_operativo (documento_referencia_id) WHERE documento_referencia_id IS NOT NULL;
CREATE INDEX ix_doc_item_objeto      ON ops.documento_item (objeto_id);
CREATE INDEX ix_eval_tecnico         ON ops.evaluacion_tecnica (tecnico_id, evaluado_en DESC);
CREATE INDEX ix_transf_arista        ON ops.transferencia (arista_id) INCLUDE (unidades, peso_kg, estado_transferencia);
CREATE INDEX ix_recol_arista         ON ops.recoleccion (arista_id) INCLUDE (unidades, peso_kg);
CREATE INDEX ix_asig_objeto          ON ops.asignacion_beneficiario (objeto_id);
CREATE INDEX ix_asig_beneficiario    ON ops.asignacion_beneficiario (beneficiario_id);
CREATE INDEX ix_trat_objeto          ON ops.tratamiento (objeto_id, finalizado_en DESC);
CREATE INDEX ix_mov_objeto           ON inv.movimiento_inventario (objeto_id, ocurrido_en);
CREATE INDEX ix_mov_documento        ON inv.movimiento_inventario (documento_id);
CREATE INDEX ix_mov_brin             ON inv.movimiento_inventario USING brin (ocurrido_en);
CREATE INDEX ix_vinculo_documento    ON evd.evidencia_vinculo (documento_id) WHERE documento_id IS NOT NULL;
CREATE INDEX ix_vinculo_objeto       ON evd.evidencia_vinculo (objeto_id) WHERE objeto_id IS NOT NULL;
CREATE INDEX ix_acceso_evidencia     ON evd.acceso_evidencia (evidencia_id, ocurrido_en DESC);
CREATE INDEX ix_arista_destino       ON red.arista (nodo_destino_id);
CREATE INDEX ix_resultado_arista     ON red.resultado_flujo_arista (arista_id);
CREATE INDEX ix_ejecucion_escenario  ON red.ejecucion_flujo (escenario_id, finalizado_en DESC);
CREATE INDEX ix_usuario_rol_usuario  ON seg.usuario_rol (usuario_id);
CREATE INDEX ix_log_tabla_pk         ON aud.log_cambio (esquema, tabla, pk);
CREATE INDEX ix_log_brin             ON aud.log_cambio USING brin (ocurrido_en);
CREATE INDEX ix_log_usuario          ON aud.log_cambio (usuario_id, ocurrido_en DESC);
CREATE INDEX ix_mcp_limite           ON mcp.invocacion (usuario_id, herramienta_id, ocurrido_en DESC);
CREATE INDEX ix_outbox_pendiente     ON integ.outbox_evento (id) WHERE publicado_en IS NULL;
CREATE INDEX ix_alerta_abierta       ON ind.alerta (ecosistema_id, regla_id) WHERE estado <> 'RESUELTA';
CREATE INDEX ix_organizacion_padre   ON org.organizacion (organizacion_padre_id) WHERE organizacion_padre_id IS NOT NULL;
CREATE INDEX ix_ubicacion_ruta       ON org.ubicacion USING gist (ruta);
CREATE INDEX ix_categoria_ruta       ON cat.categoria_raee USING gist (ruta);

-- ---------------------------------------------------------------------
-- 6. Comentarios de tablas (diccionario de datos)
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('meta.dominio','Dominio de datos (un esquema): propietario de negocio y custodio técnico.'),
    ('meta.entidad','Entidad del diccionario: tipo de entidad, clasificación de la información, retención y exposición MCP.'),
    ('meta.atributo','Atributo del diccionario, sincronizado desde el catálogo de PostgreSQL más metadatos de negocio (PII, derivado).'),
    ('meta.termino_glosario','Glosario maestro común a las cinco asignaturas: término canónico y su equivalente en cada materia.'),
    ('meta.version_esquema','Migraciones aplicadas al esquema (control de versiones de la base).'),
    ('cat.unidad_medida','Unidades de medida de capacidades y flujos (unidades, kilogramos).'),
    ('cat.tipo_actor','Tipos de actor organizacional del ecosistema (generador, acopio, gestor, beneficiario…).'),
    ('cat.actor_negocio','Actores del modelo de Arquitectura Empresarial; se mapean a roles del sistema.'),
    ('cat.estado_trazabilidad','Conjunto S de estados del ciclo de vida de un objeto trazable.'),
    ('cat.transicion_estado','Relación T ⊆ S×S: transiciones permitidas con su permiso, documento y requisitos.'),
    ('cat.clasificacion_tecnica','Clasificación técnica K = {Reutilizable, Reparable, Reciclable, No recuperable} + Pendiente (solo inventario).'),
    ('cat.tipo_destino','Destinos circulares: reutilización, reacondicionamiento, reciclaje, disposición controlada.'),
    ('cat.clasificacion_destino_permitido','Matriz clasificación × destino; implementa RN-04 y la compatibilidad de rutas.'),
    ('cat.categoria_raee','Árbol recursivo de categorías de RAEE (ruta ltree); define atributos esperados por categoría.'),
    ('cat.marca','Marcas de equipos.'),
    ('cat.modelo_equipo','Modelos de equipo por marca y categoría.'),
    ('cat.tipo_centro','Funciones que puede cumplir un centro (acopio, evaluación, reacondicionamiento, reciclaje, disposición).'),
    ('cat.tipo_nodo','Tipos de nodo del grafo con su prefijo (G, C, E, R, K, D, B) y rol de fuente/sumidero.'),
    ('cat.arista_tipo_permitida','Arcos válidos entre tipos de nodo; los marcados exigen excepción aprobada por el Comité.'),
    ('cat.tipo_evidencia','Tipos de evidencia con nivel de acceso, formatos y retención.'),
    ('cat.proposito_uso','Finalidades explícitas para acceder a evidencias (minimización de datos).'),
    ('cat.tipo_tratamiento','Tratamientos aplicables y el destino circular al que conducen.'),
    ('cat.material','Fracciones de material recuperable (metales, plásticos, vidrio…).'),
    ('cat.criterio_evaluacion','Lista de verificación de la evaluación técnica, general o por categoría.'),
    ('cat.motivo','Motivos de anulación, rechazo, ajuste, reevaluación o excepción.'),
    ('cat.parametro_sistema','Parámetros configurables con historial de vigencia (sin solapamiento).'),
    ('seg.ecosistema','Ecosistema o tenant: red circular de una universidad, municipio, consorcio o comunidad.'),
    ('seg.rol','Rol del sistema; jerárquico (hereda permisos de su rol padre).'),
    ('seg.permiso','Permiso atómico recurso.acción.'),
    ('seg.rol_permiso','Asignación de permisos a roles.'),
    ('seg.segregacion_funciones','Pares de roles incompatibles en un mismo usuario (separación de funciones).'),
    ('seg.actor_rol_mapeo','Correspondencia actor de AE → rol del sistema.'),
    ('seg.usuario','Usuario de la plataforma (identidad federada en Cognito; datos mínimos y sintéticos).'),
    ('seg.usuario_rol','Asignación de rol con alcance (organización/centro) y vigencia; conserva el historial.'),
    ('seg.habilitacion_tecnica','Habilitación de un técnico para evaluar una categoría y sus subcategorías (RN-02).'),
    ('org.organizacion','Organización del ecosistema; recursiva (matriz → sedes).'),
    ('org.organizacion_actor','Roles de actor que cumple una organización a lo largo del tiempo.'),
    ('org.centro','Centro físico operado por una organización.'),
    ('org.centro_funcion','Funciones que cumple cada centro (un centro puede tener varias).'),
    ('org.capacidad_centro','Capacidad de almacenamiento y proceso por función, con vigencia.'),
    ('org.ubicacion','Ubicación física recursiva dentro de un centro (bodega → zona → estante).'),
    ('trz.objeto_trazable','Supertipo de todo lo que se traza (dispositivo o lote); identificador único y caché de estado, clasificación y ubicación.'),
    ('trz.dispositivo','Subtipo: equipo individual; recursivo para componentes extraídos.'),
    ('trz.lote','Subtipo: agrupación de objetos para operar en conjunto.'),
    ('trz.lote_composicion','Pertenencia temporal de un objeto a un lote (a lo sumo un lote a la vez); admite lotes anidados.'),
    ('trz.lote_genealogia','Genealogía de lotes: división, fusión y reempaque (grafo acíclico).'),
    ('trz.historial_estado','Historial inmutable de estados (RN-01), particionado por mes.'),
    ('ops.documento_operativo','Supertipo de documentos del ciclo de vida; numeración correlativa y cadena documental recursiva.'),
    ('ops.secuencia_documento','Contador correlativo sin huecos por ecosistema, tipo de documento y año.'),
    ('ops.documento_item','Objetos involucrados en un documento.'),
    ('ops.solicitud_recoleccion','Subtipo: solicitud de recolección o aviso de entrega directa.'),
    ('ops.recoleccion','Subtipo: recolección programada; consume capacidad del arco generador → acopio.'),
    ('ops.recepcion','Subtipo: recepción en centro con conformidad y peso verificado.'),
    ('ops.evaluacion_tecnica','Subtipo: evaluación inmutable por dispositivo; reevaluaciones encadenadas (RN-02).'),
    ('ops.evaluacion_criterio','Resultado de cada criterio de la lista de verificación.'),
    ('ops.transferencia','Subtipo: traslado por una arista de la red (RN-03, RN-05).'),
    ('ops.tratamiento','Subtipo: reacondicionamiento, reciclaje o disposición y su resultado.'),
    ('ops.tratamiento_fraccion','Material recuperado por tratamiento (indicador ambiental).'),
    ('ops.asignacion_beneficiario','Subtipo: asignación de un equipo a una entidad beneficiaria (RN-04, RN-09).'),
    ('ops.cierre_trazabilidad','Subtipo: cierre con destino final y fecha de confirmación (RN-08).'),
    ('inv.movimiento_inventario','Kardex de doble entrada, inmutable y particionado por mes.'),
    ('inv.saldo_ubicacion','Saldo actual por ubicación, categoría y clasificación; nunca negativo (RN-06).'),
    ('evd.evidencia','Metadatos y huella SHA-256 de una evidencia almacenada en S3.'),
    ('evd.evidencia_vinculo','Vínculo de una evidencia con documentos u objetos.'),
    ('evd.politica_acceso','Política de acceso rol × tipo de evidencia × propósito (RN-07).'),
    ('evd.acceso_evidencia','Bitácora de accesos permitidos y denegados a evidencias.'),
    ('red.nodo','Vértice del grafo G: un centro (por función) o una organización generadora/beneficiaria.'),
    ('red.arista','Arco dirigido E entre nodos (relación recursiva nodo × nodo).'),
    ('red.capacidad_arista','Capacidad c(u,v) por unidad y periodo, con historial de vigencia.'),
    ('red.escenario_red','Escenario de análisis; recursivo (hereda capacidades del escenario base).'),
    ('red.escenario_arista','Ajustes de capacidad o actividad de una arista en un escenario.'),
    ('red.escenario_nodo','Oferta y demanda por nodo en un escenario.'),
    ('red.ejecucion_flujo','Ejecución del algoritmo de flujo máximo con huella del dataset (reproducibilidad).'),
    ('red.resultado_flujo_arista','Flujo por arista de una ejecución; saturación y utilización derivadas.'),
    ('red.corte_minimo','Corte mínimo encontrado (puede haber varios por ejecución).'),
    ('red.corte_minimo_arista','Aristas que forman cada corte mínimo.'),
    ('ind.indicador','Definición de indicador (operativo, ambiental, social, económico, técnico) y su materia de origen.'),
    ('ind.medicion_indicador','Serie histórica de mediciones de indicadores.'),
    ('ind.regla_alerta','Reglas de alerta con severidad y umbral.'),
    ('ind.alerta','Alertas generadas y su ciclo de atención.'),
    ('gob.decision_arquitectura','Registro de decisiones de arquitectura (ADR); recursivo por sustitución.'),
    ('gob.excepcion_regla','Excepción a una regla aprobada por el Comité de Arquitectura, con vigencia.'),
    ('gob.riesgo','Matriz de riesgos sociales, éticos y técnicos con el control que los mitiga.'),
    ('aud.log_cambio','Auditoría técnica: imagen antes/después de cada cambio, con usuario, canal y huella; particionada.'),
    ('aud.sello_integridad','Sello encadenado por periodo sobre la auditoría (evidencia de no manipulación).'),
    ('aud.evento_seguridad','Eventos de seguridad: accesos denegados, rechazos MCP, cambios de rol.'),
    ('mcp.herramienta','Herramientas expuestas por el servidor MCP: esquema JSON, objeto SQL, confirmación y límite.'),
    ('mcp.herramienta_rol','Roles autorizados para cada herramienta MCP.'),
    ('mcp.recurso','Recursos MCP de solo lectura (URI → función del esquema api).'),
    ('mcp.invocacion','Bitácora de invocaciones MCP, particionada por mes.'),
    ('integ.idempotencia','Claves de idempotencia para reintentos seguros de comandos.'),
    ('integ.outbox_evento','Outbox transaccional de eventos de dominio para integración asíncrona.')
  ) AS v(tabla, comentario) LOOP
    EXECUTE format('COMMENT ON TABLE %s IS %L', r.tabla, r.comentario);
  END LOOP;
END $$;

-- Comentarios de columnas estándar (se aplican a todas las tablas que las tengan)
DO $$
DECLARE r record; d text;
BEGIN
  FOR r IN SELECT n.nspname, c.relname, a.attname
             FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relkind IN ('r','p') AND NOT c.relispartition AND a.attnum > 0 AND NOT a.attisdropped
              AND n.nspname IN ('meta','cat','seg','org','trz','ops','inv','evd','red','ind','gob','aud','mcp','integ')
              AND col_description(c.oid, a.attnum) IS NULL LOOP
    d := CASE r.attname
      WHEN 'id' THEN 'Identificador interno (clave subrogada).'
      WHEN 'uid' THEN 'Identificador público UUID expuesto por la API (evita enumeración).'
      WHEN 'codigo' THEN 'Código de negocio único y legible.'
      WHEN 'nombre' THEN 'Nombre descriptivo.'
      WHEN 'descripcion' THEN 'Descripción.'
      WHEN 'activo' THEN 'Indica si el registro está vigente para nuevas operaciones (baja lógica).'
      WHEN 'activa' THEN 'Indica si el registro está vigente para nuevas operaciones.'
      WHEN 'ecosistema_id' THEN 'Ecosistema (tenant) al que pertenece; base del aislamiento RLS.'
      WHEN 'creado_en' THEN 'Fecha y hora de creación.'
      WHEN 'creado_por' THEN 'Usuario que creó el registro (contexto de la API).'
      WHEN 'actualizado_en' THEN 'Fecha y hora de la última modificación.'
      WHEN 'actualizado_por' THEN 'Usuario de la última modificación.'
      WHEN 'version' THEN 'Versión para control de concurrencia optimista.'
      WHEN 'eliminado_en' THEN 'Baja lógica: fecha de eliminación (NULL = vigente).'
      WHEN 'vigencia' THEN 'Periodo de validez [desde, hasta); sin solapamientos por restricción de exclusión.'
      WHEN 'documento_id' THEN 'Documento operativo asociado.'
      WHEN 'tipo_documento' THEN 'Discriminador del subtipo de documento (especialización disjunta).'
      WHEN 'tipo_objeto' THEN 'Discriminador del subtipo de objeto trazable (DISPOSITIVO | LOTE).'
      WHEN 'objeto_id' THEN 'Objeto trazable referido.'
      WHEN 'usuario_id' THEN 'Usuario que ejecutó la acción.'
      WHEN 'ocurrido_en' THEN 'Instante del hecho; clave de partición en tablas históricas.'
      WHEN 'observacion' THEN 'Observación libre.'
      WHEN 'estado' THEN 'Estado del registro.'
      WHEN 'orden' THEN 'Orden de presentación.'
      WHEN 'peso_kg' THEN 'Peso en kilogramos.'
      WHEN 'unidades' THEN 'Cantidad en unidades.'
      WHEN 'centro_id' THEN 'Centro asociado.'
      WHEN 'organizacion_id' THEN 'Organización asociada.'
      WHEN 'arista_id' THEN 'Arista de la red asociada.'
      WHEN 'escenario_id' THEN 'Escenario de red asociado.'
      WHEN 'rol_id' THEN 'Rol asociado.'
      WHEN 'unidad_id' THEN 'Unidad de medida.'
      WHEN 'periodo' THEN 'Periodo de referencia de la capacidad o medición.'
      WHEN 'request_id' THEN 'Identificador de la petición HTTP/MCP para correlación con CloudWatch.'
      WHEN 'canal' THEN 'Canal de origen: WEB, API, MCP o BATCH.'
      WHEN 'ruta' THEN 'Ruta materializada (ltree) desde la raíz; derivada por trigger.'
      WHEN 'nivel' THEN 'Profundidad en la jerarquía; derivada de la ruta.'
      ELSE NULL END;
    IF d IS NOT NULL THEN EXECUTE format('COMMENT ON COLUMN %I.%I.%I IS %L', r.nspname, r.relname, r.attname, d); END IF;
  END LOOP;
END $$;

-- Comentarios de columnas específicas
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('trz.objeto_trazable.estado_actual_id','Caché del último estado del historial (desnormalización controlada por trigger).'),
    ('trz.objeto_trazable.clasificacion_actual_id','Caché de la clasificación de la evaluación vigente; solo la cambia un técnico (RN-02).'),
    ('trz.objeto_trazable.ubicacion_actual_id','Caché de la ubicación según el kardex; NULL en tránsito o fuera de un centro.'),
    ('trz.objeto_trazable.organizacion_origen_id','Generador que entregó el objeto.'),
    ('trz.objeto_trazable.cerrado_en','Fecha de cierre de la trazabilidad (RN-08).'),
    ('trz.dispositivo.contiene_almacenamiento','El equipo almacena datos: exige certificado de borrado antes de asignarse (RN-09).'),
    ('trz.dispositivo.atributos','Atributos propios de la categoría (JSONB validado contra cat.categoria_raee.esquema_atributos).'),
    ('trz.dispositivo.componente_de_id','Equipo del que se extrajo esta pieza (relación recursiva de desensamble).'),
    ('trz.lote.peso_declarado_kg','Peso declarado por quien arma el lote; el peso real es derivado (api.v1_lote_resumen).'),
    ('ops.documento_operativo.documento_referencia_id','Documento que origina a este (cadena documental recursiva).'),
    ('ops.documento_operativo.numero','Número correlativo legible: prefijo-año-secuencia.'),
    ('ops.evaluacion_tecnica.vigente','Solo una evaluación vigente por dispositivo (índice único parcial).'),
    ('ops.evaluacion_tecnica.modalidad','COMPLETA, PRECLASIFICACION en acopio por técnico, o REEVALUACION.'),
    ('ops.evaluacion_tecnica.evaluacion_anterior_id','Evaluación a la que reemplaza (cadena recursiva de reevaluaciones).'),
    ('ops.transferencia.estado_transferencia','PROGRAMADA → DESPACHADA → RECIBIDA → CERRADA (o ANULADA).'),
    ('ops.cierre_trazabilidad.fecha_confirmacion','Fecha en que el destino final confirmó la recepción (RN-08).'),
    ('inv.movimiento_inventario.sentido','+1 entrada, -1 salida.'),
    ('inv.movimiento_inventario.par_movimiento_id','Movimiento complementario de un traslado (salida ↔ entrada).'),
    ('evd.evidencia.sha256','Huella del archivo; garantiza integridad y evita duplicados.'),
    ('evd.evidencia.s3_clave','Clave del objeto en S3; solo se entrega mediante api.fn_obtener_evidencia.'),
    ('evd.evidencia.metadatos_limpios','Las fotografías se suben sin EXIF/GPS (RNF-10).'),
    ('red.nodo.centro_id','Centro representado (exclusivo con organizacion_id).'),
    ('red.nodo.organizacion_id','Organización generadora o beneficiaria representada (exclusivo con centro_id).'),
    ('red.arista.excepcion_id','Excepción del Comité que habilita un arco no estándar (p. ej. C2→K1).'),
    ('red.escenario_red.escenario_base_id','Escenario del que hereda capacidades (relación recursiva).'),
    ('red.escenario_red.fecha_referencia','Instante en que se leen las capacidades vigentes.'),
    ('red.ejecucion_flujo.hash_entrada','SHA-256 del dataset leído; el resultado se rechaza si el dataset cambió.'),
    ('red.resultado_flujo_arista.saturada','Derivado: flujo = capacidad.'),
    ('red.corte_minimo.lado_fuente','Nodos del lado S del corte (s y t son virtuales y no se almacenan).'),
    ('aud.log_cambio.hash_registro','SHA-256 de la fila de auditoría; base del sellado por periodo.'),
    ('aud.log_cambio.pk','Clave primaria de la fila auditada en JSON.'),
    ('mcp.herramienta.objeto_sql','Función o vista del esquema api que ejecuta la herramienta (nunca SQL libre).'),
    ('mcp.herramienta.esquema_entrada','JSON Schema de los argumentos que publica el servidor MCP.'),
    ('mcp.invocacion.argumentos','Argumentos saneados (sin correos, tokens ni claves).'),
    ('seg.usuario.correo','Correo sintético; dato personal clasificado, no expuesto a roles de lectura.'),
    ('seg.usuario.alias','Nombre visible que no identifica a la persona.'),
    ('seg.usuario_rol.centro_id','Alcance: si se indica, el rol solo aplica en ese centro.'),
    ('org.organizacion.tipo_persona','Las personas naturales se registran seudonimizadas.')
  ) AS v(col, comentario) LOOP
    EXECUTE format('COMMENT ON COLUMN %s IS %L', r.col, r.comentario);
  END LOOP;
END $$;

-- Comentarios del resto de columnas (cobertura completa del diccionario)
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('aud.evento_seguridad.detalle','Detalle del evento en JSON (sin datos personales).'),
    ('aud.evento_seguridad.ip_hash','Hash de la IP de origen (no se guarda la IP en claro).'),
    ('aud.evento_seguridad.tipo','Tipo de evento de seguridad.'),
    ('aud.log_cambio.campos_cambiados','Columnas que cambiaron en un UPDATE.'),
    ('aud.log_cambio.datos_antes','Imagen de la fila antes del cambio.'),
    ('aud.log_cambio.datos_despues','Imagen de la fila después del cambio.'),
    ('aud.log_cambio.esquema','Esquema de la tabla auditada.'),
    ('aud.log_cambio.operacion','I inserción, U actualización, D eliminación.'),
    ('aud.log_cambio.tabla','Tabla auditada.'),
    ('aud.log_cambio.txid','Identificador de la transacción de base de datos.'),
    ('aud.log_cambio.usuario_bd','Rol de base de datos que ejecutó el cambio.'),
    ('aud.sello_integridad.hash_periodo','SHA-256 de todos los hash del periodo encadenado con el sello anterior.'),
    ('aud.sello_integridad.hash_sello_anterior','Hash del sello previo (cadena de sellos).'),
    ('aud.sello_integridad.registros','Filas de auditoría cubiertas por el sello.'),
    ('aud.sello_integridad.sellado_en','Momento del sellado.'),
    ('cat.actor_negocio.responsabilidad','Responsabilidad principal según el enunciado y AE.'),
    ('cat.arista_tipo_permitida.justificacion','Justificación de negocio del arco.'),
    ('cat.arista_tipo_permitida.requiere_excepcion','Si el arco solo puede crearse con excepción del Comité.'),
    ('cat.categoria_raee.contiene_almacenamiento','Si los equipos de la categoría suelen almacenar datos.'),
    ('cat.categoria_raee.esquema_atributos','Atributos obligatorios y tipos esperados (JSON Schema simplificado).'),
    ('cat.categoria_raee.peso_referencial_kg','Peso típico para estimaciones.'),
    ('cat.categoria_raee.vida_util_anios','Vida útil de referencia.'),
    ('cat.clasificacion_destino_permitido.prioridad','Orden de preferencia del destino (1 = preferido).'),
    ('cat.clasificacion_tecnica.es_resultado_evaluacion','Si puede ser resultado de una evaluación (PENDIENTE no).'),
    ('cat.criterio_evaluacion.obligatorio','Si debe registrarse en toda evaluación completa.'),
    ('cat.criterio_evaluacion.tipo_valor','Tipo del valor medido: BOOLEANO, NUMERO o TEXTO.'),
    ('cat.estado_trazabilidad.es_final','Estado terminal (sin transiciones de salida).'),
    ('cat.estado_trazabilidad.es_inicial','Estado de registro.'),
    ('cat.material.es_peligroso','Material peligroso que exige gestor autorizado.'),
    ('cat.modelo_equipo.anio_lanzamiento','Año de lanzamiento del modelo.'),
    ('cat.motivo.ambito','Ámbito en que se usa el motivo.'),
    ('cat.parametro_sistema.valor','Valor del parámetro en JSON.'),
    ('cat.tipo_destino.es_final','Si el destino cierra la trazabilidad.'),
    ('cat.tipo_evidencia.mime_permitidos','Formatos de archivo admitidos.'),
    ('cat.tipo_evidencia.nivel_acceso','Clasificación de la información por defecto.'),
    ('cat.tipo_evidencia.retencion_meses','Meses de conservación antes de eliminar o archivar.'),
    ('cat.tipo_nodo.es_fuente','Se conecta a la superfuente virtual s.'),
    ('cat.tipo_nodo.es_sumidero','Se conecta al supersumidero virtual t.'),
    ('cat.tipo_nodo.prefijo','Prefijo del código de nodo en el grafo.'),
    ('cat.transicion_estado.permiso_requerido','Permiso que debe tener el usuario.'),
    ('cat.transicion_estado.requiere_clasificacion','Exige clasificación técnica vigente.'),
    ('cat.transicion_estado.requiere_evidencia','Exige evidencia vinculada al documento.'),
    ('evd.acceso_evidencia.resultado','PERMITIDO o DENEGADO.'),
    ('evd.evidencia.mime','Tipo MIME del archivo.'),
    ('evd.evidencia.nivel_acceso','Clasificación de la información.'),
    ('evd.evidencia.retener_hasta','Fecha hasta la que debe conservarse.'),
    ('evd.evidencia.s3_bucket','Bucket privado de S3.'),
    ('evd.evidencia.s3_version_id','Versión del objeto en S3 (bucket con versionado).'),
    ('evd.evidencia.subido_en','Fecha de carga.'),
    ('evd.evidencia.tamano_bytes','Tamaño en bytes (máximo 25 MB).'),
    ('evd.evidencia_vinculo.vinculado_en','Fecha del vínculo.'),
    ('evd.politica_acceso.puede_descargar','Si el rol puede obtener la URL de descarga.'),
    ('gob.decision_arquitectura.consecuencias','Consecuencias de la decisión.'),
    ('gob.decision_arquitectura.contexto','Problema o fuerza que motiva la decisión.'),
    ('gob.decision_arquitectura.decision','Decisión adoptada.'),
    ('gob.decision_arquitectura.fecha','Fecha de la decisión.'),
    ('gob.decision_arquitectura.materias','Asignaturas involucradas.'),
    ('gob.decision_arquitectura.titulo','Título del ADR.'),
    ('gob.excepcion_regla.regla','Regla exceptuada (RN-xx).'),
    ('gob.riesgo.categoria','Dimensión del riesgo.'),
    ('gob.riesgo.control','Control que lo mitiga.'),
    ('gob.riesgo.impacto','Impacto de 1 a 5.'),
    ('gob.riesgo.materia_origen','Asignatura que identificó el riesgo.'),
    ('gob.riesgo.objeto_bd','Objeto de la base que implementa el control.'),
    ('gob.riesgo.probabilidad','Probabilidad de 1 a 5.'),
    ('ind.alerta.generada_en','Momento de generación.'),
    ('ind.alerta.mensaje','Mensaje legible.'),
    ('ind.alerta.resuelta_en','Momento de resolución.'),
    ('ind.indicador.dimension','Dimensión del indicador.'),
    ('ind.indicador.formula','Fórmula de cálculo.'),
    ('ind.indicador.fuente','Vista, tabla o función que lo calcula.'),
    ('ind.indicador.materia_origen','Asignatura que lo propone.'),
    ('ind.indicador.meta','Valor objetivo.'),
    ('ind.indicador.sentido','Interpretación de la meta.'),
    ('ind.indicador.unidad','Unidad del indicador.'),
    ('ind.medicion_indicador.calculado_en','Momento del cálculo.'),
    ('ind.medicion_indicador.valor','Valor medido.'),
    ('ind.regla_alerta.condicion','Condición que dispara la alerta.'),
    ('ind.regla_alerta.severidad','Severidad.'),
    ('ind.regla_alerta.umbral','Umbral numérico.'),
    ('integ.idempotencia.clave','Clave Idempotency-Key enviada por el cliente.'),
    ('integ.idempotencia.expira_en','Fin de validez de la clave.'),
    ('integ.idempotencia.hash_solicitud','Huella del cuerpo de la petición.'),
    ('integ.idempotencia.operacion','Operación invocada.'),
    ('integ.idempotencia.respuesta','Respuesta original a devolver en reintentos.'),
    ('integ.outbox_evento.agregado','Tipo de agregado que origina el evento.'),
    ('integ.outbox_evento.agregado_id','Identificador del agregado.'),
    ('integ.outbox_evento.intentos','Intentos de publicación.'),
    ('integ.outbox_evento.payload','Contenido del evento en JSON.'),
    ('integ.outbox_evento.publicado_en','Momento de publicación (NULL = pendiente).'),
    ('integ.outbox_evento.tipo_evento','Nombre del evento de dominio.'),
    ('inv.movimiento_inventario.tipo_movimiento','INGRESO, EGRESO, TRASLADO_SALIDA, TRASLADO_ENTRADA o AJUSTE.'),
    ('mcp.herramienta.esquema_salida','JSON Schema de la respuesta.'),
    ('mcp.herramienta.limite_por_minuto','Invocaciones máximas por usuario y minuto.'),
    ('mcp.herramienta.requiere_confirmacion','Exige confirmación humana antes de ejecutar.'),
    ('mcp.herramienta.tipo','LECTURA, ESCRITURA o ANALISIS.'),
    ('mcp.herramienta.titulo','Título visible.'),
    ('mcp.invocacion.argumentos_hash','Huella de los argumentos originales.'),
    ('mcp.invocacion.duracion_ms','Duración de la ejecución.'),
    ('mcp.invocacion.error','Mensaje de error, si lo hubo.'),
    ('mcp.invocacion.filas','Filas devueltas o afectadas.'),
    ('mcp.invocacion.nombre_solicitado','Nombre pedido por el cliente aunque no exista.'),
    ('mcp.invocacion.sesion_mcp','Identificador de la sesión MCP.'),
    ('mcp.recurso.mime','Tipo de contenido devuelto.'),
    ('mcp.recurso.objeto_sql','Función del esquema api que resuelve el recurso.'),
    ('mcp.recurso.uri_plantilla','Plantilla de URI del recurso.'),
    ('meta.atributo.es_derivado','Columna calculada (GENERATED).'),
    ('meta.atributo.es_fk','Es clave foránea.'),
    ('meta.atributo.es_pii','Contiene un dato personal.'),
    ('meta.atributo.es_pk','Forma parte de la clave primaria.'),
    ('meta.atributo.nombre_columna','Nombre físico de la columna.'),
    ('meta.atributo.nulo','Admite NULL.'),
    ('meta.atributo.posicion','Posición de la columna.'),
    ('meta.atributo.referencia','Tabla y columna referidas.'),
    ('meta.atributo.tipo_dato','Tipo de dato físico.'),
    ('meta.atributo.valor_defecto','Valor por defecto.'),
    ('meta.dominio.custodio_tecnico','Responsable técnico del dominio.'),
    ('meta.dominio.esquema','Esquema de PostgreSQL.'),
    ('meta.dominio.propietario_negocio','Dueño de negocio del dominio.'),
    ('meta.entidad.clasificacion_datos','Clasificación de la información.'),
    ('meta.entidad.expuesta_mcp','Si se consulta desde herramientas MCP.'),
    ('meta.entidad.nombre_negocio','Nombre en lenguaje de negocio.'),
    ('meta.entidad.nombre_tabla','Nombre físico de la tabla.'),
    ('meta.entidad.retencion','Política de retención.'),
    ('meta.entidad.sincronizada_en','Última sincronización con el catálogo.'),
    ('meta.entidad.tipo_entidad','Tipo de entidad en el modelo EER.'),
    ('meta.termino_glosario.definicion','Definición canónica.'),
    ('meta.termino_glosario.entidad_ref','Tabla que materializa el término.'),
    ('meta.termino_glosario.sinonimos','Nombres alternativos usados antes.'),
    ('meta.termino_glosario.termino','Término canónico.'),
    ('meta.termino_glosario.termino_ae','Equivalente en Arquitectura Empresarial.'),
    ('meta.termino_glosario.termino_bd','Equivalente en Bases de Datos.'),
    ('meta.termino_glosario.termino_inn','Equivalente en Innovación en la Sociedad.'),
    ('meta.termino_glosario.termino_md','Equivalente en Matemáticas Discretas.'),
    ('meta.termino_glosario.termino_nube','Equivalente en Arquitectura en la Nube.'),
    ('meta.version_esquema.aplicada_en','Fecha de aplicación.'),
    ('meta.version_esquema.aplicada_por','Rol que la aplicó.'),
    ('meta.version_esquema.checksum','Huella del script.'),
    ('meta.version_esquema.script','Archivo de la migración.'),
    ('ops.asignacion_beneficiario.criterio_asignacion','Criterio explícito de asignación (control del riesgo R-03).'),
    ('ops.asignacion_beneficiario.entregado_en','Fecha de entrega confirmada.'),
    ('ops.documento_item.cantidad','Unidades del ítem.'),
    ('ops.documento_item.resultado','Resultado por ítem.'),
    ('ops.documento_operativo.estado_documento','Estado del documento.'),
    ('ops.documento_operativo.fecha_cierre','Fecha de cierre del documento.'),
    ('ops.documento_operativo.fecha_documento','Fecha de emisión.'),
    ('ops.evaluacion_criterio.cumple','Si el criterio se cumple.'),
    ('ops.evaluacion_criterio.valor_booleano','Valor si el criterio es booleano.'),
    ('ops.evaluacion_criterio.valor_numero','Valor si el criterio es numérico.'),
    ('ops.evaluacion_criterio.valor_texto','Valor si el criterio es textual.'),
    ('ops.evaluacion_tecnica.evaluado_en','Fecha de la evaluación.'),
    ('ops.evaluacion_tecnica.funcional','Si el equipo funciona.'),
    ('ops.evaluacion_tecnica.puntaje','Puntaje de 0 a 100.'),
    ('ops.evaluacion_tecnica.requiere_borrado_datos','Si debe certificarse borrado antes de reutilizar.'),
    ('ops.recepcion.conformidad','Resultado de la verificación en la recepción.'),
    ('ops.recepcion.peso_verificado_kg','Peso pesado en el centro.'),
    ('ops.recepcion.recibido_en','Fecha de recepción.'),
    ('ops.recoleccion.fecha_ejecucion','Fecha real de la recolección.'),
    ('ops.recoleccion.fecha_programada','Fecha programada.'),
    ('ops.recoleccion.transportista_ref','Referencia del transporte (sin datos personales).'),
    ('ops.secuencia_documento.anio','Año de la numeración.'),
    ('ops.secuencia_documento.ultimo','Último número emitido.'),
    ('ops.solicitud_recoleccion.cantidad_estimada','Unidades estimadas.'),
    ('ops.solicitud_recoleccion.fecha_preferida','Fecha preferida por el generador.'),
    ('ops.solicitud_recoleccion.modalidad','RECOLECCION o ENTREGA_DIRECTA.'),
    ('ops.solicitud_recoleccion.peso_estimado_kg','Peso estimado.'),
    ('ops.solicitud_recoleccion.sector_referencial','Sector aproximado; nunca la dirección exacta.'),
    ('ops.transferencia.despachado_en','Fecha de despacho.'),
    ('ops.transferencia.recibido_en','Fecha de recepción en destino.'),
    ('ops.transferencia.transportista_ref','Referencia del transporte.'),
    ('ops.tratamiento.finalizado_en','Fin del tratamiento.'),
    ('ops.tratamiento.iniciado_en','Inicio del tratamiento.'),
    ('ops.tratamiento.resultado','EXITOSO, PARCIAL o FALLIDO.'),
    ('org.capacidad_centro.capacidad_almacen','Capacidad de almacenamiento.'),
    ('org.capacidad_centro.capacidad_proceso','Capacidad de proceso por periodo.'),
    ('org.centro.canton','Cantón.'),
    ('org.centro.horario','Horario de atención en JSON.'),
    ('org.centro.parroquia','Parroquia.'),
    ('org.organizacion.canton','Cantón (ubicación gruesa).'),
    ('org.organizacion.parroquia','Parroquia (ubicación gruesa).'),
    ('org.organizacion.sector','Sector: público, privado, académico o comunitario.'),
    ('org.ubicacion.capacidad_kg','Capacidad física en kg.'),
    ('org.ubicacion.tipo','Tipo de ubicación.'),
    ('red.capacidad_arista.capacidad','Valor de c(u,v).'),
    ('red.capacidad_arista.fuente','Origen del dato de capacidad.'),
    ('red.corte_minimo.capacidad_corte','Capacidad del corte (= flujo máximo).'),
    ('red.corte_minimo.numero_corte','Número del corte dentro de la ejecución.'),
    ('red.ejecucion_flujo.algoritmo','Algoritmo usado.'),
    ('red.ejecucion_flujo.duracion_ms','Derivado: duración de la ejecución.'),
    ('red.ejecucion_flujo.finalizado_en','Fin de la ejecución.'),
    ('red.ejecucion_flujo.flujo_maximo','Valor del flujo máximo.'),
    ('red.ejecucion_flujo.iniciado_en','Inicio de la ejecución.'),
    ('red.ejecucion_flujo.mensaje_error','Error, si lo hubo.'),
    ('red.ejecucion_flujo.parametros','Parámetros de la ejecución.'),
    ('red.ejecucion_flujo.version_modulo','Versión del módulo matemático.'),
    ('red.escenario_arista.capacidad_ajustada','Capacidad que sustituye a la heredada.'),
    ('red.escenario_arista.motivo','Motivo del ajuste.'),
    ('red.escenario_nodo.demanda','Demanda del nodo sumidero.'),
    ('red.escenario_nodo.oferta','Oferta del nodo fuente.'),
    ('red.resultado_flujo_arista.capacidad','Capacidad efectiva usada en el cálculo.'),
    ('red.resultado_flujo_arista.flujo','Valor de f(u,v).'),
    ('red.resultado_flujo_arista.utilizacion','Derivado: flujo / capacidad × 100.'),
    ('seg.ecosistema.tipo','Tipo de organización que coordina la red.'),
    ('seg.ecosistema.zona_horaria','Zona horaria para reportes.'),
    ('seg.habilitacion_tecnica.evidencia_ref','Referencia del certificado que habilita.'),
    ('seg.permiso.accion','Acción permitida.'),
    ('seg.permiso.recurso','Recurso protegido.'),
    ('seg.rol.es_servicio','Rol de una cuenta técnica.'),
    ('seg.segregacion_funciones.motivo','Por qué los roles son incompatibles.'),
    ('seg.usuario.hash_credencial','Hash de credencial solo para usuarios LOCAL.'),
    ('seg.usuario.mfa_habilitado','Si tiene segundo factor activo.'),
    ('seg.usuario.proveedor_identidad','COGNITO o LOCAL.'),
    ('seg.usuario.sub_externo','Identificador del usuario en el proveedor de identidad.'),
    ('seg.usuario.ultimo_acceso_en','Último acceso.'),
    ('seg.usuario_rol.motivo','Motivo de la asignación.'),
    ('trz.dispositivo.anio_fabricacion','Año de fabricación (la antigüedad es derivada).'),
    ('trz.dispositivo.numero_serie','Número de serie (único por marca).'),
    ('trz.lote.proposito','Propósito del lote.'),
    ('trz.lote.sellado_en','Fecha de sellado del lote.'),
    ('trz.lote_composicion.motivo','Motivo de incorporación o salida.'),
    ('trz.lote_genealogia.operacion','DIVISION, FUSION o REEMPAQUE.'),
    ('trz.objeto_trazable.registrado_en','Fecha de registro (RN-01).')
  ) AS v(col, comentario) LOOP
    EXECUTE format('COMMENT ON COLUMN %s IS %L', r.col, r.comentario);
  END LOOP;
END $$;
