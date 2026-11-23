import { useMemo, useState } from 'react';
import { api } from '@/shared/api';
import { useCatalogos } from '@/features/auth';
import { ModeloSerie } from './ModeloSerie';
import { Modal } from '@/shared/ui/Modal';
import { EvidenciaInput } from '@/shared/ui/EvidenciaInput';
import { useToast } from '@/shared/ui/Toast';

// Un formulario por acción. El contexto (centros, destinos, criterios, tipos de evidencia) lo calcula el backend
// con el estado del objeto y los permisos del usuario; la base vuelve a validar todo al confirmar.
export function AccionDialog({ accion, objeto, dispositivo, onClose, onDone }) {
  const toast = useToast();
  const [error, setError] = useState('');
  const [fase, setFase] = useState('');
  const [progreso, setProgreso] = useState(null);
  const ctx = accion.contexto;
  const Form = FORMS[accion.codigo];

  const ejecutar = async (fn) => {
    setError(''); setFase('Guardando...');
    try {
      const r = await fn({
        subir: async (ev, opciones = {}) => {
          if (!ev?.file) return null;
          setFase('Subiendo evidencia...'); setProgreso(0);
          const uid = await api.subirEvidencia({ tipo: ev.tipo, file: ev.file, ...opciones }, setProgreso);
          setProgreso(null); setFase('Guardando...');
          return uid;
        },
      });
      toast(r?.numero ? `Listo: ${r.numero}.` : 'Operación registrada.');
      onDone();
    } catch (err) {
      setError(err.message + (err.requestId ? ` (ref. ${err.requestId.slice(0, 8)})` : ''));
      setFase(''); setProgreso(null);
    }
  };

  return (
    <Modal title={accion.titulo} onClose={onClose} wide={accion.codigo === 'EVALUAR'}>
      <p className="hint">{accion.descripcion}</p>
      <Form ctx={ctx} objeto={objeto} dispositivo={dispositivo} ejecutar={ejecutar} ocupado={!!fase}>
        {error && <p className="error" role="alert">{error}</p>}
        {progreso !== null && <div className="progress" role="progressbar" aria-valuenow={progreso} aria-valuemin="0" aria-valuemax="100"><i style={{ width: `${progreso}%` }} /></div>}
        <div className="actions-row">
          <button type="button" className="btn btn--ghost" onClick={onClose}>Cancelar</button>
          <button className={`btn ${accion.codigo === 'ANULAR' ? 'btn--danger' : 'btn--primary'}`} disabled={!!fase}>{fase || (accion.codigo === 'ANULAR' ? 'Anular registro' : 'Confirmar')}</button>
        </div>
      </Form>
    </Modal>
  );
}

const datos = (e) => Object.fromEntries(new FormData(e.currentTarget));
const nulo = (v) => (v === '' || v == null ? null : v);

function Formulario({ onSubmit, children }) {
  return <form className="accion-form" onSubmit={(e) => { e.preventDefault(); onSubmit(e); }}>{children}</form>;
}

function Solicitar({ ctx, objeto, ejecutar, children }) {
  return (
    <Formulario onSubmit={(e) => { const d = datos(e); ejecutar(() => api.solicitar({ objetos: [objeto.uid], centro_destino: d.centro, fecha_preferida: nulo(d.fecha), sector: nulo(d.sector) })); }}>
      <label className="field">Centro de acopio<select name="centro" required>{ctx.centros.map((c) => <option key={c.codigo} value={c.codigo}>{c.codigo} · {c.nombre}</option>)}</select></label>
      <div className="two">
        <label className="field">Fecha preferida<input name="fecha" type="date" min={new Date().toISOString().slice(0, 10)} /></label>
        <label className="field">Sector de referencia<input name="sector" maxLength={120} placeholder="Ej.: Campus norte" /></label>
      </div>
      <p className="hint">Solo se guarda el sector, no la dirección exacta (minimización de datos, RNF-10).</p>
      {children}
    </Formulario>
  );
}

