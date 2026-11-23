import { Icon } from './Icon';
import { TONO_ESTADO, TONO_CLASIFICACION } from '@/shared/api';
const tonos = { lime: 'success', sun: 'warning', coral: 'danger', sky: 'info', gray: 'neutral' };
const iconos = { success: 'check', warning: 'clock', danger: 'close', info: 'info', neutral: 'circle' };
export function StatusBadge({ state, value, label, tone, icon }) {
  const codigo = state || value;
  const tipo = tone || (codigo === 'CERRADO' ? 'success' : null) || tonos[TONO_ESTADO[codigo] || TONO_CLASIFICACION[codigo]] || 'neutral';
  return <span className="status-badge" data-status={tipo}><Icon name={icon || iconos[tipo] || 'circle'} size={16} /><span>{label || codigo || 'Sin evaluar'}</span></span>;
}
