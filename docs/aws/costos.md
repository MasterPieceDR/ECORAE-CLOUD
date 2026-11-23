# Estimación de costos mensuales (RNF-08)

Región `us-east-1`, 730 horas al mes, precios públicos bajo demanda de referencia (verificar en el
[AWS Pricing Calculator](https://calculator.aws/) antes de entregar: los precios cambian y AWS Academy otorga créditos).
No incluye impuestos.

## Escenario de laboratorio (parámetros de `infrastructure/cloudformation/parametros/lab.json`)

| Servicio | Configuración | Cálculo aproximado | USD/mes |
|---|---|---|---|
| EC2 | 1 × t3.small (ASG mínimo 1) | 0,0208 × 730 | 15,2 |
| EBS | 20 GB gp3 cifrado | 20 × 0,08 | 1,6 |
| RDS PostgreSQL | db.t4g.micro Single-AZ | 0,016 × 730 | 11,7 |
| RDS almacenamiento | 20 GB gp3 + backups 7 días (dentro del tamaño de la base) | 20 × 0,115 | 2,3 |
| Application Load Balancer | 1 ALB + pocas LCU | 0,0225 × 730 + ~2 | 18,4 |
| NAT Gateway | 1 NAT + ~5 GB procesados | 0,045 × 730 + 5 × 0,045 | 33,1 |
| IPv4 públicas | IP elástica del NAT + 2 del ALB | 3 × 0,005 × 730 | 11,0 |
| Secrets Manager | 4 secretos propios + 1 gestionado por RDS | 5 × 0,40 | 2,0 |
| S3 | < 5 GB entre frontend, evidencias, contenidos y auditoría | — | < 1 |
| CloudFront | Dentro de la capa gratuita (1 TB y 10 M solicitudes al mes) | — | 0 |
| CloudWatch | Logs (< 5 GB, retención limitada) + 6 alarmas + métricas del agente | 6 × 0,10 + logs | 2–4 |
| CloudTrail | Un trail de eventos de administración (el primero es gratuito; solo S3) | — | < 1 |
| AWS Budgets | Un presupuesto (los dos primeros son gratuitos) | — | 0 |
| **Total aproximado** | | | **≈ 100 USD/mes** |

Lectura: **un tercio del costo es el NAT Gateway** y otro sexto las IPv4 públicas; el cómputo y la base son lo más barato.

## Escenario de alta disponibilidad (diseño, RNF-02)

| Cambio | USD/mes adicional |
|---|---|
| RDS Multi-AZ (`MultiAZ=true`) | +14 (la instancia se duplica) |
| ASG con 2 instancias permanentes | +17 |
| Un NAT por AZ | +33 |
| **Total aproximado** | **≈ 165 USD/mes** |

## Decisiones de optimización

1. **Apagar fuera de la evaluación.** Poner el ASG en `DesiredCapacity=0` y detener RDS (máximo 7 días seguidos)
   ahorra unos 30 USD/mes, pero el NAT, el ALB y las IPv4 siguen facturando: si el laboratorio queda sin uso varios
   días, conviene **borrar los stacks** (RDS deja un snapshot final) y recrearlos con CloudFormation (CP-12).
2. **Endpoints de interfaz frente a NAT.** Cada endpoint de interfaz cuesta unos 7,3 USD/mes por AZ; con 5 servicios
   en 2 AZ serían unos 73 USD, más caro que un NAT. Por eso quedan desactivados (`CrearEndpoints=false`) y solo se
   usa el endpoint **gateway** de S3, que es gratuito y además evita pagar el NAT por el tráfico hacia S3.
3. **Tamaños pequeños con instancias Graviton** donde se puede (`db.t4g.micro`).
4. **Retención de logs limitada** y ciclo de vida en los buckets (versiones antiguas a almacenamiento más barato y
   expiración).
5. **Etiquetas obligatorias** `Proyecto`, `Entorno` y `Responsable` en todos los recursos para filtrar el costo en
   Cost Explorer.
6. **Presupuesto con alerta al 80 %** por correo (stack `observabilidad`). Avisa, no detiene.

## Costo por escenario de uso (métrica del enunciado 10.2)

Con la capacidad de la red en el escenario base E0 (flujo máximo de 200 equipos por semana, unos 870 al mes), el costo
del laboratorio es de unos **0,12 USD por equipo trazado**. El costo es casi fijo: duplicar el volumen apenas cambia el total, porque los
componentes dominantes (NAT, ALB, IPv4) no dependen del tráfico a esta escala.
