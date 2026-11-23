-- =====================================================================
-- Script 06: pruebas de integración de la base de datos
-- Ciclo completo de trazabilidad + pruebas negativas de RN-01…RN-09,
-- seguridad (RLS, privilegios), MCP, auditoría, recursividad.
-- Cada paso positivo es una transacción, como lo haría la API.
-- Resultado: tabla prueba.resultado (CP-xx, PASS/FAIL, detalle)
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;
\set u_gen   '00000000-0000-4000-8000-000000000001'
\set u_muni  '00000000-0000-4000-8000-000000000002'
\set u_c1    '00000000-0000-4000-8000-000000000003'
\set u_c2    '00000000-0000-4000-8000-000000000004'
\set u_e1    '00000000-0000-4000-8000-000000000005'
\set u_tece1 '00000000-0000-4000-8000-000000000006'
\set u_tecc2 '00000000-0000-4000-8000-000000000007'
\set u_tecr1 '00000000-0000-4000-8000-000000000008'
\set u_coord '00000000-0000-4000-8000-000000000009'
\set u_gr1   '00000000-0000-4000-8000-000000000010'
\set u_gk1   '00000000-0000-4000-8000-000000000011'
\set u_benef '00000000-0000-4000-8000-000000000012'
\set u_admin '00000000-0000-4000-8000-000000000013'
\set u_audit '00000000-0000-4000-8000-000000000014'
\set u_sede  '00000000-0000-4000-8000-000000000016'
\set u_otro  '00000000-0000-4000-8000-000000000017'

DROP SCHEMA IF EXISTS prueba CASCADE;
CREATE SCHEMA prueba;
CREATE TABLE prueba.resultado (
  id serial PRIMARY KEY, caso text NOT NULL, descripcion text NOT NULL,
  estado text NOT NULL CHECK (estado IN ('PASS','FAIL')), detalle text, en timestamptz DEFAULT clock_timestamp());

CREATE FUNCTION prueba.ok(p_caso text, p_desc text, p_ok boolean, p_detalle text DEFAULT NULL) RETURNS void LANGUAGE sql AS $$
  INSERT INTO prueba.resultado(caso, descripcion, estado, detalle) VALUES (p_caso, p_desc, CASE WHEN p_ok THEN 'PASS' ELSE 'FAIL' END, p_detalle)
$$;

