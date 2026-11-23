-- =====================================================================
-- EcoRAEE Cloud / CircuTrace — Base de datos transaccional final
-- Script 01: extensiones, esquemas, dominios y tablas
-- Motor: PostgreSQL 16 (Amazon RDS for PostgreSQL)
-- Grupo 7 · UIDE · Sistemas de Gestión de Bases de Datos
-- =====================================================================
SET client_min_messages = warning;

CREATE EXTENSION IF NOT EXISTS pgcrypto;     -- gen_random_uuid(), digest() para hashes de auditoría
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- restricciones de exclusión sobre vigencias (tstzrange/daterange)
CREATE EXTENSION IF NOT EXISTS ltree;        -- rutas jerárquicas en estructuras recursivas

-- ---------------------------------------------------------------------
-- Esquemas por dominio de datos (arquitectura de información de AE)
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS meta;  -- diccionario de datos vivo y glosario maestro
CREATE SCHEMA IF NOT EXISTS cat;   -- catálogos y reglas parametrizables
CREATE SCHEMA IF NOT EXISTS seg;   -- identidad, roles, permisos, ecosistemas (tenants)
CREATE SCHEMA IF NOT EXISTS org;   -- organizaciones, centros y ubicaciones
CREATE SCHEMA IF NOT EXISTS trz;   -- objetos trazables (dispositivo, lote) e historial
CREATE SCHEMA IF NOT EXISTS ops;   -- documentos operativos del ciclo de vida
CREATE SCHEMA IF NOT EXISTS inv;   -- kardex e inventario
CREATE SCHEMA IF NOT EXISTS evd;   -- evidencias (metadatos de objetos en S3)
CREATE SCHEMA IF NOT EXISTS red;   -- grafo, capacidades, escenarios y resultados de flujo
CREATE SCHEMA IF NOT EXISTS ind;   -- indicadores y alertas
CREATE SCHEMA IF NOT EXISTS gob;   -- gobierno: ADR, excepciones, riesgos (Comité/ARB)
CREATE SCHEMA IF NOT EXISTS aud;   -- auditoría técnica y de seguridad
CREATE SCHEMA IF NOT EXISTS mcp;   -- registro de herramientas/recursos MCP y su bitácora
CREATE SCHEMA IF NOT EXISTS integ; -- idempotencia y outbox de eventos
CREATE SCHEMA IF NOT EXISTS api;   -- contrato público: vistas v1 y funciones de comando

-- ---------------------------------------------------------------------
-- Dominios reutilizables
-- ---------------------------------------------------------------------
CREATE DOMAIN cat.d_codigo AS varchar(40)  CHECK (VALUE ~ '^[A-Z0-9][A-Z0-9_\-\.]*$');
CREATE DOMAIN cat.d_peso   AS numeric(12,3) CHECK (VALUE >= 0);
CREATE DOMAIN cat.d_cantidad AS numeric(14,3) CHECK (VALUE >= 0);
CREATE DOMAIN cat.d_sha256 AS char(64)     CHECK (VALUE ~ '^[0-9a-f]{64}$');

-- =====================================================================
-- META · Diccionario de datos y glosario maestro
-- =====================================================================
CREATE TABLE meta.dominio (
  id               smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  esquema          name        NOT NULL UNIQUE,
  nombre           varchar(80) NOT NULL,
  descripcion      text        NOT NULL,
  propietario_negocio varchar(80) NOT NULL,   -- dueño del dato (rol de negocio)
  custodio_tecnico varchar(80) NOT NULL       -- responsable técnico
);

CREATE TABLE meta.entidad (
  id               integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  dominio_id       smallint    NOT NULL REFERENCES meta.dominio(id),
  nombre_tabla     name        NOT NULL,
  nombre_negocio   varchar(120),
  descripcion      text,
  tipo_entidad     varchar(20) NOT NULL DEFAULT 'FUERTE'
    CHECK (tipo_entidad IN ('FUERTE','DEBIL','SUPERTIPO','SUBTIPO','ASOCIATIVA','CATALOGO','TEMPORAL','BITACORA','METADATO')),
  clasificacion_datos varchar(15) NOT NULL DEFAULT 'INTERNO'
    CHECK (clasificacion_datos IN ('PUBLICO','INTERNO','CONFIDENCIAL','RESTRINGIDO')),
  retencion        varchar(60),
  expuesta_mcp     boolean     NOT NULL DEFAULT false,
  sincronizada_en  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (dominio_id, nombre_tabla)
);

CREATE TABLE meta.atributo (
  id               integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  entidad_id       integer     NOT NULL REFERENCES meta.entidad(id) ON DELETE CASCADE,
  posicion         smallint    NOT NULL,
  nombre_columna   name        NOT NULL,
  tipo_dato        text        NOT NULL,
  nulo             boolean     NOT NULL,
  valor_defecto    text,
  es_pk            boolean     NOT NULL DEFAULT false,
  es_fk            boolean     NOT NULL DEFAULT false,
  referencia       text,
  descripcion      text,
  es_pii           boolean     NOT NULL DEFAULT false,
  es_derivado      boolean     NOT NULL DEFAULT false,
  UNIQUE (entidad_id, nombre_columna)
);

CREATE TABLE meta.termino_glosario (
  id               integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  termino          varchar(80) NOT NULL UNIQUE,
  definicion       text        NOT NULL,
  sinonimos        text[]      NOT NULL DEFAULT '{}',
  termino_ae       varchar(120),   -- Arquitectura Empresarial
  termino_md       varchar(120),   -- Matemáticas Discretas
  termino_bd       varchar(120),   -- Bases de Datos
  termino_nube     varchar(120),   -- Arquitectura en la Nube
  termino_inn      varchar(120),   -- Innovación en la Sociedad
  entidad_ref      text
);

CREATE TABLE meta.version_esquema (
  version          varchar(20) PRIMARY KEY,
  descripcion      text        NOT NULL,
  script           varchar(120) NOT NULL,
  checksum         cat.d_sha256,
  aplicada_en      timestamptz NOT NULL DEFAULT now(),
  aplicada_por     name        NOT NULL DEFAULT current_user
);

-- =====================================================================
-- CAT · Catálogos (diccionario maestro común a las 5 materias)
-- =====================================================================
CREATE TABLE cat.unidad_medida (
  id      smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo  cat.d_codigo NOT NULL UNIQUE,         -- UND, KG
  nombre  varchar(60)  NOT NULL,
  activo  boolean      NOT NULL DEFAULT true
);

CREATE TABLE cat.tipo_actor (                    -- tipos de actor organizacional (PDF 6.1)
  id      smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo  cat.d_codigo NOT NULL UNIQUE,
  nombre  varchar(80)  NOT NULL,
  descripcion text,
  activo  boolean      NOT NULL DEFAULT true
);

CREATE TABLE cat.actor_negocio (                 -- actores: 8 del enunciado + 3 de AE
  id      smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo  cat.d_codigo NOT NULL UNIQUE,
  nombre  varchar(80)  NOT NULL,
  responsabilidad text NOT NULL,
  activo  boolean      NOT NULL DEFAULT true
);

CREATE TABLE cat.estado_trazabilidad (
  id         smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo     cat.d_codigo NOT NULL UNIQUE,
  nombre     varchar(60)  NOT NULL,
  orden      smallint     NOT NULL,
  es_inicial boolean      NOT NULL DEFAULT false,
  es_final   boolean      NOT NULL DEFAULT false,
  descripcion text,
  activo     boolean      NOT NULL DEFAULT true
);

CREATE TABLE cat.transicion_estado (             -- relación T ⊆ S×S (recursiva sobre estado)
  id                    smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  estado_origen_id      smallint NOT NULL REFERENCES cat.estado_trazabilidad(id),
  estado_destino_id     smallint NOT NULL REFERENCES cat.estado_trazabilidad(id),
  permiso_requerido     cat.d_codigo NOT NULL,
  tipo_documento        varchar(20),
  requiere_evidencia    boolean  NOT NULL DEFAULT false,
  requiere_clasificacion boolean NOT NULL DEFAULT false,
  descripcion           text     NOT NULL,
  activo                boolean  NOT NULL DEFAULT true,
  UNIQUE (estado_origen_id, estado_destino_id),
  CHECK (estado_origen_id <> estado_destino_id)
);

CREATE TABLE cat.clasificacion_tecnica (         -- K = {Reutilizable, Reparable, Reciclable, NoRecuperable}
  id      smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo  cat.d_codigo NOT NULL UNIQUE,
  nombre  varchar(60)  NOT NULL,
  orden   smallint     NOT NULL,
  es_resultado_evaluacion boolean NOT NULL DEFAULT true,   -- PENDIENTE = false (solo inventario)
  descripcion text,
  activo  boolean      NOT NULL DEFAULT true
);

