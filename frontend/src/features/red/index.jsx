import { PageHeader } from '@/shared/ui/PageHeader';
import { useEffect, useRef, useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { api, formatDate } from '@/shared/api';
import { useAsync } from '@/shared/hooks/useAsync';
import { Skeleton } from '@/shared/ui/Skeleton';
import { Counter } from '@/shared/ui/Counter';
import { Icon } from '@/shared/ui/Icon';
import { useToast } from '@/shared/ui/Toast';
import { FlowGraph, COLORS, fmt, inf, nodosDeRed } from './FlowGraph';
import { FlowDetalle, indices } from './FlowDetalle';
import { EditarSeleccion, NuevoEscenario } from './FlowEditor';
import { descargarCSV, descargarPNG } from './exportar';
import './red.css';

const fmtArista = ([a, b]) => (a === 's' ? `Oferta de ${b}` : b === 't' ? `Demanda de ${a}` : `${a} → ${b}`);
const MODOS = [['flujo', 'Flujo / capacidad'], ['uso', '% de uso'], ['holgura', 'Holgura']];
const ORDEN = { corte: 0, saturada: 1, holgura: 2 };
const REFRESCO_MS = 30000;

export function RedPage() {
  const [id, setId] = useState('E0');
  const [corteSel, setCorteSel] = useState(null);
  const [seleccion, setSeleccion] = useState(null);
  const [modo, setModo] = useState('flujo');
  const [auto, setAuto] = useState(false);
  const [actualizado, setActualizado] = useState(new Date());
  const [nuevo, setNuevo] = useState(false);
  const toast = useToast();
  const red = useAsync(() => api.red());
  const flujo = useAsync(() => api.analizarEscenario(id).then((x) => { setActualizado(new Date()); return x; }), [id]);
  const cmp = useAsync(() => api.compararEscenarios());
  const [registrando, setRegistrando] = useState(false);
  const svgWrap = useRef(null);
  const r = flujo.data;
  const corte = corteSel != null ? r?.cortes[corteSel] : null;
  const escenario = red.data?.escenarios.find((e) => e.codigo === id);
  const editable = red.data?.puede_editar && escenario?.estado === 'BORRADOR';

  // Esc limpia la selección
  useEffect(() => {
    const k = (e) => { if (e.key === 'Escape' && !document.querySelector('dialog[open]')) setSeleccion(null); };
    window.addEventListener('keydown', k);
    return () => window.removeEventListener('keydown', k);
  }, []);

  // Refresco automático opcional: vuelve a leer la base sin parpadeo (solo con la pestaña visible)
  useEffect(() => {
    if (!auto) return undefined;
    const t = setInterval(async () => {
      if (document.hidden) return;
      try {
        const [x, y] = await Promise.all([api.analizarEscenario(id), api.red()]);
        flujo.setData(x); red.setData(y); setActualizado(new Date());
      } catch { /* se reintenta en el próximo ciclo */ }
    }, REFRESCO_MS);
    return () => clearInterval(t);
  }, [auto, id]); // eslint-disable-line react-hooks/exhaustive-deps

  const cambiarEscenario = (c) => { setId(c); setCorteSel(null); };

  const registrar = async () => {
    setRegistrando(true);
    try {
      const x = await api.ejecutarEscenario(id);
      flujo.setData(x);
      cmp.reload();
      toast(`Ejecución ${x.ejecucion_id} registrada con su huella del dataset.`);
    } catch (e) { toast(e.message, 'error'); }
    setRegistrando(false);
  };

  const aplicado = (x) => { flujo.setData(x); setActualizado(new Date()); red.reload(); cmp.reload(); };
  const eliminar = async () => {
    try { await api.eliminarEscenario(id); toast(`Escenario ${id} eliminado.`); cambiarEscenario(escenario?.escenario_base ?? 'E0'); red.reload(); cmp.reload(); }
    catch (e) { toast(e.message, 'error'); }
  };

  const elegirFila = (sel) => { setSeleccion(sel); svgWrap.current?.scrollIntoView({ behavior: 'smooth', block: 'center' }); };

  return (
    <>
      <PageHeader title="Red de flujo" description="Flujo máximo y todos los cortes mínimos (Edmonds-Karp) sobre la red real G = (V, E, c) leída desde la base, en equipos por semana." action={<> <div className="actions-row">
          {red.data?.puede_editar && <button className="btn btn--ghost" onClick={() => setNuevo(true)}><Icon name="plus" size={18} /> Nuevo escenario</button>}
          {red.data?.puede_registrar && <button className="btn btn--primary" onClick={registrar} disabled={registrando || !r}><Icon name="check" size={18} /> {registrando ? 'Registrando...' : 'Registrar ejecución'}</button>}
        </div> </>} />
      <div className="chips" role="group" aria-label="Escenarios">
        {(red.data?.escenarios ?? []).map((s) => (
          <button key={s.codigo} className="chip" aria-pressed={s.codigo === id} onClick={() => cambiarEscenario(s.codigo)} title={s.descripcion ?? ''}>
            {s.codigo} · {s.nombre}{s.estado === 'BORRADOR' && <small className="chip__tag">borrador</small>}
          </button>
        ))}
      </div>
      {flujo.error && <p className="error" role="alert" style={{ marginTop: 16 }}>{flujo.error.message}</p>}
      {!r || !red.data ? <Skeleton h={460} style={{ marginTop: 16 }} /> : (
        <>
          <section className="flow-kpis">
            <article className="card"><span>Flujo máximo</span><b><Counter to={r.flujo_maximo} /></b><small>equipos por semana</small></article>
            <article className="card"><span>Generación</span><b><Counter to={r.generacion} /></b><small>oferta total de los generadores</small></article>
            <article className="card"><span>Cobertura</span><b><Counter to={r.cobertura} suffix=" %" /></b><small>de lo generado llega a un destino</small></article>
            <article className="card"><span>Cortes mínimos</span><b><Counter to={r.cortes.length} /></b><small>{r.cortes.length > 1 ? 'el cuello de botella no es único' : 'un solo cuello de botella'}</small></article>
          </section>

          <section className="card flow-graph">
            <div className="flow-tools">
              <div className="seg" role="group" aria-label="Qué muestran las etiquetas">
                {MODOS.map(([k, l]) => <button key={k} aria-pressed={modo === k} onClick={() => setModo(k)}>{l}</button>)}
              </div>
              <div className="flow-tools__r">
                <label className="check"><input type="checkbox" checked={auto} onChange={(e) => setAuto(e.target.checked)} /> Actualizar cada 30 s</label>
                <small className="hint">Calculado {actualizado.toLocaleTimeString('es-EC', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}</small>
                <button className="icon-btn" title="Recalcular ahora" aria-label="Recalcular ahora" onClick={() => { flujo.reload(); red.reload(); }}><Icon name="refresh" size={18} /></button>
                <button className="btn btn--ghost btn--sm" onClick={() => descargarPNG(svgWrap.current?.querySelector('svg'), `red-${id}.png`)}><Icon name="download" size={16} /> Imagen</button>
                <button className="btn btn--ghost btn--sm" onClick={() => descargarCSV(red.data, r, `flujo-${id}.csv`)}><Icon name="download" size={16} /> CSV</button>
              </div>
            </div>
            <div className="flow-layout">
              <div className="flow-graph__scroll" ref={svgWrap}>
                <FlowGraph red={red.data} resultado={r} corte={corte} seleccion={seleccion} onSelect={setSeleccion} modo={modo} />
              </div>
              <div className="flow-side">
                <AnimatePresence mode="wait">
                  <motion.div key={seleccion ? JSON.stringify(seleccion) : 'nada'} initial={{ opacity: 0, x: 12 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0 }} transition={{ duration: 0.18 }}>
                    <FlowDetalle red={red.data} resultado={r} seleccion={seleccion} onSelect={setSeleccion} />
                  </motion.div>
                </AnimatePresence>
                {seleccion && editable && <EditarSeleccion escenario={escenario} seleccion={seleccion} resultado={r} onAplicado={aplicado} />}
                {seleccion && red.data.puede_editar && !editable && (
                  <div className="det__edit"><p className="hint">{escenario?.codigo} es un escenario aprobado. Para probar cambios, <button className="det__link" onClick={() => setNuevo(true)}>crea un escenario derivado</button>.</p></div>
                )}
              </div>
            </div>
            <div className="flow-legend">
              {corte ? <span data-k="corte">Corte {corteSel + 1} resaltado</span> : <><span data-k="holgura">Con holgura</span><span data-k="saturada">Saturada (al tope)</span><span data-k="corte">En algún corte mínimo</span></>}
              <span className="flow-legend__v">oferta y demanda (s y t virtuales)</span>
              <span className="flow-legend__n">anillo = capacidad de procesamiento del nodo</span>
              {r.registrado && <span className="flow-legend__ok">Ejecución {r.ejecucion_id} registrada · hash {r.hash.slice(0, 10)}…</span>}
            </div>
          </section>

          <AnimatePresence mode="wait">
            <motion.p key={id} className="flow-reading" initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }}>
              <b>{r.nombre}.</b> {r.lectura}
            </motion.p>
          </AnimatePresence>

          <div className="flow-grid">
            <section className="card">
              <h2 className="flow-h2">Cortes mínimos ({r.cortes.length}) {r.cortes.length > 1 && <small className="hint">El cuello de botella no es único: ampliar un solo corte no basta.</small>}</h2>
              <div className="chips" role="group" aria-label="Cortes">
                <button className="chip" aria-pressed={corteSel === null} onClick={() => setCorteSel(null)}>Todos</button>
                {r.cortes.map((c, i) => <button key={c.numero} className="chip" aria-pressed={corteSel === i} onClick={() => setCorteSel(i)}>Corte {i + 1}</button>)}
              </div>
              {r.cortes.map((c, i) => (
                <ul key={c.numero} className="cut" data-off={corteSel !== null && corteSel !== i}>
                  <li className="cut__t"><span>Corte {i + 1}</span><b>{fmt(c.capacidad)}</b></li>
                  {c.aristas.map((a) => <li key={a.join()}><button className="cut__btn" onClick={() => elegirFila({ tipo: 'arista', origen: a[0], destino: a[1] })}><code>{fmtArista(a)}</code><b>{fmt(r.aristas.find((x) => x.origen === a[0] && x.destino === a[1])?.capacidad ?? 0)}</b></button></li>)}
                  {c.nodos.map((n) => <li key={n}><button className="cut__btn" onClick={() => elegirFila({ tipo: 'nodo', codigo: n })}><code>Procesamiento de {n}</code><b>{fmt(r.nodos.find((x) => x.nodo === n)?.capacidad ?? 0)}</b></button></li>)}
                  {c.virtuales.map((a) => <li key={a.join()}><button className="cut__btn" onClick={() => elegirFila({ tipo: 'arista', origen: a[0], destino: a[1] })}><code>{fmtArista(a)}</code><b>{fmt(r.virtuales.find((x) => x.origen === a[0] && x.destino === a[1])?.capacidad ?? 0)}</b></button></li>)}
                </ul>
              ))}
              <p className="hint">Capacidad de cada corte = flujo máximo (teorema de flujo máximo y corte mínimo).</p>
            </section>
            <section className="card">
              <h2 className="flow-h2">Comparación de escenarios</h2>
              {cmp.data?.escenarios.map((c) => (
                <button key={c.codigo} className="cmp" data-on={c.codigo === id} onClick={() => cambiarEscenario(c.codigo)}>
                  <span>{c.codigo}</span>
                  <div><motion.i animate={{ width: `${c.cobertura}%` }} /></div>
                  <b>{fmt(c.flujo_maximo)} / {fmt(c.generacion)}</b>
                </button>
              ))}
              {escenario && (escenario.cambios_aristas.length > 0 || escenario.cambios_nodos.length > 0) && (
                <div className="changes">
                  <b>Cambios de {escenario.codigo} respecto a {escenario.escenario_base ?? 'la red vigente'}</b>
                  <ul>
                    {escenario.cambios_nodos.map((x) => <li key={x.nodo}><button className="det__link" onClick={() => elegirFila({ tipo: 'nodo', codigo: x.nodo })}>{x.nodo}</button>: {[x.oferta != null && `oferta ${Number(x.oferta)}`, x.demanda != null && `demanda ${Number(x.demanda)}`, x.capacidad != null && `procesa ${Number(x.capacidad)}`].filter(Boolean).join(', ')}</li>)}
                    {escenario.cambios_aristas.map((x) => <li key={x.origen + x.destino}><button className="det__link" onClick={() => elegirFila({ tipo: 'arista', origen: x.origen, destino: x.destino })}>{x.origen} → {x.destino}</button>: {x.capacidad != null ? Number(x.capacidad) : ''}{x.activa === false ? ' (inactiva)' : ''} · {x.motivo}</li>)}
                  </ul>
                </div>
              )}
              {editable && <button className="btn btn--ghost btn--sm" style={{ marginTop: 12 }} onClick={eliminar}><Icon name="close" size={14} /> Eliminar borrador {id}</button>}
              {cmp.data?.ultimas_ejecuciones?.length > 0 && <p className="hint">Última ejecución registrada: {formatDate(cmp.data.ultimas_ejecuciones.reduce((a, b) => (a.finalizado_en > b.finalizado_en ? a : b)).finalizado_en)}.</p>}
            </section>
          </div>

          <TablaFlujo red={red.data} resultado={r} seleccion={seleccion} onSelect={elegirFila} />

          {red.data.utilizacion.length > 0 && (
            <section className="card" style={{ marginTop: 14 }}>
              <h2 className="flow-h2">Uso real de la capacidad esta semana (RN-05) <small className="hint">Transferencias despachadas contra la capacidad vigente.</small></h2>
              <div className="tbl-wrap"><table className="tbl">
                <thead><tr><th>Ruta</th><th>Unidad</th><th>Capacidad</th><th>Consumido</th><th>Uso</th></tr></thead>
                <tbody>{red.data.utilizacion.map((u) => (
                  <tr key={u.origen + u.destino + u.unidad}><td>{u.origen} → {u.destino}</td><td>{u.unidad}</td><td>{Number(u.capacidad)}</td><td>{Number(u.consumo)}</td>
                    <td><div className="use"><i style={{ width: `${Math.min(100, u.utilizacion_pct ?? 0)}%` }} data-alto={(u.utilizacion_pct ?? 0) >= 80} /></div>{Number(u.utilizacion_pct ?? 0).toFixed(0)} %</td></tr>
                ))}</tbody>
              </table></div>
            </section>
          )}
        </>
      )}
      {nuevo && red.data && <NuevoEscenario escenarios={red.data.escenarios} base={id} onClose={() => setNuevo(false)}
        onCreado={(c) => { setNuevo(false); toast(`Escenario ${c} creado. Toca un nodo o una arista para ajustarlo.`); red.reload(); cmp.reload(); cambiarEscenario(c); }} />}
    </>
  );
}