function Programar({ ctx, ejecutar, children }) {
  const manana = new Date(Date.now() + 86400000).toISOString().slice(0, 16);
  return (
    <Formulario onSubmit={(e) => { const d = datos(e); ejecutar(() => api.programar(ctx.solicitud, { fecha: new Date(d.fecha).toISOString(), transportista: nulo(d.transportista) })); }}>
      <p className="note">Solicitud <b>{ctx.numero}</b> hacia <b>{ctx.centro}</b>. La base comprueba que la ruta generador → acopio tenga capacidad libre esta semana (RN-05).</p>
      <div className="two">
        <label className="field">Fecha y hora<input name="fecha" type="datetime-local" required defaultValue={manana} /></label>
        <label className="field">Transporte<input name="transportista" maxLength={120} placeholder="Camión 01" /></label>
      </div>
      {children}
    </Formulario>
  );
}

function Recibir({ ctx, objeto, ejecutar, children }) {
  const [centro, setCentro] = useState(ctx.centros[0]?.codigo);
  const [ev, setEv] = useState(null);
  const ubic = ctx.centros.find((c) => c.codigo === centro)?.ubicaciones ?? [];
  return (
    <Formulario onSubmit={(e) => {
      const d = datos(e);
      ejecutar(async ({ subir }) => api.recibir({ objetos: [objeto.uid], centro, ubicacion: nulo(d.ubicacion), conformidad: d.conformidad,
        solicitud: ctx.solicitud ?? null, peso_verificado: d.peso ? Number(d.peso) : null, evidencias: [await subir(ev)].filter(Boolean) }));
    }}>
      <div className="two">
        <label className="field">Centro<select value={centro} onChange={(e) => setCentro(e.target.value)}>{ctx.centros.map((c) => <option key={c.codigo} value={c.codigo}>{c.codigo} · {c.nombre}</option>)}</select></label>
        <label className="field">Ubicación<select name="ubicacion">{ubic.filter((u) => u.tipo !== 'RAIZ').map((u) => <option key={u.codigo} value={u.codigo}>{u.nombre}</option>)}<option value="">Sin ubicar (raíz del centro)</option></select></label>
      </div>
      <div className="two">
        <label className="field">Conformidad<select name="conformidad"><option value="CONFORME">Conforme</option><option value="OBSERVADA">Con observaciones</option><option value="RECHAZADA">Rechazada</option></select></label>
        <label className="field">Peso verificado (kg)<input name="peso" type="number" step="0.01" min="0" placeholder={objeto.peso_kg ?? ''} /></label>
      </div>
      <EvidenciaInput tipos={ctx.evidencias} value={ev} onChange={setEv} />
      {children}
    </Formulario>
  );
}

