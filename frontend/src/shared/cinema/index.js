// Kit de animación independiente del framework. Se activa con atributos data-* en el HTML.
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import Lenis from 'lenis';

gsap.registerPlugin(ScrollTrigger);

const reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
const hasHover = () => matchMedia('(hover: hover) and (pointer: fine)').matches;
const isWide = () => matchMedia('(min-width: 900px)').matches;
const all = (root, sel) => [...root.querySelectorAll(sel)];
const EXPO = 'expo.out';

let lenis = null;
const preferenciaMovimiento = matchMedia('(prefers-reduced-motion: reduce)');
preferenciaMovimiento.addEventListener('change', () => { if (preferenciaMovimiento.matches && lenis) { lenis.destroy(); lenis = null; } else if (!preferenciaMovimiento.matches) startSmoothScroll(); });
// Sin pantalla de carga, los títulos entran de inmediato en lugar de esperarla.
let introDone = (() => { try { return sessionStorage.getItem('eco-intro') === '1'; } catch { return false; } })();

export function startSmoothScroll() {
  if (lenis || reduced() || !hasHover()) return;
  lenis = new Lenis({ lerp: 0.09 });
  lenis.on('scroll', ScrollTrigger.update);
  gsap.ticker.add((t) => lenis?.raf(t * 1000));
  gsap.ticker.lagSmoothing(0);
}
export const scrollToTop = () => { if (lenis) lenis.scrollTo(0, { immediate: true }); else window.scrollTo(0, 0); };
export const scrollToId = (id) => {
  const el = document.getElementById(id);
  if (!el) return;
  if (lenis) lenis.scrollTo(el, { offset: -70 }); else el.scrollIntoView();
};

// Divide el texto en palabras o letras con máscara. Conserva <em> y lo anuncia completo a lectores.
function split(el, mode = 'words') {
  if (el.dataset.ready) return all(el, '.cin-i');
  el.dataset.ready = '1';
  const label = el.textContent.trim().replace(/\s+/g, ' ');
  const wrap = (text, tag) => text.split(/(\s+)/).map((part) => {
    if (!part.trim()) return part;
    const inner = mode === 'chars' ? [...part].map((c) => `<span class="cin-m"><span class="cin-i">${c}</span></span>`).join('') : `<span class="cin-m"><span class="cin-i">${part}</span></span>`;
    const body = mode === 'chars' ? `<span class="cin-w">${inner}</span>` : inner;
    return tag ? `<${tag}>${body}</${tag}>` : body;
  }).join('');
  el.innerHTML = [...el.childNodes].map((n) => {
    if (n.nodeType === 3) return wrap(n.textContent);
    if (n.tagName === 'BR') return '<br>';
    return wrap(n.textContent, n.tagName.toLowerCase());
  }).join('');
  el.setAttribute('aria-label', label);
  return all(el, '.cin-i');
}

function wordsOnScroll(el) {
  const text = el.textContent.trim();
  el.setAttribute('aria-label', text);
  el.innerHTML = text.split(/\s+/).map((w) => `<span class="cin-word" aria-hidden="true">${w}</span>`).join(' ');
  gsap.fromTo(el.children, { opacity: 0.14 }, { opacity: 1, stagger: 0.05, ease: 'none', scrollTrigger: { trigger: el, start: 'top 78%', end: 'bottom 45%', scrub: true } });
}

function count(el) {
  const to = Number(el.dataset.count);
  const decimals = Number(el.dataset.decimals ?? 0);
  const suffix = el.dataset.suffix ?? '';
  const write = (v) => { el.textContent = `${v.toFixed(decimals).replace('.', ',')}${suffix}`; };
  if (reduced()) { write(to); return; }
  const state = { v: 0 };
  write(0);
  gsap.to(state, { v: to, duration: 1.8, ease: 'power3.out', onUpdate: () => write(state.v), scrollTrigger: { trigger: el, start: 'top 92%', once: true } });
}

function tilt(el) {
  const max = Number(el.dataset.tilt || 7);
  const move = (e) => {
    const r = el.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width - 0.5;
    const y = (e.clientY - r.top) / r.height - 0.5;
    gsap.to(el, { rotateY: x * max * 2, rotateX: -y * max * 2, transformPerspective: 900, duration: 0.5, ease: 'power2.out' });
    el.style.setProperty('--gx', `${(x + 0.5) * 100}%`);
    el.style.setProperty('--gy', `${(y + 0.5) * 100}%`);
  };
  const leave = () => gsap.to(el, { rotateY: 0, rotateX: 0, duration: 0.9, ease: 'elastic.out(1,.5)' });
  el.addEventListener('pointermove', move);
  el.addEventListener('pointerleave', leave);
  return () => { el.removeEventListener('pointermove', move); el.removeEventListener('pointerleave', leave); };
}

