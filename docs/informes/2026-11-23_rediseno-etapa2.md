# Rediseño visual — etapa 2

## Archivos modificados

- `frontend/src/features/dashboard/index.jsx`
- `frontend/src/features/dashboard/dashboard.css`
- `frontend/src/features/tareas/index.jsx`
- `frontend/src/features/tareas/tareas.css`
- `frontend/src/features/objetos/ObjetosPage.jsx`
- `frontend/src/features/objetos/ObjetoPage.jsx`
- `frontend/src/features/objetos/RegistrarDialog.jsx`
- `frontend/src/features/objetos/AccionDialog.jsx`
- `frontend/src/features/objetos/objetos.css`
- `frontend/src/features/catalogo/index.jsx`
- `frontend/src/features/catalogo/catalogo.css`
- `frontend/src/shared/ui/Field.jsx`
- `frontend/src/shared/ui/StatusBadge.jsx`
- `frontend/src/shared/core/icons.js`

Se creó también este informe.

## Decisiones por vista

- Inicio: saludo sobrio, tareas prioritarias, indicadores, gráficos de estado y clasificación en columnas adaptables, proyección a ancho completo y movimientos compactos. Se retiraron las fotografías decorativas de los bloques operativos.
- Mis tareas: grupos por acción, acceso directo a la acción disponible y estado vacío compartido. La ficha comprueba la lista de acciones de la API antes de abrir el diálogo.
- Equipos y lotes: cabecera, filtros visibles, chips removibles, limpieza y estado vacío; se conserva la tabla que se transforma en tarjetas en móvil.
- Ficha: migas, insignias y acciones en cabecera; pestañas de resumen, línea de tiempo, fotos y evidencias/documentos. La línea muestra hora de Ecuador; se conserva el acceso a la base de datos.
- Diálogos: secciones en registro, ayuda y validación en línea en campos adaptados, pie de acciones adherido y confirmación adicional para anular. Las validaciones y permisos del servidor siguen vigentes.
- Catálogo: miniaturas mediante el endpoint existente, alternativa con icono, filtros de categoría y marca, insignia con reloj o candado y tiempo restante.

## Compilación real

Comando: `docker run --rm -v "C:/Users/diego/Desktop/EcoRAEE_Cloud/frontend:/web" -w /web node:22-alpine sh -c "npm ci --no-audit --no-fund && npm run build"`.

Código de salida: 0. Salida combinada:

```text

added 38 packages in 18s
npm notice
npm notice New major version of npm available! 10.9.9 -> 12.2.3
npm notice Changelog: https://github.com/npm/cli/releases/tag/v12.2.3
npm notice To update run: npm install -g npm@12.2.3
npm notice

> ecoraee-frontend@3.0.0 build
> vite build

vite v8.3.5 building client environment for production...
transforming...
✓ 1073 modules transformed.
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
dist/assets/catalogo-ux4oDtz8.css                                        0.89 kB │ gzip:   0.44 kB
dist/assets/tareas-wV6YMIdj.css                                          1.34 kB │ gzip:   0.55 kB
dist/assets/profile-Bb1801S2.css                                         1.98 kB │ gzip:   0.84 kB
dist/assets/verificacion-CbMuKslZ.css                                    2.70 kB │ gzip:   0.86 kB
dist/assets/asistente-CWsTrPHI.css                                       3.03 kB │ gzip:   0.98 kB
dist/assets/LoginPage-CkwWpgqK.css                                       3.26 kB │ gzip:   1.13 kB
dist/assets/ContenidoCard-B6Pky6QR.css                                   4.04 kB │ gzip:   1.36 kB
dist/assets/dashboard-BzxHcvTN.css                                       4.72 kB │ gzip:   1.35 kB
dist/assets/objetos-BMofOpgT.css                                         7.15 kB │ gzip:   1.90 kB
dist/assets/red-C5P48gH6.css                                             9.45 kB │ gzip:   2.45 kB
dist/assets/landing-BQvPl-Vb.css                                        12.02 kB │ gzip:   3.07 kB
dist/assets/index-M_hYuF3O.css                                          26.02 kB │ gzip:   6.11 kB
dist/assets/EmptyState-C3iSpLsN.js                                       0.31 kB │ gzip:   0.23 kB
dist/assets/Skeleton-Cb_qY_gV.js                                         0.32 kB │ gzip:   0.24 kB
dist/assets/StateBadge-gNlOZkVn.js                                       0.35 kB │ gzip:   0.24 kB
dist/assets/useCinema-CXPmuX6o.js                                        0.40 kB │ gzip:   0.27 kB
dist/assets/useAsync-B0sBiLGr.js                                         0.49 kB │ gzip:   0.30 kB
dist/assets/StatusBadge-C5DJrmfp.js                                      0.61 kB │ gzip:   0.41 kB
dist/assets/PageHeader-nZAF4IYC.js                                       0.64 kB │ gzip:   0.35 kB
dist/assets/Modal-hI41Mytt.js                                            0.72 kB │ gzip:   0.43 kB
dist/assets/ContenidoCard-CO5mFTpk.js                                    1.05 kB │ gzip:   0.56 kB
dist/assets/formato-C4-daQth.js                                          2.03 kB │ gzip:   1.08 kB
dist/assets/tareas-BriGAH0J.js                                           2.21 kB │ gzip:   1.09 kB
dist/assets/objetos-DPWjCMu3.js                                          3.23 kB │ gzip:   1.33 kB
dist/assets/documentos-DlICvPwg.js                                       3.31 kB │ gzip:   1.31 kB
dist/assets/profile-DMzDz_E3.js                                          4.12 kB │ gzip:   1.65 kB
dist/assets/usuarios-4Gec3QyJ.js                                         5.21 kB │ gzip:   1.86 kB
dist/assets/LoginPage-Cbp-dTos.js                                        5.59 kB │ gzip:   2.29 kB
dist/assets/catalogo-C40flJX1.js                                         6.79 kB │ gzip:   2.37 kB
dist/assets/api-DC82Tc27.js                                              6.80 kB │ gzip:   2.60 kB
dist/assets/verificacion-C1GMffsg.js                                     6.85 kB │ gzip:   2.60 kB
dist/assets/Solicitudes-CAipdEEu.js                                      6.93 kB │ gzip:   2.55 kB
dist/assets/auditoria-YCj5ZOsv.js                                        8.07 kB │ gzip:   2.77 kB
dist/assets/capacitacion-JwdOhGif.js                                     8.32 kB │ gzip:   3.12 kB
dist/assets/jsx-runtime-Wy9s6hX0.js                                      8.91 kB │ gzip:   3.39 kB
dist/assets/asistente-Ihn5VDQx.js                                        9.01 kB │ gzip:   3.20 kB
dist/assets/landing-C8ntWJhm.js                                          9.48 kB │ gzip:   2.92 kB
dist/assets/dashboard-D5iQJ9mX.js                                       11.93 kB │ gzip:   4.18 kB
dist/assets/ObjetosPage-6uOj771u.js                                     14.69 kB │ gzip:   4.60 kB
dist/assets/ObjetoPage-GMxlNlNN.js                                      32.21 kB │ gzip:   9.54 kB
dist/assets/red-qXrX1ywT.js                                             58.42 kB │ gzip:  18.52 kB
dist/assets/chunk-6KYCQHYJ-7x9aaK7A.js                                  92.23 kB │ gzip:  30.50 kB
dist/assets/react-BGrmTCnT.js                                          131.64 kB │ gzip:  43.83 kB
dist/assets/zrender-C8dDVtEY.js                                        168.23 kB │ gzip:  55.21 kB
dist/assets/Chart-BEB_iNb6.js                                          350.72 kB │ gzip: 117.67 kB
dist/assets/index-DFc5M9dx.js                                          384.97 kB │ gzip: 130.57 kB

✓ built in 3.40s
[PLUGIN_TIMINGS] JavaScript callbacks ran for 1.7s of this 3.4s build (50%).
1 callback is listed without a time. Its calls overlapped, so the time inside one call includes work from other calls. To find its cost, profile the build with `node --cpu-prof`:
  - plugin vite:css transform (18 calls)
See https://rolldown.rs/reference/InputOptions.checks#bundlertimings for more details.


```

## Búsqueda de colores real

```sh
grep -rnE "#[0-9a-fA-F]{3,8}\b|rgba?\(" frontend/src --include=*.css --include=*.jsx --include=*.js | grep -v tokens.css
```

Código de salida: 1 (el último grep devuelve 1 al no encontrar coincidencias). Salida:

```text
```

## Pendientes y límites

- La API de objetos no admite categoría y limita cada consulta a 500 resultados. El filtro se aplica en el cliente sobre esos resultados, por lo que no cubre registros posteriores al límite.
- No se realizó revisión visual, de teclado o contraste en navegador con datos reales, en ambos temas y a todos los anchos solicitados.
- Las acciones conservan algunos campos y validaciones nativos existentes; la conversión a Field y ayuda en línea no cubre todos los controles complejos ni asigna a campos concretos los errores generales de la API.
- Queda la etapa 3 para las demás vistas de la especificación. No se modificaron backend ni contratos; no se ejecutaron pruebas de API.
