import { TIPO_NODO } from '@/shared/api';
import { Icon } from '@/shared/ui/Icon';
import { COLORS, claveArista, fmt, inf, nodosDeRed } from './FlowGraph';

const ESTADO = {
  corte: { t: 'Cuello de botella', tono: 'coral' },
  saturada: { t: 'Al tope', tono: 'sun' },
  holgura: { t: 'Con holgura', tono: 'lime' },
};
const TIPO = { ...TIPO_NODO, FUENTE: 'Fuente virtual', SUMIDERO: 'Sumidero virtual' };

function Barra({ valor, capacidad, estado }) {
  const pct = capacidad > 9000 ? 0 : Math.min(100, (100 * valor) / (capacidad || 1));
  return <div className="det__bar" aria-hidden="true"><i style={{ width: `${pct}%`, background: COLORS[estado] }} /></div>;
}

function Fila({ etiqueta, e, onSelect }) {
  return (
    <li>
      <button className="det__row" onClick={() => onSelect({ tipo: 'arista', origen: e.origen, destino: e.destino })}>
        <span className="det__row-t">{etiqueta}</span>
        <Barra valor={e.flujo} capacidad={e.capacidad} estado={e.estado} />
        <b>{fmt(e.flujo)}/{inf(e.capacidad)}</b>
      </button>
    </li>
  );
}

// Datos derivados del resultado: cortes a los que pertenece cada elemento y los que están en todos los cortes.
export function indices(resultado) {
  const cortesDe = {};
  const cortesNodo = {};
  resultado.cortes.forEach((c, i) => {
    [...c.aristas, ...c.virtuales].forEach(([a, b]) => { (cortesDe[claveArista(a, b)] ??= []).push(i + 1); });
    c.nodos.forEach((n) => { (cortesNodo[n] ??= []).push(i + 1); });
  });
  const todos = resultado.cortes.length;
  return { cortesDe, cortesNodo, todos };
}

function lecturaArista(e, cortes, todos) {
  const libre = e.capacidad - e.flujo;
  if (cortes?.length) {
    if (todos === 1) return `Es parte del único corte mínimo: es un cuello de botella. Si se amplía su capacidad, el flujo máximo puede subir.`;
    if (cortes.length === todos) return `Está en los ${todos} cortes mínimos: ampliarla es condición necesaria para que la red mueva más.`;
    return `Está en el corte ${cortes.join(' y ')} de ${todos}. Como el cuello de botella no es único, ampliarla sola no basta: también hay que ampliar los otros cortes.`;
  }
  if (e.flujo === 0) return 'La solución óptima no la usa: el algoritmo encontró rutas mejores o los destinos alcanzables desde aquí ya están llenos.';
  if (libre <= 1e-6) return 'Va llena, pero no limita el total: aunque la amplíes, el flujo máximo no sube porque el límite está en otra parte de la red.';
  return `Le sobran ${fmt(libre)} por semana: hoy no limita la red.`;
}

