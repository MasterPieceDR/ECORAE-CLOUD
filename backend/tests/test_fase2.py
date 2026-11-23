"""Pruebas del contrato común de los almacenes de la fase 2."""
import hashlib
import io

import pytest
from PIL import Image

from app import almacen
from app.errores import ErrorAPI


@pytest.mark.parametrize("formato,mime", [("PNG", "image/png"), ("WEBP", "image/webp")])
def test_almacen_local_verifica_imagen(monkeypatch, tmp_path, formato, mime):
    monkeypatch.setattr(almacen, "ruta_local", lambda bucket, clave: tmp_path / clave)
    salida = io.BytesIO()
    Image.new("RGB", (8, 8)).save(salida, formato)
    datos = salida.getvalue()
    (tmp_path / "foto").write_bytes(datos)
    local = almacen.AlmacenLocal()
    assert local.verificar_objeto("bucket", "foto", hashlib.sha256(datos).hexdigest(), len(datos), mime)
    with pytest.raises(ErrorAPI):
        local.verificar_objeto("bucket", "foto", "0" * 64, len(datos), mime)
    local.eliminar("bucket", "foto")
    assert not (tmp_path / "foto").exists()


def test_almacen_s3_verifica_contenido(monkeypatch):
    salida = io.BytesIO()
    Image.new("RGB", (8, 8)).save(salida, "PNG")
    datos = salida.getvalue()

    class Cliente:
        def get_object(self, **kwargs):
            return {"ContentLength": len(datos), "Body": io.BytesIO(datos)}

        def head_object(self, **kwargs):
            return {"ContentLength": 500 * 1024 * 1024}

    monkeypatch.setattr(almacen, "_s3", lambda: Cliente())
    s3 = almacen.AlmacenS3()
    assert s3.verificar_objeto("bucket", "clave", hashlib.sha256(datos).hexdigest(), len(datos), "image/png")
    with pytest.raises(ErrorAPI):
        s3.verificar_objeto("bucket", "clave", "0" * 64, len(datos), "image/png")
    assert s3.verificar_objeto("bucket", "video", "0" * 64, 500 * 1024 * 1024, "video/mp4")
    with pytest.raises(ErrorAPI):
        s3.verificar_objeto("bucket", "video", "0" * 64, 100, "video/mp4")
    with pytest.raises(ErrorAPI):
        s3.verificar_objeto("bucket", "foto", "0" * 64, 10 * 1024 * 1024 + 1, "image/png")