-- Ejecuta p_sql en una subtransacción con el contexto de p_usuario (y opcionalmente con un rol de BD);
-- PASS si falla con el SQLSTATE esperado. Los efectos siempre se deshacen.
CREATE FUNCTION prueba.error(p_caso text, p_desc text, p_usuario uuid, p_sql text, p_estado text, p_rol text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    IF p_usuario IS NOT NULL THEN PERFORM api.fn_iniciar_contexto(p_usuario, 'API'); END IF;
    IF p_rol IS NOT NULL THEN EXECUTE format('SET LOCAL ROLE %I', p_rol); END IF;
    EXECUTE p_sql;
    RAISE EXCEPTION 'sin error' USING ERRCODE = 'TS001';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'TS001' THEN
      PERFORM prueba.ok(p_caso, p_desc, false, 'No lanzó error');
    ELSE
      PERFORM prueba.ok(p_caso, p_desc, SQLSTATE = p_estado, SQLSTATE || ': ' || SQLERRM);
    END IF;
  END;
END $$;

-- Evidencia sintética (huella aleatoria) en el contexto del usuario actual
CREATE FUNCTION prueba.evid(p_tipo text, p_objeto uuid DEFAULT NULL, p_mime text DEFAULT 'application/pdf') RETURNS uuid LANGUAGE sql AS $$
  SELECT api.fn_registrar_evidencia(p_tipo, 'ecoraee-evidencias-dev', 'pruebas/' || gen_random_uuid() || '.bin',
                                    encode(digest(gen_random_uuid()::text, 'sha256'), 'hex'), p_mime, 120000, true, p_objeto)
$$;
CREATE FUNCTION prueba.estado(p_codigo text) RETURNS text LANGUAGE sql AS $$
  SELECT e.codigo FROM trz.objeto_trazable o JOIN cat.estado_trazabilidad e ON e.id = o.estado_actual_id WHERE o.codigo = p_codigo
$$;
CREATE FUNCTION prueba.uid(p_codigo text) RETURNS uuid LANGUAGE sql AS $$ SELECT uid FROM trz.objeto_trazable WHERE codigo = p_codigo $$;
CREATE FUNCTION prueba.saldo(p_centro text, p_clas text) RETURNS integer LANGUAGE sql AS $$
  SELECT coalesce(sum(s.unidades), 0)::int FROM inv.saldo_ubicacion s JOIN org.ubicacion u ON u.id = s.ubicacion_id
    JOIN org.centro c ON c.id = u.centro_id JOIN cat.clasificacion_tecnica k ON k.id = s.clasificacion_id
   WHERE c.codigo = p_centro AND k.codigo = p_clas
$$;

-- =====================================================================
-- 1. Registro (RN-01, CP-02)
-- =====================================================================
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_gen', 'WEB') \gset ctx_
SELECT api.fn_registrar_dispositivo('LAP-001', 'PORTATIL', 2.1, true, 'DELL', 'Latitude 5490', 'SN-DL-0001', 2018,
       '{"ram_gb":8,"almacenamiento_gb":256,"procesador":"i5-8350U"}') AS lap1 \gset
SELECT api.fn_registrar_dispositivo('LAP-002', 'PORTATIL', 1.8, true, 'LENOVO', 'ThinkPad T470', 'SN-LN-0002', 2017,
       '{"ram_gb":4,"almacenamiento_gb":128}') AS lap2 \gset
SELECT api.fn_registrar_dispositivo('MON-001', 'MONITOR', 3.2, false, 'LG', '22MK400', 'SN-LG-0003', 2018, '{"pulgadas":22}') AS mon1 \gset
SELECT api.fn_crear_lote('LOT-UNIV-01', 'RECEPCION', ARRAY[:'lap1', :'lap2', :'mon1']::uuid[], 'Donación de laboratorio', 7.0) AS lot1 \gset
COMMIT;

SELECT prueba.ok('CP-02', 'Registro de 3 dispositivos y 1 lote con historial inicial',
  (SELECT count(*) FROM trz.historial_estado h JOIN trz.objeto_trazable o ON o.id = h.objeto_id WHERE o.codigo IN ('LAP-001','LAP-002','MON-001','LOT-UNIV-01')) = 4);
SELECT prueba.error('CP-02', 'Código duplicado en el ecosistema', :'u_gen',
  $$SELECT api.fn_registrar_dispositivo('LAP-001','PORTATIL',2,false,NULL,NULL,NULL,NULL,'{"ram_gb":1,"almacenamiento_gb":1}')$$, '23505');
SELECT prueba.error('CP-02', 'Número de serie duplicado para la misma marca', :'u_gen',
  $$SELECT api.fn_registrar_dispositivo('LAP-099','PORTATIL',2,false,'DELL',NULL,'SN-DL-0001',NULL,'{"ram_gb":1,"almacenamiento_gb":1}')$$, '23505');
SELECT prueba.error('CP-02', 'Atributos obligatorios de la categoría', :'u_gen',
  $$SELECT api.fn_registrar_dispositivo('LAP-098','PORTATIL',2,false,NULL,NULL,NULL,NULL,'{"ram_gb":8}')$$, 'EC422');
SELECT prueba.error('CP-01', 'Un generador no registra equipos de otra organización', :'u_gen',
  $$SELECT api.fn_registrar_dispositivo('LAP-097','PORTATIL',2,false,NULL,NULL,NULL,NULL,'{"ram_gb":1,"almacenamiento_gb":1}',
     (SELECT uid FROM org.organizacion WHERE codigo='GEN-MUNI'))$$, 'EC403');
SELECT prueba.error('RN-01', 'La identidad del objeto es inmutable', NULL,
  $$UPDATE trz.objeto_trazable SET codigo = 'OTRO' WHERE codigo = 'LAP-001'$$, 'EC422');
SELECT prueba.error('RN-01', 'El estado no se cambia por UPDATE directo', NULL,
  $$UPDATE trz.objeto_trazable SET estado_actual_id = (SELECT id FROM cat.estado_trazabilidad WHERE codigo='CERRADO') WHERE codigo = 'LAP-001'$$, 'EC422');

-- =====================================================================
-- 2. Solicitud, recolección y recepción (propagación por lote, RN-05 en G→C)
-- =====================================================================
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_gen') \gset ctx_
SELECT api.fn_solicitar_recoleccion(ARRAY[:'lot1']::uuid[], 'C1', 'RECOLECCION', current_date + 1, 'Campus norte') AS sol1 \gset
COMMIT;
SELECT prueba.ok('CP-03', 'La solicitud propaga el estado del lote a sus 3 miembros',
  (SELECT bool_and(prueba.estado(c) = 'RECOLECCION_SOLICITADA') FROM unnest(ARRAY['LOT-UNIV-01','LAP-001','LAP-002','MON-001']) c));
SELECT prueba.error('CP-03', 'Transición inválida: recibir en C1 algo aún no recolectado no está en T (RECOLECCION_SOLICITADA→RECIBIDO)', :'u_c1',
  format($$SELECT api.fn_recibir(ARRAY['%s']::uuid[], 'C1', 'EST-01', ARRAY[prueba.evid('FOTO_RECEPCION', NULL, 'image/jpeg')])$$, :'lot1'), 'EC409');

BEGIN;
SELECT api.fn_iniciar_contexto(:'u_coord') \gset ctx_
SELECT api.fn_programar_recoleccion(:'sol1', now() + interval '1 day', 'Camión 01') AS rcl1 \gset
COMMIT;
SELECT prueba.ok('RN-05', 'La recolección consume capacidad del arco G1→C1',
  (SELECT consumo FROM api.v1_utilizacion_arista WHERE origen = 'G1' AND destino = 'C1') = 3);

SELECT prueba.error('RNF-10', 'Fotografía con metadatos EXIF/GPS es rechazada', :'u_c1',
  $$SELECT api.fn_registrar_evidencia('FOTO_RECEPCION','b','k/x.jpg',repeat('a',64),'image/jpeg',1000,false)$$, 'EC422');
SELECT prueba.error('CP-01', 'Operador de C2 no puede recibir en C1 (alcance por centro)', :'u_c2',
  format($$SELECT api.fn_recibir(ARRAY['%s']::uuid[], 'C1', 'EST-01')$$, :'lot1'), 'EC403');
SELECT prueba.error('RN-03', 'Recepción sin evidencia es rechazada', :'u_c1',
  format($$SELECT api.fn_recibir(ARRAY['%s']::uuid[], 'C1', 'EST-01', '{}', 'CONFORME', '%s')$$, :'lot1', :'sol1'), 'EC422');

BEGIN;
SELECT api.fn_iniciar_contexto(:'u_c1') \gset ctx_
SELECT prueba.evid('FOTO_RECEPCION', NULL, 'image/jpeg') AS foto1 \gset
SELECT api.fn_recibir(ARRAY[:'lot1']::uuid[], 'C1', 'EST-01', ARRAY[:'foto1']::uuid[], 'CONFORME', :'sol1', 7.1) AS rcp1 \gset
COMMIT;
SELECT prueba.ok('RN-06', 'Recepción: 3 unidades PENDIENTE en el inventario de C1', prueba.saldo('C1', 'PENDIENTE') = 3);
SELECT prueba.ok('REC', 'Ubicación recursiva: EST-01 cuelga de ZONA-1 y BOD-A (nivel 4)',
  (SELECT nivel FROM org.ubicacion u JOIN org.centro c ON c.id = u.centro_id WHERE c.codigo = 'C1' AND u.codigo = 'EST-01') = 4);

-- =====================================================================
-- 3. Traslado C1→E1 sin clasificar, recepción y desagrupación del lote
-- =====================================================================
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_coord') \gset ctx_
SELECT api.fn_transferir(ARRAY[:'lot1']::uuid[], 'C1', 'E1', 'LAB', NULL, 'Camión 02') AS trf1 \gset
COMMIT;
SELECT prueba.ok('RN-06', 'Despacho atómico: saldo de C1 vuelve a 0 y kardex con 3 salidas',
  prueba.saldo('C1','PENDIENTE') = 0 AND (SELECT count(*) FROM inv.movimiento_inventario m JOIN ops.documento_operativo d ON d.id = m.documento_id
                                          WHERE d.uid = :'trf1' AND m.sentido = -1) = 3);
SELECT prueba.error('RN-03', 'Confirmar traslado sin evidencia', :'u_e1',
  format($$SELECT api.fn_recibir_transferencia('%s', '{}')$$, :'trf1'), 'EC422');
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_e1') \gset ctx_
SELECT prueba.evid('GUIA_REMISION') AS guia1 \gset
SELECT api.fn_recibir_transferencia(:'trf1', ARRAY[:'guia1']::uuid[]);
SELECT api.fn_desagrupar_lote(:'lot1', 'Se evalúa cada equipo por separado');
COMMIT;
SELECT prueba.ok('RN-03', 'Traslado cerrado con origen, destino, responsable, confirmación y evidencia',
  (SELECT estado_transferencia FROM ops.transferencia t JOIN ops.documento_operativo d ON d.id = t.documento_id WHERE d.uid = :'trf1') = 'CERRADA');
SELECT prueba.ok('CP-03', 'Llegan RECIBIDO a evaluación; el lote queda DESAGRUPADO y sin miembros vigentes',
  prueba.estado('LAP-001') = 'RECIBIDO' AND prueba.estado('LOT-UNIV-01') = 'DESAGRUPADO'
  AND NOT EXISTS (SELECT 1 FROM trz.lote_composicion lc JOIN trz.objeto_trazable o ON o.id = lc.lote_id WHERE o.codigo = 'LOT-UNIV-01' AND upper_inf(lc.vigencia)));

-- =====================================================================
-- 4. Evaluación técnica (RN-02)
-- =====================================================================
SELECT prueba.error('RN-02', 'Un operador (no técnico) no puede evaluar', :'u_e1',
  format($$SELECT api.fn_evaluar('%s','REPARABLE','REACONDICIONAMIENTO',false)$$, :'lap1'), 'EC403');
SELECT prueba.error('RN-02', 'Técnico de C2 no evalúa en E1 (alcance)', :'u_tecc2',
  format($$SELECT api.fn_evaluar('%s','REPARABLE','REACONDICIONAMIENTO',false)$$, :'lap1'), 'EC403');
SELECT prueba.error('RN-02', 'Destino incompatible con la clasificación (matriz)', :'u_tece1',
  format($$SELECT api.fn_evaluar('%s','RECICLABLE','REUTILIZACION',false)$$, :'lap2'), '23503');
SELECT prueba.error('RN-02', 'Criterios obligatorios faltantes (trigger diferido al confirmar)', :'u_tece1',
  format($$SELECT api.fn_evaluar('%s','REPARABLE','REACONDICIONAMIENTO',false,'[{"criterio":"ENCIENDE","valor":true,"cumple":true}]'); SET CONSTRAINTS ALL IMMEDIATE$$, :'lap1'), 'EC422');

BEGIN;
SELECT api.fn_iniciar_contexto(:'u_tece1') \gset ctx_
SELECT api.fn_evaluar(:'lap1', 'REPARABLE', 'REACONDICIONAMIENTO', false,
  '[{"criterio":"ENCIENDE","valor":true,"cumple":true},{"criterio":"DANO_FISICO","valor":false,"cumple":true},
    {"criterio":"PANTALLA_FUNCIONAL","valor":false,"cumple":false},{"criterio":"DATOS_PRESENTES","valor":true,"cumple":false},
    {"criterio":"BATERIA_SALUD_PCT","valor":41,"cumple":false}]', 'COMPLETA', true, 55) AS eva1 \gset
SELECT api.fn_evaluar(:'lap2', 'RECICLABLE', 'RECICLAJE', false,
  '[{"criterio":"ENCIENDE","valor":false,"cumple":false},{"criterio":"DANO_FISICO","valor":true,"cumple":false},
    {"criterio":"PANTALLA_FUNCIONAL","valor":false,"cumple":false},{"criterio":"DATOS_PRESENTES","valor":false,"cumple":true}]', 'COMPLETA', false, 10) AS eva2 \gset
SELECT api.fn_evaluar(:'mon1', 'NO_RECUPERABLE', 'DISPOSICION_CONTROLADA', false,
  '[{"criterio":"ENCIENDE","valor":false,"cumple":false},{"criterio":"DANO_FISICO","valor":true,"cumple":false}]') AS eva3 \gset
COMMIT;
SELECT prueba.ok('RN-02', 'Clasificaciones registradas por técnico habilitado; saldo se reubica de PENDIENTE a su clasificación',
  prueba.estado('LAP-001') = 'CLASIFICADO' AND prueba.saldo('E1','PENDIENTE') = 0 AND prueba.saldo('E1','REPARABLE') = 1
  AND prueba.saldo('E1','RECICLABLE') = 1 AND prueba.saldo('E1','NO_RECUPERABLE') = 1);
SELECT prueba.error('RN-02', 'La evaluación es inmutable (corrección = reevaluación)', NULL,
  $$UPDATE ops.evaluacion_tecnica SET clasificacion_id = (SELECT id FROM cat.clasificacion_tecnica WHERE codigo='REUTILIZABLE')$$, 'EC422');

-- =====================================================================
-- 5. Rutas: compatibilidad clasificación ↔ destino (RN-04) y traslados desde E1
-- =====================================================================
SELECT prueba.error('RN-04', 'Un NO_RECUPERABLE no puede ir a un beneficiario', :'u_coord',
  format($$SELECT api.fn_transferir(ARRAY['%s']::uuid[], 'E1', 'B1')$$, :'mon1'), 'EC422');
SELECT prueba.error('RN-04', 'Un RECICLABLE no puede ir a reacondicionamiento', :'u_coord',
  format($$SELECT api.fn_transferir(ARRAY['%s']::uuid[], 'E1', 'R1')$$, :'lap2'), 'EC422');
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_coord') \gset ctx_
SELECT api.fn_transferir(ARRAY[:'lap1']::uuid[], 'E1', 'R1', 'TALLER') AS trf2 \gset
SELECT api.fn_transferir(ARRAY[:'lap2']::uuid[], 'E1', 'K1', 'PATIO') AS trf3 \gset
SELECT api.fn_transferir(ARRAY[:'mon1']::uuid[], 'E1', 'D1') AS trf4 \gset
SELECT prueba.evid('GUIA_REMISION') AS guia4 \gset
SELECT api.fn_recibir_transferencia(:'trf4', ARRAY[:'guia4']::uuid[]);   -- el coordinador hereda TRANSFERENCIA.CONFIRMAR del operador
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_gr1') \gset ctx_
SELECT prueba.evid('GUIA_REMISION') AS guia2 \gset
SELECT api.fn_recibir_transferencia(:'trf2', ARRAY[:'guia2']::uuid[]);
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_gk1') \gset ctx_
SELECT prueba.evid('GUIA_REMISION') AS guia3 \gset
SELECT api.fn_recibir_transferencia(:'trf3', ARRAY[:'guia3']::uuid[]);
COMMIT;
SELECT prueba.ok('CP-03', 'LAP-001 y LAP-002 en tratamiento; jerarquía de roles: el coordinador confirmó D1 como operador',
  prueba.estado('LAP-001') = 'EN_TRATAMIENTO' AND prueba.estado('LAP-002') = 'EN_TRATAMIENTO' AND prueba.estado('MON-001') = 'EN_TRATAMIENTO');

-- =====================================================================
-- 6. Reacondicionamiento, reevaluación, RN-09, asignación y cierre (reutilización)
-- =====================================================================
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_gr1') \gset ctx_
SELECT prueba.evid('FOTO_TRATAMIENTO', NULL, 'image/png') AS ftr1 \gset
SELECT api.fn_registrar_tratamiento(:'lap1', 'REACONDICIONAMIENTO_COMPLETO', 'EXITOSO', ARRAY[:'ftr1']::uuid[], '[]',
       'Cambio de pantalla y batería') AS trt1 \gset
COMMIT;
SELECT prueba.error('RN-02', 'Reevaluación sin motivo', :'u_tecr1',
  format($$SELECT api.fn_evaluar('%s','REUTILIZABLE','REUTILIZACION',true)$$, :'lap1'), 'EC422');
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_tecr1') \gset ctx_
SELECT api.fn_evaluar(:'lap1', 'REUTILIZABLE', 'REUTILIZACION', true,
  '[{"criterio":"ENCIENDE","valor":true,"cumple":true},{"criterio":"DANO_FISICO","valor":false,"cumple":true},
    {"criterio":"PANTALLA_FUNCIONAL","valor":true,"cumple":true},{"criterio":"DATOS_PRESENTES","valor":true,"cumple":false}]',
  'COMPLETA', true, 88, 'CONTROL_CALIDAD') AS eva4 \gset
