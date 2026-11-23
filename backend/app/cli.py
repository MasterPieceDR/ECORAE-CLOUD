"""Tareas de operación: python -m app.cli inicializar | flujos

inicializar: calcula y registra el flujo de todos los escenarios (para que el comité vea resultados guardados)
             y recalcula indicadores. Se ejecuta tras cargar la base (docker compose lo hace solo).
"""
from __future__ import annotations

import asyncio
import sys
from datetime import date

from . import db, flujo

COORDINADOR = "00000000-0000-4000-8000-000000000009"


async def _inicializar() -> None:
    await db.abrir()
    try:
        async with db.transaccion(COORDINADOR, "BATCH") as conn:
            escenarios = [r["codigo"] for r in await conn.fetch("SELECT codigo FROM api.v1_escenario ORDER BY codigo")]
        for e in escenarios:
            async with db.transaccion(COORDINADOR, "BATCH") as conn:
                r = await flujo.calcular(conn, e, registrar=True)
            print(f"{e}: flujo {r['flujo_maximo']:.0f}/{r['generacion']:.0f} ({r['cobertura']} %) · {len(r['cortes'])} corte(s) · ejecución {r['ejecucion_id']}")
        async with db.transaccion(COORDINADOR, "BATCH") as conn:
            hoy = date.today()
            n = await conn.fetchval("SELECT ind.fn_calcular_indicadores($1, $2)", hoy.replace(day=1), hoy)
            a = await conn.fetchval("SELECT ind.fn_generar_alertas()")
        print(f"Indicadores: {n} · alertas nuevas: {a}")
    finally:
        await db.cerrar()


if __name__ == "__main__":
    orden = sys.argv[1] if len(sys.argv) > 1 else "inicializar"
    if orden in ("inicializar", "flujos"):
        asyncio.run(_inicializar())
    else:
        sys.exit(f"Orden desconocida: {orden}")
