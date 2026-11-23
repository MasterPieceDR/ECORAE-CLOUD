-- =====================================================================
-- Script 05: datos semilla — diccionario maestro (catálogos), seguridad,
-- ecosistema sintético, red, registro MCP, indicadores, gobierno, glosario
-- Todos los datos son SINTÉTICOS (restricción académica 3.3 / RNF-10)
-- =====================================================================
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- Catálogos
-- ---------------------------------------------------------------------
INSERT INTO cat.unidad_medida(codigo, nombre) VALUES ('UND','Unidades'), ('KG','Kilogramos');

INSERT INTO cat.tipo_actor(codigo, nombre, descripcion) VALUES
 ('GENERADOR','Generador','Entrega equipos en desuso'),
 ('ACOPIO','Operador de acopio','Recibe y almacena temporalmente'),
 ('EVALUADOR','Evaluador técnico','Determina condición y ruta'),
 ('REACONDICIONADOR','Reacondicionador','Repara y prepara para reutilización'),
 ('RECICLADOR','Gestor de reciclaje','Desensambla y recupera materiales'),
 ('GESTOR_DISPOSICION','Gestor de disposición','Dispone residuos no recuperables'),
 ('BENEFICIARIO','Entidad beneficiaria','Recibe equipos recuperados'),
 ('COORDINADOR_RED','Coordinación de la red','Gestiona capacidades y transferencias'),
 ('AUTORIDAD_AMBIENTAL','Autoridad ambiental','Supervisa cumplimiento (solo lectura)');

INSERT INTO cat.actor_negocio(codigo, nombre, responsabilidad) VALUES
 ('GENERADOR','Generador','Registra equipos y solicita recolección o entrega'),
 ('OPERADOR_CENTRO','Operador de centro','Recibe lotes, verifica información y administra inventario'),
 ('TECNICO_EVALUADOR','Técnico evaluador','Determina condición, categoría y destino posible'),
 ('COORDINADOR_LOGISTICO','Coordinador logístico','Gestiona capacidades, transferencias y análisis de flujo'),
 ('REACONDICIONADOR_RECICLADOR','Reacondicionador/reciclador','Confirma recepción, tratamiento y resultado'),
 ('ENTIDAD_BENEFICIARIA','Entidad beneficiaria','Recibe dispositivos recuperados'),
 ('ADMINISTRADOR','Administrador','Gestiona catálogos, usuarios, roles, centros y parámetros'),
 ('COMITE_ARQUITECTURA','Comité de arquitectura','Evalúa alineación, riesgos, excepciones y cambios'),
 ('RESPONSABLE_GESTION','Responsable de gestión (AE)','Dirige la operación y rinde cuentas de indicadores'),
 ('RESPONSABLE_TECNOLOGICO','Responsable tecnológico (AE)','Opera la plataforma y su infraestructura'),
 ('AUTORIDAD_AMBIENTAL','Autoridad ambiental (AE)','Supervisa trazabilidad y cumplimiento');

INSERT INTO cat.estado_trazabilidad(codigo, nombre, orden, es_inicial, es_final, descripcion) VALUES
 ('REGISTRADO','Registrado',1,true,false,'Objeto registrado por el generador o el operador'),
 ('RECOLECCION_SOLICITADA','Recolección solicitada',2,false,false,'Existe una solicitud de recolección'),
 ('EN_RECOLECCION','En recolección',3,false,false,'Recolección programada o en curso'),
 ('RECIBIDO','Recibido',4,false,false,'Recibido físicamente en un centro'),
 ('EN_EVALUACION','En evaluación',5,false,false,'En evaluación técnica'),
 ('CLASIFICADO','Clasificado',6,false,false,'Tiene clasificación técnica vigente'),
 ('EN_TRANSFERENCIA','En transferencia',7,false,false,'En tránsito por una arista de la red'),
 ('EN_TRATAMIENTO','En tratamiento',8,false,false,'En reacondicionamiento, reciclaje o disposición'),
 ('TRATADO','Tratado',9,false,false,'Tratamiento concluido con resultado'),
 ('ASIGNADO_BENEFICIARIO','Asignado a beneficiario',10,false,false,'Entregado a una entidad beneficiaria'),
 ('CERRADO','Cerrado',11,false,true,'Destino final confirmado con evidencia (RN-08)'),
 ('ANULADO','Anulado',12,false,true,'Registro anulado por error o duplicidad'),
 ('DESAGRUPADO','Desagrupado',13,false,true,'Solo lotes: el lote se disolvió y sus miembros siguen por separado');

INSERT INTO cat.transicion_estado(estado_origen_id, estado_destino_id, permiso_requerido, tipo_documento, requiere_evidencia, requiere_clasificacion, descripcion)
SELECT o.id, d.id, t.permiso, t.doc, t.evid, t.clas, t.descr
  FROM (VALUES
   ('REGISTRADO','RECOLECCION_SOLICITADA','SOLICITUD.CREAR','SOLICITUD',false,false,'Generador solicita recolección'),
   ('REGISTRADO','RECIBIDO','RECEPCION.REGISTRAR','RECEPCION',true,false,'Entrega directa en el centro'),
   ('RECOLECCION_SOLICITADA','EN_RECOLECCION','RECOLECCION.PROGRAMAR','RECOLECCION',false,false,'Coordinador programa la recolección'),
   ('EN_RECOLECCION','RECIBIDO','RECEPCION.REGISTRAR','RECEPCION',true,false,'Recepción de lo recolectado'),
   ('RECIBIDO','EN_EVALUACION','EVALUACION.REGISTRAR','EVALUACION',false,false,'Inicio de evaluación técnica completa'),
   ('RECIBIDO','CLASIFICADO','EVALUACION.REGISTRAR','EVALUACION',false,true,'Preclasificación por técnico habilitado en acopio'),
   ('EN_EVALUACION','CLASIFICADO','EVALUACION.REGISTRAR','EVALUACION',false,true,'Fin de evaluación con clasificación'),
   ('RECIBIDO','EN_TRANSFERENCIA','TRANSFERENCIA.CREAR','TRANSFERENCIA',false,false,'Traslado a un centro de evaluación'),
   ('CLASIFICADO','EN_TRANSFERENCIA','TRANSFERENCIA.CREAR','TRANSFERENCIA',false,true,'Traslado hacia el destino de su ruta'),
   ('TRATADO','EN_TRANSFERENCIA','TRANSFERENCIA.CREAR','TRANSFERENCIA',false,true,'Equipo reacondicionado sale hacia beneficiario'),
   ('EN_TRANSFERENCIA','RECIBIDO','TRANSFERENCIA.CONFIRMAR','TRANSFERENCIA',true,false,'Llega a evaluación sin clasificar'),
   ('EN_TRANSFERENCIA','CLASIFICADO','TRANSFERENCIA.CONFIRMAR','TRANSFERENCIA',true,true,'Llega a un centro intermedio ya clasificado'),
   ('EN_TRANSFERENCIA','EN_TRATAMIENTO','TRANSFERENCIA.CONFIRMAR','TRANSFERENCIA',true,true,'Llega a gestor de tratamiento'),
   ('EN_TRANSFERENCIA','ASIGNADO_BENEFICIARIO','TRANSFERENCIA.CONFIRMAR','ASIGNACION',true,true,'Beneficiario confirma la entrega'),
   ('CLASIFICADO','ASIGNADO_BENEFICIARIO','ASIGNACION.REGISTRAR','ASIGNACION',true,true,'Entrega directa en el centro'),
   ('TRATADO','ASIGNADO_BENEFICIARIO','ASIGNACION.REGISTRAR','ASIGNACION',true,true,'Entrega directa desde reacondicionamiento'),
   ('EN_TRATAMIENTO','TRATADO','TRATAMIENTO.REGISTRAR','TRATAMIENTO',true,false,'Tratamiento concluido'),
   ('EN_TRATAMIENTO','EN_EVALUACION','TRATAMIENTO.REGISTRAR','TRATAMIENTO',false,false,'Tratamiento fallido: vuelve a evaluación (R1→K1)'),
   ('TRATADO','CERRADO','CIERRE.CONFIRMAR','CIERRE',true,false,'Cierre tras reciclaje o disposición'),
   ('ASIGNADO_BENEFICIARIO','CERRADO','CIERRE.CONFIRMAR','CIERRE',true,false,'Cierre por reutilización confirmada'),
   ('REGISTRADO','ANULADO','OBJETO.ANULAR','AJUSTE',false,false,'Anulación por error de registro'),
   ('RECOLECCION_SOLICITADA','ANULADO','OBJETO.ANULAR','AJUSTE',false,false,'Anulación de solicitud'),
   ('RECIBIDO','DESAGRUPADO','LOTE.GESTIONAR','AJUSTE',false,false,'Disolución de un lote recibido'),
   ('CLASIFICADO','DESAGRUPADO','LOTE.GESTIONAR','AJUSTE',false,false,'Disolución de un lote clasificado'),
   ('TRATADO','DESAGRUPADO','LOTE.GESTIONAR','AJUSTE',false,false,'Disolución de un lote tratado')
  ) AS t(o, d, permiso, doc, evid, clas, descr)
  JOIN cat.estado_trazabilidad o ON o.codigo = t.o JOIN cat.estado_trazabilidad d ON d.codigo = t.d;

INSERT INTO cat.clasificacion_tecnica(codigo, nombre, orden, es_resultado_evaluacion, descripcion) VALUES
 ('PENDIENTE','Pendiente de evaluación',0,false,'Solo para saldos de inventario antes de evaluar'),
 ('REUTILIZABLE','Reutilizable',1,true,'Funciona y puede entregarse tras borrado de datos'),
 ('REPARABLE','Reparable',2,true,'Requiere reacondicionamiento'),
 ('RECICLABLE','Reciclable',3,true,'Solo recuperación de materiales'),
 ('NO_RECUPERABLE','No recuperable',4,true,'Disposición controlada');

INSERT INTO cat.tipo_destino(codigo, nombre, es_final) VALUES
 ('REUTILIZACION','Reutilización por beneficiario',true),
 ('REACONDICIONAMIENTO','Reacondicionamiento',false),
 ('RECICLAJE','Reciclaje',true),
 ('DISPOSICION_CONTROLADA','Disposición controlada',true);