COMMIT;
SELECT prueba.ok('REC', 'Cadena de reevaluaciones: la nueva apunta a la anterior y solo una queda vigente',
  (SELECT count(*) FILTER (WHERE vigente) = 1 AND count(*) = 2 AND count(evaluacion_anterior_id) = 1
     FROM ops.evaluacion_tecnica et JOIN trz.objeto_trazable o ON o.id = et.objeto_id WHERE o.codigo = 'LAP-001'));
SELECT prueba.error('RN-09', 'Equipo con almacenamiento sin certificado de borrado no se asigna', :'u_coord',
  format($$SELECT api.fn_transferir(ARRAY['%s']::uuid[], 'R1', 'B1', NULL, 'Inclusión digital')$$, :'lap1'), 'EC422');
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_tecr1') \gset ctx_
SELECT prueba.evid('CERTIFICADO_BORRADO', :'lap1') AS cbor \gset
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_coord') \gset ctx_
SELECT api.fn_transferir(ARRAY[:'lap1']::uuid[], 'R1', 'B1', NULL, 'Programa de inclusión digital escolar') AS trf5 \gset
COMMIT;
SELECT prueba.error('CP-01', 'Solo la organización beneficiaria confirma la entrega', :'u_gk1',
  format($$SELECT api.fn_recibir_transferencia('%s', ARRAY[prueba.evid('GUIA_REMISION')])$$, :'trf5'), 'EC403');
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_benef') \gset ctx_
SELECT prueba.evid('ACTA_ENTREGA') AS acta1 \gset
SELECT api.fn_recibir_transferencia(:'trf5', ARRAY[:'acta1']::uuid[]);
COMMIT;
SELECT prueba.error('RN-08', 'Cierre con fecha de confirmación futura', :'u_benef',
  format($$SELECT api.fn_cerrar_trazabilidad('%s', now() + interval '2 days', ARRAY[prueba.evid('ACTA_ENTREGA')])$$, :'lap1'), 'EC422');
