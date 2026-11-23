"""Proyección aislada de recolección."""
import logging
from datetime import timedelta
from typing import Literal
from fastapi import APIRouter, Depends, Query
from ..seguridad import sesion, perfil, Sesion
from ..errores import ErrorAPI
from ..prediccion import holt

router = APIRouter(prefix="/prediccion", tags=["Predicción"])
log = logging.getLogger(__name__)

@router.get("/recoleccion")
async def recoleccion(categoria: str | None = None, semanas: int = Query(8, ge=1, le=52), medida: Literal["equipos", "peso"] = "equipos", s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        p = await perfil(conn)
        if not any(p.rol(r) for r in ("ADMINISTRADOR", "COORDINADOR_LOGISTICO", "COMITE_ARQUITECTURA", "AUDITOR")):
            raise ErrorAPI(403, "No tienes permiso para consultar la proyección", "EC403")
    try:
        async with s.tx() as conn:
            filas = await conn.fetch("""WITH datos AS (
                SELECT semana, sum(equipos) equipos, sum(peso_kg) peso, bool_or(sintetico) sintetico
                FROM api.v1_serie_recoleccion WHERE ($1::text IS NULL OR categoria=$1) GROUP BY semana
            ), limites AS (SELECT min(semana) inicio, max(semana) fin FROM datos)
            SELECT serie.semana::date AS semana, coalesce(datos.equipos, 0) equipos,
                   coalesce(datos.peso, 0) peso, coalesce(datos.sintetico, false) sintetico
            FROM limites CROSS JOIN LATERAL generate_series(inicio::timestamp, fin::timestamp, interval '1 week') serie(semana)
            LEFT JOIN datos ON datos.semana=serie.semana::date ORDER BY serie.semana""", categoria)
        historia = [{"semana": f["semana"].isoformat(), "valor": float(f[medida]), "sintetico": f["sintetico"]} for f in filas]
        resultado = holt([x["valor"] for x in historia], semanas)
        for i, punto in enumerate(resultado["pronostico"], 1):
            punto["semana"] = (filas[-1]["semana"] + timedelta(weeks=i)).isoformat()
        return {"disponible": True, "metodo": "Holt", **resultado, "historia": historia,
                "nota": "La historia incluye datos sintéticos de demostración. Banda aproximada del 80 %."}
    except Exception:
        log.exception("No se pudo calcular la proyección")
        return {"disponible": False, "metodo": "Holt", "parametros": {}, "historia": [], "pronostico": [], "mape": None, "nota": "No hay datos suficientes o la proyección no está disponible."}
