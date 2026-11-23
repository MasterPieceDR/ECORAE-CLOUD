import { useMemo, useState } from 'react';
import { api } from '@/shared/api';
import { useAuth, useCatalogos } from '@/features/auth';
import { Modal } from '@/shared/ui/Modal';
import { useToast } from '@/shared/ui/Toast';

const ETIQUETA = { ram_gb: 'RAM (GB)', almacenamiento_gb: 'Almacenamiento (GB)', procesador: 'Procesador', pulgadas: 'Pulgadas', quimica: 'Química de la batería' };
const NUMERICO = /(_gb|pulgadas)$/;

// Registro de un dispositivo (RN-01). Los atributos obligatorios salen del esquema de la categoría en la base.
export function RegistrarDialog({ onClose, onCreated }) {
  const { c } = useCatalogos();
  const { can, user } = useAuth();
  const toast = useToast();
  const hojas = useMemo(() => c.categorias.filter((x) => x.nivel >= 3), [c.categorias]);
  const [cat, setCat] = useState(hojas.find((x) => x.codigo === 'PORTATIL')?.codigo ?? hojas[0]?.codigo);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const categoria = c.categorias.find((x) => x.codigo === cat);
  const requeridos = categoria?.requeridos ?? [];
  const extras = Object.keys(categoria?.propiedades ?? {}).filter((k) => !requeridos.includes(k));
  const enNombreDeOtro = can('RECEPCION.REGISTRAR');            // un operador registra entregas directas de otras organizaciones
  const generadoras = c.organizaciones.filter((o) => o.nodo?.startsWith('G'));
  const padres = [...new Set(hojas.map((h) => h.padre))];

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true); setError('');
    const d = Object.fromEntries(new FormData(e.currentTarget));
    const atributos = {};
    [...requeridos, ...extras].forEach((k) => { if (d[`a_${k}`] !== '' && d[`a_${k}`] != null) atributos[k] = NUMERICO.test(k) ? Number(d[`a_${k}`]) : d[`a_${k}`]; });
    try {
      const r = await api.registrarDispositivo({
        codigo: d.codigo?.trim().toUpperCase() || null, categoria: cat, peso_kg: Number(d.peso), contiene_almacenamiento: d.almacenamiento === 'on',
        marca: d.marca || null, modelo: d.modelo?.trim() || null, numero_serie: d.serie?.trim() || null, anio: d.anio ? Number(d.anio) : null,
        atributos, organizacion_origen: d.organizacion || null,
      });
      toast(`Equipo ${r.codigo} registrado.`);
      onCreated(r.codigo);
    } catch (err) { setError(err.message); setBusy(false); }
  };

  return (
    <Modal title="Registrar equipo" onClose={onClose} wide>
      <form className="accion-form" onSubmit={submit}>
        <div className="two">
          <label className="field">Categoría *
            <select value={cat} onChange={(e) => setCat(e.target.value)}>
              {padres.map((p) => (
                <optgroup key={p} label={c.categorias.find((x) => x.codigo === p)?.nombre ?? p}>
                  {hojas.filter((h) => h.padre === p).map((h) => <option key={h.codigo} value={h.codigo}>{h.nombre}</option>)}
                </optgroup>
              ))}
            </select>
          </label>
          <label className="field">Código (opcional)<input name="codigo" maxLength={40} pattern="[A-Za-z0-9][A-Za-z0-9_\-.]{1,39}" placeholder="Se asigna solo" /></label>
        </div>
        <div className="three">
          <label className="field">Peso (kg) *<input name="peso" type="number" step="0.01" min="0.01" required /></label>
          <label className="field">Marca<select name="marca" defaultValue=""><option value="">Sin marca</option>{c.marcas.map((m) => <option key={m.codigo} value={m.codigo}>{m.nombre}</option>)}</select></label>
          <label className="field">Año<input name="anio" type="number" min="1970" max={new Date().getFullYear()} /></label>
        </div>
        <div className="two">
          <label className="field">Modelo<input name="modelo" maxLength={120} /></label>
          <label className="field">Número de serie<input name="serie" maxLength={80} /></label>
        </div>
        {(requeridos.length > 0 || extras.length > 0) && (
          <div className="three">
            {[...requeridos, ...extras].map((k) => (
              <label key={k} className="field">{ETIQUETA[k] ?? k}{requeridos.includes(k) ? ' *' : ''}
                <input name={`a_${k}`} type={NUMERICO.test(k) ? 'number' : 'text'} step="any" min="0" required={requeridos.includes(k)} />
              </label>
            ))}
          </div>
        )}
        <label className="check" key={cat}><input type="checkbox" name="almacenamiento" defaultChecked={categoria?.contiene_almacenamiento} /> Tiene almacenamiento de datos (exigirá certificado de borrado antes de donarse)</label>
        {enNombreDeOtro && (
          <label className="field">Organización de origen<select name="organizacion" defaultValue=""><option value="">{user.organizacion?.nombre} (mi organización)</option>{generadoras.map((o) => <option key={o.uid} value={o.uid}>{o.nombre}</option>)}</select></label>
        )}
        {error && <p className="error" role="alert">{error}</p>}
        <div className="actions-row">
          <button type="button" className="btn btn--ghost" onClick={onClose}>Cancelar</button>
          <button className="btn btn--primary" disabled={busy}>{busy ? 'Guardando...' : 'Registrar'}</button>
        </div>
      </form>
    </Modal>
  );
}