function magnetic(el) {
  const move = (e) => {
    const r = el.getBoundingClientRect();
    gsap.to(el, { x: (e.clientX - r.left - r.width / 2) * 0.28, y: (e.clientY - r.top - r.height / 2) * 0.4, duration: 0.4, ease: 'power3.out' });
  };
  const leave = () => gsap.to(el, { x: 0, y: 0, duration: 0.8, ease: 'elastic.out(1,.4)' });
  el.addEventListener('pointermove', move);
  el.addEventListener('pointerleave', leave);
  return () => { el.removeEventListener('pointermove', move); el.removeEventListener('pointerleave', leave); };
}

function marquee(el) {
  const inner = el.firstElementChild;
  if (!inner) return;
  if (!inner.dataset.cloned) inner.append(...[...inner.children].map((c) => { const k = c.cloneNode(true); k.setAttribute('aria-hidden', 'true'); return k; }));
  inner.dataset.cloned = '1';
  const dir = Number(el.dataset.marquee || -1);
  const tween = gsap.fromTo(inner, { xPercent: dir < 0 ? 0 : -50 }, { xPercent: dir < 0 ? -50 : 0, duration: Number(el.dataset.speed || 32), ease: 'none', repeat: -1 });
  ScrollTrigger.create({
    trigger: document.body, start: 0, end: 'max',
    onUpdate: (self) => {
      const v = Math.min(Math.abs(self.getVelocity()) / 400, 4);
      gsap.to(tween, { timeScale: 1 + v, duration: 0.3, overwrite: true });
      gsap.to(tween, { timeScale: 1, duration: 1.2, delay: 0.3 });
    },
  });
}

function steps(el) {
  const items = all(el, '[data-step]');
  const images = all(el, '[data-step-img]');
  const dots = all(el, '[data-step-dot]');
  const show = (i) => {
    images.forEach((im, k) => {
      im.classList.toggle('is-on', k === i);
      if (k === i) gsap.fromTo(im, { clipPath: 'inset(100% 0 0 0)', scale: 1.08 }, { clipPath: 'inset(0% 0 0 0)', scale: 1, duration: 1.1, ease: EXPO, overwrite: true, zIndex: 2 });
      else gsap.set(im, { zIndex: 1 });
    });
    dots.forEach((d, k) => d.classList.toggle('is-on', k === i));
    items.forEach((s, k) => s.classList.toggle('is-on', k === i));
  };
  items.forEach((item, i) => ScrollTrigger.create({ trigger: item, start: 'top 58%', end: 'bottom 42%', onToggle: (s) => { if (s.isActive) show(i); } }));
}

function hscroll(el) {
  const track = el.querySelector('[data-track]');
  if (!track) return;
  const distance = () => Math.max(0, track.scrollWidth - window.innerWidth);
  gsap.to(track, { x: () => -distance(), ease: 'none', scrollTrigger: { trigger: el, pin: true, start: 'top top', end: () => `+=${distance()}`, scrub: 1, invalidateOnRefresh: true } });
}

function circleHero(el) {
  const mask = el.querySelector('[data-mask]');
  const fade = all(el, '[data-hero-fade]');
  const tl = gsap.timeline({ scrollTrigger: { trigger: el, start: 'top top', end: 'bottom bottom', scrub: 0.6 } });
  tl.fromTo(mask, { clipPath: 'circle(21% at 50% 50%)' }, { clipPath: 'circle(78% at 50% 50%)', ease: 'none', duration: 1 });
  const im = mask.querySelector('img');
  if (im) tl.fromTo(im, { scale: 1.3 }, { scale: 1, ease: 'none', duration: 1 }, 0);
  if (fade.length) tl.to(fade, { opacity: 0, y: -50, ease: 'none', duration: 0.45 }, 0.1);
  const late = all(el, '[data-hero-late]');
  if (late.length) tl.fromTo(late, { opacity: 0, y: 40 }, { opacity: 1, y: 0, ease: 'none', duration: 0.3 }, 0.68);
}

