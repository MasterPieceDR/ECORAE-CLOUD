"""Casos de prueba del enunciado ejecutados a través de la API (CP-01…CP-14, RN-xx, RNF-10, MCP)."""
from __future__ import annotations

import pytest

from conftest import jpeg_con_gps

pytestmark = pytest.mark.asyncio(loop_scope="session")


async def uid_de(actor, codigo):
    r = await actor.get(f"/objetos/{codigo}")
    assert r.status_code == 200, r.text
    return r.json()["objeto"]["uid"]


# ---------------------------------------------------------------- identidad
async def test_login_incorrecto_y_sin_token(cliente):
    r = await cliente.post("/auth/login", json={"correo": "coordinador@ejemplo.invalid", "password": "mala"})
    assert r.status_code == 401 and r.json()["codigo"] == "EC401"
    r = await cliente.get("/tareas")
    assert r.status_code == 401
    r = await cliente.get("/tareas", headers={"Authorization": "Bearer xxx"})
    assert r.status_code == 401


async def test_perfil_con_permisos_heredados(actores):
    p = (await actores["coordinador"].get("/auth/me")).json()
    assert "OPERADOR_CENTRO" in p["roles_efectivos"] and "USUARIO_BASE" in p["roles_efectivos"]
    codigos = {x["codigo"] for x in p["permisos"]}
    assert {"RED.EJECUTAR_FLUJO", "RECEPCION.REGISTRAR", "INDICADOR.CONSULTAR"} <= codigos
    p = (await actores["tecnico.e1"].get("/auth/me")).json()
    assert {"codigo": "EVALUACION.REGISTRAR", "centro": "E1"} in p["permisos"]


async def test_registro_y_asignacion_de_rol_con_segregacion(cliente, actores):
    r = await cliente.post("/auth/registro", json={"alias": "ana.prueba", "correo": "ana@ejemplo.invalid", "password": "Clave-segura-1",
                                                   "organizacion": "GEN-MUNI"})
    assert r.status_code == 201, r.text
    nuevo = r.json()["usuario"]
    assert nuevo["roles_efectivos"] == ["USUARIO_BASE"]
    admin = actores["admin"]
    assert (await admin.post(f"/usuarios/{nuevo['uid']}/roles", {"rol": "GENERADOR", "motivo": "Responsable del punto limpio"})).status_code == 201
    r = await admin.post(f"/usuarios/{nuevo['uid']}/roles", {"rol": "TECNICO_EVALUADOR", "centro": "E1", "motivo": "Prueba de segregación"})
    assert r.status_code in (403, 409, 422), r.text            # SoD: GENERADOR y TECNICO_EVALUADOR son incompatibles
    r = await actores["coordinador"].post(f"/usuarios/{nuevo['uid']}/roles", {"rol": "AUDITOR", "motivo": "Sin permiso"})
    assert r.status_code == 403


# ---------------------------------------------------------------- CP-01 acceso por rol y RLS
async def test_cp01_visibilidad_y_permisos(actores):
    assert (await actores["gen.municipio"].get("/objetos")).json()["total"] == 3          # solo lo de su organización
    assert (await actores["beneficiario"].get("/objetos")).json()["total"] == 2           # solo lo asignado
    assert (await actores["gen.municipio"].get("/objetos/LAP-1001")).status_code == 404   # RLS: no existe para él
    assert (await actores["coordinador"].get("/auditoria/cambios")).status_code == 403
    assert (await actores["auditor"].get("/auditoria/cambios?codigo=LAP-1001")).status_code == 200
    assert (await actores["operador.c1"].get("/red/escenarios/E0/flujo")).status_code == 403
    assert (await actores["comite"].get("/red/escenarios/E0/flujo")).status_code == 200
    r = await actores["comite"].post("/red/escenarios/E0/flujo")                          # analiza, pero no registra
    assert r.status_code == 403 and "RED.EJECUTAR_FLUJO" in r.json()["detail"]


