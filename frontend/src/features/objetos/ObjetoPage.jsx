import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { motion } from 'motion/react';
import { api, formatDate, formatKg, formatBytes, DOCUMENTO, ICONO_ACCION } from '@/shared/api';
import { useAuth, useCatalogos } from '@/features/auth';
import { useAsync } from '@/shared/hooks/useAsync';
import { Skeleton } from '@/shared/ui/Skeleton';
import { Icon } from '@/shared/ui/Icon';
import { StateBadge, ClasBadge } from '@/shared/ui/StateBadge';
import { useToast } from '@/shared/ui/Toast';
import { AccionDialog } from './AccionDialog';
import { FilasBD } from '@/features/verificacion';
import './objetos.css';

const PROPOSITO_POR_ROL = [['AUDITOR', 'AUDITORIA'], ['TECNICO_EVALUADOR', 'EVALUACION_TECNICA'], ['COMITE_ARQUITECTURA', 'AUDITORIA']];

export function ObjetoPage() {
  const { codigo } = useParams();
  const { data, loading, error, reload } = useAsync(() => api.objeto(codigo), [codigo]);
  const [accion, setAccion] = useState(null);
  const [verBD, setVerBD] = useState(false);
  if (loading && !data) return <Skeleton h={480} />;
  if (error) return <div><Link to="/app/objetos" className="detail__back"><Icon name="back" size={18} /> Equipos y lotes</Link><p className="error" role="alert">{error.message}</p></div>;
  const { objeto: o, dispositivo: d, linea, miembros, lotes, evidencias, documentos, acciones, avisos } = data;
  const titulo = o.tipo_objeto === 'LOTE' ? `Lote ${o.codigo}` : `${o.categoria_nombre ?? 'Equipo'} ${o.marca ? `· ${o.marca}` : ''}`;
  return (
    <div className="detail">
      <Link to="/app/objetos" className="detail__back"><Icon name="back" size={18} /> Equipos y lotes</Link>
      <div className="page-head">
        <div><h1 className="page-title">{titulo}</h1><p className="page-sub">{o.codigo} · {o.organizacion_origen_nombre}{o.centro_actual ? ` · en ${o.centro_actual}` : ''}</p></div>
        <div className="detail__badges"><ClasBadge value={o.clasificacion} /><StateBadge state={o.estado} />
          <button className="btn btn--ghost btn--sm" onClick={() => setVerBD(true)}><Icon name="layers" size={16} /> Ver en la base de datos</button></div>
      </div>
      <div className="detail__grid">
        <div className="detail__main">
          <section className="card">
            <h2 className="detail__h2">Línea de trazabilidad {linea?.trazabilidad_completa && <span className="badge">Completa</span>}</h2>
            <ol className="timeline">
              {(linea?.pasos ?? []).map((p, i) => (
                <motion.li key={`${p.paso}-${p.estado_destino}`} initial={{ opacity: 0, x: -12 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: i * .04 }}>
                  <span className="timeline__dot"><Icon name="check" size={14} /></span>
                  <div>
                    <b><StateName code={p.estado_destino} /></b>
                    <p>{p.tipo_documento ? `${DOCUMENTO[p.tipo_documento] ?? p.tipo_documento} ${p.documento}` : p.observacion ?? 'Registro'}{p.centro ? ` · ${p.centro}` : ''}</p>
                    <small>{formatDate(p.ocurrido_en)} · {p.usuario} · canal {p.canal}{p.evidencias ? ` · ${p.evidencias} evidencia(s)` : ''}</small>
                  </div>
                </motion.li>
              ))}
            </ol>
          </section>
          {o.tipo_objeto === 'LOTE' && miembros.length > 0 && (
            <section className="card">
              <h2 className="detail__h2">Composición del lote</h2>
              <ul className="members">
                {miembros.map((m) => (
                  <li key={`${m.objeto}-${m.desde}`} data-off={!m.vigente}>
                    <Link to={`/app/objetos/${m.objeto}`}><b>{m.objeto}</b></Link><StateBadge state={m.estado} />
                    <small>{m.vigente ? `desde ${formatDate(m.desde)}` : `salió ${formatDate(m.hasta)}`}</small>
                  </li>
                ))}
              </ul>
            </section>
          )}
          <Evidencias lista={evidencias} />
          <section className="card">
            <h2 className="detail__h2">Documentos</h2>
            {documentos.length === 0 ? <p className="hint">Aún no hay documentos.</p> : (
              <div className="tbl-wrap"><table className="tbl">
                <thead><tr><th>Número</th><th>Tipo</th><th>Fecha</th><th>Centro / ruta</th><th>Responsable</th><th>Estado</th></tr></thead>
                <tbody>{documentos.map((x) => (
                  <tr key={x.uid}><td className="mono">{x.numero}</td><td>{DOCUMENTO[x.tipo_documento] ?? x.tipo_documento}</td><td>{formatDate(x.fecha_documento)}</td>
                    <td>{x.nodo_origen ? `${x.nodo_origen} → ${x.nodo_destino}` : x.centro ?? '—'}</td><td>{x.responsable}</td><td>{x.estado_transferencia ?? x.estado_documento}</td></tr>
                ))}</tbody>
              </table></div>
            )}
          </section>
        </div>
        <aside className="detail__side">
          <section className="card acts">
            <h2 className="detail__h2">Lo que puedes hacer</h2>
            {avisos.map((a) => <p key={a.texto} className="note" data-tone={a.tipo}>{a.texto} {a.enlace && <Link to={`/app/objetos/${a.enlace}`}>Ver {a.enlace}</Link>}</p>)}
            {acciones.length === 0 && !avisos.length && <p className="hint">{o.estado === 'CERRADO' ? 'La trazabilidad está cerrada: el equipo tiene destino final confirmado.' : 'Tu rol no tiene operaciones sobre este objeto en su estado actual.'}</p>}
            {acciones.map((a) => (
              <button key={a.codigo} className="act" data-pending={a.tarea} onClick={() => setAccion(a)}>
                <span><Icon name={ICONO_ACCION[a.codigo] ?? 'arrow'} size={20} /></span>
                <div><b>{a.titulo}</b><small>{a.descripcion}</small></div>
              </button>
            ))}
          </section>
          <section className="card">
            <h2 className="detail__h2">Ficha</h2>
            <dl className="facts">
              <div><dt>Organización de origen</dt><dd>{o.organizacion_origen_nombre}</dd></div>
              <div><dt>Registrado</dt><dd>{formatDate(o.registrado_en)}</dd></div>
              {d && <>
                <div><dt>Categoría</dt><dd>{d.categoria_nombre}</dd></div>
                <div><dt>Marca y modelo</dt><dd>{[d.marca, d.modelo].filter(Boolean).join(' · ') || '—'}</dd></div>
                <div><dt>Serie / año</dt><dd>{d.numero_serie ?? '—'} · {d.anio_fabricacion ?? '—'}</dd></div>
                <div><dt>Peso</dt><dd>{formatKg(d.peso_kg)}</dd></div>
                <div><dt>Almacenamiento de datos</dt><dd>{d.contiene_almacenamiento ? (d.tiene_certificado_borrado ? 'Sí · borrado certificado' : 'Sí · sin certificado de borrado') : 'No'}</dd></div>
                {Object.keys(d.atributos ?? {}).length > 0 && <div><dt>Atributos</dt><dd>{Object.entries(d.atributos).map(([k, v]) => `${k}: ${v}`).join(' · ')}</dd></div>}
              </>}
              {linea?.evaluacion_vigente && <div><dt>Evaluación vigente</dt><dd><Destino ev={linea.evaluacion_vigente} /></dd></div>}
              {linea?.cierre && <div><dt>Destino final</dt><dd><Cierre c={linea.cierre} /></dd></div>}
              {lotes.length > 0 && <div><dt>Lotes</dt><dd>{lotes.map((l) => <Link key={l.lote + l.desde} to={`/app/objetos/${l.lote}`} className="chip-link">{l.lote}{l.vigente ? '' : ' (histórico)'}</Link>)}</dd></div>}
            </dl>
          </section>
        </aside>
      </div>
      {verBD && <FilasBD codigo={o.codigo} onClose={() => setVerBD(false)} />}
      {accion && <AccionDialog accion={accion} objeto={o} dispositivo={data.dispositivo} onClose={() => setAccion(null)} onDone={() => { setAccion(null); reload(); }} />}
    </div>
  );
}