INSERT INTO cat.clasificacion_destino_permitido(clasificacion_id, tipo_destino_id, prioridad)
SELECT k.id, d.id, m.p FROM (VALUES
  ('REUTILIZABLE','REUTILIZACION',1), ('REUTILIZABLE','REACONDICIONAMIENTO',2),
  ('REPARABLE','REACONDICIONAMIENTO',1), ('REPARABLE','RECICLAJE',2),
  ('RECICLABLE','RECICLAJE',1), ('RECICLABLE','DISPOSICION_CONTROLADA',2),
  ('NO_RECUPERABLE','DISPOSICION_CONTROLADA',1)) m(k, d, p)
  JOIN cat.clasificacion_tecnica k ON k.codigo = m.k JOIN cat.tipo_destino d ON d.codigo = m.d;

INSERT INTO cat.categoria_raee(codigo, nombre, categoria_padre_id, peso_referencial_kg, vida_util_anios, contiene_almacenamiento, esquema_atributos)
VALUES ('RAEE','Residuos de aparatos eléctricos y electrónicos',NULL,NULL,NULL,false,'{}');
INSERT INTO cat.categoria_raee(codigo, nombre, categoria_padre_id, peso_referencial_kg, vida_util_anios, contiene_almacenamiento, esquema_atributos)
SELECT v.c, v.n, p.id, v.peso, v.vida, v.alm, v.esq::jsonb FROM (VALUES
  ('TIC','Equipos de informática y telecomunicaciones','RAEE',NULL::numeric,NULL::int,false,'{}'),
  ('COMPONENTE','Componentes extraídos','RAEE',NULL,NULL,false,'{}'),
  ('PEQ_ELECTRO','Pequeños electrodomésticos','RAEE',3,8,false,'{}')) v(c, n, padre, peso, vida, alm, esq)
  JOIN cat.categoria_raee p ON p.codigo = v.padre;
INSERT INTO cat.categoria_raee(codigo, nombre, categoria_padre_id, peso_referencial_kg, vida_util_anios, contiene_almacenamiento, esquema_atributos)
SELECT v.c, v.n, p.id, v.peso, v.vida, v.alm, v.esq::jsonb FROM (VALUES
  ('PORTATIL','Laptop','TIC',2.2,5,true,'{"required":["ram_gb","almacenamiento_gb"],"properties":{"ram_gb":{"type":"number"},"almacenamiento_gb":{"type":"number"},"procesador":{"type":"string"}}}'),
  ('ESCRITORIO','Computador de escritorio','TIC',8,6,true,'{"required":["ram_gb","almacenamiento_gb"]}'),
  ('MONITOR','Monitor','TIC',4.5,7,false,'{"required":["pulgadas"]}'),
  ('TABLET','Tablet','TIC',0.6,4,true,'{}'),
  ('CELULAR','Teléfono celular','TIC',0.2,3,true,'{}'),
  ('IMPRESORA','Impresora','TIC',7,6,false,'{}'),
  ('EQUIPO_RED','Router / switch','TIC',1.5,7,false,'{}'),
  ('BATERIA','Batería','COMPONENTE',0.4,NULL,false,'{"required":["quimica"]}'),
  ('DISCO','Unidad de almacenamiento','COMPONENTE',0.1,NULL,true,'{}'),
  ('PLACA','Tarjeta de circuito','COMPONENTE',0.3,NULL,false,'{}')) v(c, n, padre, peso, vida, alm, esq)
  JOIN cat.categoria_raee p ON p.codigo = v.padre;

INSERT INTO cat.marca(codigo, nombre) VALUES ('DELL','Dell'),('HP','HP'),('LENOVO','Lenovo'),('SAMSUNG','Samsung'),
  ('ACER','Acer'),('LG','LG'),('APPLE','Apple'),('GENERICA','Genérica');
INSERT INTO cat.modelo_equipo(marca_id, categoria_id, nombre, anio_lanzamiento, peso_kg)
SELECT m.id, c.id, v.n, v.a, v.p FROM (VALUES ('DELL','PORTATIL','Latitude 5490',2018,1.9),('LENOVO','PORTATIL','ThinkPad T470',2017,1.6),
  ('HP','ESCRITORIO','ProDesk 400 G4',2017,6.8),('LG','MONITOR','22MK400',2018,3.1),('SAMSUNG','CELULAR','Galaxy A10',2019,0.17)) v(m, c, n, a, p)
  JOIN cat.marca m ON m.codigo = v.m JOIN cat.categoria_raee c ON c.codigo = v.c;

INSERT INTO cat.tipo_centro(codigo, nombre) VALUES ('ACOPIO','Acopio'),('EVALUACION','Evaluación técnica'),
  ('REACONDICIONAMIENTO','Reacondicionamiento'),('RECICLAJE','Reciclaje'),('DISPOSICION','Disposición controlada');

INSERT INTO cat.tipo_nodo(codigo, nombre, prefijo, es_fuente, es_sumidero, tipo_centro_id, tipo_destino_id)
SELECT v.c, v.n, v.p, v.f, v.s, tc.id, td.id FROM (VALUES
  ('GENERADOR','Generador','G',true,false,NULL,NULL),
  ('ACOPIO','Centro de acopio','C',false,false,'ACOPIO',NULL),
  ('EVALUACION','Centro de evaluación','E',false,false,'EVALUACION',NULL),
  ('REACONDICIONAMIENTO','Reacondicionamiento','R',false,false,'REACONDICIONAMIENTO','REACONDICIONAMIENTO'),
  ('RECICLAJE','Reciclaje','K',false,true,'RECICLAJE','RECICLAJE'),
  ('DISPOSICION','Disposición controlada','D',false,true,'DISPOSICION','DISPOSICION_CONTROLADA'),
  ('BENEFICIARIO','Beneficiario','B',false,true,NULL,'REUTILIZACION')) v(c, n, p, f, s, tc, td)
  LEFT JOIN cat.tipo_centro tc ON tc.codigo = v.tc LEFT JOIN cat.tipo_destino td ON td.codigo = v.td;

INSERT INTO cat.arista_tipo_permitida(tipo_nodo_origen_id, tipo_nodo_destino_id, requiere_excepcion, justificacion)
SELECT o.id, d.id, v.x, v.j FROM (VALUES
  ('GENERADOR','ACOPIO',false,'Recolección o entrega directa'),
  ('ACOPIO','EVALUACION',false,'Todo equipo se evalúa antes de su destino (RN-02)'),
  ('ACOPIO','ACOPIO',false,'Consolidación entre acopios'),
  ('ACOPIO','RECICLAJE',true,'Solo con preclasificación de un técnico habilitado en el acopio (excepción del Comité)'),
  ('EVALUACION','REACONDICIONAMIENTO',false,'Reparable'),
  ('EVALUACION','RECICLAJE',false,'Reciclable / reparable no viable'),
  ('EVALUACION','DISPOSICION',false,'No recuperable'),
  ('EVALUACION','BENEFICIARIO',false,'Reutilizable'),
  ('REACONDICIONAMIENTO','BENEFICIARIO',false,'Reacondicionado con control de calidad'),
  ('REACONDICIONAMIENTO','RECICLAJE',false,'Descarte tras tratamiento fallido y reevaluación'),
  ('REACONDICIONAMIENTO','DISPOSICION',false,'Residuo del reacondicionamiento'),
  ('RECICLAJE','DISPOSICION',false,'Fracción no recuperable del reciclaje')) v(o, d, x, j)
  JOIN cat.tipo_nodo o ON o.codigo = v.o JOIN cat.tipo_nodo d ON d.codigo = v.d;

INSERT INTO cat.tipo_evidencia(codigo, nombre, nivel_acceso, retencion_meses, mime_permitidos) VALUES
 ('FOTO_RECEPCION','Fotografía de recepción','INTERNO',24,'{image/jpeg,image/png}'),
 ('ACTA_RECEPCION','Acta de recepción','INTERNO',60,'{application/pdf}'),
 ('INFORME_EVALUACION','Informe de evaluación técnica','INTERNO',60,'{application/pdf,image/jpeg,image/png}'),
 ('GUIA_REMISION','Guía de remisión','INTERNO',60,'{application/pdf,image/jpeg}'),
 ('ACTA_ENTREGA','Acta de entrega a beneficiario','CONFIDENCIAL',60,'{application/pdf}'),
 ('CERTIFICADO_BORRADO','Certificado de borrado seguro','RESTRINGIDO',84,'{application/pdf}'),
 ('CERTIFICADO_TRATAMIENTO','Certificado de tratamiento','INTERNO',84,'{application/pdf}'),
 ('FOTO_TRATAMIENTO','Fotografía de tratamiento','INTERNO',24,'{image/jpeg,image/png}');

INSERT INTO cat.proposito_uso(codigo, nombre, descripcion) VALUES
 ('TRAZABILIDAD','Trazabilidad operativa','Verificar el recorrido de un objeto'),
 ('EVALUACION_TECNICA','Evaluación técnica','Sustentar una clasificación'),
 ('AUDITORIA','Auditoría','Revisión interna o del Comité'),
 ('CUMPLIMIENTO_AMBIENTAL','Cumplimiento ambiental','Supervisión de la autoridad'),
 ('INVESTIGACION_ANONIMIZADA','Investigación anonimizada','Análisis agregado sin datos identificables');

INSERT INTO cat.tipo_tratamiento(codigo, nombre, tipo_destino_id)
SELECT v.c, v.n, d.id FROM (VALUES ('REACONDICIONAMIENTO_COMPLETO','Reacondicionamiento completo','REACONDICIONAMIENTO'),
  ('REPARACION_MENOR','Reparación menor','REACONDICIONAMIENTO'),('DESENSAMBLE_RECICLAJE','Desensamble y reciclaje','RECICLAJE'),
  ('DISPOSICION_FINAL','Disposición final controlada','DISPOSICION_CONTROLADA')) v(c, n, d) JOIN cat.tipo_destino d ON d.codigo = v.d;

