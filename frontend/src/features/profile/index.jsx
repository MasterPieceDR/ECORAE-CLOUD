import { PageHeader } from '@/shared/ui/PageHeader';
import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { motion } from 'motion/react';
import { useAuth, useCatalogos } from '@/features/auth';
import { api, formatDay, formatDate } from '@/shared/api';
import { useAsync } from '@/shared/hooks/useAsync';
import { Avatar } from '@/shared/ui/Avatar';
import { Icon } from '@/shared/ui/Icon';
import { ContenidoCard } from '@/features/capacitacion/ContenidoCard';
import { SolicitarAcceso } from '@/features/usuarios/Solicitudes';
import './profile.css';

const TABS = [['acceso', 'Roles y permisos'], ['contenidos', 'Mis contenidos'], ['comentarios', 'Mis comentarios']];

export function ProfilePage() {
  const { user, logout } = useAuth();
  const { nombreRol, nombreCentro } = useCatalogos();
  const [tab, setTab] = useState('acceso');
  const { data } = useAsync(() => api.miActividad(), [user.uid]);
  const navigate = useNavigate();
  const porRecurso = {};
  user.permisos.forEach((p) => { const [r] = p.codigo.split('.'); (porRecurso[r] ??= []).push(p); });
  return (
    <>
      <PageHeader title={user.alias} description={`${user.organizacion?.nombre ?? ''} · desde ${formatDay(user.desde)}`} action={<Avatar name={user.alias} large />} />
      <div className="pf-tabs" role="tablist">
        {TABS.map(([k, label]) => (
          <button key={k} role="tab" aria-selected={tab === k} onClick={() => setTab(k)}>{label}{tab === k && <motion.i layoutId="pf-line" />}</button>
        ))}
      </div>
      {tab === 'acceso' && (
        <div className="pf-grid">
          <section className="card pf-config">
            <h2 className="detail__h2">Cuenta</h2>
            <dl className="facts">
              <div><dt>Alias (seudónimo)</dt><dd>{user.alias}</dd></div>
              <div><dt>Proveedor de identidad</dt><dd>{user.proveedor === 'COGNITO' ? 'Amazon Cognito' : 'Local (MVP)'} · MFA {user.mfa ? 'activo' : 'no activo'}</dd></div>
              <div><dt>Roles asignados</dt><dd>{user.roles.map((r) => <span key={r.codigo + r.centro} className="chip-link">{nombreRol(r.codigo)}{r.centro ? ` · ${nombreCentro(r.centro)}` : ' · todos los centros'}</span>)}</dd></div>
              <div><dt>Roles heredados</dt><dd>{user.roles_efectivos.filter((r) => !user.roles.some((x) => x.codigo === r)).map(nombreRol).join(', ') || '—'}</dd></div>
            </dl>
            <p className="hint">Tu correo no se muestra: la base lo protege por columna (RNF-10). Los roles los asigna el administrador con motivo y vigencia; puedes pedirlos abajo.</p>
            <button className="btn btn--ghost" onClick={() => logout().then(() => navigate('/'))}><Icon name="logout" size={18} /> Cerrar sesión</button>
          </section>
          <section className="card">
            <h2 className="detail__h2">Permisos efectivos ({user.permisos.length})</h2>
            <div className="perms">
              {Object.entries(porRecurso).sort().map(([r, ps]) => (
                <div key={r}><b>{r}</b>{ps.map((p) => <span key={p.codigo + p.centro} className="perm">{p.codigo.split('.')[1].toLowerCase().replace('_', ' ')}{p.centro ? ` · ${p.centro}` : ''}</span>)}</div>
              ))}
            </div>
          </section>
          <SolicitarAcceso />
        </div>
      )}
      {tab === 'contenidos' && (
        <div className="vgrid">
          {data?.contenidos.map((v, i) => <ContenidoCard key={v.uid} c={{ ...v, autor: user.alias, organizacion_autor: user.organizacion?.nombre }} index={i} />)}
          {data?.contenidos.length === 0 && <p className="empty">Aún no publicas contenidos. <Link to="/app/capacitacion/publicar">Publicar uno</Link></p>}
        </div>
      )}
      {tab === 'comentarios' && (
        <ul className="pf-comments">
          {data?.comentarios.map((c) => <li key={c.uid} className="card"><Link to={`/app/capacitacion/${c.contenido_uid}`}><b>{c.contenido_titulo}</b></Link><p>{c.texto}</p><small>{formatDate(c.creado_en)}</small></li>)}
          {data?.comentarios.length === 0 && <li className="empty">Todavía no has comentado.</li>}
        </ul>
      )}
    </>
  );
}
