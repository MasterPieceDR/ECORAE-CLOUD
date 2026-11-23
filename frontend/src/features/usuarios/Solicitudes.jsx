import { EmptyState } from '@/shared/ui/EmptyState';
import { useState } from 'react';
import { api, formatDate } from '@/shared/api';
import { useAuth, useCatalogos } from '@/features/auth';
import { useAsync } from '@/shared/hooks/useAsync';
import { Icon } from '@/shared/ui/Icon';
import { Modal } from '@/shared/ui/Modal';
import { useToast } from '@/shared/ui/Toast';
import './solicitudes.css';

const TONO = { PENDIENTE: 'sun', APROBADA: 'lime', RECHAZADA: 'coral', CANCELADA: 'gray' };
// Roles que trabajan en un centro concreto: piden el alcance
const CON_CENTRO = ['OPERADOR_CENTRO', 'TECNICO_EVALUADOR', 'GESTOR_TRATAMIENTO', 'COORDINADOR_LOGISTICO'];

export const soloRolBase = (user) => user.roles.every((r) => r.codigo === 'USUARIO_BASE');

// Perfil: el usuario pide un rol y ve en qué quedó cada pedido.
export function SolicitarAcceso() {
  const { user, refrescar } = useAuth();
  const { c, nombreRol } = useCatalogos();
  const toast = useToast();
  const mias = useAsync(() => api.solicitudesRol().then((l) => l.filter((s) => s.usuario === user.uid)), [user.uid]);
  const [rol, setRol] = useState('GENERADOR');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const roles = c.roles.filter((r) => !r.servicio && r.codigo !== 'USUARIO_BASE' && !user.roles.some((x) => x.codigo === r.codigo));
  const pendiente = (mias.data ?? []).some((s) => s.estado === 'PENDIENTE');

  const enviar = async (e) => {
    e.preventDefault();
    const form = e.currentTarget;
    const d = Object.fromEntries(new FormData(form));
    setBusy(true); setError('');
    try {
      await api.solicitarRol({ rol: d.rol, centro: d.centro || null, motivo: d.motivo });
      form.reset();
      toast('Solicitud enviada. El administrador la revisará.');
      mias.reload();
    } catch (err) { setError(err.message); }
    setBusy(false);
  };
  const cancelar = async (uid) => {
    try { await api.cancelarSolicitudRol(uid); mias.reload(); } catch (err) { toast(err.message, 'error'); }
  };

  return (
    <section className="card pf-config" id="solicitar">
      <h2 className="detail__h2">Solicitar acceso</h2>
      <p className="hint">Al registrarte recibes el rol base (consulta y capacitación). Si trabajas en la red, pide el rol que te corresponde: un administrador verifica quién eres y lo aprueba. Así nadie se da permisos a sí mismo.</p>
      {(mias.data ?? []).length > 0 && (
        <ul className="sol-list">
          {mias.data.map((s) => (
            <li key={s.uid}>
              <div><b>{nombreRol(s.rol)}{s.centro ? ` · ${s.centro}` : ''}</b><span className="badge" data-tone={TONO[s.estado]}>{s.estado.toLowerCase()}</span></div>
              <small className="hint">Enviada {formatDate(s.creado_en)}{s.resuelto_en && s.estado !== 'CANCELADA' ? ` · resuelta por ${s.resuelto_por} ${formatDate(s.resuelto_en)}` : ''}</small>
              {s.respuesta && <p className="sol-resp">“{s.respuesta}”</p>}
              {s.estado === 'PENDIENTE' && <button className="btn btn--ghost btn--sm" onClick={() => cancelar(s.uid)}>Cancelar solicitud</button>}
              {s.estado === 'APROBADA' && !user.roles.some((r) => r.codigo === s.rol) && <button className="btn btn--primary btn--sm" onClick={() => refrescar()}><Icon name="refresh" size={14} /> Actualizar mis permisos</button>}
            </li>
          ))}
        </ul>
      )}
      {!pendiente && roles.length > 0 && (
        <form className="accion-form" onSubmit={enviar}>
          <label className="field">Rol que necesitas
            <select name="rol" value={rol} onChange={(e) => setRol(e.target.value)}>
              {roles.map((r) => <option key={r.codigo} value={r.codigo}>{r.nombre}</option>)}
            </select>
          </label>
          {CON_CENTRO.includes(rol) && (
            <label className="field">Centro donde trabajas
              <select name="centro" required><option value="">Elige un centro</option>{c.centros.map((x) => <option key={x.codigo} value={x.codigo}>{x.codigo} · {x.nombre}</option>)}</select>
            </label>
          )}
          <label className="field">¿Quién eres y para qué lo necesitas? *
            <textarea name="motivo" rows="3" required minLength={10} maxLength={500} placeholder="Ej.: Soy el responsable del punto limpio del GAD y registraré los equipos que recibimos." />
          </label>
          {error && <p className="error" role="alert">{error}</p>}
          <button className="btn btn--primary btn--sm" disabled={busy}><Icon name="send" size={16} /> {busy ? 'Enviando...' : 'Enviar solicitud'}</button>
        </form>
      )}
      {pendiente && <p className="note">Tienes una solicitud pendiente. Te avisaremos aquí cuando se resuelva; luego pulsa «Actualizar mis permisos».</p>}
    </section>
  );
}

