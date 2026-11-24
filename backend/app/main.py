"""EcoRAEE Cloud — API (FastAPI). Delgada por diseño: las reglas viven en la base (ADR-005)."""
from __future__ import annotations

import json
import hmac
import logging
import time
import uuid
from contextlib import asynccontextmanager

import asyncpg
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from starlette.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from . import db, errores
from .config import config
from .rutas import asistente, auth, capacitacion, catalogo, documentos, evidencias, general, gobierno, objetos, prediccion, red, verificacion


class _JSON(logging.Formatter):
    """Una línea JSON por evento: CloudWatch Logs Insights la consulta sin parsers (RF-CL-06)."""

    def format(self, r: logging.LogRecord) -> str:
        base = {"t": self.formatTime(r, "%Y-%m-%dT%H:%M:%S"), "nivel": r.levelname, "origen": r.name, "msg": r.getMessage()}
        base.update(getattr(r, "extra", {}) or {})
        if r.exc_info:
            base["excepcion"] = self.formatException(r.exc_info)
        return json.dumps(base, ensure_ascii=False, default=str)


_h = logging.StreamHandler()
_h.setFormatter(_JSON())
logging.basicConfig(level=logging.INFO, handlers=[_h], force=True)
log = logging.getLogger("ecoraee.api")


@asynccontextmanager
async def vida(app: FastAPI):
    await db.abrir()
    log.info("API lista", extra={"extra": {"entorno": config().entorno, "auth": config().auth_modo, "almacen": config().almacen_modo}})
    yield
    await db.cerrar()


app = FastAPI(title="EcoRAEE Cloud API", version=config().version, lifespan=vida,
              docs_url="/api/docs", openapi_url="/api/openapi.json", redoc_url=None,
              description="Trazabilidad de RAEE, red logística con flujo máximo, capacitación y asistente MCP. "
                          "Todas las escrituras pasan por funciones api.* de PostgreSQL que aplican RN-01…RN-09.")

app.add_middleware(CORSMiddleware, allow_origins=config().origenes, allow_credentials=False,
                   allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"], allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
                   expose_headers=["X-Request-ID"])


@app.middleware("http")
async def contexto_peticion(request: Request, siguiente):
    rid = request.headers.get("x-request-id") or uuid.uuid4().hex
    request.state.request_id = rid[:64]
    t0 = time.perf_counter()
    secreto = config().origin_secret
    recibido = request.headers.get("x-origin-verify", "")
    if secreto and not hmac.compare_digest(secreto.encode("utf-8"), recibido.encode("utf-8")):
        respuesta = JSONResponse(status_code=403, content={"detail": "Forbidden"})
    else:
        try:
            respuesta = await siguiente(request)
        except Exception:
            log.exception("peticion", extra={"extra": {"metodo": request.method, "ruta": request.url.path,
                "estado": 500, "ms": round((time.perf_counter() - t0) * 1000, 1), "request_id": request.state.request_id}})
            raise
    ms = round((time.perf_counter() - t0) * 1000, 1)
    respuesta.headers["X-Request-ID"] = request.state.request_id
    respuesta.headers["X-Content-Type-Options"] = "nosniff"
    respuesta.headers["Referrer-Policy"] = "no-referrer"
    if respuesta.status_code >= 500 or not request.url.path.endswith("/salud"):
        log.info("peticion", extra={"extra": {"metodo": request.method, "ruta": request.url.path, "estado": respuesta.status_code,
                                              "ms": ms, "request_id": request.state.request_id,
                                              "usuario": getattr(request.state, "usuario", None)}})
    return respuesta


app.add_exception_handler(errores.ErrorAPI, errores.manejar_api)
app.add_exception_handler(asyncpg.PostgresError, errores.manejar_postgres)
app.add_exception_handler(RequestValidationError, errores.manejar_validacion)
app.add_exception_handler(StarletteHTTPException, errores.manejar_http)
app.add_exception_handler(Exception, errores.manejar_inesperado)

for r in (general.router, auth.router, catalogo.router, objetos.router, prediccion.router, documentos.router, evidencias.router, red.router,
          capacitacion.router, gobierno.router, asistente.router, verificacion.router):
    app.include_router(r, prefix="/api/v1")
