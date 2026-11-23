# Informe: versión de producción en local y endurecimiento de credenciales

**Fecha:** 2026-11-23 · **Rama:** `fase2-mejoras` · **Implementó:** Codex · **Revisó y verificó:** Claude (arquitectura)

## Motivo

Al revisar la pantalla de inicio de sesión se detectó que la clave de las cuentas de demostración (`EcoRAEE-2026`) la
asigna `database/10_integracion.sql` a **todos** los usuarios, y que las 15 cuentas sintéticas (incluido el
administrador) vienen en `05_semillas.sql`, no solo en los datos demo. La clave figura en el README de un repositorio
público. Con `DEMO=false` solo se ocultaba el panel; las cuentas seguían activas. Además, `python -m app.cli inicializar`
actuaba como el coordinador de demostración.

## Cambios

| Archivo | Cambio |
|---|---|
| `database/19_produccion.sql` | Función administrativa `preparar_produccion`: bloquea la credencial local de las cuentas sintéticas (o les asigna una clave de evaluación si se indica), crea o actualiza el administrador inicial y crea un usuario de sistema sin credencial para los procesos batch. Auditada; sin acceso desde la API |
| `backend/app/cli.py` | `inicializar` usa el usuario de sistema; nueva orden `preparar-produccion` con conexión administrativa por variables de entorno |
| `docker-compose.produccion.yml` | Réplica local de AWS: `ENTORNO=produccion`, `DEMO=false`, almacén `s3` contra **LocalStack 4.4**, web en el puerto 8090, base y API sin puertos publicados |
| `frontend/nginx.produccion.conf` | Emula CloudFront: `/api/*` a la API y cabeceras de seguridad (CSP, `X-Frame-Options: DENY`, `Referrer-Policy`, `Permissions-Policy`, sin versión del servidor) |
| `scripts/generar_env_produccion.(ps1\|sh)` | Generan `.env.produccion` con secretos aleatorios (no se suben a Git) |
| `scripts/localstack/` | Crea los buckets privados con CORS al arrancar LocalStack |
| `backend/app/almacen.py`, `config.py` | URL pública para firmar distinta de la interna (el navegador alcanza `localhost:4566`; la API habla con `localstack:4566`). En AWS real no se usa |
| `infrastructure/scripts/migrar_base.sh` | En RDS, después de los scripts 01–19, ejecuta la preparación de producción (sin cuentas demo salvo `CLAVE_DEMO`) |
| `iniciar_produccion_local.bat`, `detener_produccion_local.bat`, README | Arranque en Windows y documentación |
| `backend/tests/test_produccion.py` | Pruebas del bloqueo, la reactivación con clave de evaluación, el administrador nuevo y el cálculo batch |

**Cambio de decisión:** se empezó con MinIO, pero sus imágenes ya no se pueden descargar (Docker Hub: «repository does
not exist»; quay.io: 401). Se reemplazó por LocalStack, que además emula S3 de forma más parecida a AWS.

## Verificación independiente (Claude)

| Comprobación | Resultado |
|---|---|
| `docker compose -f docker-compose.produccion.yml up -d --build` | 4 servicios sanos (db, localstack, api, web) |
| `preparar-produccion` e `inicializar` | Correctos; 5 escenarios de flujo y 4 indicadores calculados |
| `GET /api/v1/salud` | 200 |
| `GET /api/v1/auth/demo` | `{"habilitado": false, "cuentas": []}` |
| Login de `admin@ejemplo.invalid` y `coordinador@ejemplo.invalid` con la clave pública | 401 |
| Login del administrador nuevo (clave de `.env.produccion`) | 200 con token |
| Registro de evidencia como administrador | 403 «Tu rol no tiene el permiso EVIDENCIA.CARGAR»: correcto por separación de funciones |
| Ciclo S3 con `operador.c1` en modo evaluación (clave aleatoria) | URL prefirmada a `localhost:4566` → PUT 200 → registro 201 (SHA-256 verificado contra S3) → descarga prefirmada 200 con archivo idéntico |
| Volver a bloquear las cuentas de evaluación | Login → 401 |
| Cabeceras de nginx | CSP, `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy`, `Permissions-Policy`; `Server: nginx` sin versión |

## Limitaciones conocidas

- **LocalStack no aplica políticas de acceso por defecto:** un GET sin firma al objeto respondió 200. En AWS real los
  buckets tienen `BlockPublicAccess` (plantilla `04-almacenamiento.yaml`) y ese GET devuelve 403; esa comprobación se
  hace en AWS como parte de CP-10.
- Los datos de LocalStack no persisten entre reinicios; la base sí. Es aceptable para pruebas locales.
- El HSTS está comentado en nginx porque la versión local usa HTTP; en AWS lo aplica CloudFront con HTTPS.
