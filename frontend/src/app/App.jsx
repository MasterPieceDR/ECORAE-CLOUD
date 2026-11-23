import { lazy, Suspense } from 'react';
import { createHashRouter, RouterProvider, Navigate } from 'react-router-dom';
import { MotionConfig } from 'motion/react';
import { AuthProvider, RequireAuth } from '@/features/auth';
import { ToastProvider } from '@/shared/ui/Toast';
import { PageSkeleton } from '@/shared/ui/Skeleton';
import { AppLayout } from './layouts/AppLayout';

const page = (loader, name) => lazy(() => loader().then((m) => ({ default: m[name] })));
const LandingPage = page(() => import('@/features/landing'), 'LandingPage');
const LoginPage = page(() => import('@/features/auth/LoginPage'), 'LoginPage');
const DashboardPage = page(() => import('@/features/dashboard'), 'DashboardPage');
const TareasPage = page(() => import('@/features/tareas'), 'TareasPage');
const ObjetosPage = page(() => import('@/features/objetos/ObjetosPage'), 'ObjetosPage');
const ObjetoPage = page(() => import('@/features/objetos/ObjetoPage'), 'ObjetoPage');
const DocumentosPage = page(() => import('@/features/documentos'), 'DocumentosPage');
const RedPage = page(() => import('@/features/red'), 'RedPage');
const CapacitacionPage = page(() => import('@/features/capacitacion'), 'CapacitacionPage');
const ContenidoPage = page(() => import('@/features/capacitacion'), 'ContenidoPage');
const PublicarPage = page(() => import('@/features/capacitacion'), 'PublicarPage');
const AuditoriaPage = page(() => import('@/features/auditoria'), 'AuditoriaPage');
const UsuariosPage = page(() => import('@/features/usuarios'), 'UsuariosPage');
const ProfilePage = page(() => import('@/features/profile'), 'ProfilePage');
const VerificacionPage = page(() => import('@/features/verificacion'), 'VerificacionPage');

const lazyEl = (Component) => <Suspense fallback={<PageSkeleton />}><Component /></Suspense>;

// HashRouter: funciona servido desde S3 + CloudFront sin reglas de reescritura (RF-CL-01)
const router = createHashRouter([
  { path: '/', element: lazyEl(LandingPage) },
  { path: '/login', element: lazyEl(LoginPage) },
  {
    path: '/app',
    element: <RequireAuth><AppLayout /></RequireAuth>,
    children: [
      { index: true, element: lazyEl(DashboardPage) },
      { path: 'tareas', element: lazyEl(TareasPage) },
      { path: 'objetos', element: lazyEl(ObjetosPage) },
      { path: 'objetos/:codigo', element: lazyEl(ObjetoPage) },
      { path: 'documentos', element: lazyEl(DocumentosPage) },
      { path: 'red', element: lazyEl(RedPage) },
      { path: 'capacitacion', element: lazyEl(CapacitacionPage) },
      { path: 'capacitacion/publicar', element: lazyEl(PublicarPage) },
      { path: 'capacitacion/:uid', element: lazyEl(ContenidoPage) },
      { path: 'auditoria', element: lazyEl(AuditoriaPage) },
      { path: 'usuarios', element: lazyEl(UsuariosPage) },
      { path: 'perfil', element: lazyEl(ProfilePage) },
      { path: 'base-de-datos', element: lazyEl(VerificacionPage) },
      { path: '*', element: <Navigate to="/app" replace /> },
    ],
  },
  { path: '*', element: <Navigate to="/" replace /> },
]);

export function App() {
  return (
    <MotionConfig reducedMotion="user">
      <ToastProvider>
        <AuthProvider>
          <RouterProvider router={router} />
        </AuthProvider>
      </ToastProvider>
    </MotionConfig>
  );
}