@pytest.mark.asyncio(loop_scope="session")
async def test_catalogo_serie_y_fotos_en_base(cliente):
    """El contrato SQL aplica permisos, coherencia, serie y límite de fotos con el login de la API."""
    import asyncpg
    from uuid import uuid4
    from app import db

    coordinador = "00000000-0000-4000-8000-000000000009"
    generador = "00000000-0000-4000-8000-000000000001"
    sufijo = uuid4().hex[:10].upper()
    async with db.pool("api").acquire() as conn:
        tx = conn.transaction()
        await tx.start()
        try:
            await conn.fetchval("SELECT api.fn_iniciar_contexto($1::uuid)", coordinador)
            modelo = await conn.fetchval("SELECT api.fn_crear_modelo('MONITOR', 'LG', $1, 2020, 3)", f"Prueba {sufijo}")
            await conn.execute("SELECT api.fn_actualizar_modelo($1::uuid, $2, 2021, 4, true)", modelo, f"Actualizado {sufijo}")
            await conn.fetchval("SELECT api.fn_iniciar_contexto($1::uuid)", generador)

            async def falla(estado, consulta, *argumentos):
                with pytest.raises(asyncpg.PostgresError) as error:
                    async with conn.transaction():
                        await conn.fetchval(consulta, *argumentos)
                assert error.value.sqlstate == estado

            await falla("EC403", "SELECT api.fn_crear_modelo('MONITOR', 'LG', 'Denegado', 2020, 3)")
            await falla("EC422", "SELECT api.fn_registrar_dispositivo('MAL-CAT', 'CELULAR', 1, true, 'LG', NULL, 'PRUEBA-99', 2020, '{}'::jsonb, NULL, NULL, $1::uuid)", modelo)
            equipo = await conn.fetchval("""SELECT api.fn_registrar_dispositivo($1, 'MONITOR', 3, false, 'LG', NULL,
                                           $2, 2020, '{"pulgadas":20}'::jsonb, NULL, NULL, $3::uuid)""",
                                        f"MON-{sufijo}", f"  ab-{sufijo.lower()}  ", modelo)
            fila = await conn.fetchrow("SELECT modelo, modelo_uid, modelo_en_catalogo, numero_serie FROM api.v1_dispositivo WHERE uid = $1::uuid", equipo)
            assert fila["modelo"] == f"Actualizado {sufijo}" and fila["modelo_uid"] == modelo
            assert fila["modelo_en_catalogo"] and fila["numero_serie"] == f"AB-{sufijo}"
            await falla("EC409", "SELECT api.fn_registrar_dispositivo($1, 'MONITOR', 3, false, NULL, NULL, $2, 2020, '{\"pulgadas\":20}'::jsonb)", f"DUP-{sufijo}", f"ab-{sufijo.lower()}")
            await falla("EC422", "SELECT api.fn_registrar_dispositivo($1, 'CELULAR', 1, true, NULL, NULL, NULL, 2020, '{}'::jsonb)", f"SIN-{sufijo}")
            await falla("EC422", "SELECT api.fn_registrar_dispositivo($1, 'MONITOR', 3, false, NULL, NULL, 'AB?', 2020, '{\"pulgadas\":20}'::jsonb)", f"BAD-{sufijo}")
            libre = await conn.fetchval("SELECT api.fn_registrar_dispositivo($1, 'MONITOR', 3, false, NULL, 'Modelo libre', NULL, 2020, '{\"pulgadas\":20}'::jsonb)", f"LIB-{sufijo}")
            fila = await conn.fetchrow("SELECT modelo, modelo_en_catalogo FROM api.v1_objeto_operativo WHERE uid = $1::uuid", libre)
            assert fila["modelo"] == "Modelo libre" and not fila["modelo_en_catalogo"]
            consulta = "SELECT api.fn_registrar_evidencia('FOTO_EQUIPO', 'pruebas', $1, $2, 'image/webp', 100, true, $3::uuid)"
            for i in range(5):
                await conn.fetchval(consulta, f"{sufijo}-{i}", hashlib.sha256(f"{sufijo}-{i}".encode()).hexdigest(), libre)
            await falla("EC422", consulta, f"{sufijo}-6", hashlib.sha256(f"{sufijo}-6".encode()).hexdigest(), libre)
            await conn.fetchval("SELECT api.fn_anular_objeto($1::uuid, 'Registro duplicado')", equipo)
            await conn.fetchval("SELECT api.fn_registrar_dispositivo($1, 'MONITOR', 3, false, NULL, NULL, $2, 2020, '{\"pulgadas\":20}'::jsonb)", f"REU-{sufijo}", f"AB-{sufijo}")
        finally:
            await tx.rollback()


def imagen_prueba(formato="PNG", color=(23, 87, 149)):
    salida = io.BytesIO()
    Image.new("RGB", (8, 8), color).save(salida, formato)
    return salida.getvalue()


async def subir_imagen_modelo(actor, uid, datos, mime="image/png"):
    r = await actor.post(f"/catalogo/modelos/{uid}/imagen/subida", {"mime": mime, "tamano": len(datos)})
    assert r.status_code == 200, r.text
    subida = r.json()
    r = await actor.c.put(subida["url"].removeprefix("/api/v1"), content=datos, headers=subida["cabeceras"])
    assert r.status_code == 200, r.text
    return await actor.put(f"/catalogo/modelos/{uid}/imagen", {"clave": subida["clave"], "sha256": hashlib.sha256(datos).hexdigest(),
                                                                "mime": mime, "tamano": len(datos)})


