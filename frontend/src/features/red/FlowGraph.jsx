import { useState } from 'react';
import { motion } from 'motion/react';

export const COLORS = { holgura: '#5BD6A0', saturada: '#F4C04E', corte: '#FF7A59' };
// Columna por tipo de nodo: s → generadores → acopios → evaluación → taller → destinos → t
const COLUMNA = { FUENTE: 0, GENERADOR: 1, ACOPIO: 2, EVALUACION: 3, REACONDICIONAMIENTO: 4, BENEFICIARIO: 5, RECICLAJE: 5, DISPOSICION: 5, SUMIDERO: 6 };
const W = 1000;
const H = 460;
const XS = [40, 175, 330, 490, 650, 805, 955];

export const claveArista = (o, d) => `${o}>${d}`;
export const nodosDeRed = (red) => [{ codigo: 's', nombre: 'Generación', tipo: 'FUENTE' },
  ...red.nodos.filter((n) => n.activo), { codigo: 't', nombre: 'Destino final', tipo: 'SUMIDERO' }];
export const inf = (c) => (c > 9000 ? '∞' : fmt(c));
export const fmt = (x) => (Number.isInteger(x) ? String(x) : Number(x).toFixed(1));

// Coloca automáticamente los nodos que vienen de la base: un nodo nuevo aparece sin tocar el código.
function layout(nodos) {
  const cols = {};
  nodos.forEach((n) => { (cols[COLUMNA[n.tipo] ?? 3] ??= []).push(n); });
  const pos = {};
  Object.entries(cols).forEach(([c, lista]) => {
    lista.sort((a, b) => a.codigo.localeCompare(b.codigo));
    const paso = (H - 100) / Math.max(lista.length, 1);
    lista.forEach((n, i) => { pos[n.codigo] = { x: XS[c], y: 60 + paso * (i + 0.5) }; });
  });
  return pos;
}

const curva = (a, b) => {
  if (Math.abs(a.x - b.x) < 5) {                     // misma columna (p. ej. R1→K1): arco hacia la derecha
    const dx = 60;
    return { d: `M${a.x} ${a.y} C${a.x + dx} ${a.y} ${b.x + dx} ${b.y} ${b.x} ${b.y}`, lx: a.x + dx * 0.75, ly: (a.y + b.y) / 2 };
  }
  const mx = (a.x + b.x) / 2;
  return { d: `M${a.x} ${a.y} C${mx} ${a.y} ${mx} ${b.y} ${b.x} ${b.y}`, lx: mx, ly: (a.y + b.y) / 2 };
};

const texto = (e, modo) => {
  if (modo === 'uso') return `${e.uso} %`;
  if (modo === 'holgura') { const h = e.capacidad - e.flujo; return e.capacidad > 9000 ? '∞' : h <= 0 ? 'llena' : `+${fmt(h)}`; }
  return `${fmt(e.flujo)}/${inf(e.capacidad)}`;
};

// Etiqueta con fondo para que se lea sobre las líneas
function Etiqueta({ x, y, children, color, fuerte }) {
  const ancho = String(children).length * 7 + 14;
  return (
    <g transform={`translate(${x} ${y})`} className="graph__pill" data-fuerte={fuerte || undefined}>
      <rect x={-ancho / 2} y={-10} width={ancho} height={20} rx={10} stroke={color} />
      <text textAnchor="middle" dy="4">{children}</text>
    </g>
  );
}

