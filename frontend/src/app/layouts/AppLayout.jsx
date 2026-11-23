import { lazy, Suspense, useEffect, useRef, useState } from 'react';
import { NavLink, Link, useLocation, useNavigate, useOutlet } from 'react-router-dom';
import { AnimatePresence, motion } from 'motion/react';
import { useAuth, useCatalogos } from '@/features/auth';
import { coverFor, photo } from '@/shared/api';
import { cursor, particles, scrollToTop, ScrollTrigger } from '@/shared/cinema/index.js';
import { Icon } from '@/shared/ui/Icon';
import { Logo } from '@/shared/ui/Logo';
import { Avatar } from '@/shared/ui/Avatar';
import './AppLayout.css';

const AsistentePanel = lazy(() => import('@/features/asistente').then((m) => ({ default: m.AsistentePanel })));

const OPERATIVOS = ['SOLICITUD.CREAR', 'RECOLECCION.PROGRAMAR', 'RECEPCION.REGISTRAR', 'EVALUACION.REGISTRAR', 'TRANSFERENCIA.CREAR',
  'TRANSFERENCIA.CONFIRMAR', 'TRATAMIENTO.REGISTRAR', 'CIERRE.CONFIRMAR'];

// La navegación se arma con los permisos efectivos que devuelve la base, no con una lista de roles en el código.
const NAV = [
  { key: 'inicio', label: 'Inicio', icon: 'home', path: '/app' },
  { key: 'tareas', label: 'Mis tareas', corto: 'Tareas', icon: 'inbox', path: '/app/tareas', ver: (can) => OPERATIVOS.some((p) => can(p)) },
  { key: 'objetos', label: 'Equipos y lotes', corto: 'Equipos', icon: 'box', path: '/app/objetos' },
  { key: 'catalogo', label: 'Catálogo', icon: 'layers', path: '/app/catalogo', ver: (can) => can('CATALOGO.ADMINISTRAR') || can('RED.GESTIONAR') },
  { key: 'documentos', label: 'Documentos', icon: 'file', path: '/app/documentos', ver: (can) => OPERATIVOS.some((p) => can(p)) || can('AUDITORIA.CONSULTAR') },
  { key: 'red', label: 'Red de flujo', corto: 'Red', icon: 'network', path: '/app/red', ver: (can) => can('RED.EJECUTAR_FLUJO') || can('GOBIERNO.DECIDIR') || can('AUDITORIA.CONSULTAR') },
  { key: 'capacitacion', label: 'Capacitación', corto: 'Aprende', icon: 'play', path: '/app/capacitacion' },
  { key: 'auditoria', label: 'Auditoría', icon: 'history', path: '/app/auditoria', ver: (can) => can('AUDITORIA.CONSULTAR') },
  { key: 'usuarios', label: 'Usuarios', icon: 'users', path: '/app/usuarios', ver: (can) => can('USUARIO.ADMINISTRAR') },
  { key: 'bd', label: 'Base de datos', corto: 'BD', icon: 'layers', path: '/app/base-de-datos' },
  { key: 'perfil', label: 'Perfil', icon: 'user', path: '/app/perfil' },
];

export function AppLayout() {
  const { user, can, logout } = useAuth();
  const { nombreRol } = useCatalogos();
  const { pathname } = useLocation();
  const navigate = useNavigate();
  const outlet = useOutlet();
  const [asistente, setAsistente] = useState(false);
  const items = NAV.filter((n) => !n.ver || n.ver(can));
  const net = useRef(null);
  const pointer = useRef(null);
  useEffect(() => particles(net.current, { color: '150,230,170', density: 26000 }), []);
  useEffect(() => cursor(pointer.current), []);
  useEffect(() => { scrollToTop(); ScrollTrigger.refresh(); }, [pathname]);
  const rolPrincipal = user.roles[0]?.codigo;
  const onSearch = (e) => {
    e.preventDefault();
    const q = new FormData(e.currentTarget).get('q').trim();
    if (q) navigate(`/app/objetos?q=${encodeURIComponent(q)}`);
  };
  return (
    <div className="shell">
      <canvas ref={net} className="shell__net" aria-hidden="true" />
      <div ref={pointer} className="cin-cursor" aria-hidden="true"><i /><i /></div>
      <a className="skip" href="#contenido">Saltar al contenido</a>
      <aside className="side">
        <Link to="/app" className="side__brand" aria-label="Ir al inicio"><Logo /></Link>
        <nav aria-label="Principal">
          {items.map((n) => (
            <NavLink key={n.key} to={n.path} end={n.path === '/app'} className="side__link">
              {({ isActive }) => (
                <>
                  {isActive && <motion.span layoutId="side-pill" className="side__pill" transition={{ type: 'spring', stiffness: 420, damping: 34 }} />}
                  <Icon name={n.icon} /><span>{n.label}</span>
                </>
              )}
            </NavLink>
          ))}
        </nav>
        <div className="side__who"><b>{user.alias}</b><small>{nombreRol(rolPrincipal)}{user.roles[0]?.centro ? ` · ${user.roles[0].centro}` : ''}</small></div>
        <button className="side__logout" onClick={() => logout().then(() => navigate('/'))}><Icon name="logout" /> Cerrar sesión</button>
      </aside>

      <div className="main">
        <header className="top">
          <Link to="/app" className="top__logo" aria-label="Ir al inicio"><Logo /></Link>
          <form className="search" role="search" onSubmit={onSearch}>
            <Icon name="search" />
            <input name="q" type="search" placeholder="Buscar equipo, lote, marca..." aria-label="Buscar equipos y lotes" />
          </form>
          <button className="ask-btn" onClick={() => setAsistente(true)} aria-haspopup="dialog"><Icon name="bot" /><span>Asistente</span></button>
          <Link to="/app/perfil" className="top__me" title={`${user.alias} · ${nombreRol(rolPrincipal)}`}><Avatar name={user.alias} /></Link>
        </header>
        <div className="cover" aria-hidden="true"><img key={coverFor(pathname)} src={photo(coverFor(pathname))} alt="" /></div>
        <main id="contenido" className="content">
          <AnimatePresence mode="wait" initial={false}>
            <motion.div key={pathname} initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -8 }} transition={{ duration: 0.22 }}>
              {outlet}
            </motion.div>
          </AnimatePresence>
        </main>
      </div>

      <nav className="tabs" aria-label="Navegación móvil">
        {items.slice(0, 5).map((n) => (
          <NavLink key={n.key} to={n.path} end={n.path === '/app'} className="tabs__link">
            <Icon name={n.icon} /><span>{n.corto ?? n.label}</span>
          </NavLink>
        ))}
      </nav>
      {asistente && <Suspense fallback={null}><AsistentePanel onClose={() => setAsistente(false)} /></Suspense>}
    </div>
  );
}
