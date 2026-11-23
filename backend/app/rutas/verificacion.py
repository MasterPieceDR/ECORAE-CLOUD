"""Verificación de la base de datos (Parte II · integración): conexión, estructura, consistencia y persistencia.

- /verificacion/conexion   sin sesión: comprueba la cadena navegador → API → PostgreSQL y mide la latencia.
- /verificacion/base       con sesión: claves, restricciones, RLS, auditoría, volumen y 8 comprobaciones (0 problemas = correcto).
- /verificacion/objetos/X  con sesión: las filas reales que la base guarda de un equipo (prueba de persistencia), con su auditoría.
"""
from __future__ import annotations

import time

from fastapi import APIRouter, Depends

from .. import db
from ..seguridad import Sesion, sesion

router = APIRouter(prefix="/verificacion", tags=["Verificación de la base de datos"])


@router.get("/conexion")
async def conexion():
    """Abre una conexión con el login de la API, ejecuta SELECT 1 y devuelve versión, base y latencia."""
    t0 = time.perf_counter()
    async with db.sin_contexto() as conn:
        fila = await conn.fetchrow("SELECT 1 AS ok, current_database() AS base, session_user AS usuario, "
                                   "split_part(version(), ' on ', 1) AS motor, now() AS hora_servidor")
    return {"api": "ok", "base_de_datos": "ok" if fila["ok"] == 1 else "error", "motor": fila["motor"], "base": fila["base"],
            "usuario_conexion": fila["usuario"], "hora_servidor": fila["hora_servidor"],
            "latencia_ms": round((time.perf_counter() - t0) * 1000, 1)}


@router.get("/base")
async def base(s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        return await conn.fetchval("SELECT api.fn_verificar_base()")


@router.get("/objetos/{codigo}")
async def objeto(codigo: str, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        return await conn.fetchval("SELECT api.fn_verificar_objeto($1)", codigo)
