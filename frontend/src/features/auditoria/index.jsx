import { Fragment, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, formatDate } from '@/shared/api';
import { useAsync } from '@/shared/hooks/useAsync';
import { Skeleton } from '@/shared/ui/Skeleton';
import { Icon } from '@/shared/ui/Icon';
import { StateBadge } from '@/shared/ui/StateBadge';

const TABS = [['cambios', 'Cambios'], ['asof', 'Estado en una fecha'], ['mcp', 'Asistente MCP'], ['seguridad', 'Seguridad'], ['adr', 'Decisiones (ADR)']];
const OP = { I: 'alta', U: 'cambio', D: 'baja' };

// Auditoría (7.6, RNF-04): imagen antes/después de cada cambio, reconstrucción en el tiempo y bitácoras.
export function AuditoriaPage() {
  const [tab, setTab] = useState('cambios');
  return (
    <>
      <div className="page-head"><div><h1 className="page-title">Auditoría</h1><p className="page-sub">Quién cambió qué, cuándo y por qué canal. Cada registro tiene huella SHA-256 y los periodos se sellan en cadena.</p></div></div>
      <div className="tabs-row chips" role="tablist">
        {TABS.map(([k, l]) => <button key={k} role="tab" className="chip" aria-pressed={tab === k} aria-selected={tab === k} onClick={() => setTab(k)}>{l}</button>)}
      </div>
      {tab === 'cambios' && <Cambios />}
      {tab === 'asof' && <AsOf />}
      {tab === 'mcp' && <Bitacora cargar={api.bitacoraMcp} columnas={[['ocurrido_en', 'Fecha', formatDate], ['herramienta', 'Herramienta'], ['usuario', 'Usuario'], ['estado', 'Estado', (v) => <span className="badge" data-tone={v === 'OK' ? 'lime' : v === 'DENEGADO' || v === 'ERROR' ? 'coral' : 'sun'}>{v}</span>], ['argumentos', 'Argumentos (saneados)', (v) => <code className="mono">{JSON.stringify(v)}</code>], ['duracion_ms', 'ms'], ['error', 'Error']]} />}
      {tab === 'seguridad' && <Bitacora cargar={api.eventosSeguridad} columnas={[['ocurrido_en', 'Fecha', formatDate], ['tipo', 'Evento', (v) => <span className="badge" data-tone={v === 'LOGIN_OK' ? 'lime' : v === 'CAMBIO_ROL' ? 'sky' : 'coral'}>{v.toLowerCase().replace('_', ' ')}</span>], ['usuario', 'Usuario'], ['detalle', 'Detalle', (v) => <code className="mono">{JSON.stringify(v)}</code>]]} />}
      {tab === 'adr' && <Decisiones />}
    </>
  );
}

function Cambios() {
  const [f, setF] = useState({ codigo: '', tabla: '' });
  const [q, setQ] = useState({});
  const [abierto, setAbierto] = useState(null);
  const { data, loading, error } = useAsync(() => api.cambios({ ...q, limite: 150 }), [JSON.stringify(q)]);
  return (
    <>
      <form className="filters-a" onSubmit={(e) => { e.preventDefault(); setQ({ codigo: f.codigo.trim().toUpperCase() || undefined, tabla: f.tabla || undefined }); }}>
        <label className="field">Código de objeto<input value={f.codigo} onChange={(e) => setF({ ...f, codigo: e.target.value })} placeholder="LAP-1001" /></label>
        <label className="field">Tabla<select value={f.tabla} onChange={(e) => setF({ ...f, tabla: e.target.value })}>
          <option value="">Todas</option>{['trz.objeto_trazable', 'trz.dispositivo', 'ops.documento_operativo', 'ops.transferencia', 'ops.evaluacion_tecnica', 'evd.evidencia', 'seg.usuario_rol', 'red.capacidad_arista', 'edu.contenido'].map((t) => <option key={t}>{t}</option>)}
        </select></label>
        <button className="btn btn--primary btn--sm">Filtrar</button>
      </form>
      {error && <p className="error" role="alert">{error.message}</p>}
      {loading && !data ? <Skeleton h={300} /> : (
        <div className="card tbl-wrap">
          <table className="tbl">
            <thead><tr><th>Fecha</th><th>Tabla</th><th>Operación</th><th>Campos</th><th>Usuario</th><th>Canal</th><th>Huella</th></tr></thead>
            <tbody>
              {data?.map((x) => (
                <Fragment key={x.id}>
                  <tr className="row-click" onClick={() => setAbierto(abierto === x.id ? null : x.id)}>
                    <td>{formatDate(x.ocurrido_en)}</td><td className="mono">{x.tabla}</td><td>{OP[x.operacion]}</td>
                    <td>{(x.campos_cambiados ?? []).join(', ') || '—'}</td><td>{x.usuario ?? x.usuario_bd}</td><td>{x.canal ?? '—'}</td><td className="mono">{x.hash_registro.slice(0, 10)}…</td>
                  </tr>
                  {abierto === x.id && x.cambios && (
                    <tr><td colSpan={7}><div className="diff">{Object.entries(x.cambios).map(([k, v]) => <p key={k}><b>{k}</b> <s>{JSON.stringify(v.antes)}</s> → <ins>{JSON.stringify(v.despues)}</ins></p>)}</div></td></tr>
                  )}
                </Fragment>
              ))}
            </tbody>
          </table>
          {data?.length === 0 && <p className="empty">Sin cambios con ese filtro.</p>}
        </div>
      )}
    </>
  );
}

