"""
CP-06 / RNF-01: comparación de planes y tiempos antes y después de los índices.
Crea una copia (ecoraee_perf), carga volumen sintético y mide cada consulta 5 veces
sin el índice (DROP dentro de una transacción que se revierte) y con él.
"""
import json, os, statistics, subprocess
import psycopg2

H = os.getenv("PGHOST", "/srv/pg")
subprocess.run(["psql", "-h", H, "-U", "postgres", "-qc", "DROP DATABASE IF EXISTS ecoraee_perf"], check=True)
subprocess.run(["psql", "-h", H, "-U", "postgres", "-qc", "CREATE DATABASE ecoraee_perf TEMPLATE ecoraee"], check=True)
conn = psycopg2.connect(host=H, user="postgres", dbname="ecoraee_perf")
conn.autocommit = True
cur = conn.cursor()

N_OBJ, PASOS = 60000, 8
cur.execute("SET session_replication_role = replica")          # carga masiva sin triggers (práctica estándar de ETL)
cur.execute(f"""
INSERT INTO trz.objeto_trazable(ecosistema_id, codigo, tipo_objeto, organizacion_origen_id, estado_actual_id, registrado_por, registrado_en, cerrado_en)
SELECT 1, 'BULK-' || g, 'DISPOSITIVO', (SELECT id FROM org.organizacion WHERE codigo = 'GEN-UNIV'),
       CASE WHEN g % 10 < 7 THEN (SELECT id FROM cat.estado_trazabilidad WHERE codigo='CERRADO') ELSE 1 + g % 10 END,
       1, timestamptz '2026-09-01' + (g % 180) * interval '1 day',
       CASE WHEN g % 10 < 7 THEN timestamptz '2026-09-20' + (g % 160) * interval '1 day' END
  FROM generate_series(1, {N_OBJ}) g;
INSERT INTO trz.dispositivo(objeto_id, categoria_id, peso_kg, atributos)
SELECT o.id, (SELECT id FROM cat.categoria_raee WHERE codigo='PORTATIL'), 2,
       jsonb_build_object('ram_gb', (2 ^ (1 + o.id % 5))::int, 'almacenamiento_gb', 128 * (1 + o.id % 4),
                          'procesador', CASE WHEN o.id % 1000 = 0 THEN 'i9-9980HK' ELSE 'i5-8350U' END)
  FROM trz.objeto_trazable o WHERE o.codigo LIKE 'BULK-%';
INSERT INTO trz.historial_estado(ocurrido_en, objeto_id, estado_origen_id, estado_destino_id, usuario_id, canal)
SELECT o.registrado_en + p * interval '3 hours', o.id, p, p + 1, 1, 'API'
  FROM trz.objeto_trazable o CROSS JOIN generate_series(1, {PASOS}) p WHERE o.codigo LIKE 'BULK-%';
""")
cur.execute("SET session_replication_role = origin")
cur.execute("VACUUM ANALYZE")                                  # incorpora la lista pendiente del GIN y actualiza estadísticas
cur.execute("SELECT count(*) FROM trz.historial_estado"); n_hist = cur.fetchone()[0]
cur.execute("SELECT count(*) FROM trz.objeto_trazable"); n_obj = cur.fetchone()[0]
cur.execute("SELECT id FROM trz.objeto_trazable WHERE codigo = 'BULK-31337'"); obj = cur.fetchone()[0]

CASOS = [
  ("Q1", "Línea de trazabilidad de un objeto (CP-14)", "ix_historial_objeto",
   "CREATE INDEX ix_historial_objeto ON trz.historial_estado (objeto_id, ocurrido_en)",
   f"SELECT * FROM trz.historial_estado WHERE objeto_id = {obj} ORDER BY ocurrido_en"),
  ("Q2", "Objetos activos por estado (tablero operativo)", "ix_objeto_estado_activo",
   "CREATE INDEX ix_objeto_estado_activo ON trz.objeto_trazable (ecosistema_id, estado_actual_id) WHERE cerrado_en IS NULL",
   "SELECT count(*) FROM trz.objeto_trazable WHERE ecosistema_id = 1 AND estado_actual_id = 5 AND cerrado_en IS NULL"),
  ("Q3", "Atributo JSONB selectivo (procesador poco frecuente)", "ix_dispositivo_atributos",
   "CREATE INDEX ix_dispositivo_atributos ON trz.dispositivo USING gin (atributos jsonb_path_ops)",
   """SELECT count(*) FROM trz.dispositivo WHERE atributos @> '{"procesador":"i9-9980HK"}'"""),
  ("Q4", "Atributo JSONB poco selectivo (20 % de las filas)", "ix_dispositivo_atributos",
   "CREATE INDEX ix_dispositivo_atributos ON trz.dispositivo USING gin (atributos jsonb_path_ops)",
   """SELECT count(*) FROM trz.dispositivo WHERE atributos @> '{"ram_gb":32}'"""),
]

def medir(sql):
    tiempos, plan = [], None
    for _ in range(5):
        cur.execute("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) " + sql)
        r = cur.fetchone()[0][0]
        tiempos.append(r["Execution Time"])
        plan = r["Plan"]
    def nodos(p):
        yield p["Node Type"] + (f" ({p['Index Name']})" if "Index Name" in p else "")
        for h in p.get("Plans", []):
            yield from nodos(h)
    return statistics.median(tiempos), " → ".join(nodos(plan)), plan.get("Shared Hit Blocks", 0) + plan.get("Shared Read Blocks", 0)

resultados = []
for cid, desc, idx, ddl, sql in CASOS:
    conn.autocommit = False
    cur.execute(f"DROP INDEX IF EXISTS {'trz.' + idx}")
    antes = medir(sql)
    conn.rollback()                                            # el índice vuelve a existir
    conn.autocommit = True
    despues = medir(sql)
    resultados.append({"id": cid, "consulta": desc, "indice": idx, "sin_ms": round(antes[0], 3), "con_ms": round(despues[0], 3),
                       "plan_sin": antes[1], "plan_con": despues[1], "bloques_sin": antes[2], "bloques_con": despues[2],
                       "mejora_x": round(antes[0] / despues[0], 1) if despues[0] else None})
    print(f"{cid} {desc}: {antes[0]:.2f} ms → {despues[0]:.3f} ms ({antes[0]/despues[0]:.0f}×) | {antes[1]}  ⇒  {despues[1]}")

salida = {"objetos": n_obj, "historial": n_hist, "resultados": resultados}
json.dump(salida, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "resultados_rendimiento.json"), "w"), ensure_ascii=False, indent=2)
print(f"Volumen: {n_obj} objetos, {n_hist} filas de historial (particionadas por mes)")
conn.close()
