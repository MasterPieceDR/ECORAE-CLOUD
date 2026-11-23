-- =====================================================================
-- Script 12: datos de demostración (sintéticos, RNF-10)
-- Recorre el ciclo de vida real llamando a las mismas funciones api.*
-- que usa la API, con el usuario que corresponde a cada paso. Deja
-- equipos en todas las etapas para que cada rol tenga trabajo pendiente.
-- No se ejecuta junto con 06_pruebas.sql (ambos crean objetos).
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;
\set u_univ  '00000000-0000-4000-8000-000000000001'
\set u_muni  '00000000-0000-4000-8000-000000000002'
\set u_emp   '00000000-0000-4000-8000-000000000018'
\set u_c1    '00000000-0000-4000-8000-000000000003'
\set u_c2    '00000000-0000-4000-8000-000000000004'
\set u_e1    '00000000-0000-4000-8000-000000000005'
\set u_tece1 '00000000-0000-4000-8000-000000000006'
\set u_tecr1 '00000000-0000-4000-8000-000000000008'
\set u_coord '00000000-0000-4000-8000-000000000009'
\set u_gr1   '00000000-0000-4000-8000-000000000010'
\set u_gk1   '00000000-0000-4000-8000-000000000011'
\set u_benef '00000000-0000-4000-8000-000000000012'
\set u_admin '00000000-0000-4000-8000-000000000013'

-- Evidencia sintética: el archivo de demostración lo crea la API al inicializar (claves demo/…)
CREATE FUNCTION pg_temp.evid(p_tipo text, p_objeto uuid DEFAULT NULL) RETURNS uuid LANGUAGE sql AS $$
  SELECT api.fn_registrar_evidencia(p_tipo, 'ecoraee-evidencias', 'demo/' || lower(p_tipo) || '-' || left(gen_random_uuid()::text, 8) ||
           CASE WHEN p_tipo LIKE 'FOTO%' THEN '.png' ELSE '.pdf' END,
           encode(digest(gen_random_uuid()::text, 'sha256'), 'hex'),
           CASE WHEN p_tipo LIKE 'FOTO%' THEN 'image/png' ELSE 'application/pdf' END, 24000, true, p_objeto)
$$;

-- 1. Registro por los generadores ---------------------------------------
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_univ', 'WEB') \gset ctx_
SELECT api.fn_registrar_dispositivo('LAP-1001','PORTATIL',2.1,true,'DELL','Latitude 5490','SN-DL-1001',2018,'{"ram_gb":8,"almacenamiento_gb":256,"procesador":"i5-8350U"}') AS lap1 \gset
SELECT api.fn_registrar_dispositivo('MON-1002','MONITOR',3.4,false,'LG','22MK400','SN-LG-1002',2016,'{"pulgadas":22}') AS mon2 \gset
SELECT api.fn_registrar_dispositivo('RTR-1007','EQUIPO_RED',0.6,false,'TP-LINK',NULL,'SN-TP-1007',2019,'{}') AS rtr7 \gset
SELECT api.fn_registrar_dispositivo('LAP-1009','PORTATIL',1.9,true,'LENOVO','ThinkPad T470','SN-LN-1009',2017,'{"ram_gb":8,"almacenamiento_gb":256}') AS lap9 \gset
SELECT api.fn_registrar_dispositivo('LAP-1010','PORTATIL',2.0,true,'HP','EliteBook 840','SN-HP-1010',2018,'{"ram_gb":8,"almacenamiento_gb":512}') AS lap10 \gset
SELECT api.fn_registrar_dispositivo('MON-1011','MONITOR',3.1,false,'SAMSUNG',NULL,'SN-SM-1011',2015,'{"pulgadas":20}') AS mon11 \gset
SELECT api.fn_registrar_dispositivo('LAP-1013','PORTATIL',2.2,true,'ACER','Aspire 5','SN-AC-1013',2019,'{"ram_gb":4,"almacenamiento_gb":500}') AS lap13 \gset
SELECT api.fn_registrar_dispositivo('LAP-1014','PORTATIL',2.0,true,'DELL','Latitude 3400','SN-DL-1014',2019,'{"ram_gb":8,"almacenamiento_gb":256}') AS lap14 \gset
SELECT api.fn_crear_lote('LOT-UNIV-02','RECEPCION',ARRAY[:'lap9',:'lap10',:'mon11']::uuid[],'Renovación del laboratorio de redes',7.0) AS lot2 \gset
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_muni', 'WEB') \gset ctx_
SELECT api.fn_registrar_dispositivo('CEL-1006','CELULAR',0.2,true,'SAMSUNG','Galaxy A20','SN-SG-1006',2019,'{}') AS cel6 \gset
SELECT api.fn_registrar_dispositivo('TAB-1008','TABLET',0.5,true,'HUAWEI',NULL,'SN-HW-1008',2018,'{}') AS tab8 \gset
SELECT api.fn_registrar_dispositivo('CEL-1012','CELULAR',0.2,true,'XIAOMI',NULL,'SN-XM-1012',2020,'{}') AS cel12 \gset
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_emp', 'WEB') \gset ctx_
SELECT api.fn_registrar_dispositivo('IMP-1003','IMPRESORA',8.5,false,'HP','LaserJet P2035','SN-HP-1003',2012,'{}') AS imp3 \gset
SELECT api.fn_registrar_dispositivo('BAT-1004','BATERIA',0.9,false,NULL,NULL,NULL,NULL,'{"quimica":"Ion de litio"}') AS bat4 \gset
SELECT api.fn_registrar_dispositivo('ESC-1005','ESCRITORIO',7.8,true,'LENOVO','ThinkCentre M710','SN-LN-1005',2017,'{"ram_gb":8,"almacenamiento_gb":1000}') AS esc5 \gset
COMMIT;

