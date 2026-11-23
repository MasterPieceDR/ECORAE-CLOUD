"""Flujo de verificación contra PostgreSQL real."""
import os
import asyncpg
import pytest

pytestmark = pytest.mark.asyncio(loop_scope="session")

async def test_verificacion_y_limites(cliente, monkeypatch):
    codigos = []
    monkeypatch.setattr("app.correo.enviar_codigo", lambda correo, codigo: codigos.append(codigo))
    correo = "verificacion@ejemplo.invalid"
    clave = "Clave-segura-123"
    r = await cliente.post("/auth/registro", json={"alias": "verificacion.prueba", "correo": correo, "password": clave, "organizacion": "GEN-MUNI"})
    assert r.status_code == 201 and r.json()["estado"] == "PENDIENTE_VERIFICACION"
    assert len(codigos) == 1
    r = await cliente.post("/auth/login", json={"correo": correo, "password": clave})
    assert r.status_code == 403 and r.json()["codigo"] == "VERIFICACION_PENDIENTE"
    incorrecto = "000000" if codigos[0] != "000000" else "111111"
    for _ in range(5):
        assert (await cliente.post("/auth/verificar", json={"correo": correo, "codigo": incorrecto})).status_code == 422
    assert (await cliente.post("/auth/verificar", json={"correo": correo, "codigo": codigos[-1]})).status_code == 422
    admin = await asyncpg.connect(host=os.environ["PGHOST"], user=os.environ["PGUSER"], password=os.environ["PGPASSWORD"], database="ecoraee")
    try:
        await cliente.post("/auth/reenviar-codigo", json={"correo": correo})
        assert len(codigos) == 1
        await admin.execute("UPDATE seg.verificacion_correo SET enviado_en=now()-interval '61 seconds' WHERE usuario_id=(SELECT id FROM seg.usuario WHERE correo=$1)", correo)
        await cliente.post("/auth/reenviar-codigo", json={"correo": correo})
        assert len(codigos) == 2
        await admin.execute("UPDATE seg.verificacion_correo SET vence_en=now()-interval '1 second' WHERE usuario_id=(SELECT id FROM seg.usuario WHERE correo=$1)", correo)
        assert (await cliente.post("/auth/verificar", json={"correo": correo, "codigo": codigos[-1]})).status_code == 422
        for _ in range(3):
            await admin.execute("UPDATE seg.verificacion_correo SET enviado_en=now()-interval '61 seconds' WHERE usuario_id=(SELECT id FROM seg.usuario WHERE correo=$1)", correo)
            await cliente.post("/auth/reenviar-codigo", json={"correo": correo})
        assert len(codigos) == 5
        await admin.execute("UPDATE seg.verificacion_correo SET enviado_en=now()-interval '61 seconds' WHERE usuario_id=(SELECT id FROM seg.usuario WHERE correo=$1)", correo)
        await cliente.post("/auth/reenviar-codigo", json={"correo": correo})
        assert len(codigos) == 5
        assert (await cliente.post("/auth/verificar", json={"correo": correo, "codigo": codigos[-1]})).status_code == 200
        assert (await cliente.post("/auth/login", json={"correo": correo, "password": clave})).status_code == 200
        assert (await cliente.post("/auth/login", json={"correo": "coordinador@ejemplo.invalid", "password": "EcoRAEE-2026"})).status_code == 200
    finally:
        await admin.close()
