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
