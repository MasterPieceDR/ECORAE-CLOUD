# Índice de evidencias (enunciado 10.4 y 10.5)

Cada prueba se puede localizar desde esta tabla sin recorrer carpetas. Una captura sola no es un resultado: cada fila
indica el criterio de aceptación, dónde está la evidencia y el estado.

## Convenciones

- Una carpeta por caso de prueba: `evidence/CP-XX/`.
- Nombre de archivo: `CP-XX_AAAA-MM-DD_descripcion-corta.ext` (por ejemplo `CP-10_2026-12-02_rds-sin-acceso-publico.png`).
- Junto a cada captura, un `.md` corto con: entorno (local o AWS), versión (commit), configuración, pasos,
  resultado esperado, resultado obtenido y estado.
- Estados: **Definitivo** (prueba superada en el entorno final) · **Desarrollo** (superada en local o en una versión
  previa) · **Fallida corregida** (falló, se registró el defecto y se volvió a probar) · **Pendiente**.
- Antes de guardar: enmascarar contraseñas, tokens, claves, ARN de la cuenta y URL prefirmadas.

## Índice

| Caso | Prueba (10.1) | Criterio de aceptación | Evidencia | Estado |
|---|---|---|---|---|
| CP-01 | Acceso por rol | Permite o deniega según la matriz | `backend/tests/test_api.py` (casos de rol y RLS) · `evidence/CP-01/` (capturas en AWS) | Desarrollo (2026-11-23, API 33/33 en local) |
| CP-02 | Registro y lote | Persiste sin duplicados | `database/06_pruebas.sql` · `backend/tests/test_fase2.py` (serie duplicada → 409) | Desarrollo (2026-11-23, base 84/84) |
| CP-03 | Transición de estado | Solo transiciones permitidas | `database/06_pruebas.sql` · `backend/tests/test_api.py` | Desarrollo (2026-11-23) |
| CP-04 | Integridad referencial | Protege relaciones o aplica la política definida | `database/06_pruebas.sql` · `docs/resultados_pruebas.csv` | Desarrollo |
| CP-05 | Transacción | Rollback completo ante fallo | `database/06_pruebas.sql` · `database/07_concurrencia.sh` | Desarrollo |
| CP-06 | Optimización SQL | Plan o tiempo mejora y se justifica | `database/08_rendimiento.py` · `database/resultados_rendimiento.json` · `database/16_rendimiento.sql` | Desarrollo |
| CP-07 | Flujo máximo | Coincide con el cálculo manual | `math/flujo_maximo.py` · `math/resultados_flujo.json` | Desarrollo |
| CP-08 | Corte mínimo | Identifica aristas críticas | `math/resultados_flujo.json` (E1 y E3 con cortes) | Desarrollo |
| CP-09 | Integración matemática | Procesa datos de la red desde la base (RDS) | `backend/tests/test_api.py` (flujo leído de la base) · `evidence/CP-09/` | Desarrollo · Pendiente en RDS |
| CP-10 | Conectividad cloud | Comunicación autorizada; acceso directo restringido | `evidence/CP-10/` (ver guía, sección 4) | Pendiente |
| CP-11 | IAM | Tres usuarios sin credenciales en plantilla; InfraAdmins: nicolas; DBAdmins: diego; AppAdmins y Developers: eithan; Monitoring: los tres. Verificar PassRole solo al rol de despliegue, lectura del maestro por DBA y denegación al runtime, túnel y publicación por AppAdmins | `infrastructure/cloudformation/08-iam.yaml` · `infrastructure/iam/` · `evidence/CP-11/` | Desarrollo · Pendiente en AWS |
| SNS | Eventos de negocio | Cierre y transferencias generan eventos SNS con atributo `tipo`, JSON y correo legible; confirmar suscripción y entrega en AWS | `backend/tests/test_eventos.py` · confirmación de correo en AWS pendiente | Desarrollo |
| CP-12 | IaC | Recursos se recrean sin pasos ocultos | `infrastructure/cloudformation/` (validadas con `cfn-lint`: 0 errores, 0 advertencias, 2026-11-23) · `evidence/CP-12/` | Desarrollo · Pendiente en AWS |
| CP-13 | Trazabilidad | Historial ordenado y destino final verificable | `backend/tests/test_api.py` (ciclo completo) · `evidence/CP-13/` | Desarrollo · Pendiente en AWS |
| CP-14 | Monitorización | Log, métrica y alarma observables | `infrastructure/cloudformation/07-observabilidad.yaml` · `evidence/CP-14/` | Pendiente |
| CP-15 | Usabilidad e inclusión | Identifica barreras y aplica mejoras | `innovation/` · `evidence/CP-15/` | Pendiente |

