"""Catálogos, tablero de indicadores, salud y almacén local (emulación de URL prefirmadas en desarrollo)."""
from __future__ import annotations

from datetime import date

from fastapi import APIRouter, Depends, Request
from fastapi.responses import Response

from .. import almacen, db, flujo
from ..config import config
from ..errores import ErrorAPI
from ..seguridad import Sesion, perfil, sesion

router = APIRouter()


@router.get("/salud", include_in_schema=False)
async def salud():
    """Liveness/readiness para el ALB y ECS: comprueba la conexión a la base."""
    async with db.pool("api").acquire() as conn:
        await conn.fetchval("SELECT 1")
    return {"estado": "ok", "version": config().version, "entorno": config().entorno}


@router.get("/catalogos", tags=["Catálogos"])
async def catalogos(s: Sesion = Depends(sesion)):
    """Fuente única de estados, transiciones, clasificaciones, roles, centros y demás (ADR-003)."""
    async with s.tx() as conn:
        return await conn.fetchval("SELECT api.fn_catalogos()")


@router.get("/glosario", tags=["Catálogos"])
async def glosario(s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        return db.filas(await conn.fetch("SELECT * FROM api.v1_glosario ORDER BY termino"))


@router.get("/tablero", tags=["Indicadores"])
async def tablero(s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        p = await perfil(conn)
        por_estado = db.filas(await conn.fetch(
            "SELECT estado, count(*) AS n FROM api.v1_objeto_operativo WHERE tipo_objeto = 'DISPOSITIVO' GROUP BY estado"))
        por_clas = db.filas(await conn.fetch(
            "SELECT coalesce(clasificacion, 'PENDIENTE') AS clasificacion, count(*) AS n FROM api.v1_objeto_operativo "
            "WHERE tipo_objeto = 'DISPOSITIVO' GROUP BY 1"))
        recientes = db.filas(await conn.fetch(
            "SELECT objeto_uid, codigo, ocurrido_en, estado_origen, estado_destino, tipo_documento, documento, centro, usuario "
            "FROM api.v1_linea_trazabilidad ORDER BY ocurrido_en DESC LIMIT 8"))
        indicadores = db.filas(await conn.fetch(
            "SELECT codigo, nombre, dimension, materia_origen, unidad, valor, meta, cumple_meta, calculado_en FROM api.v1_indicador "
            "ORDER BY dimension, codigo"))
        alertas = db.filas(await conn.fetch("SELECT id, regla, severidad, mensaje, generada_en, objeto FROM api.v1_alerta_abierta "
                                            "ORDER BY generada_en DESC LIMIT 10"))
        red = None
        if p.tiene("RED.EJECUTAR_FLUJO") or p.tiene("GOBIERNO.DECIDIR") or p.tiene("AUDITORIA.CONSULTAR"):
            r = await flujo.calcular(conn, "E0")
            red = {"flujo_maximo": r["flujo_maximo"], "generacion": r["generacion"], "cobertura": r["cobertura"],
                   "cortes": r["cortes"], "lectura": r["lectura"]}
    total = sum(x["n"] for x in por_estado)
    cerrados = sum(x["n"] for x in por_estado if x["estado"] == "CERRADO")
    evaluados = [x for x in por_clas if x["clasificacion"] != "PENDIENTE"]
    recuperables = sum(x["n"] for x in evaluados if x["clasificacion"] != "NO_RECUPERABLE")
    n_eval = sum(x["n"] for x in evaluados)
    return {
        "dispositivos": total, "cerrados": cerrados, "en_proceso": total - cerrados,
        "trazabilidad_completa_pct": round(100 * cerrados / total) if total else 0,
        "recuperacion_pct": round(100 * recuperables / n_eval) if n_eval else 0,
        "por_estado": por_estado, "por_clasificacion": por_clas, "recientes": recientes,
        "indicadores": indicadores, "alertas": alertas, "red": red,
    }


@router.post("/indicadores/recalcular", tags=["Indicadores"])
async def recalcular(s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        p = await perfil(conn)
        if not (p.tiene("RED.GESTIONAR") or p.tiene("CATALOGO.ADMINISTRAR")):
            raise ErrorAPI(403, "Recalcular indicadores es tarea del coordinador o del administrador", "EC403")
        hoy = date.today()
        n = await conn.fetchval("SELECT ind.fn_calcular_indicadores($1, $2)", hoy.replace(day=1), hoy)
        a = await conn.fetchval("SELECT ind.fn_generar_alertas()")
    return {"indicadores": n, "alertas_nuevas": a}


# ---------------------------------------------------------------------------
# Almacén local: solo cuando ALMACEN_MODO=local (en AWS las URL apuntan directo a S3)
# ---------------------------------------------------------------------------
@router.put("/almacen/{bucket}/{clave:path}", include_in_schema=False)
async def almacen_put(bucket: str, clave: str, expira: int, firma: str, request: Request):
    if config().almacen_modo != "local":
        raise ErrorAPI(404, "No disponible", "HTTP")
    almacen.verificar_firma("PUT", bucket, clave, expira, firma)
    await almacen.actual().recibir(bucket, clave, request)
    return Response(status_code=200)


@router.get("/almacen/{bucket}/{clave:path}", include_in_schema=False)
async def almacen_get(bucket: str, clave: str, expira: int, firma: str):
    if config().almacen_modo != "local":
        raise ErrorAPI(404, "No disponible", "HTTP")
    almacen.verificar_firma("GET", bucket, clave, expira, firma)
    return almacen.actual().respuesta(bucket, clave)