# ---------------------------------------------------------------- CP-07/08/09 flujo máximo desde RDS
@pytest.mark.parametrize("escenario,valor,cortes", [("E0", 200, 1), ("E1", 225, 3), ("E2", 200, 1), ("E3", 175, 2), ("E4", 280, 1)])
async def test_cp09_flujo_desde_la_base(actores, escenario, valor, cortes):
    r = (await actores["coordinador"].post(f"/red/escenarios/{escenario}/flujo")).json()
    assert r["flujo_maximo"] == valor and len(r["cortes"]) == cortes and r["registrado"] and r["ejecucion_id"]
    assert all(c["capacidad"] == valor for c in r["cortes"])                              # flujo máximo = corte mínimo
    for n in ("G1", "C1", "C2", "R1", "K1", "B1", "D1"):                                    # conservación
        entra = sum(a["flujo"] for a in r["aristas"] + r["virtuales"] if a["destino"] == n)
        sale = sum(a["flujo"] for a in r["aristas"] + r["virtuales"] if a["origen"] == n)
        assert abs(entra - sale) < 1e-6, n


# ---------------------------------------------------------------- ciclo completo por la API (CP-02, CP-03, CP-14)
async def test_ciclo_completo_por_api(actores):
    gen, coord, c2, e1, tec, gk1 = (actores[a] for a in ("gen.municipio", "coordinador", "operador.c2", "operador.e1", "tecnico.e1", "gestor.k1"))
    r = await gen.post("/objetos/dispositivos", {"categoria": "MONITOR", "peso_kg": 3.5, "marca": "LG", "atributos": {"pulgadas": 19}})
    assert r.status_code == 201, r.text
    codigo, uid = r.json()["codigo"], r.json()["uid"]
    assert codigo.startswith("MON-")
    # CP-02: atributos obligatorios de la categoría
    r = await gen.post("/objetos/dispositivos", {"categoria": "MONITOR", "peso_kg": 3})
    assert r.status_code == 422
    ficha = (await gen.get(f"/objetos/{codigo}")).json()
    assert [a["codigo"] for a in ficha["acciones"]] == ["SOLICITAR_RECOLECCION", "EDITAR", "ANULAR"]   # + corregir o anular mientras está REGISTRADO

    sol = (await gen.post("/documentos/solicitudes", {"objetos": [uid], "centro_destino": "C2", "sector": "Prueba"})).json()
    assert sol["numero"].startswith("SOL-")
    assert (await c2.post("/documentos/recepciones", {"objetos": [uid], "centro": "C2"})).status_code == 409   # CP-03: aún no recolectado
    assert (await coord.post(f"/documentos/solicitudes/{sol['uid']}/programar", {"fecha": "2026-12-01T10:00:00Z"})).status_code == 201

    # RN-03: recepción sin evidencia rechazada
    r = await c2.post("/documentos/recepciones", {"objetos": [uid], "centro": "C2", "ubicacion": "BOD-A", "solicitud": sol["uid"]})
    assert r.status_code == 422
    foto = await c2.evidencia("FOTO_RECEPCION", "image/png")
    r = await c2.post("/documentos/recepciones", {"objetos": [uid], "centro": "C2", "ubicacion": "BOD-A", "evidencias": [foto], "solicitud": sol["uid"]})
    assert r.status_code == 201, r.text

    # transferencia a evaluación y confirmación
    trf = (await coord.post("/documentos/transferencias", {"objetos": [uid], "nodo_origen": "C2", "nodo_destino": "E1", "ubicacion_destino": "LAB"})).json()
    acciones_e1 = [a["codigo"] for a in (await e1.get(f"/objetos/{codigo}")).json()["acciones"]]
    assert acciones_e1 == ["RECIBIR_TRANSFERENCIA"]
    guia = await e1.evidencia("GUIA_REMISION")
    assert (await e1.post(f"/documentos/transferencias/{trf['uid']}/recibir", {"evidencias": [guia]})).status_code == 200

    # RN-02: solo el técnico evalúa; criterios obligatorios
    criterios = [{"criterio": "ENCIENDE", "valor": False, "cumple": False}, {"criterio": "DANO_FISICO", "valor": True, "cumple": False}]
    cuerpo = {"objeto": uid, "clasificacion": "RECICLABLE", "destino_sugerido": "RECICLAJE", "funcional": False, "criterios": criterios}
    assert (await e1.post("/documentos/evaluaciones", cuerpo)).status_code == 403
    r = await tec.post("/documentos/evaluaciones", {**cuerpo, "criterios": criterios[:1]})
    assert r.status_code == 422, r.text
    assert (await tec.post("/documentos/evaluaciones", cuerpo)).status_code == 201

    # RN-04: un reciclable no va a reacondicionamiento; sí a reciclaje
    ficha = (await coord.get(f"/objetos/{codigo}")).json()
    destinos = {d["nodo"]: d for d in next(a for a in ficha["acciones"] if a["codigo"] == "TRANSFERIR")["contexto"]["destinos"]}
    assert not destinos["R1"]["permitido"] and destinos["K1"]["permitido"]
    assert (await coord.post("/documentos/transferencias", {"objetos": [uid], "nodo_origen": "E1", "nodo_destino": "R1"})).status_code == 422
    trf2 = (await coord.post("/documentos/transferencias", {"objetos": [uid], "nodo_origen": "E1", "nodo_destino": "K1", "ubicacion_destino": "PATIO"})).json()
    guia2 = await gk1.evidencia("GUIA_REMISION")
    assert (await gk1.post(f"/documentos/transferencias/{trf2['uid']}/recibir", {"evidencias": [guia2]})).status_code == 200

    cert = await gk1.evidencia("CERTIFICADO_TRATAMIENTO")
    r = await gk1.post("/documentos/tratamientos", {"objeto": uid, "tipo_tratamiento": "DESENSAMBLE_RECICLAJE", "resultado": "EXITOSO",
                                                    "evidencias": [cert], "fracciones": [{"material": "VIDRIO", "peso_kg": 9}]})
    assert r.status_code == 422                                                            # fracciones > peso del equipo
    r = await gk1.post("/documentos/tratamientos", {"objeto": uid, "tipo_tratamiento": "DESENSAMBLE_RECICLAJE", "resultado": "EXITOSO",
                                                    "evidencias": [cert], "fracciones": [{"material": "VIDRIO", "peso_kg": 1.5},
                                                                                         {"material": "PLASTICO", "peso_kg": 1.2}]})
    assert r.status_code == 201, r.text
    cert2 = await gk1.evidencia("CERTIFICADO_TRATAMIENTO")
    assert (await gk1.post("/documentos/cierres", {"objeto": uid, "evidencias": [cert2]})).status_code == 201

    ficha = (await coord.get(f"/objetos/{codigo}")).json()
    assert ficha["objeto"]["estado"] == "CERRADO" and ficha["linea"]["trazabilidad_completa"]
    assert [p["estado_destino"] for p in ficha["linea"]["pasos"]] == [
        "REGISTRADO", "RECOLECCION_SOLICITADA", "EN_RECOLECCION", "RECIBIDO", "EN_TRANSFERENCIA", "RECIBIDO", "EN_EVALUACION",
        "CLASIFICADO", "EN_TRANSFERENCIA", "EN_TRATAMIENTO", "TRATADO", "CERRADO"]
    assert ficha["linea"]["cierre"]["destino_final"] == "RECICLAJE" and ficha["acciones"] == []


