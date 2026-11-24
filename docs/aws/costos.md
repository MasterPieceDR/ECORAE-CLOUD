# Costos y plan gratuito

Región objetivo `us-east-2`. La elegibilidad y cuotas del plan gratuito dependen de la fecha y tipo de cuenta; confirme en la consola de facturación y [AWS Free Tier](https://aws.amazon.com/free/). Estos valores son objetivos de uso, no una garantía de costo cero.

| Servicio | Configuración y límite a vigilar |
|---|---|
| EC2 | Una t3.small o t3.micro, hasta 750 h si la oferta de la cuenta aplica; recuperación automática mediante alarma |
| EBS | gp3 20 GB cifrados; comprobar cuota gratuita y snapshots |
| IPv4 | Una IP pública en uso; comprobar si la cuenta tiene cobertura gratuita |
| RDS | db.t4g.micro PostgreSQL, 20 GB gp3, Single-AZ, respaldos 1 día; comprobar horas, almacenamiento y snapshots |
| S3 | Frontend, evidencias, contenidos, artefactos y auditoría; vigilar capacidad, solicitudes, versiones y transferencia |
| CloudFront | Tráfico y solicitudes dentro de la oferta aplicable |
| Secrets Manager | Seis secretos en el diseño: maestro administrado por RDS, API, MCP, servicios compuesto, JWT y origen; tras la prueba se facturan por secreto y solicitudes. A 0,40 USD por secreto/mes serían unos 2,40 USD/mes, sujeto a precios regionales y ciclo de vida |
| CloudWatch | Siete alarmas en total incluida recuperación; un panel; vigilar logs y métricas personalizadas del agente, que pueden generar cargos |
| CloudTrail | Un trail de eventos de administración; S3 y retención pueden costar |
| SNS / SES / Budgets | Vigilar notificaciones, correo en sandbox y límites de presupuestos |

No se crean NAT Gateway, ALB ni ASG por defecto. La retención de snapshots y buckets puede seguir facturando después del borrado. Un presupuesto avisa y no detiene recursos. Consulte precios vigentes y Cost Explorer antes de desplegar; la estimación depende de consumo y elegibilidad.
