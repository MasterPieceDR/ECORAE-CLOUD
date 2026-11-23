import { lazy, Suspense, useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth, useCatalogos } from '@/features/auth';
import { api, formatDate, DOCUMENTO } from '@/shared/api';
import { useAsync } from '@/shared/hooks/useAsync';
import { useCinema } from '@/shared/hooks/useCinema';
import { Skeleton } from '@/shared/ui/Skeleton';
import { Icon } from '@/shared/ui/Icon';
import { ListaTareas } from '@/features/tareas';
import { ContenidoCard } from '@/features/capacitacion/ContenidoCard';
import { soloRolBase } from '@/features/usuarios/Solicitudes';
const Grafico = lazy(() => import('@/shared/ui/Chart').then((m) => ({ default: m.Chart })));
const Chart = (props) => <Suspense fallback={<Skeleton h={320} />}><Grafico {...props} /></Suspense>;
import './dashboard.css';
const R = 62;
const C = 2 * Math.PI * R;
export function DashboardPage() {
  const { user, can } = useAuth();
  const { c, nombreEstado, nombreRol } = useCatalogos();
  const stats = useAsync(() => api.tablero());
  const operativo = ['SOLICITUD.CREAR', 'RECEPCION.REGISTRAR', 'EVALUACION.REGISTRAR', 'TRANSFERENCIA.CREAR', 'TRANSFERENCIA.CONFIRMAR', 'TRATAMIENTO.REGISTRAR', 'CIERRE.CONFIRMAR'].some((p) => can(p));
  const tareas = useAsync(() => (operativo ? api.tareas() : Promise.resolve(null)), [operativo]);
  const videos = useAsync(() => api.contenidos());
  const s = stats.data;
  const root = useCinema(!!s);
  const porEstado = Object.fromEntries((s?.por_estado ?? []).map((x) => [x.estado, x.n]));
  const navigate = useNavigate();
  const estados = c.estados.filter((e) => e.codigo !== 'DESAGRUPADO');
  const barras = useMemo(() => ({ tooltip: { trigger: 'axis' }, grid: { left: 150, right: 25, top: 10, bottom: 25 }, xAxis: { type: 'value' }, yAxis: { type: 'category', data: estados.map((e) => e.nombre), axisLabel: { color: 'var(--muted)' } }, series: [{ type: 'bar', data: estados.map((e) => ({ value: porEstado[e.codigo] ?? 0, codigo: e.codigo })) }] }), [s, c]);
  const dona = useMemo(() => ({ tooltip: { trigger: 'item' }, series: [{ type: 'pie', radius: ['45%', '70%'], data: (s?.por_clasificacion ?? []).map((x) => ({ name: c.clasificaciones.find((k) => k.codigo === x.clasificacion)?.nombre ?? x.clasificacion, value: x.n })) }] }), [s, c]);
  const rol = user.roles[0];
  return (
    <div className="dash" ref={root}>
      <section className="dash__hero">
        <div>
          <p className="dash__kicker">{nombreRol(rol?.codigo)}{rol?.centro ? ` · ${rol.centro}` : ''} · {user.organizacion?.nombre}</p>
          <h1 data-split data-now>¡Hola, <em>{user.alias.split('.')[0]}!</em></h1>
          <p className="dash__sum">{s ? (tareas.data?.total ? `Tienes ${tareas.data.total} tarea(s) pendiente(s). ` : '') + `${s.en_proceso} equipo(s) en proceso en la red.` : 'Preparando tu resumen...'}</p>
        </div>
      </section>
      {soloRolBase(user) && (
        <section className="card dash__base" role="status">
          <Icon name="key" size={22} />
          <div><b>Tu cuenta tiene el rol base</b><p>Puedes consultar y aprender en Capacitación. Si trabajas en la red (generador, operador, técnico…), pide tu rol y un administrador lo aprobará.</p></div>
          <Link className="btn btn--primary btn--sm" to="/app/perfil#solicitar">Solicitar acceso</Link>
        </section>
      )}
      {!s ? <div className="kpis"><Skeleton h={150} /><Skeleton h={150} /><Skeleton h={150} /><Skeleton h={150} /></div> : (
        <section className="kpis" aria-label="Indicadores">
          <article className="kpi" data-tilt="5" data-rise><Icon name="box" size={22} /><b data-count={s.en_proceso}>{s.en_proceso}</b><span>En proceso</span><small>de {s.dispositivos} equipos visibles</small></article>
          <article className="kpi" data-tilt="5" data-rise><Icon name="check" size={22} /><b data-count={s.trazabilidad_completa_pct} data-suffix=" %">{s.trazabilidad_completa_pct} %</b><span>Trazabilidad completa</span><small>{s.cerrados} con destino final</small></article>
          <article className="kpi" data-tilt="5" data-rise><Icon name="leaf" size={22} /><b data-count={s.recuperacion_pct} data-suffix=" %">{s.recuperacion_pct} %</b><span>Recuperación</span><small>de los equipos evaluados</small></article>
          {s.red ? (
            <article className="kpi kpi--ring" data-tilt="5" data-rise>
              <svg viewBox="0 0 150 150" width="112" height="112" aria-hidden="true">
                <circle cx="75" cy="75" r={R} fill="none" stroke="var(--line)" strokeWidth="11" />
                <circle cx="75" cy="75" r={R} fill="none" stroke="var(--danger)" strokeWidth="11" strokeLinecap="round" strokeDasharray={C} strokeDashoffset={C * (1 - s.red.cobertura / 100)} transform="rotate(-90 75 75)" />
              </svg>
              <div><b>{s.red.cobertura} %</b><span>Capacidad de la red (E0)</span><small>{s.red.flujo_maximo} de {s.red.generacion} equipos por semana</small></div>
            </article>
          ) : (
            <article className="kpi" data-rise><Icon name="play" size={22} /><b>{videos.data?.length ?? '–'}</b><span>Contenidos de capacitación</span><small><Link to="/app/capacitacion">Aprende sobre RAEE</Link></small></article>
          )}
        </section>
      )}
      {s && (
        <div className="dash__grid">
          <section className="card">
            <h2 className="dash__h2">Equipos por estado</h2>
            <Chart label="Equipos por estado; selecciona una barra para filtrar" option={barras} onClick={(p) => p.data?.codigo && navigate(`/app/objetos?estado=${encodeURIComponent(p.data.codigo)}`)} />
            <div aria-label="Filtrar equipos por estado">{estados.filter((e) => porEstado[e.codigo]).map((e) => <Link key={e.codigo} className="chip-link" to={`/app/objetos?estado=${encodeURIComponent(e.codigo)}`}>{e.nombre} ({porEstado[e.codigo]})</Link>)}</div>
          </section>
          <section className="card"><h2 className="dash__h2">Clasificación</h2><Chart label="Equipos por clasificación" option={dona} /></section>
        </div>
      )}
      {operativo && (
        <section>
          <div className="dash__head"><h2 className="dash__h2"><Icon name="inbox" /> Qué hacer ahora</h2><Link to="/app/tareas" className="dash__all">Ver todas ({tareas.data?.total ?? 0}) <Icon name="arrow" size={16} /></Link></div>
          {tareas.loading ? <Skeleton h={160} /> : <ListaTareas grupos={tareas.data?.grupos ?? []} compacta />}
        </section>
      )}
      <Proyeccion />
      {s && <div className="dash__col">
            {s.red && (
              <section className="card dash__neck">
                <div>
                  <h2 className="dash__h2"><Icon name="alert" /> Cuello de botella hoy</h2>
                  {s.red.cortes[0]?.aristas.map(([a, b]) => <p key={a + b} className="neck"><code>{a} → {b}</code><b>ruta</b></p>)}
                  {s.red.cortes[0]?.nodos.map((n) => <p key={n} className="neck"><code>{n}</code><b>capacidad del centro</b></p>)}
                  <Link to="/app/red" className="btn btn--primary btn--sm" data-magnetic>Analizar escenarios <Icon name="arrow" size={16} /></Link>
                </div>
              </section>
            )}
            <section className="card">
              <h2 className="dash__h2"><Icon name="history" /> Movimientos recientes</h2>
              <ul className="feed">
                {s.recientes.map((r) => (
                  <li key={`${r.codigo}-${r.ocurrido_en}-${r.estado_destino}`}>
                    <Link to={`/app/objetos/${r.codigo}`}><b>{r.codigo}</b></Link> {nombreEstado(r.estado_destino)}
                    <small>{r.tipo_documento ? `${DOCUMENTO[r.tipo_documento]} ${r.documento}` : ''} · {r.usuario} · {formatDate(r.ocurrido_en)}</small>
                  </li>
                ))}
                {s.recientes.length === 0 && <li className="hint">Sin movimientos visibles.</li>}
              </ul>
            </section>
          </div>}
      {s?.indicadores?.length > 0 && (
        <section className="card">
          <h2 className="dash__h2"><Icon name="leaf" /> Indicadores del periodo</h2>
          <div className="inds">
            {s.indicadores.map((i) => (
              <article key={i.codigo} className="ind" data-ok={i.cumple_meta}>
                <small>{i.dimension.toLowerCase()} · {i.materia_origen}</small>
                <b>{Number(i.valor).toLocaleString('es-EC', { maximumFractionDigits: 1 })} <span>{i.unidad}</span></b>
                <p>{i.nombre}</p>
                {i.meta != null && <small>meta {Number(i.meta)} {i.unidad} · {i.cumple_meta ? 'cumple' : 'no cumple'}</small>}
              </article>
            ))}
          </div>
        </section>
      )}
      <section>
        <div className="dash__head"><h2 className="dash__h2"><Icon name="play" /> Capacitación</h2><Link to="/app/capacitacion" className="dash__all">Ver todo <Icon name="arrow" size={16} /></Link></div>
        <div className="vgrid">
          {videos.loading ? [0, 1, 2].map((k) => <Skeleton key={k} h={240} />) : videos.data?.slice(0, 3).map((v, i) => <ContenidoCard key={v.uid} c={v} index={i} />)}
        </div>
      </section>
    </div>
  );
}
function Proyeccion() {
  const { c } = useCatalogos();
  const { can } = useAuth();
  const permitido = can('RED.GESTIONAR') || can('CATALOGO.ADMINISTRAR') || can('AUDITORIA.CONSULTAR') || can('GOBIERNO.DECIDIR');
  const [categoria, setCategoria] = useState(''), [semanas, setSemanas] = useState('8'), [medida, setMedida] = useState('equipos');
  const { data, error, loading } = useAsync(() => permitido ? api.prediccion({ categoria, semanas, medida }) : Promise.resolve(null), [permitido, categoria, semanas, medida]);
  const option = useMemo(() => {
    const h = data?.historia ?? [], p = data?.pronostico ?? [], plataforma = data?.plataforma ?? [];
    const fechas = [...new Set([...h, ...p, ...plataforma].map((x) => x.semana))].sort();
    const valores = (serie) => Object.fromEntries(serie.map((x) => [x.semana, x.valor]));
    const historia = valores(h), pronostico = valores(p), registradas = valores(plataforma);
    const ultimo = h.at(-1);
    const porFecha = Object.fromEntries(p.map((x) => [x.semana, x]));
    return { tooltip: { trigger: 'axis' }, legend: { textStyle: { color: 'var(--muted)' }, data: ['Historia', 'Pronóstico', 'Banda 80 %', ...(plataforma.length ? ['Registradas en la plataforma'] : [])] }, grid: { left: 55, right: 20, bottom: 45 },
      xAxis: { type: 'category', data: fechas }, yAxis: { type: 'value' },
      series: [{ name: 'Historia', type: 'line', showSymbol: false, data: fechas.map((f) => historia[f] ?? null) },
        { name: 'Pronóstico', type: 'line', showSymbol: false, lineStyle: { type: 'dashed' }, data: fechas.map((f) => pronostico[f] ?? (f === ultimo?.semana ? ultimo.valor : null)) },
        { name: 'Límite inferior', type: 'line', stack: 'banda', symbol: 'none', lineStyle: { opacity: 0 }, data: fechas.map((f) => porFecha[f]?.inferior ?? null) },
        { name: 'Banda 80 %', type: 'line', stack: 'banda', symbol: 'none', lineStyle: { opacity: 0 }, areaStyle: { opacity: .18 }, data: fechas.map((f) => porFecha[f] ? porFecha[f].superior - porFecha[f].inferior : null) },
        ...(plataforma.length ? [{ name: 'Registradas en la plataforma', type: 'bar', barMaxWidth: 12, data: fechas.map((f) => registradas[f] ?? null) }] : [])] };
  }, [data]);
  if (!permitido) return null;
  return <section className="card"><h2 className="dash__h2">Proyección de recolección</h2><div className="proyeccion-filters">
    <label className="field">Categoría<select value={categoria} onChange={(e) => setCategoria(e.target.value)}><option value="">Todas</option>{c.categorias.filter((x) => x.nivel === 2).map((x) => <option key={x.codigo} value={x.codigo}>{x.nombre}</option>)}</select></label>
    <label className="field">Horizonte<select value={semanas} onChange={(e) => setSemanas(e.target.value)}>{[4,8,12].map((x) => <option key={x} value={x}>{x} semanas</option>)}</select></label>
    <label className="field">Medida<select value={medida} onChange={(e) => setMedida(e.target.value)}><option value="equipos">Equipos</option><option value="peso">Kilogramos</option></select></label></div>
    {loading ? <p>Cargando proyección...</p> : error || !data?.disponible ? <p role="status">{error?.message ?? data?.nota}</p> : <><Chart label="Historia y proyección de recolección con banda de confianza del 80 por ciento" option={option} /><p className="hint">{data.nota} {data.mape == null ? 'No se pudo calcular el error porcentual.' : `Al comparar el pronóstico con las últimas cuatro semanas completas, el error porcentual medio fue ${data.mape} %.`}</p></>}
  </section>;
}
