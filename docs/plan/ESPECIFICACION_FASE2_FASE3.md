# EcoRAEE Cloud — Especificación de cambios (Proyecto Integrador III)

Documento de trabajo. Lo redacta el arquitecto (revisión de la Parte II y del enunciado) y lo implementa el equipo de
desarrollo por tareas. Cada tarea termina con pruebas que pasan y un resumen de lo cambiado.

## Reglas generales (aplican a todas las tareas)

- **No romper lo que existe.** Los 84 casos de `database/06_pruebas.sql` y las pruebas de `backend/tests` deben seguir pasando.
- **Las reglas de negocio viven en PostgreSQL** (ADR-005): toda escritura nueva va por una función `api.fn_*` `SECURITY DEFINER`,
  toda lectura por una vista `api.v1_*` con `security_invoker`. La API solo autentica, llama y traduce errores.
  Errores de negocio con `RAISE EXCEPTION ... USING ERRCODE = 'EC4xx'` (ya mapeados en `backend/app/errores.py`).
- **Cambios de base en scripts nuevos numerados** (`database/17_*.sql`, `18_*.sql`…), idempotentes cuando sea posible, y
  registrados en los tres lugares que recrean la base: `database/docker-init.sh`, `database/cargar_demo.sh` y
  `database/aplicar_cambios.sql` (este último con su `\if :faltaNN` como los demás).
- **Permisos:** los logins `ecoraee_api_svc` y `ecoraee_mcp_svc` no tienen INSERT/UPDATE directos; da `GRANT EXECUTE`/`SELECT`
  a los roles que ya usan los scripts 10–16 (`ecoraee_lectura`, etc.). Revisa cómo lo hace `14_dispositivos.sql`.
- **Auditoría:** toda tabla nueva con datos de negocio se engancha al mismo mecanismo de auditoría que usan las tablas de `trz`/`cat`.
- **Diccionario de datos:** documenta tablas y columnas nuevas igual que `04_seguridad_indices_diccionario.sql`.
- **Idioma:** código, mensajes y comentarios en español, con el mismo estilo del proyecto.
- **Sin secretos en el código.** Todo valor configurable entra por variable de entorno (`backend/app/config.py`).

---

## TAREA 1 — Base de datos y API: catálogo, número de serie, imágenes, regla de 1 día, almacén desacoplado

### 1.1 Catálogo de productos por categoría (`cat.modelo_equipo`)

El catálogo de productos es la tabla existente `cat.modelo_equipo` (marca + categoría + nombre).

- Script `database/17_catalogo_serie_imagenes.sql`:
  - Añadir a `cat.modelo_equipo`: `uid uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE`, `creado_en timestamptz NOT NULL DEFAULT now()`,
    `creado_por bigint REFERENCES seg.usuario(id)`, `editable_hasta timestamptz NOT NULL DEFAULT now() + interval '24 hours'`,
    `actualizado_en timestamptz`, `imagen_clave text` (clave en el almacén de la foto del modelo).
    Los modelos semilla existentes quedan con `editable_hasta = creado_en` (ya bloqueados).
  - Vista `api.v1_modelo_equipo`: uid, nombre, marca (código y nombre), categoría (código y nombre), anio_lanzamiento, peso_kg,
    activo, creado_en, creado_por (alias), editable_hasta, `editable` (boolean = now() < editable_hasta),
    `segundos_restantes` (≥ 0), tiene_imagen.
  - `api.fn_crear_modelo(p_categoria text, p_marca text, p_nombre text, p_anio int, p_peso numeric) RETURNS uuid`:
    exige permiso `CATALOGO.ADMINISTRAR` **o** `RED.GESTIONAR` (administrador o coordinador). La categoría debe ser hoja activa.
  - `api.fn_actualizar_modelo(p_modelo uuid, p_nombre text, p_anio int, p_peso numeric, p_activo boolean)`:
    mismos permisos. **Regla de 1 día:** si `now() >= editable_hasta` → `RAISE EXCEPTION 'El catálogo … está bloqueado desde …'
    USING ERRCODE = 'EC409'`. La comprobación se hace con la fila bloqueada (`FOR UPDATE`) y con la hora del servidor de base de
    datos, nunca con una hora enviada por el cliente.
  - `api.fn_reabrir_modelo(p_modelo uuid, p_motivo text)`: solo `CATALOGO.ADMINISTRAR`; motivo de 5 a 300 caracteres;
    pone `editable_hasta = now() + 24 h` y deja rastro en auditoría con el motivo.
  - Las horas se guardan en UTC (`timestamptz`); la zona de presentación es `America/Guayaquil` (la resuelve el frontend).
