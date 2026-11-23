import { PageHeader } from '@/shared/ui/PageHeader';
import { useState } from 'react';
import { motion } from 'motion/react';
import { api, formatDate } from '@/shared/api';
import { useAsync } from '@/shared/hooks/useAsync';
import { Skeleton } from '@/shared/ui/Skeleton';
import { Icon } from '@/shared/ui/Icon';
import { Modal } from '@/shared/ui/Modal';
import './verificacion.css';

const ESTRUCTURA = [
  ['tablas', 'Tablas'], ['claves_primarias', 'Claves primarias'], ['claves_foraneas', 'Claves foráneas'],
  ['restricciones_check', 'Restricciones CHECK'], ['restricciones_unicas', 'Restricciones UNIQUE'], ['restricciones_exclusion', 'Restricciones de exclusión'],
  ['tablas_con_rls', 'Tablas con seguridad por fila'], ['triggers_auditoria', 'Triggers de auditoría'], ['triggers_reglas', 'Triggers de reglas de negocio'],
  ['vistas_contrato', 'Vistas del contrato api'], ['funciones_contrato', 'Funciones del contrato api'], ['esquemas', 'Esquemas'],
];
const VOLUMEN = {
  usuarios: 'Usuarios', organizaciones: 'Organizaciones', centros: 'Centros', dispositivos: 'Dispositivos', lotes: 'Lotes',
  cambios_de_estado: 'Cambios de estado', documentos: 'Documentos', evidencias: 'Evidencias', nodos_red: 'Nodos de la red',
  aristas_red: 'Aristas de la red', escenarios: 'Escenarios', ejecuciones_flujo: 'Ejecuciones de flujo',
  contenidos_capacitacion: 'Contenidos de capacitación', registros_auditoria: 'Registros de auditoría',
};

// Verificación de la base (Parte II · integración): la cadena navegador → API → PostgreSQL, su estructura y su consistencia.
export function VerificacionPage() {
  const cx = useAsync(() => api.verificarConexion());
  const v = useAsync(() => api.verificarBase());
  const recargar = () => { cx.reload(); v.reload(); };
  const d = v.data;
  return (
    <>
      <PageHeader title="Base de datos" description="Verificación en vivo de PostgreSQL: conexión, integridad y consistencia de lo que guarda la aplicación." action={<> <button className="btn btn--primary" onClick={recargar} disabled={cx.loading || v.loading}><Icon name="refresh" size={18} /> {cx.loading || v.loading ? 'Verificando...' : 'Verificar ahora'}</button> </>} />
      <section className="card vf-chain" aria-label="Cadena de conexión">
        {[['Navegador', 'React', 'user', true], ['API', 'FastAPI', 'network', !!cx.data], ['Base de datos', cx.data?.motor ?? 'PostgreSQL', 'layers', cx.data?.base_de_datos === 'ok']].map(([t, s, i, ok], k) => (
          <div key={t} className="vf-chain__step">
            {k > 0 && <motion.i className="vf-chain__line" data-ok={ok || undefined} initial={{ scaleX: 0 }} animate={{ scaleX: 1 }} transition={{ delay: k * 0.15 }} />}
            <span className="vf-chain__dot" data-ok={ok || undefined}><Icon name={ok ? 'check' : i} size={22} /></span>
            <b>{t}</b><small>{s}</small>
          </div>
        ))}
        <p className="hint vf-chain__meta">{cx.error ? cx.error.message : cx.data ? `Base «${cx.data.base}» · conectada como ${cx.data.usuario_conexion} · ${cx.data.latencia_ms} ms · ${formatDate(cx.data.hora_servidor)}` : 'Conectando...'}</p>
      </section>

      {v.error && <p className="error" role="alert">{v.error.message}</p>}
      {!d ? <Skeleton h={420} /> : (
        <>
          <section className="card vf-ok" data-ok={d.todo_correcto || undefined}>
            <Icon name={d.todo_correcto ? 'check' : 'alert'} size={26} />
            <div><b>{d.todo_correcto ? 'La base está íntegra y consistente' : 'Hay comprobaciones con problemas'}</b>
              <p>{d.consistencia.filter((c) => c.ok).length} de {d.consistencia.length} comprobaciones correctas · tamaño {d.conexion.tamano} · {d.duracion_ms} ms</p></div>
          </section>

          <div className="vf-grid">
            <section className="card">
              <h2 className="detail__h2">Comprobaciones de consistencia</h2>
              <ul className="vf-checks">
                {d.consistencia.map((c) => (
                  <li key={c.id} data-ok={c.ok || undefined}>
                    <span className="vf-checks__i"><Icon name={c.ok ? 'check' : 'alert'} size={16} /></span>
                    <div><b>{c.descripcion}</b><small>{c.id} · {c.regla} · {c.problemas} problema(s)</small></div>
                  </li>
                ))}
              </ul>
              <p className="hint">Cada comprobación cuenta las filas que violarían una regla. Las reglas las imponen claves foráneas, restricciones y triggers; estas consultas lo demuestran.</p>
            </section>
            <section className="card">
              <h2 className="detail__h2">Estructura</h2>
              <dl className="vf-nums">{ESTRUCTURA.map(([k, l]) => <div key={k}><dt>{l}</dt><dd>{d.estructura[k]}</dd></div>)}</dl>
              <h2 className="detail__h2" style={{ marginTop: 18 }}>Datos guardados</h2>
              <dl className="vf-nums">{Object.entries(VOLUMEN).map(([k, l]) => <div key={k}><dt>{l}</dt><dd>{d.volumen[k]}</dd></div>)}</dl>
              <p className="hint">Scripts aplicados: {Object.entries(d.scripts).filter(([, x]) => x).map(([k]) => k).join(' · ')}</p>
            </section>
          </div>
        </>
      )}
    </>
  );
}

