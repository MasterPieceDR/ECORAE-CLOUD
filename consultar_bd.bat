@echo off
title EcoRAEE Cloud - base de datos PostgreSQL
cd /d "%~dp0"
mode con: cols=170 lines=60
echo Consultando directamente la base de datos (contenedor db, PostgreSQL 16)...
docker compose exec -T db psql -U ecoraee_admin -d ecoraee -f /database/demo_consultas.sql
pause
