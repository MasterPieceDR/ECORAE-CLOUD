import { useEffect, useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { motion } from 'motion/react';
import { useAuth } from './index';
import { api, photo } from '@/shared/api';
import { Icon } from '@/shared/ui/Icon';
import { LogoMark } from '@/shared/ui/Logo';
import { useCinema } from '@/shared/hooks/useCinema';
import './auth.css';

export function LoginPage() {
  const [tab, setTab] = useState('login');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [showPass, setShowPass] = useState(false);
  const [demo, setDemo] = useState(null);
  const [orgs, setOrgs] = useState([]);
  const { login, registrar } = useAuth();
  const navigate = useNavigate();
  const { state } = useLocation();
  const root = useCinema();

  useEffect(() => { api.cuentasDemo().then(setDemo, () => setDemo({ habilitado: false })); }, []);
  useEffect(() => { if (tab === 'register' && !orgs.length) api.organizacionesPublicas().then(setOrgs, () => {}); }, [tab, orgs.length]);

  const ir = () => navigate(state?.from ?? '/app', { replace: true });
  const entrarComo = async (cuenta) => {
    setError(''); setBusy(true);
    try { await login(cuenta.correo, demo.clave); ir(); } catch (err) { setError(err.message); setBusy(false); }
  };
  const submit = async (e) => {
    e.preventDefault();
    setError(''); setBusy(true);
    const d = Object.fromEntries(new FormData(e.currentTarget));
    try {
      if (tab === 'login') await login(d.correo, d.password);
      else await registrar({ alias: d.alias.trim().toLowerCase(), correo: d.correo, password: d.password, organizacion: d.organizacion });
      ir();
    } catch (err) { setError(err.message); setBusy(false); }
  };

  return (
    <div className="auth" ref={root}>
      <div className="auth__art">
        <img src={photo('cotopaxi')} alt="El Cotopaxi al atardecer sobre las luces de la ciudad" />
        <Link to="/" aria-label="Volver al inicio" className="auth__logo"><LogoMark size={64} animated /></Link>
        <div><p className="auth__big" data-split data-now>Juntos por un Ecuador <em>más sostenible</em></p></div>
      </div>
      <div className="auth__panel">
        <motion.div className="auth__form" initial={{ opacity: 0, y: 26 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: .7, ease: [0.16, 1, 0.3, 1] }}>
          <h1>{tab === 'login' ? 'Qué bueno verte de nuevo' : 'Únete a la red'}</h1>
          <div className="auth__tabs" role="tablist">
            {[['login', 'Iniciar sesión'], ['register', 'Registrarse']].map(([k, label]) => (
              <button key={k} role="tab" aria-selected={tab === k} onClick={() => { setTab(k); setError(''); }}>
                {tab === k && <motion.i layoutId="auth-pill" />}<span>{label}</span>
              </button>
            ))}
          </div>
          <form onSubmit={submit} className="auth__fields">
            {tab === 'register' && (
              <>
                <label className="field">Alias (seudónimo visible)<input name="alias" required minLength={3} maxLength={40} pattern="[a-zA-Z0-9][a-zA-Z0-9._\-]{2,39}" placeholder="ana.mora" autoComplete="username" /></label>
                <label className="field">Organización
                  <select name="organizacion" required defaultValue="">
                    <option value="" disabled>Selecciona</option>
                    {orgs.map((o) => <option key={o.codigo} value={o.codigo}>{o.nombre}</option>)}
                  </select>
                </label>
              </>
            )}
            <label className="field">Correo electrónico<input name="correo" type="email" required autoComplete="email" /></label>
            <label className="field">Contraseña
              <span className="auth__pass">
                <input name="password" type={showPass ? 'text' : 'password'} required minLength={tab === 'register' ? 10 : undefined} autoComplete={tab === 'login' ? 'current-password' : 'new-password'} />
                <button type="button" onClick={() => setShowPass((v) => !v)} aria-label={showPass ? 'Ocultar contraseña' : 'Mostrar contraseña'}><Icon name="eye" /></button>
              </span>
            </label>
            {tab === 'register' && <p className="auth__note">Tu cuenta empieza con el rol base: puedes consultar y capacitarte. El administrador asigna las funciones operativas (separación de funciones).</p>}
            {error && <p className="error" role="alert">{error}</p>}
            <button className="btn btn--primary" disabled={busy}>{busy ? 'Entrando...' : tab === 'login' ? 'Ingresar' : 'Crear cuenta'}</button>
          </form>
          {tab === 'login' && demo?.habilitado && (
            <section className="demo" aria-labelledby="demo-t">
              <h2 id="demo-t">Cuentas de demostración <small>datos sintéticos · clave {demo.clave}</small></h2>
              <div className="demo__grid">
                {demo.cuentas.map((c) => (
                  <button key={c.alias} type="button" className="demo__btn" disabled={busy} onClick={() => entrarComo(c)} title={c.descripcion}>
                    <b>{c.rol}</b><small>{c.descripcion}</small>
                  </button>
                ))}
              </div>
            </section>
          )}
        </motion.div>
      </div>
    </div>
  );
}
