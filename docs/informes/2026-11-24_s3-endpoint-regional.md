# Endpoint regional de S3

Fecha: 2026-11-24

## Cambio

El cliente S3 usa `https://s3.<region>.amazonaws.com` cuando no se configura un endpoint personalizado. Se fuerza la firma S3 v4 y el direccionamiento virtual para que las URL prefirmadas utilicen el host regional del bucket, evitando el redireccionamiento 307 del endpoint global en buckets nuevos. Los endpoints personalizados conservan la selección y configuración anteriores, incluido el endpoint público para firmar. No se modifica la variable global `AWS_ENDPOINT_URL` ni el cliente de Secrets Manager.

## Archivos

- `backend/app/almacen.py`: selección del endpoint regional y configuración del cliente S3.
- `backend/tests/test_fase2.py`: pruebas sin red de la URL regional con credenciales falsas y de los endpoints personalizados.
- `docs/informes/2026-11-24_s3-endpoint-regional.md`: este informe.

## Resultado de las pruebas

- `docker compose -f docker-compose.pruebas.yml run --rm pruebas`: éxito, **49 pruebas aprobadas**, 28 advertencias en 20,47 s. Las advertencias corresponden a la longitud de la clave HMAC JWT usada en pruebas.
- `docker compose -f docker-compose.pruebas.yml down -v`: éxito; contenedor, red y volumen de pruebas eliminados.

Las pruebas de firma son locales y no realizan una subida a AWS real.
