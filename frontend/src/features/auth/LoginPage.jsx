import { useEffect, useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { motion } from 'motion/react';
import { useAuth } from './index';
import { api, photo } from '@/shared/api';
import { Stepper } from '@/shared/ui/Stepper';
import { Icon } from '@/shared/ui/Icon';
import { LogoMark } from '@/shared/ui/Logo';
import { useCinema } from '@/shared/hooks/useCinema';
import './auth.css';

export function LoginPage() {
  const { state } = useLocation();
  const [tab, setTab] = useState(state?.registro ? 'register' : 'login');
  const [error, setError] = useState('');
  const [correoVerificar, setCorreoVerificar] = useState('');
  const [espera, setEspera] = useState(0);
  const [mensaje, setMensaje] = useState('');
  const [busy, setBusy] = useState(false);
  const [showPass, setShowPass] = useState(false);
  const [demo, setDemo] = useState(null);
  const [orgs, setOrgs] = useState([]);
  const { login, registrar } = useAuth();
  const navigate = useNavigate();
  const root = useCinema();

  useEffect(() => { api.cuentasDemo().then(setDemo, () => setDemo({ habilitado: false })); }, []);
  useEffect(() => { if (tab === 'register' && !orgs.length) api.organizacionesPublicas().then(setOrgs, () => {}); }, [tab, orgs.length]);

  useEffect(() => { if (!espera) return undefined; const t = setTimeout(() => setEspera((n) => n - 1), 1000); return () => clearTimeout(t); }, [espera]);

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
      if (tab === 'verificar') {
        const resultado = await api.verificarCorreo(correoVerificar, d.codigo);
        setMensaje(resultado.mensaje); setTab('login');
      } else if (tab === 'login') { await login(d.correo, d.password); ir(); }
      else {
        await registrar({ alias: d.alias.trim().toLowerCase(), correo: d.correo, password: d.password, organizacion: d.organizacion });
        setCorreoVerificar(d.correo); setEspera(60); setTab('verificar');
        setMensaje('Si corresponde, recibirás un código de seis dígitos.');
      }
    } catch (err) {
      if (err.codigo === 'VERIFICACION_PENDIENTE') { setCorreoVerificar(d.correo); setTab('verificar'); setMensaje(err.message); }
      else setError(err.message);
    } finally { setBusy(false); }
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
          <h1>{tab === 'login' ? 'Qué bueno verte de nuevo' : tab === 'verificar' ? 'Verifica tu correo' : 'Únete a la red'}</h1>
          <div className="auth__tabs" role="tablist">
            {[['login', 'Iniciar sesión'], ['register', 'Registrarse']].map(([k, label]) => (
              <button key={k} role="tab" aria-selected={tab === k} onClick={() => { setTab(k); setError(''); }}>
                {tab === k && <motion.i layoutId="auth-pill" />}<span>{label}</span>
              </button>
            ))}
          </div>
          {tab !== 'login' && <Stepper steps={['Datos', 'Verificar correo']} current={tab === 'verificar' ? 1 : 0} />}
          <form onSubmit={submit} className="auth__fields">
            {tab === 'verificar' && <><p>Ingresa el código enviado a {correoVerificar}.</p><label className="field">Código de seis dígitos<input name="codigo" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required /></label><button type="button" disabled={busy || espera > 0} onClick={async () => { setError(''); setBusy(true); try { const r = await api.reenviarCodigo(correoVerificar); setMensaje(r.mensaje); setEspera(60); } catch (e) { setError(e.message); } finally { setBusy(false); } }}>{espera ? `Reenviar en ${espera} s` : 'Reenviar código'}</button></>}
            {mensaje && <p role="status">{mensaje}</p>}
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
            {tab !== 'verificar' && <><label className="field">Correo electrónico<input name="correo" type="email" required autoComplete="email" /></label>
            <label className="field">Contraseña
              <span className="auth__pass">
                <input name="password" type={showPass ? 'text' : 'password'} required minLength={tab === 'register' ? 10 : undefined} autoComplete={tab === 'login' ? 'current-password' : 'new-password'} />
                <button type="button" onClick={() => setShowPass((v) => !v)} aria-label={showPass ? 'Ocultar contraseña' : 'Mostrar contraseña'}><Icon name="eye" /></button>
              </span>
            </label>
            </>}
            {tab === 'register' && <p className="auth__note">Tu cuenta empieza con el rol base: puedes consultar y capacitarte. El administrador asigna las funciones operativas (separación de funciones).</p>}
            {error && <p className="error" role="alert">{error}</p>}
            <button className="btn btn--primary" disabled={busy}>{busy ? 'Entrando...' : tab === 'login' ? 'Ingresar' : tab === 'verificar' ? 'Verificar' : 'Crear cuenta'}</button>
          </form>
          {tab === 'login' && demo?.habilitado && (
            <details className="demo">
              <summary>Cuentas de demostración</summary><p className="hint">Datos sintéticos · clave {demo.clave}</p>
              <div className="demo__grid">
                {demo.cuentas.map((c) => (
                  <button key={c.alias} type="button" className="demo__btn" disabled={busy} onClick={() => entrarComo(c)} title={c.descripcion}>
                    <b>{c.rol}</b><small>{c.descripcion}</small>
                  </button>
                ))}
              </div>
            </details>
          )}
        </motion.div>
      </div>
    </div>
  );
}