- Registro y corrección de dispositivos (`api.fn_registrar_dispositivo` y `api.fn_actualizar_dispositivo`): aceptar un modelo
  del catálogo por **uid** (`p_modelo_uid uuid`, nuevo parámetro opcional) y validar coherencia:
  el modelo debe pertenecer a la **misma categoría** del equipo (y a la misma marca si se indicó) → si no, `EC422`.
  Si viene `p_modelo_uid`, la marca del equipo se toma del modelo.
- **Corregir el error actual:** hoy, si `p_modelo` (texto) no coincide exactamente con un modelo del catálogo, el dato se pierde
  sin aviso. Añadir columna `trz.dispositivo.modelo_libre varchar(120)` y guardar ahí el texto cuando no se elige del catálogo
  («Otro modelo»). La vista `api.v1_dispositivo` y `api.v1_objeto_operativo` deben devolver
  `coalesce(nombre del modelo del catálogo, modelo_libre)` como `modelo` y además `modelo_uid` y `modelo_en_catalogo` (boolean).
- API (nuevo router `backend/app/rutas/catalogo.py`, prefijo `/catalogo`):
  - `GET /catalogo/modelos?categoria=&marca=&q=&incluir_inactivos=` → lista desde la vista.
  - `POST /catalogo/modelos` (201) · `PUT /catalogo/modelos/{uid}` · `POST /catalogo/modelos/{uid}/reabrir`.
  - `PUT /catalogo/modelos/{uid}/imagen` y `GET /catalogo/modelos/{uid}/imagen` (ver 1.3).
  - `DispositivoIn`/`DispositivoUpd` aceptan `modelo_uid` opcional además de `modelo` (texto libre).

### 1.2 Número de serie

- Normalización en la base (no solo en la API): `upper(btrim(...))`; cadena vacía → NULL.
- Formato: `^[A-Z0-9][A-Z0-9./-]{3,39}$` (4 a 40 caracteres: letras, números, punto, guion y barra). Si no cumple → `EC422`
  con un mensaje claro que diga el formato.
- **Unicidad en todo el ecosistema**, no solo por marca: índice único sobre
  `(ecosistema del objeto, numero_serie)` donde `numero_serie IS NOT NULL` (puede requerir una columna o un trigger, porque el
  ecosistema está en `trz.objeto_trazable`; elige la solución más limpia y justifícala en un comentario). Si se repite →
  error 409 con mensaje «Ya existe un equipo con el número de serie X (código Y)». Los equipos ANULADO no cuentan para la unicidad.
- **Obligatorio** cuando el equipo `contiene_almacenamiento` (RN-09 depende de identificarlo) → `EC422` si falta.
- Migración: el script normaliza los números de serie existentes; si algún dato demo no cumple el formato o queda duplicado,
  corrígelo en el propio script (son datos sintéticos) y revisa también `12_datos_demo.sql`.
- Búsqueda: `GET /objetos` busca también por número de serie en `q` y acepta filtro exacto `serie=`.
  `GET /objetos/serie/{serie}` devuelve el equipo (o 404). `GET /objetos/serie-disponible?serie=&excluir=<uid>` devuelve
  `{disponible, valida, normalizada, mensaje}` para validar en vivo desde el formulario.