// Flujo por arista (salida del modelo 7.4): tabla ordenable para leer y citar en la memoria.
function TablaFlujo({ red, resultado, seleccion, onSelect }) {
  const [orden, setOrden] = useState('estado');
  const nombre = Object.fromEntries(nodosDeRed(red).map((n) => [n.codigo, n.nombre]));
  const { cortesDe } = indices(resultado);
  const filas = [...resultado.aristas].sort((a, b) => (orden === 'uso' ? b.uso - a.uso : orden === 'flujo' ? b.flujo - a.flujo
    : (ORDEN[a.estado] - ORDEN[b.estado]) || (b.uso - a.uso)));
  return (
    <section className="card" style={{ marginTop: 14 }}>
      <h2 className="flow-h2">Flujo por arista ({filas.length}) <small className="hint">Toca una fila para verla en el grafo.</small></h2>
      <div className="seg" role="group" aria-label="Ordenar por" style={{ marginBottom: 10 }}>
        {[['estado', 'Cuellos de botella primero'], ['uso', 'Mayor uso'], ['flujo', 'Mayor flujo']].map(([k, l]) => <button key={k} aria-pressed={orden === k} onClick={() => setOrden(k)}>{l}</button>)}
      </div>
      <div className="tbl-wrap"><table className="tbl tbl--hover">
        <thead><tr><th>Arista</th><th>Desde → hacia</th><th>Flujo</th><th>Capacidad</th><th>Uso</th><th>Holgura</th><th>Estado</th></tr></thead>
        <tbody>{filas.map((e) => {
          const sel = seleccion?.tipo === 'arista' && seleccion.origen === e.origen && seleccion.destino === e.destino;
          const cortes = cortesDe[`${e.origen}>${e.destino}`];
          return (
            <tr key={e.origen + e.destino} data-sel={sel || undefined} tabIndex={0} onClick={() => onSelect({ tipo: 'arista', origen: e.origen, destino: e.destino })}
              onKeyDown={(ev) => { if (ev.key === 'Enter') onSelect({ tipo: 'arista', origen: e.origen, destino: e.destino }); }}>
              <td className="mono">{e.origen} → {e.destino}</td>
              <td>{nombre[e.origen]} → {nombre[e.destino]}</td>
              <td>{fmt(e.flujo)}</td><td>{inf(e.capacidad)}</td>
              <td><div className="use"><i style={{ width: `${Math.min(100, e.uso)}%`, background: COLORS[e.estado] }} /></div>{e.uso} %</td>
              <td>{fmt(e.capacidad - e.flujo)}</td>
              <td><span className="badge" data-tone={e.estado === 'corte' ? 'coral' : e.estado === 'saturada' ? 'sun' : 'lime'}>{e.estado === 'corte' ? `Corte ${cortes?.join(', ') ?? ''}` : e.estado === 'saturada' ? 'Al tope' : 'Holgura'}</span></td>
            </tr>
          );
        })}</tbody>
      </table></div>
    </section>
  );
}