CREATE TABLE cat.tipo_destino (
  id      smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo  cat.d_codigo NOT NULL UNIQUE,
  nombre  varchar(80)  NOT NULL,
  es_final boolean     NOT NULL DEFAULT false,
  activo  boolean      NOT NULL DEFAULT true
);

CREATE TABLE cat.clasificacion_destino_permitido (  -- matriz clasificación × destino (RN-04)
  clasificacion_id smallint NOT NULL REFERENCES cat.clasificacion_tecnica(id),
  tipo_destino_id  smallint NOT NULL REFERENCES cat.tipo_destino(id),
  prioridad        smallint NOT NULL DEFAULT 1,
  PRIMARY KEY (clasificacion_id, tipo_destino_id)
);

CREATE TABLE cat.categoria_raee (                -- árbol recursivo de categorías
  id                 smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo             cat.d_codigo NOT NULL UNIQUE,
  nombre             varchar(80)  NOT NULL,
  categoria_padre_id smallint REFERENCES cat.categoria_raee(id),
  ruta               ltree,                       -- mantenida por trigger
  nivel              smallint,
  peso_referencial_kg cat.d_peso,
  vida_util_anios    smallint CHECK (vida_util_anios > 0),
  contiene_almacenamiento boolean NOT NULL DEFAULT false,
  esquema_atributos  jsonb NOT NULL DEFAULT '{}'::jsonb,   -- atributos esperados por categoría
  activo             boolean NOT NULL DEFAULT true,
  CHECK (categoria_padre_id IS NULL OR categoria_padre_id <> id)
);

CREATE TABLE cat.marca (
  id      integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo  cat.d_codigo NOT NULL UNIQUE,
  nombre  varchar(80)  NOT NULL,
  activo  boolean      NOT NULL DEFAULT true
);

CREATE TABLE cat.modelo_equipo (
  id           integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  marca_id     integer  NOT NULL REFERENCES cat.marca(id),
  categoria_id smallint NOT NULL REFERENCES cat.categoria_raee(id),
  nombre       varchar(120) NOT NULL,
  anio_lanzamiento smallint CHECK (anio_lanzamiento BETWEEN 1970 AND 2100),
  peso_kg      cat.d_peso,
  activo       boolean NOT NULL DEFAULT true,
  UNIQUE (marca_id, nombre)
);

CREATE TABLE cat.tipo_centro (
  id      smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo  cat.d_codigo NOT NULL UNIQUE,
  nombre  varchar(80)  NOT NULL,
  activo  boolean      NOT NULL DEFAULT true
);

CREATE TABLE cat.tipo_nodo (
  id         smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo     cat.d_codigo NOT NULL UNIQUE,
  nombre     varchar(80)  NOT NULL,
  prefijo    varchar(3)   NOT NULL UNIQUE,      -- G, C, E, R, K, D, B
  es_fuente  boolean      NOT NULL DEFAULT false,
  es_sumidero boolean     NOT NULL DEFAULT false,
  tipo_centro_id smallint REFERENCES cat.tipo_centro(id),
  tipo_destino_id smallint,                      -- destino circular que representa (FK abajo)
  activo     boolean      NOT NULL DEFAULT true
);

CREATE TABLE cat.arista_tipo_permitida (          -- arcos válidos entre tipos de nodo (coherencia T ↔ grafo)
  tipo_nodo_origen_id  smallint NOT NULL REFERENCES cat.tipo_nodo(id),
  tipo_nodo_destino_id smallint NOT NULL REFERENCES cat.tipo_nodo(id),
  requiere_excepcion   boolean  NOT NULL DEFAULT false,
  justificacion        text     NOT NULL,
  PRIMARY KEY (tipo_nodo_origen_id, tipo_nodo_destino_id)
);

CREATE TABLE cat.tipo_evidencia (
  id                 smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo             cat.d_codigo NOT NULL UNIQUE,
  nombre             varchar(80)  NOT NULL,
  nivel_acceso       varchar(15)  NOT NULL DEFAULT 'INTERNO'
    CHECK (nivel_acceso IN ('PUBLICO','INTERNO','CONFIDENCIAL','RESTRINGIDO')),
  retencion_meses    smallint     NOT NULL DEFAULT 60,
  mime_permitidos    text[]       NOT NULL DEFAULT '{image/jpeg,image/png,application/pdf}',
  activo             boolean      NOT NULL DEFAULT true
);

CREATE TABLE cat.proposito_uso (                  -- finalidad explícita (RNF-10 / RN-07)
  id      smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo  cat.d_codigo NOT NULL UNIQUE,
  nombre  varchar(80)  NOT NULL,
  descripcion text     NOT NULL,
  activo  boolean      NOT NULL DEFAULT true
);

CREATE TABLE cat.tipo_tratamiento (
  id      smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo  cat.d_codigo NOT NULL UNIQUE,
  nombre  varchar(80)  NOT NULL,
  tipo_destino_id smallint NOT NULL REFERENCES cat.tipo_destino(id),
  activo  boolean      NOT NULL DEFAULT true
);

CREATE TABLE cat.material (
  id      smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo  cat.d_codigo NOT NULL UNIQUE,
  nombre  varchar(80)  NOT NULL,
  es_peligroso boolean NOT NULL DEFAULT false,
  activo  boolean      NOT NULL DEFAULT true
);

CREATE TABLE cat.criterio_evaluacion (
  id            smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo        cat.d_codigo NOT NULL UNIQUE,
  nombre        varchar(120) NOT NULL,
  tipo_valor    varchar(10)  NOT NULL CHECK (tipo_valor IN ('BOOLEANO','NUMERO','TEXTO')),
  categoria_id  smallint REFERENCES cat.categoria_raee(id),   -- NULL = aplica a todas
  obligatorio   boolean NOT NULL DEFAULT true,
  activo        boolean NOT NULL DEFAULT true
);

CREATE TABLE cat.motivo (
  id      smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo  cat.d_codigo NOT NULL UNIQUE,
  ambito  varchar(20)  NOT NULL CHECK (ambito IN ('ANULACION','RECHAZO','AJUSTE','REEVALUACION','EXCEPCION')),
  nombre  varchar(120) NOT NULL,
  activo  boolean      NOT NULL DEFAULT true
);

CREATE TABLE cat.parametro_sistema (              -- parámetros con historial de vigencia
  id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo      cat.d_codigo NOT NULL,
  valor       jsonb        NOT NULL,
  descripcion text         NOT NULL,
  vigencia    tstzrange    NOT NULL DEFAULT tstzrange(now(), NULL),
  EXCLUDE USING gist (codigo WITH =, vigencia WITH &&)
);

-- =====================================================================
-- SEG · Identidad, roles y permisos
-- =====================================================================
CREATE TABLE seg.ecosistema (                     -- tenant: red circular / municipio / consorcio
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  uid         uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  codigo      cat.d_codigo NOT NULL UNIQUE,
  nombre      varchar(120) NOT NULL,
  tipo        varchar(20)  NOT NULL CHECK (tipo IN ('UNIVERSIDAD','MUNICIPIO','CONSORCIO','RED_COMUNITARIA','EMPRESA')),
  zona_horaria varchar(40) NOT NULL DEFAULT 'America/Guayaquil',
  activo      boolean      NOT NULL DEFAULT true,
  creado_en   timestamptz  NOT NULL DEFAULT now()
);

CREATE TABLE seg.rol (                            -- RBAC jerárquico (recursivo)
  id           smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo       cat.d_codigo NOT NULL UNIQUE,
  nombre       varchar(80)  NOT NULL,
  descripcion  text         NOT NULL,
  rol_padre_id smallint REFERENCES seg.rol(id),   -- hereda permisos del padre
  es_servicio  boolean      NOT NULL DEFAULT false,  -- cuentas técnicas (API, MCP)
  activo       boolean      NOT NULL DEFAULT true,
  CHECK (rol_padre_id IS NULL OR rol_padre_id <> id)
);

CREATE TABLE seg.permiso (
  id          smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo      cat.d_codigo NOT NULL UNIQUE,      -- p. ej. EVALUACION.REGISTRAR
  recurso     varchar(40)  NOT NULL,
  accion      varchar(40)  NOT NULL,
  descripcion text         NOT NULL
);

CREATE TABLE seg.rol_permiso (
  rol_id     smallint NOT NULL REFERENCES seg.rol(id),
  permiso_id smallint NOT NULL REFERENCES seg.permiso(id),
  PRIMARY KEY (rol_id, permiso_id)
);

CREATE TABLE seg.segregacion_funciones (          -- pares de roles incompatibles (SoD)
  rol_a_id   smallint NOT NULL REFERENCES seg.rol(id),
  rol_b_id   smallint NOT NULL REFERENCES seg.rol(id),
  motivo     text     NOT NULL,
  PRIMARY KEY (rol_a_id, rol_b_id),
  CHECK (rol_a_id < rol_b_id)
);

