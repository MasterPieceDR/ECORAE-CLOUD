#!/bin/bash
# CP-05 / RNF-04: dos coordinadores despachan a la vez por una arista con capacidad para 1 unidad.
# Sin el bloqueo FOR UPDATE de red.fn_validar_capacidad ambos pasarían (actualización perdida).
export PGHOST=${PGHOST:-/srv/pg} PGUSER=${PGUSER:-postgres} PGDATABASE=${PGDATABASE:-ecoraee}
C1=00000000-0000-4000-8000-000000000003; CO=00000000-0000-4000-8000-000000000009
psql -q -v ON_ERROR_STOP=1 <<SQL >/dev/null
-- preparación: arco C1→C2 (consolidación) con capacidad 1 UND/semana y dos monitores en C1
INSERT INTO red.arista(ecosistema_id, nodo_origen_id, nodo_destino_id)
SELECT n1.ecosistema_id, n1.id, n2.id FROM red.nodo n1, red.nodo n2 WHERE n1.codigo='C1' AND n2.codigo='C2';
INSERT INTO red.capacidad_arista(arista_id, capacidad, unidad_id, periodo, fuente)
SELECT a.id, 1, (SELECT id FROM cat.unidad_medida WHERE codigo='UND'), 'SEMANA', 'Prueba de concurrencia'
  FROM red.arista a JOIN red.nodo n1 ON n1.id=a.nodo_origen_id AND n1.codigo='C1' JOIN red.nodo n2 ON n2.id=a.nodo_destino_id AND n2.codigo='C2';
BEGIN;
SELECT api.fn_iniciar_contexto('$C1');
SELECT api.fn_registrar_dispositivo('MON-C1','MONITOR',3,false,NULL,NULL,NULL,NULL,'{"pulgadas":19}',(SELECT uid FROM org.organizacion WHERE codigo='GEN-EMP'));
SELECT api.fn_registrar_dispositivo('MON-C2','MONITOR',3,false,NULL,NULL,NULL,NULL,'{"pulgadas":19}',(SELECT uid FROM org.organizacion WHERE codigo='GEN-EMP'));
SELECT api.fn_recibir(ARRAY[(SELECT uid FROM trz.objeto_trazable WHERE codigo='MON-C1'),(SELECT uid FROM trz.objeto_trazable WHERE codigo='MON-C2')],
       'C1','BOD-A', ARRAY[prueba.evid('FOTO_RECEPCION', NULL, 'image/jpeg')]);
COMMIT;
SQL
# Sesión A: despacha y mantiene la transacción abierta 3 s
( psql -qAt <<SQL
BEGIN;
SELECT api.fn_iniciar_contexto('$CO','API');
SELECT 'A despachó ' || api.fn_transferir(ARRAY[(SELECT uid FROM trz.objeto_trazable WHERE codigo='MON-C1')],'C1','C2');
SELECT pg_sleep(3), 'A confirma a las ' || to_char(clock_timestamp(),'HH24:MI:SS.MS');
COMMIT;
SQL
) > /tmp/claude-0/sesion_a.txt 2>&1 &
sleep 1
# Sesión B: llega 1 s después; queda bloqueada en la fila de capacidad hasta que A confirma
T0=$(date +%s.%N)
psql -qAt <<SQL > /tmp/claude-0/sesion_b.txt 2>&1
BEGIN;
SELECT api.fn_iniciar_contexto('$CO','API');
SELECT 'B despachó ' || api.fn_transferir(ARRAY[(SELECT uid FROM trz.objeto_trazable WHERE codigo='MON-C2')],'C1','C2');
COMMIT;
SQL
T1=$(date +%s.%N); wait
cat /tmp/claude-0/sesion_a.txt | grep -v '^$' | sed 's/^/  /'
grep -o 'ERROR:.*' /tmp/claude-0/sesion_b.txt | sed 's/^/  B → /'
printf "  B esperó %.1f s por el bloqueo de la capacidad\n" $(echo "$T1 - $T0" | bc)
psql -qAt -c "SELECT '  Traslados por C1→C2 confirmados: ' || count(*) FROM ops.transferencia t JOIN red.arista a ON a.id=t.arista_id
              JOIN red.nodo n1 ON n1.id=a.nodo_origen_id AND n1.codigo='C1' JOIN red.nodo n2 ON n2.id=a.nodo_destino_id AND n2.codigo='C2'"