@pytest.mark.asyncio(loop_scope="session")
async def test_fase2_catalogo_modelos_y_regla_24h(actores):
    import os
    from uuid import uuid4
    import psycopg2

    coord, gen, admin = (actores[x] for x in ("coordinador", "gen.universidad", "admin"))
    nombre = f"Modelo prueba {uuid4().hex[:8]}"
    datos = {"categoria": "MONITOR", "marca": "LG", "nombre": nombre, "anio": 2020, "peso": 3.5}
    assert (await gen.post("/catalogo/modelos", datos)).status_code == 403
    r = await coord.post("/catalogo/modelos", datos)
    assert r.status_code == 201, r.text
    uid = r.json()["uid"]
    lista = await gen.get("/catalogo/modelos", params={"categoria": "MONITOR", "marca": "LG", "q": nombre})
    assert lista.status_code == 200 and any(m["uid"] == uid and m["editable"] for m in lista.json())
    cambio = {"nombre": nombre + " editado", "anio": 2021, "peso": 4, "activo": True}
    assert (await coord.put(f"/catalogo/modelos/{uid}", cambio)).status_code == 200
    imagen = imagen_prueba()
    r = await subir_imagen_modelo(coord, uid, imagen)
    assert r.status_code == 200, r.text
    r = await gen.get(f"/catalogo/modelos/{uid}/imagen")
    assert r.status_code == 200 and r.json()["expira_en"] == 300
    descarga = await gen.c.get(r.json()["url"].removeprefix("/api/v1"))
    assert descarga.status_code == 200 and descarga.content == imagen
    assert (await gen.post(f"/catalogo/modelos/{uid}/imagen/subida", {"mime": "image/png", "tamano": len(imagen)})).status_code == 403

    with psycopg2.connect(dbname=os.getenv("DB_NOMBRE", "ecoraee"), host=os.getenv("PGHOST", "localhost"),
                          user=os.getenv("PGUSER", "ecoraee_admin"), password=os.getenv("PGPASSWORD")) as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE cat.modelo_equipo SET editable_hasta = now() - interval '1 hour' WHERE uid = %s", (uid,))
    r = await coord.put(f"/catalogo/modelos/{uid}", cambio)
    assert r.status_code == 409 and "bloqueado" in r.json()["detail"]
    assert (await coord.post(f"/catalogo/modelos/{uid}/imagen/subida", {"mime": "image/png", "tamano": len(imagen)})).status_code == 409
    assert (await coord.post(f"/catalogo/modelos/{uid}/reabrir", {"motivo": "Corregir datos"})).status_code == 403
    assert (await admin.post(f"/catalogo/modelos/{uid}/reabrir", {"motivo": "Corregir datos"})).status_code == 200
    assert (await coord.put(f"/catalogo/modelos/{uid}", cambio)).status_code == 200