-- 2. Solicitudes de recolección -----------------------------------------
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_univ') \gset ctx_
SELECT api.fn_solicitar_recoleccion(ARRAY[:'lap1',:'mon2',:'rtr7',:'lap13',:'lap14']::uuid[], 'C1', 'RECOLECCION', current_date + 1, 'Campus norte') AS sol1 \gset
SELECT api.fn_solicitar_recoleccion(ARRAY[:'lot2']::uuid[], 'C1', 'RECOLECCION', current_date + 3, 'Laboratorio de redes') AS sol2 \gset
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_muni') \gset ctx_
SELECT api.fn_solicitar_recoleccion(ARRAY[:'cel6']::uuid[], 'C2', 'RECOLECCION', current_date + 1, 'Punto limpio La Y') AS sol3 \gset
SELECT api.fn_solicitar_recoleccion(ARRAY[:'cel12']::uuid[], 'C2', 'RECOLECCION', current_date + 2, 'Punto limpio Carcelén') AS sol4 \gset
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_emp') \gset ctx_
SELECT api.fn_solicitar_recoleccion(ARRAY[:'imp3',:'bat4',:'esc5']::uuid[], 'C2', 'RECOLECCION', current_date + 1, 'Bodega central') AS sol5 \gset
COMMIT;

-- 3. Programación (coordinador) — la del lote LOT-UNIV-02 queda pendiente -----
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_coord') \gset ctx_
SELECT api.fn_programar_recoleccion(:'sol1', now() + interval '1 day', 'Camión 01') AS rcl1 \gset
SELECT api.fn_programar_recoleccion(:'sol3', now() + interval '1 day', 'Furgoneta 03') AS rcl3 \gset
SELECT api.fn_programar_recoleccion(:'sol4', now() + interval '2 days', 'Furgoneta 03') AS rcl4 \gset
SELECT api.fn_programar_recoleccion(:'sol5', now() + interval '1 day', 'Camión 02') AS rcl5 \gset
COMMIT;

-- 4. Recepción en acopios (CEL-1012 queda EN_RECOLECCION) ----------------
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_c1') \gset ctx_
SELECT pg_temp.evid('FOTO_RECEPCION') AS f1 \gset
SELECT api.fn_recibir(ARRAY[:'lap1',:'mon2',:'rtr7',:'lap13',:'lap14']::uuid[], 'C1', 'EST-01', ARRAY[:'f1']::uuid[], 'CONFORME', :'sol1', 10.3) AS rcp1 \gset
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_c2') \gset ctx_
SELECT pg_temp.evid('FOTO_RECEPCION') AS f2 \gset
SELECT api.fn_recibir(ARRAY[:'cel6']::uuid[], 'C2', 'BOD-A', ARRAY[:'f2']::uuid[], 'CONFORME', :'sol3') AS rcp2 \gset
SELECT pg_temp.evid('ACTA_RECEPCION') AS f3 \gset
SELECT api.fn_recibir(ARRAY[:'imp3',:'bat4',:'esc5']::uuid[], 'C2', 'BOD-A', ARRAY[:'f3']::uuid[], 'CONFORME', :'sol5', 17.2) AS rcp3 \gset
COMMIT;

