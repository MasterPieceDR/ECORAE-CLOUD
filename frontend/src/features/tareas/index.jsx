import { Link } from 'react-router-dom';
import { motion } from 'motion/react';
import { api, desdeHace, ICONO_ACCION } from '@/shared/api';
import { useAsync } from '@/shared/hooks/useAsync';
import { Skeleton } from '@/shared/ui/Skeleton';
import { Icon } from '@/shared/ui/Icon';
import { StateBadge } from '@/shared/ui/StateBadge';
import { PageHeader } from '@/shared/ui/PageHeader';
import { EmptyState } from '@/shared/ui/EmptyState';
import './tareas.css';

// Bandeja de trabajo: lo que este usuario puede hacer ahora, calculado con sus permisos efectivos y el estado de cada objeto.
export function TareasPage() {
  const { data, loading, error, reload } = useAsync(() => api.tareas());
  return (
    <>
      <PageHeader title="Mis tareas" description="Lo que te toca hacer ahora según tu rol y tu centro." action={<button className="btn btn--ghost btn--sm" onClick={reload}><Icon name="refresh" size={16} /> Actualizar</button>} />
      {error && <p className="error" role="alert">{error.message}</p>}
      {loading && !data ? <Skeleton h={300} /> : <ListaTareas grupos={data?.grupos ?? []} />}
    </>
  );
}

export function ListaTareas({ grupos, compacta = false }) {
  if (!grupos.length) return <EmptyState title="¡Todo al día!" description="No tienes tareas pendientes en este momento." />;
  return (
    <div className={`tareas ${compacta ? 'tareas--compacta' : ''}`}>
      {grupos.map((g, gi) => (
        <motion.section key={g.codigo} className="card tgroup" initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: gi * .05 }}>
          <h2><span><Icon name={ICONO_ACCION[g.codigo] ?? 'arrow'} size={18} /></span>{g.titulo}<b>{g.objetos.length}</b></h2>
          <ul>
            {g.objetos.slice(0, compacta ? 4 : 50).map((o) => (
              <li key={o.codigo}>
                <Link to={`/app/objetos/${o.codigo}?accion=${encodeURIComponent(g.codigo)}`}>
                  <b>{o.codigo}</b>
                  <small>{o.tipo_objeto === 'LOTE' ? 'Lote' : o.categoria_nombre ?? ''}{o.centro_actual ? ` · ${o.centro_actual}` : ''} · {desdeHace(o.ultimo_movimiento)}</small>
                  <StateBadge state={o.estado} /><span className="btn btn--primary btn--sm">{g.titulo} <Icon name="arrow" size={16} /></span>
                </Link>
              </li>
            ))}
          </ul>
          {compacta && g.objetos.length > 4 && <Link to="/app/tareas" className="tgroup__more">Ver las {g.objetos.length}</Link>}
        </motion.section>
      ))}
    </div>
  );
}