@pytest.mark.asyncio(loop_scope="session")
async def test_fase2_objetos_modelo_serie_y_fotos(actores):
    from uuid import uuid4

    gen, otro, coord = (actores[x] for x in ("gen.universidad", "gen.municipio", "coordinador"))
    sufijo = uuid4().hex[:10].upper()
    r = await coord.post("/catalogo/modelos", {"categoria": "MONITOR", "marca": "LG", "nombre": f"Monitor {sufijo}", "anio": 2020, "peso": 3})
    assert r.status_code == 201, r.text
    modelo = r.json()["uid"]
    base = {"categoria": "MONITOR", "peso_kg": 3, "atributos": {"pulgadas": 22}}
    assert (await gen.post("/objetos/dispositivos", {"categoria": "CELULAR", "peso_kg": 1, "modelo_uid": modelo, "numero_serie": f"BAD-{sufijo}"})).status_code == 422
    assert (await gen.post("/objetos/dispositivos", {**base, "marca": "HP", "modelo_uid": modelo})).status_code == 422
    assert (await gen.post("/objetos/dispositivos", {**base, "numero_serie": "abc?"})).status_code == 422
    assert (await gen.post("/objetos/dispositivos", {"categoria": "CELULAR", "peso_kg": 1})).status_code == 422
    serie = f"F2/{sufijo}"
    r = await gen.post("/objetos/dispositivos", {**base, "modelo_uid": modelo, "numero_serie": f"  {serie.lower()}  "})
    assert r.status_code == 201, r.text
    codigo, uid = r.json()["codigo"], r.json()["uid"]
    ficha = (await gen.get(f"/objetos/{codigo}")).json()
    assert ficha["dispositivo"]["modelo_uid"] == modelo and ficha["dispositivo"]["numero_serie"] == serie
    assert ficha["dispositivo"]["marca"] == "LG"
    duplicado = await gen.post("/objetos/dispositivos", {**base, "numero_serie": serie.lower()})
    assert duplicado.status_code == 409 and serie in duplicado.json()["detail"] and codigo in duplicado.json()["detail"]
    assert any(x["codigo"] == codigo for x in (await gen.get("/objetos", params={"q": serie})).json()["objetos"])
    assert any(x["codigo"] == codigo for x in (await gen.get("/objetos", params={"serie": serie.lower()})).json()["objetos"])
    assert (await gen.get(f"/objetos/serie/{serie.lower()}")).json()["objeto"]["codigo"] == codigo
    assert (await otro.get(f"/objetos/serie/{serie}")).status_code == 404
    disponible = (await otro.get("/objetos/serie-disponible", params={"serie": serie})).json()
    assert disponible["valida"] and not disponible["disponible"]
    assert (await gen.get("/objetos/serie-disponible", params={"serie": serie, "excluir": uid})).json()["disponible"]
    assert not (await gen.get("/objetos/serie-disponible", params={"serie": "?"})).json()["valida"]
    libre = await gen.post("/objetos/dispositivos", {**base, "modelo": f"Modelo libre {sufijo}"})
    assert libre.status_code == 201, libre.text
    ficha = (await gen.get(f"/objetos/{libre.json()['codigo']}")).json()
    assert ficha["dispositivo"]["modelo"] == f"Modelo libre {sufijo}" and not ficha["dispositivo"]["modelo_en_catalogo"]
    cambio = {"peso_kg": 3, "modelo_uid": modelo, "numero_serie": serie, "atributos": {"pulgadas": 22}, "motivo": "Corregir modelo"}
    assert (await gen.put(f"/objetos/dispositivos/{uid}", cambio)).status_code == 200

    for i in range(5):
        formato, mime = ("WEBP", "image/webp") if i == 1 else ("PNG", "image/png")
        await gen.evidencia("FOTO_EQUIPO", mime, imagen_prueba(formato, (i * 30, 100, 120)), uid)
    datos = imagen_prueba("PNG", (200, 50, 40))
    r = await gen.post("/evidencias/subida", {"tipo": "FOTO_EQUIPO", "mime": "image/png", "tamano": len(datos)})
    subida = r.json()
    await gen.c.put(subida["url"].removeprefix("/api/v1"), content=datos, headers=subida["cabeceras"])
    r = await gen.post("/evidencias", {"tipo": "FOTO_EQUIPO", "clave": subida["clave"], "sha256": hashlib.sha256(datos).hexdigest(),
                                       "mime": "image/png", "tamano": len(datos), "objeto": uid})
    assert r.status_code == 422, r.text
    r = await gen.get(f"/objetos/{codigo}/fotos")
    assert r.status_code == 200 and len(r.json()) == 5 and all(x["url"] for x in r.json()), r.text
    assert {x["mime"] for x in r.json()} == {"image/png", "image/webp"}
    descarga = await gen.c.get(r.json()[0]["url"].removeprefix("/api/v1"))
    assert descarga.status_code == 200
    # La entrega de las cinco URL debe haber registrado cinco accesos RN-07.
    import os
    import psycopg2
    with psycopg2.connect(dbname=os.getenv("DB_NOMBRE", "ecoraee"), host=os.getenv("PGHOST", "localhost"),
                          user=os.getenv("PGUSER", "ecoraee_admin"), password=os.getenv("PGPASSWORD")) as conn:
        with conn.cursor() as cur:
            cur.execute("""SELECT count(*) FROM evd.acceso_evidencia a JOIN evd.evidencia_vinculo v ON v.evidencia_id = a.evidencia_id
                            JOIN trz.objeto_trazable o ON o.id = v.objeto_id WHERE o.uid = %s AND a.resultado = 'PERMITIDO'""", (uid,))
            assert cur.fetchone()[0] == 5
    assert (await otro.get(f"/objetos/{codigo}/fotos")).status_code == 404
    assert (await gen.post("/evidencias/subida", {"tipo": "FOTO_EQUIPO", "mime": "image/png", "tamano": 10 * 1024 * 1024 + 1})).status_code == 422


