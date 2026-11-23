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
