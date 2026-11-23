"""Integración del módulo matemático (RF-INT-04, CP-09): el cálculo es el mismo de /math/ecoraee_flujo.py."""
from __future__ import annotations

import os
import sys
from pathlib import Path

# /math del repositorio (en Docker se copia a /app/math)
for candidato in (Path(__file__).resolve().parents[2] / "math", Path("/app/math"), Path(os.getenv("ECORAEE_MATH", "")) ):
    if candidato and (candidato / "ecoraee_flujo.py").exists() and str(candidato) not in sys.path:
        sys.path.insert(0, str(candidato))
        break

import ecoraee_flujo as nucleo  # noqa: E402

VERSION = "2.0.0"


async def calcular(conn, escenario: str, registrar: bool = False) -> dict:
    """Lee el dataset desde RDS, calcula y, si se pide, registra la ejecución (la base valida el hash)."""
    dataset = await conn.fetchval("SELECT api.fn_dataset_flujo($1)", escenario)
    r = nucleo.calcular(dataset)
    meta = await conn.fetchrow("SELECT nombre, descripcion, escenario_base FROM api.v1_escenario WHERE codigo = $1", escenario)
    r.update({"nombre": meta["nombre"], "lectura": meta["descripcion"], "escenario_base": meta["escenario_base"],
              "ejecucion_id": None, "registrado": False})
    if registrar:
        flujos, cortes = nucleo.para_registro(r)
        r["ejecucion_id"] = await conn.fetchval(
            "SELECT api.fn_registrar_resultado_flujo($1, $2, $3, $4::jsonb, $5::jsonb, 'EDMONDS_KARP', $6)",
            escenario, dataset["hash"], r["flujo_maximo"], flujos, cortes, VERSION)
        r["registrado"] = True
    return r
