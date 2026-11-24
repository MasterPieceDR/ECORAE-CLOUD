# Guion del video — EcoRAEE Cloud en AWS (Parte III)

Duración máxima: **5:00**. Participan los tres integrantes y cada uno explica su aporte. Grabar con la aplicación
desplegada y funcionando (enunciado: «no es suficiente mostrar capturas; se debe demostrar su funcionamiento»).

## Antes de grabar (10 minutos)

1. Consola de AWS en la cuenta del despliegue, región **Ohio (us-east-2)**. Pestañas abiertas en este orden:
   CloudFront · S3 · EC2 · RDS · IAM (Usuarios, Grupos, Roles) · SNS · CloudWatch (panel `ecoraee-prod`) · CloudTrail.
2. La aplicación abierta en el dominio de CloudFront (`https://<dominio>.cloudfront.net`), con la sesión cerrada.
3. Las claves de la app están en `Desktop\EcoRAEE_AWS_credenciales.txt` (no mostrarlo en pantalla).
4. Tener a mano una foto de un aparato (para subirla como evidencia) y el correo abierto para ver el aviso de SNS.
5. Ocultar números de cuenta, correos y claves si aparecen en pantalla.

## Reparto y tiempos

| Tiempo | Quién | Bloque | Qué se muestra |
|---|---|---|---|
| 0:00–0:40 | **Nicolás** (infraestructura) | Arquitectura | Diagrama `docs/aws/arquitectura.mmd` y CloudFormation con los 8 stacks |
| 0:40–2:10 | **Eithan** (aplicación) | Demostración funcional | La app en CloudFront: login, registrar, consultar, actualizar, subir foto, anular |
| 2:10–3:10 | **Diego** (base de datos) | Datos y archivos | RDS, migración, S3 evidencias, SNS |
| 3:10–4:10 | **Nicolás** | Seguridad | IAM, Security Groups, Secrets Manager |
| 4:10–4:50 | **Eithan** | Observabilidad | CloudWatch, CloudTrail, Budgets, Trusted Advisor |
| 4:50–5:00 | Los tres | Cierre | Costos y apagado |

## Texto sugerido

### 0:00 — Nicolás: arquitectura
> «Desplegamos EcoRAEE Cloud en AWS con infraestructura como código: ocho plantillas de CloudFormation crean la red,
> la seguridad, la base de datos, los buckets, el backend, la CDN, el monitoreo y la identidad. El usuario entra por
> CloudFront con HTTPS; el frontend vive en un bucket S3 privado, la API en una instancia EC2 y los datos en RDS
> PostgreSQL en una subred privada. Para quedarnos en el plan gratuito reemplazamos el balanceador y el NAT del diseño
> de la Parte II por una sola EC2 con recuperación automática detrás de CloudFront; lo justificamos en el ADR-016.
> Mi aporte fue la red, las plantillas y el despliegue.»

Mostrar: CloudFormation → lista de stacks en `CREATE_COMPLETE`/`UPDATE_COMPLETE`.

### 0:40 — Eithan: demostración funcional (punto 3 de la Parte 6)
> «Esta es la aplicación desplegada, servida desde CloudFront.»

1. Iniciar sesión con la cuenta de operador de evaluación.
2. **Registrar**: Equipos → nuevo equipo con categoría, modelo y número de serie → guardar.
3. **Consultar**: abrirlo en la lista y ver su ficha y línea de tiempo.
4. **Actualizar**: avanzar su estado (por ejemplo, recepción o evaluación).
5. **Subir evidencia**: adjuntar la foto → se ve en la galería (viene de S3 con URL temporal).
6. **Eliminar**: anular un equipo de prueba (borrado lógico con motivo, queda en la auditoría).
7. Abrir «Red» o el panel de predicción para mostrar que los cálculos leen de RDS.

> «Mi aporte fue el frontend, su publicación en S3 y CloudFront y la integración con la API.»

### 2:10 — Diego: base de datos, S3 y SNS (puntos 4, 5 y 8)
1. RDS → instancia PostgreSQL 16: **Acceso público: No**, cifrado activado, subred privada, grupo de seguridad que
   solo admite 5432 desde la EC2.
   > «Migramos la base local completa a RDS por un túnel de Session Manager a través de la EC2, sin abrir la base a
   > internet. Las contraseñas están en Secrets Manager; la API usa un usuario de servicio sin permisos de escritura
   > directa: todo pasa por funciones con reglas de negocio.»
2. En la app, botón «Ver en la base de datos» del equipo recién registrado (el dato está en RDS).
3. S3 → bucket de evidencias → la foto subida hace un momento. Pestaña Permisos: bloqueo público activado.
   Intentar abrir el objeto con su URL directa → `AccessDenied`.
4. **SNS**: en la app, registrar el cierre de trazabilidad o una transferencia → mostrar el correo «Trazabilidad
   cerrada» / «Transferencia enviada» que llega al buzón.
   > «SNS notifica los movimientos y el cierre de trazabilidad de los RAEE: es una funcionalidad real del sistema.»
> «Mi aporte fue la base de datos, la migración y la integración con S3 y SNS.»

### 3:10 — Nicolás: seguridad (Parte 5, punto 6)
1. IAM → **Grupos**: InfraAdmins, DBAdmins, AppAdmins, Developers y Monitoring, con sus usuarios.
2. Abrir un grupo: una política **administrada por AWS** (p. ej. `AmazonRDSReadOnlyAccess`) y una **administrada por
   el cliente** (`EcoRAEE-…Policy`).
3. IAM → **Roles**: el rol de la EC2 (solo sus dos buckets, sus secretos, SES y su tema SNS) y
   `EcoRAEE-CfnDeployRole` (CloudFormation despliega con él; los usuarios no tienen permisos directos).
4. EC2 → instancia → Security Group: solo puerto 80 desde la lista de CloudFront, **sin SSH** (Session Manager).
> «Ningún grupo tiene AdministratorAccess y no hay credenciales en el código: la EC2 usa su rol y Secrets Manager.»

### 4:10 — Eithan: observabilidad
1. CloudWatch → panel `ecoraee-prod`: CPU de EC2 y RDS, errores 5xx y latencia de la API; alarmas en `OK`.
2. CloudWatch Logs → logs JSON de la API (Logs Insights: `fields @timestamp, ruta, estado, ms`).
3. CloudTrail → historial de eventos (por ejemplo, la creación de los stacks).
4. Trusted Advisor → comprobaciones de seguridad gratuitas. Budgets → presupuesto de 30 USD.

### 4:50 — Los tres: cierre
> «Al terminar la evaluación borramos los stacks en orden inverso para no generar costos, como pide el enunciado.»

## Comprobación rápida antes de dar por buena la toma

- [ ] Duración ≤ 5:00 y hablaron los tres.
- [ ] Se vio registrar, consultar, actualizar y eliminar.
- [ ] Se vio la foto en la app y en S3, y el `AccessDenied` directo.
- [ ] Se vio RDS sin acceso público y el dato en la base.
- [ ] Se vieron usuarios, grupos, políticas (AWS y cliente) y roles.
- [ ] Llegó el correo de SNS.
- [ ] No aparecen claves, contraseñas ni el número de cuenta completo.
