"""Tareas de operación: python -m app.cli inicializar | flujos

inicializar: calcula y registra el flujo de todos los escenarios (para que el comité vea resultados guardados)
             y recalcula indicadores. Se ejecuta tras cargar la base (docker compose lo hace solo).
"""
from __future__ import annotations

import asyncio
import sys
import os
import secrets
import asyncpg
from datetime import date

from . import db, flujo

SISTEMA = "00000000-0000-4000-8000-000000000099"


async def _inicializar() -> None:
    await db.abrir()
    try:
        async with db.transaccion(SISTEMA, "BATCH") as conn:
            escenarios = [r["codigo"] for r in await conn.fetch("SELECT codigo FROM api.v1_escenario ORDER BY codigo")]
        for e in escenarios:
            async with db.transaccion(SISTEMA, "BATCH") as conn:
                r = await flujo.calcular(conn, e, registrar=True)
            print(f"{e}: flujo {r['flujo_maximo']:.0f}/{r['generacion']:.0f} ({r['cobertura']} %) · {len(r['cortes'])} corte(s) · ejecución {r['ejecucion_id']}")
        async with db.transaccion(SISTEMA, "BATCH") as conn:
            hoy = date.today()
            n = await conn.fetchval("SELECT ind.fn_calcular_indicadores($1, $2)", hoy.replace(day=1), hoy)
            a = await conn.fetchval("SELECT ind.fn_generar_alertas()")
        print(f"Indicadores: {n} · alertas nuevas: {a}")
    finally:
        await db.cerrar()


async def _preparar_produccion() -> None:
    requeridas = ("DB_ADMIN_HOST", "DB_ADMIN_NOMBRE", "DB_ADMIN_USUARIO", "DB_ADMIN_CLAVE", "ADMIN_CORREO", "ADMIN_ALIAS")
    faltan = [v for v in requeridas if not os.environ.get(v)]
    if faltan:
        sys.exit("Faltan variables: " + ", ".join(faltan))
    clave = os.environ.get("ADMIN_CLAVE") or secrets.token_urlsafe(36)
    conn = await asyncpg.connect(host=os.environ["DB_ADMIN_HOST"], port=int(os.getenv("DB_ADMIN_PORT", "5432")),
                                 database=os.environ["DB_ADMIN_NOMBRE"], user=os.environ["DB_ADMIN_USUARIO"],
                                 password=os.environ["DB_ADMIN_CLAVE"], ssl=os.getenv("DB_ADMIN_SSL", "false").lower() == "true")
    try:
        uid = await conn.fetchval("SELECT seg.fn_preparar_produccion($1,$2,$3,$4)", os.environ["ADMIN_CORREO"], os.environ["ADMIN_ALIAS"], clave, os.getenv("CLAVE_DEMO") or None)
        print(f"Administrador preparado: {uid}")
        if not os.environ.get("ADMIN_CLAVE"):
            print(f"Clave generada (guárdela ahora): {clave}")
    finally:
        await conn.close()


if __name__ == "__main__":
    orden = sys.argv[1] if len(sys.argv) > 1 else "inicializar"
    if orden in ("inicializar", "flujos"):
        asyncio.run(_inicializar())
    elif orden == "preparar-produccion":
        asyncio.run(_preparar_produccion())
    else:
        sys.exit(f"Orden desconocida: {orden}")