- `v1_objeto_operativo` expone `numero_serie` para mostrarlo en el listado.

### 1.3 Imágenes de equipos y de modelos (almacén desacoplado, listo para S3)

- **Refactor de `backend/app/almacen.py`** a una abstracción con dos implementaciones intercambiables:
  `AlmacenLocal` y `AlmacenS3`, que cumplen una misma interfaz (`url_subida`, `url_descarga`, `verificar_objeto`, `eliminar`).
  `almacen.actual()` elige según `ALMACEN_MODO`. Ningún router importa `boto3` ni conoce rutas de disco.
  `AlmacenS3` acepta `AWS_ENDPOINT_URL` opcional (para probar con MinIO/LocalStack) y usa las credenciales del rol de la
  instancia (nunca claves en variables). La base guarda **solo bucket + clave relativa**, nunca URLs.
- Formatos de imagen: JPEG, PNG y **WEBP**; máximo 10 MB por imagen. Añadir `image/webp` donde corresponda (`EXT`, catálogo
  `cat.tipo_evidencia` del tipo de foto, verificación EXIF con Pillow, `MIME_IMAGEN` del frontend en la tarea 2).
- **Fotos del equipo:** nuevo tipo de evidencia `FOTO_EQUIPO` (o reutiliza el tipo de foto existente si encaja; revisa
  `05_semillas.sql`) asociado al objeto. Máximo **5 fotos por equipo** (regla en la base, `EC422`).
  - `GET /objetos/{codigo}/fotos` → lista con `uid, mime, tamano, subido_en, subido_por, url` (URL de descarga temporal, 5 min).
  - El registro de la foto reutiliza el flujo de evidencias (`POST /evidencias/subida` + `POST /evidencias` con `objeto`).
  - Respetar RN-07: solo roles con acceso al objeto ven sus fotos; la descarga queda en bitácora como hoy.
- **Foto del modelo del catálogo:** `PUT /catalogo/modelos/{uid}/imagen` recibe `{clave, sha256, mime, tamano}` de una subida
  previa (pedida con `POST /catalogo/modelos/{uid}/imagen/subida`) y guarda `imagen_clave`. Cambiar la imagen también
  respeta la regla de 1 día. `GET …/imagen` devuelve una URL temporal.

### 1.4 Seguridad y configuración

- CORS (`backend/app/main.py`): permitir `DELETE` y `OPTIONS` además de GET/POST/PUT (hoy anular un equipo falla entre orígenes).
- Mantener `CORS_ORIGENES` configurable por entorno.

### 1.5 Pruebas (obligatorias)

Añade a `backend/tests/test_api.py` (o un archivo nuevo `test_fase2.py`) pruebas para:
- crear modelo como coordinador; un generador no puede (403);
- registrar equipo con un modelo de **otra categoría** → 422; con modelo correcto → OK y la ficha muestra el modelo;
- registrar con modelo de texto libre → se guarda en `modelo_libre` y se ve en la ficha (regresión del error);
- serie: normalización, formato inválido (422), duplicado (409), obligatoria con almacenamiento (422), búsqueda por serie,
  endpoint de disponibilidad;
- regla de 1 día: editar un modelo recién creado funciona; forzar `editable_hasta` al pasado (con un UPDATE como
  `ecoraee_admin` dentro de la prueba, igual que hace la suite para otros casos) → editar devuelve 409; reabrir como
  admin → vuelve a ser editable; reabrir como coordinador → 403;
- fotos: subir WEBP/PNG, sexta foto → 422, listar fotos con URL.
Añade casos equivalentes en `database/06_pruebas.sql` solo si es sencillo; si no, deja anotado por qué.

---

## TAREA 2 — Frontend, gráficos interactivos y modelo de predicción

