import { EmptyState } from '@/shared/ui/EmptyState';
import { useEffect, useRef, useState } from 'react';
import { motion } from 'motion/react';
import { api } from '@/shared/api';
import { useAsync } from '@/shared/hooks/useAsync';
import { Icon } from '@/shared/ui/Icon';
import './asistente.css';

const TONO = { LECTURA: 'sky', ANALISIS: 'sun', ESCRITURA: 'coral' };
const sesion = `web-${Math.random().toString(36).slice(2, 10)}`;

// Asistente MCP (ADR-006): las herramientas salen del registro en la base y se filtran por tu rol.
// Las que escriben piden tu confirmación; evaluar, transferir y cerrar se hacen en la ficha del equipo.
export function AsistentePanel({ onClose }) {
  const { data, loading, error } = useAsync(() => api.herramientas());
  const [modo, setModo] = useState('herramientas');
  const ref = useRef(null);
  useEffect(() => { ref.current?.showModal(); }, []);
  return (
    <dialog ref={ref} className="asis" onClose={onClose} aria-labelledby="asis-t">
      <motion.div className="asis__in" initial={{ x: 40, opacity: 0 }} animate={{ x: 0, opacity: 1 }} transition={{ duration: .25 }}>
        <header className="asis__head">
          <span className="asis__logo"><Icon name="bot" /></span>
          <div><h2 id="asis-t">Asistente EcoRAEE</h2><small>Model Context Protocol · cada uso queda en la bitácora</small></div>
          <button className="icon-btn" onClick={onClose} aria-label="Cerrar"><Icon name="close" /></button>
        </header>
        {data?.chat_disponible && (
          <div className="auth__tabs asis__tabs" role="tablist">
            {[['herramientas', 'Herramientas'], ['chat', 'Conversar']].map(([k, l]) => (
              <button key={k} role="tab" aria-selected={modo === k} onClick={() => setModo(k)}>{modo === k && <motion.i layoutId="asis-pill" />}<span>{l}</span></button>
            ))}
          </div>
        )}
        {error && <p className="error">{error.message}</p>}
        {loading && <p className="hint">Cargando herramientas de tu rol...</p>}
        {data && (modo === 'chat' ? <Chat /> : <Herramientas lista={data.herramientas} />)}
      </motion.div>
    </dialog>
  );
}

function Herramientas({ lista }) {
  const [sel, setSel] = useState(null);
  if (sel) return <Ejecutar h={sel} volver={() => setSel(null)} />;
  return (
    <div className="asis__body">
      <p className="hint">Tienes {lista.length} herramienta(s) según tu rol. Las de escritura piden confirmación.</p>
      {lista.length === 0 && <EmptyState title="Sin herramientas disponibles" description="Tu rol no tiene herramientas disponibles en este momento." />}
      <ul className="tools">
        {lista.map((h) => (
          <li key={h.nombre}><button onClick={() => setSel(h)}>
            <b>{h.titulo}</b><span className="badge" data-tone={TONO[h.tipo]}>{h.tipo.toLowerCase()}</span>
            <small>{h.descripcion}</small>
          </button></li>
        ))}
      </ul>
    </div>
  );
}

function Campo({ nombre, esquema, requerido }) {
  const label = `${nombre.replace(/_/g, ' ')}${requerido ? ' *' : ''}`;
  if (esquema.type === 'boolean') return <label className="check"><input type="checkbox" name={nombre} /> {label}</label>;
  if (esquema.type === 'object') return <label className="field">{label} (JSON)<textarea name={nombre} rows="3" placeholder='{"pulgadas": 22}' /></label>;
  if (esquema.type === 'array') return <label className="field">{label} (separados por coma)<input name={nombre} required={requerido} /></label>;
  return <label className="field">{label}<input name={nombre} type={esquema.type === 'number' || esquema.type === 'integer' ? 'number' : 'text'} step="any" required={requerido} max={esquema.maximum} /></label>;
}