INSERT INTO cat.material(codigo, nombre, es_peligroso) VALUES ('METAL_FERROSO','Metales ferrosos',false),('ALUMINIO','Aluminio',false),
  ('COBRE','Cobre',false),('PLASTICO','Plásticos',false),('VIDRIO','Vidrio',false),('TARJETA_CIRCUITO','Tarjetas de circuito',false),
  ('BATERIA_LITIO','Baterías de litio',true),('RESIDUO_NR','Residuo no recuperable',true);

INSERT INTO cat.criterio_evaluacion(codigo, nombre, tipo_valor, categoria_id, obligatorio)
SELECT v.c, v.n, v.t, c.id, v.o FROM (VALUES
  ('ENCIENDE','El equipo enciende','BOOLEANO',NULL,true),
  ('DANO_FISICO','Presenta daño físico grave','BOOLEANO',NULL,true),
  ('ESTADO_ESTETICO','Estado estético','TEXTO',NULL,false),
  ('PANTALLA_FUNCIONAL','Pantalla funcional','BOOLEANO','PORTATIL',true),
  ('DATOS_PRESENTES','Contiene datos del usuario anterior','BOOLEANO','PORTATIL',true),
  ('BATERIA_SALUD_PCT','Salud de batería (%)','NUMERO','PORTATIL',false)) v(c, n, t, cat, o)
  LEFT JOIN cat.categoria_raee c ON c.codigo = v.cat;

INSERT INTO cat.motivo(codigo, ambito, nombre) VALUES
 ('ERROR_REGISTRO','ANULACION','Error de registro'),('DUPLICADO','ANULACION','Registro duplicado'),
 ('EMBALAJE_INADECUADO','RECHAZO','Embalaje inadecuado o peligroso'),('DIFERENCIA_PESO','AJUSTE','Diferencia de peso'),
 ('TRATAMIENTO_FALLIDO','REEVALUACION','El tratamiento no fue exitoso'),('CONTROL_CALIDAD','REEVALUACION','Control de calidad posterior al tratamiento'),
 ('RECLAMO','REEVALUACION','Reclamo de un actor'),('PRECLASIFICACION_ACOPIO','EXCEPCION','Preclasificación en acopio');

INSERT INTO cat.parametro_sistema(codigo, valor, descripcion) VALUES
 ('DIAS_ALERTA_ESTANCADO','15','Días sin cambio de estado para alertar'),
 ('UMBRAL_SATURACION_PCT','90','Utilización de arista que dispara alerta'),
 ('TTL_URL_EVIDENCIA_SEG','300','Vida de la URL prefirmada de S3'),
 ('RETENCION_AUDITORIA_MESES','60','Retención de la auditoría antes de archivar en S3 Glacier');

-- ---------------------------------------------------------------------
-- Seguridad: permisos, roles jerárquicos, SoD y mapeo de actores
-- ---------------------------------------------------------------------
INSERT INTO seg.permiso(codigo, recurso, accion, descripcion) VALUES
 ('OBJETO.CONSULTAR','objeto','consultar','Consultar objetos y su trazabilidad'),
 ('OBJETO.REGISTRAR','objeto','registrar','Registrar dispositivos'),
 ('OBJETO.ANULAR','objeto','anular','Anular registros erróneos'),
 ('LOTE.GESTIONAR','lote','gestionar','Crear y recomponer lotes'),
 ('SOLICITUD.CREAR','solicitud','crear','Solicitar recolección'),
 ('RECOLECCION.PROGRAMAR','recoleccion','programar','Programar recolecciones'),
 ('RECEPCION.REGISTRAR','recepcion','registrar','Registrar recepciones'),
 ('EVALUACION.REGISTRAR','evaluacion','registrar','Registrar evaluaciones técnicas'),
 ('TRANSFERENCIA.CREAR','transferencia','crear','Despachar transferencias'),
 ('TRANSFERENCIA.CONFIRMAR','transferencia','confirmar','Confirmar recepción de transferencias'),
 ('TRATAMIENTO.REGISTRAR','tratamiento','registrar','Registrar resultados de tratamiento'),
 ('ASIGNACION.REGISTRAR','asignacion','registrar','Asignar equipos a beneficiarios'),
 ('CIERRE.CONFIRMAR','cierre','confirmar','Confirmar cierre de trazabilidad'),
 ('EVIDENCIA.CARGAR','evidencia','cargar','Cargar evidencias'),
 ('EVIDENCIA.VER','evidencia','ver','Ver evidencias según política'),
 ('INVENTARIO.CONSULTAR','inventario','consultar','Consultar inventario'),
 ('RED.GESTIONAR','red','gestionar','Gestionar nodos, aristas, capacidades y escenarios'),
 ('RED.EJECUTAR_FLUJO','red','ejecutar_flujo','Ejecutar análisis de flujo máximo'),
 ('CATALOGO.ADMINISTRAR','catalogo','administrar','Administrar catálogos y parámetros'),
 ('USUARIO.ADMINISTRAR','usuario','administrar','Administrar usuarios y roles'),
 ('AUDITORIA.CONSULTAR','auditoria','consultar','Consultar auditoría'),
 ('GOBIERNO.DECIDIR','gobierno','decidir','Aprobar excepciones y decisiones de arquitectura'),
 ('INDICADOR.CONSULTAR','indicador','consultar','Consultar indicadores');

INSERT INTO seg.rol(codigo, nombre, descripcion, es_servicio) VALUES
 ('USUARIO_BASE','Usuario base','Rol raíz: consulta e indicadores',false);
INSERT INTO seg.rol(codigo, nombre, descripcion, rol_padre_id, es_servicio)
SELECT v.c, v.n, v.d, p.id, v.s FROM (VALUES
  ('GENERADOR','Generador','Registra equipos y solicita recolección','USUARIO_BASE',false),
  ('OPERADOR_CENTRO','Operador de centro','Recibe, verifica e inventaría','USUARIO_BASE',false),
  ('TECNICO_EVALUADOR','Técnico evaluador','Evalúa y clasifica (RN-02)','USUARIO_BASE',false),
  ('GESTOR_TRATAMIENTO','Reacondicionador / reciclador','Confirma recepción y resultado del tratamiento','USUARIO_BASE',false),
  ('BENEFICIARIO','Entidad beneficiaria','Confirma la recepción de equipos','USUARIO_BASE',false),
  ('ADMINISTRADOR','Administrador','Catálogos, usuarios, centros y parámetros','USUARIO_BASE',false),
  ('AUDITOR','Auditor','Lectura de auditoría y evidencias (incluye autoridad ambiental)','USUARIO_BASE',false),
  ('SISTEMA_BATCH','Servicio por lotes','Cálculo de indicadores y alertas','USUARIO_BASE',true)) v(c, n, d, padre, s)
  JOIN seg.rol p ON p.codigo = v.padre;
INSERT INTO seg.rol(codigo, nombre, descripcion, rol_padre_id) SELECT 'COORDINADOR_LOGISTICO','Coordinador logístico',
  'Capacidades, transferencias y flujo; hereda al operador', id FROM seg.rol WHERE codigo = 'OPERADOR_CENTRO';
INSERT INTO seg.rol(codigo, nombre, descripcion, rol_padre_id) SELECT 'COMITE_ARQUITECTURA','Comité de arquitectura',
  'Decide excepciones y cambios; hereda al auditor', id FROM seg.rol WHERE codigo = 'AUDITOR';

INSERT INTO seg.rol_permiso(rol_id, permiso_id)
SELECT r.id, p.id FROM (VALUES
  ('USUARIO_BASE','OBJETO.CONSULTAR'),('USUARIO_BASE','INDICADOR.CONSULTAR'),
  ('GENERADOR','OBJETO.REGISTRAR'),('GENERADOR','LOTE.GESTIONAR'),('GENERADOR','SOLICITUD.CREAR'),('GENERADOR','EVIDENCIA.CARGAR'),
  ('OPERADOR_CENTRO','OBJETO.REGISTRAR'),('OPERADOR_CENTRO','LOTE.GESTIONAR'),('OPERADOR_CENTRO','RECEPCION.REGISTRAR'),
  ('OPERADOR_CENTRO','EVIDENCIA.CARGAR'),('OPERADOR_CENTRO','EVIDENCIA.VER'),('OPERADOR_CENTRO','INVENTARIO.CONSULTAR'),
  ('OPERADOR_CENTRO','TRANSFERENCIA.CONFIRMAR'),
  ('TECNICO_EVALUADOR','EVALUACION.REGISTRAR'),('TECNICO_EVALUADOR','EVIDENCIA.CARGAR'),('TECNICO_EVALUADOR','EVIDENCIA.VER'),
  ('TECNICO_EVALUADOR','INVENTARIO.CONSULTAR'),
  ('COORDINADOR_LOGISTICO','RECOLECCION.PROGRAMAR'),('COORDINADOR_LOGISTICO','TRANSFERENCIA.CREAR'),('COORDINADOR_LOGISTICO','ASIGNACION.REGISTRAR'),
  ('COORDINADOR_LOGISTICO','RED.GESTIONAR'),('COORDINADOR_LOGISTICO','RED.EJECUTAR_FLUJO'),('COORDINADOR_LOGISTICO','CIERRE.CONFIRMAR'),
  ('GESTOR_TRATAMIENTO','TRATAMIENTO.REGISTRAR'),('GESTOR_TRATAMIENTO','TRANSFERENCIA.CONFIRMAR'),('GESTOR_TRATAMIENTO','EVIDENCIA.CARGAR'),
  ('GESTOR_TRATAMIENTO','EVIDENCIA.VER'),('GESTOR_TRATAMIENTO','CIERRE.CONFIRMAR'),('GESTOR_TRATAMIENTO','INVENTARIO.CONSULTAR'),
  ('BENEFICIARIO','TRANSFERENCIA.CONFIRMAR'),('BENEFICIARIO','CIERRE.CONFIRMAR'),('BENEFICIARIO','EVIDENCIA.CARGAR'),
  ('ADMINISTRADOR','CATALOGO.ADMINISTRAR'),('ADMINISTRADOR','USUARIO.ADMINISTRAR'),('ADMINISTRADOR','OBJETO.ANULAR'),
  ('AUDITOR','AUDITORIA.CONSULTAR'),('AUDITOR','EVIDENCIA.VER'),('AUDITOR','INVENTARIO.CONSULTAR'),
  ('COMITE_ARQUITECTURA','GOBIERNO.DECIDIR'),
  ('SISTEMA_BATCH','RED.EJECUTAR_FLUJO')) v(r, p)
  JOIN seg.rol r ON r.codigo = v.r JOIN seg.permiso p ON p.codigo = v.p;