-- 5. Traslados a evaluación (RTR-1007 se queda en C1) ---------------------
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_coord') \gset ctx_
SELECT api.fn_transferir(ARRAY[:'lap1',:'mon2',:'lap13',:'lap14']::uuid[], 'C1', 'E1', 'LAB', NULL, 'Camión 01') AS t1 \gset
SELECT api.fn_transferir(ARRAY[:'cel6',:'imp3',:'bat4',:'esc5']::uuid[], 'C2', 'E1', 'LAB', NULL, 'Camión 02') AS t2 \gset
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_e1') \gset ctx_
SELECT pg_temp.evid('GUIA_REMISION') AS g1 \gset
SELECT api.fn_recibir_transferencia(:'t1', ARRAY[:'g1']::uuid[]);
SELECT pg_temp.evid('GUIA_REMISION') AS g2 \gset
SELECT api.fn_recibir_transferencia(:'t2', ARRAY[:'g2']::uuid[]);
COMMIT;

-- 6. Evaluación técnica (CEL-1006 queda RECIBIDO, pendiente de evaluar) ----
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_tece1') \gset ctx_
SELECT api.fn_evaluar(:'lap1','REPARABLE','REACONDICIONAMIENTO',false,
  '[{"criterio":"ENCIENDE","valor":true,"cumple":true},{"criterio":"DANO_FISICO","valor":false,"cumple":true},
    {"criterio":"PANTALLA_FUNCIONAL","valor":false,"cumple":false},{"criterio":"DATOS_PRESENTES","valor":true,"cumple":false}]','COMPLETA',true,58) AS e1 \gset
SELECT api.fn_evaluar(:'lap13','REPARABLE','REACONDICIONAMIENTO',false,
  '[{"criterio":"ENCIENDE","valor":true,"cumple":true},{"criterio":"DANO_FISICO","valor":false,"cumple":true},
    {"criterio":"PANTALLA_FUNCIONAL","valor":true,"cumple":true},{"criterio":"DATOS_PRESENTES","valor":true,"cumple":false}]','COMPLETA',true,64) AS e13 \gset
SELECT api.fn_evaluar(:'lap14','REUTILIZABLE','REACONDICIONAMIENTO',true,
  '[{"criterio":"ENCIENDE","valor":true,"cumple":true},{"criterio":"DANO_FISICO","valor":false,"cumple":true},
    {"criterio":"PANTALLA_FUNCIONAL","valor":true,"cumple":true},{"criterio":"DATOS_PRESENTES","valor":true,"cumple":false}]','COMPLETA',true,81) AS e14 \gset
SELECT api.fn_evaluar(:'mon2','RECICLABLE','RECICLAJE',false,
  '[{"criterio":"ENCIENDE","valor":false,"cumple":false},{"criterio":"DANO_FISICO","valor":true,"cumple":false}]') AS e2 \gset
SELECT api.fn_evaluar(:'imp3','RECICLABLE','RECICLAJE',false,
  '[{"criterio":"ENCIENDE","valor":false,"cumple":false},{"criterio":"DANO_FISICO","valor":true,"cumple":false}]') AS e3 \gset
SELECT api.fn_evaluar(:'bat4','NO_RECUPERABLE','DISPOSICION_CONTROLADA',false,
  '[{"criterio":"ENCIENDE","valor":false,"cumple":false},{"criterio":"DANO_FISICO","valor":true,"cumple":false}]') AS e4 \gset
SELECT api.fn_evaluar(:'esc5','REPARABLE','REACONDICIONAMIENTO',true,
  '[{"criterio":"ENCIENDE","valor":true,"cumple":true},{"criterio":"DANO_FISICO","valor":false,"cumple":true}]','COMPLETA',true,70) AS e5 \gset
COMMIT;

-- 7. Traslados a tratamiento (ESC-1005 queda CLASIFICADO en E1; BAT-1004 viaja a D1) ---
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_coord') \gset ctx_
SELECT api.fn_transferir(ARRAY[:'lap1',:'lap13',:'lap14']::uuid[], 'E1', 'R1', 'TALLER', NULL, 'Camión 01') AS t3 \gset
SELECT api.fn_transferir(ARRAY[:'mon2',:'imp3']::uuid[], 'E1', 'K1', 'PATIO', NULL, 'Camión 02') AS t4 \gset
SELECT api.fn_transferir(ARRAY[:'bat4']::uuid[], 'E1', 'D1', NULL, NULL, 'Transporte de peligrosos') AS t5 \gset
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_gr1') \gset ctx_
SELECT pg_temp.evid('GUIA_REMISION') AS g3 \gset
SELECT api.fn_recibir_transferencia(:'t3', ARRAY[:'g3']::uuid[]);
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_gk1') \gset ctx_
SELECT pg_temp.evid('GUIA_REMISION') AS g4 \gset
SELECT api.fn_recibir_transferencia(:'t4', ARRAY[:'g4']::uuid[]);
COMMIT;

