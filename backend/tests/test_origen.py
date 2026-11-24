"""Protección de la API frente a solicitudes que no pasan por el origen autorizado."""
import pytest
from httpx import ASGITransport, AsyncClient

from app.config import config
from app.main import app


@pytest.mark.asyncio
@pytest.mark.parametrize("secreto,cabecera,esperado", [
    ("", None, 200),
    ("secreto-prueba", None, 403),
    ("secreto-prueba", "incorrecto", 403),
    ("secreto-prueba", "secreto-prueba", 200),
])
async def test_verificacion_origen(monkeypatch, secreto, cabecera, esperado):
    monkeypatch.setattr(config(), "origin_secret", secreto)
    headers = {"X-Origin-Verify": cabecera} if cabecera is not None else {}
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as cliente:
        respuesta = await cliente.get("/api/v1/salud", headers=headers)
    assert respuesta.status_code == esperado