INSERT INTO seg.segregacion_funciones(rol_a_id, rol_b_id, motivo)
SELECT least(a.id, b.id), greatest(a.id, b.id), v.m FROM (VALUES
  ('ADMINISTRADOR','AUDITOR','Quien administra no se audita a sí mismo'),
  ('ADMINISTRADOR','TECNICO_EVALUADOR','Quien gestiona usuarios no clasifica equipos'),
  ('GENERADOR','TECNICO_EVALUADOR','Conflicto de interés: evaluar equipos propios')) v(a, b, m)
  JOIN seg.rol a ON a.codigo = v.a JOIN seg.rol b ON b.codigo = v.b;

INSERT INTO seg.actor_rol_mapeo(actor_negocio_id, rol_id, observacion)
SELECT a.id, r.id, v.o FROM (VALUES
  ('GENERADOR','GENERADOR',NULL),('OPERADOR_CENTRO','OPERADOR_CENTRO',NULL),('TECNICO_EVALUADOR','TECNICO_EVALUADOR',NULL),
  ('COORDINADOR_LOGISTICO','COORDINADOR_LOGISTICO',NULL),('REACONDICIONADOR_RECICLADOR','GESTOR_TRATAMIENTO','Un rol, alcance por centro'),
  ('ENTIDAD_BENEFICIARIA','BENEFICIARIO',NULL),('ADMINISTRADOR','ADMINISTRADOR',NULL),('COMITE_ARQUITECTURA','COMITE_ARQUITECTURA',NULL),
  ('RESPONSABLE_GESTION','COMITE_ARQUITECTURA','Integra el ARB y consume indicadores'),
  ('RESPONSABLE_TECNOLOGICO','ADMINISTRADOR','Administra parámetros y usuarios'),
  ('AUTORIDAD_AMBIENTAL','AUDITOR','Lectura con propósito CUMPLIMIENTO_AMBIENTAL')) v(a, r, o)
  JOIN cat.actor_negocio a ON a.codigo = v.a JOIN seg.rol r ON r.codigo = v.r;

-- ---------------------------------------------------------------------
-- Ecosistemas (dos, para demostrar aislamiento multi-tenant)
-- ---------------------------------------------------------------------
INSERT INTO seg.ecosistema(codigo, nombre, tipo) VALUES
 ('RCM','Red Circular Metropolitana de RAEE','CONSORCIO'),
 ('DEMO2','Ecosistema de prueba de aislamiento','MUNICIPIO');

INSERT INTO org.organizacion(ecosistema_id, codigo, nombre, tipo_persona, sector, canton, parroquia)
SELECT e.id, v.c, v.n, v.t, v.s, 'Quito', v.p FROM seg.ecosistema e, (VALUES
  ('GEN-UNIV','Universidad Andina (sintética)','JURIDICA','ACADEMICO','Iñaquito'),
  ('GEN-MUNI','GAD Municipal Norte (sintético)','JURIDICA','PUBLICO','Calderón'),
  ('GEN-EMP','Comercial Tecno S.A. (sintética)','JURIDICA','PRIVADO','Carcelén'),
  ('RED-OPER','Red Circular — Operación','JURIDICA','COMUNITARIO','Kennedy'),
  ('REACOND','Taller Segunda Vida (sintético)','JURIDICA','PRIVADO','Cotocollao'),
  ('RECICLA','EcoMetales Gestor (sintético)','JURIDICA','PRIVADO','Pomasqui'),
  ('DISPOSIC','Gestor de Disposición Segura (sintético)','JURIDICA','PRIVADO','Pifo'),
  ('BENEF','Fundación Aprende Conectado (sintética)','JURIDICA','COMUNITARIO','Comité del Pueblo')) v(c, n, t, s, p)
 WHERE e.codigo = 'RCM';
INSERT INTO org.organizacion(ecosistema_id, codigo, nombre, tipo_persona, sector, canton, parroquia, organizacion_padre_id)
SELECT ecosistema_id, 'GEN-UNIV-S2', 'Universidad Andina — Sede Sur (sintética)', 'JURIDICA', 'ACADEMICO', 'Quito', 'Quitumbe', id
  FROM org.organizacion WHERE codigo = 'GEN-UNIV';
INSERT INTO org.organizacion(ecosistema_id, codigo, nombre, tipo_persona, sector)
SELECT id, 'GEN-OTRO', 'Generador de otro ecosistema (sintético)', 'JURIDICA', 'PUBLICO' FROM seg.ecosistema WHERE codigo = 'DEMO2';

INSERT INTO org.organizacion_actor(organizacion_id, tipo_actor_id, vigencia)
SELECT o.id, t.id, daterange('2026-09-01', NULL) FROM (VALUES
  ('GEN-UNIV','GENERADOR'),('GEN-UNIV-S2','GENERADOR'),('GEN-MUNI','GENERADOR'),('GEN-EMP','GENERADOR'),('GEN-OTRO','GENERADOR'),
  ('RED-OPER','ACOPIO'),('RED-OPER','EVALUADOR'),('RED-OPER','COORDINADOR_RED'),
  ('REACOND','REACONDICIONADOR'),('RECICLA','RECICLADOR'),('DISPOSIC','GESTOR_DISPOSICION'),('BENEF','BENEFICIARIO'),
  ('GEN-MUNI','BENEFICIARIO')) v(o, t)                      -- el municipio también puede recibir equipos (varios roles)
  JOIN org.organizacion o ON o.codigo = v.o JOIN cat.tipo_actor t ON t.codigo = v.t;

INSERT INTO org.centro(organizacion_id, codigo, nombre, canton, parroquia)
SELECT o.id, v.c, v.n, 'Quito', v.p FROM (VALUES
  ('RED-OPER','C1','Centro de acopio Norte','Carcelén'),('RED-OPER','C2','Centro de acopio Sur','Quitumbe'),
  ('RED-OPER','E1','Laboratorio de evaluación técnica','Kennedy'),('REACOND','R1','Taller de reacondicionamiento','Cotocollao'),
  ('RECICLA','K1','Planta de reciclaje','Pomasqui'),('DISPOSIC','D1','Celda de disposición controlada','Pifo')) v(o, c, n, p)
  JOIN org.organizacion o ON o.codigo = v.o;
INSERT INTO org.centro_funcion(centro_id, tipo_centro_id)
SELECT c.id, t.id FROM (VALUES ('C1','ACOPIO'),('C2','ACOPIO'),('E1','EVALUACION'),('R1','REACONDICIONAMIENTO'),
  ('K1','RECICLAJE'),('D1','DISPOSICION')) v(c, t) JOIN org.centro c ON c.codigo = v.c JOIN cat.tipo_centro t ON t.codigo = v.t;
INSERT INTO org.capacidad_centro(centro_id, tipo_centro_id, capacidad_almacen, capacidad_proceso, unidad_id, periodo, vigencia)
SELECT cf.centro_id, cf.tipo_centro_id, v.a, v.p, u.id, 'SEMANA', tstzrange('2026-09-01', NULL)
  FROM (VALUES ('C1',300,120),('C2',200,90),('E1',150,100),('R1',80,60),('K1',500,150),('D1',1000,40)) v(c, a, p)
  JOIN org.centro c ON c.codigo = v.c JOIN org.centro_funcion cf ON cf.centro_id = c.id JOIN cat.unidad_medida u ON u.codigo = 'UND';

-- Ubicaciones recursivas: raíz por centro + subniveles
INSERT INTO org.ubicacion(centro_id, codigo, nombre, tipo, capacidad_kg)
SELECT id, 'RAIZ', 'Instalaciones ' || codigo, 'RAIZ', NULL FROM org.centro;
INSERT INTO org.ubicacion(centro_id, ubicacion_padre_id, codigo, nombre, tipo, capacidad_kg)
SELECT c.id, u.id, v.cod, v.n, v.t, v.cap FROM (VALUES
  ('C1','BOD-A','Bodega A','BODEGA',3000),('C2','BOD-A','Bodega A','BODEGA',2000),('E1','LAB','Laboratorio','BODEGA',1500),
  ('E1','CUARENTENA','Cuarentena (baterías dañadas)','CUARENTENA',200),('R1','TALLER','Taller','BODEGA',900),
  ('K1','PATIO','Patio de desensamble','BODEGA',8000)) v(c, cod, n, t, cap)
  JOIN org.centro c ON c.codigo = v.c JOIN org.ubicacion u ON u.centro_id = c.id AND u.codigo = 'RAIZ';
INSERT INTO org.ubicacion(centro_id, ubicacion_padre_id, codigo, nombre, tipo)
SELECT u.centro_id, u.id, 'ZONA-1', 'Zona 1', 'ZONA' FROM org.ubicacion u JOIN org.centro c ON c.id = u.centro_id
 WHERE c.codigo = 'C1' AND u.codigo = 'BOD-A';
INSERT INTO org.ubicacion(centro_id, ubicacion_padre_id, codigo, nombre, tipo)
SELECT u.centro_id, u.id, 'EST-01', 'Estante 01', 'ESTANTE' FROM org.ubicacion u JOIN org.centro c ON c.id = u.centro_id
 WHERE c.codigo = 'C1' AND u.codigo = 'ZONA-1';