@pytest.mark.asyncio(loop_scope="session")
async def test_prediccion_endpoint(actores):
    for alias in ("coordinador", "admin", "auditor", "comite"):
        r = await actores[alias].get("/prediccion/recoleccion", params={"semanas": 4, "medida": "peso"})
        assert r.status_code == 200, r.text
        datos = r.json()
        assert datos["disponible"], datos
        assert len(datos["historia"]) == 52 and len(datos["pronostico"]) == 4
        assert datos["fuente_modelo"] == "RED_HISTORICO"
        assert "sintético" in datos["nota"]
        assert datos["pronostico"][0]["inferior"] <= datos["pronostico"][0]["valor"] <= datos["pronostico"][0]["superior"]
    r = await actores["gen.universidad"].get("/prediccion/recoleccion")
    assert r.status_code == 403


@pytest.mark.asyncio(loop_scope="session")
async def test_prediccion_fallo_aislado(actores, monkeypatch):
    from app.rutas import prediccion
    def fallar(*args, **kwargs):
        raise RuntimeError("fallo simulado")
    monkeypatch.setattr(prediccion, "holt", fallar)
    r = await actores["coordinador"].get("/prediccion/recoleccion")
    assert r.status_code == 200 and not r.json()["disponible"]
    assert (await actores["coordinador"].get("/tablero")).status_code == 200

@pytest.mark.asyncio(loop_scope="session")
async def test_prediccion_fuentes_huecos_y_semana_actual(actores):
    import os
    import psycopg2
    from datetime import datetime, timedelta
    from zoneinfo import ZoneInfo

    hoy = datetime.now(ZoneInfo("America/Guayaquil")).date()
    actual = hoy - timedelta(days=hoy.weekday())
    with psycopg2.connect(dbname=os.getenv("DB_NOMBRE", "ecoraee"), host=os.getenv("PGHOST", "localhost"),
                          user=os.getenv("PGUSER", "ecoraee_admin"), password=os.getenv("PGPASSWORD")) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id, codigo FROM cat.categoria_raee WHERE nivel=2 ORDER BY id LIMIT 1")
            categoria_id, codigo = cur.fetchone()
            hueco = actual - timedelta(weeks=3)
            cur.execute("SELECT equipos, peso_kg FROM ind.historial_recoleccion_semanal WHERE categoria_id=%s AND semana=%s", (categoria_id, hueco))
            original = cur.fetchone()
            cur.execute("DELETE FROM ind.historial_recoleccion_semanal WHERE categoria_id=%s AND semana=%s", (categoria_id, hueco))
            cur.execute("INSERT INTO ind.historial_recoleccion_semanal VALUES (%s,%s,999,999,true)", (actual, categoria_id))
        conn.commit()
        try:
            r = await actores["coordinador"].get("/prediccion/recoleccion", params={"categoria": codigo})
            datos = r.json()
            assert r.status_code == 200 and datos["disponible"]
            assert datos["fuente_modelo"] == "RED_HISTORICO"
            historia = {x["semana"]: x["valor"] for x in datos["historia"]}
            assert historia[hueco.isoformat()] == 0
            assert actual.isoformat() not in historia
            assert datos["pronostico"][0]["semana"] == actual.isoformat()
            assert all(x["semana"] <= actual.isoformat() for x in datos["plataforma"])
        finally:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM ind.historial_recoleccion_semanal WHERE categoria_id=%s AND semana=%s", (categoria_id, actual))
                cur.execute("INSERT INTO ind.historial_recoleccion_semanal VALUES (%s,%s,%s,%s,true)", (hueco, categoria_id, *original))
            conn.commit()