# ---------------------------------------------------------------- RN-09 y RNF-10
async def test_rn09_borrado_antes_de_asignar(actores):
    coord, tec = actores["coordinador"], actores["tecnico.r1"]
    uid = await uid_de(coord, "LAP-1013")
    ficha = (await coord.get("/objetos/LAP-1013")).json()
    b1 = next(d for d in ficha["acciones"][0]["contexto"]["destinos"] if d["nodo"] == "B1")
    assert not b1["permitido"] and "RN-09" in b1["motivo"]
    r = await coord.post("/documentos/transferencias", {"objetos": [uid], "nodo_origen": "R1", "nodo_destino": "B1"})
    assert r.status_code == 422 and "RN-09" in r.json()["detail"]
    await tec.evidencia("CERTIFICADO_BORRADO", objeto=uid)
    r = await coord.post("/documentos/transferencias", {"objetos": [uid], "nodo_origen": "R1", "nodo_destino": "B1",
                                                        "criterio_asignacion": "Inclusión digital"})
    assert r.status_code == 201, r.text
    acciones = (await actores["beneficiario"].get("/objetos/LAP-1013")).json()["acciones"]
    assert [a["codigo"] for a in acciones] == ["RECIBIR_TRANSFERENCIA"]


async def test_rnf10_foto_con_gps_rechazada(actores):
    op = actores["operador.c1"]
    datos = jpeg_con_gps()
    s = (await op.post("/evidencias/subida", {"tipo": "FOTO_RECEPCION", "mime": "image/jpeg", "tamano": len(datos)})).json()
    await op.c.put(s["url"].removeprefix("/api/v1"), content=datos, headers={"Content-Type": "image/jpeg"})
    import hashlib
    r = await op.post("/evidencias", {"tipo": "FOTO_RECEPCION", "clave": s["clave"], "sha256": hashlib.sha256(datos).hexdigest(),
                                      "mime": "image/jpeg", "tamano": len(datos)})
    assert r.status_code == 422 and "EXIF" in r.json()["detail"]
    r = await op.post("/evidencias/subida", {"tipo": "FOTO_RECEPCION", "mime": "application/pdf", "tamano": 10})
    assert r.status_code == 422                                                            # formato no permitido para el tipo


