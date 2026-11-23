@echo off
cd /d "%~dp0"
docker compose exec -T db psql -U ecoraee_admin -d ecoraee -tA -F "|" -c "select 'usuario', alias, uid::text from seg.usuario where alias in ('coordinador','gen.municipio','admin','auditor') union all select 'equipo', o.codigo || ' ' || e.codigo, o.uid::text from (select * from trz.objeto_trazable order by registrado_en desc limit 6) o join cat.estado_trazabilidad e on e.id = o.estado_actual_id" > datos_video.txt 2>&1
