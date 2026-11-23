"""Auditoría (AUDITORIA.CONSULTAR) y administración de usuarios y roles (USUARIO.ADMINISTRAR)."""
from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from .. import db
from ..seguridad import Sesion, sesion

router = APIRouter(tags=["Gobierno"])


@router.get("/auditoria/cambios")
async def cambios(tabla: str | None = None, codigo: str | None = None, desde: datetime | None = None,
                  limite: int = Query(100, le=500), s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        return await conn.fetchval("SELECT api.fn_auditoria($1, $2, $3, $4)", limite, tabla, codigo, desde)


@router.get("/auditoria/objetos/{codigo}/en")
async def objeto_en(codigo: str, instante: datetime, s: Sesion = Depends(sesion)):
    """Reconstrucción del estado de un objeto en un instante pasado, desde la auditoría."""
    async with s.tx() as conn:
        return await conn.fetchval("SELECT api.fn_objeto_en($1, $2)", codigo, instante)


@router.get("/auditoria/mcp")
async def bitacora_mcp(limite: int = Query(100, le=500), s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        return await conn.fetchval("SELECT api.fn_bitacora_mcp($1)", limite)


@router.get("/auditoria/seguridad")
async def seguridad(limite: int = Query(100, le=500), s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        return await conn.fetchval("SELECT api.fn_eventos_seguridad($1)", limite)


@router.get("/gobierno/decisiones")
async def decisiones(s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        return db.filas(await conn.fetch("SELECT codigo, titulo, contexto, decision, consecuencias, materias, estado, fecha "
                                         "FROM gob.decision_arquitectura ORDER BY codigo"))


class RolIn(BaseModel):
    rol: str
    centro: str | None = None
    motivo: str = Field(min_length=5, max_length=300)


class RevocarIn(BaseModel):
    motivo: str = Field(min_length=5, max_length=300)


@router.get("/usuarios")
async def usuarios(s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        return await conn.fetchval("SELECT api.fn_listar_usuarios()")


@router.post("/usuarios/{uid}/roles", status_code=201)
async def asignar(uid: str, d: RolIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        await conn.execute("SELECT api.fn_asignar_rol($1::uuid, $2, $3, $4)", uid, d.rol, d.centro, d.motivo)
    return {"ok": True}


@router.post("/usuarios/{uid}/roles/{rol}/revocar")
async def revocar(uid: str, rol: str, d: RevocarIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        await conn.execute("SELECT api.fn_revocar_rol($1::uuid, $2, $3)", uid, rol, d.motivo)
    return {"ok": True}


# ---- Solicitudes de rol: el usuario nuevo pide acceso y el administrador decide ----
class SolicitudIn(BaseModel):
    rol: str
    centro: str | None = None
    motivo: str = Field(min_length=10, max_length=500)


class ResolverIn(BaseModel):
    aprobar: bool
    respuesta: str | None = Field(None, max_length=500)


@router.get("/solicitudes-rol")
async def solicitudes(pendientes: bool = False, s: Sesion = Depends(sesion)):
    """Administrador: todas las del ecosistema. Cualquier otro usuario: solo las suyas."""
    async with s.tx() as conn:
        return await conn.fetchval("SELECT api.fn_solicitudes_rol($1)", pendientes)


@router.post("/solicitudes-rol", status_code=201)
async def solicitar(d: SolicitudIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        uid = await conn.fetchval("SELECT api.fn_solicitar_rol($1, $2, $3)", d.rol, d.centro or None, d.motivo)
    return {"uid": uid}


@router.post("/solicitudes-rol/{uid}/cancelar")
async def cancelar(uid: str, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        await conn.execute("SELECT api.fn_cancelar_solicitud_rol($1::uuid)", uid)
    return {"ok": True}


@router.post("/solicitudes-rol/{uid}/resolver")
async def resolver(uid: str, d: ResolverIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        await conn.execute("SELECT api.fn_resolver_solicitud_rol($1::uuid, $2, $3)", uid, d.aprobar, d.respuesta)
    return {"ok": True}
