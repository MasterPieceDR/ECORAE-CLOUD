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
                SELECT fuente, semana, sum(equipos) equipos, sum(peso_kg) peso
                FROM api.v1_serie_recoleccion
                WHERE ($1::text IS NULL OR categoria=$1)
                  AND semana <= date_trunc('week', current_timestamp AT TIME ZONE 'America/Guayaquil')::date
                GROUP BY fuente, semana
            ), limites AS (SELECT fuente, min(semana) inicio, max(semana) fin FROM datos GROUP BY fuente)
            SELECT limites.fuente, serie.semana::date AS semana,
                   coalesce(datos.equipos, 0) equipos, coalesce(datos.peso, 0) peso,
                   serie.semana::date < date_trunc('week', current_timestamp AT TIME ZONE 'America/Guayaquil')::date AS completa
            FROM limites CROSS JOIN LATERAL generate_series(
                inicio::timestamp,
                greatest(fin::timestamp, date_trunc('week', current_timestamp AT TIME ZONE 'America/Guayaquil') - interval '1 week'),
                interval '1 week') serie(semana)
            LEFT JOIN datos ON datos.fuente=limites.fuente AND datos.semana=serie.semana::date
            ORDER BY limites.fuente, serie.semana""", categoria)
        series = {fuente: [f for f in filas if f["fuente"] == fuente]
                  for fuente in ("RED_HISTORICO", "PLATAFORMA")}
        completas = {fuente: [f for f in registros if f["completa"]] for fuente, registros in series.items()}
        fuente = "RED_HISTORICO" if completas["RED_HISTORICO"] else "PLATAFORMA"
        entrenamiento = completas[fuente]
        def puntos(registros):
            return [{"semana": f["semana"].isoformat(), "valor": float(f[medida])} for f in registros]
        historia = puntos(entrenamiento)
        plataforma = puntos(series["PLATAFORMA"])
        resultado = holt([x["valor"] for x in historia], semanas)
        for i, punto in enumerate(resultado["pronostico"], 1):
            punto["semana"] = (entrenamiento[-1]["semana"] + timedelta(weeks=i)).isoformat()
        nota = ("El modelo se entrenó con el histórico sintético de demostración de la red."
                if fuente == "RED_HISTORICO" else "El modelo se entrenó con las recepciones registradas en la plataforma.")
        return {"disponible": True, "metodo": "Holt", **resultado, "fuente_modelo": fuente,
                "historia": historia, "plataforma": plataforma, "nota": nota + " Banda aproximada del 80 %."}
    except Exception:
        log.exception("No se pudo calcular la proyección")
        return {"disponible": False, "metodo": "Holt", "parametros": {}, "fuente_modelo": None, "historia": [], "plataforma": [], "pronostico": [], "mape": None, "nota": "No hay datos suficientes o la proyección no está disponible."}