function AsOf() {
  const [res, setRes] = useState(null);
  const [error, setError] = useState('');
  const local = (d) => new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
  const consultar = async (e) => {
    e.preventDefault();
    const d = Object.fromEntries(new FormData(e.currentTarget));
    setError('');
    try { setRes({ ...(await api.objetoEn(d.codigo.trim().toUpperCase(), new Date(d.instante).toISOString())), codigo: d.codigo.trim().toUpperCase() }); }
    catch (err) { setError(err.message); setRes(null); }
  };
  return (
    <section className="card asof">
      <p className="hint">Reconstruye cómo estaba un equipo en cualquier instante a partir de la auditoría (aud.fn_estado_en). Sirve para responder reclamos y verificar evidencias.</p>
      <form className="filters-a" onSubmit={consultar}>
        <label className="field">Código<input name="codigo" required placeholder="LAP-1001" /></label>
        <label className="field">Instante<input name="instante" type="datetime-local" required defaultValue={local(new Date(Date.now() - 3600000))} /></label>
        <button className="btn btn--primary btn--sm">Reconstruir</button>
      </form>
      {error && <p className="error" role="alert">{error}</p>}
      {res && (res.existia ? (
        <dl className="facts">
          <div><dt>{res.codigo} en {formatDate(res.instante)}</dt><dd><StateBadge state={res.estado} /></dd></div>
          <div><dt>Clasificación</dt><dd>{res.clasificacion ?? 'Sin evaluar'}</dd></div>
          <div><dt>Ubicación</dt><dd>{res.ubicacion ?? 'En tránsito o fuera de un centro'}</dd></div>
          <div><dt>Versión de la fila</dt><dd>{res.version}</dd></div>
          <div><dt>Ficha actual</dt><dd><Link to={`/app/objetos/${res.codigo}`}>Ver {res.codigo} <Icon name="arrow" size={14} /></Link></dd></div>
        </dl>
      ) : <p className="note">El objeto aún no existía en ese instante.</p>)}
    </section>
  );
}

function Bitacora({ cargar, columnas }) {
  const { data, loading, error } = useAsync(() => cargar());
  if (loading && !data) return <Skeleton h={300} />;
  if (error) return <p className="error" role="alert">{error.message}</p>;
  return (
    <div className="card tbl-wrap">
      <table className="tbl">
        <thead><tr>{columnas.map(([, t]) => <th key={t}>{t}</th>)}</tr></thead>
        <tbody>{data.map((x, i) => <tr key={i}>{columnas.map(([k, , fmt]) => <td key={k}>{fmt ? fmt(x[k]) : x[k] ?? '—'}</td>)}</tr>)}</tbody>
      </table>
      {data.length === 0 && <p className="empty">Sin registros.</p>}
    </div>
  );
}

function Decisiones() {
  const { data, loading } = useAsync(() => api.decisiones());
  if (loading && !data) return <Skeleton h={300} />;
  return (
    <div className="adrs">
      {data?.map((d) => (
        <article key={d.codigo} className="card adr">
          <header><b>{d.codigo}</b><span className="badge" data-tone={d.estado === 'APROBADA' ? 'lime' : 'sun'}>{d.estado.toLowerCase()}</span><small>{d.materias.join(' · ')}</small></header>
          <h3>{d.titulo}</h3>
          <p><b>Contexto:</b> {d.contexto}</p><p><b>Decisión:</b> {d.decision}</p><p><b>Consecuencias:</b> {d.consecuencias}</p>
        </article>
      ))}
    </div>
  );
}
