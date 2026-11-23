// Punto único de datos de la app: todas las rutas de la API en un solo lugar.
import { http, subirEvidencia, subirVideo, subirImagenModelo, token, ApiError, onSesionExpirada } from '../core/http.js';

export const api = {
  // identidad
  login: (correo, password) => http.post('/auth/login', { correo, password }),
  registro: (datos) => http.post('/auth/registro', datos),
  verificarCorreo: (correo, codigo) => http.post('/auth/verificar', { correo, codigo }),
  reenviarCodigo: (correo) => http.post('/auth/reenviar-codigo', { correo }),
  me: () => http.get('/auth/me'),
  cuentasDemo: () => http.get('/auth/demo'),
  organizacionesPublicas: () => http.get('/auth/organizaciones'),
  // catálogos e indicadores
  catalogos: () => http.get('/catalogos'),
  modelos: (filtros) => http.get('/catalogo/modelos', filtros),
  crearModelo: (d) => http.post('/catalogo/modelos', d),
  actualizarModelo: (uid, d) => http.put(`/catalogo/modelos/${uid}`, d),
  reabrirModelo: (uid, motivo) => http.post(`/catalogo/modelos/${uid}/reabrir`, { motivo }),
  imagenModelo: (uid) => http.get(`/catalogo/modelos/${uid}/imagen`),
  subirImagenModelo,
  prediccion: (filtros) => http.get('/prediccion/recoleccion', filtros),
  serieDisponible: (serie, excluir) => http.get('/objetos/serie-disponible', { serie, excluir }),
  objetoPorSerie: (serie) => http.get(`/objetos/serie/${encodeURIComponent(serie)}`),
  fotos: (codigo) => http.get(`/objetos/${encodeURIComponent(codigo)}/fotos`),
  tablero: () => http.get('/tablero'),
  recalcularIndicadores: () => http.post('/indicadores/recalcular'),
  // trazabilidad
  tareas: () => http.get('/tareas'),
  objetos: (filtros) => http.get('/objetos', filtros),
  objeto: (codigo) => http.get(`/objetos/${encodeURIComponent(codigo)}`),
  registrarDispositivo: (d) => http.post('/objetos/dispositivos', d),
  actualizarDispositivo: (uid, d) => http.put(`/objetos/dispositivos/${uid}`, d),
  anularObjeto: (uid, motivo) => http.del(`/objetos/${uid}`, { motivo }),
  crearLote: (d) => http.post('/objetos/lotes', d),
  desagrupar: (uid, observacion) => http.post(`/objetos/lotes/${uid}/desagrupar`, { observacion }),
  // documentos operativos
  documentos: (filtros) => http.get('/documentos', filtros),
  solicitar: (d) => http.post('/documentos/solicitudes', d),
  programar: (uid, d) => http.post(`/documentos/solicitudes/${uid}/programar`, d),
  recibir: (d) => http.post('/documentos/recepciones', d),
  evaluar: (d) => http.post('/documentos/evaluaciones', d),
  transferir: (d) => http.post('/documentos/transferencias', d),
  recibirTransferencia: (uid, d) => http.post(`/documentos/transferencias/${uid}/recibir`, d),
  tratar: (d) => http.post('/documentos/tratamientos', d),
  cerrar: (d) => http.post('/documentos/cierres', d),
  // evidencias
  subirEvidencia,
  descargarEvidencia: (uid, proposito) => http.get(`/evidencias/${uid}/descarga`, { proposito }),
  // red y flujo máximo
  red: () => http.get('/red'),
  analizarEscenario: (codigo) => http.get(`/red/escenarios/${codigo}/flujo`),
  ejecutarEscenario: (codigo) => http.post(`/red/escenarios/${codigo}/flujo`),
  compararEscenarios: () => http.get('/red/comparacion'),
  crearEscenario: (d) => http.post('/red/escenarios', d),
  ajustarArista: (codigo, d) => http.put(`/red/escenarios/${codigo}/aristas`, d),
  ajustarNodo: (codigo, d) => http.put(`/red/escenarios/${codigo}/nodos`, d),
  eliminarEscenario: (codigo) => http.del(`/red/escenarios/${codigo}`),
  // verificación de la base
  verificarConexion: () => http.get('/verificacion/conexion'),
  verificarBase: () => http.get('/verificacion/base'),
  verificarObjeto: (codigo) => http.get(`/verificacion/objetos/${encodeURIComponent(codigo)}`),
  // solicitudes de rol
  solicitudesRol: (pendientes = false) => http.get('/solicitudes-rol', pendientes ? { pendientes: true } : undefined),
  solicitarRol: (d) => http.post('/solicitudes-rol', d),
  cancelarSolicitudRol: (uid) => http.post(`/solicitudes-rol/${uid}/cancelar`),
  resolverSolicitudRol: (uid, d) => http.post(`/solicitudes-rol/${uid}/resolver`, d),
  // capacitación
  contenidos: (filtros) => http.get('/capacitacion', filtros),
  contenido: (uid) => http.get(`/capacitacion/${uid}`),
  miActividad: () => http.get('/capacitacion/actividad'),
  subirVideo,
  publicar: (d) => http.post('/capacitacion', d),
  reaccionar: (uid) => http.post(`/capacitacion/${uid}/reaccion`),
  comentar: (uid, texto) => http.post(`/capacitacion/${uid}/comentarios`, { texto }),
  moderar: (uid, estado) => http.post(`/capacitacion/${uid}/moderacion`, { estado }),
  // gobierno
  cambios: (filtros) => http.get('/auditoria/cambios', filtros),
  objetoEn: (codigo, instante) => http.get(`/auditoria/objetos/${encodeURIComponent(codigo)}/en`, { instante }),
  bitacoraMcp: () => http.get('/auditoria/mcp'),
  eventosSeguridad: () => http.get('/auditoria/seguridad'),
  decisiones: () => http.get('/gobierno/decisiones'),
  usuarios: () => http.get('/usuarios'),
  asignarRol: (uid, d) => http.post(`/usuarios/${uid}/roles`, d),
  revocarRol: (uid, rol, motivo) => http.post(`/usuarios/${uid}/roles/${rol}/revocar`, { motivo }),
  // asistente MCP
  herramientas: () => http.get('/asistente/herramientas'),
  ejecutarHerramienta: (d) => http.post('/asistente/ejecutar', d),
  chat: (d) => http.post('/asistente/chat', d),
};

export { token, ApiError, onSesionExpirada };
export * from '../core/formato.js';
export { ICONS } from '../core/icons.js';
export { STATS, MANIFESTO, STEPS, DESTINIES, PLATFORM, GALLERY, ESTADOS_PUBLICOS, CAPACITACION_PUBLICA, photo, coverFor, fotoTema } from '../core/story.js';
