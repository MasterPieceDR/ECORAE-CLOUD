@echo off
cd /d "%~dp0"
if not exist .env.produccion powershell -NoProfile -ExecutionPolicy Bypass -File scripts\generar_env_produccion.ps1
if errorlevel 1 exit /b 1
docker compose -f docker-compose.produccion.yml up -d --build
if errorlevel 1 exit /b 1
docker compose -f docker-compose.produccion.yml run --rm --no-deps --env-from-file .env.produccion -e DB_ADMIN_HOST=db -e DB_ADMIN_NOMBRE=ecoraee -e DB_ADMIN_USUARIO=ecoraee_admin api sh -c "DB_ADMIN_CLAVE=\"$POSTGRES_PASSWORD\" python -m app.cli preparar-produccion"
if errorlevel 1 exit /b 1
docker compose -f docker-compose.produccion.yml exec api python -m app.cli inicializar
if errorlevel 1 exit /b 1
start http://localhost:8090