SELECT prueba.error('RN-08', 'Cierre sin evidencia', :'u_benef',
  format($$SELECT api.fn_cerrar_trazabilidad('%s', now(), '{}')$$, :'lap1'), 'EC422');
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_benef') \gset ctx_
SELECT prueba.evid('ACTA_ENTREGA') AS acta2 \gset
SELECT api.fn_cerrar_trazabilidad(:'lap1', now(), ARRAY[:'acta2']::uuid[], 'Equipo entregado a escuela fiscal') AS cie1 \gset
COMMIT;
SELECT prueba.ok('CP-14', 'LAP-001: ciclo completo REGISTRADO→…→CERRADO con destino REUTILIZACION',
  (SELECT (api.fn_linea_trazabilidad('LAP-001') -> 'cierre' ->> 'destino_final') = 'REUTILIZACION'
      AND (api.fn_linea_trazabilidad('LAP-001') ->> 'trazabilidad_completa')::boolean));

-- =====================================================================
-- 7. Reciclaje con fracciones y cierre
-- =====================================================================
SELECT prueba.error('RN-08', 'Fracciones recuperadas superiores al peso del equipo', :'u_gk1',
  format($$SELECT api.fn_registrar_tratamiento('%s','DESENSAMBLE_RECICLAJE','EXITOSO',ARRAY[prueba.evid('CERTIFICADO_TRATAMIENTO')],
           '[{"material":"ALUMINIO","peso_kg":3}]')$$, :'lap2'), 'EC422');
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_gk1') \gset ctx_
SELECT prueba.evid('CERTIFICADO_TRATAMIENTO') AS ctr1 \gset
SELECT api.fn_registrar_tratamiento(:'lap2', 'DESENSAMBLE_RECICLAJE', 'EXITOSO', ARRAY[:'ctr1']::uuid[],
  '[{"material":"ALUMINIO","peso_kg":0.45},{"material":"PLASTICO","peso_kg":0.6},{"material":"TARJETA_CIRCUITO","peso_kg":0.3},
    {"material":"BATERIA_LITIO","peso_kg":0.3}]') AS trt2 \gset