function Evaluar({ ctx, objeto, ejecutar, children }) {
  const { c, destinosPara, nombreDestino } = useCatalogos();
  const [clas, setClas] = useState('');
  const [valores, setValores] = useState({});
  const [ev, setEv] = useState(null);
  const opciones = destinosPara(clas);
  const set = (k, campo, v) => setValores((x) => ({ ...x, [k]: { ...x[k], [campo]: v } }));
  return (
    <Formulario onSubmit={(e) => {
      const d = datos(e);
      const criterios = ctx.criterios.filter((cr) => valores[cr.codigo]?.valor !== undefined && valores[cr.codigo]?.valor !== '')
        .map((cr) => ({ criterio: cr.codigo, valor: cr.tipo_valor === 'NUMERO' ? Number(valores[cr.codigo].valor) : valores[cr.codigo].valor, cumple: !!valores[cr.codigo].cumple }));
      ejecutar(async ({ subir }) => api.evaluar({ objeto: objeto.uid, clasificacion: clas, destino_sugerido: d.destino, funcional: d.funcional === 'on',
        criterios, requiere_borrado: d.borrado === 'on', puntaje: d.puntaje ? Number(d.puntaje) : null, motivo: nulo(d.motivo),
        evidencias: [await subir(ev)].filter(Boolean) }));
    }}>
      {ctx.reevaluacion && (
        <label className="field">Motivo de la reevaluación *<select name="motivo" required defaultValue="">
          <option value="" disabled>Selecciona</option>{c.motivos.map((m) => <option key={m.codigo} value={m.codigo}>{m.nombre}</option>)}</select></label>
      )}
      <fieldset className="evid" style={{ borderStyle: 'solid' }}>
        <legend>Clasificación técnica *</legend>
        <div className="radio-cards">
          {c.clasificaciones.filter((k) => k.codigo !== 'PENDIENTE').map((k) => (
            <label key={k.codigo} className="radio-card"><input type="radio" name="clas" value={k.codigo} required checked={clas === k.codigo} onChange={() => setClas(k.codigo)} /><b>{k.nombre}</b></label>
          ))}
        </div>
      </fieldset>
      <div className="two">
        <label className="field">Destino sugerido *<select name="destino" required disabled={!clas} key={clas}>{opciones.map((x) => <option key={x} value={x}>{nombreDestino(x)}</option>)}</select></label>
        <label className="field">Puntaje (0–100)<input name="puntaje" type="number" min="0" max="100" /></label>
      </div>
      <div className="crit">
        <b>Criterios</b>
        {ctx.criterios.map((cr) => (
          <div key={cr.codigo} className="crit__row">
            <span>{cr.nombre}{cr.obligatorio && <em title="Obligatorio"> *</em>}</span>
            {cr.tipo_valor === 'BOOLEANO' ? (
              <select aria-label={cr.nombre} required={cr.obligatorio} value={valores[cr.codigo]?.valor === undefined ? '' : String(valores[cr.codigo].valor)}
                onChange={(e) => set(cr.codigo, 'valor', e.target.value === '' ? undefined : e.target.value === 'true')}>
                <option value="">—</option><option value="true">Sí</option><option value="false">No</option>
              </select>
            ) : (
              <input aria-label={cr.nombre} type={cr.tipo_valor === 'NUMERO' ? 'number' : 'text'} required={cr.obligatorio} onChange={(e) => set(cr.codigo, 'valor', e.target.value)} />
            )}
            <label className="check"><input type="checkbox" onChange={(e) => set(cr.codigo, 'cumple', e.target.checked)} /> Cumple</label>
          </div>
        ))}
      </div>
      <div className="two">
        <label className="check"><input type="checkbox" name="funcional" /> El equipo funciona</label>
        <label className="check"><input type="checkbox" name="borrado" defaultChecked={ctx.requiere_borrado} /> Requiere borrado de datos {ctx.requiere_borrado && '(tiene almacenamiento)'}</label>
      </div>
      <EvidenciaInput tipos={['INFORME_EVALUACION']} value={ev} onChange={setEv} required={false} />
      {children}
    </Formulario>
  );
}

function Certificar({ objeto, ejecutar, children }) {
  const [ev, setEv] = useState(null);
  return (
    <Formulario onSubmit={() => ejecutar(async ({ subir }) => { await subir(ev, { objeto: objeto.uid }); return null; })}>
      <p className="note">El certificado queda vinculado al equipo. Sin él, la base bloquea su entrega a una beneficiaria (RN-09).</p>
      <EvidenciaInput tipos={['CERTIFICADO_BORRADO']} value={ev} onChange={setEv} />
      {children}
    </Formulario>
  );
}

