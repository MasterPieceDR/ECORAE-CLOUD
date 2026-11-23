"""Objetos trazables (dispositivos y lotes): listado, ficha completa, registro, lotes y bandeja de tareas."""
from __future__ import annotations

import asyncpg
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from .. import acciones, db
from ..errores import ErrorAPI
from ..seguridad import Perfil, Sesion, perfil, sesion

router = APIRouter(tags=["Trazabilidad"])

PREFIJO = {"PORTATIL": "LAP", "ESCRITORIO": "ESC", "MONITOR": "MON", "CELULAR": "CEL", "TABLET": "TAB", "IMPRESORA": "IMP",
           "EQUIPO_RED": "RTR", "BATERIA": "BAT", "DISCO": "DSK", "PLACA": "PLC", "PEQ_ELECTRO": "PEQ"}


async def contexto(conn, p: Perfil | None = None) -> acciones.Contexto:
    p = p or await perfil(conn)
    return acciones.Contexto(
        perfil=p, catalogos=await conn.fetchval("SELECT api.fn_catalogos()"),
        aristas=db.filas(await conn.fetch("SELECT origen, destino, activa, requiere_excepcion, capacidad_und FROM api.v1_red_arista")),
        nodos=db.filas(await conn.fetch("SELECT codigo, nombre, tipo, centro, organizacion FROM api.v1_red_nodo WHERE activo")))


async def operativo(conn, codigo: str) -> dict:
    fila = await conn.fetchrow("SELECT * FROM api.v1_objeto_operativo WHERE codigo = $1", codigo)
    if not fila:
        raise ErrorAPI(404, f"El objeto {codigo} no existe o no tienes acceso a él", "EC404")
    return dict(fila)