async def test_rn07_descarga_con_proposito(actores):
    ficha = (await actores["auditor"].get("/objetos/LAP-1001")).json()
    acta = next(e for e in ficha["evidencias"] if e["tipo"] == "ACTA_ENTREGA")
    r = await actores["auditor"].get(f"/evidencias/{acta['uid']}/descarga?proposito=AUDITORIA")
    assert r.status_code == 200
    archivo = await actores["auditor"].c.get(r.json()["url"].removeprefix("/api/v1"))
    assert archivo.status_code == 200 and archivo.content.startswith(b"%PDF")
    r = await actores["auditor"].get(f"/evidencias/{acta['uid']}/descarga?proposito=TRAZABILIDAD")
    assert r.status_code == 403


# ---------------------------------------------------------------- MCP gobernado por la base (ADR-006)
async def test_mcp_catalogo_confirmacion_y_bitacora(actores):
    gen, coord = actores["gen.universidad"], actores["coordinador"]
    nombres = {h["nombre"] for h in (await gen.get("/asistente/herramientas")).json()["herramientas"]}
    assert "solicitar_recoleccion" in nombres and "ejecutar_flujo_maximo" not in nombres
    r = (await gen.post("/asistente/ejecutar", {"herramienta": "ejecutar_flujo_maximo", "argumentos": {"escenario": "E0"}})).json()
    assert r["estado"] == "DENEGADO"
    args = {"codigo": "MON-9001", "categoria": "MONITOR", "peso_kg": 2.0, "atributos": {"pulgadas": 17}}
    assert (await gen.post("/asistente/ejecutar", {"herramienta": "registrar_dispositivo", "argumentos": args})).json()["estado"] == "PENDIENTE_CONFIRMACION"
    r = (await gen.post("/asistente/ejecutar", {"herramienta": "registrar_dispositivo", "argumentos": args, "confirmado": True})).json()
    assert r["estado"] == "OK", r
    r = (await coord.post("/asistente/ejecutar", {"herramienta": "ejecutar_flujo_maximo", "argumentos": {"escenario": "E3"}})).json()
    assert r["estado"] == "OK" and r["resultado"]["flujo_maximo"] == 175
    bit = (await actores["auditor"].get("/auditoria/mcp")).json()
    estados = {(b["herramienta"], b["estado"]) for b in bit}
    assert {("ejecutar_flujo_maximo", "DENEGADO"), ("registrar_dispositivo", "PENDIENTE_CONFIRMACION"), ("registrar_dispositivo", "OK")} <= estados


