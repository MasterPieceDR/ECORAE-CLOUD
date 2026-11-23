# EcoRAEE Cloud — Proyecto Integrador (Grupo 7, UIDE)

Plataforma de trazabilidad de residuos de aparatos eléctricos y electrónicos (RAEE) para una red circular:
registro, recolección, evaluación técnica, transferencias por la red, tratamiento, asignación a beneficiarios y
cierre, con análisis de flujo máximo de la red, capacitación y un asistente MCP. **Todos los datos son sintéticos.**

```
/database   PostgreSQL 16: scripts 01–05 (base final), 10 (integración), 13 (editor de escenarios y solicitudes de rol),
            14 (actualizar y anular equipos), 15 (verificación de la base desde la API),
            11 (logins), 12 (datos demo), 06 (84 pruebas)
/math       Núcleo de flujo máximo (ecoraee_flujo.py) que usan el CLI y la API, y el CLI conectado a la base
/backend    API FastAPI (app/), servidor MCP (mcp_server/), pruebas de integración (tests/), Dockerfile
/frontend   React 19 + Vite, servido por nginx en Docker (en AWS: S3 + CloudFront)
/docs       Diccionario de datos, diagramas ER por dominio y resultados de las pruebas de la base
```

## 1. Levantar todo con un comando (recomendado)

Requiere Docker Desktop. En Windows basta con doble clic:

| Archivo | Qué hace |
|---|---|
| `iniciar_ecoraee.bat` | Construye y levanta todo (`docker compose up -d --build`) y abre la web |
| `actualizar_ecoraee.bat` | Tras recibir cambios: reconstruye la API y la web y aplica a la base solo lo que falte, **sin borrar datos** |
| `consultar_bd.bat` | Muestra directamente en PostgreSQL los últimos equipos, su historial y la auditoría (para demostrar la persistencia) |
| `verificar_ecoraee.bat` | Revisa contenedores, base y API y deja el resultado en `verificacion.txt` |
| `abrir_api.bat` | Abre la documentación interactiva de la API |
| `detener_ecoraee.bat` | Apaga los contenedores (los datos quedan en el volumen) |

O desde una terminal:

```bash
docker compose up --build
```

La construcción no necesita internet dentro de los contenedores: la web va ya compilada en `frontend/dist`
(`Dockerfile.compilar` la compila con Node si se prefiere) y las librerías de Python vienen en `backend/wheels`.

| Qué | Dónde |
|---|---|
| Aplicación web | http://localhost:8080 |
| Documentación de la API (OpenAPI) | http://localhost:8080/api/docs |
| Servidor MCP (Streamable HTTP) | http://localhost:8001/mcp |
| PostgreSQL | localhost:5432 · base `ecoraee` · usuario `ecoraee_admin` |

La primera vez la base se crea desde los scripts (RNF-09) y la API calcula el flujo de los cinco escenarios.
Para empezar de cero: `docker compose down -v` y de nuevo `docker compose up --build`.

Las contraseñas por defecto son solo para tu PC. Para cambiarlas, crea un archivo `.env` junto al compose:

```
API_DB_PASS=...
MCP_DB_PASS=...
DB_ADMIN_PASS=...
JWT_SECRETO=...
# ANTHROPIC_API_KEY=...   (opcional: activa el chat del asistente)
```

### Cuentas de demostración

En la pantalla de inicio de sesión hay un botón por rol. Todas usan la contraseña `EcoRAEE-2026` y el correo
`<alias>@ejemplo.invalid`, por ejemplo `coordinador@ejemplo.invalid`.

| Alias | Rol | Qué tiene pendiente en los datos demo |
|---|---|---|
| coordinador | Coordinador logístico (hereda operador) | Programar LOT-UNIV-02, despachar RTR-1007 y ESC-1005, confirmar BAT-1004 |
| gen.municipio | Generador | Solicitar la recolección de TAB-1008 |
| operador.c2 | Operador del acopio Sur | Recibir CEL-1012 |
| tecnico.e1 | Técnico evaluador del laboratorio | Evaluar CEL-1006 |
| tecnico.r1 / gestor.r1 | Técnico y gestor del taller | Certificado de borrado de LAP-1013 (RN-09) |
| gestor.k1 | Gestor de reciclaje | Registrar el tratamiento de IMP-1003 |
| gestor.d1 | Gestor de disposición | Confirmar la llegada de BAT-1004 |
| beneficiario | Entidad beneficiaria | Confirmar el destino final de LAP-1014 |
| admin · auditor · comite | Gobierno | Usuarios y roles · auditoría · escenarios y decisiones |

## 2. Sin Docker (desarrollo)

Necesitas PostgreSQL 16, Python 3.12+ y Node 22.

```bash
# Base de datos (PGHOST/PGUSER de un usuario administrador)
export API_DB_PASS=api_dev_pass MCP_DB_PASS=mcp_dev_pass
database/cargar_demo.sh                      # 01–05 + 10 + 11 + 12

# API
cd backend
pip install -r requirements-dev.txt
cp .env.example .env                         # ajusta DB_HOST y las claves DB_CLAVE_API / DB_CLAVE_MCP
python -m app.cli inicializar                # flujo de E0–E4 e indicadores
uvicorn app.main:app --port 8000
uvicorn mcp_server.server:app --port 8001    # opcional: servidor MCP para clientes externos

# Frontend (en otra terminal)
cd frontend
npm install
npm run dev                                  # http://localhost:5171 (reenvía /api a localhost:8000)
```

En Windows, ejecuta los `.sql` en el orden de `database/cargar_demo.sh` con `psql -f` (o desde DBeaver),
pasando `-v api_pass=... -v mcp_pass=...` al script 11.

## 3. Pruebas

