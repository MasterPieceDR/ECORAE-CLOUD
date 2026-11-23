"""Ejecutor de herramientas MCP gobernado por la base (ADR-006).

Flujo de cada invocación (igual para el panel web, el chat con Claude y el servidor MCP estándar):
  1. Transacción con el login ecoraee_mcp_svc y canal 'MCP': solo puede ejecutar los objetos registrados en mcp.herramienta.
  2. api.fn_mcp_autorizar: rol, límite por minuto y confirmación humana para escrituras (los rechazos quedan en bitácora).
  3. Se ejecuta el objeto api.* registrado (en un savepoint: si falla, el error también se registra).
  4. api.fn_mcp_registrar: argumentos saneados, filas, duración y error en la bitácora particionada.
"""
from __future__ import annotations

import time
import uuid
from typing import Any, Awaitable, Callable

import asyncpg

from .. import db, flujo

Handler = Callable[[asyncpg.Connection, dict], Awaitable[tuple[Any, int]]]


async def _trazabilidad(conn, a):
    r = await conn.fetchval("SELECT api.fn_linea_trazabilidad($1)", a["codigo"])
    if r is None:
        return {"encontrado": False, "codigo": a["codigo"]}, 0
    return r, len(r.get("pasos") or [])


async def _buscar(conn, a):
    rows = db.filas(await conn.fetch("""
        SELECT codigo, tipo_objeto, estado, clasificacion, categoria, peso_kg, organizacion_origen, centro_actual, dias_en_estado
          FROM api.v1_objeto
         WHERE ($1::text IS NULL OR centro_actual = $1) AND ($2::text IS NULL OR estado = $2)
           AND ($3::text IS NULL OR categoria = $3) AND ($4::text IS NULL OR clasificacion = $4)
         ORDER BY codigo LIMIT $5""", a.get("centro"), a.get("estado"), a.get("categoria"), a.get("clasificacion"),
                                       min(int(a.get("limite") or 50), 200)))
    return rows, len(rows)


async def _inventario(conn, a):
    rows = db.filas(await conn.fetch("SELECT centro, ubicacion, categoria, clasificacion, unidades, peso_kg FROM api.v1_inventario "
                                     "WHERE ($1::text IS NULL OR centro = $1) ORDER BY centro, ubicacion", a.get("centro")))
    return rows, len(rows)


async def _utilizacion(conn, a):
    rows = db.filas(await conn.fetch("SELECT origen, destino, unidad, periodo, capacidad, consumo, utilizacion_pct "
                                     "FROM api.v1_utilizacion_arista ORDER BY utilizacion_pct DESC NULLS LAST"))
    return rows, len(rows)


async def _flujo(conn, a):
    dataset = await conn.fetchval("SELECT api.fn_dataset_flujo($1)", a["escenario"])
    r = flujo.nucleo.calcular(dataset)
    flujos, cortes = flujo.nucleo.para_registro(r)
    return {"escenario": a["escenario"], "flujo_maximo": r["flujo_maximo"], "generacion": r["generacion"], "cobertura": r["cobertura"],
            "cortes_minimos": r["cortes"], "hash": dataset["hash"], "flujos": flujos, "cortes": cortes}, len(r["aristas"])


async def _registrar_flujo(conn, a):
    ej = await conn.fetchval("SELECT api.fn_registrar_resultado_flujo($1, $2, $3, $4::jsonb, $5::jsonb, 'EDMONDS_KARP', $6)",
                             a["escenario"], a["hash"], a["flujo_maximo"], a["flujos"], a["cortes"], flujo.VERSION)
    return {"ejecucion_id": ej, "registrado": True}, 1


async def _comparar(conn, a):
    esc = a.get("escenarios") or None
    rows = db.filas(await conn.fetch("SELECT escenario, escenario_base, flujo_maximo, finalizado_en, cortes_minimos, aristas_saturadas "
                                     "FROM api.v1_resultado_flujo WHERE ($1::text[] IS NULL OR escenario = ANY($1)) ORDER BY escenario", esc))
    return rows, len(rows)


async def _indicadores(conn, a):
    rows = db.filas(await conn.fetch("SELECT codigo, nombre, dimension, unidad, valor, meta, cumple_meta, periodo FROM api.v1_indicador "
                                     "WHERE ($1::text IS NULL OR dimension = $1) ORDER BY codigo", a.get("dimension")))
    for r in rows:
        r["periodo"] = str(r["periodo"]) if r.get("periodo") is not None else None
    return rows, len(rows)


async def _alertas(conn, a):
    rows = db.filas(await conn.fetch("SELECT regla, severidad, mensaje, generada_en, objeto FROM api.v1_alerta_abierta ORDER BY generada_en DESC"))
    return rows, len(rows)