function insetHero(el) {
  const mask = el.querySelector('[data-mask]');
  const tl = gsap.timeline({ scrollTrigger: { trigger: el, start: 'top top', end: 'bottom bottom', scrub: 0.6 } });
  tl.fromTo(mask, { clipPath: 'inset(16% 26% 16% 26% round 24px)' }, { clipPath: 'inset(0% 0% 0% 0% round 0px)', ease: 'none', duration: 1 });
  const im = mask.querySelector('img');
  if (im) tl.fromTo(im, { scale: 1.25 }, { scale: 1, ease: 'none', duration: 1 }, 0);
  const fade = all(el, '[data-hero-fade]');
  if (fade.length) tl.to(fade, { opacity: 0, y: -40, ease: 'none', duration: 0.4 }, 0);
  const late = all(el, '[data-hero-late]');
  if (late.length) tl.fromTo(late, { opacity: 0, y: 40 }, { opacity: 1, y: 0, ease: 'none', duration: 0.35 }, 0.62);
}

// El texto gigante deja ver la foto a través de las letras y crece hasta llenar la pantalla.
function textZoom(el) {
  const word = el.querySelector('[data-zoom-word]');
  const tl = gsap.timeline({ scrollTrigger: { trigger: el, start: 'top top', end: 'bottom bottom', scrub: 0.6 } });
  tl.fromTo(word, { scale: 1 }, { scale: 16, ease: 'power2.in', duration: 1, transformOrigin: '50% 48%' });
  tl.to(word, { opacity: 0, ease: 'none', duration: 0.2 }, 0.8);
  const fade = all(el, '[data-hero-fade]');
  if (fade.length) tl.to(fade, { opacity: 0, y: -40, ease: 'none', duration: 0.3 }, 0);
  const late = all(el, '[data-hero-late]');
  if (late.length) tl.fromTo(late, { opacity: 0, y: 40 }, { opacity: 1, y: 0, ease: 'none', duration: 0.25 }, 0.75);
}

// Dos paneles que se abren como una compuerta.
function shutter(el) {
  const [a, b] = all(el, '[data-panel]');
  const tl = gsap.timeline({ scrollTrigger: { trigger: el, start: 'top top', end: 'bottom bottom', scrub: 0.6 } });
  tl.to(a, { xPercent: -101, ease: 'power2.inOut', duration: 1 }, 0).to(b, { xPercent: 101, ease: 'power2.inOut', duration: 1 }, 0);
  const im = el.querySelector('[data-behind] img');
  if (im) tl.fromTo(im, { scale: 1.25 }, { scale: 1, ease: 'none', duration: 1 }, 0);
  const fade = all(el, '[data-hero-fade]');
  if (fade.length) tl.to(fade, { opacity: 0, y: -40, ease: 'none', duration: 0.3 }, 0);
  const late = all(el, '[data-hero-late]');
  if (late.length) tl.fromTo(late, { opacity: 0, y: 40 }, { opacity: 1, y: 0, ease: 'none', duration: 0.3 }, 0.7);
}

// Tarjetas que se abren en abanico al hacer scroll.
function fan(el) {
  const cards = all(el, '[data-fan-card]');
  const mid = (cards.length - 1) / 2;
  const tl = gsap.timeline({ scrollTrigger: { trigger: el, start: 'top top', end: 'bottom bottom', scrub: 0.7 } });
  cards.forEach((c, i) => {
    tl.fromTo(c, { rotate: (i - mid) * 3, x: (i - mid) * 14, y: (i - mid) * 6 }, { rotate: (i - mid) * 9, x: (i - mid) * (isWide() ? 300 : 90), y: Math.abs(i - mid) * 30, ease: 'power1.inOut', duration: 1 }, 0);
  });
  const fade = all(el, '[data-hero-fade]');
  if (fade.length) tl.to(fade, { opacity: 0, ease: 'none', duration: 0.3 }, 0);
  const late = all(el, '[data-hero-late]');
  if (late.length) tl.fromTo(late, { opacity: 0, y: 30 }, { opacity: 1, y: 0, ease: 'none', duration: 0.3 }, 0.65);
}

function stack(el) {
  const cards = all(el, '[data-stack-card]');
  cards.forEach((c, i) => {
    if (i === cards.length - 1) return;
    gsap.to(c, { scale: 0.92, opacity: 0.45, ease: 'none', scrollTrigger: { trigger: cards[i + 1], start: 'top bottom', end: 'top 18%', scrub: true } });
  });
}