-- ---------------------------------------------------------------------
-- Usuarios sintéticos (uid fijos para pruebas y demo)
-- ---------------------------------------------------------------------
INSERT INTO seg.usuario(uid, ecosistema_id, organizacion_id, alias, correo, sub_externo)
SELECT v.uid::uuid, o.ecosistema_id, o.id, v.alias, v.alias || '@ejemplo.invalid', 'cognito-' || v.alias FROM (VALUES
  ('00000000-0000-4000-8000-000000000001','gen.universidad','GEN-UNIV'),
  ('00000000-0000-4000-8000-000000000002','gen.municipio','GEN-MUNI'),
  ('00000000-0000-4000-8000-000000000003','operador.c1','RED-OPER'),
  ('00000000-0000-4000-8000-000000000004','operador.c2','RED-OPER'),
  ('00000000-0000-4000-8000-000000000005','operador.e1','RED-OPER'),
  ('00000000-0000-4000-8000-000000000006','tecnico.e1','RED-OPER'),
  ('00000000-0000-4000-8000-000000000007','tecnico.c2','RED-OPER'),
  ('00000000-0000-4000-8000-000000000008','tecnico.r1','REACOND'),
  ('00000000-0000-4000-8000-000000000009','coordinador','RED-OPER'),
  ('00000000-0000-4000-8000-000000000010','gestor.r1','REACOND'),
  ('00000000-0000-4000-8000-000000000011','gestor.k1','RECICLA'),
  ('00000000-0000-4000-8000-000000000012','beneficiario','BENEF'),
  ('00000000-0000-4000-8000-000000000013','admin','RED-OPER'),
  ('00000000-0000-4000-8000-000000000014','auditor','RED-OPER'),
  ('00000000-0000-4000-8000-000000000015','comite','RED-OPER'),
  ('00000000-0000-4000-8000-000000000016','gen.sedesur','GEN-UNIV-S2'),
  ('00000000-0000-4000-8000-000000000017','gen.otro','GEN-OTRO'),
  ('00000000-0000-4000-8000-000000000018','gen.empresa','GEN-EMP')) v(uid, alias, org)
  JOIN org.organizacion o ON o.codigo = v.org;

INSERT INTO seg.usuario_rol(usuario_id, rol_id, centro_id, vigencia, motivo)
SELECT u.id, r.id, c.id, tstzrange('2026-09-01', NULL), 'Carga inicial' FROM (VALUES
  ('gen.universidad','GENERADOR',NULL),('gen.municipio','GENERADOR',NULL),('gen.sedesur','GENERADOR',NULL),('gen.otro','GENERADOR',NULL),
  ('gen.empresa','GENERADOR',NULL),
  ('operador.c1','OPERADOR_CENTRO','C1'),('operador.c2','OPERADOR_CENTRO','C2'),('operador.e1','OPERADOR_CENTRO','E1'),
  ('tecnico.e1','TECNICO_EVALUADOR','E1'),('tecnico.c2','TECNICO_EVALUADOR','C2'),('tecnico.r1','TECNICO_EVALUADOR','R1'),
  ('coordinador','COORDINADOR_LOGISTICO',NULL),('gestor.r1','GESTOR_TRATAMIENTO','R1'),('gestor.k1','GESTOR_TRATAMIENTO','K1'),
  ('beneficiario','BENEFICIARIO',NULL),('admin','ADMINISTRADOR',NULL),('auditor','AUDITOR',NULL),('comite','COMITE_ARQUITECTURA',NULL)) v(u, r, c)
  JOIN seg.usuario u ON u.alias = v.u JOIN seg.rol r ON r.codigo = v.r LEFT JOIN org.centro c ON c.codigo = v.c;

INSERT INTO seg.habilitacion_tecnica(usuario_id, categoria_id, vigencia, evidencia_ref)
SELECT u.id, c.id, daterange('2026-09-01', '2027-09-01'), v.ref FROM (VALUES
  ('tecnico.e1','RAEE','Certificación interna EVA-2026-01'),
  ('tecnico.c2','TIC','Habilitación de preclasificación PRE-2026-02'),
  ('tecnico.r1','PORTATIL','Control de calidad QA-2026-03')) v(u, cat, ref)
  JOIN seg.usuario u ON u.alias = v.u JOIN cat.categoria_raee c ON c.codigo = v.cat;

INSERT INTO evd.politica_acceso(rol_id, tipo_evidencia_id, proposito_id, puede_descargar)
SELECT r.id, t.id, p.id, true FROM (VALUES
  ('OPERADOR_CENTRO','FOTO_RECEPCION','TRAZABILIDAD'),('OPERADOR_CENTRO','ACTA_RECEPCION','TRAZABILIDAD'),
  ('OPERADOR_CENTRO','GUIA_REMISION','TRAZABILIDAD'),
  ('TECNICO_EVALUADOR','FOTO_RECEPCION','EVALUACION_TECNICA'),('TECNICO_EVALUADOR','INFORME_EVALUACION','EVALUACION_TECNICA'),
  ('TECNICO_EVALUADOR','CERTIFICADO_BORRADO','EVALUACION_TECNICA'),
  ('GESTOR_TRATAMIENTO','GUIA_REMISION','TRAZABILIDAD'),('GESTOR_TRATAMIENTO','CERTIFICADO_TRATAMIENTO','TRAZABILIDAD'),
  ('GESTOR_TRATAMIENTO','FOTO_TRATAMIENTO','TRAZABILIDAD'),
  ('COORDINADOR_LOGISTICO','ACTA_ENTREGA','TRAZABILIDAD'),
  ('AUDITOR','ACTA_RECEPCION','AUDITORIA'),('AUDITOR','INFORME_EVALUACION','AUDITORIA'),('AUDITOR','GUIA_REMISION','AUDITORIA'),
  ('AUDITOR','ACTA_ENTREGA','AUDITORIA'),('AUDITOR','CERTIFICADO_TRATAMIENTO','AUDITORIA'),
  ('AUDITOR','CERTIFICADO_TRATAMIENTO','CUMPLIMIENTO_AMBIENTAL'),('AUDITOR','CERTIFICADO_BORRADO','AUDITORIA')) v(r, t, p)
  JOIN seg.rol r ON r.codigo = v.r JOIN cat.tipo_evidencia t ON t.codigo = v.t JOIN cat.proposito_uso p ON p.codigo = v.p;

-- ---------------------------------------------------------------------
-- Gobierno: decisiones (ADR), excepción C2→K1, riesgos
-- ---------------------------------------------------------------------
INSERT INTO gob.decision_arquitectura(codigo, titulo, contexto, decision, consecuencias, materias, estado) VALUES
 ('ADR-001','PostgreSQL 16 en Amazon RDS como fuente transaccional',
  'Se requiere integridad, SQL avanzado, transacciones ACID y despliegue en AWS (RF-BD, RF-CL).',
  'Usar PostgreSQL 16 (RDS Multi-AZ por diseño) con extensiones pgcrypto, btree_gist y ltree.',
  'Restricciones de exclusión para vigencias, RLS nativo, particionamiento declarativo; DynamoDB queda fuera del núcleo.','{BD,NUBE}','APROBADA'),
 ('ADR-002','Supertipo OBJETO_TRAZABLE con subtipos DISPOSITIVO y LOTE',
  'RN-01 exige identificador e historial para dispositivo o lote; el EER de la Fase 1 los trataba por separado.',
  'Especialización total y disjunta implementada con discriminador y FK compuesta (id, tipo_objeto).',
  'Un único historial, una única máquina de estados y lotes anidados sin duplicar lógica.','{BD,MD}','APROBADA'),
 ('ADR-003','Diccionario maestro común a las cinco materias',
  'Discretas, BD y AE usaban nombres y conjuntos distintos (categoría/condición, 9 estados sin RECIBIDO, 7/8/10 roles).',
  'Adoptar "clasificación técnica", 13 estados con RECIBIDO y la relación T de cat.transicion_estado como fuente única.',
  'Matemáticas, BPMN y API leen los mismos catálogos; cambiar una regla es cambiar datos, no código.','{AE,MD,BD,NUBE,INN}','APROBADA'),
 ('ADR-004','Arco C2→K1 por preclasificación técnica en acopio',
  'El arco C2→K1 está en el corte mínimo de E0 y saltaba la evaluación (contradice RN-02).',
  'Permitirlo solo con evaluación en modalidad PRECLASIFICACION por técnico habilitado y excepción aprobada del Comité.',
  'El grafo y la relación T vuelven a ser coherentes; la excepción tiene vigencia y se audita.','{MD,AE,BD}','APROBADA'),
 ('ADR-005','Escritura solo por funciones del esquema api; lectura con RLS',
  'Varias reglas abarcan varias tablas (RN-03, RN-06, RN-08) y deben cumplirse aunque falle la API.',
  'Las cuentas de servicio no tienen INSERT/UPDATE directos; ejecutan funciones SECURITY DEFINER que validan reglas.',
  'Las reglas viven en la base (defensa en profundidad); la API se mantiene delgada.','{BD,NUBE}','APROBADA'),
 ('ADR-006','Capa MCP gobernada desde la base de datos',
  'El frontend incluye un asistente que consulta la plataforma mediante MCP.',
  'Registrar herramientas y recursos en mcp.*, permitir solo funciones/vistas api.*, exigir confirmación en escrituras y dejar fuera del MCP las acciones de alto impacto.',
  'Sin SQL libre ni privilegios extra; toda invocación queda en bitácora.','{NUBE,INN,AE}','APROBADA'),
 ('ADR-007','Auditoría por triggers y sellado periódico',
  'Encadenar el hash fila a fila serializa todas las escrituras.',
  'Hash por fila de auditoría y sello encadenado por periodo (aud.sello_integridad).',
  'Misma capacidad de detectar manipulación sin cuello de botella.','{BD}','APROBADA'),
 ('ADR-008','RN-09: borrado seguro antes de reutilizar',
  'El análisis de Innovación identificó el riesgo de datos residuales en equipos donados.',
  'Ningún equipo con almacenamiento se asigna sin CERTIFICADO_BORRADO vinculado.',
  'Cumple el criterio global 10: el análisis social modifica un requisito.','{INN,BD}','APROBADA'),
 ('ADR-009','Multi-ecosistema con RLS',
  'RNF-05 pide crecer en centros y volúmenes; el escenario admite universidad, municipio o consorcio.',
  'Toda entidad raíz lleva ecosistema_id y las políticas RLS aíslan por ecosistema del contexto.',
  'La misma instancia sirve a varias redes (base del producto CircuTrace) sin rediseñar el núcleo.','{AE,NUBE,BD}','APROBADA');

