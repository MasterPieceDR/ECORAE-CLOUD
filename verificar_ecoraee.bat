@echo off
cd /d "%~dp0"
(
echo == contenedores ==
docker compose ps --format "table {{.Service}}\t{{.Status}}"
echo == cambios en la base: scripts 13, 14 y 15 ==
docker compose exec -T db psql -U ecoraee_admin -d ecoraee -tAc "select to_regclass('seg.solicitud_rol'), to_regprocedure('api.fn_anular_objeto(uuid,text)'), to_regprocedure('api.fn_verificar_base()'), (select count(*) from seg.usuario)"
echo == salud de la API ==
curl -s http://localhost:8080/api/v1/salud
echo.
echo == rutas nuevas ==
curl -s http://localhost:8080/api/v1/verificacion/conexion
echo.
) > verificacion.txt 2>&1
