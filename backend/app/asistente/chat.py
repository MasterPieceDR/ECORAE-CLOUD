"""Asistente conversacional con Claude sobre las mismas herramientas MCP (opcional: requiere ANTHROPIC_API_KEY).

El estado de la conversación lo guarda el navegador (el servidor es stateless). Cuando Claude pide una herramienta
que escribe, el ciclo se detiene y devuelve la acción pendiente: solo continúa si la persona la confirma (ADR-006).
"""
from __future__ import annotations

import json
from typing import Any

from ..config import config
from ..errores import ErrorAPI
from . import herramientas

SISTEMA = """Eres el asistente de EcoRAEE Cloud, la plataforma de trazabilidad de residuos electrónicos de una red circular.
Responde en español, breve y claro. Usa SOLO las herramientas para consultar datos: nunca inventes códigos, cifras ni estados.
Si una herramienta devuelve DENEGADO, explica que el rol del usuario no tiene ese acceso. Las acciones que escriben requieren
confirmación del usuario; evaluar, transferir, cerrar y descargar evidencias no están disponibles aquí: indica que se hacen
en la ficha del equipo. Los datos son sintéticos."""
MAX_PASOS = 6


def disponible() -> bool:
    return bool(config().anthropic_api_key)


def _cliente():
    import anthropic
    return anthropic.AsyncAnthropic(api_key=config().anthropic_api_key)


def _texto(resultado: dict) -> str:
    return json.dumps(resultado, ensure_ascii=False, default=str)[:20000]


async def conversar(usuario_uid: str, historial: list[dict], sesion: str, request_id: str | None,
                    confirmacion: dict | None = None, cliente: Any = None) -> dict:
    """historial: mensajes en formato de la API de Anthropic. confirmacion: {'tool_use_id', 'aprobado'} para una acción pendiente."""
    if cliente is None:
        if not disponible():
            raise ErrorAPI(503, "El chat con Claude no está configurado (ANTHROPIC_API_KEY). Usa el modo herramientas.", "CHAT")
        cliente = _cliente()
    catalogo = await herramientas.catalogo(usuario_uid, request_id)
    tools = [{"name": h["nombre"], "description": f"{h['titulo']}. {h['descripcion']}", "input_schema": h["esquema_entrada"]} for h in catalogo]
    escritura = {h["nombre"] for h in catalogo if h["requiere_confirmacion"]}
    mensajes = list(historial)
    eventos: list[dict] = []

    if confirmacion:                                     # resolver la acción que quedó pendiente
        ultimo = mensajes[-1]
        uso = next(b for b in ultimo["content"] if b.get("type") == "tool_use" and b["id"] == confirmacion["tool_use_id"])
        if confirmacion.get("aprobado"):
            r = await herramientas.ejecutar(usuario_uid, uso["name"], uso["input"], True, sesion, request_id)
        else:
            r = {"estado": "RECHAZADO_POR_USUARIO", "mensaje": "La persona no autorizó la acción."}
        eventos.append({"tipo": "herramienta", "herramienta": uso["name"], "argumentos": uso["input"], "estado": r["estado"]})
        mensajes.append({"role": "user", "content": [{"type": "tool_result", "tool_use_id": uso["id"], "content": _texto(r)}]})

    for _ in range(MAX_PASOS):
        resp = await cliente.messages.create(model=config().anthropic_modelo, max_tokens=1500, system=SISTEMA, tools=tools, messages=mensajes)
        bloques = [b.model_dump() if hasattr(b, "model_dump") else dict(b) for b in resp.content]
        bloques = [{k: v for k, v in b.items() if k in ("type", "text", "id", "name", "input")} for b in bloques]
        mensajes.append({"role": "assistant", "content": bloques})
        usos = [b for b in bloques if b["type"] == "tool_use"]
        if resp.stop_reason != "tool_use" or not usos:
            texto = "".join(b.get("text", "") for b in bloques if b["type"] == "text")
            return {"respuesta": texto, "historial": mensajes, "eventos": eventos, "pendiente": None}
        resultados = []
        for u in usos:
            if u["name"] in escritura:                   # nunca se escribe sin que la persona confirme
                texto = "".join(b.get("text", "") for b in bloques if b["type"] == "text")
                return {"respuesta": texto, "historial": mensajes, "eventos": eventos,
                        "pendiente": {"tool_use_id": u["id"], "herramienta": u["name"], "argumentos": u["input"]}}
            r = await herramientas.ejecutar(usuario_uid, u["name"], u["input"], False, sesion, request_id)
            eventos.append({"tipo": "herramienta", "herramienta": u["name"], "argumentos": u["input"], "estado": r["estado"]})
            resultados.append({"type": "tool_result", "tool_use_id": u["id"], "content": _texto(r)})
        mensajes.append({"role": "user", "content": resultados})
    return {"respuesta": "Detuve la consulta porque necesitaba demasiados pasos. Reformula la pregunta, por favor.",
            "historial": mensajes, "eventos": eventos, "pendiente": None}
