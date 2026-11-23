# Verificación del correo — 23 de noviembre de 2026

## Archivos

Creados:
- `database/20_verificacion_correo.sql`: estado pendiente, datos y funciones de verificación, auditoría y permisos.
- `backend/app/correo.py`: transporte de correo.
- `backend/tests/test_verificacion_correo.py`: flujo y límites contra PostgreSQL.
- `docs/informes/2026-11-23_verificacion-correo.md`: este informe.

Modificados:
- `database/docker-init.sh`, `database/rebuild.sh`, `database/aplicar_cambios.sql`: incorporación de la migración. `cargar_demo.sh` la ejecuta a través de `rebuild.sh`.
- `backend/app/config.py`, `backend/app/rutas/auth.py`, `backend/tests/test_api.py`.
- `docker-compose.yml`, `docker-compose.produccion.yml`.
- `frontend/src/features/auth/LoginPage.jsx`, `frontend/src/features/auth/index.jsx`, `frontend/src/shared/api/index.js`.
- `infrastructure/cloudformation/02-seguridad.yaml`, `infrastructure/cloudformation/05-computo.yaml`, `infrastructure/iam/RuntimeDataPolicy.json`, `infrastructure/README.md`.

## Decisiones

El código de seis dígitos se genera con `secrets` y se guarda con bcrypt y sal individual. Dura 15 minutos; se admiten cinco intentos por código. Los envíos se serializan por usuario: al menos 60 segundos entre ellos y máximo cinco en una ventana móvil de una hora, contando el envío inicial. Los intentos fallidos se confirman en la base antes de responder. La tabla y los eventos de seguridad registran envíos, intentos y activación; las cuentas anteriores conservan su estado. El login identifica la cuenta pendiente solo tras comprobar la contraseña. Registro duplicado y reenvío devuelven mensajes genéricos.

Los modos son consola, SMTP (STARTTLS y autenticación opcionales) y SES v2 con credenciales ambientales del rol de instancia. Los envíos se ejecutan después del commit; un fallo queda registrado sin el código y permite solicitar otro. En consola el código se imprime como contenido del correo para desarrollo. Los dos Compose locales usan Mailpit `axllent/mailpit:v1.27.9`; su puerto web se publica solo en localhost. En AWS, la política SES limita el recurso a la identidad configurada. El remitente debe coincidir en ambas plantillas y estar verificado en SES.

## Verificaciones ejecutadas

- `docker pull axllent/mailpit:v1.27.9`: descarga correcta, digest `sha256:b004cc0672d0692f097ba8ab9e5956ae08eeafee3d0a6bf2ab239750101ac538`.
- `docker compose -f docker-compose.pruebas.yml run --rm pruebas`: **37 passed**, 28 advertencias de PyJWT sobre la longitud de la clave de pruebas. Una ejecución preliminar falló por una restricción de tipos de auditoría, corregida antes de la ejecución final.
- `docker compose -f docker-compose.pruebas.yml run --rm pruebas base`: **84 PASS**, cero fallos, salida 0. La primera ejecución preliminar coincidió con la recreación de la base por pytest y se interrumpió; se repitió en secuencia.
- `docker compose build web`: compilación de Vite correcta (1066 módulos), salida 0. Una primera compilación encontró un error JSX que se corrigió.
- `docker run --rm -v "C:/Users/diego/Desktop/EcoRAEE_Cloud/infrastructure:/infra" python:3.13-slim sh -c "pip install -q cfn-lint && cfn-lint --regions us-east-1 -- /infra/cloudformation/*.yaml"`: salida 0, sin salida de cfn-lint; pip mostró su advertencia de ejecución como root y aviso de actualización.
- `docker compose up -d --build`: salida 0; DB y API saludables, Mailpit y web levantados.
- `docker compose exec -T db psql -U ecoraee_admin -d ecoraee -v ON_ERROR_STOP=1 -f /database/aplicar_cambios.sql`: salida 0, migración 20 confirmada y «La base está al día».
- Prueba real con `curl.exe`, cuenta sintética aleatoria `prueba.fb34a95590@ejemplo.invalid`, organización `GEN-MUNI`:
  - `POST /api/v1/auth/registro`: HTTP 201, `{"estado":"PENDIENTE_VERIFICACION","mensaje":"Si corresponde, recibirás un código de verificación."}`.
  - `POST /api/v1/auth/login` antes de verificar: HTTP 403, `{"detail":"Verifica tu correo antes de iniciar sesión","codigo":"VERIFICACION_PENDIENTE",...}`.
  - `GET http://localhost:8025/api/v1/messages`: HTTP 200, un mensaje dirigido a la cuenta; `GET /api/v1/message/{ID}`: HTTP 200, código de seis dígitos extraído del texto. Se omite el código en este informe.
  - `POST /api/v1/auth/verificar`: HTTP 200, `{"mensaje":"Correo verificado. Ya puedes iniciar sesión."}`.
  - `POST /api/v1/auth/login` después: HTTP 200, `token_type=bearer`, perfil con `roles_efectivos=["USUARIO_BASE"]`; token omitido.
- `git diff --check`: sin errores de espacios; Git avisó de normalización CRLF/LF en varios archivos.

## Limitaciones

No se desplegó AWS ni se enviaron correos reales mediante SES o SMTP externo; dependen de identidad verificada, permisos y disponibilidad del laboratorio. No se ejecutó el entorno de producción local en paralelo, ya que ambos Compose publican Mailpit en el mismo puerto; se probó el desarrollo solicitado. El entorno de desarrollo queda levantado. No se hicieron commits.