// Registra todos los efectos dentro de root. Devuelve la función que los limpia.
export function scan(root = document.body) {
  const cleanups = [];
  if (reduced()) {
    all(root, '[data-count]').forEach(count);
    return () => {};
  }
  const ctx = gsap.context(() => {
    all(root, '[data-split]').forEach((el) => {
      const parts = split(el, el.dataset.split || 'words');
      const vars = { yPercent: 115, duration: 1.15, ease: EXPO, stagger: el.dataset.split === 'chars' ? 0.018 : 0.06 };
      if (el.hasAttribute('data-now')) gsap.from(parts, { ...vars, delay: introDone ? 0.15 : Number(el.dataset.delay ?? 0.1) });
      else gsap.from(parts, { ...vars, scrollTrigger: { trigger: el, start: 'top 88%', once: true } });
    });
    all(root, '[data-words]').forEach(wordsOnScroll);
    all(root, '[data-img-reveal]').forEach((el) => {
      const im = el.querySelector('img') ?? el;
      gsap.from(el, { clipPath: 'inset(100% 0 0 0)', duration: 1.4, ease: EXPO, scrollTrigger: { trigger: el, start: 'top 90%', once: true } });
      gsap.from(im, { scale: 1.28, duration: 1.8, ease: EXPO, scrollTrigger: { trigger: el, start: 'top 90%', once: true } });
    });
    all(root, '[data-parallax]').forEach((el) => {
      gsap.fromTo(el, { yPercent: -Number(el.dataset.parallax) }, { yPercent: Number(el.dataset.parallax), ease: 'none', scrollTrigger: { trigger: el.parentElement, start: 'top bottom', end: 'bottom top', scrub: true } });
    });
    all(root, '[data-columns]').forEach((el) => {
      if (isWide()) all(el, '[data-speed]').forEach((c) => gsap.to(c, { yPercent: Number(c.dataset.speed), ease: 'none', scrollTrigger: { trigger: el, start: 'top bottom', end: 'bottom top', scrub: true } }));
    });
    gsap.utils.toArray(all(root, '[data-rise]')).forEach((el, i) => {
      gsap.from(el, { y: 44, opacity: 0, duration: 1.1, ease: EXPO, delay: Number(el.dataset.rise || 0) || (i % 4) * 0.06, scrollTrigger: { trigger: el, start: 'top 92%', once: true } });
    });
    all(root, '[data-pop]').forEach((el, i) => gsap.from(el, { scale: 0.7, opacity: 0, duration: 1, ease: 'back.out(1.6)', delay: 0.9 + i * 0.16 }));
    all(root, '[data-float]').forEach((el, i) => gsap.to(el, { y: Number(el.dataset.float || 12), duration: 2.6 + i * 0.4, ease: 'sine.inOut', repeat: -1, yoyo: true }));
    all(root, '[data-marquee]').forEach(marquee);
    all(root, '[data-count]').forEach(count);
    all(root, '[data-steps]').forEach(steps);
    all(root, '[data-stack]').forEach(stack);
    all(root, '[data-draw]').forEach((el) => {
      const len = el.getTotalLength?.() ?? 1000;
      gsap.fromTo(el, { strokeDasharray: len, strokeDashoffset: len }, { strokeDashoffset: 0, ease: 'none', scrollTrigger: { trigger: el.closest('svg') ?? el, start: 'top 80%', end: 'bottom 55%', scrub: true } });
    });
    all(root, '[data-bar]').forEach((el) => gsap.from(el, { scaleX: 0, transformOrigin: 'left', duration: 1.3, ease: EXPO, scrollTrigger: { trigger: el, start: 'top 95%', once: true } }));
    all(root, '[data-progress]').forEach((el) => gsap.fromTo(el, { scaleX: 0 }, { scaleX: 1, ease: 'none', transformOrigin: 'left', scrollTrigger: { start: 0, end: 'max', scrub: 0.3 } }));
    if (isWide()) all(root, '[data-hscroll]').forEach(hscroll);
    all(root, '[data-circle-hero]').forEach(circleHero);
    all(root, '[data-inset-hero]').forEach(insetHero);
    all(root, '[data-zoom-hero]').forEach(textZoom);
    all(root, '[data-shutter]').forEach(shutter);
    all(root, '[data-fan]').forEach(fan);
  }, root);
  if (hasHover()) {
    all(root, '[data-tilt]').forEach((el) => cleanups.push(tilt(el)));
    all(root, '[data-magnetic]').forEach((el) => cleanups.push(magnetic(el)));
  }
  // Las fotos cambian la altura de la página: recalcula los puntos de scroll al cargarlas.
  const refresh = () => ScrollTrigger.refresh();
  const pending = all(root, 'img').filter((im) => !im.complete);
  pending.forEach((im) => im.addEventListener('load', refresh, { once: true }));
  requestAnimationFrame(refresh);
  return () => {
    cleanups.forEach((fn) => fn());
    pending.forEach((im) => im.removeEventListener('load', refresh));
    ctx.revert();
  };
}