SELECT prueba.evid('CERTIFICADO_TRATAMIENTO') AS ctr2 \gset
SELECT api.fn_cerrar_trazabilidad(:'lap2', now(), ARRAY[:'ctr2']::uuid[]) AS cie2 \gset
COMMIT;
SELECT prueba.ok('RN-08', 'LAP-002 cerrado con destino RECICLAJE y sin saldo en K1',
  prueba.estado('LAP-002') = 'CERRADO' AND prueba.saldo('K1','RECICLABLE') = 0
  AND (SELECT td.codigo FROM ops.cierre_trazabilidad c JOIN cat.tipo_destino td ON td.id = c.tipo_destino_final_id
        JOIN trz.objeto_trazable o ON o.id = c.objeto_id WHERE o.codigo = 'LAP-002') = 'RECICLAJE');

-- =====================================================================
-- 8. Entrega directa, preclasificación y arco C2→K1 con excepción (ADR-004)
-- =====================================================================
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_c2') \gset ctx_
SELECT api.fn_registrar_dispositivo('ESC-001', 'ESCRITORIO', 7.5, true, 'HP', 'ProDesk 400 G4', 'SN-HP-0004', 2017,
       '{"ram_gb":4,"almacenamiento_gb":500}', (SELECT uid FROM org.organizacion WHERE codigo = 'GEN-MUNI')) AS esc1 \gset
SELECT prueba.evid('FOTO_RECEPCION', NULL, 'image/jpeg') AS foto2 \gset
SELECT api.fn_recibir(ARRAY[:'esc1']::uuid[], 'C2', 'BOD-A', ARRAY[:'foto2']::uuid[]) AS rcp2 \gset
COMMIT;
SELECT prueba.ok('R-04', 'Entrega directa sin solicitud previa: REGISTRADO→RECIBIDO', prueba.estado('ESC-001') = 'RECIBIDO');
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_tecc2') \gset ctx_
SELECT api.fn_evaluar(:'esc1', 'RECICLABLE', 'RECICLAJE', false, '[]', 'PRECLASIFICACION') AS eva5 \gset
COMMIT;
SELECT prueba.error('ADR-004', 'Sin excepción vigente el arco C2→K1 no se usa', :'u_coord',
  format($$UPDATE gob.excepcion_regla SET estado = 'VENCIDA' WHERE codigo = 'EXC-001';
           SELECT api.fn_transferir(ARRAY['%s']::uuid[], 'C2', 'K1')$$, :'esc1'), 'EC422');
SELECT prueba.error('ADR-004', 'No se crea un arco ACOPIO→RECICLAJE sin excepción', NULL,
  $$INSERT INTO red.arista(ecosistema_id, nodo_origen_id, nodo_destino_id)
    SELECT ecosistema_id, (SELECT id FROM red.nodo WHERE codigo='C1'), (SELECT id FROM red.nodo WHERE codigo='K1') FROM red.nodo WHERE codigo='C1'$$, 'EC422');
SELECT prueba.error('CP-03', 'Arco inexistente en el grafo (C2→B1)', :'u_coord',
  format($$SELECT api.fn_transferir(ARRAY['%s']::uuid[], 'C2', 'B1')$$, :'esc1'), 'EC422');
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_coord') \gset ctx_
SELECT api.fn_transferir(ARRAY[:'esc1']::uuid[], 'C2', 'K1', 'PATIO') AS trf6 \gset
COMMIT;
SELECT prueba.ok('ADR-004', 'Preclasificado en C2 viaja C2→K1 con excepción aprobada', prueba.estado('ESC-001') = 'EN_TRANSFERENCIA');

-- =====================================================================
-- 9. RN-05: capacidad por kilogramos y atomicidad (CP-05)
-- =====================================================================
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_c1') \gset ctx_
SELECT api.fn_registrar_dispositivo('RACK-001', 'EQUIPO_RED', 1850, false, 'GENERICA', NULL, 'SN-RK-01', 2015, '{}',
       (SELECT uid FROM org.organizacion WHERE codigo = 'GEN-EMP')) AS rack1 \gset
SELECT api.fn_registrar_dispositivo('MON-002', 'MONITOR', 4.0, false, 'LG', NULL, 'SN-LG-0005', 2016, '{"pulgadas":24}',
       (SELECT uid FROM org.organizacion WHERE codigo = 'GEN-EMP')) AS mon2 \gset
SELECT prueba.evid('FOTO_RECEPCION', NULL, 'image/jpeg') AS foto3 \gset
SELECT api.fn_recibir(ARRAY[:'rack1', :'mon2']::uuid[], 'C1', 'BOD-A', ARRAY[:'foto3']::uuid[]);
COMMIT;
SELECT prueba.error('RN-05', 'C1→E1 admite 1800 kg/semana: un envío de 1850 kg se rechaza', :'u_coord',
  format($$SELECT api.fn_transferir(ARRAY['%s']::uuid[], 'C1', 'E1')$$, :'rack1'), 'EC422');