CREATE TABLE seg.actor_rol_mapeo (                -- actor de AE → rol del sistema
  actor_negocio_id smallint NOT NULL REFERENCES cat.actor_negocio(id),
  rol_id           smallint NOT NULL REFERENCES seg.rol(id),
  observacion      text,
  PRIMARY KEY (actor_negocio_id, rol_id)
);

-- =====================================================================
-- ORG · Organizaciones, centros y ubicaciones
-- =====================================================================
CREATE TABLE org.organizacion (                   -- recursiva: matriz → sede/unidad
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  uid                uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  ecosistema_id      bigint NOT NULL REFERENCES seg.ecosistema(id),
  codigo             cat.d_codigo NOT NULL,
  nombre             varchar(160) NOT NULL,          -- sintético / seudónimo
  tipo_persona       varchar(25)  NOT NULL CHECK (tipo_persona IN ('JURIDICA','NATURAL_SEUDONIMIZADA','COLECTIVO')),
  sector             varchar(15)  NOT NULL CHECK (sector IN ('PUBLICO','PRIVADO','ACADEMICO','COMUNITARIO')),
  organizacion_padre_id bigint REFERENCES org.organizacion(id),
  canton             varchar(60),                    -- ubicación gruesa: minimización de datos
  parroquia          varchar(60),
  estado             varchar(10)  NOT NULL DEFAULT 'ACTIVA' CHECK (estado IN ('ACTIVA','SUSPENDIDA','BAJA')),
  creado_en          timestamptz NOT NULL DEFAULT now(),
  creado_por         bigint,
  actualizado_en     timestamptz NOT NULL DEFAULT now(),
  actualizado_por    bigint,
  version            integer     NOT NULL DEFAULT 1,
  eliminado_en       timestamptz,
  UNIQUE (ecosistema_id, codigo),
  CHECK (organizacion_padre_id IS NULL OR organizacion_padre_id <> id)
);

CREATE TABLE org.organizacion_actor (             -- una organización puede tener varios roles de actor
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  organizacion_id  bigint   NOT NULL REFERENCES org.organizacion(id),
  tipo_actor_id    smallint NOT NULL REFERENCES cat.tipo_actor(id),
  vigencia         daterange NOT NULL DEFAULT daterange(current_date, NULL),
  EXCLUDE USING gist (organizacion_id WITH =, tipo_actor_id WITH =, vigencia WITH &&)
);

CREATE TABLE org.centro (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  uid              uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  organizacion_id  bigint NOT NULL REFERENCES org.organizacion(id),
  codigo           cat.d_codigo NOT NULL,
  nombre           varchar(160) NOT NULL,
  canton           varchar(60),
  parroquia        varchar(60),
  horario          jsonb,
  estado           varchar(10) NOT NULL DEFAULT 'ACTIVO' CHECK (estado IN ('ACTIVO','SUSPENDIDO','CERRADO')),
  creado_en        timestamptz NOT NULL DEFAULT now(),
  creado_por       bigint,
  actualizado_en   timestamptz NOT NULL DEFAULT now(),
  actualizado_por  bigint,
  version          integer     NOT NULL DEFAULT 1,
  eliminado_en     timestamptz,
  UNIQUE (organizacion_id, codigo)
);

CREATE TABLE org.centro_funcion (                 -- un centro puede cumplir varias funciones
  centro_id      bigint   NOT NULL REFERENCES org.centro(id),
  tipo_centro_id smallint NOT NULL REFERENCES cat.tipo_centro(id),
  PRIMARY KEY (centro_id, tipo_centro_id)
);

CREATE TABLE org.capacidad_centro (               -- capacidad con historial de vigencia
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  centro_id        bigint   NOT NULL,
  tipo_centro_id   smallint NOT NULL,
  capacidad_almacen cat.d_cantidad NOT NULL,
  capacidad_proceso cat.d_cantidad NOT NULL,
  unidad_id        smallint NOT NULL REFERENCES cat.unidad_medida(id),
  periodo          varchar(10) NOT NULL CHECK (periodo IN ('DIA','SEMANA','MES')),
  vigencia         tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  FOREIGN KEY (centro_id, tipo_centro_id) REFERENCES org.centro_funcion(centro_id, tipo_centro_id),
  EXCLUDE USING gist (centro_id WITH =, tipo_centro_id WITH =, unidad_id WITH =, vigencia WITH &&)
);

CREATE TABLE org.ubicacion (                      -- recursiva: centro → bodega → zona → estante
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  centro_id          bigint NOT NULL REFERENCES org.centro(id),
  ubicacion_padre_id bigint REFERENCES org.ubicacion(id),
  codigo             cat.d_codigo NOT NULL,
  nombre             varchar(120) NOT NULL,
  tipo               varchar(12)  NOT NULL CHECK (tipo IN ('RAIZ','BODEGA','ZONA','ESTANTE','CUARENTENA','TRANSITO')),
  capacidad_kg       cat.d_peso,
  ruta               ltree,
  nivel              smallint,
  activo             boolean NOT NULL DEFAULT true,
  UNIQUE (centro_id, codigo),
  CHECK (ubicacion_padre_id IS NULL OR ubicacion_padre_id <> id)
);

-- usuarios dependen de organización; se crean después de org.organizacion
CREATE TABLE seg.usuario (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  uid              uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  ecosistema_id    bigint NOT NULL REFERENCES seg.ecosistema(id),
  organizacion_id  bigint NOT NULL REFERENCES org.organizacion(id),
  alias            varchar(60)  NOT NULL,          -- nombre visible, no identifica a la persona
  correo           varchar(160) NOT NULL,          -- sintético; PII clasificada
  proveedor_identidad varchar(10) NOT NULL DEFAULT 'COGNITO' CHECK (proveedor_identidad IN ('COGNITO','LOCAL')),
  sub_externo      varchar(120),                   -- id del IdP (Cognito sub)
  hash_credencial  text,                           -- solo si proveedor LOCAL (argon2/bcrypt)
  mfa_habilitado   boolean NOT NULL DEFAULT false,
  estado           varchar(10) NOT NULL DEFAULT 'ACTIVO' CHECK (estado IN ('ACTIVO','BLOQUEADO','BAJA')),
  ultimo_acceso_en timestamptz,
  creado_en        timestamptz NOT NULL DEFAULT now(),
  creado_por       bigint,
  actualizado_en   timestamptz NOT NULL DEFAULT now(),
  actualizado_por  bigint,
  version          integer NOT NULL DEFAULT 1,
  eliminado_en     timestamptz,
  UNIQUE (ecosistema_id, correo),
  UNIQUE (proveedor_identidad, sub_externo),
  CHECK (proveedor_identidad <> 'LOCAL' OR hash_credencial IS NOT NULL)
);

CREATE TABLE seg.usuario_rol (                    -- asignación con alcance y vigencia (histórico)
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario_id       bigint   NOT NULL REFERENCES seg.usuario(id),
  rol_id           smallint NOT NULL REFERENCES seg.rol(id),
  organizacion_id  bigint REFERENCES org.organizacion(id),  -- alcance opcional
  centro_id        bigint REFERENCES org.centro(id),        -- alcance opcional
  vigencia         tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  otorgado_por     bigint REFERENCES seg.usuario(id),
  motivo           text,
  EXCLUDE USING gist (usuario_id WITH =, rol_id WITH =, (coalesce(centro_id,0)) WITH =, vigencia WITH &&)
);

CREATE TABLE seg.habilitacion_tecnica (           -- técnico autorizado por categoría (RN-02)
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario_id    bigint   NOT NULL REFERENCES seg.usuario(id),
  categoria_id  smallint NOT NULL REFERENCES cat.categoria_raee(id),  -- incluye subcategorías
  vigencia      daterange NOT NULL,
  emitida_por   bigint REFERENCES seg.usuario(id),
  evidencia_ref text,
  EXCLUDE USING gist (usuario_id WITH =, categoria_id WITH =, vigencia WITH &&)
);

