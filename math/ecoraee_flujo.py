"""
EcoRAEE Cloud — núcleo matemático de flujo máximo (RF-MD-03, RF-MD-04, CP-07, CP-08).

Módulo puro, sin base de datos: lo usan el CLI (math/flujo_maximo.py) y la API (backend).

Entrada: el dataset que devuelve api.fn_dataset_flujo(escenario):
  aristas   [{origen, destino, capacidad}]
  fuentes   [{nodo, oferta}]      → arcos virtuales s → nodo
  sumideros [{nodo, demanda}]     → arcos virtuales nodo → t
  nodos     [{nodo, capacidad}]   → capacidad de procesamiento: el nodo se parte en
                                     nodo__in → nodo__out (la arista E_in → E_out del capítulo)

Salida: flujo máximo, flujo por arista y por nodo, y TODOS los cortes mínimos.
"""
from __future__ import annotations

import itertools
from collections import deque

S, T = "s", "t"            # superfuente y supersumidero virtuales (no se guardan en la base)
_IN, _OUT = "__in", "__out"
EPS = 1e-9


def edmonds_karp(capacidad: dict[tuple[str, str], float], s: str = S, t: str = T) -> tuple[float, dict[tuple[str, str], float]]:
    """Edmonds-Karp (BFS: camino aumentante más corto). Devuelve (valor, flujo por arista)."""
    residual: dict[tuple[str, str], float] = {}
    vecinos: dict[str, set[str]] = {}
    for (u, v), c in capacidad.items():
        residual[(u, v)] = residual.get((u, v), 0) + c
        residual.setdefault((v, u), 0)
        vecinos.setdefault(u, set()).add(v)
        vecinos.setdefault(v, set()).add(u)
    valor = 0.0
    while True:
        padre: dict[str, str | None] = {s: None}
        cola = deque([s])
        while cola and t not in padre:
            u = cola.popleft()
            for v in sorted(vecinos.get(u, ())):          # orden fijo: resultados reproducibles
                if v not in padre and residual[(u, v)] > EPS:
                    padre[v] = u
                    cola.append(v)
        if t not in padre:
            break
        cuello, v = float("inf"), t
        while padre[v] is not None:
            cuello = min(cuello, residual[(padre[v], v)])
            v = padre[v]
        v = t
        while padre[v] is not None:
            u = padre[v]
            residual[(u, v)] -= cuello
            residual[(v, u)] += cuello
            v = u
        valor += cuello
    flujo = {e: c - residual[e] for e, c in capacidad.items()}
    return valor, flujo


def cortes_minimos(capacidad: dict[tuple[str, str], float], valor: float, s: str = S, t: str = T) -> list[set[str]]:
    """Todos los lados-fuente S cuyo corte (S, V∖S) tiene capacidad igual al flujo máximo.
    Enumeración exhaustiva: adecuada para redes del tamaño del ecosistema (≤ 20 nodos internos)."""
    internos = sorted({n for e in capacidad for n in e} - {s, t})
    if len(internos) > 20:
        raise ValueError("Red demasiado grande para enumerar todos los cortes mínimos")
    lados = []
    for bits in itertools.product((0, 1), repeat=len(internos)):
        lado = {s} | {n for n, b in zip(internos, bits) if b}
        cap = sum(c for (u, v), c in capacidad.items() if u in lado and v not in lado)
        if abs(cap - valor) < 1e-6:
            lados.append(lado)
    return lados


def _base(n: str) -> str:
    return n[: -len(_IN)] if n.endswith(_IN) else n[: -len(_OUT)] if n.endswith(_OUT) else n


def red_extendida(dataset: dict) -> tuple[dict[tuple[str, str], float], set[str]]:
    """Construye la red con s, t y los nodos con capacidad partidos en nodo__in → nodo__out."""
    partidos = {n["nodo"]: float(n["capacidad"]) for n in dataset.get("nodos", []) if n.get("capacidad") is not None}
    entra = lambda n: n + _IN if n in partidos else n      # noqa: E731
    sale = lambda n: n + _OUT if n in partidos else n      # noqa: E731
    cap: dict[tuple[str, str], float] = {}
    for a in dataset["aristas"]:
        cap[(sale(a["origen"]), entra(a["destino"]))] = float(a["capacidad"])
    total = sum(cap.values()) + sum(partidos.values()) + 1     # "infinito" práctico para fuentes/sumideros sin límite
    for f in dataset["fuentes"]:
        cap[(S, entra(f["nodo"]))] = float(f["oferta"]) if f.get("oferta") is not None else total
    for k in dataset["sumideros"]:
        cap[(sale(k["nodo"]), T)] = float(k["demanda"]) if k.get("demanda") is not None else total
    for n, c in partidos.items():
        cap[(n + _IN, n + _OUT)] = c
    return cap, set(partidos)


