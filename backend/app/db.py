"""Acceso a PostgreSQL: dos pools (API y MCP, cada uno con su login) y una transacción por petición con contexto.

Contrato de la base (ADR-005):
  1. Cada transacción empieza con api.fn_iniciar_contexto(usuario, canal, request_id).
  2. Lecturas por vistas api.v1_* (RLS por ecosistema y rol).
  3. Escrituras solo por funciones api.fn_* (SECURITY DEFINER); el login de la API no tiene INSERT/UPDATE/DELETE.
"""
from __future__ import annotations

import json
import ssl
from contextlib import asynccontextmanager
from typing import AsyncIterator

import asyncpg

from .config import config

_pools: dict[str, asyncpg.Pool] = {}


async def _init(conn: asyncpg.Connection) -> None:
    for tipo in ("json", "jsonb"):
        await conn.set_type_codec(tipo, encoder=lambda v: json.dumps(v, default=str), decoder=json.loads, schema="pg_catalog")
    await conn.set_type_codec("uuid", encoder=str, decoder=str, schema="pg_catalog", format="text")


async def abrir() -> None:
    c = config()
    tls = ssl.create_default_context() if c.db_ssl else None
    for nombre, usuario, clave in (("api", c.db_usuario_api, c.db_clave_api), ("mcp", c.db_usuario_mcp, c.db_clave_mcp)):
        if nombre not in _pools:
            _pools[nombre] = await asyncpg.create_pool(
                host=c.db_host, port=c.db_port, database=c.db_nombre, user=usuario, password=clave or None, ssl=tls,
                min_size=c.db_pool_min, max_size=c.db_pool_max, init=_init, command_timeout=20,
                server_settings={"application_name": f"ecoraee-{nombre}"})


async def cerrar() -> None:
    for p in list(_pools.values()):
        await p.close()
    _pools.clear()


def pool(nombre: str = "api") -> asyncpg.Pool:
    return _pools[nombre]


@asynccontextmanager
async def transaccion(usuario_uid: str | None, canal: str = "WEB", request_id: str | None = None,
                      pool_nombre: str = "api") -> AsyncIterator[asyncpg.Connection]:
    """Una transacción con el contexto del usuario: RLS y reglas aplican igual que en las pruebas de la base."""
    async with pool(pool_nombre).acquire() as conn:
        async with conn.transaction():
            if usuario_uid:
                await conn.fetchval("SELECT api.fn_iniciar_contexto($1::uuid, $2, $3)", usuario_uid, canal, request_id)
            yield conn


@asynccontextmanager
async def sin_contexto() -> AsyncIterator[asyncpg.Connection]:
    """Solo para autenticación y registro (funciones que se ejecutan antes de conocer al usuario)."""
    async with pool("api").acquire() as conn:
        async with conn.transaction():
            yield conn


def filas(registros) -> list[dict]:
    return [dict(r) for r in registros]
