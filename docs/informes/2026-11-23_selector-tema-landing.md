# Selector de tema en landing y acceso

Fecha: 2026-11-23

## Archivos

- `frontend/src/shared/ui/ThemeSelect.jsx` y `ThemeSelect.css`: control compartido accesible, con opciones Claro, Oscuro y Sistema y estilos basados en tokens.
- `frontend/src/app/layouts/AppLayout.jsx` y `AppLayout.css`: reutilización del control y conservación del ajuste compacto en la barra de la aplicación.
- `frontend/src/features/landing/index.jsx` y `landing.css`: selector junto a las acciones de acceso, incluido en el menú móvil; el menú aparece antes para dejar espacio al nuevo control.
- `frontend/src/features/auth/LoginPage.jsx` y `auth.css`: selector en la esquina superior derecha de inicio de sesión y registro.

## Decisiones

El componente usa `aplicarTema` y la preferencia inicial de `document.documentElement.dataset.themePreference`, conservando la persistencia y seguimiento del sistema ya existentes en `theme.js`. El `label` accesible es «Tema». Los colores del control usan `--surface`, `--text` y `--line`; no se añadieron colores fijos. El selector móvil ocupa el ancho disponible en el menú.

## Verificación

Búsqueda: `rg -n -i '#[0-9a-f]{3,8}\b|rgba?\(' frontend/src -g '*.css' -g '*.jsx' -g '*.js' -g '!tokens.css'`. Resultado: sin coincidencias.

Compilación (código de salida 0):

```sh
docker run --rm -v C:/Users/diego/Desktop/EcoRAEE_Cloud/frontend:/web -w /web node:22-alpine sh -c 'npm ci --no-audit --no-fund && npm run build'
```

Salida real:

```text

added 38 packages in 37s
npm notice
npm notice New major version of npm available! 10.9.9 -> 12.2.3
npm notice Changelog: https://github.com/npm/cli/releases/tag/v12.2.3
npm notice To update run: npm install -g npm@12.2.3
npm notice

> ecoraee-frontend@3.0.0 build
> vite build

vite v8.3.5 building client environment for production...
transforming...
✓ 1076 modules transformed.
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
dist/assets/LoginPage-Qb4ksVUB.css                                       3.36 kB │ gzip:   1.17 kB
dist/assets/ContenidoCard-B6Pky6QR.css                                   4.04 kB │ gzip:   1.36 kB
dist/assets/dashboard-BzxHcvTN.css                                       4.72 kB │ gzip:   1.35 kB
dist/assets/objetos-B9cHnPXr.css                                         7.38 kB │ gzip:   1.96 kB
dist/assets/red-C5P48gH6.css                                             9.45 kB │ gzip:   2.45 kB
dist/assets/landing-CX4jk_aD.css                                        12.10 kB │ gzip:   3.09 kB
dist/assets/index-CnsWV4cS.css                                          26.22 kB │ gzip:   6.15 kB
dist/assets/EmptyState-3QW_20UV.js                                       0.31 kB │ gzip:   0.23 kB
dist/assets/Skeleton-Cb_qY_gV.js                                         0.32 kB │ gzip:   0.24 kB
dist/assets/StateBadge-BrtnV7Gj.js                                       0.35 kB │ gzip:   0.24 kB
dist/assets/useCinema-BJLxd1VU.js                                        0.40 kB │ gzip:   0.27 kB
dist/assets/useAsync-B0sBiLGr.js                                         0.49 kB │ gzip:   0.30 kB
dist/assets/StatusBadge-0G3VMKLW.js                                      0.61 kB │ gzip:   0.41 kB
dist/assets/PageHeader-nZAF4IYC.js                                       0.64 kB │ gzip:   0.35 kB
dist/assets/Modal-Bm2_Ec2w.js                                            0.72 kB │ gzip:   0.44 kB
dist/assets/ContenidoCard-BSGm_moO.js                                    1.07 kB │ gzip:   0.58 kB
dist/assets/formato-C4-daQth.js                                          2.03 kB │ gzip:   1.08 kB
dist/assets/tareas-ChVLwiax.js                                           2.23 kB │ gzip:   1.11 kB
dist/assets/story-Bt2Bptp8.js                                            3.18 kB │ gzip:   1.56 kB
dist/assets/objetos-IGrMDFuu.js                                          3.23 kB │ gzip:   1.33 kB
dist/assets/documentos-_f_yBZdY.js                                       3.26 kB │ gzip:   1.35 kB
dist/assets/profile-B0n77Iok.js                                          3.86 kB │ gzip:   1.61 kB
dist/assets/usuarios-nMArThAd.js                                         5.11 kB │ gzip:   1.85 kB
dist/assets/LoginPage-oXMTI1dR.js                                        6.09 kB │ gzip:   2.49 kB
dist/assets/catalogo-BxipvMUM.js                                         6.31 kB │ gzip:   2.29 kB
dist/assets/verificacion-CLQ7XxUx.js                                     6.80 kB │ gzip:   2.61 kB
dist/assets/api-DC82Tc27.js                                              6.80 kB │ gzip:   2.60 kB
dist/assets/Solicitudes-BDbp01PQ.js                                      7.02 kB │ gzip:   2.58 kB
dist/assets/auditoria-BV53vQlk.js                                        8.06 kB │ gzip:   2.84 kB
dist/assets/capacitacion-BzpXz4ji.js                                     8.23 kB │ gzip:   3.15 kB
dist/assets/jsx-runtime-Wy9s6hX0.js                                      8.91 kB │ gzip:   3.39 kB
dist/assets/asistente-CTUn5oF1.js                                        9.19 kB │ gzip:   3.27 kB
dist/assets/landing-vQqxt_bj.js                                          9.63 kB │ gzip:   2.96 kB
dist/assets/dashboard-MUpl6I4H.js                                       11.96 kB │ gzip:   4.19 kB
dist/assets/ObjetosPage-C6SLK5Yq.js                                     14.22 kB │ gzip:   4.54 kB
dist/assets/ObjetoPage-BXj5j5S8.js                                      32.21 kB │ gzip:   9.54 kB
dist/assets/red-D79WDlG1.js                                             58.36 kB │ gzip:  18.52 kB
dist/assets/chunk-6KYCQHYJ-7x9aaK7A.js                                  92.23 kB │ gzip:  30.50 kB
dist/assets/react-BGrmTCnT.js                                          131.64 kB │ gzip:  43.83 kB
dist/assets/zrender-C8dDVtEY.js                                        168.23 kB │ gzip:  55.21 kB
dist/assets/Chart-BEB_iNb6.js                                          350.72 kB │ gzip: 117.67 kB
dist/assets/index-CMFBJEu7.js                                          381.45 kB │ gzip: 128.89 kB

✓ built in 7.56s
[PLUGIN_TIMINGS] JavaScript callbacks ran for 3.7s of this 7.5s build (50%).
The slowest callbacks, timed inside each callback (the wait before a callback starts is excluded, the time it awaits is included):
  - plugin vite:prepare-out-dir renderStart (18%, 1.4s, 1 call)
Additional callback time came from the callbacks below and from callbacks under 1s.
1 callback is listed without a time. Its calls overlapped, so the time inside one call includes work from other calls. To find its cost, profile the build with `node --cpu-prof`:
  - plugin vite:css transform (19 calls)
See https://rolldown.rs/reference/InputOptions.checks#bundlertimings for more details.
```
