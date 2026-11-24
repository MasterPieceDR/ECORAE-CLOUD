# Correcciones previas al despliegue AWS — 2026-11-23

## Estado

Trabajo **incompleto**: no desplegar con esta guía hasta terminar y revisar IAM (tarea B), completar la documentación de cuenta propia (D) y verificar los límites indicados abajo. No se ejecutó el CLI de AWS, no se crearon recursos en AWS y no se hicieron commits.

## Cambios por tarea y archivos

- **A, parcial:** `backend/app/eventos.py` y `backend/app/rutas/documentos.py` programan publicaciones tras terminar la transacción, con asunto y atributo `tipo`, tolerando fallos y sin publicar si falta el ARN. `backend/tests/test_eventos.py` cubre los tres endpoints y el publicador con mocks. `infrastructure/cloudformation/02-seguridad.yaml` crea el tema de negocio cifrado, suscripción y permiso de publicación en el rol propio; `05-computo.yaml` inyecta el ARN. `.env.aws.example` y `docker-compose.aws.yml` documentan su configuración. En Academy los permisos de LabRole siguen siendo externos a la plantilla. Falta comprobar en AWS la suscripción, entrega y contenido, y ampliar datos de ecosistema de recepción y cierre.
- **B, pendiente:** no se creó `08-iam.yaml` ni se actualizaron los documentos IAM. Los usuarios, grupos y rol de despliegue no existen por efecto de este trabajo. No se ha validado el mínimo privilegio ni el despliegue con `--role-arn`.
- **C, parcial:** `infrastructure/scripts/migrar_base.sh` incluye el script 20 y permite `--datos` sobre una base vacía mediante volcado completo, que restaura los datos antes de restricciones y triggers; crea roles de grupo y logins y prepara producción. La fuente debe incluir los scripts 19 y 20. `PGPORT_LOCAL` y `PGHOSTADDR` permiten un túnel manteniendo el nombre TLS. `infrastructure/README.md` describe el túnel y CA. La lista de scripts aún está duplicada respecto a `rebuild.sh`. El flujo y TLS reales con RDS siguen sin comprobarse. La restauración solo comprueba la versión de la fuente después de restaurar; ante una fuente antigua se debe descartar la base destino.
- **D, parcial:** `infrastructure/cloudformation/parametros/cuenta-propia.json` incorpora los valores solicitados; `02-seguridad.yaml` exige la prefix list sin valor regional fijo; `05-computo.yaml` resuelve la AMI mediante SSM. `infrastructure/README.md`, `docs/aws/GUIA_DESPLIEGUE.md` y `evidence/README.md` recogen región, SNS y parte de los pasos. Queda pendiente el orden con 08, rol de despliegue, destrucción de 08 y actualización completa de CP-11. El inventario de parámetros no es directamente un archivo de entrada de `cloudformation deploy`.
- **E:** `frontend/src/features/dashboard/dashboard.css` permite partir el saludo; `frontend/src/features/objetos/ObjetosPage.jsx` y `objetos.css` incorporan botón de filtros con contador en pantallas menores de 768 px. No se agregaron colores fijos. Falta verificación visual interactiva a 375 px en los tres temas.

## Verificación ejecutada

- `docker compose -f docker-compose.pruebas.yml run --rm pruebas`: primera ejecución simultánea con la suite de base: **11 fallos y 26 aprobados**, porque ambas recrearon la misma base y se cortaron las conexiones. Repetida de forma aislada: **42 aprobadas**, 28 advertencias de longitud de clave JWT sintética; salida 0.
- `docker compose -f docker-compose.pruebas.yml run --rm pruebas base`: **84 PASS**, cero fallos, salida 0. La primera ejecución coincidió con la API y causó los fallos descritos arriba.
- `docker run --rm -v "${PWD}/frontend:/web" -w /web node:22-alpine sh -c "npm ci --no-audit --no-fund && npm run build"`: salida 0, 1076 módulos transformados, Vite compiló. Hubo aviso informativo de tiempos de plugins.
- `docker run --rm -v "${PWD}:/repo" -w /repo python:3.13-slim sh -c "pip install -q cfn-lint && cfn-lint infrastructure/cloudformation/*.yaml"`: salida 0, sin errores ni advertencias de cfn-lint para las plantillas existentes; todavía no hay plantilla 08.
- `git diff --check`: salida 0, con avisos de conversión CRLF de Git.

### Migración local con maestro sin superusuario

Se levantó `postgres:16` con `docker run -d --name ecoraee-rds-prueba ... postgres:16`, se creó `maestro` con `LOGIN CREATEDB CREATEROLE` y la base `ecoraee` de su propiedad. Consulta de `pg_roles`: `rolsuper=f`, `rolcreaterole=t`, `rolcreatedb=t`. El origen fue la base de desarrollo de la suite, en la red de Docker. Se copiaron los archivos de base y el script al contenedor. Un ejecutable de prueba local reemplazó las lecturas de Secrets Manager con JSON sintético; un wrapper local de `psql` desactivó TLS para esta emulación. No se ejecutó AWS CLI ni se probó TLS.

- `docker exec ... bash /tmp/prueba/infrastructure/scripts/migrar_base.sh` con variables sintéticas: **salida 0**, scripts 01–20, logins y preparación de producción.
- `docker exec ... bash /tmp/prueba/infrastructure/scripts/migrar_base.sh --datos` inmediatamente sobre la base ya migrada: **salida 1 esperada**, «La base destino debe estar vacía para --datos».
- Tras recrear esa base vacía: el mismo comando `--datos` terminó con **salida 0**, incluida la preparación de producción. Antes, el método previo `pg_dump --data-only` falló por duplicado en `actor_negocio_pkey`; su transacción hizo rollback.
- Conteos en origen → destino tras `--datos`: `seg.usuario` **23 → 24** (se crea el administrador inicial); `trz.objeto_trazable` **22 → 22**; `ops.documento_operativo` **50 → 50**; `cat.categoria_raee` **14 → 14**.

Los puntos suspensivos de los comandos anteriores representan variables y credenciales **sintéticas y efímeras** del contenedor, no argumentos de AWS reales. La prueba ejercitó el script, pero no Secrets Manager, Session Manager ni certificados reales.

- `docker compose -f docker-compose.pruebas.yml down -v`: salida 0, contenedor, red y volumen de pruebas eliminados.
- `docker rm -f ecoraee-rds-prueba`: salida 0, contenedor de migración eliminado.