-- =====================================================================
-- TRZ · Objetos trazables (supertipo) y sus subtipos
-- =====================================================================
CREATE TABLE trz.objeto_trazable (
  id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  uid                    uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  ecosistema_id          bigint NOT NULL REFERENCES seg.ecosistema(id),
  codigo                 cat.d_codigo NOT NULL,                 -- RN-01: identificador único
  tipo_objeto            varchar(12) NOT NULL CHECK (tipo_objeto IN ('DISPOSITIVO','LOTE')),
  organizacion_origen_id bigint NOT NULL REFERENCES org.organizacion(id),  -- generador
  -- desnormalización controlada (cache mantenida por triggers; fuente: historiales)
  estado_actual_id       smallint NOT NULL REFERENCES cat.estado_trazabilidad(id),
  clasificacion_actual_id smallint REFERENCES cat.clasificacion_tecnica(id),
  ubicacion_actual_id    bigint REFERENCES org.ubicacion(id),
  registrado_en          timestamptz NOT NULL DEFAULT now(),
  registrado_por         bigint NOT NULL REFERENCES seg.usuario(id),
  cerrado_en             timestamptz,
  creado_en              timestamptz NOT NULL DEFAULT now(),
  creado_por             bigint,
  actualizado_en         timestamptz NOT NULL DEFAULT now(),
  actualizado_por        bigint,
  version                integer NOT NULL DEFAULT 1,
  UNIQUE (ecosistema_id, codigo),
  UNIQUE (id, tipo_objeto)                                    -- soporte de especialización disjunta
);

CREATE TABLE trz.dispositivo (                    -- subtipo; recursivo por desensamble
  objeto_id          bigint PRIMARY KEY,
  tipo_objeto        varchar(12) NOT NULL DEFAULT 'DISPOSITIVO' CHECK (tipo_objeto = 'DISPOSITIVO'),
  categoria_id       smallint NOT NULL REFERENCES cat.categoria_raee(id),
  marca_id           integer  REFERENCES cat.marca(id),
  modelo_id          integer  REFERENCES cat.modelo_equipo(id),
  numero_serie       varchar(80),
  anio_fabricacion   smallint CHECK (anio_fabricacion BETWEEN 1970 AND 2100),
  peso_kg            cat.d_peso NOT NULL,
  contiene_almacenamiento boolean NOT NULL DEFAULT false,   -- dispara RN-09 (borrado de datos)
  atributos          jsonb NOT NULL DEFAULT '{}'::jsonb,       -- extensibilidad por categoría
  componente_de_id   bigint REFERENCES trz.dispositivo(objeto_id), -- pieza extraída de otro equipo
  FOREIGN KEY (objeto_id, tipo_objeto) REFERENCES trz.objeto_trazable(id, tipo_objeto),
  CHECK (componente_de_id IS NULL OR componente_de_id <> objeto_id),
  UNIQUE (marca_id, numero_serie)
);

CREATE TABLE trz.lote (
  objeto_id         bigint PRIMARY KEY,
  tipo_objeto       varchar(12) NOT NULL DEFAULT 'LOTE' CHECK (tipo_objeto = 'LOTE'),
  proposito         varchar(15) NOT NULL CHECK (proposito IN ('RECEPCION','TRANSFERENCIA','TRATAMIENTO','ASIGNACION')),
  descripcion       text,
  peso_declarado_kg cat.d_peso,                        -- declarado ≠ derivado (v_lote_resumen)
  sellado_en        timestamptz,
  FOREIGN KEY (objeto_id, tipo_objeto) REFERENCES trz.objeto_trazable(id, tipo_objeto)
);

CREATE TABLE trz.lote_composicion (               -- pertenencia temporal (recursiva: lote dentro de lote)
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  lote_id    bigint NOT NULL REFERENCES trz.lote(objeto_id),
  objeto_id  bigint NOT NULL REFERENCES trz.objeto_trazable(id),
  vigencia   tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  agregado_por bigint REFERENCES seg.usuario(id),
  motivo     text,
  CHECK (lote_id <> objeto_id),
  -- "en un instante dado, cada objeto pertenece a lo sumo a un lote"
  EXCLUDE USING gist (objeto_id WITH =, vigencia WITH &&)
);

CREATE TABLE trz.lote_genealogia (                -- DAG de división / fusión de lotes
  lote_origen_id     bigint NOT NULL REFERENCES trz.lote(objeto_id),
  lote_resultante_id bigint NOT NULL REFERENCES trz.lote(objeto_id),
  operacion          varchar(10) NOT NULL CHECK (operacion IN ('DIVISION','FUSION','REEMPAQUE')),
  documento_id       bigint,                     -- FK agregada tras crear ops.documento_operativo
  ocurrido_en        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (lote_origen_id, lote_resultante_id),
  CHECK (lote_origen_id <> lote_resultante_id)
);

-- =====================================================================
-- OPS · Documentos operativos (supertipo) y subtipos
-- =====================================================================
CREATE TABLE ops.documento_operativo (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  uid                uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  ecosistema_id      bigint NOT NULL REFERENCES seg.ecosistema(id),
  tipo_documento     varchar(15) NOT NULL CHECK (tipo_documento IN
                     ('SOLICITUD','RECOLECCION','RECEPCION','EVALUACION','TRANSFERENCIA','TRATAMIENTO','ASIGNACION','CIERRE','AJUSTE')),
  numero             varchar(30) NOT NULL,
  centro_id          bigint REFERENCES org.centro(id),
  organizacion_id    bigint REFERENCES org.organizacion(id),
  responsable_id     bigint NOT NULL REFERENCES seg.usuario(id),
  documento_referencia_id bigint REFERENCES ops.documento_operativo(id),  -- cadena documental (recursiva)
  estado_documento   varchar(12) NOT NULL DEFAULT 'EMITIDO'
                     CHECK (estado_documento IN ('BORRADOR','EMITIDO','EN_CURSO','CERRADO','ANULADO')),
  fecha_documento    timestamptz NOT NULL DEFAULT now(),
  fecha_cierre       timestamptz,
  motivo_anulacion_id smallint REFERENCES cat.motivo(id),
  observacion        text,
  creado_en          timestamptz NOT NULL DEFAULT now(),
  creado_por         bigint,
  actualizado_en     timestamptz NOT NULL DEFAULT now(),
  actualizado_por    bigint,
  version            integer NOT NULL DEFAULT 1,
  UNIQUE (ecosistema_id, tipo_documento, numero),
  UNIQUE (id, tipo_documento),
  CHECK (documento_referencia_id IS NULL OR documento_referencia_id <> id),
  CHECK (estado_documento <> 'ANULADO' OR motivo_anulacion_id IS NOT NULL),
  CHECK (estado_documento <> 'CERRADO' OR fecha_cierre IS NOT NULL)
);

ALTER TABLE trz.lote_genealogia
  ADD CONSTRAINT fk_genealogia_documento FOREIGN KEY (documento_id) REFERENCES ops.documento_operativo(id);

CREATE TABLE ops.secuencia_documento (           -- numeración correlativa sin huecos por tipo y año
  ecosistema_id  bigint NOT NULL REFERENCES seg.ecosistema(id),
  tipo_documento varchar(15) NOT NULL,
  anio           smallint NOT NULL,
  ultimo         integer  NOT NULL DEFAULT 0 CHECK (ultimo >= 0),
  PRIMARY KEY (ecosistema_id, tipo_documento, anio)
);

CREATE TABLE ops.documento_item (                 -- líneas de documento: qué objetos involucra
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  documento_id bigint NOT NULL REFERENCES ops.documento_operativo(id),
  objeto_id    bigint NOT NULL REFERENCES trz.objeto_trazable(id),
  cantidad     integer NOT NULL DEFAULT 1 CHECK (cantidad > 0),
  peso_kg      cat.d_peso,
  resultado    varchar(15) CHECK (resultado IN ('CONFORME','OBSERVADO','RECHAZADO','PENDIENTE')),
  observacion  text,
  UNIQUE (documento_id, objeto_id)
);

CREATE TABLE ops.solicitud_recoleccion (
  documento_id       bigint PRIMARY KEY,
  tipo_documento     varchar(15) NOT NULL DEFAULT 'SOLICITUD' CHECK (tipo_documento = 'SOLICITUD'),
  organizacion_generador_id bigint NOT NULL REFERENCES org.organizacion(id),
  modalidad          varchar(16) NOT NULL CHECK (modalidad IN ('RECOLECCION','ENTREGA_DIRECTA')),
  centro_destino_id  bigint NOT NULL REFERENCES org.centro(id),
  fecha_preferida    date,
  sector_referencial varchar(120),               -- sin dirección exacta (minimización)
  cantidad_estimada  integer CHECK (cantidad_estimada > 0),
  peso_estimado_kg   cat.d_peso,
  FOREIGN KEY (documento_id, tipo_documento) REFERENCES ops.documento_operativo(id, tipo_documento)
);