function leer(form, esquema) {
  const d = new FormData(form);
  const out = {};
  Object.entries(esquema.properties ?? {}).forEach(([k, e]) => {
    const v = d.get(k);
    if (e.type === 'boolean') { out[k] = v === 'on'; return; }
    if (v === null || v === '') return;
    if (e.type === 'number' || e.type === 'integer') out[k] = Number(v);
    else if (e.type === 'array') out[k] = String(v).split(',').map((x) => x.trim()).filter(Boolean);
    else if (e.type === 'object') out[k] = JSON.parse(v);
    else out[k] = v;
  });
  return out;
}

function Ejecutar({ h, volver }) {
  const [res, setRes] = useState(null);
  const [args, setArgs] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const correr = async (a, confirmado = false) => {
    setBusy(true); setError('');
    try { setRes(await api.ejecutarHerramienta({ herramienta: h.nombre, argumentos: a, confirmado, sesion })); setArgs(a); }
    catch (e) { setError(e.message); }
    setBusy(false);
  };
  const props = h.esquema_entrada.properties ?? {};
  return (
    <div className="asis__body">
      <button className="link" onClick={volver}><Icon name="back" size={14} /> Herramientas</button>
      <h3>{h.titulo}</h3>
      <p className="hint">{h.descripcion}</p>
      <form className="accion-form" onSubmit={(e) => { e.preventDefault(); try { correr(leer(e.currentTarget, h.esquema_entrada)); } catch { setError('El JSON no es válido.'); } }}>
        {Object.entries(props).map(([k, e]) => <Campo key={k} nombre={k} esquema={e} requerido={(h.esquema_entrada.required ?? []).includes(k)} />)}
        {Object.keys(props).length === 0 && <p className="hint">No necesita datos.</p>}
        <button className="btn btn--primary btn--sm" disabled={busy}>{busy ? 'Consultando...' : 'Ejecutar'}</button>
      </form>
      {error && <p className="error">{error}</p>}
      {res?.estado === 'PENDIENTE_CONFIRMACION' && (
        <div className="confirm">
          <b><Icon name="alert" size={16} /> Esta acción escribe en la plataforma</b>
          <code className="mono">{JSON.stringify(args)}</code>
          <div className="actions-row"><button className="btn btn--ghost btn--sm" onClick={() => setRes(null)}>Cancelar</button><button className="btn btn--primary btn--sm" onClick={() => correr(args, true)} disabled={busy}>Confirmar</button></div>
        </div>
      )}
      {res && res.estado !== 'PENDIENTE_CONFIRMACION' && <Resultado r={res} />}
    </div>
  );
}

const celda = (x) => (typeof x === 'object' && x !== null ? JSON.stringify(x) : String(x ?? '—'));
const esTabla = (x) => Array.isArray(x) && x.length > 0 && typeof x[0] === 'object' && x[0] !== null;

function Tabla({ filas }) {
  const cols = Object.keys(filas[0]);
  return (
    <div className="tbl-wrap"><table className="tbl"><thead><tr>{cols.map((k) => <th key={k}>{k.replace(/_/g, ' ')}</th>)}</tr></thead>
      <tbody>{filas.slice(0, 100).map((f, i) => <tr key={i}>{cols.map((k) => <td key={k}>{celda(f[k])}</td>)}</tr>)}</tbody></table></div>
  );
}

