import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { STATS, MANIFESTO, STEPS, DESTINIES, PLATFORM, GALLERY, ESTADOS_PUBLICOS, CAPACITACION_PUBLICA, photo, fotoTema, TEMA } from '@/shared/api';
import { cursor, particles, preloader, scrollToId } from '@/shared/cinema/index.js';
import { useCinema } from '@/shared/hooks/useCinema';
import { Logo, LogoMark } from '@/shared/ui/Logo';
import { Icon } from '@/shared/ui/Icon';
import './landing.css';

const COLUMNS = [GALLERY.slice(0, 3), GALLERY.slice(3, 6), GALLERY.slice(6, 9)];

export function LandingPage() {
  const root = useCinema();
  const loader = useRef(null);
  const pointer = useRef(null);
  const net = useRef(null);
  const [open, setOpen] = useState(false);
  useEffect(() => { if (loader.current) preloader(loader.current); }, []);
  useEffect(() => cursor(pointer.current), []);
  useEffect(() => particles(net.current, { color: '182,243,106', density: 22000 }), []);
  const jump = (id) => (e) => { e.preventDefault(); setOpen(false); scrollToId(id); };
  return (
    <div className="lp" ref={root}>
      <div ref={loader} className="lp-load" aria-hidden="true">
        <LogoMark size={92} draw />
        <span data-load-num>000</span>
      </div>
      <div ref={pointer} className="cin-cursor" aria-hidden="true"><i /><i /></div>
      <div className="lp-progress" data-progress aria-hidden="true" />

      <header className="lp-nav">
        <Link to="/" aria-label="EcoRAEE Cloud"><Logo /></Link>
        <nav className={open ? 'is-open' : ''} aria-label="Secciones">
          <a href="#recorrido" onClick={jump('recorrido')}>Recorrido</a>
          <a href="#destinos" onClick={jump('destinos')}>Destinos</a>
          <a href="#plataforma" onClick={jump('plataforma')}>Plataforma</a>
          <a href="#aprende" onClick={jump('aprende')}>Aprende</a>
          <Link to="/login" className="btn btn--primary btn--sm" data-magnetic>Entrar</Link>
        </nav>
        <button className="lp-burger" onClick={() => setOpen((v) => !v)} aria-expanded={open} aria-label="Abrir menú"><Icon name={open ? 'close' : 'menu'} /></button>
      </header>

      <main id="contenido">
        <section className="hero" data-circle-hero>
          <div className="hero__stage">
            <canvas ref={net} className="hero__net" aria-hidden="true" />
            <div className="hero__mask" data-mask><img src={photo('placas-pila')} alt="Montón de placas electrónicas desechadas" fetchPriority="high" /><i /></div>
            <div className="hero__title" data-hero-fade>
              <p className="eyebrow" data-split data-now data-delay="1.8">Economía circular · Ecuador</p>
              <h1 data-split data-now data-delay="1.9">Aprende, comparte <br />y <em>cuida el planeta</em></h1>
            </div>
            <p className="hero__scroll" data-hero-fade>Desliza para descubrir <i /></p>
            <div className="hero__late" data-hero-late>
              <h2>Cada equipo merece una <em>segunda vida.</em></h2>
              <div className="hero__cta">
                <Link to="/login" className="btn btn--primary" data-magnetic><Icon name="play" size={16} /> Explorar videos</Link>
                <a href="#recorrido" className="btn btn--ghost" onClick={jump('recorrido')} data-magnetic>Ver el recorrido</a>
              </div>
            </div>
          </div>
        </section>

        <section className="manifesto"><p data-words>{MANIFESTO}</p></section>

        <div className="ticker" data-marquee data-speed="40" aria-hidden="true"><div>{ESTADOS_PUBLICOS.map((s) => <span key={s}>{s}<i>→</i></span>)}</div></div>

        <section className="stats" aria-label="Cifras">
          {STATS.map((s) => (
            <div key={s.label} data-rise><b data-count={s.value} data-decimals={s.decimals} data-suffix={s.suffix}>{s.value}{s.suffix}</b><p>{s.label}</p></div>
          ))}
        </section>

        <section id="recorrido" className="steps" data-steps>
          <div className="steps__media" aria-hidden="true">
            {STEPS.map((s, i) => <img key={s.n} src={photo(s.photo)} alt="" data-step-img className={i === 0 ? 'is-on' : ''} loading="lazy" />)}
            <div className="steps__dots">{STEPS.map((s, i) => <i key={s.n} data-step-dot className={i === 0 ? 'is-on' : ''} />)}</div>
          </div>
          <div className="steps__list">
            <h2 data-split>Un solo recorrido, <em>de principio a fin.</em></h2>
            {STEPS.map((s) => (
              <article key={s.n} className="step" data-step>
                <img className="step__img" src={photo(s.photo)} alt="" loading="lazy" />
                <span>{s.n}</span>
                <h3>{s.title}</h3>
                <p>{s.text}</p>
                <small>{s.who}</small>
              </article>
            ))}
          </div>
        </section>

        <section id="destinos" className="hs" data-hscroll>
          <div className="hs__track" data-track>
            <div className="hs__intro">
              <h2 data-split>Cuatro destinos, <em>una decisión técnica.</em></h2>
              <p>Solo un técnico autorizado clasifica cada equipo. El sistema muestra únicamente los caminos permitidos.</p>
            </div>
            {DESTINIES.map((d, i) => (
              <article key={d.title} className="dest" data-tilt="5">
                <img src={photo(d.photo)} alt="" loading="lazy" />
                <span>0{i + 1}</span>
                <div><h3>{d.title}</h3><p>{d.text}</p></div>
              </article>
            ))}
          </div>
        </section>

        <section id="plataforma" className="plat">
          <div className="plat__head">
            <h2 data-split>La red, <em>a la vista.</em></h2>
            <p data-rise>Cuando se detecta un cuello de botella, se ve. Ampliar solo la evaluación suma 25 equipos por semana; una inversión coordinada, 80.</p>
          </div>
          <div className="plat__grid">
            <article className="plat__main" data-tilt="3" data-rise>
              <svg viewBox="0 0 640 300" role="img" aria-label="Esquema de la red de centros, evaluación y destinos">
                {['M60 60C180 60 180 150 300 150', 'M60 150C180 150 180 150 300 150', 'M60 240C180 240 180 150 300 150', 'M340 150C450 150 450 60 580 60', 'M340 150C450 150 450 150 580 150', 'M340 150C450 150 450 240 580 240'].map((d, i) => <path key={d} data-draw d={d} fill="none" stroke={i === 3 || i === 4 ? '#B6F36A' : 'rgb(255 255 255 / .35)'} strokeWidth="3" />)}
                {[[60, 60], [60, 150], [60, 240], [580, 60], [580, 150], [580, 240]].map(([x, y]) => <circle key={`${x}-${y}`} cx={x} cy={y} r="11" fill="#0A1C14" stroke="#B6F36A" strokeWidth="2.500" />)}
                <circle cx="320" cy="150" r="40" fill="#FF8A68" opacity=".18" /><circle cx="320" cy="150" r="24" fill="#FF8A68" />
                <text x="320" y="214" textAnchor="middle" fill="#FFC3B2" fontSize="15" fontWeight="600">Evaluación: 160 / 160</text>
              </svg>
              <div className="plat__nums"><div><b data-count="200">200</b><span>flujo máximo</span></div><div><b data-count="54" data-suffix=" %">54 %</b><span>cobertura</span></div><div><b data-count="280">280</b><span>con ampliación</span></div></div>
            </article>
            {PLATFORM.map((p) => (
              <article key={p.title} className="plat__cell" data-rise data-tilt="6"><span><Icon name={p.icon} size={24} /></span><h3>{p.title}</h3><p>{p.text}</p></article>
            ))}
          </div>
        </section>

        <section className="wall" data-columns aria-hidden="true">
          {COLUMNS.map((col, i) => (
            <div key={col[0]} data-speed={[-16, 14, -22][i]}>
              {col.map((p) => <figure key={p} data-img-reveal><img src={photo(p)} alt="" loading="lazy" /></figure>)}
            </div>
          ))}
        </section>

        <section id="aprende" className="learn">
          <h2 data-split>Aprende <em>en minutos.</em></h2>
          <div className="learn__grid">
            {CAPACITACION_PUBLICA.map((v, i) => (
              <Link key={v.titulo} to="/app/capacitacion" className={`learn__v ${i === 0 ? 'is-big' : ''}`} data-rise>
                <figure><img src={fotoTema(v.tema, i)} alt="" loading="lazy" /></figure>
                <span className="learn__p"><Icon name="play" size={18} /></span>
                <div><small>{TEMA[v.tema]}</small><h3>{v.titulo}</h3></div>
              </Link>
            ))}
          </div>
        </section>

        <section className="end">
          <img src={photo('cotopaxi')} alt="El Cotopaxi al atardecer sobre las luces de la ciudad" loading="lazy" data-parallax="10" />
          <div>
            <h2 data-split>Juntos por un Ecuador <em>más sostenible.</em></h2>
            <Link to="/login" className="btn btn--primary" data-magnetic>Registrar mi primer equipo <Icon name="arrow" size={18} /></Link>
          </div>
        </section>
      </main>

      <footer className="foot">
        <p className="foot__big" aria-hidden="true">EcoRAEE</p>
        <div><Logo /><p>Proyecto Integrador · Ingeniería en Sistemas de Información · UIDE. Datos sintéticos con fines académicos. Fotos: Unsplash.</p></div>
      </footer>
    </div>
  );
}