CREATE TABLE ops.recoleccion (
  documento_id     bigint PRIMARY KEY,
  tipo_documento   varchar(15) NOT NULL DEFAULT 'RECOLECCION' CHECK (tipo_documento = 'RECOLECCION'),
  solicitud_id     bigint NOT NULL REFERENCES ops.solicitud_recoleccion(documento_id),
  arista_id        bigint,                   -- arco G→C usado (FK abajo); aplica RN-05
  unidades         integer  NOT NULL CHECK (unidades > 0),
  peso_kg          cat.d_peso NOT NULL,
  fecha_programada timestamptz NOT NULL,
  fecha_ejecucion  timestamptz,
  transportista_ref varchar(80),
  CHECK (fecha_ejecucion IS NULL OR fecha_ejecucion >= fecha_programada - interval '1 day'),
  FOREIGN KEY (documento_id, tipo_documento) REFERENCES ops.documento_operativo(id, tipo_documento)
);

CREATE TABLE ops.recepcion (
  documento_id     bigint PRIMARY KEY,
  tipo_documento   varchar(15) NOT NULL DEFAULT 'RECEPCION' CHECK (tipo_documento = 'RECEPCION'),
  centro_id        bigint NOT NULL REFERENCES org.centro(id),
  ubicacion_id     bigint NOT NULL REFERENCES org.ubicacion(id),
  solicitud_id     bigint REFERENCES ops.solicitud_recoleccion(documento_id), -- NULL = entrega sin solicitud
  recibido_en      timestamptz NOT NULL DEFAULT now(),
  conformidad      varchar(20) NOT NULL CHECK (conformidad IN ('CONFORME','CON_OBSERVACIONES','RECHAZADA')),
  peso_verificado_kg cat.d_peso,
  FOREIGN KEY (documento_id, tipo_documento) REFERENCES ops.documento_operativo(id, tipo_documento)
);

CREATE TABLE ops.evaluacion_tecnica (             -- una evaluación por dispositivo; inmutable
  documento_id      bigint PRIMARY KEY,
  tipo_documento    varchar(15) NOT NULL DEFAULT 'EVALUACION' CHECK (tipo_documento = 'EVALUACION'),
  objeto_id         bigint   NOT NULL REFERENCES trz.dispositivo(objeto_id),
  tecnico_id        bigint   NOT NULL REFERENCES seg.usuario(id),
  modalidad         varchar(16) NOT NULL DEFAULT 'COMPLETA' CHECK (modalidad IN ('COMPLETA','PRECLASIFICACION','REEVALUACION')),
  clasificacion_id  smallint NOT NULL REFERENCES cat.clasificacion_tecnica(id),
  tipo_destino_sugerido_id smallint NOT NULL REFERENCES cat.tipo_destino(id),
  funcional         boolean  NOT NULL,
  requiere_borrado_datos boolean NOT NULL DEFAULT false,
  puntaje           numeric(5,2) CHECK (puntaje BETWEEN 0 AND 100),
  evaluado_en       timestamptz NOT NULL DEFAULT now(),
  vigente           boolean  NOT NULL DEFAULT true,
  evaluacion_anterior_id bigint REFERENCES ops.evaluacion_tecnica(documento_id), -- cadena de reevaluaciones
  motivo_reevaluacion_id smallint REFERENCES cat.motivo(id),
  FOREIGN KEY (documento_id, tipo_documento) REFERENCES ops.documento_operativo(id, tipo_documento),
  FOREIGN KEY (clasificacion_id, tipo_destino_sugerido_id)
     REFERENCES cat.clasificacion_destino_permitido(clasificacion_id, tipo_destino_id)
);

CREATE TABLE ops.evaluacion_criterio (
  evaluacion_id bigint   NOT NULL REFERENCES ops.evaluacion_tecnica(documento_id),
  criterio_id   smallint NOT NULL REFERENCES cat.criterio_evaluacion(id),
  valor_booleano boolean,
  valor_numero  numeric(12,3),
  valor_texto   varchar(250),
  cumple        boolean NOT NULL,
  PRIMARY KEY (evaluacion_id, criterio_id),
  CHECK (num_nonnulls(valor_booleano, valor_numero, valor_texto) = 1)
);

CREATE TABLE ops.transferencia (
  documento_id     bigint PRIMARY KEY,
  tipo_documento   varchar(15) NOT NULL DEFAULT 'TRANSFERENCIA' CHECK (tipo_documento = 'TRANSFERENCIA'),
  arista_id        bigint NOT NULL,          -- FK a red.arista (se agrega más abajo)
  ubicacion_origen_id  bigint NOT NULL REFERENCES org.ubicacion(id),
  ubicacion_destino_id bigint REFERENCES org.ubicacion(id),  -- NULL si el destino es un beneficiario sin centro
  unidades         integer  NOT NULL CHECK (unidades > 0),
  peso_kg          cat.d_peso NOT NULL,
  estado_transferencia varchar(12) NOT NULL DEFAULT 'PROGRAMADA'
                   CHECK (estado_transferencia IN ('PROGRAMADA','DESPACHADA','RECIBIDA','CERRADA','ANULADA')),
  transportista_ref varchar(80),
  despachado_en    timestamptz,
  recibido_en      timestamptz,
  confirmado_por   bigint REFERENCES seg.usuario(id),
  CHECK (ubicacion_destino_id IS NULL OR ubicacion_destino_id <> ubicacion_origen_id),
  CHECK (recibido_en IS NULL OR despachado_en IS NULL OR recibido_en >= despachado_en),
  FOREIGN KEY (documento_id, tipo_documento) REFERENCES ops.documento_operativo(id, tipo_documento)
);

CREATE TABLE ops.tratamiento (
  documento_id       bigint PRIMARY KEY,
  tipo_documento     varchar(15) NOT NULL DEFAULT 'TRATAMIENTO' CHECK (tipo_documento = 'TRATAMIENTO'),
  objeto_id          bigint   NOT NULL REFERENCES trz.objeto_trazable(id),
  tipo_tratamiento_id smallint NOT NULL REFERENCES cat.tipo_tratamiento(id),
  gestor_organizacion_id bigint NOT NULL REFERENCES org.organizacion(id),
  iniciado_en        timestamptz NOT NULL DEFAULT now(),
  finalizado_en      timestamptz,
  resultado          varchar(10) CHECK (resultado IN ('EXITOSO','PARCIAL','FALLIDO')),
  observacion        text,
  CHECK (finalizado_en IS NULL OR finalizado_en >= iniciado_en),
  CHECK ((finalizado_en IS NULL) = (resultado IS NULL)),
  FOREIGN KEY (documento_id, tipo_documento) REFERENCES ops.documento_operativo(id, tipo_documento)
);

CREATE TABLE ops.tratamiento_fraccion (           -- materiales recuperados (indicador ambiental)
  tratamiento_id bigint   NOT NULL REFERENCES ops.tratamiento(documento_id),
  material_id    smallint NOT NULL REFERENCES cat.material(id),
  peso_kg        cat.d_peso NOT NULL,
  PRIMARY KEY (tratamiento_id, material_id)
);

CREATE TABLE ops.asignacion_beneficiario (
  documento_id       bigint PRIMARY KEY,
  tipo_documento     varchar(15) NOT NULL DEFAULT 'ASIGNACION' CHECK (tipo_documento = 'ASIGNACION'),
  objeto_id          bigint NOT NULL REFERENCES trz.dispositivo(objeto_id),
  beneficiario_id    bigint NOT NULL REFERENCES org.organizacion(id),
  criterio_asignacion text  NOT NULL,
  entregado_en       timestamptz,
  FOREIGN KEY (documento_id, tipo_documento) REFERENCES ops.documento_operativo(id, tipo_documento)
);

CREATE TABLE ops.cierre_trazabilidad (            -- RN-08
  documento_id         bigint PRIMARY KEY,
  tipo_documento       varchar(15) NOT NULL DEFAULT 'CIERRE' CHECK (tipo_documento = 'CIERRE'),
  objeto_id            bigint NOT NULL UNIQUE REFERENCES trz.objeto_trazable(id),
  tipo_destino_final_id smallint NOT NULL REFERENCES cat.tipo_destino(id),
  organizacion_destino_id bigint NOT NULL REFERENCES org.organizacion(id),
  fecha_confirmacion   timestamptz NOT NULL,
  confirmado_por       bigint NOT NULL REFERENCES seg.usuario(id),
  observacion          text,
  FOREIGN KEY (documento_id, tipo_documento) REFERENCES ops.documento_operativo(id, tipo_documento)
);

-- =====================================================================
-- TRZ · Historial de estados (particionado, inmutable)
-- =====================================================================
CREATE TABLE trz.historial_estado (
  id                 bigint GENERATED ALWAYS AS IDENTITY,
  ocurrido_en        timestamptz NOT NULL DEFAULT now(),
  objeto_id          bigint   NOT NULL REFERENCES trz.objeto_trazable(id),
  estado_origen_id   smallint REFERENCES cat.estado_trazabilidad(id),   -- NULL en el registro inicial
  estado_destino_id  smallint NOT NULL REFERENCES cat.estado_trazabilidad(id),
  transicion_id      smallint REFERENCES cat.transicion_estado(id),
  documento_id       bigint REFERENCES ops.documento_operativo(id),
  usuario_id         bigint   NOT NULL REFERENCES seg.usuario(id),
  canal              varchar(8) NOT NULL DEFAULT 'WEB' CHECK (canal IN ('WEB','API','MCP','BATCH')),
  observacion        text,
  PRIMARY KEY (id, ocurrido_en)
) PARTITION BY RANGE (ocurrido_en);