function Transferir({ ctx, objeto, ejecutar, children }) {
  const permitido = ctx.destinos.filter((d) => d.permitido);
  const [destino, setDestino] = useState(permitido[0]?.nodo ?? '');
  const sel = ctx.destinos.find((d) => d.nodo === destino);
  return (
    <Formulario onSubmit={(e) => {
      const d = datos(e);
      ejecutar(() => api.transferir({ objetos: [objeto.uid], nodo_origen: ctx.nodo_origen, nodo_destino: destino, ubicacion_destino: nulo(d.ubicacion),
        criterio_asignacion: nulo(d.criterio), transportista: nulo(d.transportista) }));
    }}>
      <fieldset className="evid" style={{ borderStyle: 'solid' }}>
        <legend>Destino desde {ctx.nodo_origen} *</legend>
        <div className="radio-cards">
          {ctx.destinos.map((d) => (
            <label key={d.nodo} className="radio-card" title={d.motivo ?? ''}>
              <input type="radio" name="destino" value={d.nodo} disabled={!d.permitido} checked={destino === d.nodo} onChange={() => setDestino(d.nodo)} required />
              <b>{d.nodo} · {d.nombre}</b>
              <small>{d.capacidad != null ? `Capacidad ${Number(d.capacidad)} eq/semana` : 'Sin capacidad UND'}{d.requiere_excepcion ? ' · por excepción ADR-004' : ''}</small>
              {!d.permitido && <small className="radio-card__why">{d.motivo}</small>}
            </label>
          ))}
        </div>
      </fieldset>
      <div className="two">
        {sel?.ubicaciones?.length > 0 && (
          <label className="field">Ubicación de destino<select name="ubicacion">{sel.ubicaciones.filter((u) => u.tipo !== 'RAIZ').map((u) => <option key={u.codigo} value={u.codigo}>{u.nombre}</option>)}<option value="">Raíz del centro</option></select></label>
        )}
        <label className="field">Transporte<input name="transportista" maxLength={120} placeholder="Camión 02" /></label>
      </div>
      {sel?.tipo === 'BENEFICIARIO' && <label className="field">Criterio de asignación<input name="criterio" maxLength={200} defaultValue="Programa de inclusión digital" /></label>}
      {!permitido.length && <p className="note" data-tone="aviso">Ningún destino es válido ahora: revisa los motivos de cada uno.</p>}
      {children}
    </Formulario>
  );
}

function RecibirTransferencia({ ctx, ejecutar, children }) {
  const [ev, setEv] = useState(null);
  return (
    <Formulario onSubmit={(e) => { const d = datos(e); ejecutar(async ({ subir }) => api.recibirTransferencia(ctx.transferencia, { evidencias: [await subir(ev)], ubicacion: nulo(d.ubicacion) })); }}>
      <p className="note">Transferencia <b>{ctx.numero}</b>. La base no la cierra sin origen, destino, responsable, confirmación y evidencia (RN-03).</p>
      {ctx.ubicaciones?.length > 0 && (
        <label className="field">Ubicación<select name="ubicacion"><option value="">La indicada al despachar</option>{ctx.ubicaciones.filter((u) => u.tipo !== 'RAIZ').map((u) => <option key={u.codigo} value={u.codigo}>{u.nombre}</option>)}</select></label>
      )}
      <EvidenciaInput tipos={ctx.evidencias} value={ev} onChange={setEv} />
      {children}
    </Formulario>
  );
}

