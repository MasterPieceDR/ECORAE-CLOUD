import { useState } from 'react';
import { Link } from 'react-router-dom';
import { api, formatDate, DOCUMENTO } from '@/shared/api';
import { useAsync } from '@/shared/hooks/useAsync';
import { Skeleton } from '@/shared/ui/Skeleton';

const ESTADO_DOC = { EMITIDO: 'sun', EN_CURSO: 'sky', CERRADO: 'gray', ANULADO: 'coral', DESPACHADA: 'sky', RECIBIDA: 'lime', CERRADA: 'gray' };

// Cadena documental: cada movimiento del ciclo de vida es un documento con número correlativo (supertipo DOCUMENTO_OPERATIVO).
export function DocumentosPage() {
  const [tipo, setTipo] = useState('');
  const [abiertos, setAbiertos] = useState(false);
  const { data, loading, error } = useAsync(() => api.documentos({ tipo, abiertos: abiertos || undefined }), [tipo, abiertos]);
  return (
    <>
      <div className="page-head"><div><h1 className="page-title">Documentos</h1><p className="page-sub">Solicitudes, recepciones, evaluaciones, transferencias, tratamientos, asignaciones y cierres con numeración correlativa. Ves los de tu organización o centro.</p></div></div>
      <div className="chips" role="group" aria-label="Tipo de documento">
        <button className="chip" aria-pressed={!tipo} onClick={() => setTipo('')}>Todos</button>
        {Object.entries(DOCUMENTO).map(([k, v]) => <button key={k} className="chip" aria-pressed={tipo === k} onClick={() => setTipo(k)}>{v}</button>)}
      </div>
      <label className="check" style={{ margin: '14px 0' }}><input type="checkbox" checked={abiertos} onChange={(e) => setAbiertos(e.target.checked)} /> Solo abiertos (emitidos o en curso)</label>
      {error && <p className="error" role="alert">{error.message}</p>}
      {loading && !data ? <Skeleton h={300} /> : data?.length === 0 ? <p className="empty card">No hay documentos con ese filtro.</p> : (
        <div className="card tbl-wrap">
          <table className="tbl">
            <thead><tr><th>Número</th><th>Tipo</th><th>Fecha</th><th>Objetos</th><th>Centro / ruta</th><th>Organización</th><th>Responsable</th><th>Estado</th></tr></thead>
            <tbody>
              {data?.map((d) => (
                <tr key={d.uid}>
                  <td className="mono">{d.numero}{d.documento_referencia && <small className="hint"><br />ref. {d.documento_referencia}</small>}</td>
                  <td>{DOCUMENTO[d.tipo_documento] ?? d.tipo_documento}{d.modalidad && <small className="hint"><br />{d.modalidad.toLowerCase().replace('_', ' ')}</small>}</td>
                  <td>{formatDate(d.fecha_documento)}</td>
                  <td>{(d.objetos ?? []).slice(0, 4).map((c) => <Link key={c} to={`/app/objetos/${c}`} className="chip-link">{c}</Link>)}{d.items > 4 && <small className="hint">+{d.items - 4}</small>}</td>
                  <td>{d.nodo_origen ? `${d.nodo_origen} → ${d.nodo_destino}` : d.centro_destino ? `→ ${d.centro_destino}` : d.centro ?? '—'}</td>
                  <td>{d.organizacion ?? '—'}</td>
                  <td>{d.responsable}</td>
                  <td><span className="badge" data-tone={ESTADO_DOC[d.estado_transferencia ?? d.estado_documento] ?? 'gray'}>{(d.estado_transferencia ?? d.estado_documento).toLowerCase().replace('_', ' ')}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