INSERT INTO gob.excepcion_regla(codigo, regla, descripcion, decision_id, aprobada_por, vigencia, estado)
SELECT 'EXC-001', 'RN-02', 'Envío directo C2→K1 de chatarra preclasificada por técnico habilitado en el acopio sur',
       d.id, u.id, daterange('2026-09-01', '2027-03-01'), 'APROBADA'
  FROM gob.decision_arquitectura d, seg.usuario u WHERE d.codigo = 'ADR-004' AND u.alias = 'comite';

INSERT INTO gob.riesgo(codigo, categoria, descripcion, probabilidad, impacto, control, objeto_bd, estado, materia_origen) VALUES
 ('R-01','PRIVACIDAD','Datos personales residuales en equipos donados',4,5,'RN-09: certificado de borrado obligatorio','ops.fn_validar_asignacion','MITIGADO','INN'),
 ('R-02','PRIVACIDAD','Fotos de recepción con geolocalización del generador',3,4,'Metadatos EXIF/GPS eliminados antes de subir','evd.evidencia.metadatos_limpios','MITIGADO','INN'),
 ('R-03','PODER','Asignación discrecional de equipos a beneficiarios',3,4,'Criterio de asignación obligatorio, auditoría e indicador de beneficiarios','ops.asignacion_beneficiario','MITIGADO','INN'),
 ('R-04','EXCLUSION','Generadores sin conectividad no pueden registrar',3,3,'Entrega directa: el operador registra en el centro','cat.transicion_estado REGISTRADO→RECIBIDO','MITIGADO','INN'),
 ('R-05','SEGURIDAD','Inyección de instrucciones a través del asistente MCP',3,5,'Solo funciones api.*, confirmación en escrituras, roles y límite por minuto','mcp.herramienta','MITIGADO','NUBE'),
 ('R-06','TECNICO','Saturación de aristas críticas del corte mínimo',4,3,'Alerta ARISTA_SATURADA y comparación de escenarios','ind.regla_alerta','ABIERTO','MD'),
 ('R-07','PROPIEDAD','Uso de evidencias para fines no declarados',2,4,'Acceso por propósito explícito y bitácora','evd.politica_acceso','MITIGADO','INN'),
 ('R-08','SOSTENIBILIDAD','Crecimiento de la disposición frente a la recuperación',3,4,'Indicador TASA_DISPOSICION con meta','ind.indicador','ABIERTO','INN'),
 ('R-09','COSTO','Crecimiento de almacenamiento por auditoría',3,2,'Particiones mensuales y archivo a S3 Glacier a los 60 meses','aud.log_cambio','MITIGADO','NUBE');

-- ---------------------------------------------------------------------
-- Red G=(V,E,c): nodos G1–G3, C1, C2, E1, R1, K1, D1, B1
-- Capacidades de demostración (UND/semana). Para reproducir E0–E4 del
-- capítulo de Discretas se cargan sus valores con este mismo formato.
-- ---------------------------------------------------------------------
INSERT INTO red.nodo(ecosistema_id, codigo, nombre, tipo_nodo_id, centro_id, organizacion_id)
SELECT e.id, v.c, v.n, t.id, ce.id, o.id FROM seg.ecosistema e CROSS JOIN (VALUES
  ('G1','Universidad Andina','GENERADOR',NULL,'GEN-UNIV'),('G2','GAD Municipal Norte','GENERADOR',NULL,'GEN-MUNI'),
  ('G3','Comercial Tecno','GENERADOR',NULL,'GEN-EMP'),('C1','Acopio Norte','ACOPIO','C1',NULL),('C2','Acopio Sur','ACOPIO','C2',NULL),
  ('E1','Laboratorio de evaluación','EVALUACION','E1',NULL),('R1','Reacondicionamiento','REACONDICIONAMIENTO','R1',NULL),
  ('K1','Reciclaje','RECICLAJE','K1',NULL),('D1','Disposición controlada','DISPOSICION','D1',NULL),
  ('B1','Fundación Aprende Conectado','BENEFICIARIO',NULL,'BENEF')) v(c, n, t, centro, org)
  JOIN cat.tipo_nodo t ON t.codigo = v.t LEFT JOIN org.centro ce ON ce.codigo = v.centro LEFT JOIN org.organizacion o ON o.codigo = v.org
 WHERE e.codigo = 'RCM';

INSERT INTO red.arista(ecosistema_id, nodo_origen_id, nodo_destino_id, excepcion_id)
SELECT no.ecosistema_id, no.id, nd.id, CASE WHEN v.o = 'C2' AND v.d = 'K1' THEN (SELECT id FROM gob.excepcion_regla WHERE codigo = 'EXC-001') END
  FROM (VALUES ('G1','C1'),('G2','C1'),('G2','C2'),('G3','C2'),('C1','E1'),('C2','E1'),('C2','K1'),('E1','R1'),('E1','K1'),
               ('E1','D1'),('E1','B1'),('R1','B1'),('R1','K1'),('K1','D1')) v(o, d)
  JOIN red.nodo no ON no.codigo = v.o JOIN red.nodo nd ON nd.codigo = v.d;

INSERT INTO red.capacidad_arista(arista_id, capacidad, unidad_id, periodo, vigencia, fuente)
SELECT a.id, v.cap, u.id, 'SEMANA', tstzrange('2026-09-01', NULL), 'Levantamiento AS-IS (sintético)'
  FROM (VALUES ('G1','C1',80),('G2','C1',60),('G2','C2',50),('G3','C2',70),('C1','E1',100),('C2','E1',60),('C2','K1',40),
               ('E1','R1',60),('E1','K1',70),('E1','D1',20),('E1','B1',30),('R1','B1',50),('R1','K1',15),('K1','D1',30)) v(o, d, cap)
  JOIN red.nodo no ON no.codigo = v.o JOIN red.nodo nd ON nd.codigo = v.d
  JOIN red.arista a ON a.nodo_origen_id = no.id AND a.nodo_destino_id = nd.id
  JOIN cat.unidad_medida u ON u.codigo = 'UND';
INSERT INTO red.capacidad_arista(arista_id, capacidad, unidad_id, periodo, vigencia, fuente)  -- segunda unidad en una arista
SELECT a.id, 1800, u.id, 'SEMANA', tstzrange('2026-09-01', NULL), 'Capacidad de carga del vehículo (sintético)'
  FROM red.arista a JOIN red.nodo no ON no.id = a.nodo_origen_id AND no.codigo = 'C1'
  JOIN red.nodo nd ON nd.id = a.nodo_destino_id AND nd.codigo = 'E1' JOIN cat.unidad_medida u ON u.codigo = 'KG';

-- Escenarios recursivos: E1 hereda de E0; E2 hereda de E1; E3 hereda de E0
INSERT INTO red.escenario_red(ecosistema_id, codigo, nombre, descripcion, unidad_id, periodo, estado, creado_por)
SELECT e.id, 'E0', 'Línea base', 'Capacidades vigentes del levantamiento', u.id, 'SEMANA', 'APROBADO', us.id
  FROM seg.ecosistema e, cat.unidad_medida u, seg.usuario us WHERE e.codigo = 'RCM' AND u.codigo = 'UND' AND us.alias = 'coordinador';
INSERT INTO red.escenario_red(ecosistema_id, codigo, nombre, descripcion, escenario_base_id, unidad_id, periodo, estado, creado_por)
SELECT b.ecosistema_id, v.c, v.n, v.d, b.id, b.unidad_id, b.periodo, 'APROBADO', b.creado_por
  FROM (VALUES ('E1','Ampliación del laboratorio','Más capacidad de entrada a evaluación','E0'),
               ('E3','Sin excepción C2→K1','El Comité no renueva la excepción','E0')) v(c, n, d, base)
  JOIN red.escenario_red b ON b.codigo = v.base;
INSERT INTO red.escenario_red(ecosistema_id, codigo, nombre, descripcion, escenario_base_id, unidad_id, periodo, estado, creado_por)
SELECT ecosistema_id, 'E2', 'Ampliación + cierre temporal de R1', 'Hereda E1 y desactiva el taller', id, unidad_id, periodo, 'APROBADO', creado_por
  FROM red.escenario_red WHERE codigo = 'E1';
INSERT INTO red.escenario_arista(escenario_id, arista_id, capacidad_ajustada, activa, motivo)
SELECT s.id, a.id, v.cap, v.act, v.m FROM (VALUES
  ('E1','C1','E1',140,NULL::boolean,'Segundo turno en el laboratorio'),('E1','C2','E1',90,NULL,'Segundo turno en el laboratorio'),
  ('E2','E1','R1',NULL,false,'Taller cerrado'),('E2','R1','B1',NULL,false,'Taller cerrado'),('E2','R1','K1',NULL,false,'Taller cerrado'),
  ('E3','C2','K1',NULL,false,'Excepción no renovada')) v(e, o, d, cap, act, m)
  JOIN red.escenario_red s ON s.codigo = v.e JOIN red.nodo no ON no.codigo = v.o JOIN red.nodo nd ON nd.codigo = v.d
  JOIN red.arista a ON a.nodo_origen_id = no.id AND a.nodo_destino_id = nd.id;

