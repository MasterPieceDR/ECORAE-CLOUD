# Informe: arquitectura para plan gratuito

Fecha: 2026-11-23 · Rama: `fase2-mejoras` · Sin commits ni despliegue en AWS.

## Cambios y archivos

- `infrastructure/cloudformation/01-red.yaml` y `parametros/{cuenta-propia,lab}.json`: NAT desactivado; la ruta privada solo existe bajo la condición NAT.
- `02-seguridad.yaml`: ingreso TCP 80 desde la prefix list CloudFront, base 5432 desde SG de aplicación, sin SSH ni SG de ALB; permiso acotado al secreto de origen.
- `03-datos.yaml`: se conservó íntegro el cambio previo de `DiasRespaldo`; RDS ya usa 20 GB gp3, Single-AZ por defecto y no habilita Performance Insights ni Enhanced Monitoring. La guía usa `DiasRespaldo=1`.
- `05-computo.yaml`: EC2 pública única, IMDSv2, volumen cifrado, perfil, arranque y logs conservados, secreto de origen, alarma de recuperación y salidas. `06-cdn.yaml`: DNS público como parámetro, HTTP y cabecera para API sin caché.
- `backend/app/config.py`, `backend/app/main.py`, `backend/tests/test_origen.py`: lectura del secreto por ARN, comparación constante, 403 para cabecera ausente o incorrecta y registro JSON de 500 inesperados; cuatro casos unitarios.
- `07-observabilidad.yaml`: seis alarmas con SNS, filtro de 5xx, panel de EC2, RDS, errores y latencia; CloudTrail y presupuesto conservados. La séptima alarma, de recuperación en 05, ejecuta la acción de recuperación EC2.
- `08-iam.yaml`: retirados permisos y roles vinculados exclusivos de ALB/ASG; Session Manager y despliegue conservados.
- `docs/adr/ADR-016-plan-gratuito.md`, `docs/aws/GUIA_DESPLIEGUE.md`, `docs/aws/costos.md`, `docs/aws/arquitectura.mmd`, `infrastructure/README.md`, `evidence/README.md`: arquitectura, despliegue, costos y evidencias CP-10/CP-14 y Trusted Advisor.

## Verificación ejecutada en serie

1. `docker compose -f docker-compose.pruebas.yml run --rm pruebas`: salida 0; **47 aprobadas**, 28 advertencias por longitud de clave JWT de pruebas.
2. `docker compose -f docker-compose.pruebas.yml run --rm pruebas base`: salida 0; **84 PASS**, ninguna fila de fallo.
3. `docker compose -f docker-compose.pruebas.yml down -v`: salida 0; contenedor, red y volumen de pruebas eliminados.
4. `docker run --rm -v "${PWD}/frontend:/web" -w /web node:22-alpine sh -c "npm ci --no-audit --no-fund && npm run build"`: salida 0; 1076 módulos, compilación Vite correcta.
5. `docker run --rm -v "${PWD}:/repo" -w /repo python:3.13-slim sh -c "pip install -q cfn-lint && cfn-lint infrastructure/cloudformation/*.yaml"`: primer intento salida 1 por dependencia redundante y propiedad EC2 no admitida; corregidas ambas. Repetición salida **0**, sin diagnósticos de cfn-lint.

Se repitieron API y base antes de esta secuencia tras ajustar el registro de excepciones. `docker ps --format "{{.Names}}"` no mostró contenedores activos al finalizar. Los comandos anteriores se ejecutaron en PowerShell; no fue necesario usar Git Bash ni conversión de rutas MSYS.

## Límites

No se ejecutó AWS CLI ni se crearon recursos; la validación real de despliegue, permisos, conectividad, correo SNS/SES, recuperación, panel, CloudTrail y Trusted Advisor requiere la cuenta. La IP pública y DNS pueden cambiar; el user-data actualizado no se reejecuta automáticamente y la guía explica recreación. CloudFront–EC2 usa HTTP sin cifrar y el valor de cabecera es visible para quien pueda consultar la configuración de la distribución; proteger estos permisos. No hay alta disponibilidad multi-instancia.

La cobertura gratuita depende de cuenta y uso. El diseño existente crea cuatro secretos propios de datos y uno maestro de RDS; el origen agrega un sexto. Secrets Manager, métricas personalizadas del agente, almacenamiento, solicitudes, snapshots, logs y otros excesos pueden facturarse. La alarma de recuperación actúa sobre EC2; las seis alarmas operativas del stack 07 notifican al tema de alarmas. La prueba de 5xx debe generar una respuesta registrada por la API, pues apagar el contenedor por sí solo no genera ese log.