// Usuarios (administrador): bandeja de solicitudes para aprobar o rechazar.
export function BandejaSolicitudes({ onResuelta }) {
  const { nombreRol } = useCatalogos();
  const toast = useToast();
  const [todas, setTodas] = useState(false);
  const lista = useAsync(() => api.solicitudesRol(!todas), [todas]);
  const [rechazar, setRechazar] = useState(null);
  const [busy, setBusy] = useState(null);

  const aprobar = async (s) => {
    setBusy(s.uid);
    try { await api.resolverSolicitudRol(s.uid, { aprobar: true, respuesta: 'Verificado por el administrador' }); toast(`${s.alias} ahora tiene el rol ${nombreRol(s.rol)}.`); lista.reload(); onResuelta?.(); }
    catch (e) { toast(e.message, 'error'); }
    setBusy(null);
  };
  const pendientes = (lista.data ?? []).filter((s) => s.estado === 'PENDIENTE').length;
  return (
    <section className="card sol-box">
      <div className="sol-head">
        <h2 className="detail__h2"><Icon name="inbox" size={20} /> Solicitudes de acceso {pendientes > 0 && <span className="badge" data-tone="sun">{pendientes} pendiente(s)</span>}</h2>
        <label className="check"><input type="checkbox" checked={todas} onChange={(e) => setTodas(e.target.checked)} /> Ver historial</label>
      </div>
      {lista.data?.length === 0 && <EmptyState title="No hay solicitudes" description={todas ? "Todavía no hay solicitudes." : "No hay solicitudes pendientes de revisión."} />}
      <ul className="sol-list">
        {(lista.data ?? []).map((s) => (
          <li key={s.uid}>
            <div><b>{s.alias}</b> <span className="hint">({s.organizacion})</span> pide <b>{nombreRol(s.rol)}{s.centro ? ` · ${s.centro}` : ''}</b> <span className="badge" data-tone={TONO[s.estado]}>{s.estado.toLowerCase()}</span></div>
            <p className="sol-resp">“{s.motivo}”</p>
            <small className="hint">{formatDate(s.creado_en)}{s.resuelto_por ? ` · ${s.estado.toLowerCase()} por ${s.resuelto_por}` : ''}{s.respuesta ? ` · ${s.respuesta}` : ''}</small>
            {s.estado === 'PENDIENTE' && (
              <div className="actions-row">
                <button className="btn btn--ghost btn--sm" disabled={busy === s.uid} onClick={() => setRechazar(s)}>Rechazar</button>
                <button className="btn btn--primary btn--sm" disabled={busy === s.uid} onClick={() => aprobar(s)}><Icon name="check" size={14} /> Aprobar</button>
              </div>
            )}
          </li>
        ))}
      </ul>
      {rechazar && <RechazarDialog s={rechazar} onClose={() => setRechazar(null)} onDone={() => { setRechazar(null); lista.reload(); }} />}
    </section>
  );
}

function RechazarDialog({ s, onClose, onDone }) {
  const toast = useToast();
  const [error, setError] = useState('');
  const submit = async (e) => {
    const d = Object.fromEntries(new FormData(e.currentTarget));
    try { await api.resolverSolicitudRol(s.uid, { aprobar: false, respuesta: d.respuesta }); toast('Solicitud rechazada.'); onDone(); } catch (err) { setError(err.message); }
  };
  return (
    <Modal title={`Rechazar la solicitud de ${s.alias}`} onClose={onClose} onSubmit={submit}>
      <p className="hint">La persona verá tu respuesta en su perfil.</p>
      <label className="field">Motivo *<input name="respuesta" required minLength={5} maxLength={500} placeholder="Ej.: No pudimos verificar que pertenezcas al GAD" /></label>
      {error && <p className="error" role="alert">{error}</p>}
      <div className="actions-row"><button type="button" className="btn btn--ghost" onClick={onClose}>Cancelar</button><button className="btn btn--primary">Rechazar</button></div>
    </Modal>
  );
}
