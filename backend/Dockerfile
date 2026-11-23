# EcoRAEE Cloud — imagen de la API y del servidor MCP (misma imagen, distinto comando)
# Construir desde la raíz del repositorio:  docker build -f backend/Dockerfile -t ecoraee-api .
FROM python:3.13-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 ECORAEE_MATH=/app/math
WORKDIR /app
COPY backend/requirements.txt .
# Instala desde backend/wheels/ (descargadas de antemano) para no depender de la red durante la construcción;
# si la carpeta no existe, descarga de PyPI.
COPY backend/wheels/ /tmp/wheels/
RUN if ls /tmp/wheels/*.whl >/dev/null 2>&1; then pip install --no-index --find-links /tmp/wheels -r requirements.txt; \
    else pip install --retries 10 --timeout 60 -r requirements.txt; fi && rm -rf /tmp/wheels
COPY math/ecoraee_flujo.py /app/math/ecoraee_flujo.py
COPY backend/app /app/app
COPY backend/mcp_server /app/mcp_server
# usuario sin privilegios (CP-11: mínimo privilegio también en el contenedor)
RUN useradd --uid 10001 --no-create-home ecoraee && mkdir -p /app/almacen && chown ecoraee /app/almacen
USER ecoraee
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/v1/salud', timeout=2)"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