export function FlowDetalle({ red, resultado, seleccion, onSelect }) {
  const nodos = nodosDeRed(red);
  const porCodigo = Object.fromEntries(nodos.map((n) => [n.codigo, n]));
  const todas = [...resultado.virtuales, ...resultado.aristas];
  const { cortesDe, cortesNodo, todos } = indices(resultado);
  const capNodo = Object.fromEntries(resultado.nodos.map((n) => [n.nodo, n]));
  const nombre = (c) => porCodigo[c]?.nombre ?? c;
  const btnNodo = (c) => <button className="det__link" onClick={() => onSelect({ tipo: 'nodo', codigo: c })}>{c}</button>;

  if (!seleccion) {
    const criticos = resultado.criticos_en_todos_los_cortes ?? [];
    const llenas = resultado.aristas.filter((e) => e.estado !== 'holgura');
    return (
      <aside className="det" aria-live="polite">
        <h3 className="det__h"><Icon name="info" size={18} /> Explora la red</h3>
        <p className="hint">Toca un <b>nodo</b> (círculo) o una <b>arista</b> (línea) para ver sus detalles. Al pasar el cursor se resaltan sus conexiones. Esc limpia la selección.</p>
        {criticos.length > 0 && (
          <>
            <p className="det__k">En todos los cortes mínimos</p>
            <p className="hint">Ampliarlos es necesario para que la red crezca.</p>
            <div className="det__chips">
              {criticos.map((x) => (x.nodo
                ? <button key={x.nodo} className="chip" onClick={() => onSelect({ tipo: 'nodo', codigo: x.nodo })}>Nodo {x.nodo}</button>
                : <button key={x.join()} className="chip" onClick={() => onSelect({ tipo: 'arista', origen: x[0], destino: x[1] })}>{x[0] === 's' ? `Oferta ${x[1]}` : x[1] === 't' ? `Demanda ${x[0]}` : `${x[0]} → ${x[1]}`}</button>))}
            </div>
          </>
        )}
        <p className="det__k">Aristas al tope o en corte ({llenas.length})</p>
        <div className="det__chips">
          {llenas.map((e) => <button key={claveArista(e.origen, e.destino)} className="chip" data-k={e.estado} onClick={() => onSelect({ tipo: 'arista', origen: e.origen, destino: e.destino })}>{e.origen} → {e.destino}</button>)}
        </div>
      </aside>
    );
  }

  if (seleccion.tipo === 'arista') {
    const e = todas.find((x) => x.origen === seleccion.origen && x.destino === seleccion.destino);
    if (!e) return <aside className="det"><p className="hint">Esa arista no existe en este escenario.</p></aside>;
    const cortes = cortesDe[claveArista(e.origen, e.destino)];
    const info = red.aristas.find((x) => x.origen === e.origen && x.destino === e.destino);
    const uso = red.utilizacion.find((u) => u.origen === e.origen && u.destino === e.destino && u.unidad === 'UND');
    const virtual = e.origen === 's' || e.destino === 't';
    const estado = ESTADO[e.estado];
    return (
      <aside className="det" aria-live="polite">
        <button className="det__close icon-btn" onClick={() => onSelect(null)} aria-label="Cerrar detalle"><Icon name="close" size={16} /></button>
        <p className="det__k">{virtual ? (e.origen === 's' ? 'Oferta de un generador' : 'Demanda de un destino') : 'Arista (conexión)'}</p>
        <h3 className="det__h">{btnNodo(e.origen)} <Icon name="arrow" size={16} /> {btnNodo(e.destino)}</h3>
        <p className="hint">{nombre(e.origen)} → {nombre(e.destino)}</p>
        <span className="badge" data-tone={estado.tono}>{estado.t}</span>
        <div className="det__big"><b>{fmt(e.flujo)}</b><span>de {inf(e.capacidad)} equipos por semana</span></div>
        <Barra valor={e.flujo} capacidad={e.capacidad} estado={e.estado} />
        <dl className="det__facts">
          <div><dt>Capacidad c(u,v)</dt><dd>{inf(e.capacidad)}</dd></div>
          <div><dt>Flujo f(u,v)</dt><dd>{fmt(e.flujo)}</dd></div>
          <div><dt>Holgura</dt><dd>{e.capacidad > 9000 ? '∞' : fmt(e.capacidad - e.flujo)}</dd></div>
          <div><dt>Uso</dt><dd>{e.capacidad > 9000 ? '—' : `${e.uso} %`}</dd></div>
        </dl>
        <p className="det__read">{virtual
          ? (e.origen === 's'
            ? `${nombre(e.destino)} genera ${fmt(e.capacidad)} equipos por semana y la red logra recolectar ${fmt(e.flujo)}.${e.capacidad - e.flujo > 0 ? ` Quedan ${fmt(e.capacidad - e.flujo)} sin recolectar.` : ''}`
            : `${nombre(e.origen)} puede recibir ${inf(e.capacidad)} por semana y le llegan ${fmt(e.flujo)}.`) + (cortes ? ` ${lecturaArista(e, cortes, todos)}` : '')
          : lecturaArista(e, cortes, todos)}</p>
        {info?.requiere_excepcion && <p className="note" data-tone="aviso"><Icon name="shield" size={15} /> Esta ruta solo se usa con una excepción aprobada (ADR-004: preclasificación por técnico habilitado).</p>}
        {uso && <p className="hint">Uso real esta semana: {Number(uso.consumo)} de {Number(uso.capacidad)} ({Number(uso.utilizacion_pct ?? 0).toFixed(0)} %). Las transferencias que la superen se rechazan (RN-05).</p>}
      </aside>
    );
  }

  const c = seleccion.codigo;
  const n = porCodigo[c];
  if (!n) return <aside className="det"><p className="hint">Ese nodo no está en la red.</p></aside>;
  const entradas = todas.filter((e) => e.destino === c);
  const salidas = todas.filter((e) => e.origen === c);
  const reales = (l) => l.filter((e) => e.origen !== 's' && e.destino !== 't');
  const oferta = entradas.find((e) => e.origen === 's');
  const demanda = salidas.find((e) => e.destino === 't');
  const entra = entradas.reduce((s, e) => s + e.flujo, 0);
  const cn = capNodo[c];
  const cortes = cortesNodo[c];
  const estadoNodo = cn?.estado ?? (cortes ? 'corte' : null);
  let lectura;
  if (c === 's') lectura = `Nodo virtual: reúne la oferta de todos los generadores (${fmt(resultado.generacion)} equipos por semana). Sirve para calcular el flujo con un solo origen.`;
  else if (c === 't') lectura = `Nodo virtual: reúne la demanda de todos los destinos finales. Lo que llega aquí es el flujo máximo: ${fmt(resultado.flujo_maximo)} equipos por semana.`;
  else if (cn && cortes) lectura = todos === 1 ? `Su capacidad de procesamiento (${fmt(cn.capacidad)}) es el cuello de botella: ampliarla sube el flujo máximo.` : cortes.length === todos ? `Su procesamiento está en los ${todos} cortes: ampliarlo es necesario para crecer.` : `Su procesamiento está en el corte ${cortes.join(' y ')} de ${todos}; ampliarlo solo no basta.`;
  else if (cn && cn.estado === 'saturada') lectura = 'Procesa al máximo, pero no es lo que limita la red: el cuello de botella está en otra parte.';
  else if (cn) lectura = `Puede procesar ${fmt(cn.capacidad - cn.flujo)} más por semana.`;
  else if (oferta) lectura = oferta.capacidad - oferta.flujo > 0 ? `Genera ${fmt(oferta.capacidad)} por semana pero solo se recolectan ${fmt(oferta.flujo)}: ${fmt(oferta.capacidad - oferta.flujo)} se quedan esperando.` : `Toda su oferta (${fmt(oferta.capacidad)}) se recolecta.`;
  else if (demanda) lectura = `Recibe ${fmt(demanda.flujo)} de ${inf(demanda.capacidad)} que puede absorber por semana.`;
  else lectura = 'No tiene capacidad propia: lo limitan sus aristas de entrada y salida.';
  return (
    <aside className="det" aria-live="polite">
      <button className="det__close icon-btn" onClick={() => onSelect(null)} aria-label="Cerrar detalle"><Icon name="close" size={16} /></button>
      <p className="det__k">{TIPO[n.tipo] ?? n.tipo}</p>
      <h3 className="det__h"><span className="det__code">{c}</span> {n.nombre}</h3>
      {(n.centro || n.organizacion) && <p className="hint">{[n.centro && `Centro ${n.centro}`, n.organizacion].filter(Boolean).join(' · ')}</p>}
      {estadoNodo && <span className="badge" data-tone={ESTADO[estadoNodo].tono}>{ESTADO[estadoNodo].t}</span>}
      {cn && (
        <>
          <div className="det__big"><b>{fmt(cn.flujo)}</b><span>de {fmt(cn.capacidad)} que puede procesar por semana</span></div>
          <Barra valor={cn.flujo} capacidad={cn.capacidad} estado={cn.estado} />
          <p className="hint">En el modelo se divide en {c}<sub>in</sub> → {c}<sub>out</sub> con esa capacidad.</p>
        </>
      )}
      <dl className="det__facts">
        <div><dt>Entra</dt><dd>{fmt(entra)}</dd></div>
        <div><dt>Sale</dt><dd>{fmt(salidas.reduce((s, e) => s + e.flujo, 0))}</dd></div>
        {oferta && <div><dt>Genera</dt><dd>{fmt(oferta.capacidad)}</dd></div>}
        {demanda && <div><dt>Puede recibir</dt><dd>{inf(demanda.capacidad)}</dd></div>}
      </dl>
      <p className="det__read">{lectura}</p>
      {reales(entradas).length > 0 && <><p className="det__k">Llega desde</p><ul className="det__list">{reales(entradas).map((e) => <Fila key={e.origen} etiqueta={e.origen === 's' ? 'Oferta' : e.origen} e={e} onSelect={onSelect} />)}</ul></>}
      {reales(salidas).length > 0 && <><p className="det__k">Sale hacia</p><ul className="det__list">{reales(salidas).map((e) => <Fila key={e.destino} etiqueta={e.destino} e={e} onSelect={onSelect} />)}</ul></>}
      {(c === 's' || c === 't') && <ul className="det__list">{(c === 's' ? salidas : entradas).map((e) => <Fila key={e.origen + e.destino} etiqueta={c === 's' ? e.destino : e.origen} e={e} onSelect={onSelect} />)}</ul>}
    </aside>
  );
}