-- =====================================================================
-- INV · Kardex y saldos
-- =====================================================================
CREATE TABLE inv.movimiento_inventario (
  id               bigint GENERATED ALWAYS AS IDENTITY,
  ocurrido_en      timestamptz NOT NULL DEFAULT now(),
  documento_id     bigint   NOT NULL REFERENCES ops.documento_operativo(id),
  objeto_id        bigint   NOT NULL REFERENCES trz.objeto_trazable(id),
  ubicacion_id     bigint   NOT NULL REFERENCES org.ubicacion(id),
  sentido          smallint NOT NULL CHECK (sentido IN (-1, 1)),       -- -1 salida, +1 entrada
  tipo_movimiento  varchar(20) NOT NULL CHECK (tipo_movimiento IN ('INGRESO','EGRESO','TRASLADO_SALIDA','TRASLADO_ENTRADA','AJUSTE')),
  unidades         integer  NOT NULL CHECK (unidades > 0),
  peso_kg          cat.d_peso NOT NULL,
  categoria_id     smallint NOT NULL REFERENCES cat.categoria_raee(id),
  clasificacion_id smallint NOT NULL REFERENCES cat.clasificacion_tecnica(id),
  par_movimiento_id bigint,                      -- vincula salida y entrada de un traslado
  usuario_id       bigint   NOT NULL REFERENCES seg.usuario(id),
  PRIMARY KEY (id, ocurrido_en)
) PARTITION BY RANGE (ocurrido_en);

CREATE TABLE inv.saldo_ubicacion (                -- saldo actual (derivado del kardex, mantenido atómicamente)
  ubicacion_id     bigint   NOT NULL REFERENCES org.ubicacion(id),
  categoria_id     smallint NOT NULL REFERENCES cat.categoria_raee(id),
  clasificacion_id smallint NOT NULL REFERENCES cat.clasificacion_tecnica(id),
  unidades         integer  NOT NULL DEFAULT 0 CHECK (unidades >= 0),      -- RN-06: nunca negativo
  peso_kg          numeric(14,3) NOT NULL DEFAULT 0 CHECK (peso_kg >= 0),
  actualizado_en   timestamptz NOT NULL DEFAULT now(),
  version          integer NOT NULL DEFAULT 1,
  PRIMARY KEY (ubicacion_id, categoria_id, clasificacion_id)
);

-- =====================================================================
-- EVD · Evidencias (binario en S3, metadatos aquí)
-- =====================================================================
CREATE TABLE evd.evidencia (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  uid              uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  ecosistema_id    bigint   NOT NULL REFERENCES seg.ecosistema(id),
  tipo_evidencia_id smallint NOT NULL REFERENCES cat.tipo_evidencia(id),
  s3_bucket        varchar(63)  NOT NULL,
  s3_clave         varchar(512) NOT NULL,
  s3_version_id    varchar(120),
  sha256           cat.d_sha256 NOT NULL,
  mime             varchar(80)  NOT NULL,
  tamano_bytes     bigint NOT NULL CHECK (tamano_bytes > 0 AND tamano_bytes <= 26214400),  -- ≤ 25 MB
  nivel_acceso     varchar(15) NOT NULL CHECK (nivel_acceso IN ('PUBLICO','INTERNO','CONFIDENCIAL','RESTRINGIDO')),
  metadatos_limpios boolean NOT NULL DEFAULT false,   -- EXIF/GPS eliminados antes de subir
  subido_por       bigint NOT NULL REFERENCES seg.usuario(id),
  subido_en        timestamptz NOT NULL DEFAULT now(),
  retener_hasta    date NOT NULL,
  estado           varchar(12) NOT NULL DEFAULT 'ACTIVA' CHECK (estado IN ('ACTIVA','EN_RETENCION','ELIMINADA')),
  UNIQUE (ecosistema_id, sha256),                  -- evita duplicados (CP-02)
  UNIQUE (s3_bucket, s3_clave)
);

CREATE TABLE evd.evidencia_vinculo (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  evidencia_id  bigint NOT NULL REFERENCES evd.evidencia(id),
  documento_id  bigint REFERENCES ops.documento_operativo(id),
  objeto_id     bigint REFERENCES trz.objeto_trazable(id),
  vinculado_en  timestamptz NOT NULL DEFAULT now(),
  vinculado_por bigint NOT NULL REFERENCES seg.usuario(id),
  CHECK (num_nonnulls(documento_id, objeto_id) >= 1),
  UNIQUE NULLS NOT DISTINCT (evidencia_id, documento_id, objeto_id)
);

CREATE TABLE evd.politica_acceso (                -- RN-07: rol × tipo de evidencia × propósito
  rol_id            smallint NOT NULL REFERENCES seg.rol(id),
  tipo_evidencia_id smallint NOT NULL REFERENCES cat.tipo_evidencia(id),
  proposito_id      smallint NOT NULL REFERENCES cat.proposito_uso(id),
  puede_descargar   boolean  NOT NULL DEFAULT false,
  PRIMARY KEY (rol_id, tipo_evidencia_id, proposito_id)
);

CREATE TABLE evd.acceso_evidencia (               -- bitácora de accesos (permitidos y denegados)
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ocurrido_en   timestamptz NOT NULL DEFAULT now(),
  evidencia_id  bigint   NOT NULL REFERENCES evd.evidencia(id),
  usuario_id    bigint   NOT NULL REFERENCES seg.usuario(id),
  proposito_id  smallint NOT NULL REFERENCES cat.proposito_uso(id),
  resultado     varchar(10) NOT NULL CHECK (resultado IN ('PERMITIDO','DENEGADO')),
  canal         varchar(8)  NOT NULL DEFAULT 'WEB'
);

-- =====================================================================
-- RED · Grafo dirigido G=(V,E,c), escenarios y resultados
-- =====================================================================
CREATE TABLE red.nodo (                           -- representa a un centro (por función) o a una organización
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ecosistema_id  bigint   NOT NULL REFERENCES seg.ecosistema(id),
  codigo         cat.d_codigo NOT NULL,           -- G1, C1, E1, R1, K1, D1, B1
  nombre         varchar(120) NOT NULL,
  tipo_nodo_id   smallint NOT NULL REFERENCES cat.tipo_nodo(id),
  centro_id      bigint REFERENCES org.centro(id),
  organizacion_id bigint REFERENCES org.organizacion(id),
  activo         boolean NOT NULL DEFAULT true,
  UNIQUE (ecosistema_id, codigo),
  UNIQUE (centro_id, tipo_nodo_id),
  CHECK (num_nonnulls(centro_id, organizacion_id) = 1)
);

CREATE TABLE red.arista (                         -- relación recursiva nodo × nodo
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ecosistema_id    bigint NOT NULL REFERENCES seg.ecosistema(id),
  nodo_origen_id   bigint NOT NULL REFERENCES red.nodo(id),
  nodo_destino_id  bigint NOT NULL REFERENCES red.nodo(id),
  excepcion_id     bigint,                        -- FK a gob.excepcion_regla (arcos que requieren excepción)
  activa           boolean NOT NULL DEFAULT true,
  UNIQUE (nodo_origen_id, nodo_destino_id),
  CHECK (nodo_origen_id <> nodo_destino_id)
);

ALTER TABLE ops.transferencia
  ADD CONSTRAINT fk_transferencia_arista FOREIGN KEY (arista_id) REFERENCES red.arista(id);
ALTER TABLE ops.recoleccion
  ADD CONSTRAINT fk_recoleccion_arista FOREIGN KEY (arista_id) REFERENCES red.arista(id);
ALTER TABLE cat.tipo_nodo
  ADD CONSTRAINT fk_tipo_nodo_destino FOREIGN KEY (tipo_destino_id) REFERENCES cat.tipo_destino(id);

CREATE TABLE red.capacidad_arista (               -- c(u,v) con historial de vigencia
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  arista_id    bigint   NOT NULL REFERENCES red.arista(id),
  capacidad    cat.d_cantidad NOT NULL,
  unidad_id    smallint NOT NULL REFERENCES cat.unidad_medida(id),
  periodo      varchar(10) NOT NULL CHECK (periodo IN ('DIA','SEMANA','MES')),
  vigencia     tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  fuente       varchar(120) NOT NULL,
  EXCLUDE USING gist (arista_id WITH =, unidad_id WITH =, vigencia WITH &&)
);

