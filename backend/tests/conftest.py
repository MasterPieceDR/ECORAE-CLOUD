"""Pruebas de integración de la API contra un PostgreSQL real recreado desde los scripts (sin mocks de la base)."""
from __future__ import annotations

import hashlib
import io
import os
import subprocess
from pathlib import Path

import httpx
import pytest
import pytest_asyncio

RAIZ = Path(__file__).resolve().parents[2]
CLAVE = "EcoRAEE-2026"


@pytest.fixture(scope="session", autouse=True)
def base_de_datos():
    """Recrea la base con datos de demostración antes de la sesión (RNF-09: reproducible desde scripts)."""
    if os.getenv("ECORAEE_NO_RECREAR") != "1":
        env = {**os.environ, "API_DB_PASS": os.getenv("DB_CLAVE_API", "api_dev_pass"), "MCP_DB_PASS": os.getenv("DB_CLAVE_MCP", "mcp_dev_pass")}
        subprocess.run([str(RAIZ / "database" / "cargar_demo.sh")], check=True, env=env, capture_output=True)
    yield


@pytest_asyncio.fixture(scope="session")
async def cliente(base_de_datos, tmp_path_factory):
    os.environ.setdefault("ALMACEN_DIR", str(tmp_path_factory.mktemp("almacen")))
    from app import db
    from app.main import app
    await db.abrir()
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://prueba/api/v1") as c:
        yield c
    await db.cerrar()


class Actor:
    """Un usuario sintético con su token, como lo usaría el frontend."""

    def __init__(self, c: httpx.AsyncClient, alias: str, token: str):
        self.c, self.alias, self.h = c, alias, {"Authorization": f"Bearer {token}"}

    async def get(self, ruta, **kw):
        return await self.c.get(ruta, headers=self.h, **kw)

    async def post(self, ruta, json=None, **kw):
        return await self.c.post(ruta, headers=self.h, json=json if json is not None else {}, **kw)

    async def put(self, ruta, json=None, **kw):
        return await self.c.put(ruta, headers=self.h, json=json if json is not None else {}, **kw)

    async def delete(self, ruta, **kw):
        return await self.c.delete(ruta, headers=self.h, **kw)

    async def evidencia(self, tipo: str, mime: str = "application/pdf", datos: bytes | None = None, objeto: str | None = None) -> str:
        """Sube un archivo como el navegador: pide URL firmada, hace PUT y registra la evidencia."""
        datos = datos or (png_limpio() if mime.startswith("image/") else b"%PDF-1.4\n% evidencia sintetica " + os.urandom(8).hex().encode() + b"\n%%EOF\n")
        r = await self.post("/evidencias/subida", {"tipo": tipo, "mime": mime, "tamano": len(datos)})
        assert r.status_code == 200, r.text
        s = r.json()
        put = await self.c.put(s["url"].removeprefix("/api/v1"), content=datos, headers={"Content-Type": mime})
        assert put.status_code == 200, put.text
        r = await self.post("/evidencias", {"tipo": tipo, "clave": s["clave"], "sha256": hashlib.sha256(datos).hexdigest(),
                                            "mime": mime, "tamano": len(datos), "objeto": objeto})
        assert r.status_code == 201, r.text
        return r.json()["uid"]


def png_limpio() -> bytes:
    from PIL import Image
    buf = io.BytesIO()
    Image.new("RGB", (8, 8), tuple(os.urandom(3))).save(buf, "PNG")
    return buf.getvalue()


def jpeg_con_gps() -> bytes:
    from PIL import Image
    img = Image.new("RGB", (8, 8), (200, 10, 10))
    exif = img.getexif()
    exif[0x8825] = {2: (0, 13, 0), 4: (78, 30, 0)}       # GPSInfo
    exif[0x010F] = "CamaraX"
    buf = io.BytesIO()
    img.save(buf, "JPEG", exif=exif)
    return buf.getvalue()


@pytest_asyncio.fixture(scope="session")
async def actores(cliente):
    salida = {}
    for alias in ("coordinador", "gen.universidad", "gen.municipio", "operador.c1", "operador.c2", "operador.e1", "tecnico.e1",
                  "tecnico.r1", "gestor.r1", "gestor.k1", "gestor.d1", "beneficiario", "admin", "auditor", "comite"):
        r = await cliente.post("/auth/login", json={"correo": f"{alias}@ejemplo.invalid", "password": CLAVE})
        assert r.status_code == 200, r.text
        salida[alias] = Actor(cliente, alias, r.json()["access_token"])
    return salida
