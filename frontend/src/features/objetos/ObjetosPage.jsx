import { useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { AnimatePresence, motion } from 'motion/react';
import { api, desdeHace } from '@/shared/api';
import { useAuth, useCatalogos } from '@/features/auth';
import { useAsync } from '@/shared/hooks/useAsync';
import { Icon } from '@/shared/ui/Icon';
import { Skeleton } from '@/shared/ui/Skeleton';
import { StateBadge, ClasBadge } from '@/shared/ui/StateBadge';
import { Modal } from '@/shared/ui/Modal';
import { useToast } from '@/shared/ui/Toast';
import { RegistrarDialog } from './RegistrarDialog';
import './objetos.css';

export function ObjetosPage() {
  const { can } = useAuth();
  const { c } = useCatalogos();
  const [params, setParams] = useSearchParams();
  const navigate = useNavigate();
  const filtros = { q: params.get('q') ?? '', estado: params.get('estado') ?? '', clasificacion: params.get('clasificacion') ?? '', tipo: params.get('tipo') ?? '', centro: params.get('centro') ?? '', serie: params.get('serie') ?? '' };
  const { data, loading, error, reload } = useAsync(() => api.objetos(filtros), [params.toString()]);
  const [sel, setSel] = useState(new Set());
  const [dialogo, setDialogo] = useState(null);
  const set = (k) => (e) => { const p = new URLSearchParams(params); if (e.target.value) p.set(k, e.target.value); else p.delete(k); setParams(p, { replace: true }); };
  const objetos = data?.objetos ?? [];
  const elegidos = objetos.filter((o) => sel.has(o.uid));
  const toggle = (uid) => setSel((s) => { const n = new Set(s); if (n.has(uid)) n.delete(uid); else n.add(uid); return n; });
  const puedeLote = can('LOTE.GESTIONAR') && elegidos.length >= 2 && elegidos.every((o) => o.tipo_objeto === 'DISPOSITIVO' && !o.lote_codigo);
  const puedeSolicitar = can('SOLICITUD.CREAR') && elegidos.length >= 1 && elegidos.every((o) => o.estado === 'REGISTRADO' && !o.lote_codigo);

  return (
    <>
      <div className="page-head">
        <div><h1 className="page-title">Equipos y lotes</h1><p className="page-sub">Cada objeto con su identificador único, su estado y su historia completa{data ? ` · ${data.total} visibles para ti` : ''}.</p></div>
        {can('OBJETO.REGISTRAR') && <button className="btn btn--primary" onClick={() => setDialogo('registrar')}><Icon name="plus" size={18} /> Registrar equipo</button>}
      </div>
      <div className="filters">
        <label className="field"><span className="sr">Buscar</span><input type="search" placeholder="Código, categoría, marca, serie, lote u origen" value={filtros.q} onChange={set('q')} /></label>
        <label className="field">Serie exacta<input value={filtros.serie} onChange={set('serie')} /></label>
        <label className="field"><span className="sr">Estado</span>
          <select value={filtros.estado} onChange={set('estado')}><option value="">Todos los estados</option>{c.estados.map((s) => <option key={s.codigo} value={s.codigo}>{s.nombre}</option>)}</select>
        </label>
        <label className="field"><span className="sr">Clasificación</span>
          <select value={filtros.clasificacion} onChange={set('clasificacion')}><option value="">Toda clasificación</option>{c.clasificaciones.filter((k) => k.codigo !== 'PENDIENTE').map((k) => <option key={k.codigo} value={k.codigo}>{k.nombre}</option>)}</select>
        </label>
        <label className="field"><span className="sr">Centro</span>
          <select value={filtros.centro} onChange={set('centro')}><option value="">Todos los centros</option>{c.centros.map((x) => <option key={x.codigo} value={x.codigo}>{x.codigo} · {x.nombre}</option>)}</select>
        </label>
      </div>

      <AnimatePresence>
        {sel.size > 0 && (
          <motion.div className="bulk" initial={{ opacity: 0, y: -8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }}>
            <b>{sel.size} seleccionado{sel.size > 1 ? 's' : ''}</b>
            <button className="btn btn--ghost btn--sm" disabled={!puedeLote} onClick={() => setDialogo('lote')} title="Mismo estado y ubicación, sin lote vigente"><Icon name="layers" size={16} /> Crear lote</button>
            <button className="btn btn--ghost btn--sm" disabled={!puedeSolicitar} onClick={() => setDialogo('solicitar')} title="Solo equipos registrados de un mismo generador"><Icon name="truck" size={16} /> Solicitar recolección</button>
            <button className="link" onClick={() => setSel(new Set())}>Limpiar</button>
          </motion.div>
        )}
      </AnimatePresence>

      {error && <p className="error" role="alert">{error.message}</p>}
      {loading && !data ? <Skeleton h={320} /> : objetos.length === 0 ? <p className="empty card">No hay objetos con esos filtros.</p> : (
        <div className="card devices">
          <table>
            <thead><tr><th><span className="sr">Seleccionar</span></th><th>Código</th><th>Equipo</th><th>Serie</th><th>Origen</th><th>Ubicación</th><th>Clasificación</th><th>Estado</th><th><span className="sr">Abrir</span></th></tr></thead>
            <tbody>
              {objetos.map((o) => (
                <tr key={o.uid} data-sel={sel.has(o.uid)}>
                  <td><input type="checkbox" className="pick" aria-label={`Seleccionar ${o.codigo}`} checked={sel.has(o.uid)} onChange={() => toggle(o.uid)} /></td>
                  <td data-label="Código"><Link to={o.codigo}><b>{o.codigo}</b></Link>{o.tareas?.length > 0 && <span className="pending" title="Tienes una tarea con este objeto">tarea</span>}</td>
                  <td data-label="Equipo">{o.tipo_objeto === 'LOTE' ? `Lote · ${o.miembros_vigentes} equipos` : o.categoria_nombre}<small>{o.marca ?? ''}{o.lote_codigo ? ` · en ${o.lote_codigo}` : ''}</small></td>
                  <td data-label="Serie">{o.numero_serie ?? '—'}</td>
                  <td data-label="Origen">{o.organizacion_origen_nombre}</td>
                  <td data-label="Ubicación">{o.centro_actual ? `${o.centro_actual}${o.ubicacion_actual && o.ubicacion_actual !== 'RAIZ' ? ` / ${o.ubicacion_actual}` : ''}` : o.transferencia_nodo_destino ? `→ ${o.transferencia_nodo_destino}` : '—'}<small>{desdeHace(o.ultimo_movimiento)}</small></td>
                  <td data-label="Clasificación">{o.tipo_objeto === 'LOTE' ? '—' : <ClasBadge value={o.clasificacion} />}</td>
                  <td data-label="Estado"><StateBadge state={o.estado} /></td>
                  <td><Link to={o.codigo} className="devices__go" aria-label={`Ver trazabilidad de ${o.codigo}`}><Icon name="arrow" size={18} /></Link></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {dialogo === 'registrar' && <RegistrarDialog onClose={() => setDialogo(null)} onCreated={(codigo) => { setDialogo(null); navigate(codigo); }} />}
      {dialogo === 'lote' && <LoteDialog objetos={elegidos} onClose={() => setDialogo(null)} onDone={() => { setDialogo(null); setSel(new Set()); reload(); }} />}
      {dialogo === 'solicitar' && <SolicitarDialog objetos={elegidos} onClose={() => setDialogo(null)} onDone={() => { setDialogo(null); setSel(new Set()); reload(); }} />}
    </>
  );
}

function LoteDialog({ objetos, onClose, onDone }) {
  const toast = useToast();
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const peso = objetos.reduce((s, o) => s + Number(o.peso_kg ?? 0), 0);
  const submit = async (e) => {
    const d = Object.fromEntries(new FormData(e.currentTarget));
    setBusy(true); setError('');
    try {
      const r = await api.crearLote({ codigo: d.codigo.trim().toUpperCase(), proposito: d.proposito, objetos: objetos.map((o) => o.uid), descripcion: d.descripcion || null, peso_declarado: Number(d.peso) || null });
      toast(`Lote ${r.codigo} creado.`); onDone();
    } catch (err) { setError(err.message); setBusy(false); }
  };
  return (
    <Modal title="Crear lote" onClose={onClose} onSubmit={submit}>
      <p className="hint">{objetos.map((o) => o.codigo).join(', ')}. Deben compartir estado y ubicación: la base lo valida.</p>
      <div className="two">
        <label className="field">Código *<input name="codigo" required pattern="[A-Za-z0-9][A-Za-z0-9_\-.]{1,39}" defaultValue={`LOT-${Date.now().toString().slice(-5)}`} /></label>
        <label className="field">Propósito<select name="proposito"><option value="RECEPCION">Recepción</option><option value="TRANSFERENCIA">Transferencia</option><option value="TRATAMIENTO">Tratamiento</option><option value="ASIGNACION">Asignación</option></select></label>
      </div>
      <div className="two">
        <label className="field">Descripción<input name="descripcion" maxLength={200} /></label>
        <label className="field">Peso declarado (kg)<input name="peso" type="number" step="0.01" defaultValue={peso.toFixed(2)} /></label>
      </div>
      {error && <p className="error" role="alert">{error}</p>}
      <div className="actions-row"><button type="button" className="btn btn--ghost" onClick={onClose}>Cancelar</button><button className="btn btn--primary" disabled={busy}>{busy ? 'Creando...' : 'Crear lote'}</button></div>
    </Modal>
  );
}

function SolicitarDialog({ objetos, onClose, onDone }) {
  const { c } = useCatalogos();
  const toast = useToast();
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const acopios = c.centros.filter((x) => (x.funciones ?? []).some((f) => f === 'ACOPIO' || f === 'EVALUACION'));
  const submit = async (e) => {
    const d = Object.fromEntries(new FormData(e.currentTarget));
    setBusy(true); setError('');
    try {
      const r = await api.solicitar({ objetos: objetos.map((o) => o.uid), centro_destino: d.centro, fecha_preferida: d.fecha || null, sector: d.sector || null });
      toast(`Solicitud ${r.numero} enviada.`); onDone();
    } catch (err) { setError(err.message); setBusy(false); }
  };
  return (
    <Modal title="Solicitar recolección" onClose={onClose} onSubmit={submit}>
      <p className="hint">{objetos.length} equipo(s): {objetos.map((o) => o.codigo).join(', ')}.</p>
      <label className="field">Centro<select name="centro">{acopios.map((x) => <option key={x.codigo} value={x.codigo}>{x.codigo} · {x.nombre}</option>)}</select></label>
      <div className="two">
        <label className="field">Fecha preferida<input name="fecha" type="date" min={new Date().toISOString().slice(0, 10)} /></label>
        <label className="field">Sector<input name="sector" maxLength={120} /></label>
      </div>
      {error && <p className="error" role="alert">{error}</p>}
      <div className="actions-row"><button type="button" className="btn btn--ghost" onClick={onClose}>Cancelar</button><button className="btn btn--primary" disabled={busy}>{busy ? 'Enviando...' : 'Solicitar'}</button></div>
    </Modal>
  );
}