// Entrada de cada pantalla interna: los bloques suben en cascada.
export function pageIn(el) {
  if (!el || reduced()) return;
  gsap.fromTo(el.children, { y: 26, opacity: 0 }, { y: 0, opacity: 1, duration: 0.9, ease: EXPO, stagger: 0.07, clearProps: 'all' });
}

// Pantalla de carga: el contador sube y una cortina descubre la página. Solo una vez por sesión.
export function preloader(el, onDone = () => {}) {
  const skip = () => { introDone = true; el.remove(); onDone(); };
  let seen = false;
  try { seen = sessionStorage.getItem('eco-intro') === '1'; sessionStorage.setItem('eco-intro', '1'); } catch { /* sin almacenamiento */ }
  if (seen || reduced()) { skip(); return; }
  const num = el.querySelector('[data-load-num]');
  const state = { v: 0 };
  const tl = gsap.timeline({ onComplete: skip });
  tl.to(state, { v: 100, duration: 1.5, ease: 'power2.inOut', onUpdate: () => { if (num) num.textContent = String(Math.round(state.v)).padStart(3, '0'); } });
  const lines = el.querySelectorAll('[data-load-draw]');
  if (lines.length) tl.fromTo(lines, { strokeDasharray: 400, strokeDashoffset: 400 }, { strokeDashoffset: 0, duration: 1.4, ease: 'power2.inOut', stagger: 0.12 }, 0);
  tl.to(el, { yPercent: -100, duration: 0.9, ease: 'expo.inOut' }, '+=0.05');
}

// Cursor con punto preciso y aro con retraso; solo en dispositivos con puntero fino.
export function cursor(el) {
  if (!el || !hasHover() || reduced()) { el?.remove(); return () => {}; }
  const [dot, ring] = el.children;
  const dx = gsap.quickTo(dot, 'x', { duration: 0.08 });
  const dy = gsap.quickTo(dot, 'y', { duration: 0.08 });
  const rx = gsap.quickTo(ring, 'x', { duration: 0.45, ease: 'power3' });
  const ry = gsap.quickTo(ring, 'y', { duration: 0.45, ease: 'power3' });
  const move = (e) => { el.classList.add('is-on'); dx(e.clientX); dy(e.clientY); rx(e.clientX); ry(e.clientY); };
  // en zonas de precisión (el grafo) se usa el puntero normal: el anillo taparía los nodos
  const over = (e) => {
    el.classList.toggle('is-off', !!e.target.closest?.('[data-cursor=native]'));
    el.classList.toggle('is-link', !!e.target.closest?.('a,button,[role=button],input,select,textarea,label'));
  };
  window.addEventListener('pointermove', move);
  window.addEventListener('pointerover', over);
  return () => { window.removeEventListener('pointermove', move); window.removeEventListener('pointerover', over); };
}

