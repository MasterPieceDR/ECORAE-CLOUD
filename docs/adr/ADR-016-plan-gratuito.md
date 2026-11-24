# ADR-016: arquitectura de bajo costo para el plan gratuito

Fecha: 2026-11-23 · Estado: aceptada para despliegue pendiente de validación

## Contexto

Se requieren frontend privado, API, base privada, IAM, eventos y observabilidad con gasto mínimo. NAT Gateway y ALB tienen costos fijos, independientemente del tráfico.

## Decisión

Una EC2 pública con IMDSv2 y sin SSH recibe solo TCP 80 desde la prefix list administrada de CloudFront; la API exige además `X-Origin-Verify` con secreto en Secrets Manager. CloudFront sirve S3 mediante OAC y reenvía `/api/*` sin caché a EC2 por HTTP. RDS permanece privado con TLS. Se usa una alarma de recuperación automática de EC2 y alarmas de aplicación y base. NAT y endpoints de interfaz quedan desactivados; S3 mantiene endpoint gateway.

## Alternativas

- ALB + ASG + NAT: mejor capacidad y disponibilidad, pero costos fijos.
- EC2 privada con endpoints de interfaz: evita NAT para servicios compatibles, pero cada endpoint cuesta y no proporciona salida general para descargar paquetes y CA.

## Consecuencias

No hay alta disponibilidad multi-instancia; la recuperación automática no detecta todos los fallos de aplicación. El tramo CloudFront–EC2 no está cifrado. DNS público puede cambiar y requiere actualizar CDN. El secreto del origen añade un secreto facturable, además de los ya presentes; verificar elegibilidad, cuotas y costos reales. La protección de cabecera no reemplaza TLS. Las métricas personalizadas, logs y retención pueden generar cargos.