Cómo repetir las pruebas locales (no requiere instalar PostgreSQL ni Python):

```
docker compose -f docker-compose.pruebas.yml run --rm pruebas        # API
docker compose -f docker-compose.pruebas.yml run --rm pruebas base   # base de datos
docker compose -f docker-compose.pruebas.yml down -v
```

## Defectos y decisiones registrados en la Fase 2

| Id | Hallazgo | Corrección | Prueba que lo cubre |
|---|---|---|---|
| D-01 | El modelo escrito a mano se perdía sin aviso si no coincidía con el catálogo | Columna `modelo_libre` y selector de catálogo por categoría (script 17) | `test_fase2.py::test_fase2_objetos_modelo_serie_y_fotos` |
| D-02 | El número de serie era único solo por marca y sin formato | Serie normalizada, con formato y única por ecosistema (script 17) | `test_fase2.py` (serie inválida 422, duplicada 409) |
| D-03 | CORS no permitía `DELETE` (anular equipos fallaba entre orígenes) | `allow_methods` con `DELETE` y `OPTIONS` | Revisión de código |
| D-04 | En modo S3 la verificación descargaba archivos de hasta 500 MB en la EC2 | Solo se descargan imágenes; el resto se verifica con `head_object` | `test_fase2.py::test_almacen_s3_verifica_contenido` |
| D-05 | El diagrama AWS de la Parte II tenía todo en una AZ y la EC2 sin salida | Rediseño en 2 AZ con NAT (ver `docs/aws/GUIA_DESPLIEGUE.md`) | CP-12 |
| D-06 | La proyección saltaba las semanas sin datos (distorsionaba la tendencia) | Serie semanal continua rellenada con 0 | `test_fase2.py` (huecos) |
| D-07 | Las semanas con datos reales y sintéticos se sumaban dos veces | El dato real tiene prioridad sobre el sintético | `test_fase2.py` (precedencia) |
| D-08 | El ALB aceptaba tráfico de cualquier IP y permitía saltarse CloudFront | Prefix list de CloudFront + cabecera secreta `X-Origin-Verify`; el resto recibe 403 | `cfn-lint` · CP-10 |
| D-09 | El user-data leía metadatos sin token, incompatible con IMDSv2 obligatorio | Token IMDSv2 antes de leer `instance-id` | `cfn-lint` · CP-12 |
| D-10 | Las 15 cuentas semilla (incluido el administrador) tenían la clave pública `EcoRAEE-2026`, publicada en un repositorio público; `DEMO=false` solo ocultaba el panel | Script 19 y `preparar-produccion`: cuentas sintéticas sin credencial en producción, administrador con clave aleatoria, usuario de sistema para procesos batch | `test_produccion.py` · [informe](../docs/informes/2026-11-23_produccion-local-y-credenciales.md) |
| D-11 | La proyección mezclaba el histórico de la red con los pocos registros de la plataforma (caída brusca, MAPE 55 %) y usaba la categoría raíz | Series separadas (`RED_HISTORICO` / `PLATAFORMA`), categorías de nivel 2; MAPE 4,2 % | `test_fase2.py`, `test_prediccion.py` |
| D-12 | El autorregistro activaba la cuenta sin comprobar que el correo existe | Verificación con código de 6 dígitos (hash bcrypt, 15 min, 5 intentos, reenvío limitado), Mailpit en local y SES en AWS | `test_verificacion_correo.py` · [informe](../docs/informes/2026-11-23_verificacion-correo.md) |