| Capa | Comando | Resultado |
|---|---|---|
| Base de datos | `psql -d ecoraee -f database/06_pruebas.sql` (sobre una base 01–05 + 10, sin el 12) | 84/84 |
| Matemática | `python3 math/flujo_maximo.py` | E0 200 · E1 225 (3 cortes) · E2 200 · E3 175 (2 cortes) · E4 280 |
| API | `cd backend && pytest` (recrea la base desde los scripts) | 20/20 |
| Frontend | `npm run build` | compila sin errores |

Las pruebas de la API recorren el ciclo completo de un equipo por HTTP y los casos negativos del enunciado:
CP-01 (acceso por rol y RLS), CP-02, CP-03, CP-09 (flujo leído desde la base en los cinco escenarios),
RN-02, RN-03, RN-04, RN-07 (descarga con propósito), RN-09 (borrado antes de donar), RNF-10 (foto con GPS
rechazada), segregación de funciones y la gobernanza del asistente MCP (denegado, pendiente de confirmación,
bitácora). También prueban que el chat con Claude no escribe nada sin confirmación humana.

## 4. Cómo encaja cada parte

**Base de datos (ADR-005).** Toda escritura pasa por funciones `api.fn_*` que aplican RN-01…RN-09; las lecturas
pasan por vistas `api.v1_*` con RLS. La API usa el login `ecoraee_api_svc` (sin INSERT/UPDATE directos) y el
servidor MCP usa `ecoraee_mcp_svc`, que solo puede ejecutar lo registrado en `mcp.herramienta`.
Cada petición abre una transacción con `api.fn_iniciar_contexto(usuario, canal, request_id)`.

**Script 10 (nuevo):**
- la red real del capítulo de Discretas, con capacidad del laboratorio como nodo (E_in → E_out) y los cinco escenarios (ADR-010);
- el esquema `edu` de capacitación con auditoría y RLS (ADR-011);
- autenticación local con bcrypt en la base, autorregistro con rol base, resolución de usuarios de Cognito;
- vistas y funciones para la interfaz: catálogos, vista operativa del objeto, documentos, evidencias, red, auditoría, bitácora MCP y administración de roles.

**API.** Es delgada: no repite reglas, solo autentica, abre el contexto, llama al contrato y traduce errores
(`EC401/403/404/409/422` → HTTP). Además:
- calcula, para cada objeto, qué acciones puede hacer el usuario según su estado, ubicación y permisos;
- integra el módulo matemático (flujo, todos los cortes y registro con hash del dataset);
- firma URLs de subida y descarga del almacén.

**Script 13 (nuevo):** escenarios «qué pasaría si» (un borrador hereda de E0–E4 y se ajusta tocando el grafo; los
aprobados no se modifican) y solicitudes de rol (el usuario del autorregistro pide un rol y el administrador lo aprueba
con las mismas reglas de `api.fn_asignar_rol`: motivo, nadie se aprueba a sí mismo y separación de funciones).

**Script 14 (nuevo):** completa el CRUD de equipos. Mientras un equipo está *Registrado* (nadie lo ha recogido),
quien lo registró o su organización puede **corregir** sus datos (`PUT /objetos/dispositivos/{uid}`) o **anularlo**
(`DELETE /objetos/{uid}`). Anular es una eliminación lógica: pasa a ANULADO con un documento de ajuste y nada se borra,
porque en un sistema de trazabilidad todo debe poder auditarse. Después de la recolección los datos ya no se editan (RN-01).

**Script 15 (nuevo) y verificación:** `GET /api/v1/verificacion/conexion` (navegador → API → PostgreSQL, sin sesión),
`GET /api/v1/verificacion/base` (claves, restricciones, RLS, auditoría, volumen y 8 comprobaciones de consistencia) y
`GET /api/v1/verificacion/objetos/{codigo}` (las filas reales guardadas de un equipo, con su auditoría). En la web: menú
**Base de datos** y botón **Ver en la base de datos** en la ficha de cada equipo.

**Frontend.** No tiene reglas ni catálogos escritos a mano:
- los estados, roles, categorías y permisos los toma de la base;
- cada acción abre un formulario con el contexto que calcula la API;
- las fotos se limpian de EXIF/GPS en el navegador antes de subirlas.

**Asistente (ADR-006).** Hay tres puertas que usan el mismo ejecutor y la misma bitácora:
- el panel web en modo herramientas;
- el chat con Claude, si hay `ANTHROPIC_API_KEY`;
- el servidor MCP estándar.

Las escrituras exigen confirmación humana.

### Correspondencia con AWS

| Local (Docker) | AWS |
|---|---|
| `web` (nginx) | S3 + CloudFront (`/api/*` hacia el ALB) |
| `api`, `mcp` | ECS Fargate o EC2 detrás del ALB, en subredes privadas |
| `db` | Amazon RDS for PostgreSQL 16 (Multi-AZ por diseño) |
| Almacén local firmado (`ALMACEN_MODO=local`) | Buckets S3 privados con URL prefirmadas (`ALMACEN_MODO=s3`) |
| Variables de entorno | Secrets Manager (`DB_SECRET_ARN`, `JWT_SECRET_ARN`) |
| JWT local (`AUTH_MODO=local`) | Amazon Cognito (`AUTH_MODO=cognito`) |
| Logs JSON por línea | CloudWatch Logs Insights; `/api/v1/salud` para el health check del ALB |

### Conectar Claude Desktop u otro cliente MCP

Inicia sesión en la web y copia el token:

```js
sessionStorage.getItem('ecoraee:token')   // en la consola del navegador
```

Luego configura el cliente MCP con el servidor `http://localhost:8001/mcp` y la cabecera
`Authorization: Bearer <token>`. El cliente verá solo las herramientas de tu rol.
