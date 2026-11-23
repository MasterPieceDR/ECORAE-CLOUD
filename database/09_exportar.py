"""Exporta desde el catálogo: diccionario (JSON), diagramas ER por dominio (Graphviz + Mermaid) y diagrama de estados."""
import json, os, subprocess, psycopg2, html
OUT = os.environ.get("OUT", "./salida")
conn = psycopg2.connect(host="/srv/pg", user="postgres", dbname="ecoraee"); cur = conn.cursor()
cur.execute("""SELECT d.esquema, d.nombre, e.nombre_tabla, e.tipo_entidad, e.clasificacion_datos, e.descripcion, e.expuesta_mcp, e.retencion,
       json_agg(json_build_object('col',a.nombre_columna,'tipo',a.tipo_dato,'nulo',a.nulo,'pk',a.es_pk,'fk',a.es_fk,'ref',a.referencia,
                'desc',a.descripcion,'pii',a.es_pii,'der',a.es_derivado,'def',a.valor_defecto) ORDER BY a.posicion)
  FROM meta.entidad e JOIN meta.dominio d ON d.id=e.dominio_id JOIN meta.atributo a ON a.entidad_id=e.id
 GROUP BY d.id, d.esquema, d.nombre, e.nombre_tabla, e.tipo_entidad, e.clasificacion_datos, e.descripcion, e.expuesta_mcp, e.retencion
 ORDER BY d.id, e.nombre_tabla""")
dic = [dict(zip(["esquema","dominio","tabla","tipo","clasif","desc","mcp","ret","cols"], r)) for r in cur.fetchall()]
json.dump(dic, open(f"{OUT}/diccionario.json","w"), ensure_ascii=False, indent=1)
cur.execute("""SELECT c.conrelid::regclass::text, c.confrelid::regclass::text,
       bool_and(a.attnotnull), array_agg(a.attname::text)
  FROM pg_constraint c JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum = ANY(c.conkey)
  JOIN pg_class k ON k.oid=c.conrelid WHERE c.contype='f' AND NOT k.relispartition
   AND c.conrelid::regclass::text !~ '^prueba' GROUP BY c.oid, c.conrelid, c.confrelid""")
fks = cur.fetchall()
tipo = {f"{t['esquema']}.{t['tabla']}": t['tipo'] for t in dic}
COLOR = {"SUPERTIPO":"#1F4E79","SUBTIPO":"#2E75B6","FUERTE":"#385723","DEBIL":"#7F6000","ASOCIATIVA":"#7030A0",
         "TEMPORAL":"#C55A11","BITACORA":"#595959","CATALOGO":"#0E6E6E","METADATO":"#3A3A3A"}
DOMINIOS = {
 "01_nucleo_trazabilidad": ("Núcleo de trazabilidad: objetos, documentos e inventario", ["trz","ops","inv"], ["cat.estado_trazabilidad","cat.clasificacion_tecnica","cat.categoria_raee","cat.tipo_destino","cat.tipo_tratamiento","org.ubicacion","org.organizacion","seg.usuario","red.arista","cat.clasificacion_destino_permitido","cat.criterio_evaluacion","cat.material","cat.motivo","cat.transicion_estado"]),
 "02_red_flujo": ("Red, capacidades, escenarios y resultados de flujo", ["red"], ["cat.tipo_nodo","cat.unidad_medida","org.centro","org.organizacion","seg.ecosistema","seg.usuario","gob.excepcion_regla","cat.arista_tipo_permitida"]),
 "03_seguridad_organizacion": ("Identidad, roles, organizaciones, centros y ubicaciones", ["seg","org"], ["cat.tipo_actor","cat.actor_negocio","cat.categoria_raee","cat.tipo_centro","cat.unidad_medida"]),
 "04_evidencias_gobierno_mcp": ("Evidencias, gobierno, indicadores, auditoría y MCP", ["evd","gob","ind","aud","mcp","integ"], ["seg.rol","seg.usuario","seg.ecosistema","cat.tipo_evidencia","cat.proposito_uso","ops.documento_operativo","trz.objeto_trazable","red.arista","org.centro"]),
}
def cols_key(t):
    for x in dic:
        if f"{x['esquema']}.{x['tabla']}" == t: return x["cols"]
    return []