CREATE TABLE red.escenario_red (                  -- recursivo: escenario derivado hereda de su base
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ecosistema_id      bigint NOT NULL REFERENCES seg.ecosistema(id),
  codigo             cat.d_codigo NOT NULL,        -- E0..E4
  nombre             varchar(120) NOT NULL,
  descripcion        text,
  escenario_base_id  bigint REFERENCES red.escenario_red(id),
  fecha_referencia   timestamptz NOT NULL DEFAULT now(),  -- instante para leer capacidades vigentes
  unidad_id          smallint NOT NULL REFERENCES cat.unidad_medida(id),
  periodo            varchar(10) NOT NULL CHECK (periodo IN ('DIA','SEMANA','MES')),
  estado             varchar(10) NOT NULL DEFAULT 'BORRADOR' CHECK (estado IN ('BORRADOR','APROBADO','ARCHIVADO')),
  creado_por         bigint NOT NULL REFERENCES seg.usuario(id),
  creado_en          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (ecosistema_id, codigo),
  CHECK (escenario_base_id IS NULL OR escenario_base_id <> id)
);

CREATE TABLE red.escenario_arista (               -- sobrescritura de capacidad/actividad por escenario
  escenario_id        bigint NOT NULL REFERENCES red.escenario_red(id),
  arista_id           bigint NOT NULL REFERENCES red.arista(id),
  capacidad_ajustada  cat.d_cantidad,
  activa              boolean,
  motivo              text NOT NULL,
  PRIMARY KEY (escenario_id, arista_id),
  CHECK (num_nonnulls(capacidad_ajustada, activa) >= 1)
);

CREATE TABLE red.escenario_nodo (                 -- oferta (generadores) y demanda (sumideros)
  escenario_id bigint NOT NULL REFERENCES red.escenario_red(id),
  nodo_id      bigint NOT NULL REFERENCES red.nodo(id),
  oferta       cat.d_cantidad NOT NULL DEFAULT 0,
  demanda      cat.d_cantidad NOT NULL DEFAULT 0,
  PRIMARY KEY (escenario_id, nodo_id)
);

CREATE TABLE red.ejecucion_flujo (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  escenario_id    bigint NOT NULL REFERENCES red.escenario_red(id),
  algoritmo       varchar(20) NOT NULL DEFAULT 'EDMONDS_KARP' CHECK (algoritmo IN ('EDMONDS_KARP','FORD_FULKERSON','DINIC')),
  version_modulo  varchar(20) NOT NULL,
  parametros      jsonb NOT NULL DEFAULT '{}'::jsonb,
  hash_entrada    cat.d_sha256 NOT NULL,           -- huella del dataset leído (reproducibilidad)
  flujo_maximo    cat.d_cantidad,
  estado          varchar(10) NOT NULL DEFAULT 'EN_CURSO' CHECK (estado IN ('EN_CURSO','OK','ERROR')),
  iniciado_en     timestamptz NOT NULL DEFAULT now(),
  finalizado_en   timestamptz,
  duracion_ms     integer GENERATED ALWAYS AS ((extract(epoch FROM (finalizado_en - iniciado_en)) * 1000)::integer) STORED,
  ejecutado_por   bigint NOT NULL REFERENCES seg.usuario(id),
  canal           varchar(8) NOT NULL DEFAULT 'WEB',
  mensaje_error   text
);

CREATE TABLE red.resultado_flujo_arista (
  ejecucion_id  bigint NOT NULL REFERENCES red.ejecucion_flujo(id) ON DELETE CASCADE,
  arista_id     bigint NOT NULL REFERENCES red.arista(id),
  capacidad     cat.d_cantidad NOT NULL,
  flujo         cat.d_cantidad NOT NULL,
  saturada      boolean GENERATED ALWAYS AS (flujo >= capacidad AND capacidad > 0) STORED,
  utilizacion   numeric(6,2) GENERATED ALWAYS AS (CASE WHEN capacidad > 0 THEN round(100 * flujo / capacidad, 2) END) STORED,
  PRIMARY KEY (ejecucion_id, arista_id),
  CHECK (flujo <= capacidad)
);

CREATE TABLE red.corte_minimo (                   -- puede haber varios cortes mínimos por ejecución
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ejecucion_id     bigint NOT NULL REFERENCES red.ejecucion_flujo(id) ON DELETE CASCADE,
  numero_corte     smallint NOT NULL,
  capacidad_corte  cat.d_cantidad NOT NULL,
  lado_fuente      text[] NOT NULL,                -- códigos de nodos del lado S
  UNIQUE (ejecucion_id, numero_corte)
);

CREATE TABLE red.corte_minimo_arista (
  corte_id  bigint NOT NULL REFERENCES red.corte_minimo(id) ON DELETE CASCADE,
  arista_id bigint NOT NULL REFERENCES red.arista(id),
  PRIMARY KEY (corte_id, arista_id)
);

-- =====================================================================
-- IND · Indicadores y alertas
-- =====================================================================
CREATE TABLE ind.indicador (
  id           smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo       cat.d_codigo NOT NULL UNIQUE,
  nombre       varchar(160) NOT NULL,
  dimension    varchar(12)  NOT NULL CHECK (dimension IN ('OPERATIVA','AMBIENTAL','SOCIAL','ECONOMICA','TECNICA')),
  materia_origen varchar(10) NOT NULL CHECK (materia_origen IN ('AE','MD','BD','NUBE','INN','INT')),
  formula      text NOT NULL,
  fuente       varchar(120) NOT NULL,              -- vista o consulta que lo calcula
  unidad       varchar(20)  NOT NULL,
  meta         numeric(14,3),
  sentido      varchar(12)  NOT NULL CHECK (sentido IN ('MAYOR_MEJOR','MENOR_MEJOR','RANGO')),
  activo       boolean NOT NULL DEFAULT true
);

CREATE TABLE ind.medicion_indicador (             -- serie histórica de indicadores
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  indicador_id  smallint NOT NULL REFERENCES ind.indicador(id),
  ecosistema_id bigint   NOT NULL REFERENCES seg.ecosistema(id),
  centro_id     bigint REFERENCES org.centro(id),
  periodo       daterange NOT NULL,
  valor         numeric(14,4) NOT NULL,
  calculado_en  timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (indicador_id, ecosistema_id, centro_id, periodo)
);

CREATE TABLE ind.regla_alerta (
  id          smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo      cat.d_codigo NOT NULL UNIQUE,
  nombre      varchar(160) NOT NULL,
  severidad   varchar(8)   NOT NULL CHECK (severidad IN ('INFO','MEDIA','ALTA','CRITICA')),
  condicion   text         NOT NULL,
  umbral      numeric(14,3),
  activa      boolean NOT NULL DEFAULT true
);

CREATE TABLE ind.alerta (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  regla_id      smallint NOT NULL REFERENCES ind.regla_alerta(id),
  ecosistema_id bigint   NOT NULL REFERENCES seg.ecosistema(id),
  objeto_id     bigint REFERENCES trz.objeto_trazable(id),
  arista_id     bigint REFERENCES red.arista(id),
  centro_id     bigint REFERENCES org.centro(id),
  mensaje       text NOT NULL,
  estado        varchar(10) NOT NULL DEFAULT 'ABIERTA' CHECK (estado IN ('ABIERTA','RECONOCIDA','RESUELTA')),
  generada_en   timestamptz NOT NULL DEFAULT now(),
  resuelta_en   timestamptz,
  resuelta_por  bigint REFERENCES seg.usuario(id),
  CHECK ((estado = 'RESUELTA') = (resuelta_en IS NOT NULL))
);

-- =====================================================================
-- GOB · Comité de arquitectura (ARB)
-- =====================================================================
CREATE TABLE gob.decision_arquitectura (          -- ADR; recursiva por sustitución
  id               integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo           cat.d_codigo NOT NULL UNIQUE,  -- ADR-001
  titulo           varchar(200) NOT NULL,
  contexto         text NOT NULL,
  decision         text NOT NULL,
  consecuencias    text NOT NULL,
  materias         text[] NOT NULL,
  estado           varchar(12) NOT NULL DEFAULT 'PROPUESTA' CHECK (estado IN ('PROPUESTA','APROBADA','RECHAZADA','SUSTITUIDA')),
  sustituida_por_id integer REFERENCES gob.decision_arquitectura(id),
  fecha            date NOT NULL DEFAULT current_date,
  CHECK ((estado = 'SUSTITUIDA') = (sustituida_por_id IS NOT NULL))
);

