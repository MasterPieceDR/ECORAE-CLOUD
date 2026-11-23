# EcoRAEE Cloud · Frontend

React 19 + React Router 7 + Motion/GSAP, compilado con Vite. Se conecta a la API FastAPI de `/backend`:
no hay datos ni reglas simulados en el navegador. Los catálogos, permisos y acciones vienen de la base.

```bash
npm install
npm run dev      # http://localhost:5171 · /api se reenvía a http://localhost:8000 (VITE_PROXY para otro destino)
npm run build    # dist/ listo para S3 + CloudFront
```

```
src/app/          rutas y marco (navegación según permisos efectivos)
src/features/     auth · dashboard · tareas · objetos · documentos · red · capacitacion · auditoria · usuarios · asistente · profile · landing
src/shared/api    punto único de acceso a la API
src/shared/core   cliente HTTP, subida segura de evidencias (SHA-256 + limpieza EXIF), formatos
```
