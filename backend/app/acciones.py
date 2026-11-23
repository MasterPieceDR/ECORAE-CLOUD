"""Acciones disponibles para un objeto según su estado, ubicación, documentos abiertos y los permisos efectivos del usuario.

Esto NO reemplaza a las reglas de la base (que se vuelven a validar al ejecutar): sirve para que la interfaz
muestre solo lo que tiene sentido y explique por qué algo está bloqueado (RNF-07: mensajes claros).
Las transiciones se comprueban contra la relación T del catálogo (cat.transicion_estado, ADR-003).
"""
from __future__ import annotations

from dataclasses import dataclass

from .seguridad import Perfil

# tipo de nodo destino → tipo de destino circular (cat.tipo_nodo.tipo_destino_id)
DESTINO_DE_NODO = {"REACONDICIONAMIENTO": "REACONDICIONAMIENTO", "RECICLAJE": "RECICLAJE",
                   "DISPOSICION": "DISPOSICION_CONTROLADA", "BENEFICIARIO": "REUTILIZACION"}
# función del centro → destinos de tratamiento que puede ejecutar
FUNCION_TRATAMIENTO = {"REACONDICIONAMIENTO": "REACONDICIONAMIENTO", "RECICLAJE": "RECICLAJE", "DISPOSICION": "DISPOSICION_CONTROLADA"}
EVIDENCIA_RECEPCION = ["FOTO_RECEPCION", "ACTA_RECEPCION"]


@dataclass
class Contexto:
    perfil: Perfil
    catalogos: dict
    aristas: list[dict]
    nodos: list[dict]

    def __post_init__(self):
        self.t = {(t["origen"], t["destino"]) for t in self.catalogos["transiciones"]}
        self.centros = {c["codigo"]: c for c in self.catalogos["centros"] or []}
        self.nodo = {n["codigo"]: n for n in self.nodos}
        self.nodo_de_centro = {n["centro"]: n["codigo"] for n in self.nodos if n.get("centro")}
        self.matriz: dict[str, set] = {}
        for m in self.catalogos["matriz_destinos"]:
            self.matriz.setdefault(m["clasificacion"], set()).add(m["destino"])
        self.categorias = {c["codigo"]: c for c in self.catalogos["categorias"]}

    def permite(self, origen: str, destino: str) -> bool:
        return (origen, destino) in self.t

    def ubicaciones(self, centro: str | None) -> list[dict]:
        return (self.centros.get(centro) or {}).get("ubicaciones") or []

    def centros_con(self, permiso: str) -> list[str]:
        alcance = self.perfil.centros(permiso)
        todos = sorted(self.centros)
        return todos if alcance is None else [c for c in todos if c in alcance]

    def criterios_para(self, categoria: str | None) -> list[dict]:
        """Criterios generales y los de la categoría o sus ancestros."""
        ruta = (self.categorias.get(categoria) or {}).get("ruta", "")
        ancestros = {c["codigo"] for c in self.categorias.values() if ruta == c["ruta"] or ruta.startswith(c["ruta"] + ".")}
        return [c for c in self.catalogos["criterios"] if c["categoria"] is None or c["categoria"] in ancestros]


def _accion(codigo: str, titulo: str, descripcion: str, permiso: str, tarea: bool = True, **contexto) -> dict:
    """tarea=False: acción posible pero no pendiente (no aparece en la bandeja), p. ej. una reevaluación."""
    return {"codigo": codigo, "titulo": titulo, "descripcion": descripcion, "permiso": permiso, "tarea": tarea, "contexto": contexto}


