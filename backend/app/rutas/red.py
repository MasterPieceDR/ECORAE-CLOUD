"""Red logística y flujo máximo (RF-MD-03…05, RF-INT-04, CP-07…CP-09)."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from .. import db, flujo
from ..seguridad import Sesion, perfil, sesion

router = APIRouter(prefix="/red", tags=["Red y flujo máximo"])


@router.get("")
async def red(s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        p = await perfil(conn)
        return {
            "nodos": db.filas(await conn.fetch("SELECT codigo, nombre, tipo, es_fuente, es_sumidero, centro, organizacion, activo, capacidad_und "
                                               "FROM api.v1_red_nodo ORDER BY codigo")),
            "aristas": db.filas(await conn.fetch("SELECT origen, destino, activa, requiere_excepcion, capacidad_und, capacidad_kg "
                                                 "FROM api.v1_red_arista ORDER BY origen, destino")),
            "escenarios": db.filas(await conn.fetch("SELECT codigo, nombre, descripcion, escenario_base, estado, periodo, unidad, "
                                                    "cambios_aristas, cambios_nodos FROM api.v1_escenario ORDER BY codigo")),
            "utilizacion": db.filas(await conn.fetch("SELECT origen, destino, unidad, periodo, capacidad, consumo, utilizacion_pct "
                                                     "FROM api.v1_utilizacion_arista ORDER BY utilizacion_pct DESC NULLS LAST")),
            "puede_registrar": p.tiene("RED.EJECUTAR_FLUJO"),
            "puede_analizar": p.tiene("RED.EJECUTAR_FLUJO") or p.tiene("GOBIERNO.DECIDIR") or p.tiene("AUDITORIA.CONSULTAR"),
            "puede_editar": p.tiene("RED.EJECUTAR_FLUJO") or p.tiene("GOBIERNO.DECIDIR"),
        }


@router.get("/escenarios/{codigo}/flujo")
async def analizar(codigo: str, s: Sesion = Depends(sesion)):
    """Calcula en vivo con el dataset de la base (coordinador, comité y auditor). No escribe nada."""
    async with s.tx() as conn:
        return await flujo.calcular(conn, codigo, registrar=False)


@router.post("/escenarios/{codigo}/flujo")
async def ejecutar(codigo: str, s: Sesion = Depends(sesion)):
    """Calcula y registra la ejecución (RED.EJECUTAR_FLUJO). La base rechaza el resultado si el dataset cambió (hash)."""
    async with s.tx() as conn:
        return await flujo.calcular(conn, codigo, registrar=True)


@router.get("/comparacion")
async def comparar(s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        codigos = [r["codigo"] for r in await conn.fetch("SELECT codigo FROM api.v1_escenario ORDER BY codigo")]
        salida = []
        for c in codigos:
            r = await flujo.calcular(conn, c)
            salida.append({"codigo": c, "nombre": r["nombre"], "flujo_maximo": r["flujo_maximo"], "generacion": r["generacion"],
                           "cobertura": r["cobertura"], "cortes": len(r["cortes"])})
        historial = db.filas(await conn.fetch("SELECT escenario, ejecucion_id, flujo_maximo, finalizado_en, cortes_minimos "
                                              "FROM api.v1_resultado_flujo ORDER BY escenario"))
    return {"escenarios": salida, "ultimas_ejecuciones": historial}


# ---- Editor de escenarios ("qué pasaría si"): solo escenarios BORRADOR; E0–E4 están aprobados ----
class EscenarioIn(BaseModel):
    codigo: str = Field(pattern=r"^[A-Za-z][A-Za-z0-9_-]{1,19}$")
    nombre: str = Field(min_length=3, max_length=120)
    base: str = "E0"
    descripcion: str | None = Field(None, max_length=500)


class AjusteAristaIn(BaseModel):
    origen: str
    destino: str
    capacidad: float | None = Field(None, ge=0, le=100000)
    activa: bool | None = None
    motivo: str | None = Field(None, max_length=300)


class AjusteNodoIn(BaseModel):
    nodo: str
    capacidad: float | None = Field(None, ge=0, le=100000)
    oferta: float | None = Field(None, ge=0, le=100000)
    demanda: float | None = Field(None, ge=0, le=100000)


@router.post("/escenarios", status_code=201)
async def crear_escenario(d: EscenarioIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        codigo = await conn.fetchval("SELECT api.fn_crear_escenario($1, $2, $3, $4)", d.codigo, d.nombre, d.base, d.descripcion)
    return {"codigo": codigo}


@router.put("/escenarios/{codigo}/aristas")
async def ajustar_arista(codigo: str, d: AjusteAristaIn, s: Sesion = Depends(sesion)):
    """capacidad y activa en null = quitar el ajuste (la arista vuelve a heredar del escenario base)."""
    async with s.tx() as conn:
        await conn.execute("SELECT api.fn_ajustar_escenario_arista($1, $2, $3, $4, $5, $6)",
                           codigo, d.origen, d.destino, d.capacidad, d.activa, d.motivo)
        return await flujo.calcular(conn, codigo)


@router.put("/escenarios/{codigo}/nodos")
async def ajustar_nodo(codigo: str, d: AjusteNodoIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        await conn.execute("SELECT api.fn_ajustar_escenario_nodo($1, $2, $3, $4, $5)", codigo, d.nodo, d.capacidad, d.oferta, d.demanda)
        return await flujo.calcular(conn, codigo)


@router.delete("/escenarios/{codigo}")
async def eliminar_escenario(codigo: str, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        await conn.execute("SELECT api.fn_eliminar_escenario($1)", codigo)
    return {"ok": True}