-- CP-05: dos traslados en una misma transacción; el segundo viola RN-05 → se revierte también el primero
DO $$
DECLARE v_antes int; v_doc_antes int;
BEGIN
  SELECT count(*) INTO v_doc_antes FROM ops.transferencia;
  v_antes := prueba.saldo('C1','PENDIENTE');
  BEGIN
    PERFORM api.fn_iniciar_contexto('00000000-0000-4000-8000-000000000009', 'API');
    PERFORM api.fn_transferir(ARRAY[prueba.uid('MON-002')], 'C1', 'E1');      -- válido: escribe documento, kardex y estado
    PERFORM api.fn_transferir(ARRAY[prueba.uid('RACK-001')], 'C1', 'E1');     -- viola RN-05
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  PERFORM prueba.ok('CP-05', 'Rollback completo: sin traslado, saldo intacto y MON-002 sigue RECIBIDO en C1',
    (SELECT count(*) FROM ops.transferencia) = v_doc_antes AND prueba.saldo('C1','PENDIENTE') = v_antes
    AND prueba.estado('MON-002') = 'RECIBIDO');
END $$;
SELECT prueba.error('RN-06', 'Saldo nunca negativo: salida sin existencias', '00000000-0000-4000-8000-000000000003',
  $$SELECT inv.fn_registrar_movimiento((SELECT id FROM ops.documento_operativo LIMIT 1), (SELECT id FROM trz.objeto_trazable WHERE codigo='LAP-001'),
     (SELECT u.id FROM org.ubicacion u JOIN org.centro c ON c.id=u.centro_id WHERE c.codigo='C2' AND u.codigo='RAIZ'), -1::smallint, 'EGRESO')$$, 'EC422');

-- =====================================================================
-- 10. Integridad referencial, temporalidad y recursividad (CP-04)
-- =====================================================================
SELECT prueba.error('CP-04', 'No se elimina una organización con objetos asociados (RESTRICT)', NULL,
  $$DELETE FROM org.organizacion WHERE codigo = 'GEN-UNIV'$$, '23503');
SELECT prueba.error('CP-04', 'Capacidades con vigencias solapadas se rechazan', NULL,
  $$INSERT INTO red.capacidad_arista(arista_id, capacidad, unidad_id, periodo, vigencia, fuente)
    SELECT capacidad_arista.arista_id, 999, unidad_id, periodo, tstzrange(now(), NULL), 'x' FROM red.capacidad_arista LIMIT 1$$, '23P01');
SELECT prueba.error('CP-04', 'Un objeto no pertenece a dos lotes a la vez', :'u_c1',
  format($$SELECT api.fn_crear_lote('LOT-A','TRANSFERENCIA',ARRAY['%s']::uuid[]); SELECT api.fn_crear_lote('LOT-B','TRANSFERENCIA',ARRAY['%s']::uuid[])$$,
         :'mon2', :'mon2'), '23P01');
SELECT prueba.error('REC', 'Ciclo de lotes anidados', :'u_c1',
  format($$SELECT api.fn_crear_lote('LOT-X','TRANSFERENCIA',ARRAY['%s']::uuid[]);
           SELECT api.fn_crear_lote('LOT-Y','TRANSFERENCIA',ARRAY[prueba.uid('LOT-X')]);
           INSERT INTO trz.lote_composicion(lote_id, objeto_id) SELECT (SELECT id FROM trz.objeto_trazable WHERE codigo='LOT-X'),
                  (SELECT id FROM trz.objeto_trazable WHERE codigo='LOT-Y')$$, :'mon2'), 'EC422');
SELECT prueba.error('REC', 'Ciclo en el árbol de categorías', NULL,
  $$UPDATE cat.categoria_raee SET categoria_padre_id = (SELECT id FROM cat.categoria_raee WHERE codigo='PORTATIL') WHERE codigo='TIC'$$, 'EC422');
SELECT prueba.error('REC', 'Ciclo en la jerarquía de organizaciones', NULL,
  $$UPDATE org.organizacion SET organizacion_padre_id = (SELECT id FROM org.organizacion WHERE codigo='GEN-UNIV-S2') WHERE codigo='GEN-UNIV'$$, 'EC422');
SELECT prueba.error('REC', 'Ciclo en la herencia de roles', NULL,
  $$UPDATE seg.rol SET rol_padre_id = (SELECT id FROM seg.rol WHERE codigo='COORDINADOR_LOGISTICO') WHERE codigo='OPERADOR_CENTRO'$$, 'EC422');
SELECT prueba.error('REC', 'Ciclo en la herencia de escenarios', NULL,
  $$UPDATE red.escenario_red SET escenario_base_id = (SELECT id FROM red.escenario_red WHERE codigo='E2') WHERE codigo='E0'$$, 'EC422');
SELECT prueba.ok('REC', 'Árbol de categorías: PORTATIL desciende de TIC y de RAEE (ltree)',
  (SELECT p.ruta <@ t.ruta AND p.ruta <@ r.ruta FROM cat.categoria_raee p, cat.categoria_raee t, cat.categoria_raee r
    WHERE p.codigo='PORTATIL' AND t.codigo='TIC' AND r.codigo='RAEE'));
SELECT prueba.error('SoD', 'Segregación de funciones: un administrador no puede ser técnico', NULL,
  $$INSERT INTO seg.usuario_rol(usuario_id, rol_id) SELECT u.id, r.id FROM seg.usuario u, seg.rol r WHERE u.alias='admin' AND r.codigo='TECNICO_EVALUADOR'$$, 'EC422');
SELECT prueba.error('RN-01', 'El historial de estados es inmutable', NULL, $$UPDATE trz.historial_estado SET observacion = 'x'$$, 'EC422');
SELECT prueba.error('RN-01', 'El kardex es inmutable', NULL, $$DELETE FROM inv.movimiento_inventario$$, 'EC422');