### 2.1 Predicción (módulo aislado)

- `backend/app/prediccion.py`: **Holt** (suavizado exponencial doble) en Python puro, sin dependencias nuevas obligatorias.
  Ajusta alfa y beta por búsqueda en rejilla minimizando el error de validación (últimas 4 semanas), devuelve pronóstico de
  N semanas con banda de confianza del 80 % (a partir de la desviación de los residuos) y el MAPE del backtest.
  Pruebas unitarias en `backend/tests/test_prediccion.py` con series conocidas (constante, tendencia lineal, serie corta).
- Datos: script `database/18_historial_recoleccion.sql` con la tabla `ind.historial_recoleccion_semanal(semana date,
  categoria_id, equipos int, peso_kg numeric, sintetico boolean)` con **52 semanas sintéticas** por categoría principal
  (tendencia leve + estacionalidad suave + ruido determinista, sin `random()` para que sea reproducible), más la vista
  `api.v1_serie_recoleccion` que une ese historial con los registros reales agregados por semana desde `trz`.
- `GET /api/v1/prediccion/recoleccion?categoria=&semanas=8&medida=equipos|peso` → `{disponible, metodo, parametros,
  historia[], pronostico[{semana, valor, inferior, superior}], mape, nota}`.
  **Aislamiento:** si algo falla devuelve 200 con `disponible: false` y un mensaje; nunca afecta al resto de la API.
  Router propio `rutas/prediccion.py`, permiso de lectura para coordinador, comité, auditor y administrador.

### 2.2 Gráficos interactivos (Apache ECharts)

- Añadir `echarts` (versión estable fija en `package.json`) con un componente `shared/ui/Chart.jsx` que:
  importa solo los módulos usados (tree-shaking, `echarts/core`), se redimensiona con `ResizeObserver`, respeta el tema
  claro/oscuro del proyecto (tokens de `shared/styles/tokens.css`), usa `notMerge:false` y `lazyUpdate` para transiciones
  suaves y se destruye al desmontar.
- Dashboard (`features/dashboard`): reemplazar las barras CSS por gráficos ECharts con tooltips detallados:
  equipos por estado (barras, clic en una barra → abre `/app/objetos?estado=X`), por clasificación (dona),
  y un panel nuevo **«Proyección de recolección»** (línea histórica + pronóstico punteado + banda de confianza) con filtros de
  categoría, horizonte (4/8/12 semanas) y medida (equipos/kg). Mostrar el MAPE en lenguaje claro.
- Mantener las animaciones existentes sin lag: nada de recrear el gráfico en cada render.

### 2.3 Pantallas de la tarea 1

- **Registrar/editar equipo** (`RegistrarDialog.jsx`, `AccionDialog.jsx` modo EDITAR): al elegir la categoría, el campo Modelo
  pasa a ser un selector con los modelos de esa categoría (filtrados también por marca si se eligió), con la opción
  «Otro modelo (escribir)». Al elegir un modelo se fija su marca. Número de serie con validación en vivo
  (`/objetos/serie-disponible`, con retardo de 400 ms), mayúsculas automáticas y obligatorio si «Tiene almacenamiento».
- **Listado** (`ObjetosPage.jsx`): columna/filtro por número de serie y buscador que lo incluya.
- **Ficha del equipo** (`ObjetoPage.jsx`): galería de fotos (miniaturas, visor ampliado, subir hasta 5 con progreso,
  usando `subirEvidencia` existente, que ya limpia EXIF/GPS). Aceptar `image/webp`.
- **Nueva página «Catálogo»** (`features/catalogo`, ruta `/app/catalogo`, visible para quien tenga `CATALOGO.ADMINISTRAR` o
  `RED.GESTIONAR`; solo lectura para el resto): tabla de modelos por categoría, crear modelo, editar, subir foto del modelo,
  y una **insignia de estado**: «Editable · quedan 13 h 20 min» (cuenta regresiva) o «Bloqueado desde 22/11/2026 14:05»
  (hora de Ecuador). El botón Editar se deshabilita cuando está bloqueado, pero la API sigue siendo la que decide (si
  responde 409, mostrar el mensaje). Botón «Reabrir 24 h» solo para administrador, pide motivo.
