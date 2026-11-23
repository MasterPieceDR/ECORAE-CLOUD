"""Documentos operativos del ciclo de vida: cada endpoint llama a una función api.* que aplica RN-01…RN-09."""
from __future__ import annotations

from datetime import date, datetime
from typing import Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from .. import db
from ..seguridad import Sesion, sesion

router = APIRouter(prefix="/documentos", tags=["Documentos operativos"])
Uid = str


class SolicitudIn(BaseModel):
    objetos: list[Uid] = Field(min_length=1)
    centro_destino: str
    modalidad: Literal["RECOLECCION", "ENTREGA_DIRECTA"] = "RECOLECCION"
    fecha_preferida: date | None = None
    sector: str | None = Field(None, max_length=120)


class ProgramarIn(BaseModel):
    fecha: datetime
    transportista: str | None = Field(None, max_length=120)


class RecepcionIn(BaseModel):
    objetos: list[Uid] = Field(min_length=1)
    centro: str
    ubicacion: str | None = None
    evidencias: list[Uid] = Field(default_factory=list)
    conformidad: Literal["CONFORME", "OBSERVADA", "RECHAZADA"] = "CONFORME"
    solicitud: Uid | None = None
    peso_verificado: float | None = Field(None, gt=0)


class Criterio(BaseModel):
    criterio: str
    valor: bool | float | str
    cumple: bool


class EvaluacionIn(BaseModel):
    objeto: Uid
    clasificacion: str
    destino_sugerido: str
    funcional: bool
    criterios: list[Criterio] = Field(default_factory=list)
    modalidad: Literal["COMPLETA", "PRECLASIFICACION", "REEVALUACION"] = "COMPLETA"
    requiere_borrado: bool = False
    puntaje: float | None = Field(None, ge=0, le=100)
    motivo: str | None = None
    evidencias: list[Uid] = Field(default_factory=list)


class TransferenciaIn(BaseModel):
    objetos: list[Uid] = Field(min_length=1)
    nodo_origen: str
    nodo_destino: str
    ubicacion_destino: str | None = None
    criterio_asignacion: str | None = Field(None, max_length=200)
    transportista: str | None = Field(None, max_length=120)


class RecibirTransferenciaIn(BaseModel):
    evidencias: list[Uid] = Field(min_length=1)
    ubicacion: str | None = None


class Fraccion(BaseModel):
    material: str
    peso_kg: float = Field(gt=0)


class TratamientoIn(BaseModel):
    objeto: Uid
    tipo_tratamiento: str
    resultado: Literal["EXITOSO", "PARCIAL", "FALLIDO"]
    evidencias: list[Uid] = Field(default_factory=list)
    fracciones: list[Fraccion] = Field(default_factory=list)
    observacion: str | None = Field(None, max_length=500)


class CierreIn(BaseModel):
    objeto: Uid
    fecha_confirmacion: datetime | None = None
    evidencias: list[Uid] = Field(min_length=1)
    observacion: str | None = Field(None, max_length=500)