@router.get("/objetos")
async def listar(q: str | None = None, estado: str | None = None, clasificacion: str | None = None, tipo: str | None = None,
                 centro: str | None = None, con_tareas: bool = False, limite: int = Query(100, le=500), desde: int = 0,
                 s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        termino = f"%{q.strip()}%" if q and q.strip() else None
        rows = db.filas(await conn.fetch("""
            SELECT * FROM api.v1_objeto_operativo
             WHERE ($1::text IS NULL OR codigo ILIKE $1 OR categoria_nombre ILIKE $1 OR marca ILIKE $1 OR lote_codigo ILIKE $1
                    OR organizacion_origen_nombre ILIKE $1)
               AND ($2::text IS NULL OR estado = $2) AND ($3::text IS NULL OR clasificacion = $3)
               AND ($4::text IS NULL OR tipo_objeto = $4) AND ($5::text IS NULL OR centro_actual = $5)
             ORDER BY ultimo_movimiento DESC NULLS LAST, codigo LIMIT $6 OFFSET $7""",
            termino, estado, clasificacion, tipo, centro, limite, desde))
        cx = await contexto(conn)
        for r in rows:
            calc = acciones.calcular(r, cx)["acciones"]
            r["acciones"] = [a["codigo"] for a in calc]
            r["tareas"] = [a["codigo"] for a in calc if a["tarea"]]
        if con_tareas:
            rows = [r for r in rows if r["tareas"]]
        total = await conn.fetchval("SELECT count(*) FROM api.v1_objeto_operativo")
    return {"total": total, "objetos": rows}


@router.get("/tareas")
async def tareas(s: Sesion = Depends(sesion)):
    """Bandeja de trabajo: lo que este usuario puede hacer ahora, agrupado por acción."""
    async with s.tx() as conn:
        cx = await contexto(conn)
        rows = db.filas(await conn.fetch("SELECT * FROM api.v1_objeto_operativo WHERE estado NOT IN ('CERRADO','ANULADO','DESAGRUPADO') "
                                         "ORDER BY ultimo_movimiento LIMIT 500"))
    grupos: dict[str, dict] = {}
    for r in rows:
        for a in acciones.calcular(r, cx)["acciones"]:
            if not a["tarea"]:
                continue
            g = grupos.setdefault(a["codigo"], {"codigo": a["codigo"], "titulo": a["titulo"], "objetos": []})
            g["objetos"].append({"codigo": r["codigo"], "tipo_objeto": r["tipo_objeto"], "estado": r["estado"],
                                 "categoria_nombre": r["categoria_nombre"], "centro_actual": r["centro_actual"],
                                 "ultimo_movimiento": r["ultimo_movimiento"]})
    return {"total": sum(len(g["objetos"]) for g in grupos.values()), "grupos": list(grupos.values())}


@router.get("/objetos/{codigo}")
async def ficha(codigo: str, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        o = await operativo(conn, codigo)
        linea = await conn.fetchval("SELECT api.fn_linea_trazabilidad($1)", codigo)
        disp = await conn.fetchrow("SELECT * FROM api.v1_dispositivo WHERE codigo = $1", codigo)
        miembros = db.filas(await conn.fetch("SELECT objeto, objeto_uid, tipo_objeto, estado, desde, hasta, vigente "
                                             "FROM api.v1_lote_miembro WHERE lote = $1 ORDER BY vigente DESC, objeto", codigo))
        lotes = db.filas(await conn.fetch("SELECT lote, lote_uid, desde, hasta, vigente FROM api.v1_lote_miembro WHERE objeto = $1 "
                                          "ORDER BY desde DESC", codigo))
        evidencias = db.filas(await conn.fetch("""
            SELECT DISTINCT ON (uid) uid, tipo, tipo_nombre, mime, tamano_bytes, subido_en, subido_por, documento, tipo_documento, nivel_acceso
              FROM api.v1_evidencia
             WHERE objeto = $1 OR $1 = ANY(string_to_array(objetos_relacionados, ','))
             ORDER BY uid, subido_en""", codigo))
        # documentos con ítems del objeto (o de su lote) y los que aparecen en su línea de tiempo (p. ej. evaluaciones)
        numeros = [p["documento"] for p in (linea or {}).get("pasos") or [] if p.get("documento")]
        codigos = [codigo] + ([o["lote_codigo"]] if o.get("lote_codigo") else [])
        documentos = db.filas(await conn.fetch("""
            SELECT uid, tipo_documento, numero, estado_documento, fecha_documento, centro, responsable, estado_transferencia,
                   nodo_origen, nodo_destino FROM api.v1_documento
             WHERE objetos ?| $1::text[] OR numero = ANY($2::text[]) ORDER BY fecha_documento, numero""", codigos, numeros))
        cx = await contexto(conn)
        disponibles = acciones.calcular(o, cx)
        # CRUD: mientras está REGISTRADO, quien lo registró (o su organización) puede corregirlo o anularlo
        if o["tipo_objeto"] == "DISPOSITIVO" and await conn.fetchval("SELECT api.fn_puede_corregir($1::uuid)", o["uid"]):
            disponibles["acciones"] += [
                acciones._accion("EDITAR", "Corregir datos del equipo", "Solo mientras nadie lo ha recogido. El cambio queda auditado "
                                 "y el motivo en un documento de ajuste.", "OBJETO.REGISTRAR", tarea=False),
                acciones._accion("ANULAR", "Anular registro", "Eliminación lógica para registros duplicados o erróneos: el equipo pasa a "
                                 "«Anulado» y nada se borra del historial (RN-01).", "OBJETO.ANULAR", tarea=False)]
    evidencias.sort(key=lambda e: e["subido_en"])
    return {"objeto": o, "dispositivo": dict(disp) if disp else None, "linea": linea, "miembros": miembros, "lotes": lotes,
            "evidencias": evidencias, "documentos": documentos, **disponibles}


class DispositivoIn(BaseModel):
    codigo: str | None = Field(None, pattern=r"^[A-Z0-9][A-Z0-9_\-\.]{1,39}$")
    categoria: str
    peso_kg: float = Field(gt=0, le=2000)
    contiene_almacenamiento: bool = False
    marca: str | None = None
    modelo: str | None = None
    numero_serie: str | None = Field(None, max_length=80)
    anio: int | None = Field(None, ge=1970, le=2100)
    atributos: dict = Field(default_factory=dict)
    organizacion_origen: str | None = None          # uid; solo un operador registra en nombre de otra organización


@router.post("/objetos/dispositivos", status_code=201)
async def registrar(d: DispositivoIn, s: Sesion = Depends(sesion)):
    for intento in range(5):
        codigo = d.codigo
        try:
            async with s.tx() as conn:
                if not codigo:
                    pref = PREFIJO.get(d.categoria, "RAE")
                    n = await conn.fetchval(r"SELECT coalesce(max(substring(codigo from '\d+$')::int), 1000) + 1 + $2 FROM api.v1_objeto "
                                            "WHERE codigo LIKE $1 || '-%'", pref, intento)
                    codigo = f"{pref}-{n}"
                uid = await conn.fetchval("""SELECT api.fn_registrar_dispositivo(p_codigo => $1, p_categoria => $2, p_peso_kg => $3,
                         p_contiene_almacenamiento => $4, p_marca => $5, p_modelo => $6, p_numero_serie => $7, p_anio => $8,
                         p_atributos => $9::jsonb, p_organizacion_origen => $10::uuid)""",
                                          codigo, d.categoria, d.peso_kg, d.contiene_almacenamiento, d.marca, d.modelo,
                                          d.numero_serie or None, d.anio, d.atributos, d.organizacion_origen)
            return {"uid": uid, "codigo": codigo}
        except asyncpg.UniqueViolationError as e:
            if d.codigo or "codigo" not in (getattr(e, "constraint_name", "") or ""):
                raise
    raise ErrorAPI(409, "No se pudo asignar un código libre; indícalo manualmente", "EC409")


class DispositivoUpd(BaseModel):
    peso_kg: float = Field(gt=0, le=2000)
    contiene_almacenamiento: bool = False
    marca: str | None = None
    modelo: str | None = Field(None, max_length=120)
    numero_serie: str | None = Field(None, max_length=80)
    anio: int | None = Field(None, ge=1970, le=2100)
    atributos: dict = Field(default_factory=dict)
    motivo: str = Field(min_length=5, max_length=300)


class AnularIn(BaseModel):
    motivo: str = Field(min_length=5, max_length=300)


@router.put("/objetos/dispositivos/{uid}")
async def actualizar(uid: str, d: DispositivoUpd, s: Sesion = Depends(sesion)):
    """UPDATE del CRUD: corrige los datos mientras el equipo está REGISTRADO (la base lo valida)."""
    async with s.tx() as conn:
        await conn.execute("SELECT api.fn_actualizar_dispositivo($1::uuid, $2, $3, $4, $5, $6, $7, $8::jsonb, $9)", uid, d.peso_kg,
                           d.contiene_almacenamiento, d.marca or None, d.modelo or None, d.numero_serie, d.anio, d.atributos, d.motivo)
    return {"ok": True}


@router.delete("/objetos/{uid}")
async def anular(uid: str, d: AnularIn, s: Sesion = Depends(sesion)):
    """DELETE del CRUD: anulación lógica (REGISTRADO → ANULADO con documento AJUSTE). Nada se borra físicamente."""
    async with s.tx() as conn:
        numero = await conn.fetchval("SELECT api.fn_anular_objeto($1::uuid, $2)", uid, d.motivo)
    return {"ok": True, "numero": numero}


class LoteIn(BaseModel):
    codigo: str = Field(pattern=r"^[A-Z0-9][A-Z0-9_\-\.]{1,39}$")
    proposito: str = Field("RECEPCION", pattern="^(RECEPCION|TRANSFERENCIA|TRATAMIENTO|ASIGNACION)$")
    objetos: list[str] = Field(min_length=1)
    descripcion: str | None = None
    peso_declarado: float | None = Field(None, gt=0)


@router.post("/objetos/lotes", status_code=201)
async def crear_lote(l: LoteIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        uid = await conn.fetchval("SELECT api.fn_crear_lote($1, $2, $3::uuid[], $4, $5)",
                                  l.codigo, l.proposito, l.objetos, l.descripcion, l.peso_declarado)
    return {"uid": uid, "codigo": l.codigo}


class DesagruparIn(BaseModel):
    observacion: str | None = None


@router.post("/objetos/lotes/{uid}/desagrupar")
async def desagrupar(uid: str, d: DesagruparIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        await conn.execute("SELECT api.fn_desagrupar_lote($1::uuid, $2)", uid, d.observacion)
    return {"ok": True}


@router.get("/lotes")
async def lotes(s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        return db.filas(await conn.fetch("SELECT * FROM api.v1_lote_resumen ORDER BY codigo"))