// Presenta el resultado de forma legible: tablas para listas y fichas para objetos (sin JSON crudo).
function Resultado({ r }) {
  const [crudo, setCrudo] = useState(false);
  if (r.estado !== 'OK') return <p className={r.estado === 'ERROR' ? 'error' : 'note'} data-tone="aviso"><b>{r.estado.toLowerCase().replace('_', ' ')}:</b> {r.mensaje}</p>;
  const v = r.resultado;
  const objeto = v && typeof v === 'object' && !Array.isArray(v) ? v : null;
  return (
    <div className="res">
      <small className="hint">{r.filas} fila(s) · {r.duracion_ms} ms · registrado en la bitácora · <button className="link" onClick={() => setCrudo((x) => !x)}>{crudo ? 'ver tabla' : 'ver JSON'}</button></small>
      {crudo ? <pre className="mono res__json">{JSON.stringify(v, null, 2)}</pre> : esTabla(v) ? <Tabla filas={v} /> : objeto ? (
        <>
          <dl className="facts res__facts">
            {Object.entries(objeto).filter(([, x]) => !esTabla(x)).map(([k, x]) => (
              <div key={k}><dt>{k.replace(/_/g, ' ')}</dt><dd>{x && typeof x === 'object' ? Object.entries(x).filter(([, y]) => typeof y !== 'object' || y === null).map(([a, b]) => `${a.replace(/_/g, ' ')}: ${b ?? '—'}`).join(' · ') : celda(x)}</dd></div>
            ))}
          </dl>
          {Object.entries(objeto).filter(([, x]) => esTabla(x)).map(([k, x]) => <div key={k}><b className="res__t">{k.replace(/_/g, ' ')}</b><Tabla filas={x} /></div>)}
        </>
      ) : <p>{celda(v)}</p>}
    </div>
  );
}

function Chat() {
  const [historial, setHistorial] = useState([]);
  const [msgs, setMsgs] = useState([{ de: 'asis', texto: 'Hola. Puedo consultar la trazabilidad, la red y los indicadores con tus permisos. ¿Qué necesitas?' }]);
  const [pendiente, setPendiente] = useState(null);
  const [busy, setBusy] = useState(false);
  const fin = useRef(null);
  useEffect(() => { fin.current?.scrollIntoView({ behavior: 'smooth' }); }, [msgs, pendiente]);
  const enviar = async (cuerpo, propio) => {
    setBusy(true);
    if (propio) setMsgs((m) => [...m, { de: 'yo', texto: propio }]);
    try {
      const r = await api.chat({ historial, sesion, ...cuerpo });
      setHistorial(r.historial);
      setMsgs((m) => [...m, ...r.eventos.map((e) => ({ de: 'tool', texto: `${e.herramienta} · ${e.estado.toLowerCase()}` })), ...(r.respuesta ? [{ de: 'asis', texto: r.respuesta }] : [])]);
      setPendiente(r.pendiente);
    } catch (e) { setMsgs((m) => [...m, { de: 'error', texto: e.message }]); }
    setBusy(false);
  };
  return (
    <div className="asis__body chat">
      <div className="chat__msgs">
        {msgs.map((m, i) => <p key={i} className={`msg msg--${m.de}`}>{m.texto}</p>)}
        {pendiente && (
          <div className="confirm">
            <b><Icon name="alert" size={16} /> El asistente quiere usar «{pendiente.herramienta}»</b>
            <code className="mono">{JSON.stringify(pendiente.argumentos)}</code>
            <div className="actions-row">
              <button className="btn btn--ghost btn--sm" disabled={busy} onClick={() => enviar({ confirmacion: { tool_use_id: pendiente.tool_use_id, aprobado: false } })}>Rechazar</button>
              <button className="btn btn--primary btn--sm" disabled={busy} onClick={() => enviar({ confirmacion: { tool_use_id: pendiente.tool_use_id, aprobado: true } })}>Aprobar</button>
            </div>
          </div>
        )}
        {busy && <p className="msg msg--tool">Pensando...</p>}
        <span ref={fin} />
      </div>
      <form className="comments__form" onSubmit={(e) => { e.preventDefault(); const t = new FormData(e.currentTarget).get('t').trim(); if (t && !pendiente) { e.currentTarget.reset(); enviar({ mensaje: t }, t); } }}>
        <input name="t" placeholder={pendiente ? 'Responde a la confirmación primero' : '¿Dónde está LAP-1013?'} aria-label="Mensaje" disabled={busy || !!pendiente} maxLength={2000} />
        <button className="btn btn--primary btn--sm" aria-label="Enviar" disabled={busy || !!pendiente}><Icon name="send" size={16} /></button>
      </form>
    </div>
  );
}