// Prueba de persistencia desde la ficha: las filas reales que la base guarda de este equipo.
export function FilasBD({ codigo, onClose }) {
  const { data, loading, error } = useAsync(() => api.verificarObjeto(codigo), [codigo]);
  const [tabla, setTabla] = useState('trz.objeto_trazable');
  return (
    <Modal title={`${codigo} en la base de datos`} onClose={onClose} wide>
      <p className="hint">Esto no es la vista de la aplicación: son las filas tal como están guardadas en PostgreSQL, tabla por tabla, con su registro de auditoría.</p>
      {error && <p className="error" role="alert">{error.message}</p>}
      {loading && <Skeleton h={240} />}
      {data && (
        <>
          <div className="seg" role="tablist" style={{ marginBottom: 12 }}>
            {TABLAS.filter((t) => t in data).map((t) => <button key={t} aria-pressed={tabla === t} onClick={() => setTabla(t)}>{t} {Array.isArray(data[t]) ? `(${data[t].length})` : ''}</button>)}
          </div>
          <Datos valor={data[tabla]} />
        </>
      )}
    </Modal>
  );
}

const TABLAS = ['trz.objeto_trazable', 'trz.dispositivo', 'trz.historial_estado', 'ops.documento_item', 'aud.log_cambio'];
const PRIMERO = ['id', 'objeto_id', 'codigo', 'ocurrido_en', 'fecha', 'documento', 'tabla', 'operacion', 'campos_cambiados', 'desde', 'hacia', 'estado_actual', 'tipo', 'estado'];
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/;
const celda = (x) => (x == null ? '—' : typeof x === 'object' ? JSON.stringify(x) : ISO.test(String(x)) ? String(x).slice(0, 19).replace('T', ' ') : String(x));
function Datos({ valor }) {
  if (valor == null) return <p className="hint">Sin filas.</p>;
  const filas = Array.isArray(valor) ? valor : [valor];
  if (filas.length === 0) return <p className="hint">Sin filas.</p>;
  const todas = Object.keys(filas[0]);
  const cols = [...PRIMERO.filter((c) => todas.includes(c)), ...todas.filter((c) => !PRIMERO.includes(c))];
  return (
    <div className="tbl-wrap"><table className="tbl vf-raw">
      <thead><tr>{cols.map((c) => <th key={c}>{c}</th>)}</tr></thead>
      <tbody>{filas.map((f, i) => <tr key={i}>{cols.map((c) => <td key={c} className="mono">{celda(f[c])}</td>)}</tr>)}</tbody>
    </table></div>
  );
}