// Red de partículas que reacciona al cursor.
export function particles(canvas, { density = 15000, link = 130 } = {}) {
  if (!canvas || reduced()) return () => {};
  const ctx = canvas.getContext('2d');
  const dpr = Math.min(devicePixelRatio, 2);
  let w; let h; let nodes = []; let raf; let visible = true;
  const mouse = { x: -999, y: -999 };
  const size = () => {
    const r = canvas.getBoundingClientRect();
    w = r.width; h = r.height;
    canvas.width = w * dpr; canvas.height = h * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const n = Math.min(90, Math.round((w * h) / density));
    nodes = Array.from({ length: n }, () => ({ x: Math.random() * w, y: Math.random() * h, vx: (Math.random() - 0.5) * 0.3, vy: (Math.random() - 0.5) * 0.3 }));
  };
  const frame = () => {
    raf = requestAnimationFrame(frame);
    if (!visible) return;
    ctx.clearRect(0, 0, w, h);
    nodes.forEach((p, i) => {
      p.x += p.vx; p.y += p.vy;
      if (p.x < 0 || p.x > w) p.vx *= -1;
      if (p.y < 0 || p.y > h) p.vy *= -1;
      for (let k = i + 1; k < nodes.length; k += 1) {
        const q = nodes[k];
        const d = Math.hypot(p.x - q.x, p.y - q.y);
        if (d < link) { ctx.globalAlpha = (1 - d / link) * 0.32; ctx.strokeStyle = getComputedStyle(document.documentElement).getPropertyValue('--primary').trim(); ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(p.x, p.y); ctx.lineTo(q.x, q.y); ctx.stroke(); }
      }
      const dm = Math.hypot(p.x - mouse.x, p.y - mouse.y);
      if (dm < 180) { ctx.globalAlpha = (1 - dm / 180) * 0.7; ctx.strokeStyle = getComputedStyle(document.documentElement).getPropertyValue('--primary').trim(); ctx.beginPath(); ctx.moveTo(p.x, p.y); ctx.lineTo(mouse.x, mouse.y); ctx.stroke(); }
      ctx.globalAlpha = .85; ctx.fillStyle = getComputedStyle(document.documentElement).getPropertyValue('--primary').trim();
      ctx.beginPath(); ctx.arc(p.x, p.y, 1.7, 0, 7); ctx.fill();
    });
  };
  const onMove = (e) => { const r = canvas.getBoundingClientRect(); mouse.x = e.clientX - r.left; mouse.y = e.clientY - r.top; };
  const io = new IntersectionObserver(([en]) => { visible = en.isIntersecting; });
  io.observe(canvas);
  size();
  frame();
  addEventListener('resize', size);
  addEventListener('pointermove', onMove);
  return () => { cancelAnimationFrame(raf); io.disconnect(); removeEventListener('resize', size); removeEventListener('pointermove', onMove); };
}

// Planeta de puntos en 3D con conexiones: se dibuja en canvas 2D, sin WebGL.
export function globe(canvas, { dots = 900 } = {}) {
  if (!canvas || reduced()) return () => {};
  const ctx = canvas.getContext('2d');
  const dpr = Math.min(devicePixelRatio, 2);
  const pts = Array.from({ length: dots }, (_, i) => {
    const y = 1 - (i / (dots - 1)) * 2;
    const r = Math.sqrt(1 - y * y);
    const t = i * 2.399963;
    return [Math.cos(t) * r, y, Math.sin(t) * r, Math.random() < 0.07];
  });
  let w; let h; let raf; let rot = 0; let tiltX = 0.35; let tx = 0.35; let extra = 0; let visible = true;
  const size = () => { const r = canvas.getBoundingClientRect(); w = r.width; h = r.height; canvas.width = w * dpr; canvas.height = h * dpr; ctx.setTransform(dpr, 0, 0, dpr, 0, 0); };
  const frame = () => {
    raf = requestAnimationFrame(frame);
    if (!visible) return;
    ctx.clearRect(0, 0, w, h);
    rot += 0.0026 + extra; extra *= 0.94; tiltX += (tx - tiltX) * 0.05;
    const R = Math.min(w, h) * 0.42;
    const cr = Math.cos(rot); const sr = Math.sin(rot); const ct = Math.cos(tiltX); const st = Math.sin(tiltX);
    pts.forEach(([x, y, z, hot]) => {
      const x1 = x * cr - z * sr; const z1 = x * sr + z * cr;
      const y1 = y * ct - z1 * st; const z2 = y * st + z1 * ct;
      const alpha = 0.12 + ((z2 + 1) / 2) * 0.88;
      const s = hot ? 2.4 : 1.3;
      ctx.globalAlpha = alpha; ctx.fillStyle = getComputedStyle(document.documentElement).getPropertyValue(hot ? '--accent' : '--primary').trim();
      ctx.beginPath(); ctx.arc(w / 2 + x1 * R, h / 2 + y1 * R, s * (0.5 + (z2 + 1) / 3), 0, 7); ctx.fill();
    });
  };
  const onMove = (e) => { tx = 0.35 + (e.clientY / innerHeight - 0.5) * 0.8; };
  const onScroll = () => { extra = Math.min(0.03, extra + 0.0012); };
  const io = new IntersectionObserver(([en]) => { visible = en.isIntersecting; });
  io.observe(canvas);
  size();
  frame();
  addEventListener('resize', size);
  addEventListener('pointermove', onMove);
  addEventListener('scroll', onScroll, { passive: true });
  return () => { cancelAnimationFrame(raf); io.disconnect(); removeEventListener('resize', size); removeEventListener('pointermove', onMove); removeEventListener('scroll', onScroll); };
}

export { gsap, ScrollTrigger };