- `shared/api/index.js`: funciones para todo lo nuevo.

### 2.4 Construcción del frontend

- `frontend/Dockerfile`: compilación en varias etapas (node:22-alpine → nginx), porque `dist/` ya no está en el repositorio.
- `frontend/.dockerignore`: hoy excluye `src`, lo que rompe la compilación en Docker; corrígelo.
- `npm run build` debe terminar sin errores ni advertencias nuevas.

---

## TAREA 3 — Preparación para AWS (Proyecto Integrador III)

Arquitectura objetivo (corrige los hallazgos de la revisión de los diagramas de la Parte II):
CloudFront → S3 frontend (privado, OAC) y `/api/*` → ALB (subredes públicas en **2 AZ**) → EC2 en subredes privadas de app
(Auto Scaling Group, mínimo 1, máximo 2) → RDS PostgreSQL 16 en subredes privadas de datos (grupo de subredes en 2 AZ,
Multi-AZ como parámetro, desactivado por costo en el laboratorio). Evidencias y contenidos en buckets S3 privados con
URL prefirmadas (el navegador sube directo a S3; por eso el bucket necesita CORS y no puede restringirse solo al endpoint de VPC).

- `infrastructure/cloudformation/` con plantillas anidadas o separadas y parámetros por entorno:
  `01-red.yaml` (VPC, 2 subredes públicas, 2 privadas app, 2 privadas datos, IGW, NAT opcional por parámetro,
  endpoint gateway S3, endpoints de interfaz opcionales para ssm/ssmmessages/ec2messages/secretsmanager/logs),
  `02-seguridad.yaml` (grupos de seguridad ALB→EC2:8000→RDS:5432, rol e instance profile de EC2 con políticas de mínimo
  privilegio; parámetro `UsarLabRole` para AWS Academy, donde no se pueden crear roles), `03-datos.yaml` (RDS con secreto en
  Secrets Manager generado por CloudFormation, cifrado, backups 7 días, logs de PostgreSQL a CloudWatch),
  `04-almacenamiento.yaml` (bucket frontend con OAC, buckets de evidencias y contenidos con bloqueo de acceso público,
  cifrado SSE-S3, versionado, CORS para PUT prefirmado, ciclo de vida), `05-computo.yaml` (Launch Template con user-data
  que instala Docker, descarga el código, ejecuta la API con las variables correctas y el agente de CloudWatch; ALB,
  target group con health check `/api/v1/salud`, ASG), `06-cdn.yaml` (CloudFront con dos orígenes),
  `07-observabilidad.yaml` (grupos de logs con retención, alarmas: 5xx del ALB, CPU EC2, CPU/almacenamiento/conexiones RDS,
  hosts no saludables; tópico SNS para alarmas; CloudTrail con bucket de logs; AWS Budgets con alerta al 80 %).
  Etiquetas comunes `Proyecto=EcoRAEE`, `Entorno`, `Responsable` en todo.
  Además `parametros/lab.json` y un `README.md` con el orden de despliegue y los comandos `aws cloudformation deploy`.
- `infrastructure/scripts/`: `publicar_frontend.ps1`/`.sh` (build + `aws s3 sync` + invalidación de CloudFront),
  `migrar_base.sh` (ejecuta los scripts 01–18 contra RDS en el orden de `docker-init.sh`, leyendo el secreto de Secrets Manager;
  y la opción de volcar los datos locales con `pg_dump --data-only` e importarlos), `ec2_user_data.sh`, `cloudwatch-agent.json`.
