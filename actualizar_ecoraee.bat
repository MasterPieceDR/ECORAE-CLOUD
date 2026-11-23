@echo off
title EcoRAEE Cloud - actualizar
cd /d "%~dp0"
echo Reconstruyendo la API y la web con los cambios (tus datos se conservan)...
docker compose up -d --build
if errorlevel 1 goto error
echo.
echo Aplicando a la base los cambios nuevos (solo si faltan)...
docker compose exec -T db psql -U ecoraee_admin -d ecoraee -v ON_ERROR_STOP=1 -f /database/aplicar_cambios.sql
if errorlevel 1 goto error
docker compose restart api mcp
echo.
echo Listo. Abriendo http://localhost:8080 ...
timeout /t 8 >nul
start http://localhost:8080
pause
exit /b 0
:error
echo.
echo Hubo un error. Revisa que Docker Desktop este abierto.
pause
exit /b 1
