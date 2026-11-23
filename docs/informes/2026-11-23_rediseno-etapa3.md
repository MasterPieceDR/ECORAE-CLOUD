# Rediseño visual — etapa 3

## Archivos modificados

- `frontend/src/app/layouts/AppLayout.jsx`
- `frontend/src/features/asistente/index.jsx`
- `frontend/src/features/auditoria/index.jsx`
- `frontend/src/features/auth/LoginPage.jsx`
- `frontend/src/features/capacitacion/index.jsx`
- `frontend/src/features/catalogo/catalogo.css`
- `frontend/src/features/catalogo/index.jsx`
- `frontend/src/features/dashboard/index.jsx`
- `frontend/src/features/documentos/index.jsx`
- `frontend/src/features/landing/index.jsx`
- `frontend/src/features/objetos/ObjetosPage.jsx`
- `frontend/src/features/objetos/objetos.css`
- `frontend/src/features/profile/index.jsx`
- `frontend/src/features/red/FlowGraph.jsx`
- `frontend/src/features/red/index.jsx`
- `frontend/src/features/tareas/index.jsx`
- `frontend/src/features/usuarios/Solicitudes.jsx`
- `frontend/src/features/usuarios/index.jsx`
- `frontend/src/features/verificacion/index.jsx`
- `frontend/src/shared/styles/base.css`

Se creó también este informe. No se modificó backend ni se hicieron commits.

## Correcciones de la parte A

1. Equipos y lotes: la tabla tiene desplazamiento propio, anchura mínima contenida y columnas prioritarias; a 900 px o menos usa tarjetas. Ubicación incluye el último movimiento.
2. La tarea pendiente usa `StatusBadge` con los tokens semánticos de advertencia y un icono.
3. Los filtros tienen etiquetas visibles, búsqueda en una fila completa y una rejilla adaptable con mínimo de 190 px cuando cabe.
4. Se eliminó la fotografía de fondo global del área de aplicación y se dio a `PageHeader` una superficie y borde de la paleta. Perfil también dejó de usar la foto como fondo del título.
5. Inicio presenta primero los indicadores y gráficos; la bandeja compacta muestra hasta cuatro grupos y dos objetos por grupo, con enlace a todas las tareas y cantidad.
6. Catálogo usa tarjetas con imagen, modelo, marca, categoría, estado y acciones: cuatro columnas amplias, tres intermedias, dos en pantallas menores y una en móvil.

## Decisiones por vista

- Acceso y registro: se conserva la composición de dos columnas y la imagen existente; se añadió `Stepper` en datos y verificación, y las cuentas demo se muestran en un panel plegable solo cuando la API indica que están habilitadas. Los mensajes y el reenvío permanecen activos.
- Landing: accesos visibles a ingresar y crear cuenta, este último abre directamente el registro; se conserva el lenguaje visual con tokens.
- Red: `PageHeader`, aristas saturadas con `--danger` y corte resaltado con la leyenda existente.
- Capacitación, Documentos, Base de datos, Usuarios y Auditoría: cabeceras compartidas; documentos y auditoría incluyen estados vacíos compartidos y tablas con desplazamiento propio.
- Solicitudes y Asistente: estados vacíos compartidos; el asistente conserva su cabecera de diálogo y sus controles.
- Perfil: cabecera compartida con avatar, organización y fecha; se conservan roles, solicitudes y pestañas.

## Compilación real

Comando: `docker run --rm -v C:/Users/diego/Desktop/EcoRAEE_Cloud/frontend:/web -w /web node:22-alpine sh -c 'npm ci --no-audit --no-fund && npm run build'`.

Código de salida: 0. Salida combinada:

```text
added 38 packages in 24s
npm notice
npm notice New major version of npm available! 10.9.9 -> 12.2.3
npm notice Changelog: https://github.com/npm/cli/releases/tag/v12.2.3
npm notice To update run: npm install -g npm@12.2.3
npm notice

> ecoraee-frontend@3.0.0 build
> vite build

vite v8.3.5 building client environment for production...
transforming...
✓ 1074 modules transformed.
rendering chunks...
computing gzip size...
dist/index.html                                                          1.13 kB │ gzip:   0.51 kB
dist/assets/bricolage-grotesque-vietnamese-wght-normal-BUzh504Q.woff2    8.60 kB
dist/assets/instrument-serif-latin-ext-400-italic-D7-lnxEk.woff         10.50 kB
dist/assets/instrument-serif-latin-ext-400-italic-C9HzH3YL.woff2        12.38 kB
dist/assets/bricolage-grotesque-latin-ext-wght-normal-CcLUaPy7.woff2    18.66 kB
dist/assets/instrument-serif-latin-400-italic-u__WvvIK.woff             19.26 kB
dist/assets/instrument-serif-latin-400-italic-DKMiL14s.woff2            22.12 kB
dist/assets/bricolage-grotesque-latin-wght-normal-DLoelf7F.woff2        41.34 kB
dist/assets/Solicitudes-DnL-1oqj.css                                     0.62 kB │ gzip:   0.33 kB
dist/assets/catalogo-DJemqNOQ.css                                        0.94 kB │ gzip:   0.39 kB
dist/assets/tareas-wV6YMIdj.css                                          1.34 kB │ gzip:   0.55 kB
dist/assets/profile-Bb1801S2.css                                         1.98 kB │ gzip:   0.84 kB
dist/assets/verificacion-CbMuKslZ.css                                    2.70 kB │ gzip:   0.86 kB
dist/assets/asistente-CWsTrPHI.css                                       3.03 kB │ gzip:   0.98 kB
dist/assets/LoginPage-CkwWpgqK.css                                       3.26 kB │ gzip:   1.13 kB
dist/assets/ContenidoCard-B6Pky6QR.css                                   4.04 kB │ gzip:   1.36 kB
dist/assets/dashboard-BzxHcvTN.css                                       4.72 kB │ gzip:   1.35 kB
dist/assets/objetos-B9cHnPXr.css                                         7.38 kB │ gzip:   1.96 kB
dist/assets/red-C5P48gH6.css                                             9.45 kB │ gzip:   2.45 kB
dist/assets/landing-BQvPl-Vb.css                                        12.02 kB │ gzip:   3.07 kB
dist/assets/index-JN33kZOo.css                                          26.19 kB │ gzip:   6.14 kB
dist/assets/EmptyState-Cx9tQxvo.js                                       0.31 kB │ gzip:   0.23 kB
dist/assets/Skeleton-Cb_qY_gV.js                                         0.32 kB │ gzip:   0.24 kB
dist/assets/StateBadge-CmriFlMb.js                                       0.35 kB │ gzip:   0.24 kB
dist/assets/useCinema-B02eY28l.js                                        0.40 kB │ gzip:   0.28 kB
dist/assets/useAsync-B0sBiLGr.js                                         0.49 kB │ gzip:   0.30 kB
dist/assets/StatusBadge-nRmbnhYO.js                                      0.61 kB │ gzip:   0.41 kB
dist/assets/PageHeader-nZAF4IYC.js                                       0.64 kB │ gzip:   0.35 kB
dist/assets/Modal-frPNELaq.js                                            0.72 kB │ gzip:   0.44 kB
dist/assets/ContenidoCard-DHL_TL5S.js                                    1.07 kB │ gzip:   0.58 kB
dist/assets/formato-C4-daQth.js                                          2.03 kB │ gzip:   1.08 kB
dist/assets/tareas-DZyBpm0R.js                                           2.23 kB │ gzip:   1.10 kB
dist/assets/story-Bt2Bptp8.js                                            3.18 kB │ gzip:   1.56 kB
dist/assets/objetos-Dzz56Ygn.js                                          3.23 kB │ gzip:   1.33 kB
dist/assets/documentos-mM4qMpX0.js                                       3.26 kB │ gzip:   1.35 kB
dist/assets/profile-CUnSnnig.js                                          3.86 kB │ gzip:   1.61 kB
dist/assets/usuarios-DDigVDDE.js                                         5.11 kB │ gzip:   1.84 kB
dist/assets/LoginPage-DOgR3S9U.js                                        6.01 kB │ gzip:   2.47 kB
dist/assets/catalogo-6SWd01tL.js                                         6.31 kB │ gzip:   2.28 kB
dist/assets/verificacion-vlY6hou0.js                                     6.80 kB │ gzip:   2.61 kB
dist/assets/api-DC82Tc27.js                                              6.80 kB │ gzip:   2.60 kB
dist/assets/Solicitudes-Dlpfuh6N.js                                      7.02 kB │ gzip:   2.58 kB
dist/assets/auditoria-C3cJWzA_.js                                        8.06 kB │ gzip:   2.84 kB
dist/assets/capacitacion-DPbYPXNl.js                                     8.23 kB │ gzip:   3.15 kB
dist/assets/jsx-runtime-Wy9s6hX0.js                                      8.91 kB │ gzip:   3.39 kB
dist/assets/asistente-Cl72BI1g.js                                        9.19 kB │ gzip:   3.27 kB
dist/assets/landing-DQpHeT6M.js                                          9.61 kB │ gzip:   2.95 kB
dist/assets/dashboard-DPEw-l7m.js                                       11.96 kB │ gzip:   4.19 kB
dist/assets/ObjetosPage-DKkSgtzh.js                                     14.22 kB │ gzip:   4.54 kB
dist/assets/ObjetoPage-C2V9Tut6.js                                      32.21 kB │ gzip:   9.54 kB
dist/assets/red-KFvLNTt6.js                                             58.36 kB │ gzip:  18.52 kB
dist/assets/chunk-6KYCQHYJ-7x9aaK7A.js                                  92.23 kB │ gzip:  30.50 kB
dist/assets/react-BGrmTCnT.js                                          131.64 kB │ gzip:  43.83 kB
dist/assets/zrender-C8dDVtEY.js                                        168.23 kB │ gzip:  55.21 kB
dist/assets/Chart-BEB_iNb6.js                                          350.72 kB │ gzip: 117.67 kB
dist/assets/index-ClqIKNw6.js                                          381.42 kB │ gzip: 128.88 kB

✓ built in 5.62s
[PLUGIN_TIMINGS] JavaScript callbacks ran for 3.0s of this 5.6s build (55%).
1 callback is listed without a time. Its calls overlapped, so the time inside one call includes work from other calls. To find its cost, profile the build with `node --cpu-prof`:
  - plugin vite:css transform (18 calls)
See https://rolldown.rs/reference/InputOptions.checks#bundlertimings for more details.
```

## Búsqueda de colores real

```text
grep -rnE '#[[:xdigit:]]{6}|rgb[(]' frontend/src --include='*.css' --include='*.jsx' --include='*.js' --exclude='tokens.css'
```

Salida: vacía. Código de salida: 1 (sin coincidencias). Una búsqueda adicional con `rg` para hexadecimales de 3 a 8 dígitos y `rgb`/`rgba` tampoco encontró coincidencias.

## Pendientes y límites

- No se realizó revisión visual en navegador, medición de `scrollWidth` ni auditoría de teclado y contraste en todos los anchos y ambos temas. Los cambios responsive requieren esa validación con datos reales; no se afirma conformidad integral de WCAG ni ausencia de desbordamiento en todas las vistas.
- Se conservan algunos controles nativos y estilos anteriores en las vistas restantes; no se ha convertido cada campo o insignia heredada a un componente compartido.
- No se ejecutaron las pruebas de API: no se modificó el backend.