-- 8. Tratamientos -----------------------------------------------------------
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_gr1') \gset ctx_
SELECT pg_temp.evid('FOTO_TRATAMIENTO') AS ft1 \gset
SELECT api.fn_registrar_tratamiento(:'lap1','REACONDICIONAMIENTO_COMPLETO','EXITOSO',ARRAY[:'ft1']::uuid[],'[]','Cambio de pantalla y batería') AS tr1 \gset
SELECT pg_temp.evid('FOTO_TRATAMIENTO') AS ft13 \gset
SELECT api.fn_registrar_tratamiento(:'lap13','REPARACION_MENOR','EXITOSO',ARRAY[:'ft13']::uuid[],'[]','Limpieza y cambio de teclado') AS tr13 \gset
SELECT pg_temp.evid('FOTO_TRATAMIENTO') AS ft14 \gset
SELECT api.fn_registrar_tratamiento(:'lap14','REPARACION_MENOR','EXITOSO',ARRAY[:'ft14']::uuid[],'[]','Actualización y limpieza') AS tr14 \gset
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_gk1') \gset ctx_
SELECT pg_temp.evid('CERTIFICADO_TRATAMIENTO') AS ct2 \gset
SELECT api.fn_registrar_tratamiento(:'mon2','DESENSAMBLE_RECICLAJE','EXITOSO',ARRAY[:'ct2']::uuid[],
  '[{"material":"VIDRIO","peso_kg":1.6},{"material":"PLASTICO","peso_kg":0.9},{"material":"TARJETA_CIRCUITO","peso_kg":0.3},{"material":"COBRE","peso_kg":0.2}]') AS tr2 \gset
SELECT pg_temp.evid('CERTIFICADO_TRATAMIENTO') AS cc2 \gset
SELECT api.fn_cerrar_trazabilidad(:'mon2', now(), ARRAY[:'cc2']::uuid[], 'Materiales entregados a fundición autorizada') AS cie2 \gset
COMMIT;

-- 9. Control de calidad, borrado seguro (RN-09) y entrega a la beneficiaria -----
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_tecr1') \gset ctx_
SELECT api.fn_evaluar(:'lap1','REUTILIZABLE','REUTILIZACION',true,
  '[{"criterio":"ENCIENDE","valor":true,"cumple":true},{"criterio":"DANO_FISICO","valor":false,"cumple":true},
    {"criterio":"PANTALLA_FUNCIONAL","valor":true,"cumple":true},{"criterio":"DATOS_PRESENTES","valor":false,"cumple":true}]','COMPLETA',true,90,'CONTROL_CALIDAD') AS e1b \gset
SELECT api.fn_evaluar(:'lap13','REUTILIZABLE','REUTILIZACION',true,
  '[{"criterio":"ENCIENDE","valor":true,"cumple":true},{"criterio":"DANO_FISICO","valor":false,"cumple":true},
    {"criterio":"PANTALLA_FUNCIONAL","valor":true,"cumple":true},{"criterio":"DATOS_PRESENTES","valor":true,"cumple":false}]','COMPLETA',true,84,'CONTROL_CALIDAD') AS e13b \gset
SELECT api.fn_evaluar(:'lap14','REUTILIZABLE','REUTILIZACION',true,
  '[{"criterio":"ENCIENDE","valor":true,"cumple":true},{"criterio":"DANO_FISICO","valor":false,"cumple":true},
    {"criterio":"PANTALLA_FUNCIONAL","valor":true,"cumple":true},{"criterio":"DATOS_PRESENTES","valor":false,"cumple":true}]','COMPLETA',true,92,'CONTROL_CALIDAD') AS e14b \gset
