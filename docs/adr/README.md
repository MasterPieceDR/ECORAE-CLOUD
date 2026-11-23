# Registro de decisiones de arquitectura (ADR)

Formato: contexto, decisión, alternativas consideradas y consecuencias. Los ADR 003 a 011 se tomaron en las partes
I y II (se citan en el README y en el código) y se dejan aquí por escrito; los ADR 012 a 015 son del Proyecto Integrador III.

| ADR | Decisión | Estado |
|---|---|---|
| [003](ADR-003.md) | Los catálogos y estados se leen de la base; el frontend no los escribe a mano | Aceptada |
| [005](ADR-005.md) | Las reglas de negocio viven en PostgreSQL; la API es delgada | Aceptada |
| [006](ADR-006.md) | Asistente MCP con un solo ejecutor, bitácora y confirmación humana | Aceptada |
| [010](ADR-010.md) | Red de flujo con la capacidad del laboratorio como nodo dividido y cinco escenarios | Aceptada |
| [011](ADR-011.md) | Capacitación en un esquema propio (`edu`) con auditoría y RLS | Aceptada |
| [012](ADR-012.md) | Catálogo de modelos por categoría con ventana de edición de 24 horas | Aceptada |
| [013](ADR-013.md) | Almacén de archivos desacoplado (local / S3) con URL prefirmadas | Aceptada |
| [014](ADR-014.md) | Proyección de recolección con Holt en un módulo aislado | Aceptada |
| [015](ADR-015.md) | Despliegue en EC2 con Auto Scaling, RDS y CloudFront mediante CloudFormation | Aceptada |