CREATE TABLE gob.excepcion_regla (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo           cat.d_codigo NOT NULL UNIQUE,
  regla            varchar(10) NOT NULL,           -- RN-02, RN-05…
  descripcion      text NOT NULL,
  decision_id      integer REFERENCES gob.decision_arquitectura(id),
  aprobada_por     bigint REFERENCES seg.usuario(id),
  vigencia         daterange NOT NULL,
  estado           varchar(10) NOT NULL DEFAULT 'SOLICITADA' CHECK (estado IN ('SOLICITADA','APROBADA','RECHAZADA','VENCIDA')),
  CHECK (estado <> 'APROBADA' OR aprobada_por IS NOT NULL)
);

ALTER TABLE red.arista
  ADD CONSTRAINT fk_arista_excepcion FOREIGN KEY (excepcion_id) REFERENCES gob.excepcion_regla(id);

CREATE TABLE gob.riesgo (                         -- matriz de riesgos (Innovación + técnica)
  id             integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo         cat.d_codigo NOT NULL UNIQUE,
  categoria      varchar(15) NOT NULL CHECK (categoria IN ('ACCESO','PRIVACIDAD','PODER','PROPIEDAD','EXCLUSION','SOSTENIBILIDAD','SEGURIDAD','TECNICO','COSTO')),
  descripcion    text NOT NULL,
  probabilidad   smallint NOT NULL CHECK (probabilidad BETWEEN 1 AND 5),
  impacto        smallint NOT NULL CHECK (impacto BETWEEN 1 AND 5),
  nivel          smallint GENERATED ALWAYS AS (probabilidad * impacto) STORED,
  control        text NOT NULL,
  objeto_bd      text,                             -- tabla/regla que implementa el control
  estado         varchar(10) NOT NULL DEFAULT 'ABIERTO' CHECK (estado IN ('ABIERTO','MITIGADO','ACEPTADO','CERRADO')),
  materia_origen varchar(10) NOT NULL
);

-- =====================================================================
-- AUD · Auditoría técnica (particionada) y de seguridad
-- =====================================================================
CREATE TABLE aud.log_cambio (
  id              bigint GENERATED ALWAYS AS IDENTITY,
  ocurrido_en     timestamptz NOT NULL DEFAULT clock_timestamp(),
  esquema         name   NOT NULL,
  tabla           name   NOT NULL,
  operacion       char(1) NOT NULL CHECK (operacion IN ('I','U','D')),
  pk              jsonb  NOT NULL,
  datos_antes     jsonb,
  datos_despues   jsonb,
  campos_cambiados text[],
  usuario_id      bigint,                          -- usuario de negocio (contexto de la API)
  usuario_bd      name   NOT NULL DEFAULT current_user,
  canal           varchar(8),
  request_id      varchar(64),
  txid            bigint NOT NULL DEFAULT txid_current(),
  hash_registro   cat.d_sha256 NOT NULL,
  PRIMARY KEY (id, ocurrido_en)
) PARTITION BY RANGE (ocurrido_en);

CREATE TABLE aud.sello_integridad (               -- sellado periódico: hash encadenado por periodo
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  periodo          tstzrange NOT NULL,
  registros        bigint NOT NULL,
  hash_periodo     cat.d_sha256 NOT NULL,
  hash_sello_anterior cat.d_sha256,
  sellado_en       timestamptz NOT NULL DEFAULT now(),
  EXCLUDE USING gist (periodo WITH &&)
);

CREATE TABLE aud.evento_seguridad (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ocurrido_en   timestamptz NOT NULL DEFAULT now(),
  tipo          varchar(20) NOT NULL CHECK (tipo IN ('LOGIN_OK','LOGIN_FALLIDO','ACCESO_DENEGADO','CAMBIO_ROL','MCP_RECHAZO','REGLA_VIOLADA')),
  usuario_id    bigint,
  detalle       jsonb NOT NULL DEFAULT '{}'::jsonb,
  ip_hash       char(64),
  request_id    varchar(64)
);

-- =====================================================================
-- MCP · Registro de herramientas, recursos y bitácora de invocaciones
-- =====================================================================
CREATE TABLE mcp.herramienta (
  id                   smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre               varchar(64) NOT NULL UNIQUE CHECK (nombre ~ '^[a-z][a-z0-9_]*$'),
  titulo               varchar(120) NOT NULL,
  descripcion          text NOT NULL,              -- texto que lee el modelo/cliente MCP
  tipo                 varchar(10) NOT NULL CHECK (tipo IN ('LECTURA','ESCRITURA','ANALISIS')),
  objeto_sql           text NOT NULL,              -- función o vista del esquema api
  esquema_entrada      jsonb NOT NULL,             -- JSON Schema de argumentos
  esquema_salida       jsonb,
  requiere_confirmacion boolean NOT NULL DEFAULT false,
  limite_por_minuto    smallint NOT NULL DEFAULT 30,
  version              varchar(10) NOT NULL DEFAULT '1.0',
  activa               boolean NOT NULL DEFAULT true,
  CHECK (tipo <> 'ESCRITURA' OR requiere_confirmacion),
  CHECK (objeto_sql LIKE 'api.%')
);

CREATE TABLE mcp.herramienta_rol (
  herramienta_id smallint NOT NULL REFERENCES mcp.herramienta(id),
  rol_id         smallint NOT NULL REFERENCES seg.rol(id),
  PRIMARY KEY (herramienta_id, rol_id)
);

CREATE TABLE mcp.recurso (
  id            smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  uri_plantilla varchar(160) NOT NULL UNIQUE,      -- ecoraee://objeto/{codigo}
  nombre        varchar(120) NOT NULL,
  descripcion   text NOT NULL,
  objeto_sql    text NOT NULL CHECK (objeto_sql LIKE 'api.%'),
  mime          varchar(60) NOT NULL DEFAULT 'application/json',
  activo        boolean NOT NULL DEFAULT true
);

CREATE TABLE mcp.invocacion (
  id              bigint GENERATED ALWAYS AS IDENTITY,
  ocurrido_en     timestamptz NOT NULL DEFAULT now(),
  herramienta_id  smallint REFERENCES mcp.herramienta(id),
  recurso_id      smallint REFERENCES mcp.recurso(id),
  nombre_solicitado varchar(160) NOT NULL,            -- lo que pidió el cliente (aunque no exista)
  usuario_id      bigint NOT NULL,
  sesion_mcp      varchar(64) NOT NULL,
  argumentos      jsonb NOT NULL DEFAULT '{}'::jsonb,   -- saneados (sin PII)
  argumentos_hash cat.d_sha256 NOT NULL,
  estado          varchar(22) NOT NULL CHECK (estado IN ('OK','ERROR','DENEGADO','PENDIENTE_CONFIRMACION','CONFIRMADO','LIMITE_EXCEDIDO')),
  filas           integer,
  duracion_ms     integer,
  error           text,
  request_id      varchar(64),
  PRIMARY KEY (id, ocurrido_en),
  CHECK (num_nonnulls(herramienta_id, recurso_id) <= 1)
) PARTITION BY RANGE (ocurrido_en);

-- =====================================================================
-- INTEG · Idempotencia y outbox (escalabilidad e integración asíncrona)
-- =====================================================================
CREATE TABLE integ.idempotencia (
  clave           uuid PRIMARY KEY,
  usuario_id      bigint NOT NULL,
  operacion       varchar(80) NOT NULL,
  hash_solicitud  cat.d_sha256 NOT NULL,
  respuesta       jsonb,
  creado_en       timestamptz NOT NULL DEFAULT now(),
  expira_en       timestamptz NOT NULL DEFAULT now() + interval '24 hours'
);

CREATE TABLE integ.outbox_evento (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ocurrido_en   timestamptz NOT NULL DEFAULT now(),
  ecosistema_id bigint NOT NULL,
  agregado      varchar(30) NOT NULL,              -- OBJETO, TRANSFERENCIA, EJECUCION_FLUJO
  agregado_id   bigint NOT NULL,
  tipo_evento   varchar(60) NOT NULL,              -- objeto.estado_cambiado
  payload       jsonb NOT NULL,
  publicado_en  timestamptz,
  intentos      smallint NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------
-- Particiones mensuales (septiembre 2026 – marzo 2027) + DEFAULT
-- ---------------------------------------------------------------------
DO $$
DECLARE t text; m date;
BEGIN
  FOREACH t IN ARRAY ARRAY['trz.historial_estado','inv.movimiento_inventario','aud.log_cambio','mcp.invocacion'] LOOP
    m := date '2026-09-01';
    WHILE m < date '2027-04-01' LOOP
      EXECUTE format('CREATE TABLE %s_%s PARTITION OF %s FOR VALUES FROM (%L) TO (%L)',
                     t, to_char(m,'YYYYMM'), t, m, (m + interval '1 month')::date);
      m := (m + interval '1 month')::date;
    END LOOP;
    EXECUTE format('CREATE TABLE %s_default PARTITION OF %s DEFAULT', t, t);
  END LOOP;
END $$;