SELECT pg_temp.evid('CERTIFICADO_BORRADO', :'lap1') AS cb1 \gset
SELECT pg_temp.evid('CERTIFICADO_BORRADO', :'lap14') AS cb14 \gset
COMMIT;
-- LAP-1013 queda TRATADO y REUTILIZABLE pero SIN certificado: la asignación la bloquea RN-09
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_coord') \gset ctx_
SELECT api.fn_transferir(ARRAY[:'lap1']::uuid[], 'R1', 'B1', NULL, 'Programa de inclusión digital escolar') AS t6 \gset
SELECT api.fn_transferir(ARRAY[:'lap14']::uuid[], 'R1', 'B1', NULL, 'Programa de inclusión digital escolar') AS t7 \gset
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_benef') \gset ctx_
SELECT pg_temp.evid('ACTA_ENTREGA') AS a6 \gset
SELECT api.fn_recibir_transferencia(:'t6', ARRAY[:'a6']::uuid[]);
SELECT pg_temp.evid('ACTA_ENTREGA') AS a7 \gset
SELECT api.fn_recibir_transferencia(:'t7', ARRAY[:'a7']::uuid[]);
SELECT pg_temp.evid('ACTA_ENTREGA') AS c6 \gset
SELECT api.fn_cerrar_trazabilidad(:'lap1', now(), ARRAY[:'c6']::uuid[], 'Equipo entregado a escuela fiscal de Calderón') AS cie1 \gset
COMMIT;
-- LAP-1014 queda ASIGNADO_BENEFICIARIO: la beneficiaria confirma el cierre desde la interfaz

-- 10. Capacitación ----------------------------------------------------------
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_admin') \gset ctx_
SELECT api.fn_publicar_contenido('¿Qué son los RAEE?', 'Qué se considera residuo electrónico, por qué no va a la basura común y cómo empezar en casa.', 'CONCEPTOS') AS v1 \gset
SELECT api.fn_publicar_contenido('Reciclaje de electrónicos', 'El recorrido de un lote desde el centro de acopio hasta el gestor autorizado.', 'RECICLAJE') AS v2 \gset
SELECT api.fn_publicar_contenido('Reduce, reutiliza y recicla', 'Las tres decisiones que alargan la vida útil de un equipo antes de desecharlo.', 'CONCEPTOS') AS v3 \gset
SELECT api.fn_publicar_contenido('Borra tus datos antes de donar', 'Por qué la red exige un certificado de borrado (RN-09) y cómo hacerlo en Windows, Android y macOS.', 'SEGURIDAD_DATOS') AS v7 \gset
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_tece1') \gset ctx_
SELECT api.fn_publicar_contenido('Cómo se evalúa una placa', 'Los criterios del técnico para clasificar un equipo como reutilizable, reparable, reciclable o no recuperable.', 'REPARACION') AS v4 \gset
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_gr1') \gset ctx_
SELECT api.fn_publicar_contenido('Cambia la pantalla de tu celular', 'Reparación paso a paso con herramientas básicas y cuidado de la batería.', 'REPARACION') AS v5 \gset
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_benef') \gset ctx_
SELECT api.fn_publicar_contenido('Computadoras para escuelas', 'Cómo un equipo reacondicionado llega a una escuela beneficiaria y qué evidencia se conserva.', 'COMUNIDAD') AS v6 \gset
SELECT api.fn_comentar(:'v4', 'Nos sirve para explicar a los docentes por qué algunos equipos no llegan.');
SELECT api.fn_reaccionar(:'v6');
SELECT api.fn_reaccionar(:'v7');
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_univ') \gset ctx_
SELECT api.fn_comentar(:'v1', 'No sabía que las baterías van aparte. Gracias.');
SELECT api.fn_comentar(:'v7', 'Con esto preparamos los equipos del laboratorio antes de la donación.');
SELECT api.fn_reaccionar(:'v1');
SELECT api.fn_reaccionar(:'v7');
SELECT api.fn_registrar_vista(:'v1');
SELECT api.fn_registrar_vista(:'v7');
COMMIT;
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_c1') \gset ctx_
SELECT api.fn_comentar(:'v4', 'Lo usamos para capacitar al personal del acopio.');
SELECT api.fn_comentar(:'v2', 'Muy claro el paso de la guía de remisión.');
SELECT api.fn_reaccionar(:'v2');
SELECT api.fn_reaccionar(:'v4');
SELECT api.fn_registrar_vista(:'v2');
SELECT api.fn_registrar_vista(:'v4');
COMMIT;

-- 11. Indicadores y alertas del periodo -------------------------------------
BEGIN;
SELECT api.fn_iniciar_contexto(:'u_coord', 'BATCH') \gset ctx_
SELECT ind.fn_calcular_indicadores(date_trunc('month', current_date)::date, current_date);
SELECT ind.fn_generar_alertas();
COMMIT;
