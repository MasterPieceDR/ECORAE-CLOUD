"""Asistente del frontend: herramientas MCP (modo herramientas) y chat con Claude (si está configurado)."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from ..asistente import chat, herramientas
from ..seguridad import Sesion, sesion

router = APIRouter(prefix="/asistente", tags=["Asistente MCP"])


class EjecutarIn(BaseModel):
    herramienta: str
    argumentos: dict = Field(default_factory=dict)
    confirmado: bool = False
    sesion: str | None = None


class Confirmacion(BaseModel):
    tool_use_id: str
    aprobado: bool


class ChatIn(BaseModel):
    historial: list[dict] = Field(default_factory=list)
    mensaje: str | None = Field(None, max_length=2000)
    confirmacion: Confirmacion | None = None
    sesion: str = Field(min_length=4, max_length=60)


@router.get("/herramientas")
async def listar(s: Sesion = Depends(sesion)):
    return {"herramientas": await herramientas.catalogo(s.uid, s.request_id), "chat_disponible": chat.disponible()}


@router.post("/ejecutar")
async def ejecutar(d: EjecutarIn, s: Sesion = Depends(sesion)):
    return await herramientas.ejecutar(s.uid, d.herramienta, d.argumentos, d.confirmado, d.sesion, s.request_id)


@router.post("/chat")
async def conversar(d: ChatIn, s: Sesion = Depends(sesion)):
    historial = list(d.historial)
    if d.mensaje and not d.confirmacion:
        historial.append({"role": "user", "content": [{"type": "text", "text": d.mensaje}]})
    return await chat.conversar(s.uid, historial, d.sesion, s.request_id,
                                d.confirmacion.model_dump() if d.confirmacion else None)