-- =====================================================================
-- 11. Seguridad: RLS por ecosistema y rol, privilegios de columnas (CP-01, RN-07)
-- =====================================================================
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_sede') \gset ctx_
SELECT api.fn_registrar_dispositivo('CEL-001', 'CELULAR', 0.18, true, 'SAMSUNG', 'Galaxy A10', 'SN-SM-0006', 2019, '{}') AS cel1 \gset
COMMIT;
DO $$
DECLARE n int; v_gen int; v_sede int; v_muni int; v_otro int; v_benef int; v_aud int;
BEGIN
  SET LOCAL ROLE ecoraee_app;
  PERFORM api.fn_iniciar_contexto('00000000-0000-4000-8000-000000000001'); SELECT count(*) INTO v_gen  FROM api.v1_objeto;
  PERFORM api.fn_iniciar_contexto('00000000-0000-4000-8000-000000000016'); SELECT count(*) INTO v_sede FROM api.v1_objeto;
  PERFORM api.fn_iniciar_contexto('00000000-0000-4000-8000-000000000002'); SELECT count(*) INTO v_muni FROM api.v1_objeto;
  PERFORM api.fn_iniciar_contexto('00000000-0000-4000-8000-000000000017'); SELECT count(*) INTO v_otro FROM api.v1_objeto;
  PERFORM api.fn_iniciar_contexto('00000000-0000-4000-8000-000000000012'); SELECT count(*) INTO v_benef FROM api.v1_objeto;
  PERFORM api.fn_iniciar_contexto('00000000-0000-4000-8000-000000000014'); SELECT count(*) INTO v_aud FROM api.v1_objeto;
  RESET ROLE;
  PERFORM prueba.ok('CP-01', format('RLS: universidad ve lo suyo y lo de su sede (%s objetos)', v_gen), v_gen = 5);
  PERFORM prueba.ok('CP-01', format('RLS: la sede sur no ve lo de la matriz (%s)', v_sede), v_sede = 1);
  PERFORM prueba.ok('CP-01', format('RLS: municipio solo ve su equipo (%s)', v_muni), v_muni = 1);
  PERFORM prueba.ok('CP-01', format('RLS: otro ecosistema no ve nada de RCM (%s)', v_otro), v_otro = 0);
  PERFORM prueba.ok('CP-01', format('RLS: beneficiario solo ve lo asignado (%s)', v_benef), v_benef = 1);
  PERFORM prueba.ok('CP-01', format('RLS: auditor ve todo el ecosistema (%s)', v_aud), v_aud = (SELECT count(*) FROM trz.objeto_trazable o JOIN seg.ecosistema e ON e.id = o.ecosistema_id WHERE e.codigo='RCM'));
END $$;
SELECT prueba.error('RNF-03', 'El rol de la API no lee correos de usuarios', :'u_audit', $$SELECT correo FROM seg.usuario$$, '42501', 'ecoraee_app');
SELECT prueba.error('RNF-03', 'El rol de la API no escribe tablas directamente', :'u_c1',
  $$INSERT INTO trz.historial_estado(objeto_id, estado_destino_id, usuario_id) VALUES (1,1,1)$$, '42501', 'ecoraee_app');
SELECT prueba.error('RNF-03', 'El rol de la API no lee claves S3', :'u_audit', $$SELECT s3_clave FROM evd.evidencia$$, '42501', 'ecoraee_app');
DO $$
DECLARE v_gen int; v_aud int; r1 jsonb; r2 jsonb;
        v_cert uuid := (SELECT e.uid FROM evd.evidencia e JOIN cat.tipo_evidencia t ON t.id = e.tipo_evidencia_id WHERE t.codigo='CERTIFICADO_BORRADO');
BEGIN
  SET LOCAL ROLE ecoraee_app;
  PERFORM api.fn_iniciar_contexto('00000000-0000-4000-8000-000000000001');
  SELECT count(*) INTO v_gen FROM evd.evidencia e JOIN cat.tipo_evidencia t ON t.id = e.tipo_evidencia_id WHERE t.codigo = 'CERTIFICADO_BORRADO';
  PERFORM api.fn_iniciar_contexto('00000000-0000-4000-8000-000000000014');
  SELECT count(*) INTO v_aud FROM evd.evidencia e JOIN cat.tipo_evidencia t ON t.id = e.tipo_evidencia_id WHERE t.codigo = 'CERTIFICADO_BORRADO';
  r1 := api.fn_obtener_evidencia(v_cert, 'AUDITORIA');
  PERFORM api.fn_iniciar_contexto('00000000-0000-4000-8000-000000000003');
  r2 := api.fn_obtener_evidencia(v_cert, 'TRAZABILIDAD');   -- el operador ni siquiera la ve por RLS
  RESET ROLE;
  PERFORM prueba.ok('RN-07', format('Evidencia restringida invisible para el generador (%s) y visible para el auditor (%s)', v_gen, v_aud), v_gen = 0 AND v_aud = 1);
  PERFORM prueba.ok('RN-07', 'Descarga por propósito: auditor PERMITIDO, operador DENEGADO y ambos registrados',
    (r1 ->> 'permitido')::boolean AND NOT (r2 ->> 'permitido')::boolean
    AND (SELECT count(*) FROM evd.acceso_evidencia) = 2 AND (SELECT count(*) FROM aud.evento_seguridad WHERE tipo = 'ACCESO_DENEGADO') = 1);
END $$;