for clave, (titulo, esquemas, extras) in DOMINIOS.items():
    tablas = [f"{t['esquema']}.{t['tabla']}" for t in dic if t["esquema"] in esquemas] + extras
    g = ['digraph G {', 'graph [rankdir=LR, splines=true, nodesep=0.35, ranksep=0.9, fontname="Helvetica", fontsize=20, labelloc=t, label="%s", pad=0.3];' % titulo,
         'node [shape=plain, fontname="Helvetica", fontsize=10]; edge [color="#7f7f7f", arrowsize=0.7, dir=both];']
    for t in tablas:
        ext = t in extras
        col = "#A6A6A6" if ext else COLOR.get(tipo.get(t), "#385723")
        filas = []
        for c in cols_key(t):
            if ext and not c["pk"]: continue
            if not ext and not (c["pk"] or c["fk"]) and len([k for k in cols_key(t) if not (k['pk'] or k['fk'])]) > 6:
                continue
            m = ("PK " if c["pk"] else "") + ("FK" if c["fk"] else "")
            celda = f'<font point-size="8" color="#C00000">{m.strip()}</font>' if m else ''
            filas.append(f'<tr><td align="left">{celda}</td><td align="left">{html.escape(c["col"])}</td><td align="left"><font color="#7f7f7f" point-size="8">{html.escape(c["tipo"][:18])}</font></td></tr>')
        if not ext:
            otros = [c for c in cols_key(t) if not (c["pk"] or c["fk"])]
            if len(otros) > 6: filas.append(f'<tr><td></td><td align="left" colspan="2"><font color="#7f7f7f" point-size="8">+ {len(otros)} atributos (ver diccionario)</font></td></tr>')
        etiqueta = (f'<<table border="0" cellborder="0" cellspacing="0" cellpadding="3" bgcolor="white" color="{col}" style="rounded">'
                    f'<tr><td colspan="3" bgcolor="{col}"><font color="white"><b>{t}</b></font></td></tr>{"".join(filas)}</table>>')
        g.append(f'"{t}" [label={etiqueta}];')
    for hijo, padre, oblig, cs in fks:
        if hijo in tablas and padre in tablas:
            rec = hijo == padre
            g.append(f'"{hijo}" -> "{padre}" [arrowtail=crowodot, arrowhead={"teetee" if oblig else "teeodot"}{", color=\"#C00000\", penwidth=1.6" if rec else ""}, tooltip="{",".join(cs)}"];')
    g.append("}")
    open(f"{OUT}/diagramas/{clave}.dot","w").write("\n".join(g))
    subprocess.run(["dot","-Tpng","-Gdpi=170",f"{OUT}/diagramas/{clave}.dot","-o",f"{OUT}/diagramas/{clave}.png"], check=True)
    # Mermaid editable (requisito del enunciado)
    mm = ["erDiagram"]
    for t in tablas:
        if t in extras: continue
        n = t.replace(".","__")
        mm.append(f"  {n} {{")
        for c in cols_key(t):
            tp = c["tipo"].split("(")[0].replace(" ","_").replace("[]","_arr")
            mm.append(f'    {tp} {c["col"]}{" PK" if c["pk"] else ""}{" FK" if c["fk"] and not c["pk"] else ""}')
        mm.append("  }")
    for hijo, padre, oblig, cs in fks:
        if hijo in tablas and padre in tablas and hijo not in extras and padre not in extras:
            mm.append(f'  {padre.replace(".","__")} {"||" if oblig else "|o"}--o{{ {hijo.replace(".","__")} : "{cs[0]}"')
    open(f"{OUT}/diagramas/{clave}.mmd","w").write("\n".join(mm))
