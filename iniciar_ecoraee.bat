@echo off
title EcoRAEE Cloud
cd /d "%~dp0"
set COMPOSE_BAKE=false
echo Construyendo e iniciando EcoRAEE Cloud (la primera vez tarda varios minutos)...
docker compose up -d --build
if errorlevel 1 (
  echo.
  echo Hubo un error. Revisa que Docker Desktop este abierto.
  pause
  exit /b 1
)
echo.
echo Listo. Abriendo http://localhost:8080 ...
timeout /t 5 >nul
start http://localhost:8080
echo Para ver el estado: docker compose ps
echo Para detener: doble clic en detener_ecoraee.bat
pause
