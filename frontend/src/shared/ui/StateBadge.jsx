import { TONO_ESTADO, TONO_CLASIFICACION } from '@/shared/api';
import { useCatalogos } from '@/features/auth';

export function StateBadge({ state }) {
  const { nombreEstado } = useCatalogos();
  return <span className="badge" data-tone={TONO_ESTADO[state] ?? 'gray'}>{nombreEstado(state)}</span>;
}

export function ClasBadge({ value }) {
  const { nombreClasificacion } = useCatalogos();
  if (!value) return <span className="badge" data-tone="gray">Sin evaluar</span>;
  return <span className="badge" data-tone={TONO_CLASIFICACION[value] ?? 'gray'}>{nombreClasificacion(value)}</span>;
}
