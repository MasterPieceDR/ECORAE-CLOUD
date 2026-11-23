import { useEffect, useRef, useState } from 'react';
import { api } from '@/shared/api';
import { useCatalogos } from '@/features/auth';

export function ModeloSerie({ categoria, inicial = {}, excluir, almacenamiento, onAlmacenamiento }) {
  const { c } = useCatalogos();
  const [modelos, setModelos] = useState([]), [marca, setMarca] = useState(inicial.marca ?? ''), [modelo, setModelo] = useState(inicial.modelo_uid ?? (inicial.modelo ? 'otro' : ''));
  const [serie, setSerie] = useState(inicial.numero_serie ?? ''), [estado, setEstado] = useState(null);
  const input = useRef(null);
  useEffect(() => { let activo = true; api.modelos({ categoria }).then((r) => activo && setModelos(r)).catch(() => activo && setModelos([])); return () => { activo = false; }; }, [categoria]);
  useEffect(() => {
    if (!serie.trim()) { setEstado(null); input.current?.setCustomValidity(''); return; }
    let activo = true; setEstado({ mensaje: 'Comprobando serie...', pendiente: true }); input.current?.setCustomValidity('Comprobando disponibilidad de la serie');
    const t = setTimeout(() => api.serieDisponible(serie, excluir).then((r) => { if (activo) { setEstado(r); input.current?.setCustomValidity(r.valida && r.disponible ? '' : r.mensaje); } }).catch(() => { if (activo) { setEstado({ mensaje: 'No se pudo comprobar la serie.' }); input.current?.setCustomValidity('No se pudo comprobar la serie'); } }), 400);
    return () => { activo = false; clearTimeout(t); };
  }, [serie, excluir]);
  const cambiarModelo = (valor) => { setModelo(valor); const elegido = modelos.find((x) => x.uid === valor); if (elegido) setMarca(elegido.marca); };
  return <>
    <label className="field">Marca<select name="marca" value={marca} onChange={(e) => { setMarca(e.target.value); setModelo(''); }}><option value="">Sin marca</option>{c.marcas.map((m) => <option key={m.codigo} value={m.codigo}>{m.nombre}</option>)}</select></label>
    <label className="field">Modelo<select name="modelo_uid" value={modelo} onChange={(e) => cambiarModelo(e.target.value)}><option value="">Sin modelo</option>{modelos.filter((m) => !marca || m.marca === marca).map((m) => <option key={m.uid} value={m.uid}>{m.marca_nombre} · {m.nombre}</option>)}<option value="otro">Otro modelo (escribir)</option></select></label>
    {modelo === 'otro' && <label className="field">Otro modelo<input name="modelo" maxLength={120} defaultValue={inicial.modelo_uid ? '' : inicial.modelo ?? ''} /></label>}
    <label className="field">Número de serie {almacenamiento && '*'}<input ref={input} name="serie" maxLength={40} required={almacenamiento} value={serie} onChange={(e) => setSerie(e.target.value.toUpperCase())} aria-describedby="serie-estado" /><small id="serie-estado" aria-live="polite">{estado?.mensaje}</small></label>
    <label className="check"><input type="checkbox" name="almacenamiento" checked={almacenamiento} onChange={(e) => onAlmacenamiento(e.target.checked)} /> Tiene almacenamiento de datos</label>
  </>;
}