export function FlowGraph({ red, resultado, corte, seleccion, onSelect, modo = 'flujo' }) {
  const [hover, setHover] = useState(null);
  const nodos = nodosDeRed(red);
  const pos = layout(nodos);
  const enCorte = (o, d) => !!corte && [...corte.aristas, ...corte.virtuales].some(([a, b]) => a === o && b === d);
  const nodoEnCorte = (n) => !!corte?.nodos.includes(n);
  const aristas = [...resultado.virtuales, ...resultado.aristas];
  const maxFlujo = Math.max(1, ...aristas.filter((e) => e.capacidad < 9000).map((e) => e.flujo));
  const capNodo = Object.fromEntries(resultado.nodos.map((n) => [n.nodo, n]));

  // Foco: lo que el usuario señala (cursor) o eligió (clic). Todo lo demás se atenúa.
  const foco = hover ?? seleccion;
  let activasA = null;
  let activosN = null;
  if (foco?.tipo === 'nodo') {
    activasA = new Set(aristas.filter((e) => e.origen === foco.codigo || e.destino === foco.codigo).map((e) => claveArista(e.origen, e.destino)));
    activosN = new Set([foco.codigo, ...aristas.filter((e) => e.origen === foco.codigo).map((e) => e.destino), ...aristas.filter((e) => e.destino === foco.codigo).map((e) => e.origen)]);
  } else if (foco?.tipo === 'arista') {
    activasA = new Set([claveArista(foco.origen, foco.destino)]);
    activosN = new Set([foco.origen, foco.destino]);
  }
  const esSel = (e) => seleccion?.tipo === 'arista' && seleccion.origen === e.origen && seleccion.destino === e.destino;
  const elegir = (s) => (ev) => { ev.stopPropagation(); onSelect?.(s); };
  const teclado = (s) => (ev) => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); onSelect?.(s); } };

  const trazos = aristas.map((e) => {
    const a = pos[e.origen];
    const b = pos[e.destino];
    if (!a || !b) return null;
    const k = claveArista(e.origen, e.destino);
    const { d, lx, ly } = curva(a, b);
    const destacada = corte && enCorte(e.origen, e.destino);
    const activa = !activasA || activasA.has(k);
    const color = corte && !activasA ? (destacada ? COLORS.corte : 'rgb(255 255 255 / .22)') : COLORS[e.estado];
    const ancho = 2 + (Math.min(e.flujo, maxFlujo) / maxFlujo) * 9;
    const virtual = e.origen === 's' || e.destino === 't';
    return { e, k, d, lx, ly, destacada, activa, color, ancho, virtual };
  }).filter(Boolean);

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="graph" data-foco={!!activasA || undefined} data-cursor="native"
      role="group" aria-label={`Red con flujo máximo de ${resultado.flujo_maximo} equipos por semana. Toca un nodo o una arista para ver sus detalles.`}
      onClick={() => onSelect?.(null)}>
      <defs><filter id="glow" filterUnits="userSpaceOnUse" x="0" y="0" width={W} height={H}><feGaussianBlur stdDeviation="4" result="b" /><feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge></filter>
        <filter id="glowN" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="4" result="b" /><feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge></filter></defs>
      <rect width={W} height={H} fill="transparent" />

      {/* 1. aristas */}
      {trazos.map(({ e, k, d, destacada, activa, color, ancho, virtual }) => (
        <g key={k} className="graph__edge" opacity={activa ? (corte && !destacada && !activasA ? 0.55 : 1) : 0.12}>
          <path d={d} fill="none" stroke="rgb(255 255 255 / .08)" strokeWidth={ancho + 3} strokeLinecap="round" strokeDasharray={virtual ? '6 6' : undefined} />
          {esSel(e) && <path d={d} fill="none" stroke="#fff" strokeOpacity=".9" strokeWidth={ancho + 6} strokeLinecap="round" />}
          <motion.path d={d} fill="none" stroke={color} strokeLinecap="round" strokeDasharray={virtual ? '6 6' : undefined}
            filter={destacada || (!corte && e.estado === 'corte') ? 'url(#glow)' : undefined} animate={{ strokeWidth: e.flujo ? ancho : 1 }} />
          {e.flujo > 0 && !virtual && <path className="graph__pulse" d={d} fill="none" stroke="#fff" strokeOpacity=".5" strokeWidth={Math.max(1.5, ancho / 3)} strokeDasharray="4 16" strokeLinecap="round" />}
          {/* zona de toque amplia e invisible */}
          <path d={d} className="graph__hit" onClick={elegir({ tipo: 'arista', origen: e.origen, destino: e.destino })}
            onPointerEnter={() => setHover({ tipo: 'arista', origen: e.origen, destino: e.destino })} onPointerLeave={() => setHover(null)}>
            <title>{`${e.origen} → ${e.destino}: ${fmt(e.flujo)} de ${inf(e.capacidad)} (${e.uso} %)`}</title>
          </path>
        </g>
      ))}

      {/* 2. etiquetas por encima de todas las líneas */}
      {trazos.map(({ e, k, lx, ly, activa, color, destacada }) => (
        <g key={`l-${k}`} opacity={activa ? 1 : 0.08} pointerEvents="none">
          <Etiqueta x={lx} y={ly} color={corte && !activasA ? (destacada ? COLORS.corte : 'rgb(255 255 255 / .2)') : color} fuerte={activasA && activa}>{texto(e, modo)}</Etiqueta>
        </g>
      ))}

      {/* 3. nodos */}
      {nodos.map((n) => {
        const p = pos[n.codigo];
        const cn = capNodo[n.codigo];
        const rojo = nodoEnCorte(n.codigo) || (!corte && cn?.estado === 'corte');
        const activo = !activosN || activosN.has(n.codigo);
        const elegido = seleccion?.tipo === 'nodo' && seleccion.codigo === n.codigo;
        const enfocado = foco?.tipo === 'nodo' && foco.codigo === n.codigo;
        const sel = { tipo: 'nodo', codigo: n.codigo };
        const nombre = enfocado || n.nombre.length <= 20 ? n.nombre : `${n.nombre.slice(0, 19)}…`;
        return (
          <g key={n.codigo} transform={`translate(${p.x} ${p.y})`} className="graph__node" opacity={activo ? 1 : 0.25}
            role="button" tabIndex={0} aria-pressed={elegido} aria-label={`${n.codigo}, ${n.nombre}. Ver detalles`}
            onClick={elegir(sel)} onKeyDown={teclado(sel)}
            onPointerEnter={() => setHover(sel)} onPointerLeave={() => setHover(null)} onFocus={() => setHover(sel)} onBlur={() => setHover(null)}>
            <circle r="36" fill="transparent" />
            {elegido && <circle r="35" fill="none" stroke="#fff" strokeWidth="2" strokeDasharray="5 5" className="graph__sel" />}
            {cn && <circle r="29" fill="none" stroke={rojo ? COLORS.corte : COLORS[cn.estado]} strokeWidth="4" strokeDasharray={`${Math.min(1, cn.flujo / cn.capacidad) * 182} 182`} transform="rotate(-90)" filter={rojo ? 'url(#glowN)' : undefined} />}
            <circle r="21" className="graph__dot" stroke={rojo ? COLORS.corte : '#B6F36A'} data-on={enfocado || elegido || undefined} />
            <text textAnchor="middle" dy="4" className="graph__id">{n.codigo}</text>
            <text textAnchor="middle" y="46" className="graph__name" data-on={enfocado || undefined}>{nombre}</text>
            {cn && <g pointerEvents="none"><Etiqueta x={0} y={-47} color={rojo ? COLORS.corte : COLORS[cn.estado]}>{modo === 'uso' ? `procesa ${cn.uso} %` : `procesa ${fmt(cn.flujo)}/${fmt(cn.capacidad)}`}</Etiqueta></g>}
          </g>
        );
      })}
    </svg>
  );
}