-- ---------------------------------------------------------------------
-- Indicadores y reglas de alerta
-- ---------------------------------------------------------------------
INSERT INTO ind.indicador(codigo, nombre, dimension, materia_origen, formula, fuente, unidad, meta, sentido) VALUES
 ('TRZ_COMPLETA','Dispositivos con trazabilidad completa','OPERATIVA','INT','cerrados / registrados no anulados × 100','ind.fn_calcular_indicadores','%',95,'MAYOR_MEJOR'),
 ('TASA_REUTILIZACION','Tasa de reutilización','AMBIENTAL','INN','cierres REUTILIZACION / cierres × 100','ops.cierre_trazabilidad','%',30,'MAYOR_MEJOR'),
 ('TASA_RECICLAJE','Tasa de reciclaje','AMBIENTAL','INN','cierres RECICLAJE / cierres × 100','ops.cierre_trazabilidad','%',NULL,'RANGO'),
 ('TASA_DISPOSICION','Tasa de disposición','AMBIENTAL','INN','cierres DISPOSICION / cierres × 100','ops.cierre_trazabilidad','%',10,'MENOR_MEJOR'),
 ('KG_MATERIAL_RECUPERADO','Material recuperado','AMBIENTAL','INN','Σ fracciones recuperadas','ops.tratamiento_fraccion','kg',NULL,'MAYOR_MEJOR'),
 ('DIAS_CICLO_PROMEDIO','Tiempo promedio de ciclo','OPERATIVA','AE','promedio(cerrado_en − registrado_en)','trz.objeto_trazable','días',30,'MENOR_MEJOR'),
 ('BENEFICIARIOS_ATENDIDOS','Beneficiarios atendidos','SOCIAL','INN','beneficiarios distintos con cierres de reutilización','ops.cierre_trazabilidad','organizaciones',NULL,'MAYOR_MEJOR'),
 ('FOTOS_SIN_METADATOS_PCT','Fotos sin metadatos de ubicación','SOCIAL','INN','fotos limpias / fotos × 100','evd.evidencia','%',100,'MAYOR_MEJOR'),
 ('UTILIZACION_RED_PROMEDIO','Utilización promedio de la red','TECNICA','MD','promedio de utilización de aristas en el periodo','api.v1_utilizacion_arista','%',NULL,'RANGO');
INSERT INTO ind.regla_alerta(codigo, nombre, severidad, condicion, umbral) VALUES
 ('ARISTA_SATURADA','Arista cerca de su capacidad','ALTA','utilización del periodo ≥ umbral',90),
 ('OBJETO_ESTANCADO','Objeto sin avanzar','MEDIA','días en el mismo estado ≥ umbral',15);

-- ---------------------------------------------------------------------
-- Registro MCP (herramientas y recursos) y privilegios derivados
-- ---------------------------------------------------------------------
INSERT INTO mcp.herramienta(nombre, titulo, descripcion, tipo, objeto_sql, esquema_entrada, requiere_confirmacion, limite_por_minuto) VALUES
 ('consultar_trazabilidad','Consultar trazabilidad','Devuelve la línea de trazabilidad completa de un objeto por su código.','LECTURA','api.fn_linea_trazabilidad',
  '{"type":"object","properties":{"codigo":{"type":"string"}},"required":["codigo"]}',false,60),
 ('buscar_objetos','Buscar objetos','Lista objetos visibles para el usuario filtrando por estado, clasificación, categoría o centro.','LECTURA','api.v1_objeto',
  '{"type":"object","properties":{"estado":{"type":"string"},"clasificacion":{"type":"string"},"categoria":{"type":"string"},"centro":{"type":"string"},"limite":{"type":"integer","maximum":200}}}',false,60),
 ('consultar_inventario','Consultar inventario','Saldos por centro, ubicación, categoría y clasificación.','LECTURA','api.v1_inventario',
  '{"type":"object","properties":{"centro":{"type":"string"}}}',false,60),
 ('utilizacion_red','Utilización de la red','Capacidad y consumo de cada arista en el periodo actual.','LECTURA','api.v1_utilizacion_arista',
  '{"type":"object","properties":{}}',false,30),
 ('ejecutar_flujo_maximo','Ejecutar flujo máximo','Lee el dataset de un escenario desde RDS para que el módulo matemático calcule flujo y cortes.','ANALISIS','api.fn_dataset_flujo',
  '{"type":"object","properties":{"escenario":{"type":"string"}},"required":["escenario"]}',false,10),
 ('registrar_resultado_flujo','Registrar resultado de flujo','Guarda flujo por arista y cortes mínimos; rechaza si el dataset cambió.','ESCRITURA','api.fn_registrar_resultado_flujo',
  '{"type":"object","properties":{"escenario":{"type":"string"},"hash":{"type":"string"},"flujo_maximo":{"type":"number"},"flujos":{"type":"array"},"cortes":{"type":"array"}},"required":["escenario","hash","flujo_maximo","flujos","cortes"]}',true,10),
 ('comparar_escenarios','Comparar escenarios','Último resultado por escenario: flujo máximo, aristas saturadas y número de cortes.','ANALISIS','api.v1_resultado_flujo',
  '{"type":"object","properties":{"escenarios":{"type":"array","items":{"type":"string"}}}}',false,30),
 ('consultar_indicadores','Consultar indicadores','Último valor de cada indicador y si cumple su meta.','LECTURA','api.v1_indicador',
  '{"type":"object","properties":{"dimension":{"type":"string"}}}',false,30),
 ('alertas_abiertas','Alertas abiertas','Alertas pendientes de atención.','LECTURA','api.v1_alerta_abierta','{"type":"object","properties":{}}',false,30),
 ('explicar_entidad','Explicar entidad','Describe una tabla del modelo con sus atributos desde el diccionario de datos.','LECTURA','api.v1_diccionario',
  '{"type":"object","properties":{"tabla":{"type":"string"}},"required":["tabla"]}',false,60),
 ('registrar_dispositivo','Registrar dispositivo','Registra un dispositivo nuevo (requiere confirmación del usuario).','ESCRITURA','api.fn_registrar_dispositivo',
  '{"type":"object","properties":{"codigo":{"type":"string"},"categoria":{"type":"string"},"peso_kg":{"type":"number"},"atributos":{"type":"object"}},"required":["codigo","categoria","peso_kg"]}',true,10),
 ('solicitar_recoleccion','Solicitar recolección','Crea una solicitud de recolección para objetos del generador (requiere confirmación).','ESCRITURA','api.fn_solicitar_recoleccion',
  '{"type":"object","properties":{"objetos":{"type":"array","items":{"type":"string","format":"uuid"}},"centro_destino":{"type":"string"}},"required":["objetos","centro_destino"]}',true,10);

INSERT INTO mcp.herramienta_rol(herramienta_id, rol_id)
SELECT h.id, r.id FROM (VALUES
  ('consultar_trazabilidad','USUARIO_BASE'),('buscar_objetos','USUARIO_BASE'),('consultar_indicadores','USUARIO_BASE'),
  ('explicar_entidad','USUARIO_BASE'),('consultar_inventario','OPERADOR_CENTRO'),('consultar_inventario','TECNICO_EVALUADOR'),
  ('consultar_inventario','AUDITOR'),('utilizacion_red','COORDINADOR_LOGISTICO'),('utilizacion_red','COMITE_ARQUITECTURA'),
  ('ejecutar_flujo_maximo','COORDINADOR_LOGISTICO'),('registrar_resultado_flujo','COORDINADOR_LOGISTICO'),
  ('comparar_escenarios','COORDINADOR_LOGISTICO'),('comparar_escenarios','COMITE_ARQUITECTURA'),
  ('alertas_abiertas','OPERADOR_CENTRO'),('alertas_abiertas','COMITE_ARQUITECTURA'),
  ('registrar_dispositivo','GENERADOR'),('registrar_dispositivo','OPERADOR_CENTRO'),('solicitar_recoleccion','GENERADOR')) v(h, r)
  JOIN mcp.herramienta h ON h.nombre = v.h JOIN seg.rol r ON r.codigo = v.r;

INSERT INTO mcp.recurso(uri_plantilla, nombre, descripcion, objeto_sql) VALUES
 ('ecoraee://objeto/{codigo}','Ficha de trazabilidad','Objeto con su historial, evaluación vigente y cierre','api.fn_mcp_leer_recurso'),
 ('ecoraee://diccionario/{tabla}','Diccionario de una tabla','Atributos, tipos, claves y descripciones','api.fn_mcp_leer_recurso'),
 ('ecoraee://glosario','Glosario maestro','Términos comunes a las cinco materias','api.fn_mcp_leer_recurso'),
 ('ecoraee://escenario/{codigo}','Resultado de escenario','Último flujo máximo y cortes mínimos','api.fn_mcp_leer_recurso');

-- Privilegios del rol MCP = exactamente lo registrado (mínimo privilegio derivado de datos)
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT DISTINCT objeto_sql FROM (SELECT objeto_sql FROM mcp.herramienta UNION SELECT objeto_sql FROM mcp.recurso) x LOOP
    IF to_regclass(r.objeto_sql) IS NOT NULL THEN
      EXECUTE format('GRANT SELECT ON %s TO ecoraee_mcp', r.objeto_sql);
    ELSE
      EXECUTE (SELECT string_agg(format('GRANT EXECUTE ON FUNCTION %s TO ecoraee_mcp', p.oid::regprocedure), '; ')
                 FROM pg_proc p WHERE p.oid::regproc::text = r.objeto_sql
                    OR (p.pronamespace::regnamespace::text || '.' || p.proname) = r.objeto_sql);
    END IF;
  END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION api.fn_iniciar_contexto(uuid, text, text), api.fn_mcp_autorizar(text, jsonb, text),
                          api.fn_mcp_registrar(text, text, jsonb, text, integer, integer, text) TO ecoraee_mcp;
GRANT SELECT ON api.v1_mcp_catalogo TO ecoraee_mcp;

-- ---------------------------------------------------------------------
-- Diccionario: dominios, sincronización y clasificación de entidades
-- ---------------------------------------------------------------------
INSERT INTO meta.dominio(esquema, nombre, descripcion, propietario_negocio, custodio_tecnico) VALUES
 ('meta','Metadatos','Diccionario de datos y glosario maestro','Comité de arquitectura','Administrador de datos'),
 ('cat','Catálogos','Diccionario maestro de valores y reglas parametrizables','Comité de arquitectura','Administrador de datos'),
 ('seg','Seguridad','Identidad, roles, permisos y ecosistemas','Responsable tecnológico','Administrador de datos'),
 ('org','Organizaciones','Actores, centros y ubicaciones','Coordinador logístico','Administrador de datos'),
 ('trz','Trazabilidad','Objetos trazables e historial de estados','Responsable de gestión','Administrador de datos'),
 ('ops','Operaciones','Documentos del ciclo de vida','Coordinador logístico','Administrador de datos'),
 ('inv','Inventario','Kardex y saldos','Operador de centro','Administrador de datos'),
 ('evd','Evidencias','Metadatos de evidencias en S3 y su acceso','Responsable de gestión','Arquitecto cloud'),
 ('red','Red','Grafo, capacidades, escenarios y resultados de flujo','Coordinador logístico','Analista de red'),
 ('ind','Indicadores','Indicadores y alertas','Responsable de gestión','Administrador de datos'),
 ('gob','Gobierno','Decisiones, excepciones y riesgos del ARB','Comité de arquitectura','Arquitecto empresarial'),
 ('aud','Auditoría','Auditoría técnica y de seguridad','Auditor','Administrador de datos'),
 ('mcp','MCP','Herramientas, recursos y bitácora del servidor MCP','Responsable tecnológico','Arquitecto cloud'),
 ('integ','Integración','Idempotencia y outbox de eventos','Responsable tecnológico','Arquitecto cloud');

