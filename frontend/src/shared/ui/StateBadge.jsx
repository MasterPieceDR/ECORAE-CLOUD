import { useCatalogos } from '@/features/auth';
import { StatusBadge } from './StatusBadge';
export function StateBadge({ state }) { const { nombreEstado } = useCatalogos(); return <StatusBadge state={state} label={nombreEstado(state)} />; }
export function ClasBadge({ value }) { const { nombreClasificacion } = useCatalogos(); return <StatusBadge value={value} label={value ? nombreClasificacion(value) : 'Sin evaluar'} />; }