-- =====================================================================
-- 12. Capa MCP: catálogo por rol, autorización, confirmación, límites, privilegios
-- =====================================================================
DO $$
DECLARE n_gen int; n_coord int; a1 jsonb; a2 jsonb; a3 jsonb; a4 jsonb; a5 jsonb; i int; rec jsonb;
BEGIN
  SET LOCAL ROLE ecoraee_mcp;
  PERFORM api.fn_iniciar_contexto('00000000-0000-4000-8000-000000000001', 'MCP');
  SELECT count(*) INTO n_gen FROM api.v1_mcp_catalogo;
  a1 := api.fn_mcp_autorizar('ejecutar_flujo_maximo', '{"escenario":"E0"}', 'sesion-1');
  a2 := api.fn_mcp_autorizar('registrar_dispositivo', '{"codigo":"X","correo":"a@b.c"}', 'sesion-1');
  a3 := api.fn_mcp_autorizar('registrar_dispositivo', '{"codigo":"X","_confirmado":true}', 'sesion-1');
  a4 := api.fn_mcp_autorizar('borrar_todo', '{}', 'sesion-1');
  rec := api.fn_mcp_leer_recurso('ecoraee://objeto/LAP-001');
  PERFORM api.fn_iniciar_contexto('00000000-0000-4000-8000-000000000009', 'MCP');
  SELECT count(*) INTO n_coord FROM api.v1_mcp_catalogo;
  FOR i IN 1..10 LOOP PERFORM api.fn_mcp_registrar('ejecutar_flujo_maximo', 'sesion-2', '{"escenario":"E0"}', 'OK', 14, 12); END LOOP;
  a5 := api.fn_mcp_autorizar('ejecutar_flujo_maximo', '{"escenario":"E0"}', 'sesion-2');
  RESET ROLE;
  PERFORM prueba.ok('MCP', format('tools/list por rol: generador %s herramientas, coordinador %s', n_gen, n_coord), n_gen = 6 AND n_coord = 11);
  PERFORM prueba.ok('MCP', 'Herramienta fuera del rol: DENEGADO', a1 ->> 'estado' = 'DENEGADO');
  PERFORM prueba.ok('MCP', 'Escritura sin confirmación humana: PENDIENTE_CONFIRMACION', a2 ->> 'estado' = 'PENDIENTE_CONFIRMACION');
  PERFORM prueba.ok('MCP', 'Escritura confirmada: AUTORIZADO', a3 ->> 'estado' = 'AUTORIZADO');
  PERFORM prueba.ok('MCP', 'Herramienta inexistente: DENEGADO + evento de seguridad',
    a4 ->> 'estado' = 'DENEGADO' AND EXISTS (SELECT 1 FROM aud.evento_seguridad WHERE tipo = 'MCP_RECHAZO'));
  PERFORM prueba.ok('MCP', 'Límite por minuto: LIMITE_EXCEDIDO tras 10 llamadas', a5 ->> 'estado' = 'LIMITE_EXCEDIDO');
  PERFORM prueba.ok('MCP', 'Recurso ecoraee://objeto/LAP-001 devuelve la ficha completa', (rec ->> 'trazabilidad_completa')::boolean);
  PERFORM prueba.ok('RNF-10', 'Bitácora MCP sin datos personales (correo enmascarado)',
    NOT EXISTS (SELECT 1 FROM mcp.invocacion WHERE argumentos::text LIKE '%a@b.c%'));
END $$;
SELECT prueba.error('MCP', 'El rol MCP no puede ejecutar comandos no registrados (fn_transferir)', :'u_coord',
  format($$SELECT api.fn_transferir(ARRAY['%s']::uuid[], 'C1', 'E1')$$, :'mon2'), '42501', 'ecoraee_mcp');

-- =====================================================================
-- 13. Auditoría: as-of, sellado y detección de manipulación
-- =====================================================================
SELECT prueba.ok('AUD', 'Cada cambio de LAP-001 quedó auditado con usuario y canal',
  (SELECT count(*) >= 8 AND bool_and(usuario_id IS NOT NULL) FROM aud.log_cambio
    WHERE tabla = 'objeto_trazable' AND pk = jsonb_build_object('id', (SELECT id FROM trz.objeto_trazable WHERE codigo='LAP-001'))));
SELECT prueba.ok('AUD', 'Reconstrucción as-of: LAP-001 estaba EN_TRATAMIENTO antes de su tratamiento',
  (SELECT e.codigo FROM cat.estado_trazabilidad e WHERE e.id = (aud.fn_estado_en('trz','objeto_trazable',
     jsonb_build_object('id', (SELECT id FROM trz.objeto_trazable WHERE codigo='LAP-001')),
     (SELECT d.fecha_documento - interval '1 millisecond' FROM ops.documento_operativo d WHERE d.uid = :'trt1')) ->> 'estado_actual_id')::smallint) = 'EN_TRATAMIENTO');
SELECT aud.fn_sellar_periodo(date_trunc('day', now()) - interval '1 day', now() + interval '1 second') AS sello \gset
SELECT prueba.ok('AUD', 'Sello de integridad verificado', aud.fn_verificar_sello((SELECT max(id) FROM aud.sello_integridad)));
BEGIN;
ALTER TABLE aud.log_cambio DISABLE TRIGGER USER;
UPDATE aud.log_cambio SET hash_registro = repeat('0', 64) WHERE id = (SELECT min(id) FROM aud.log_cambio WHERE ocurrido_en > now() - interval '1 hour');
SELECT prueba.ok('AUD', 'Manipular una fila de auditoría invalida el sello', NOT aud.fn_verificar_sello((SELECT max(id) FROM aud.sello_integridad))) \gset ign_
SELECT * FROM prueba.resultado WHERE caso = 'AUD' AND descripcion LIKE 'Manipular%' \gset tamper_
ROLLBACK;
SELECT prueba.ok(:'tamper_caso', :'tamper_descripcion', :'tamper_estado' = 'PASS');

-- =====================================================================
-- 14. Indicadores y alertas
-- =====================================================================
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_coord', 'BATCH') \gset ctx_
SELECT ind.fn_calcular_indicadores(current_date - 7, current_date) AS n_ind \gset
SELECT ind.fn_generar_alertas() AS n_alertas \gset
COMMIT;
SELECT prueba.ok('IND', format('Indicadores calculados (%s) con serie histórica', :'n_ind'), :n_ind >= 7);
SELECT prueba.ok('IND', 'Tasa de reutilización = 50 % (1 de 2 cierres)', (SELECT valor FROM api.v1_indicador WHERE codigo = 'TASA_REUTILIZACION') = 50);
SELECT prueba.ok('IND', 'Material recuperado = 1.65 kg', (SELECT valor FROM api.v1_indicador WHERE codigo = 'KG_MATERIAL_RECUPERADO') = 1.65);

-- Resumen
SELECT estado, count(*) FROM prueba.resultado GROUP BY estado ORDER BY estado;
SELECT caso, descripcion, detalle FROM prueba.resultado WHERE estado = 'FAIL';
