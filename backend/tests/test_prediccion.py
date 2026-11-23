import pytest
from app.prediccion import holt

def test_constante():
    r = holt([10] * 20, 4)
    assert all(p["valor"] == 10 and p["inferior"] == 10 for p in r["pronostico"])
    assert r["mape"] == 0

def test_tendencia():
    r = holt(list(range(1, 21)), 4)
    assert [p["valor"] for p in r["pronostico"]] == [21, 22, 23, 24]

def test_corta():
    with pytest.raises(ValueError): holt([1, 2, 3])


@pytest.mark.asyncio
async def test_endpoint_usa_plataforma_sin_historico(monkeypatch):
    from datetime import date, timedelta
    from contextlib import asynccontextmanager
    from app.rutas import prediccion

    inicio = date(2025, 1, 6)
    filas = [{"fuente": "PLATAFORMA", "semana": inicio + timedelta(weeks=i),
              "equipos": 0 if i == 3 else 10, "peso": 20, "completa": i < 9}
             for i in range(10)]

    class Conexion:
        async def fetch(self, *args):
            return filas

    class Sesion:
        @asynccontextmanager
        async def tx(self):
            yield Conexion()

    class Perfil:
        def rol(self, rol):
            return rol == "ADMINISTRADOR"

    async def perfil(conn):
        return Perfil()

    monkeypatch.setattr(prediccion, "perfil", perfil)
    resultado = await prediccion.recoleccion(categoria=None, semanas=4, medida="equipos", s=Sesion())
    assert resultado["fuente_modelo"] == "PLATAFORMA"
    assert len(resultado["historia"]) == 9 and len(resultado["plataforma"]) == 10
    assert resultado["historia"][3]["valor"] == 0
    assert resultado["pronostico"][0]["semana"] == filas[-1]["semana"].isoformat()
    assert "plataforma" in resultado["nota"]