def calcular(dataset: dict) -> dict:
    """Flujo máximo, flujos por arista/nodo/arco virtual y todos los cortes mínimos, en códigos de la base."""
    cap, partidos = red_extendida(dataset)
    valor, flujo = edmonds_karp(cap)
    lados = cortes_minimos(cap, valor)

    def clasificar(e):
        u, v = e
        if (u, v) in partidos_aristas:
            n = _base(u)
            return {"tipo": "nodo", "nodo": n}
        if u == S or v == T:
            return {"tipo": "virtual", "origen": _base(u), "destino": _base(v)}
        return {"tipo": "arista", "origen": _base(u), "destino": _base(v)}

    partidos_aristas = {(n + _IN, n + _OUT) for n in partidos}
    cortes = []
    for i, lado in enumerate(lados, 1):
        cruzan = sorted((u, v) for (u, v) in cap if u in lado and v not in lado)
        aristas = [[_base(u), _base(v)] for (u, v) in cruzan if (u, v) not in partidos_aristas and S not in (u, v) and T not in (u, v)]
        nodos = sorted(_base(u) for (u, v) in cruzan if (u, v) in partidos_aristas)
        virtuales = [[_base(u), _base(v)] for (u, v) in cruzan if u == S or v == T]
        lado_fuente = sorted({_base(n) for n in lado - {S} if not n.endswith(_OUT) or (n[: -len(_OUT)] + _IN) in lado})
        cortes.append({"numero": i, "capacidad": round(sum(cap[e] for e in cruzan), 6), "aristas": aristas, "nodos": nodos,
                       "virtuales": virtuales, "lado_fuente": lado_fuente})

    en_corte = {tuple(a) for c in cortes for a in c["aristas"]}
    nodos_corte = {n for c in cortes for n in c["nodos"]}
    virt_corte = {tuple(a) for c in cortes for a in c["virtuales"]}

    def estado(clave, conjunto, f, c):
        if clave in conjunto:
            return "corte"
        return "saturada" if f >= c - EPS else "holgura"

    aristas, nodos, virtuales = [], [], []
    for (u, v), c in sorted(cap.items()):
        f = round(flujo[(u, v)], 6)
        k = clasificar((u, v))
        if k["tipo"] == "nodo":
            nodos.append({"nodo": k["nodo"], "capacidad": c, "flujo": f, "uso": round(100 * f / c) if c else 0,
                          "estado": estado(k["nodo"], nodos_corte, f, c)})
        elif k["tipo"] == "virtual":
            virtuales.append({"origen": k["origen"], "destino": k["destino"], "capacidad": c, "flujo": f,
                              "uso": round(100 * f / c) if c else 0,
                              "estado": estado((k["origen"], k["destino"]), virt_corte, f, c)})
        else:
            aristas.append({"origen": k["origen"], "destino": k["destino"], "capacidad": c, "flujo": f,
                            "uso": round(100 * f / c) if c else 0,
                            "estado": estado((k["origen"], k["destino"]), en_corte, f, c)})

    generacion = sum(c for (u, _), c in cap.items() if u == S)
    # aristas presentes en TODOS los cortes: ampliarlas es condición necesaria para crecer
    comunes = set.intersection(*[{tuple(a) for a in c["aristas"]} | {("nodo", n) for n in c["nodos"]} for c in cortes]) if cortes else set()
    return {
        "escenario": dataset.get("escenario"), "unidad": dataset.get("unidad"), "periodo": dataset.get("periodo"),
        "hash": dataset.get("hash"), "flujo_maximo": round(valor, 6), "generacion": round(generacion, 6),
        "cobertura": round(100 * valor / generacion) if generacion else 0,
        "aristas": aristas, "nodos": nodos, "virtuales": virtuales, "cortes": cortes,
        "criticos_en_todos_los_cortes": sorted([list(x) if x[0] != "nodo" else {"nodo": x[1]} for x in comunes], key=str),
    }


def para_registro(resultado: dict) -> tuple[list[dict], list[dict]]:
    """Flujos y cortes en el formato que espera api.fn_registrar_resultado_flujo."""
    flujos = [{"origen": a["origen"], "destino": a["destino"], "flujo": a["flujo"]} for a in resultado["aristas"]]
    cortes = [{"capacidad": c["capacidad"], "lado_fuente": c["lado_fuente"], "aristas": c["aristas"], "nodos": c["nodos"]}
              for c in resultado["cortes"]]
    return flujos, cortes


def validar_red_manual() -> tuple[float, int]:
    """CP-07: red clásica (Cormen et al.) con flujo máximo conocido = 23."""
    cap = {(S, "v1"): 16, (S, "v2"): 13, ("v1", "v3"): 12, ("v2", "v1"): 4, ("v2", "v4"): 14,
           ("v3", "v2"): 9, ("v3", T): 20, ("v4", "v3"): 7, ("v4", T): 4}
    valor, flujo = edmonds_karp(cap)
    for nodo in ("v1", "v2", "v3", "v4"):
        assert abs(sum(f for (u, v), f in flujo.items() if v == nodo) - sum(f for (u, v), f in flujo.items() if u == nodo)) < EPS
    assert all(-EPS <= flujo[e] <= cap[e] + EPS for e in cap)
    assert valor == 23, valor
    return valor, len(cortes_minimos(cap, valor))