# Diagrama de estados generado desde cat.transicion_estado
cur.execute("""SELECT o.codigo, d.codigo, t.permiso_requerido, t.requiere_evidencia, t.requiere_clasificacion FROM cat.transicion_estado t
  JOIN cat.estado_trazabilidad o ON o.id=t.estado_origen_id JOIN cat.estado_trazabilidad d ON d.id=t.estado_destino_id ORDER BY o.orden, d.orden""")
tr = cur.fetchall()
cur.execute("SELECT codigo, es_inicial, es_final FROM cat.estado_trazabilidad ORDER BY orden"); est = cur.fetchall()
g = ['digraph S {','graph [rankdir=LR, fontname="Helvetica", nodesep=0.4, ranksep=0.55, pad=0.2];',
     'node [shape=box, style="rounded,filled", fillcolor="#DEEAF6", color="#2E75B6", fontname="Helvetica", fontsize=11];',
     'edge [fontname="Helvetica", fontsize=8, color="#595959", fontcolor="#404040", arrowsize=0.7];']
for c, ini, fin in est:
    if ini: g.append(f'"{c}" [fillcolor="#E2EFDA", color="#548235", penwidth=2];')
    if fin: g.append(f'"{c}" [fillcolor="#F2F2F2", color="#404040", peripheries=2];')
for o, d, p, ev, cl in tr:
    marca = ("📎" if ev else "") 
    g.append(f'"{o}" -> "{d}" [label="{p.split(".")[0].lower()}{" · ev" if ev else ""}{" · clas" if cl else ""}"];')
g.append("}")
open(f"{OUT}/diagramas/05_ciclo_de_vida.dot","w").write("\n".join(g))
subprocess.run(["dot","-Tpng","-Gdpi=170",f"{OUT}/diagramas/05_ciclo_de_vida.dot","-o",f"{OUT}/diagramas/05_ciclo_de_vida.png"], check=True)
mm = ["stateDiagram-v2"] + [f"  [*] --> {c}" for c, i, f in est if i] + [f"  {o} --> {d} : {p}" for o, d, p, ev, cl in tr] + [f"  {c} --> [*]" for c, i, f in est if f]
open(f"{OUT}/diagramas/05_ciclo_de_vida.mmd","w").write("\n".join(mm))
# Vista general: esquemas como clústeres
g = ['digraph V {','graph [rankdir=LR, compound=true, fontname="Helvetica", nodesep=0.12, ranksep=1.1, pad=0.2];',
     'node [shape=box, style="rounded,filled", fontname="Helvetica", fontsize=9, height=0.25, margin="0.06,0.03"]; edge [color="#00000030", arrowsize=0.4];']
from collections import defaultdict
por = defaultdict(list)
for t in dic: por[(t["esquema"], t["dominio"])].append(t)
for (esq, dom), ts in por.items():
    g.append(f'subgraph "cluster_{esq}" {{ label="{esq} · {dom}"; style="rounded"; color="#BFBFBF"; fontsize=12;')
    for t in ts:
        g.append(f'"{esq}.{t["tabla"]}" [label="{t["tabla"]}", fillcolor="{COLOR.get(t["tipo"],"#385723")}", fontcolor="white", color="{COLOR.get(t["tipo"],"#385723")}"];')
    g.append("}")
for hijo, padre, oblig, cs in fks:
    if hijo != padre: g.append(f'"{hijo}" -> "{padre}";')
g.append("}")
open(f"{OUT}/diagramas/00_vista_general.dot","w").write("\n".join(g))
subprocess.run(["dot","-Tpng","-Gdpi=150",f"{OUT}/diagramas/00_vista_general.dot","-o",f"{OUT}/diagramas/00_vista_general.png"], check=True)
print(len(dic), "tablas;", sum(len(t["cols"]) for t in dic), "atributos;", len(fks), "FK")