def test_serie_separa_fuentes_y_categorias(base_de_datos):
    import os
    import psycopg2

    with psycopg2.connect(dbname=os.getenv("DB_NOMBRE", "ecoraee"), host=os.getenv("PGHOST", "localhost"),
                          user=os.getenv("PGUSER", "ecoraee_admin"), password=os.getenv("PGPASSWORD")) as conn:
        with conn.cursor() as cur:
            cur.execute("""SELECT c.codigo, count(h.semana) FROM cat.categoria_raee c
                           LEFT JOIN ind.historial_recoleccion_semanal h ON h.categoria_id=c.id AND h.sintetico
                           WHERE c.nivel=2 GROUP BY c.codigo""")
            assert all(n == 52 for _, n in cur.fetchall())
            cur.execute("SELECT semana, categoria, equipos, peso_kg FROM api.v1_serie_recoleccion WHERE fuente='PLATAFORMA' LIMIT 1")
            semana, categoria, equipos, peso = cur.fetchone()
            cur.execute("SELECT id FROM cat.categoria_raee WHERE codigo=%s AND nivel=2", (categoria,))
            categoria_id = cur.fetchone()[0]
            cur.execute("""INSERT INTO ind.historial_recoleccion_semanal (semana, categoria_id, equipos, peso_kg, sintetico)
                           VALUES (%s, %s, 999999, 999999, true)
                           ON CONFLICT (semana, categoria_id) DO UPDATE SET equipos=999999, peso_kg=999999, sintetico=true""", (semana, categoria_id))
            cur.execute("SELECT fuente, equipos, peso_kg FROM api.v1_serie_recoleccion WHERE semana=%s AND categoria=%s ORDER BY fuente", (semana, categoria))
            assert cur.fetchall() == [('PLATAFORMA', equipos, peso), ('RED_HISTORICO', 999999, 999999)]
            cur.execute("""SELECT count(*) FROM api.v1_serie_recoleccion v JOIN cat.categoria_raee c ON c.codigo=v.categoria WHERE c.nivel <> 2""")
            assert cur.fetchone()[0] == 0
        conn.rollback()


def test_script_historial_se_puede_reaplicar(base_de_datos):
    import os
    import psycopg2
    from pathlib import Path

    script = (Path(__file__).resolve().parents[2] / "database" / "18_historial_recoleccion.sql").read_text(encoding="utf-8")
    with psycopg2.connect(dbname=os.getenv("DB_NOMBRE", "ecoraee"), host=os.getenv("PGHOST", "localhost"),
                          user=os.getenv("PGUSER", "ecoraee_admin"), password=os.getenv("PGPASSWORD")) as conn:
        with conn.cursor() as cur:
            cur.execute("""INSERT INTO ind.historial_recoleccion_semanal
                           SELECT current_date, id, 99, 99, true FROM cat.categoria_raee WHERE nivel=1""")
            cur.execute(script)
            cur.execute("""SELECT count(*) FROM ind.historial_recoleccion_semanal h
                           JOIN cat.categoria_raee c ON c.id=h.categoria_id WHERE h.sintetico AND c.nivel <> 2""")
            assert cur.fetchone()[0] == 0
            cur.execute("""SELECT count(*) FROM cat.categoria_raee c WHERE c.nivel=2 AND
                           (SELECT count(*) FROM ind.historial_recoleccion_semanal h WHERE h.categoria_id=c.id AND h.sintetico) <> 52""")
            assert cur.fetchone()[0] == 0
        conn.rollback()
