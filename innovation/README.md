# Innovación en la Sociedad

Carpeta del aporte de la asignatura Innovación en la Sociedad (enunciado 8.2 y 9.4). Debe contener el análisis del
equipo; aquí solo se deja la estructura y lo que el producto ya refleja de ese análisis, para que la matriz de
trazabilidad pueda enlazarlo (criterio 10: «el análisis social y ético produce al menos una modificación concreta»).

## Estructura

| Archivo o carpeta | Contenido esperado (9.4) | Requisito |
|---|---|---|
| `mapa_actores.md` | Actores e intereses, incluidos los poco visibles (recicladores de base, comunidades cercanas a los centros de disposición) | RF-IN-01 |
| `top_down_bottom_up.md` | Comparación de aproximaciones de innovación aplicables al escenario | RF-IN-02 |
| `matriz_riesgos.md` | Acceso, privacidad, poder, propiedad, exclusión y sostenibilidad, con controles | RF-IN-03, RNF-10 |
| `intervencion.md` | Intervención innovadora, indicadores sociales y ambientales, mecanismos de participación | RF-IN-04 |
| `escenario_futuro.md` | Escenario futuro y reflexión crítica | RF-IN-05 |
| `pitch/` | Resumen ejecutivo y pitch de cinco minutos en inglés | RF-IN-05 |

## Decisiones del producto que vienen del análisis ético (para la matriz de trazabilidad)

Estas decisiones están implementadas y se pueden citar como evidencia de que el análisis modificó el diseño:

| Riesgo identificado | Decisión en el producto | Dónde se ve |
|---|---|---|
| Fotos de equipos con ubicación GPS de hogares o instituciones | Las imágenes se limpian de EXIF/GPS en el navegador y la base rechaza las que llegan con metadatos (RNF-10) | `frontend/src/shared/core/http.js`, `api.fn_registrar_evidencia` |
| Datos personales que quedan en discos donados | El equipo con almacenamiento exige número de serie y un certificado de borrado antes de donarse (RN-09) | Script 17, `test_api.py` |
| Acceso indiscriminado a evidencias | Descarga solo con propósito declarado y bitácora de cada acceso (RN-07) | `api.fn_obtener_evidencia` |
| Conectividad limitada de algunos actores | Las imágenes se reducen antes de subirse y la subida muestra progreso (RNF-07) | `frontend/src/shared/core/http.js` |
| Uso de datos reales | Todos los datos son sintéticos, incluido el historial que usa el modelo de predicción | `database/12_datos_demo.sql`, `database/18_historial_recoleccion.sql` |
| Decisiones automáticas sin control humano | El asistente MCP no escribe sin confirmación humana (ADR-006) | `docs/adr/ADR-006.md` |
| Predicción tomada como certeza | El panel muestra la banda de confianza, el error (MAPE) y que el historial es sintético | Dashboard, `docs/adr/ADR-014.md` |
