import { useEffect, useState } from 'react';
import { api } from '@/shared/api';
import { useAuth, useCatalogos } from '@/features/auth';
import { useAsync } from '@/shared/hooks/useAsync';
import { Modal } from '@/shared/ui/Modal';
import './catalogo.css';

export function CatalogoPage() {
  const { can } = useAuth(), { c } = useCatalogos();
  const puede = can('CATALOGO.ADMINISTRAR') || can('RED.GESTIONAR'), admin = can('CATALOGO.ADMINISTRAR');
  const [categoria, setCategoria] = useState(''), [dialogo, setDialogo] = useState(null), [error, setError] = useState(''), [progreso, setProgreso] = useState(null), [ahora, setAhora] = useState(Date.now());
  const { data, reload, error: errorCarga } = useAsync(() => api.modelos({ categoria, incluir_inactivos: true }), [categoria]);
  useEffect(() => { const t = setInterval(() => setAhora(Date.now()), 30000); return () => clearInterval(t); }, []);
  const operacion = async (fn) => { setError(''); try { await fn(); setDialogo(null); reload(); } catch (e) { setError(e.message); } };
  const imagen = async (m, e) => { const file = e.target.files?.[0]; if (!file) return; setProgreso(0); await operacion(() => api.subirImagenModelo(m.uid, file, setProgreso)); setProgreso(null); e.target.value = ''; };
  return <><div className="page-head"><div><h1 className="page-title">Catálogo</h1><p className="page-sub">Modelos de equipos por categoría</p></div>{puede && <button className="btn btn--primary" onClick={() => setDialogo({})}>Crear modelo</button>}</div>
    <label className="field">Categoría<select value={categoria} onChange={(e) => setCategoria(e.target.value)}><option value="">Todas</option>{c.categorias.filter((x) => x.nivel >= 3).map((x) => <option key={x.codigo} value={x.codigo}>{x.nombre}</option>)}</select></label>
    {(error || errorCarga) && <p role="alert" className="error">{error || errorCarga.message}</p>}{progreso !== null && <progress value={progreso} max="100" aria-label="Subida de imagen" />}
    <div className="card tbl-wrap catalogo-table"><table className="tbl"><thead><tr><th>Categoría</th><th>Marca</th><th>Modelo</th><th>Estado</th><th>Acciones</th></tr></thead><tbody>{data?.map((m) => {
      const restante = Math.max(0, new Date(m.editable_hasta).getTime() - ahora), editable = restante > 0;
      return <tr key={m.uid}><td data-label="Categoría">{m.categoria_nombre}</td><td data-label="Marca">{m.marca_nombre}</td><td data-label="Modelo">{m.nombre}{!m.activo && ' · inactivo'}</td><td data-label="Estado"><span className="badge" data-tone={editable ? 'lime' : 'gray'}>{editable ? `Editable · quedan ${Math.floor(restante/3600000)} h ${Math.floor(restante/60000)%60} min` : `Bloqueado desde ${new Intl.DateTimeFormat('es-EC', { timeZone:'America/Guayaquil', dateStyle:'short', timeStyle:'short' }).format(new Date(m.editable_hasta))}`}</span></td><td data-label="Acciones"><div className="catalogo-actions">
      {m.tiene_imagen && <button className="btn btn--ghost btn--sm" onClick={() => operacion(async () => { const r = await api.imagenModelo(m.uid); window.open(r.url, '_blank', 'noopener'); })}>Ver foto</button>}
      {puede && <><button className="btn btn--ghost btn--sm" disabled={!editable} onClick={() => setDialogo(m)}>Editar</button><label className="btn btn--ghost btn--sm file-button">Subir foto<input className="sr" aria-label={`Subir foto de ${m.nombre}`} type="file" accept="image/jpeg,image/png,image/webp" disabled={!editable || progreso !== null} onChange={(e) => imagen(m,e)} /></label></>}
      {admin && !editable && <button className="btn btn--ghost btn--sm" onClick={() => setDialogo({ reapertura: m })}>Reabrir 24 h</button>}</div></td></tr>;
    })}</tbody></table></div>
    {dialogo && <Modal title={dialogo.reapertura ? 'Reabrir modelo' : dialogo.uid ? 'Editar modelo' : 'Crear modelo'} onClose={() => { setDialogo(null); setError(''); }}><form className="accion-form" onSubmit={(e) => { e.preventDefault(); const d = Object.fromEntries(new FormData(e.currentTarget));
      if (dialogo.reapertura) operacion(() => api.reabrirModelo(dialogo.reapertura.uid, d.motivo));
      else { const base = { nombre:d.nombre, anio:d.anio ? Number(d.anio) : null, peso:d.peso ? Number(d.peso) : null }; operacion(() => dialogo.uid ? api.actualizarModelo(dialogo.uid, { ...base, activo:d.activo === 'on' }) : api.crearModelo({ ...base, categoria:d.categoria, marca:d.marca })); } }}>
      {dialogo.reapertura ? <label className="field">Motivo<input name="motivo" minLength={5} maxLength={300} required /></label> : <>
      {!dialogo.uid && <><label className="field">Categoría<select name="categoria" required>{c.categorias.filter((x) => x.nivel >= 3).map((x) => <option key={x.codigo} value={x.codigo}>{x.nombre}</option>)}</select></label><label className="field">Marca<select name="marca" required>{c.marcas.map((x) => <option key={x.codigo} value={x.codigo}>{x.nombre}</option>)}</select></label></>}
      <label className="field">Nombre<input name="nombre" defaultValue={dialogo.nombre} maxLength={120} required /></label><label className="field">Año<input name="anio" type="number" min="1970" max="2100" defaultValue={dialogo.anio_lanzamiento ?? ''} /></label><label className="field">Peso (kg)<input name="peso" type="number" min="0.01" max="2000" step="0.01" defaultValue={dialogo.peso_kg ?? ''} /></label>{dialogo.uid && <label className="check"><input type="checkbox" name="activo" defaultChecked={dialogo.activo} /> Activo</label>}</>}
      {error && <p className="error" role="alert">{error}</p>}<div className="actions-row"><button type="button" className="btn btn--ghost" onClick={() => setDialogo(null)}>Cancelar</button><button className="btn btn--primary">Guardar</button></div></form></Modal>}
  </>;
}
