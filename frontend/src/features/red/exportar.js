import { fmt, nodosDeRed } from './FlowGraph';
import { indices } from './FlowDetalle';

function bajar(blob, nombre) {
  const url = URL.createObjectURL(blob);
  const a = Object.assign(document.createElement('a'), { href: url, download: nombre });
  document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}

// Flujo por arista y por nodo en CSV (separador ";" y BOM para que Excel en español lo abra bien)
export function descargarCSV(red, r, nombre) {
  const nom = Object.fromEntries(nodosDeRed(red).map((n) => [n.codigo, n.nombre]));
  const { cortesDe, cortesNodo } = indices(r);
  const q = (x) => `"${String(x ?? '').replace(/"/g, '""')}"`;
  const filas = [['tipo', 'origen', 'destino', 'nombre_origen', 'nombre_destino', 'capacidad', 'flujo', 'uso_pct', 'holgura', 'estado', 'cortes']];
  [...r.virtuales, ...r.aristas].forEach((e) => {
    const tipo = e.origen === 's' ? 'oferta' : e.destino === 't' ? 'demanda' : 'arista';
    filas.push([tipo, e.origen, e.destino, nom[e.origen], nom[e.destino], fmt(e.capacidad), fmt(e.flujo), e.uso, fmt(e.capacidad - e.flujo), e.estado, (cortesDe[`${e.origen}>${e.destino}`] ?? []).join(' ')]);
  });
  r.nodos.forEach((n) => filas.push(['procesamiento_nodo', n.nodo, n.nodo, nom[n.nodo], nom[n.nodo], fmt(n.capacidad), fmt(n.flujo), n.uso, fmt(n.capacidad - n.flujo), n.estado, (cortesNodo[n.nodo] ?? []).join(' ')]));
  filas.push([]);
  filas.push(['resumen', r.escenario, '', r.nombre, '', fmt(r.generacion), fmt(r.flujo_maximo), r.cobertura, '', `${r.cortes.length} corte(s) mínimo(s)`, r.hash ?? '']);
  const csv = filas.map((f) => f.map(q).join(';')).join('\r\n');
  bajar(new Blob(['﻿', csv], { type: 'text/csv;charset=utf-8' }), nombre);
}

// Copia los estilos calculados al SVG para que la imagen se vea igual fuera de la página
function conEstilos(origen) {
  const copia = origen.cloneNode(true);
  const a = origen.querySelectorAll('*');
  const b = copia.querySelectorAll('*');
  const props = ['fill', 'stroke', 'stroke-width', 'font-size', 'font-weight', 'font-family', 'paint-order', 'opacity', 'stroke-opacity', 'fill-opacity'];
  a.forEach((el, i) => {
    const cs = getComputedStyle(el);
    b[i].setAttribute('style', props.map((p) => `${p}:${cs.getPropertyValue(p)}`).join(';'));
  });
  copia.querySelectorAll('.graph__pulse, .graph__hit').forEach((x) => x.remove());
  return copia;
}

export async function descargarPNG(svg, nombre) {
  if (!svg) return;
  const copia = conEstilos(svg);
  const [, , w, h] = svg.getAttribute('viewBox').split(' ').map(Number);
  const escala = 2;
  copia.setAttribute('width', w); copia.setAttribute('height', h);
  const fondo = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
  fondo.setAttribute('width', w); fondo.setAttribute('height', h); fondo.setAttribute('fill', getComputedStyle(document.documentElement).getPropertyValue('--bg').trim());
  copia.insertBefore(fondo, copia.firstChild);
  const datos = new XMLSerializer().serializeToString(copia);
  const img = new Image();
  img.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(datos)}`;
  await img.decode();
  const canvas = Object.assign(document.createElement('canvas'), { width: w * escala, height: h * escala });
  const ctx = canvas.getContext('2d');
  ctx.scale(escala, escala);
  ctx.drawImage(img, 0, 0, w, h);
  canvas.toBlob((blob) => blob && bajar(blob, nombre), 'image/png');
}