async def test_chat_detiene_escrituras_hasta_confirmar(actores, monkeypatch):
    """El chat con Claude (cliente simulado) no escribe sin confirmación humana."""
    from types import SimpleNamespace
    from app.asistente import chat

    class Falso:
        def __init__(self):
            self.messages = self
            self.n = 0

        async def create(self, **kw):
            self.n += 1
            if self.n == 1:
                return SimpleNamespace(stop_reason="tool_use", content=[
                    SimpleNamespace(model_dump=lambda: {"type": "text", "text": "Registro el equipo."}),
                    SimpleNamespace(model_dump=lambda: {"type": "tool_use", "id": "t1", "name": "registrar_dispositivo",
                                                        "input": {"codigo": "MON-9002", "categoria": "MONITOR", "peso_kg": 2, "atributos": {"pulgadas": 15}}})])
            return SimpleNamespace(stop_reason="end_turn", content=[SimpleNamespace(model_dump=lambda: {"type": "text", "text": "Listo."})])

    falso = Falso()
    uid = (await actores["gen.universidad"].get("/auth/me")).json()["uid"]
    r = await chat.conversar(uid, [{"role": "user", "content": [{"type": "text", "text": "registra un monitor"}]}], "s-prueba", None, cliente=falso)
    assert r["pendiente"]["herramienta"] == "registrar_dispositivo"
    assert (await actores["gen.universidad"].get("/objetos/MON-9002")).status_code == 404
    r = await chat.conversar(uid, r["historial"], "s-prueba", None, {"tool_use_id": "t1", "aprobado": True}, cliente=falso)
    assert r["respuesta"] == "Listo." and r["eventos"][0]["estado"] == "OK"
    assert (await actores["gen.universidad"].get("/objetos/MON-9002")).status_code == 200


# ---------------------------------------------------------------- capacitación y auditoría
async def test_capacitacion_y_auditoria_as_of(actores):
    gen = actores["gen.municipio"]
    lista = (await gen.get("/capacitacion")).json()
    assert len(lista) >= 7
    uid = lista[0]["uid"]
    r = (await gen.post(f"/capacitacion/{uid}/reaccion")).json()
    assert r["me_gusta_yo"] is True
    assert (await gen.post(f"/capacitacion/{uid}/comentarios", {"texto": "Muy útil"})).status_code == 201
    assert (await gen.post(f"/capacitacion/{uid}/moderacion", {"estado": "OCULTO"})).status_code == 403
    r = (await actores["auditor"].get("/auditoria/objetos/LAP-1001/en", params={"instante": "2020-01-01T00:00:00Z"})).json()
    assert r["existia"] is False
    r = (await actores["auditor"].get("/auditoria/objetos/LAP-1001/en", params={"instante": "2100-01-01T00:00:00Z"})).json()
    assert r["estado"] == "CERRADO"