@router.get("")
async def listar(tipo: str | None = None, abiertos: bool = False, limite: int = 200, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        return db.filas(await conn.fetch("""
            SELECT uid, tipo_documento, numero, estado_documento, fecha_documento, fecha_cierre, centro, organizacion, responsable,
                   documento_referencia, items, objetos, estado_transferencia, nodo_origen, nodo_destino, modalidad, centro_destino,
                   fecha_preferida, observacion
              FROM api.v1_documento
             WHERE ($1::text IS NULL OR tipo_documento = $1)
               AND (NOT $2 OR estado_documento IN ('EMITIDO','EN_CURSO'))
             ORDER BY fecha_documento DESC LIMIT $3""", tipo, abiertos, min(limite, 500)))


async def _numero(conn, uid: str) -> dict:
    return {"uid": uid, "numero": await conn.fetchval("SELECT numero FROM api.v1_documento WHERE uid = $1", uid)}


@router.post("/solicitudes", status_code=201)
async def solicitar(d: SolicitudIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        uid = await conn.fetchval("SELECT api.fn_solicitar_recoleccion($1::uuid[], $2, $3, $4, $5)",
                                  d.objetos, d.centro_destino, d.modalidad, d.fecha_preferida, d.sector)
        return await _numero(conn, uid)


@router.post("/solicitudes/{uid}/programar", status_code=201)
async def programar(uid: Uid, d: ProgramarIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        r = await conn.fetchval("SELECT api.fn_programar_recoleccion($1::uuid, $2, $3)", uid, d.fecha, d.transportista)
        return await _numero(conn, r)


@router.post("/recepciones", status_code=201)
async def recibir(d: RecepcionIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        uid = await conn.fetchval("SELECT api.fn_recibir($1::uuid[], $2, $3, $4::uuid[], $5, $6::uuid, $7)",
                                  d.objetos, d.centro, d.ubicacion, d.evidencias, d.conformidad, d.solicitud, d.peso_verificado)
        return await _numero(conn, uid)


@router.post("/evaluaciones", status_code=201)
async def evaluar(d: EvaluacionIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        uid = await conn.fetchval("""SELECT api.fn_evaluar(p_objeto => $1::uuid, p_clasificacion => $2, p_destino_sugerido => $3,
                 p_funcional => $4, p_criterios => $5::jsonb, p_modalidad => $6, p_requiere_borrado => $7, p_puntaje => $8,
                 p_motivo => $9, p_evidencias => $10::uuid[])""",
                                  d.objeto, d.clasificacion, d.destino_sugerido, d.funcional, [c.model_dump() for c in d.criterios],
                                  d.modalidad, d.requiere_borrado, d.puntaje, d.motivo, d.evidencias)
        await conn.execute("SET CONSTRAINTS ALL IMMEDIATE")      # criterios obligatorios: el error llega aquí y no en el commit
        return await _numero(conn, uid)


@router.post("/transferencias", status_code=201)
async def transferir(d: TransferenciaIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        uid = await conn.fetchval("SELECT api.fn_transferir($1::uuid[], $2, $3, $4, $5, $6)",
                                  d.objetos, d.nodo_origen, d.nodo_destino, d.ubicacion_destino, d.criterio_asignacion, d.transportista)
        await conn.execute("SET CONSTRAINTS ALL IMMEDIATE")
        return await _numero(conn, uid)


@router.post("/transferencias/{uid}/recibir")
async def recibir_transferencia(uid: Uid, d: RecibirTransferenciaIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        await conn.execute("SELECT api.fn_recibir_transferencia($1::uuid, $2::uuid[], $3)", uid, d.evidencias, d.ubicacion)
        await conn.execute("SET CONSTRAINTS ALL IMMEDIATE")
        return await _numero(conn, uid)


@router.post("/tratamientos", status_code=201)
async def tratar(d: TratamientoIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        uid = await conn.fetchval("SELECT api.fn_registrar_tratamiento($1::uuid, $2, $3, $4::uuid[], $5::jsonb, $6)",
                                  d.objeto, d.tipo_tratamiento, d.resultado, d.evidencias,
                                  [f.model_dump() for f in d.fracciones], d.observacion)
        await conn.execute("SET CONSTRAINTS ALL IMMEDIATE")
        return await _numero(conn, uid)


@router.post("/cierres", status_code=201)
async def cerrar(d: CierreIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        uid = await conn.fetchval("SELECT api.fn_cerrar_trazabilidad($1::uuid, coalesce($2::timestamptz, now()), $3::uuid[], $4)",
                                  d.objeto, d.fecha_confirmacion, d.evidencias, d.observacion)
        await conn.execute("SET CONSTRAINTS ALL IMMEDIATE")
        return await _numero(conn, uid)
