import { PageHeader } from '@/shared/ui/PageHeader';
import { useState } from 'react';
import { api, formatDate } from '@/shared/api';
import { useAuth, useCatalogos } from '@/features/auth';
import { useAsync } from '@/shared/hooks/useAsync';
import { Skeleton } from '@/shared/ui/Skeleton';
import { Icon } from '@/shared/ui/Icon';
import { Modal } from '@/shared/ui/Modal';
import { useToast } from '@/shared/ui/Toast';
import { BandejaSolicitudes } from './Solicitudes';

// Administración de roles (USUARIO.ADMINISTRAR): con motivo, alcance por centro y vigencia; la segregación la valida la base.
export function UsuariosPage() {
  const { user } = useAuth();
  const { nombreRol } = useCatalogos();
  const { data, loading, error, reload } = useAsync(() => api.usuarios());
  const [asignar, setAsignar] = useState(null);
  const [revocar, setRevocar] = useState(null);
  const [q, setQ] = useState('');
  const lista = (data ?? []).filter((u) => !q || `${u.alias} ${u.organizacion}`.toLowerCase().includes(q.toLowerCase()));
  return (
    <>
      <PageHeader title="Usuarios y roles" description="Las asignaciones quedan auditadas con motivo. Nadie se asigna roles a sí mismo y los roles incompatibles se rechazan (separación de funciones)." />
      <BandejaSolicitudes onResuelta={reload} />
      <label className="field" style={{ maxWidth: 380, marginBottom: 16 }}><span className="sr">Buscar</span><input type="search" placeholder="Buscar por alias u organización" value={q} onChange={(e) => setQ(e.target.value)} /></label>
      {error && <p className="error" role="alert">{error.message}</p>}
      {loading && !data ? <Skeleton h={320} /> : (
        <div className="card tbl-wrap">
          <table className="tbl">
            <thead><tr><th>Alias</th><th>Organización</th><th>Roles vigentes</th><th>Último acceso</th><th><span className="sr">Acciones</span></th></tr></thead>
            <tbody>
              {lista.map((u) => (
                <tr key={u.uid}>
                  <td><b>{u.alias}</b><small className="hint"><br />{u.proveedor.toLowerCase()} · {u.estado.toLowerCase()}</small></td>
                  <td>{u.organizacion}</td>
                  <td>{u.roles.map((r) => (
                    <span key={r.codigo + r.centro} className="rolchip" title={r.motivo ?? ''}>{nombreRol(r.codigo)}{r.centro ? ` · ${r.centro}` : ''}
                      {u.alias !== user.alias && <button aria-label={`Revocar ${r.codigo}`} onClick={() => setRevocar({ u, r })}><Icon name="close" size={12} /></button>}
                    </span>))}</td>
                  <td>{u.ultimo_acceso ? formatDate(u.ultimo_acceso) : 'Nunca'}</td>
                  <td>{u.alias !== user.alias && <button className="btn btn--ghost btn--sm" onClick={() => setAsignar(u)}><Icon name="plus" size={14} /> Rol</button>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {asignar && <AsignarDialog usuario={asignar} onClose={() => setAsignar(null)} onDone={() => { setAsignar(null); reload(); }} />}
      {revocar && <RevocarDialog {...revocar} onClose={() => setRevocar(null)} onDone={() => { setRevocar(null); reload(); }} />}
    </>
  );
}

function AsignarDialog({ usuario, onClose, onDone }) {
  const { c } = useCatalogos();
  const toast = useToast();
  const [error, setError] = useState('');
  const submit = async (e) => {
    const d = Object.fromEntries(new FormData(e.currentTarget));
    setError('');
    try { await api.asignarRol(usuario.uid, { rol: d.rol, centro: d.centro || null, motivo: d.motivo }); toast(`Rol asignado a ${usuario.alias}.`); onDone(); }
    catch (err) { setError(err.message); }
  };
  return (
    <Modal title={`Asignar rol a ${usuario.alias}`} onClose={onClose} onSubmit={submit}>
      <label className="field">Rol<select name="rol">{c.roles.filter((r) => !r.servicio && r.codigo !== 'USUARIO_BASE').map((r) => <option key={r.codigo} value={r.codigo}>{r.nombre}{r.padre && r.padre !== 'USUARIO_BASE' ? ` (hereda ${r.padre.toLowerCase()})` : ''}</option>)}</select></label>
      <label className="field">Alcance<select name="centro"><option value="">Todos los centros</option>{c.centros.map((x) => <option key={x.codigo} value={x.codigo}>{x.codigo} · {x.nombre}</option>)}</select></label>
      <label className="field">Motivo *<input name="motivo" required minLength={5} maxLength={300} placeholder="Ej.: Nuevo técnico del laboratorio" /></label>
      {error && <p className="error" role="alert">{error}</p>}
      <div className="actions-row"><button type="button" className="btn btn--ghost" onClick={onClose}>Cancelar</button><button className="btn btn--primary">Asignar</button></div>
    </Modal>
  );
}

function RevocarDialog({ u, r, onClose, onDone }) {
  const toast = useToast();
  const [error, setError] = useState('');
  const submit = async (e) => {
    const d = Object.fromEntries(new FormData(e.currentTarget));
    try { await api.revocarRol(u.uid, r.codigo, d.motivo); toast('Rol revocado: su vigencia termina ahora.'); onDone(); } catch (err) { setError(err.message); }
  };
  return (
    <Modal title={`Revocar ${r.codigo.toLowerCase()} a ${u.alias}`} onClose={onClose} onSubmit={submit}>
      <p className="hint">La asignación no se borra: se cierra su vigencia y queda en el historial.</p>
      <label className="field">Motivo *<input name="motivo" required minLength={5} maxLength={300} /></label>
      {error && <p className="error" role="alert">{error}</p>}
      <div className="actions-row"><button type="button" className="btn btn--ghost" onClick={onClose}>Cancelar</button><button className="btn btn--primary">Revocar</button></div>
    </Modal>
  );
}