- `infrastructure/iam/`: políticas JSON de mínimo privilegio que corresponden al diagrama de IAM de la Parte II
  (grupos InfraAdmins, DBAdmins, AppAdmins, Developers, Monitoring; políticas propias; rol EC2 con S3 limitado a los dos
  buckets y prefijos, `secretsmanager:GetSecretValue` solo al secreto, logs/métricas y `AmazonSSMManagedInstanceCore`).
- Backend listo para EC2: `docker-compose.aws.yml` (solo api y mcp opcional, sin db ni web, con variables de AWS),
  `.env.aws.example` sin valores reales, manejo de `X-Forwarded-*` detrás del ALB (ya existe, verificar), log JSON a stdout.
- Gancho opcional de eventos: `backend/app/eventos.py` con publicación a **SNS** (cierre de trazabilidad y alertas críticas)
  activada solo si existe `SNS_TOPIC_ARN`; si no, no hace nada. Nunca bloquea la transacción (después del commit, con try/except).
- Documentación: `docs/aws/arquitectura.mmd` y `docs/aws/iam.mmd` (Mermaid, versión corregida de los diagramas),
  `docs/aws/GUIA_DESPLIEGUE.md` (paso a paso con evidencias que capturar por cada CP-10…CP-14),
  `docs/adr/` con los ADR citados en el README (ADR-003, 005, 006, 010, 011) y los nuevos (ADR-012 catálogo y regla de 1 día,
  ADR-013 almacén desacoplado, ADR-014 predicción, ADR-015 despliegue EC2), `docs/aws/costos.md` (estimación mensual).
- Crear `/innovation/README.md` y `/evidence/README.md` con la estructura de carpetas que exige el enunciado (sección 8.2)
  y el índice de evidencias por requisito (10.5), sin inventar resultados.
- Actualizar `README.md` raíz con la nueva estructura y cómo ejecutar todo.

---

## TAREA 4 — Verificación del correo al registrarse

- **Flujo:** `POST /auth/registro` crea la cuenta en estado `PENDIENTE_VERIFICACION` (sin poder iniciar sesión) y envía
  un código de 6 dígitos; `POST /auth/verificar {correo, codigo}` la activa con el rol base; `POST /auth/reenviar-codigo`
  manda uno nuevo. El login de una cuenta pendiente responde con un mensaje que lleva a la pantalla de verificación.
- **Reglas en la base** (script nuevo `database/20_verificacion_correo.sql`): el código se guarda con hash (bcrypt o
  SHA-256 con sal), vence a los 15 minutos, admite 5 intentos, el reenvío exige 60 s desde el anterior y un máximo de
  5 por hora; cada envío, intento y activación queda auditado. Las respuestas no revelan si un correo ya existe.
- **Envío desacoplado** (`backend/app/correo.py`, mismo patrón que el almacén): `CORREO_MODO=consola|smtp|ses`.
  El envío ocurre después del commit y un fallo de envío no deja la cuenta inconsistente (se puede reenviar).
  - Local y producción local: **Mailpit** en Docker (SMTP 1025, bandeja web en http://localhost:8025).
  - AWS: **Amazon SES** (`CORREO_MODO=ses`, remitente verificado, permiso `ses:SendEmail` solo para esa identidad en el
    rol de EC2) o SMTP genérico. Documentar el *sandbox* de SES y la limitación de Learner Lab.
- **Frontend:** paso «Verifica tu correo» tras registrarse (6 casillas o un campo numérico, reenviar con cuenta
  regresiva, mensajes claros) y acceso a esa pantalla desde el login si la cuenta está pendiente.
- **Plantilla del correo:** texto plano + HTML simple en español, sin enlaces de seguimiento ni datos innecesarios.
- **Pruebas:** registro → pendiente → login rechazado → código incorrecto (intentos) → código vencido → reenvío con
  límite → código correcto → login OK. Las cuentas sintéticas existentes siguen activas.
