import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { api, token, onSesionExpirada } from '@/shared/api';
import { PageSkeleton } from '@/shared/ui/Skeleton';

const AuthContext = createContext(null);
const CatalogosContext = createContext(null);
export const useAuth = () => useContext(AuthContext);
export const useCatalogos = () => useContext(CatalogosContext);

// Igual que seg.fn_tiene_permiso: un rol global vale en cualquier centro; uno con alcance, solo en el suyo.
function crearCan(user) {
  const mapa = new Map();
  (user?.permisos ?? []).forEach((p) => { if (!mapa.has(p.codigo)) mapa.set(p.codigo, new Set()); mapa.get(p.codigo).add(p.centro ?? null); });
  return (permiso, centro) => {
    const a = mapa.get(permiso);
    if (!a) return false;
    return centro == null || a.has(null) || a.has(centro);
  };
}

export function AuthProvider({ children }) {
  const [user, setUser] = useState(undefined);
  const [catalogos, setCatalogos] = useState(null);

  const cargar = useCallback(async () => {
    if (!token.get()) { setUser(null); return; }
    try {
      const [p, c] = await Promise.all([api.me(), api.catalogos()]);
      setCatalogos(c);
      setUser(p);
    } catch { token.set(null); setUser(null); }
  }, []);

  useEffect(() => { cargar(); }, [cargar]);
  useEffect(() => onSesionExpirada(() => { token.set(null); setUser(null); }), []);

  const entrar = async (sesion) => {
    token.set(sesion.access_token);
    setCatalogos(await api.catalogos());
    setUser(sesion.usuario);
    return sesion.usuario;
  };

  const value = useMemo(() => ({
    user,
    can: crearCan(user),
    tieneRol: (r) => (user?.roles_efectivos ?? []).includes(r),
    login: async (correo, password) => entrar(await api.login(correo, password)),
    registrar: async (datos) => entrar(await api.registro(datos)),
    refrescar: async () => setUser(await api.me()),
    logout: async () => { token.set(null); setUser(null); setCatalogos(null); },
  }), [user]); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <AuthContext.Provider value={value}>
      <CatalogosProvider data={catalogos}>{children}</CatalogosProvider>
    </AuthContext.Provider>
  );
}

// Catálogos de la base (ADR-003): los nombres y reglas de la interfaz salen de aquí, no del código.
function CatalogosProvider({ data, children }) {
  const value = useMemo(() => {
    const c = data ?? {};
    const idx = (lista, k = 'codigo') => Object.fromEntries((lista ?? []).map((x) => [x[k], x]));
    const estados = idx(c.estados);
    const clas = idx(c.clasificaciones);
    const destinos = idx(c.destinos);
    const roles = idx(c.roles);
    const centros = idx(c.centros);
    const evidencias = idx(c.tipos_evidencia);
    const categorias = idx(c.categorias);
    const motivos = idx(c.motivos);
    const materiales = idx(c.materiales);
    return {
      c,
      listo: !!data,
      nombreEstado: (x) => estados[x]?.nombre ?? x,
      nombreClasificacion: (x) => clas[x]?.nombre ?? x ?? 'Sin evaluar',
      nombreDestino: (x) => destinos[x]?.nombre ?? x,
      nombreRol: (x) => roles[x]?.nombre ?? x,
      nombreCentro: (x) => centros[x]?.nombre ?? x,
      nombreCategoria: (x) => categorias[x]?.nombre ?? x,
      nombreMotivo: (x) => motivos[x]?.nombre ?? x,
      nombreMaterial: (x) => materiales[x]?.nombre ?? x,
      tipoEvidencia: (x) => evidencias[x],
      categoria: (x) => categorias[x],
      destinosPara: (clasificacion) => (c.matriz_destinos ?? []).filter((m) => m.clasificacion === clasificacion).map((m) => m.destino),
    };
  }, [data]);
  return <CatalogosContext.Provider value={value}>{children}</CatalogosContext.Provider>;
}

export function RequireAuth({ children }) {
  const { user } = useAuth();
  const { listo } = useCatalogos();
  const location = useLocation();
  if (user === undefined || (user && !listo)) return <PageSkeleton />;
  return user ? children : <Navigate to="/login" replace state={{ from: location.pathname }} />;
}
