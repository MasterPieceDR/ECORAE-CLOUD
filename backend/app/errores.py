"""Traducción de errores: los códigos propios de la base (EC4xx) y de PostgreSQL pasan a HTTP con un formato único."""
from __future__ import annotations

import logging
import re

import asyncpg
from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

log = logging.getLogger("ecoraee.api")

# SQLSTATE → (HTTP, mensaje genérico si la base no da uno útil)
SQLSTATE_HTTP = {
    "EC401": (401, None), "EC403": (403, None), "EC404": (404, None), "EC409": (409, None), "EC422": (422, None),
    "23505": (409, "Ya existe un registro con ese identificador (código, número de serie o clave)."),
    "23503": (422, "La combinación no está permitida por las reglas de la red (por ejemplo, clasificación y destino)."),
    "23514": (422, "Un dato no cumple una regla de validación."),
    "23502": (422, "Falta un dato obligatorio."),
    "23P01": (409, "Las vigencias se solapan con un registro existente."),
    "22P02": (422, "Un valor tiene un formato inválido."),
    "22007": (422, "La fecha tiene un formato inválido."),
    "42501": (403, "Privilegio insuficiente en la base de datos (mínimo privilegio)."),
    "40001": (409, "Conflicto de concurrencia: vuelve a intentarlo."),
    "40P01": (409, "Conflicto de concurrencia: vuelve a intentarlo."),
    "55P03": (409, "El recurso está siendo modificado por otra operación."),
    "57014": (504, "La consulta tardó demasiado."),
}


class ErrorAPI(Exception):
    def __init__(self, estado: int, detalle: str, codigo: str = "API"):
        self.estado, self.detalle, self.codigo = estado, detalle, codigo


def _rid(request: Request) -> str | None:
    return getattr(request.state, "request_id", None)


def _respuesta(request: Request, estado: int, detalle: str, codigo: str, **extra) -> JSONResponse:
    return JSONResponse(status_code=estado, content={"detail": detalle, "codigo": codigo, "request_id": _rid(request), **extra})


async def manejar_api(request: Request, exc: ErrorAPI):
    return _respuesta(request, exc.estado, exc.detalle, exc.codigo)


async def manejar_postgres(request: Request, exc: asyncpg.PostgresError):
    estado_sql = getattr(exc, "sqlstate", None) or "XX000"
    estado, generico = SQLSTATE_HTTP.get(estado_sql, (500, None))
    mensaje = getattr(exc, "message", None) or str(exc)
    if estado == 500:
        log.exception("Error de base no mapeado %s: %s", estado_sql, mensaje)
        return _respuesta(request, 500, "Error interno al procesar la operación.", estado_sql)
    m = re.match(r"Acceso denegado: el usuario \d+ no tiene el permiso (\S+)\s*(?:en el centro (\d+))?", mensaje or "")
    if m:                                             # sin ids internos en la respuesta
        mensaje = f"Tu rol no tiene el permiso {m.group(1)}" + (" en ese centro" if m.group(2) else "") + "."
    if generico and not estado_sql.startswith("EC"):
        restriccion = getattr(exc, "constraint_name", None)
        mensaje = generico + (f" ({restriccion})" if restriccion else "")
    return _respuesta(request, estado, mensaje, estado_sql)


# Mensajes de validación de Pydantic en español (el resto de errores ya vienen en español desde la base)
_MENSAJES = {
    "missing": "es obligatorio",
    "greater_than": "debe ser mayor que {gt}",
    "greater_than_equal": "debe ser mayor o igual que {ge}",
    "less_than": "debe ser menor que {lt}",
    "less_than_equal": "debe ser menor o igual que {le}",
    "string_too_short": "debe tener al menos {min_length} caracteres",
    "string_too_long": "debe tener como máximo {max_length} caracteres",
    "too_short": "debe tener al menos {min_length} elemento(s)",
    "string_pattern_mismatch": "no tiene el formato esperado",
    "int_parsing": "debe ser un número entero",
    "int_from_float": "debe ser un número entero",
    "float_parsing": "debe ser un número",
    "bool_parsing": "debe ser verdadero o falso",
    "uuid_parsing": "no es un identificador válido",
    "json_invalid": "el cuerpo no es un JSON válido",
    "dict_type": "debe ser un objeto JSON",
    "list_type": "debe ser una lista",
    "string_type": "debe ser un texto",
}


def _mensaje(e: dict) -> str:
    plantilla = _MENSAJES.get(e.get("type", ""))
    if not plantilla:
        return e.get("msg", "valor inválido")
    try:
        ctx = {k: (int(v) if isinstance(v, float) and v.is_integer() else v) for k, v in (e.get("ctx") or {}).items()}
        return plantilla.format(**ctx)
    except (KeyError, IndexError):
        return e.get("msg", "valor inválido")


async def manejar_validacion(request: Request, exc: RequestValidationError):
    errores = [{"campo": ".".join(str(p) for p in e.get("loc", []) if p not in ("body", "query", "path")), "mensaje": _mensaje(e)}
               for e in exc.errors()]
    primero = errores[0] if errores else {"campo": "", "mensaje": "Datos inválidos"}
    detalle = f"{primero['campo']}: {primero['mensaje']}" if primero["campo"] else primero["mensaje"]
    return _respuesta(request, 422, detalle, "VALIDACION", errores=errores)


async def manejar_http(request: Request, exc: StarletteHTTPException):
    return _respuesta(request, exc.status_code, str(exc.detail), "HTTP")


async def manejar_inesperado(request: Request, exc: Exception):
    log.exception("Error inesperado")
    return _respuesta(request, 500, "Error interno al procesar la operación.", "INTERNO")
