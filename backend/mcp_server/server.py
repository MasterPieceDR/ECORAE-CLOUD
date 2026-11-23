"""EcoRAEE Cloud — servidor MCP estándar (Streamable HTTP) para clientes externos: Claude Desktop, Claude Code u otros.

- Autenticación: el mismo JWT de la plataforma (Authorization: Bearer …). Sin token no hay herramientas.
- tools/list: sale de api.v1_mcp_catalogo, filtrado por los roles del usuario (ADR-006).
- tools/call: pasa por el mismo ejecutor que el panel web (autorización, confirmación, límite y bitácora en la base),
  con el login ecoraee_mcp_svc, que solo puede ejecutar lo registrado en mcp.herramienta.
- Las herramientas que escriben exigen el argumento "_confirmado": true, que el cliente solo debe enviar tras preguntar.

Ejecutar:  uvicorn mcp_server.server:app --port 8001     (endpoint: http://localhost:8001/mcp)
"""
from __future__ import annotations

import json
import uuid

import mcp_types as types
from mcp.server.lowlevel import Server
from mcp.server.transport_security import TransportSecuritySettings

from app import db
from app.asistente import herramientas
from app.errores import ErrorAPI
from app.seguridad import _uid_desde_token

_listo = False


async def _db() -> None:
    global _listo
    if not _listo:
        await db.abrir()
        _listo = True


async def _usuario(ctx) -> str:
    req = getattr(ctx, "request", None)
    cabecera = req.headers.get("authorization", "") if req is not None else ""
    if not cabecera.lower().startswith("bearer "):
        raise PermissionError("Falta el token de EcoRAEE (Authorization: Bearer …)")
    try:
        return await _uid_desde_token(cabecera.split(" ", 1)[1])
    except ErrorAPI as e:
        raise PermissionError(e.detalle)


def _texto(datos) -> list[types.TextContent]:
    return [types.TextContent(type="text", text=json.dumps(datos, ensure_ascii=False, default=str, indent=1))]


async def listar_herramientas(ctx, params) -> types.ListToolsResult:
    await _db()
    uid = await _usuario(ctx)
    tools = []
    for h in await herramientas.catalogo(uid):
        esquema = dict(h["esquema_entrada"])
        if h["requiere_confirmacion"]:
            esquema.setdefault("properties", {})["_confirmado"] = {
                "type": "boolean", "description": "true solo después de que la persona confirme la acción (escritura)."}
        tools.append(types.Tool(name=h["nombre"], title=h["titulo"], inputSchema=esquema,
                                description=h["descripcion"] + (" Requiere confirmación humana." if h["requiere_confirmacion"] else "")))
    return types.ListToolsResult(tools=tools)


async def llamar_herramienta(ctx, params) -> types.CallToolResult:
    await _db()
    try:
        uid = await _usuario(ctx)
    except PermissionError as e:
        return types.CallToolResult(content=_texto({"estado": "NO_AUTENTICADO", "mensaje": str(e)}), isError=True)
    args = dict(params.arguments or {})
    confirmado = bool(args.pop("_confirmado", False))
    sesion = f"mcp-{(ctx.request.headers.get('mcp-session-id') if getattr(ctx, 'request', None) else None) or uuid.uuid4().hex[:12]}"
    r = await herramientas.ejecutar(uid, params.name, args, confirmado, sesion[:60])
    return types.CallToolResult(content=_texto(r), isError=r["estado"] not in ("OK", "PENDIENTE_CONFIRMACION"))


async def listar_recursos(ctx, params) -> types.ListResourcesResult:
    recursos = [types.Resource(uri="ecoraee://glosario", name="Glosario maestro", mimeType="application/json",
                               description="Términos con su equivalencia en las cinco materias")]
    recursos += [types.Resource(uri=f"ecoraee://escenario/E{i}", name=f"Escenario E{i}", mimeType="application/json",
                                description="Último flujo máximo y cortes mínimos registrados") for i in range(5)]
    return types.ListResourcesResult(resources=recursos)


async def leer_recurso(ctx, params) -> types.ReadResourceResult:
    await _db()
    uid = await _usuario(ctx)
    async with db.transaccion(uid, "MCP", None, "mcp") as conn:
        datos = await conn.fetchval("SELECT api.fn_mcp_leer_recurso($1)", str(params.uri))
    return types.ReadResourceResult(contents=[types.TextResourceContents(uri=str(params.uri), mimeType="application/json",
                                                                         text=json.dumps(datos, ensure_ascii=False, default=str))])


servidor = Server("ecoraee-cloud", version="1.0.0", title="EcoRAEE Cloud",
                  instructions="Trazabilidad de residuos electrónicos. Datos sintéticos. Las escrituras requieren confirmación humana.",
                  on_list_tools=listar_herramientas, on_call_tool=llamar_herramienta,
                  on_list_resources=listar_recursos, on_read_resource=leer_recurso)

app = servidor.streamable_http_app(streamable_http_path="/mcp", stateless_http=True, json_response=True, host="0.0.0.0",
                                   transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False))