const StateName = ({ code }) => { const { nombreEstado } = useCatalogos(); return nombreEstado(code); };
const Destino = ({ ev }) => { const { nombreClasificacion, nombreDestino } = useCatalogos(); return `${nombreClasificacion(ev.clasificacion)} → ${nombreDestino(ev.destino_sugerido)} (${ev.modalidad.toLowerCase()})`; };
const Cierre = ({ c }) => { const { nombreDestino } = useCatalogos(); return `${nombreDestino(c.destino_final)} · ${c.organizacion} · ${formatDate(c.fecha_confirmacion)}`; };

function Evidencias({ lista }) {
  const { tieneRol } = useAuth();
  const { c } = useCatalogos();
  const toast = useToast();
  const sugerido = PROPOSITO_POR_ROL.find(([r]) => tieneRol(r))?.[1] ?? 'TRAZABILIDAD';
  const [proposito, setProposito] = useState(sugerido);
  const abrir = async (e) => {
    try {
      const r = await api.descargarEvidencia(e.uid, proposito);
      window.open(r.url, '_blank', 'noopener');
    } catch (err) { toast(err.message, 'error'); }
  };
  return (
    <section className="card">
      <div className="evs__head">
        <h2 className="detail__h2">Evidencias ({lista.length})</h2>
        {lista.length > 0 && (
          <label className="field evs__prop">Propósito de la consulta
            <select value={proposito} onChange={(e) => setProposito(e.target.value)}>{c.propositos.map((p) => <option key={p.codigo} value={p.codigo}>{p.nombre}</option>)}</select>
          </label>
        )}
      </div>
      {lista.length === 0 ? <p className="hint">Sin evidencias visibles para tu rol.</p> : (
        <ul className="evs">
          {lista.map((e) => (
            <li key={e.uid}>
              <span className="evs__ico"><Icon name={e.mime?.startsWith('image/') ? 'eye' : 'file'} size={18} /></span>
              <div><b>{e.tipo_nombre}</b><small>{e.documento ?? 'Del equipo'} · {formatDate(e.subido_en)} · {e.subido_por} · {formatBytes(e.tamano_bytes)} · {e.nivel_acceso.toLowerCase()}</small></div>
              <button className="btn btn--ghost btn--sm" onClick={() => abrir(e)} aria-label={`Abrir ${e.tipo_nombre}`}><Icon name="download" size={16} /></button>
            </li>
          ))}
        </ul>
      )}
      {lista.length > 0 && <p className="hint">Cada descarga queda registrada con tu propósito; si tu rol no puede abrir ese tipo con ese propósito, la base lo niega (RN-07).</p>}
    </section>
  );
}