function Tratamiento({ ctx, objeto, ejecutar, children }) {
  const { c, nombreDestino } = useCatalogos();
  const [tipo, setTipo] = useState(ctx.tipos[0]?.codigo ?? '');
  const [fr, setFr] = useState([]);
  const [ev, setEv] = useState(null);
  const destino = ctx.tipos.find((t) => t.codigo === tipo)?.destino;
  const suma = fr.reduce((s, f) => s + (Number(f.peso_kg) || 0), 0);
  const limite = ctx.peso_kg ? Number(ctx.peso_kg) * 1.05 : null;
  return (
    <Formulario onSubmit={(e) => {
      const d = datos(e);
      ejecutar(async ({ subir }) => api.tratar({ objeto: objeto.uid, tipo_tratamiento: tipo, resultado: d.resultado, observacion: nulo(d.observacion),
        fracciones: fr.filter((f) => f.material && Number(f.peso_kg) > 0).map((f) => ({ material: f.material, peso_kg: Number(f.peso_kg) })),
        evidencias: [await subir(ev)].filter(Boolean) }));
    }}>
      {!ctx.tipos.length && <p className="note" data-tone="aviso">Este centro no está habilitado para tratar esta clasificación.</p>}
      <div className="two">
        <label className="field">Tratamiento<select value={tipo} onChange={(e) => setTipo(e.target.value)}>{ctx.tipos.map((t) => <option key={t.codigo} value={t.codigo}>{t.nombre} ({nombreDestino(t.destino)})</option>)}</select></label>
        <label className="field">Resultado<select name="resultado"><option value="EXITOSO">Exitoso</option><option value="PARCIAL">Parcial</option><option value="FALLIDO">Fallido: vuelve a evaluación</option></select></label>
      </div>
      {destino === 'RECICLAJE' && (
        <div className="crit">
          <b>Fracciones recuperadas {limite && <small className="hint">· {suma.toFixed(2)} de {limite.toFixed(2)} kg posibles</small>}</b>
          {fr.map((f, i) => (
            <div key={i} className="crit__row">
              <select aria-label="Material" value={f.material} onChange={(e) => setFr((x) => x.map((y, j) => (j === i ? { ...y, material: e.target.value } : y)))}>
                <option value="">Material</option>{c.materiales.map((m) => <option key={m.codigo} value={m.codigo}>{m.nombre}</option>)}
              </select>
              <input aria-label="Peso en kg" type="number" step="0.01" min="0" placeholder="kg" value={f.peso_kg} onChange={(e) => setFr((x) => x.map((y, j) => (j === i ? { ...y, peso_kg: e.target.value } : y)))} />
              <button type="button" className="btn btn--ghost btn--sm" onClick={() => setFr((x) => x.filter((_, j) => j !== i))}>Quitar</button>
            </div>
          ))}
          <button type="button" className="btn btn--ghost btn--sm" onClick={() => setFr((x) => [...x, { material: '', peso_kg: '' }])}>+ Agregar fracción</button>
          {limite && suma > limite && <p className="error">Las fracciones superan el peso del equipo: la base rechazará el registro.</p>}
        </div>
      )}
      <label className="field">Observación<input name="observacion" maxLength={500} /></label>
      <EvidenciaInput tipos={ctx.evidencias} value={ev} onChange={setEv} />
      {children}
    </Formulario>
  );
}

function Cerrar({ ctx, objeto, ejecutar, children }) {
  const { nombreDestino } = useCatalogos();
  const [ev, setEv] = useState(null);
  return (
    <Formulario onSubmit={(e) => { const d = datos(e); ejecutar(async ({ subir }) => api.cerrar({ objeto: objeto.uid, evidencias: [await subir(ev)], observacion: nulo(d.observacion) })); }}>
      <p className="note">Destino final: <b>{nombreDestino(ctx.destino)}</b>. Con el cierre, la trazabilidad queda completa (RN-08).</p>
      <label className="field">Observación<input name="observacion" maxLength={500} placeholder="Ej.: Equipo en uso en la escuela" /></label>
      <EvidenciaInput tipos={ctx.evidencias} value={ev} onChange={setEv} />
      {children}
    </Formulario>
  );
}

function Desagrupar({ objeto, ejecutar, children }) {
  return (
    <Formulario onSubmit={(e) => { const d = datos(e); ejecutar(() => api.desagrupar(objeto.uid, nulo(d.observacion))); }}>
      <p className="note">El lote pasa a «Desagrupado» y cada equipo sigue su camino por separado. La composición anterior queda en el historial.</p>
      <label className="field">Observación<input name="observacion" maxLength={300} defaultValue="Se evalúa cada equipo por separado" /></label>
      {children}
    </Formulario>
  );
}

const ETIQUETA = { ram_gb: 'RAM (GB)', almacenamiento_gb: 'Almacenamiento (GB)', procesador: 'Procesador', pulgadas: 'Pulgadas', quimica: 'Química de la batería' };
const NUMERICO = /(_gb|pulgadas)$/;