async def _entidad(conn, a):
    rows = db.filas(await conn.fetch("SELECT esquema, nombre_tabla, nombre_negocio, tipo_entidad, descripcion_tabla, nombre_columna, tipo_dato, "
                                     "nulo, es_pk, es_fk, referencia, descripcion_columna FROM api.v1_diccionario WHERE nombre_tabla = $1 "
                                     "ORDER BY posicion", a["tabla"]))
    return rows, len(rows)


async def _registrar_dispositivo(conn, a):
    uid = await conn.fetchval("SELECT api.fn_registrar_dispositivo(p_codigo => $1, p_categoria => $2, p_peso_kg => $3, p_atributos => $4::jsonb)",
                              a["codigo"], a["categoria"], a["peso_kg"], a.get("atributos") or {})
    return {"uid": uid, "codigo": a["codigo"]}, 1


async def _solicitar(conn, a):
    uid = await conn.fetchval("SELECT api.fn_solicitar_recoleccion($1::uuid[], $2)", a["objetos"], a["centro_destino"])
    return {"solicitud": uid}, 1


HANDLERS: dict[str, Handler] = {
    "consultar_trazabilidad": _trazabilidad, "buscar_objetos": _buscar, "consultar_inventario": _inventario,
    "utilizacion_red": _utilizacion, "ejecutar_flujo_maximo": _flujo, "registrar_resultado_flujo": _registrar_flujo,
    "comparar_escenarios": _comparar, "consultar_indicadores": _indicadores, "alertas_abiertas": _alertas,
    "explicar_entidad": _entidad, "registrar_dispositivo": _registrar_dispositivo, "solicitar_recoleccion": _solicitar,
}


async def catalogo(usuario_uid: str, request_id: str | None = None) -> list[dict]:
    """tools/list para este usuario: cada uno ve solo las herramientas de sus roles."""
    async with db.transaccion(usuario_uid, "MCP", request_id, "mcp") as conn:
        return db.filas(await conn.fetch("SELECT nombre, titulo, descripcion, tipo, esquema_entrada, requiere_confirmacion "
                                         "FROM api.v1_mcp_catalogo ORDER BY tipo, nombre"))


async def ejecutar(usuario_uid: str, nombre: str, argumentos: dict, confirmado: bool = False, sesion: str | None = None,
                   request_id: str | None = None) -> dict:
    sesion = sesion or f"web-{uuid.uuid4().hex[:12]}"
    args = {k: v for k, v in (argumentos or {}).items() if not k.startswith("_")}
    async with db.transaccion(usuario_uid, "MCP", request_id, "mcp") as conn:
        aut = await conn.fetchval("SELECT api.fn_mcp_autorizar($1, $2::jsonb, $3)", nombre, {**args, "_confirmado": confirmado}, sesion)
        if not aut["autorizado"]:
            mensajes = {"PENDIENTE_CONFIRMACION": "Esta herramienta escribe en la plataforma: necesita tu confirmación explícita.",
                        "DENEGADO": "Tu rol no tiene acceso a esa herramienta (o no existe). El intento quedó registrado.",
                        "LIMITE_EXCEDIDO": "Superaste el límite de usos por minuto de esta herramienta."}
            return {"estado": aut["estado"], "mensaje": mensajes.get(aut["estado"], aut["estado"]), "herramienta": nombre, "argumentos": args}
        handler = HANDLERS.get(nombre)
        t0 = time.perf_counter()
        try:
            if handler is None:
                raise LookupError(f"La herramienta {nombre} está registrada pero no tiene implementación en este servidor")
            async with conn.transaction():                    # savepoint: un error no impide registrar la invocación
                resultado, n = await handler(conn, args)
        except (asyncpg.PostgresError, LookupError, KeyError, ValueError) as e:
            ms = int((time.perf_counter() - t0) * 1000)
            texto = getattr(e, "message", None) or str(e)
            await conn.execute("SELECT api.fn_mcp_registrar($1, $2, $3::jsonb, 'ERROR', NULL, $4, $5)", nombre, sesion, args, ms, texto[:500])
            return {"estado": "ERROR", "mensaje": texto, "codigo": getattr(e, "sqlstate", None), "herramienta": nombre, "argumentos": args}
        ms = int((time.perf_counter() - t0) * 1000)
        await conn.execute("SELECT api.fn_mcp_registrar($1, $2, $3::jsonb, 'OK', $4, $5, NULL)", nombre, sesion, args, n, ms)
        return {"estado": "OK", "herramienta": nombre, "argumentos": args, "resultado": resultado, "filas": n, "duracion_ms": ms}
