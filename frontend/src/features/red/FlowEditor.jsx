import { useState } from 'react';
import { api } from '@/shared/api';
import { Icon } from '@/shared/ui/Icon';
import { Modal } from '@/shared/ui/Modal';
import { useToast } from '@/shared/ui/Toast';
import { fmt } from './FlowGraph';

const num = (v) => (v === '' || v == null ? null : Number(v));

// Edita lo seleccionado en un escenario BORRADOR. Cada cambio recalcula el flujo en la API y queda auditado en la base.
export function EditarSeleccion({ escenario, seleccion, resultado, onAplicado }) {
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const k = seleccion.tipo === 'arista' ? `${seleccion.origen}>${seleccion.destino}` : seleccion.codigo;
  const aristaAjustada = seleccion.tipo === 'arista' && escenario.cambios_aristas.find((x) => x.origen === seleccion.origen && x.destino === seleccion.destino);
  const nodoAjustado = seleccion.tipo === 'nodo' && escenario.cambios_nodos.find((x) => x.nodo === seleccion.codigo);

  const enviar = async (fn, mensaje) => {
    setBusy(true); setError('');
    try { const r = await fn(); onAplicado(r); toast(mensaje); } catch (e) { setError(e.message); }
    setBusy(false);
  };

  if (seleccion.tipo === 'arista') {
    const { origen, destino } = seleccion;
    if (origen === 's' || destino === 't') return <div className="det__edit"><p className="hint">La oferta y la demanda se editan en el nodo {origen === 's' ? destino : origen}.</p></div>;
    const e = resultado.aristas.find((x) => x.origen === origen && x.destino === destino);
    return (
      <form key={k} className="det__edit" onSubmit={(ev) => {
        ev.preventDefault();
        const d = new FormData(ev.currentTarget);
        enviar(() => api.ajustarArista(escenario.codigo, { origen, destino, capacidad: num(d.get('capacidad')), activa: d.get('activa') === 'on' ? null : false, motivo: d.get('motivo') }),
          `Arista ${origen} → ${destino} ajustada en ${escenario.codigo}.`);
      }}>
        <p className="det__k"><Icon name="wrench" size={14} /> Ajustar en {escenario.codigo}</p>
        <label className="field">Capacidad por semana<input name="capacidad" type="number" min="0" max="100000" step="1" defaultValue={e ? fmt(e.capacidad) : ''} required /></label>
        <label className="check"><input type="checkbox" name="activa" defaultChecked={aristaAjustada?.activa !== false} /> Ruta activa</label>
        <label className="field">Motivo *<input name="motivo" required minLength={3} maxLength={300} defaultValue={aristaAjustada?.motivo ?? ''} placeholder="Ej.: segundo camión los sábados" /></label>
        {error && <p className="error" role="alert">{error}</p>}
        <div className="actions-row">
          {aristaAjustada && <button type="button" className="btn btn--ghost btn--sm" disabled={busy} onClick={() => enviar(() => api.ajustarArista(escenario.codigo, { origen, destino, capacidad: null, activa: null }), 'Ajuste quitado: vuelve a heredar del escenario base.')}>Quitar ajuste</button>}
          <button className="btn btn--primary btn--sm" disabled={busy}>{busy ? 'Calculando...' : 'Aplicar y recalcular'}</button>
        </div>
      </form>
    );
  }

  const c = seleccion.codigo;
  if (c === 's' || c === 't') return null;
  const cn = resultado.nodos.find((x) => x.nodo === c);
  const oferta = resultado.virtuales.find((x) => x.origen === 's' && x.destino === c);
  const demanda = resultado.virtuales.find((x) => x.origen === c && x.destino === 't');
  if (!cn && !oferta && !demanda) return <div className="det__edit"><p className="hint">Este nodo no tiene capacidad propia, oferta ni demanda: edita sus aristas.</p></div>;
  return (
    <form key={k} className="det__edit" onSubmit={(ev) => {
      ev.preventDefault();
      const d = new FormData(ev.currentTarget);
      enviar(() => api.ajustarNodo(escenario.codigo, { nodo: c, capacidad: num(d.get('capacidad')), oferta: num(d.get('oferta')), demanda: num(d.get('demanda')) }),
        `Nodo ${c} ajustado en ${escenario.codigo}.`);
    }}>
      <p className="det__k"><Icon name="wrench" size={14} /> Ajustar en {escenario.codigo}</p>
      {cn && <label className="field">Puede procesar por semana<input name="capacidad" type="number" min="0" max="100000" step="1" defaultValue={fmt(cn.capacidad)} /></label>}
      {oferta && <label className="field">Genera por semana (oferta)<input name="oferta" type="number" min="0" max="100000" step="1" defaultValue={fmt(oferta.capacidad)} /></label>}
      {demanda && demanda.capacidad < 9000 && <label className="field">Puede recibir por semana (demanda)<input name="demanda" type="number" min="0" max="100000" step="1" defaultValue={fmt(demanda.capacidad)} /></label>}
      {error && <p className="error" role="alert">{error}</p>}
      <div className="actions-row">
        {nodoAjustado && <button type="button" className="btn btn--ghost btn--sm" disabled={busy} onClick={() => enviar(() => api.ajustarNodo(escenario.codigo, { nodo: c, capacidad: null, oferta: null, demanda: null }), 'Ajuste quitado: vuelve a heredar del escenario base.')}>Quitar ajuste</button>}
        <button className="btn btn--primary btn--sm" disabled={busy}>{busy ? 'Calculando...' : 'Aplicar y recalcular'}</button>
      </div>
    </form>
  );
}

export function NuevoEscenario({ escenarios, base, onClose, onCreado }) {
  const [error, setError] = useState('');
  const libre = (() => { for (let i = 5; i < 100; i += 1) if (!escenarios.some((e) => e.codigo === `E${i}`)) return `E${i}`; return ''; })();
  const submit = async (ev) => {
    const d = Object.fromEntries(new FormData(ev.currentTarget));
    setError('');
    try { const r = await api.crearEscenario(d); onCreado(r.codigo); } catch (e) { setError(e.message); }
  };
  return (
    <Modal title="Nuevo escenario" onClose={onClose} onSubmit={submit}>
      <p className="hint">Hereda todas las capacidades del escenario base. Después tocas un nodo o una arista y ajustas solo lo que cambia. Los escenarios del capítulo (E0–E4) no se modifican.</p>
      <div className="two">
        <label className="field">Código *<input name="codigo" required pattern="[A-Za-z][A-Za-z0-9_\-]{1,19}" defaultValue={libre} /></label>
        <label className="field">Hereda de<select name="base" defaultValue={base}>{escenarios.map((e) => <option key={e.codigo} value={e.codigo}>{e.codigo} · {e.nombre}</option>)}</select></label>
      </div>
      <label className="field">Nombre *<input name="nombre" required minLength={3} maxLength={120} placeholder="Ej.: Tercer turno en el laboratorio" /></label>
      <label className="field">Descripción<input name="descripcion" maxLength={500} placeholder="Qué quieres probar" /></label>
      {error && <p className="error" role="alert">{error}</p>}
      <div className="actions-row"><button type="button" className="btn btn--ghost" onClick={onClose}>Cancelar</button><button className="btn btn--primary">Crear</button></div>
    </Modal>
  );
}