// UPDATE: corrige los datos mientras el equipo está «Registrado». Código y categoría no cambian (son su identidad).
function Editar({ objeto, dispositivo: d, ejecutar, children }) {
  const { c } = useCatalogos();
  const categoria = c.categorias.find((x) => x.codigo === d?.categoria);
  const requeridos = categoria?.requeridos ?? [];
  const claves = [...new Set([...requeridos, ...Object.keys(categoria?.propiedades ?? {}), ...Object.keys(d?.atributos ?? {})])];
  const marca = c.marcas.find((m) => m.nombre === d?.marca || m.codigo === d?.marca)?.codigo ?? '';
  const [almacenamiento, setAlmacenamiento] = useState(!!d?.contiene_almacenamiento);
  return (
    <Formulario onSubmit={(e) => {
      const f = datos(e);
      const atributos = {};
      claves.forEach((k) => { if (f[`a_${k}`] !== '' && f[`a_${k}`] != null) atributos[k] = NUMERICO.test(k) ? Number(f[`a_${k}`]) : f[`a_${k}`]; });
      ejecutar(() => api.actualizarDispositivo(objeto.uid, {
        peso_kg: Number(f.peso), contiene_almacenamiento: f.almacenamiento === 'on', marca: nulo(f.marca), modelo: nulo(f.modelo?.trim()), modelo_uid: f.modelo_uid && f.modelo_uid !== 'otro' ? f.modelo_uid : null,
        numero_serie: nulo(f.serie?.trim()), anio: f.anio ? Number(f.anio) : null, atributos, motivo: f.motivo,
      }));
    }}>
      <p className="note">{objeto.codigo} · {categoria?.nombre ?? d?.categoria_nombre}. El código y la categoría no se cambian: si están mal, anula el registro y créalo de nuevo.</p>
      <div className="two">
        <ModeloSerie categoria={d?.categoria} inicial={{ ...d, marca }} excluir={objeto.uid} almacenamiento={almacenamiento} onAlmacenamiento={setAlmacenamiento} />
        <label className="field">Año<input name="anio" type="number" min="1970" max="2100" defaultValue={d?.anio_fabricacion ?? ''} /></label>
        <label className="field">Peso (kg) *<input name="peso" type="number" step="0.01" min="0.01" max="2000" required defaultValue={d?.peso_kg ?? ''} /></label>
        {claves.map((k) => (
          <label key={k} className="field">{ETIQUETA[k] ?? k.replace(/_/g, ' ')}{requeridos.includes(k) ? ' *' : ''}
            <input name={`a_${k}`} type={NUMERICO.test(k) ? 'number' : 'text'} step="any" min={NUMERICO.test(k) ? 0 : undefined} required={requeridos.includes(k)} defaultValue={d?.atributos?.[k] ?? ''} />
          </label>
        ))}
      </div>
      <label className="field">¿Qué corriges? *<input name="motivo" required minLength={5} maxLength={300} placeholder="Ej.: peso mal digitado en el registro" /></label>
      {children}
    </Formulario>
  );
}

// DELETE lógico: el equipo pasa a «Anulado»; queda en el historial y en la auditoría.
function Anular({ objeto, ejecutar, children }) {
  return (
    <Formulario onSubmit={(e) => { const f = datos(e); ejecutar(() => api.anularObjeto(objeto.uid, f.motivo)); }}>
      <p className="note" data-tone="aviso">{objeto.codigo} dejará de aparecer como equipo activo. No se borra: en un sistema de trazabilidad nada se elimina físicamente, para que siempre se pueda auditar qué pasó.</p>
      <label className="field">Motivo *<input name="motivo" required minLength={5} maxLength={300} defaultValue="Registro duplicado" /></label>
      {children}
    </Formulario>
  );
}

const FORMS = {
  EDITAR: Editar, ANULAR: Anular,
  SOLICITAR_RECOLECCION: Solicitar, PROGRAMAR_RECOLECCION: Programar, RECIBIR: Recibir, EVALUAR: Evaluar, CERTIFICAR_BORRADO: Certificar,
  TRANSFERIR: Transferir, RECIBIR_TRANSFERENCIA: RecibirTransferencia, REGISTRAR_TRATAMIENTO: Tratamiento, CERRAR: Cerrar, DESAGRUPAR: Desagrupar,
};

export const useFormsDisponibles = () => useMemo(() => Object.keys(FORMS), []);
