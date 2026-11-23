"""
EcoRAEE Cloud — módulo matemático conectado a la base de datos (CP-07, CP-08, CP-09).

1. Valida Edmonds-Karp con una red pequeña de resultado conocido (CP-07).
2. Lee el dataset de cada escenario desde PostgreSQL con api.fn_dataset_flujo (CP-09).
3. Calcula flujo máximo, flujo por arista y por nodo, y TODOS los cortes mínimos (CP-08).
4. Contrasta el valor con networkx (verificación independiente).
5. Registra el resultado con api.fn_registrar_resultado_flujo, que rechaza
   la escritura si el dataset cambió desde que se leyó (hash SHA-256).

El cálculo vive en ecoraee_flujo.py, el mismo módulo que usa la API (RF-INT-04).
Uso: python3 flujo_maximo.py [E0 E1 E2 E3 E4]
Conexión por variables de entorno PGHOST, PGUSER, PGDATABASE (rol con EXECUTE en api.*).
"""
import json
import os
import sys

import psycopg2

import ecoraee_flujo as nucleo

COORDINADOR = "00000000-0000-4000-8000-000000000009"


def ejecutar(conn, escenario):
    with conn:
        with conn.cursor() as cur:
            cur.execute("SELECT api.fn_iniciar_contexto(%s, 'BATCH')", (COORDINADOR,))
            cur.execute("SELECT api.fn_dataset_flujo(%s)", (escenario,))
            dataset = cur.fetchone()[0]
            r = nucleo.calcular(dataset)
            try:
                import networkx as nx
                cap, _ = nucleo.red_extendida(dataset)
                g = nx.DiGraph()
                for (u, v), c in cap.items():
                    g.add_edge(u, v, capacity=c)
                assert abs(nx.maximum_flow_value(g, nucleo.S, nucleo.T) - r["flujo_maximo"]) < 1e-6, "Discrepancia con networkx"
            except ImportError:
                pass
            flujos, cortes = nucleo.para_registro(r)
            cur.execute("SELECT api.fn_registrar_resultado_flujo(%s, %s, %s, %s::jsonb, %s::jsonb, 'EDMONDS_KARP', '2.0.0')",
                        (escenario, dataset["hash"], r["flujo_maximo"], json.dumps(flujos), json.dumps(cortes)))
            r["ejecucion_id"] = cur.fetchone()[0]
    return r


if __name__ == "__main__":
    valor, n = nucleo.validar_red_manual()
    print(f"CP-07 red manual: flujo máximo = {valor:.0f} (esperado 23), cortes mínimos = {n}")
    conn = psycopg2.connect(host=os.getenv("PGHOST", "/srv/pg"), user=os.getenv("PGUSER", "postgres"),
                            dbname=os.getenv("PGDATABASE", "ecoraee"), password=os.getenv("PGPASSWORD"))
    with conn.cursor() as cur:
        cur.execute("SET ROLE ecoraee_app")              # mismos privilegios que la API: solo funciones api.*
    salida = []
    for esc in (sys.argv[1:] or ["E0", "E1", "E2", "E3", "E4"]):
        r = ejecutar(conn, esc)
        salida.append({k: r[k] for k in ("escenario", "flujo_maximo", "generacion", "cobertura", "cortes", "ejecucion_id", "hash")})
        print(f"{esc}: flujo máximo {r['flujo_maximo']:.0f} de {r['generacion']:.0f} ({r['cobertura']} %) · "
              f"{len(r['cortes'])} corte(s) mínimo(s): "
              + " | ".join(", ".join([f"{u}→{v}" for u, v in c["aristas"]] + [f"nodo {x}" for x in c["nodos"]]
                                     + [f"{u}→{v}" for u, v in c["virtuales"]]) for c in r["cortes"]))
    try:                                                 # CP-09 negativo: hash obsoleto
        with conn:
            with conn.cursor() as cur:
                cur.execute("SELECT api.fn_iniciar_contexto(%s, 'BATCH')", (COORDINADOR,))
                cur.execute("SELECT api.fn_registrar_resultado_flujo('E0', %s, 1, '[]', '[]')", ("0" * 64,))
        print("CP-09 hash: FALLÓ (aceptó un hash viejo)")
    except psycopg2.Error as e:
        print(f"CP-09 hash obsoleto rechazado: {e.pgcode}")
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "resultados_flujo.json"), "w") as f:
        json.dump(salida, f, ensure_ascii=False, indent=2)
