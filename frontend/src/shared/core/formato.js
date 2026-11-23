// Formatos y etiquetas de interfaz. Los nombres de negocio vienen del catálogo de la base (ADR-003);
// aquí solo hay presentación (colores, iconos, textos cortos).

export const formatNumber = (n) => (n >= 1000 ? `${(n / 1000).toFixed(1).replace('.0', '')}K` : String(n ?? 0));
export const formatDate = (iso) => (iso ? new Date(iso).toLocaleString('es-EC', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—');
export const formatDay = (iso) => (iso ? new Date(iso).toLocaleDateString('es-EC', { day: '2-digit', month: 'short', year: 'numeric' }) : '—');
export const formatKg = (n) => (n == null ? '—' : `${Number(n).toLocaleString('es-EC', { maximumFractionDigits: 2 })} kg`);
export const formatBytes = (n) => (n > 1048576 ? `${(n / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`);
export const initials = (name = '') => name.split(/[\s._-]+/).filter(Boolean).map((w) => w[0]).slice(0, 2).join('').toUpperCase();
export const desdeHace = (iso) => {
  if (!iso) return '';
  const s = (Date.now() - new Date(iso).getTime()) / 1000;
  if (s < 60) return 'hace un momento';
  if (s < 3600) return `hace ${Math.round(s / 60)} min`;
  if (s < 86400) return `hace ${Math.round(s / 3600)} h`;
  return `hace ${Math.round(s / 86400)} d`;
};

export const TONO_ESTADO = {
  REGISTRADO: 'gray', RECOLECCION_SOLICITADA: 'sky', EN_RECOLECCION: 'sky', RECIBIDO: 'sky', EN_EVALUACION: 'sun',
  CLASIFICADO: 'sun', EN_TRANSFERENCIA: 'sky', EN_TRATAMIENTO: 'sun', TRATADO: 'lime', ASIGNADO_BENEFICIARIO: 'lime',
  CERRADO: 'gray', ANULADO: 'coral', DESAGRUPADO: 'gray',
};
export const TONO_CLASIFICACION = { REUTILIZABLE: 'lime', REPARABLE: 'sun', RECICLABLE: 'sky', NO_RECUPERABLE: 'coral', PENDIENTE: 'gray' };

export const DOCUMENTO = {
  SOLICITUD: 'Solicitud de recolección', RECOLECCION: 'Recolección', RECEPCION: 'Recepción', EVALUACION: 'Evaluación técnica',
  TRANSFERENCIA: 'Transferencia', TRATAMIENTO: 'Tratamiento', ASIGNACION: 'Asignación', CIERRE: 'Cierre', AJUSTE: 'Ajuste',
};

export const ICONO_ACCION = {
  SOLICITAR_RECOLECCION: 'truck', PROGRAMAR_RECOLECCION: 'calendar', RECIBIR: 'inbox', EVALUAR: 'wrench', CERTIFICAR_BORRADO: 'shield',
  TRANSFERIR: 'arrow', RECIBIR_TRANSFERENCIA: 'check', REGISTRAR_TRATAMIENTO: 'recycle', CERRAR: 'flag', DESAGRUPAR: 'layers', EDITAR: 'file', ANULAR: 'close',
};

export const TEMA = { CONCEPTOS: 'Conceptos', RECICLAJE: 'Reciclaje', REPARACION: 'Reparación', COMUNIDAD: 'Comunidad', SEGURIDAD_DATOS: 'Seguridad de datos' };

export const TIPO_NODO = {
  GENERADOR: 'Generador', ACOPIO: 'Acopio', EVALUACION: 'Evaluación', REACONDICIONAMIENTO: 'Reacondicionamiento',
  RECICLAJE: 'Reciclaje', DISPOSICION: 'Disposición', BENEFICIARIO: 'Beneficiario',
};
