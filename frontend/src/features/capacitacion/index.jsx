import { PageHeader } from '@/shared/ui/PageHeader';
import { useRef, useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { AnimatePresence, motion } from 'motion/react';
import { api, fotoTema, formatNumber, formatDate, TEMA } from '@/shared/api';
import { useAuth, useCatalogos } from '@/features/auth';
import { useAsync } from '@/shared/hooks/useAsync';
import { Skeleton } from '@/shared/ui/Skeleton';
import { Icon } from '@/shared/ui/Icon';
import { Avatar } from '@/shared/ui/Avatar';
import { LogoMark } from '@/shared/ui/Logo';
import { useToast } from '@/shared/ui/Toast';
import { ContenidoCard } from './ContenidoCard';
import './capacitacion.css';

export function CapacitacionPage() {
  const { can } = useAuth();
  const { c } = useCatalogos();
  const [params] = useSearchParams();
  const [tema, setTema] = useState('');
  const [q, setQ] = useState(params.get('q') ?? '');
  const { data, loading, error } = useAsync(() => api.contenidos({ q, tema }), [q, tema]);
  return (
    <>
      <PageHeader title="Capacitación" description="Videos para reducir la brecha digital de quienes participan en la red." action={can('CONTENIDO.PUBLICAR') && <Link to="publicar" className="btn btn--primary"><Icon name="upload" size={18} /> Publicar video</Link>} />
      <div className="cap-tools">
        <label className="field"><span className="sr">Buscar</span><input type="search" placeholder="Buscar contenidos" value={q} onChange={(e) => setQ(e.target.value)} /></label>
        <div className="chips" role="group" aria-label="Temas">
          <button className="chip" aria-pressed={!tema} onClick={() => setTema('')}>Todos</button>
          {c.temas.map((t) => <button key={t} className="chip" aria-pressed={t === tema} onClick={() => setTema(t)}>{TEMA[t] ?? t}</button>)}
        </div>
      </div>
      {error && <p className="error" role="alert">{error.message}</p>}
      <div className="vgrid" style={{ marginTop: 16 }}>
        {loading && !data ? [0, 1, 2, 3, 4, 5].map((k) => <Skeleton key={k} h={240} />) : data?.map((v, i) => <ContenidoCard key={v.uid} c={v} index={i} />)}
      </div>
      {!loading && data?.length === 0 && <p className="empty">No encontramos contenidos con esa búsqueda.</p>}
    </>
  );
}

export function ContenidoPage() {
  const { uid } = useParams();
  const { can } = useAuth();
  const toast = useToast();
  const { data: v, loading, error, setData } = useAsync(() => api.contenido(uid), [uid]);
  const [texto, setTexto] = useState('');
  if (loading && !v) return <Skeleton h={480} />;
  if (error) return <p className="error" role="alert">{error.message}</p>;
  const like = async () => { try { const r = await api.reaccionar(uid); setData((d) => ({ ...d, ...r })); } catch (e) { toast(e.message, 'error'); } };
  const send = async (e) => {
    e.preventDefault();
    try { const k = await api.comentar(uid, texto); setData((d) => ({ ...d, comentarios_lista: [k, ...d.comentarios_lista], comentarios: d.comentarios + 1 })); setTexto(''); }
    catch (err) { toast(err.message, 'error'); }
  };
  const moderar = async () => {
    const estado = v.estado === 'OCULTO' ? 'PUBLICADO' : 'OCULTO';
    try { await api.moderar(uid, estado); setData((d) => ({ ...d, estado })); toast(estado === 'OCULTO' ? 'Contenido oculto.' : 'Contenido publicado.'); } catch (err) { toast(err.message, 'error'); }
  };
  return (
    <div className="watch">
      <section>
        <Link to="/app/capacitacion" className="detail__back"><Icon name="back" size={18} /> Capacitación</Link>
        {v.video_url ? <video className="player__video" src={v.video_url} controls playsInline preload="metadata" /> : (
          <div className="player"><img src={fotoTema(v.tema)} alt="" /><div className="player__bar"><small>Contenido de ejemplo: aún sin video publicado.</small></div></div>
        )}
        <h1 className="watch__title">{v.titulo}</h1>
        <p className="watch__meta"><Icon name="eye" size={16} /> {formatNumber(v.vistas)} vistas · {TEMA[v.tema]} · {formatDate(v.publicado_en)} {v.estado === 'OCULTO' && <span className="badge" data-tone="coral">Oculto por moderación</span>}</p>
        <div className="watch__author">
          <Avatar name={v.autor} />
          <div><b>{v.autor}</b><small className="hint"> · {v.organizacion_autor}</small></div>
          <button className={`btn btn--sm ${v.me_gusta_yo ? 'btn--primary' : 'btn--ghost'}`} onClick={like} aria-pressed={v.me_gusta_yo}><Icon name="like" size={16} /> {formatNumber(v.me_gusta)}</button>
          {can('CONTENIDO.MODERAR') && <button className="btn btn--ghost btn--sm" onClick={moderar}>{v.estado === 'OCULTO' ? 'Restaurar' : 'Ocultar'}</button>}
        </div>
        <p className="watch__desc">{v.descripcion}</p>
      </section>
      <aside className="card comments">
        <h2>Comentarios ({v.comentarios})</h2>
        <form onSubmit={send} className="comments__form">
          <input value={texto} onChange={(e) => setTexto(e.target.value)} maxLength={1000} required placeholder="Escribe un comentario..." aria-label="Escribe un comentario" />
          <button className="btn btn--primary btn--sm" aria-label="Enviar comentario"><Icon name="send" size={16} /></button>
        </form>
        <ul>
          <AnimatePresence initial={false}>
            {v.comentarios_lista.map((k) => (
              <motion.li key={k.uid} layout initial={{ opacity: 0, y: -8 }} animate={{ opacity: 1, y: 0 }}>
                <Avatar name={k.autor} />
                <div><b>{k.autor}</b><p>{k.texto}</p><small>{formatDate(k.creado_en)}</small></div>
              </motion.li>
            ))}
          </AnimatePresence>
        </ul>
        {v.comentarios_lista.length === 0 && <p className="empty">Sé la primera persona en comentar.</p>}
      </aside>
    </div>
  );
}

const MAX = 500 * 1024 * 1024;
const MIMES = ['video/mp4', 'video/webm', 'video/quicktime', 'video/x-msvideo'];

export function PublicarPage() {
  const { c } = useCatalogos();
  const [file, setFile] = useState(null);
  const [drag, setDrag] = useState(false);
  const [progress, setProgress] = useState(null);
  const [error, setError] = useState('');
  const input = useRef(null);
  const navigate = useNavigate();
  const toast = useToast();
  const elegir = (f) => {
    setError('');
    if (!f) return;
    if (!MIMES.includes(f.type)) { setError('Formatos permitidos: MP4, WEBM, MOV o AVI.'); return; }
    if (f.size > MAX) { setError('El archivo supera el máximo de 500 MB.'); return; }
    setFile(f);
  };
  const duracion = (f) => new Promise((ok) => { const el = document.createElement('video'); el.preload = 'metadata'; el.onloadedmetadata = () => { ok(Math.round(el.duration) || null); URL.revokeObjectURL(el.src); }; el.onerror = () => ok(null); el.src = URL.createObjectURL(f); });
  const submit = async (e) => {
    e.preventDefault();
    setError('');
    const d = Object.fromEntries(new FormData(e.currentTarget));
    try {
      let archivo = {};
      if (file) { setProgress(0); archivo = { ...(await api.subirVideo(file, setProgress)), duracion_seg: await duracion(file) }; }
      const r = await api.publicar({ titulo: d.titulo, descripcion: d.descripcion || null, tema: d.tema, ...archivo });
      toast('Contenido publicado.');
      navigate(`/app/capacitacion/${r.uid}`);
    } catch (err) { setError(err.message); setProgress(null); }
  };
  return (
    <>
      <div className="page-head upload-head"><LogoMark size={52} /><div><h1 className="page-title">Publicar un video</h1><p className="page-sub">Se sube directo al almacén privado; la plataforma solo guarda sus metadatos.</p></div></div>
      <form className="upload" onSubmit={submit}>
        <div className={`drop ${drag ? 'is-over' : ''}`} onClick={() => input.current.click()} role="button" tabIndex={0}
          onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); input.current.click(); } }}
          onDragOver={(e) => { e.preventDefault(); setDrag(true); }} onDragLeave={() => setDrag(false)}
          onDrop={(e) => { e.preventDefault(); setDrag(false); elegir(e.dataTransfer.files[0]); }}>
          <motion.span animate={{ y: drag ? -8 : 0 }}><Icon name="upload" size={44} /></motion.span>
          <b>{file ? file.name : 'Arrastra tu video o selecciónalo (opcional)'}</b>
          <small>{file ? `${(file.size / 1048576).toFixed(1)} MB` : 'MP4, MOV, AVI o WEBM · máx. 500 MB'}</small>
          <input ref={input} type="file" accept={MIMES.join(',')} hidden onChange={(e) => elegir(e.target.files[0])} />
        </div>
        <div className="upload__fields">
          <label className="field">Título<input name="titulo" required minLength={3} maxLength={160} placeholder="Ej.: Cómo preparar un equipo para donarlo" /></label>
          <label className="field">Tema<select name="tema">{c.temas.map((t) => <option key={t} value={t}>{TEMA[t] ?? t}</option>)}</select></label>
          <label className="field">Descripción<textarea name="descripcion" rows="4" maxLength={2000} placeholder="¿De qué trata?" /></label>
          {error && <p className="error" role="alert">{error}</p>}
          {progress !== null && <div className="progress" role="progressbar" aria-valuenow={progress} aria-valuemin="0" aria-valuemax="100"><i style={{ width: `${progress}%` }} /></div>}
          <button className="btn btn--primary" disabled={progress !== null}>{progress !== null ? `Subiendo ${progress} %` : 'Publicar'}</button>
        </div>
      </form>
    </>
  );
}