def calcular(o: dict, cx: Contexto) -> dict:
    """Devuelve {'acciones': [...], 'avisos': [...]} para el objeto o (fila de api.v1_objeto_operativo)."""
    p, estado, centro, tipo = cx.perfil, o["estado"], o.get("centro_actual"), o["tipo_objeto"]
    acciones, avisos = [], []

    if tipo == "DISPOSITIVO" and o.get("lote_codigo"):
        avisos.append({"tipo": "info", "texto": f"Este equipo viaja dentro del lote {o['lote_codigo']}: las operaciones logísticas se hacen sobre el lote.",
                       "enlace": o["lote_codigo"]})
        return {"acciones": [], "avisos": avisos}
    if estado in ("CERRADO", "ANULADO", "DESAGRUPADO"):
        return {"acciones": [], "avisos": avisos}

    # 1. Solicitud de recolección (generador)
    if estado == "REGISTRADO" and p.tiene("SOLICITUD.CREAR") and cx.permite("REGISTRADO", "RECOLECCION_SOLICITADA"):
        nodo_gen = next((n["codigo"] for n in cx.nodos if n.get("organizacion") == o["organizacion_origen"]), None)
        destinos = sorted({cx.nodo[a["destino"]]["centro"] for a in cx.aristas
                           if a["activa"] and a["origen"] == nodo_gen and cx.nodo.get(a["destino"], {}).get("centro")})
        if not destinos:
            destinos = [c for c, v in cx.centros.items() if "ACOPIO" in (v.get("funciones") or [])]
        acciones.append(_accion("SOLICITAR_RECOLECCION", "Solicitar recolección",
                                "Pide que un centro recoja el equipo. Se agrupan en una solicitud los objetos de un mismo generador.",
                                "SOLICITUD.CREAR", centros=[{"codigo": c, "nombre": cx.centros[c]["nombre"]} for c in destinos if c in cx.centros]))

    # 2. Programación de la recolección (coordinador; consume capacidad G→C, RN-05)
    if estado == "RECOLECCION_SOLICITADA" and o.get("solicitud_uid") and o.get("solicitud_estado") == "EMITIDO" \
            and p.tiene("RECOLECCION.PROGRAMAR", o.get("solicitud_centro")):
        acciones.append(_accion("PROGRAMAR_RECOLECCION", "Programar recolección",
                                f"Asigna fecha y transporte a la solicitud {o['solicitud_numero']} hacia {o['solicitud_centro']}.",
                                "RECOLECCION.PROGRAMAR", solicitud=o["solicitud_uid"], numero=o["solicitud_numero"], centro=o["solicitud_centro"]))

    # 3. Recepción en un centro (con solicitud o entrega directa; RN-03 exige evidencia)
    if estado in ("REGISTRADO", "EN_RECOLECCION") and cx.permite(estado, "RECIBIDO"):
        if estado == "EN_RECOLECCION":
            candidatos = [o["solicitud_centro"]] if o.get("solicitud_centro") and p.tiene("RECEPCION.REGISTRAR", o["solicitud_centro"]) else []
        else:
            candidatos = cx.centros_con("RECEPCION.REGISTRAR")
        if candidatos:
            acciones.append(_accion("RECIBIR", "Registrar recepción" if estado == "EN_RECOLECCION" else "Recibir entrega directa",
                                    tarea=(estado == "EN_RECOLECCION"),
                                    descripcion="Confirma la llegada al centro con evidencia y la ubicación donde queda en inventario.",
                                    permiso="RECEPCION.REGISTRAR", solicitud=o.get("solicitud_uid"),
                                    centros=[{"codigo": c, "nombre": cx.centros[c]["nombre"], "ubicaciones": cx.ubicaciones(c)} for c in candidatos],
                                    evidencias=EVIDENCIA_RECEPCION))

    # 4. Evaluación técnica (RN-02) y reevaluación
    if tipo == "DISPOSITIVO" and centro and p.tiene("EVALUACION.REGISTRAR", centro):
        reevaluar = estado in ("CLASIFICADO", "TRATADO")
        if estado in ("RECIBIDO", "EN_EVALUACION") or reevaluar:
            acciones.append(_accion("EVALUAR", "Reevaluar" if reevaluar else "Evaluar y clasificar",
                                    "Control de calidad o corrección: exige un motivo y deja vigente la nueva evaluación." if reevaluar
                                    else "Registra la clasificación técnica, los criterios y el destino sugerido.",
                                    "EVALUACION.REGISTRAR", tarea=not reevaluar, reevaluacion=reevaluar, criterios=cx.criterios_para(o.get("categoria")),
                                    requiere_borrado=bool(o.get("contiene_almacenamiento")), centro=centro))

    # 5. Certificado de borrado seguro (RN-09, propuesta de Innovación)
    if tipo == "DISPOSITIVO" and o.get("contiene_almacenamiento") and not o.get("tiene_certificado_borrado") and centro \
            and estado in ("CLASIFICADO", "EN_TRATAMIENTO", "TRATADO") and p.tiene("EVIDENCIA.CARGAR") \
            and (p.tiene("EVALUACION.REGISTRAR", centro) or p.tiene("TRATAMIENTO.REGISTRAR", centro)):
        acciones.append(_accion("CERTIFICAR_BORRADO", "Cargar certificado de borrado",
                                "RN-09: ningún equipo con almacenamiento se entrega sin certificado de borrado seguro de datos.",
                                "EVIDENCIA.CARGAR", tarea=(estado == "TRATADO" and o.get("clasificacion") == "REUTILIZABLE"),
                                evidencias=["CERTIFICADO_BORRADO"]))

    # 6. Transferencia por una arista de la red (RN-05 capacidad, RN-04 compatibilidad, RN-09 borrado)
    if estado in ("RECIBIDO", "CLASIFICADO", "TRATADO") and centro and p.tiene("TRANSFERENCIA.CREAR", centro) \
            and cx.permite(estado, "EN_TRANSFERENCIA"):
        origen = cx.nodo_de_centro.get(centro)
        destinos = []
        for a in cx.aristas:
            if not a["activa"] or a["origen"] != origen:
                continue
            n = cx.nodo.get(a["destino"], {})
            destino_circular = DESTINO_DE_NODO.get(n.get("tipo"))
            permitido, motivo = True, None
            if destino_circular:
                if tipo == "LOTE":
                    permitido, motivo = False, "Los lotes se desagrupan antes de ir a tratamiento o asignación."
                elif not o.get("clasificacion"):
                    permitido, motivo = False, "Primero se evalúa: un equipo sin clasificar no va a tratamiento (RN-02)."
                elif destino_circular not in cx.matriz.get(o["clasificacion"], set()):
                    permitido, motivo = False, f"La clasificación {o['clasificacion']} no admite este destino (RN-04)."
                elif n.get("tipo") == "BENEFICIARIO":
                    if not p.tiene("ASIGNACION.REGISTRAR", centro):
                        permitido, motivo = False, "Asignar a una beneficiaria requiere el permiso ASIGNACION.REGISTRAR."
                    elif o.get("contiene_almacenamiento") and not o.get("tiene_certificado_borrado"):
                        permitido, motivo = False, "RN-09: falta el certificado de borrado seguro de datos."
                    elif estado == "CLASIFICADO" and o.get("ultimo_tratamiento_destino") is None and o["clasificacion"] != "REUTILIZABLE":
                        permitido, motivo = False, "Solo un equipo reutilizable va directo a una beneficiaria."
            destinos.append({"nodo": a["destino"], "nombre": n.get("nombre"), "tipo": n.get("tipo"), "centro": n.get("centro"),
                             "capacidad": a.get("capacidad_und"), "requiere_excepcion": a.get("requiere_excepcion"),
                             "ubicaciones": cx.ubicaciones(n.get("centro")), "permitido": permitido, "motivo": motivo})
        if destinos:
            pendiente = any(d["permitido"] for d in destinos)
            acciones.append(_accion("TRANSFERIR", "Despachar a otro nodo",
                                    "Crea una transferencia por una arista de la red. La base valida la capacidad disponible (RN-05).",
                                    "TRANSFERENCIA.CREAR", tarea=pendiente, nodo_origen=origen, destinos=destinos))
        if o.get("contiene_almacenamiento") and not o.get("tiene_certificado_borrado") and o.get("clasificacion") in ("REUTILIZABLE", "REPARABLE"):
            avisos.append({"tipo": "aviso", "texto": "RN-09: antes de entregarlo a una beneficiaria necesita un certificado de borrado seguro."})

    # 7. Confirmación de la transferencia en el destino (RN-03)
    if estado == "EN_TRANSFERENCIA" and o.get("transferencia_uid"):
        destino_centro, destino_org = o.get("transferencia_centro_destino"), o.get("transferencia_org_destino")
        puede = p.tiene("TRANSFERENCIA.CONFIRMAR", destino_centro) if destino_centro else \
            (p.tiene("TRANSFERENCIA.CONFIRMAR") and p.organizacion == destino_org)
        if puede:
            acciones.append(_accion("RECIBIR_TRANSFERENCIA", "Confirmar llegada" if destino_centro else "Confirmar entrega recibida",
                                    f"Cierra la transferencia {o['transferencia_numero']} ({o['transferencia_nodo_origen']} → {o['transferencia_nodo_destino']}) con su evidencia.",
                                    "TRANSFERENCIA.CONFIRMAR", transferencia=o["transferencia_uid"], numero=o["transferencia_numero"],
                                    ubicaciones=cx.ubicaciones(destino_centro),
                                    evidencias=["GUIA_REMISION"] if destino_centro else ["ACTA_ENTREGA"]))
        else:
            avisos.append({"tipo": "info", "texto": f"En camino a {o.get('transferencia_nodo_destino')} ({o['transferencia_numero']}). Lo confirma quien lo recibe."})

    # 8. Tratamiento (reacondicionamiento, reciclaje o disposición)
    if estado == "EN_TRATAMIENTO" and centro and p.tiene("TRATAMIENTO.REGISTRAR", centro) and tipo == "DISPOSITIVO":
        funciones = set((cx.centros.get(centro) or {}).get("funciones") or [])
        habilitados = {FUNCION_TRATAMIENTO[f] for f in funciones if f in FUNCION_TRATAMIENTO}
        tipos = [t for t in cx.catalogos["tipos_tratamiento"]
                 if t["destino"] in habilitados and t["destino"] in cx.matriz.get(o.get("clasificacion") or "", set())]
        acciones.append(_accion("REGISTRAR_TRATAMIENTO", "Registrar tratamiento",
                                "Registra el resultado. Si falla, el equipo vuelve a evaluación técnica (R1→K1 del grafo).",
                                "TRATAMIENTO.REGISTRAR", tipos=tipos, peso_kg=o.get("peso_kg"),
                                evidencias=["FOTO_TRATAMIENTO", "CERTIFICADO_TRATAMIENTO"]))

    # 9. Cierre de trazabilidad (RN-08)
    if cx.permite(estado, "CERRADO"):
        if estado == "ASIGNADO_BENEFICIARIO" and p.tiene("CIERRE.CONFIRMAR") and \
                (p.organizacion == o.get("beneficiario") or p.rol("COORDINADOR_LOGISTICO")):
            acciones.append(_accion("CERRAR", "Confirmar destino final", "La beneficiaria confirma que el equipo está en uso. Cierra la trazabilidad.",
                                    "CIERRE.CONFIRMAR", destino="REUTILIZACION", evidencias=["ACTA_ENTREGA"]))
        elif estado == "TRATADO" and o.get("ultimo_tratamiento_destino") in ("RECICLAJE", "DISPOSICION_CONTROLADA") \
                and p.tiene("CIERRE.CONFIRMAR", centro):
            acciones.append(_accion("CERRAR", "Cerrar trazabilidad", "El gestor confirma el destino final con su certificado.",
                                    "CIERRE.CONFIRMAR", destino=o["ultimo_tratamiento_destino"], evidencias=["CERTIFICADO_TRATAMIENTO"]))

    # 10. Desagrupar un lote (pasa a DESAGRUPADO; los equipos siguen por separado)
    if tipo == "LOTE" and p.tiene("LOTE.GESTIONAR") and cx.permite(estado, "DESAGRUPADO") and o.get("miembros_vigentes", 0) > 0:
        acciones.append(_accion("DESAGRUPAR", "Desagrupar lote", "Libera los equipos del lote para evaluarlos o moverlos por separado.",
                                "LOTE.GESTIONAR"))
    return {"acciones": acciones, "avisos": avisos}