DO $$ BEGIN PERFORM meta.fn_sincronizar_diccionario(); END $$;

UPDATE meta.entidad e SET tipo_entidad = v.t
  FROM (VALUES ('objeto_trazable','SUPERTIPO'),('documento_operativo','SUPERTIPO'),
               ('dispositivo','SUBTIPO'),('lote','SUBTIPO'),('solicitud_recoleccion','SUBTIPO'),('recoleccion','SUBTIPO'),('recepcion','SUBTIPO'),
               ('evaluacion_tecnica','SUBTIPO'),('transferencia','SUBTIPO'),('tratamiento','SUBTIPO'),('asignacion_beneficiario','SUBTIPO'),
               ('cierre_trazabilidad','SUBTIPO'),
               ('evaluacion_criterio','DEBIL'),('tratamiento_fraccion','DEBIL'),('documento_item','DEBIL'),('resultado_flujo_arista','DEBIL'),
               ('corte_minimo','DEBIL'),('corte_minimo_arista','DEBIL'),('escenario_arista','DEBIL'),('escenario_nodo','DEBIL'),
               ('rol_permiso','ASOCIATIVA'),('centro_funcion','ASOCIATIVA'),('clasificacion_destino_permitido','ASOCIATIVA'),
               ('politica_acceso','ASOCIATIVA'),('evidencia_vinculo','ASOCIATIVA'),('herramienta_rol','ASOCIATIVA'),('actor_rol_mapeo','ASOCIATIVA'),
               ('segregacion_funciones','ASOCIATIVA'),('arista_tipo_permitida','ASOCIATIVA'),('lote_genealogia','ASOCIATIVA'),
               ('usuario_rol','TEMPORAL'),('organizacion_actor','TEMPORAL'),('capacidad_centro','TEMPORAL'),('capacidad_arista','TEMPORAL'),
               ('lote_composicion','TEMPORAL'),('habilitacion_tecnica','TEMPORAL'),('parametro_sistema','TEMPORAL'),
               ('historial_estado','BITACORA'),('movimiento_inventario','BITACORA'),('log_cambio','BITACORA'),('acceso_evidencia','BITACORA'),
               ('invocacion','BITACORA'),('evento_seguridad','BITACORA'),('outbox_evento','BITACORA'),('medicion_indicador','BITACORA'),
               ('sello_integridad','BITACORA'),('idempotencia','BITACORA')) v(n, t)
 WHERE e.nombre_tabla = v.n;
UPDATE meta.entidad e SET tipo_entidad = 'CATALOGO' FROM meta.dominio d WHERE d.id = e.dominio_id AND d.esquema = 'cat' AND e.tipo_entidad = 'FUERTE';
UPDATE meta.entidad e SET tipo_entidad = 'METADATO' FROM meta.dominio d WHERE d.id = e.dominio_id AND d.esquema = 'meta';
UPDATE meta.entidad e SET clasificacion_datos = 'PUBLICO' FROM meta.dominio d WHERE d.id = e.dominio_id AND d.esquema IN ('cat','meta');
UPDATE meta.entidad SET clasificacion_datos = 'CONFIDENCIAL' WHERE nombre_tabla IN ('usuario','evidencia','acceso_evidencia','asignacion_beneficiario','log_cambio','evento_seguridad','invocacion');
UPDATE meta.entidad SET clasificacion_datos = 'RESTRINGIDO' WHERE nombre_tabla IN ('habilitacion_tecnica');
UPDATE meta.entidad SET retencion = CASE tipo_entidad WHEN 'BITACORA' THEN '60 meses en línea; luego S3 Glacier' WHEN 'CATALOGO' THEN 'Indefinida (baja lógica)'
                                    ELSE 'Mientras el ecosistema esté activo + 60 meses' END;
UPDATE meta.atributo a SET es_pii = true FROM meta.entidad e WHERE e.id = a.entidad_id
   AND (e.nombre_tabla, a.nombre_columna) IN (('usuario','correo'),('usuario','sub_externo'),('usuario','hash_credencial'),('evento_seguridad','ip_hash'));
UPDATE meta.entidad SET expuesta_mcp = true WHERE nombre_tabla IN
  ('objeto_trazable','dispositivo','lote','historial_estado','saldo_ubicacion','arista','capacidad_arista','escenario_red','ejecucion_flujo',
   'resultado_flujo_arista','corte_minimo','indicador','medicion_indicador','alerta');

INSERT INTO meta.version_esquema(version, descripcion, script) VALUES
 ('1.0.0','Modelo final: estructura','01_estructura.sql'),('1.0.1','Lógica de dominio y reglas RN','02_logica.sql'),
 ('1.0.2','Contrato api y capa MCP','03_api_mcp.sql'),('1.0.3','Seguridad, índices y diccionario','04_seguridad_indices_diccionario.sql'),
 ('1.0.4','Datos semilla sintéticos','05_semillas.sql');

-- ---------------------------------------------------------------------
-- Glosario maestro (diccionario común a las cinco materias)
-- ---------------------------------------------------------------------
INSERT INTO meta.termino_glosario(termino, definicion, sinonimos, termino_ae, termino_md, termino_bd, termino_nube, termino_inn, entidad_ref) VALUES
 ('Objeto trazable','Todo lo que tiene identificador único e historial: un dispositivo o un lote.','{"ítem"}','Objeto de negocio "Equipo/Lote"','Elemento x ∈ X','trz.objeto_trazable','Recurso /objetos de la API','Bien recuperado','trz.objeto_trazable'),
 ('Clasificación técnica','Resultado de la evaluación: reutilizable, reparable, reciclable o no recuperable.','{"condición","categoría (Discretas)"}','Resultado de la tarea Evaluar','Conjunto K','cat.clasificacion_tecnica','—','Criterio de elegibilidad para donación','cat.clasificacion_tecnica'),
 ('Categoría RAEE','Tipo de aparato (laptop, monitor…) organizado en árbol.','{"tipo de equipo"}','Catálogo de equipos','Conjunto C','cat.categoria_raee','—','—','cat.categoria_raee'),
 ('Estado','Etapa del ciclo de vida de un objeto trazable (13 estados; DESAGRUPADO solo para lotes).','{"etapa"}','Estado del objeto en el BPMN','Conjunto S','cat.estado_trazabilidad','—','—','cat.estado_trazabilidad'),
 ('Transición','Paso permitido entre dos estados, con permiso y requisitos.','{"cambio de estado"}','Flujo de secuencia del BPMN','Relación T ⊆ S×S','cat.transicion_estado','Validación en API','—','cat.transicion_estado'),
 ('Nodo','Centro (por función) u organización generadora/beneficiaria en la red.','{"vértice"}','Ubicación / actor','v ∈ V','red.nodo','—','Actor del ecosistema','red.nodo'),
 ('Arista','Conexión dirigida por la que pueden moverse objetos entre dos nodos.','{"arco","ruta"}','Flujo logístico','(u,v) ∈ E','red.arista','—','—','red.arista'),
 ('Capacidad','Máximo de unidades o kg por periodo que admite una arista.','{"c(u,v)"}','Capacidad logística','c: E → ℝ≥0','red.capacidad_arista','—','—','red.capacidad_arista'),
 ('Escenario','Variante de capacidades o actividad de la red para comparar resultados.','{"E0…E4"}','Escenario de transición','Red G_k','red.escenario_red','—','Escenario futuro','red.escenario_red'),
 ('Corte mínimo','Conjunto de aristas de menor capacidad total que separa fuentes de sumideros; puede haber varios.','{"cuello de botella"}','Brecha de capacidad','(S, T) mínimo','red.corte_minimo','Alarma de saturación','—','red.corte_minimo'),
 ('Evidencia','Archivo que respalda una operación; se guarda en S3 con su huella SHA-256.','{"soporte"}','Objeto de datos "Evidencia"','—','evd.evidencia','Bucket S3 privado','Dato potencialmente personal','evd.evidencia'),
 ('Cierre de trazabilidad','Confirmación del destino final con fecha y evidencia (RN-08).','{"destino final"}','Evento de fin del proceso','Estado final de S','ops.cierre_trazabilidad','—','Resultado social/ambiental','ops.cierre_trazabilidad'),
 ('Documento operativo','Registro de una operación (solicitud, recepción, evaluación, transferencia, tratamiento, asignación, cierre).','{"transacción"}','Objeto de datos del BPMN','—','ops.documento_operativo','Endpoint de comando','—','ops.documento_operativo'),
 ('Rol','Conjunto de permisos asignado a un usuario con alcance y vigencia.','{"perfil"}','Actor de negocio','Conjunto A','seg.rol','Grupo IAM / Cognito','Distribución de poder','seg.rol'),
 ('Ecosistema','Red circular completa (universidad, municipio, consorcio) aislada por RLS.','{"tenant"}','Empresa extendida','—','seg.ecosistema','Cuenta / entorno','Comunidad','seg.ecosistema'),
 ('Lote','Agrupación de objetos que se operan juntos; a lo sumo un lote por objeto en cada instante.','{"carga"}','Objeto de negocio "Lote"','Clase de equivalencia en un instante t','trz.lote','—','—','trz.lote'),
 ('Herramienta MCP','Operación de la plataforma que el asistente puede invocar con permisos del usuario.','{"tool"}','Servicio de aplicación','—','mcp.herramienta','Servidor MCP en ECS/EC2','Delegación a IA con control humano','mcp.herramienta');