# ---------------------------------------------------------------- editor de escenarios (qué pasaría si)
async def test_editor_de_escenarios(actores):
    coord, gen = actores["coordinador"], actores["gen.municipio"]
    # E0–E4 son del capítulo y están aprobados: no se editan
    r = await coord.put("/red/escenarios/E0/nodos", {"nodo": "E1", "capacidad": 999})
    assert r.status_code == 409, r.text
    assert (await gen.post("/red/escenarios", {"codigo": "X1", "nombre": "Sin permiso", "base": "E0"})).status_code == 403
    r = await coord.post("/red/escenarios", {"codigo": "e9", "nombre": "Laboratorio ampliado", "base": "E0"})
    assert r.status_code == 201 and r.json()["codigo"] == "E9", r.text
    base = (await coord.get("/red/escenarios/E9/flujo")).json()
    assert base["flujo_maximo"] == 200                                        # hereda todo de E0
    r = await coord.put("/red/escenarios/E9/nodos", {"nodo": "E1", "capacidad": 230})
    assert r.status_code == 200 and r.json()["flujo_maximo"] == 225, r.text   # igual que E1 del capítulo
    r = await coord.put("/red/escenarios/E9/aristas", {"origen": "C2", "destino": "K1", "capacidad": 0})
    assert r.status_code == 422, r.text                                       # un ajuste de arista exige motivo
    r = await coord.put("/red/escenarios/E9/aristas", {"origen": "C2", "destino": "K1", "capacidad": 0, "motivo": "Ruta suspendida"})
    assert r.status_code == 200 and r.json()["flujo_maximo"] < 225, r.text
    r = await coord.put("/red/escenarios/E9/aristas", {"origen": "C2", "destino": "K1", "capacidad": None, "activa": None})
    assert r.json()["flujo_maximo"] == 225                                    # quitar el ajuste vuelve a heredar
    esc = next(e for e in (await coord.get("/red")).json()["escenarios"] if e["codigo"] == "E9")
    assert esc["estado"] == "BORRADOR" and esc["escenario_base"] == "E0" and esc["cambios_nodos"][0]["nodo"] == "E1"
    assert (await coord.delete("/red/escenarios/E9")).status_code == 200


# ---------------------------------------------------------------- solicitud de rol del autorregistro
async def test_solicitud_de_rol(cliente, actores):
    r = await cliente.post("/auth/registro", json={"alias": "luis.prueba", "correo": "luis@ejemplo.invalid", "password": "Clave-segura-2",
                                                   "organizacion": "GEN-MUNI"})
    assert r.status_code == 201, r.text
    login = await cliente.post("/auth/login", json={"correo": "luis@ejemplo.invalid", "password": "Clave-segura-2"})
    from conftest import Actor
    luis = Actor(cliente, "luis.prueba", login.json()["access_token"])
    assert (await luis.post("/solicitudes-rol", {"rol": "GENERADOR", "motivo": "corto"})).status_code == 422
    r = await luis.post("/solicitudes-rol", {"rol": "GENERADOR", "motivo": "Soy el responsable del punto limpio municipal"})
    assert r.status_code == 201, r.text
    sol = r.json()["uid"]
    assert (await luis.post("/solicitudes-rol", {"rol": "GENERADOR", "motivo": "Otra vez la misma solicitud"})).status_code == 409
    mias = (await luis.get("/solicitudes-rol")).json()
    assert len(mias) == 1 and mias[0]["estado"] == "PENDIENTE"
    assert (await luis.post(f"/solicitudes-rol/{sol}/resolver", {"aprobar": True})).status_code == 403   # no se aprueba a sí mismo
    admin = actores["admin"]
    pendientes = (await admin.get("/solicitudes-rol", params={"pendientes": True})).json()
    assert any(p["uid"] == sol for p in pendientes)
    assert (await admin.post(f"/solicitudes-rol/{sol}/resolver", {"aprobar": False, "respuesta": ""})).status_code == 422
    assert (await admin.post(f"/solicitudes-rol/{sol}/resolver", {"aprobar": True, "respuesta": "Verificado con el GAD"})).status_code == 200
    perfil = (await luis.get("/auth/me")).json()
    assert "GENERADOR" in perfil["roles_efectivos"]
    assert (await admin.post(f"/solicitudes-rol/{sol}/resolver", {"aprobar": True})).status_code == 409


# ---------------------------------------------------------------- CRUD de equipos: crear, consultar, actualizar, anular
async def test_crud_dispositivo(actores):
    gen, otro = actores["gen.municipio"], actores["gen.universidad"]
    r = await gen.post("/objetos/dispositivos", {"categoria": "MONITOR", "peso_kg": 4.5, "marca": "HP", "atributos": {"pulgadas": 22}})
    assert r.status_code == 201, r.text
    nuevo = r.json()
    ficha = (await gen.get(f"/objetos/{nuevo['codigo']}")).json()
    assert {"EDITAR", "ANULAR"} <= {a["codigo"] for a in ficha["acciones"]}
    cambio = {"peso_kg": 5.2, "marca": "HP", "numero_serie": "SN-NUEVA-1", "atributos": {"pulgadas": 24}, "motivo": "Peso mal digitado"}
    assert (await otro.put(f"/objetos/dispositivos/{nuevo['uid']}", cambio)).status_code in (403, 404)   # otra organización
    assert (await gen.put(f"/objetos/dispositivos/{nuevo['uid']}", {**cambio, "atributos": {}})).status_code == 422  # falta pulgadas
    assert (await gen.put(f"/objetos/dispositivos/{nuevo['uid']}", cambio)).status_code == 200
    ficha = (await gen.get(f"/objetos/{nuevo['codigo']}")).json()
    assert float(ficha["dispositivo"]["peso_kg"]) == 5.2 and ficha["dispositivo"]["atributos"]["pulgadas"] == 24
    assert any(d["tipo_documento"] == "AJUSTE" for d in ficha["documentos"])                        # el motivo queda documentado
    r = await gen.c.request("DELETE", f"/objetos/{nuevo['uid']}", headers=gen.h, json={"motivo": "Registro duplicado"})
    assert r.status_code == 200, r.text
    ficha = (await gen.get(f"/objetos/{nuevo['codigo']}")).json()
    assert ficha["objeto"]["estado"] == "ANULADO" and not {"EDITAR", "ANULAR"} & {a["codigo"] for a in ficha["acciones"]}
    assert (await gen.put(f"/objetos/dispositivos/{nuevo['uid']}", cambio)).status_code == 409   # ya no se edita
    # un equipo que ya avanzó en la trazabilidad no se puede anular ni editar
    lap = (await gen.get("/objetos/LAP-1001")).json()
    if lap.get("objeto"):
        r = await gen.c.request("DELETE", f"/objetos/{lap['objeto']['uid']}", headers=gen.h, json={"motivo": "Prueba"})
        assert r.status_code in (403, 409)


# ---------------------------------------------------------------- verificación de la base y persistencia (Parte II)
async def test_verificacion_de_la_base(cliente, actores):
    r = await cliente.get("/verificacion/conexion")
    assert r.status_code == 200 and r.json()["base_de_datos"] == "ok" and r.json()["usuario_conexion"] == "ecoraee_api_svc"
    assert (await cliente.get("/verificacion/base")).status_code == 401
    v = (await actores["auditor"].get("/verificacion/base")).json()
    assert v["todo_correcto"], [c for c in v["consistencia"] if not c["ok"]]
    assert v["estructura"]["claves_foraneas"] > 100 and v["estructura"]["tablas_con_rls"] > 0
    assert all(v["scripts"].values())
    # lo creado por la API aparece en las tablas de la base con su auditoría
    gen = actores["gen.municipio"]
    nuevo = (await gen.post("/objetos/dispositivos", {"categoria": "MONITOR", "peso_kg": 3.3, "atributos": {"pulgadas": 19}})).json()
    filas = (await gen.get(f"/verificacion/objetos/{nuevo['codigo']}")).json()
    assert filas["trz.objeto_trazable"]["estado_actual"] == "REGISTRADO"
    assert float(filas["trz.dispositivo"]["peso_kg"]) == 3.3
    assert filas["trz.historial_estado"][0]["hacia"] == "REGISTRADO"
    assert {x["tabla"] for x in filas["aud.log_cambio"]} >= {"trz.objeto_trazable", "trz.dispositivo"}
    # RLS: otra organización no ve las filas de este equipo
    assert (await actores["gen.universidad"].get(f"/verificacion/objetos/{nuevo['codigo']}")).status_code == 404
