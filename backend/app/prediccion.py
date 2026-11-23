"""Suavizado exponencial doble de Holt con validación temporal."""
from math import sqrt


def _ajustar(serie, alfa, beta):
    nivel, tendencia = float(serie[0]), float(serie[1] - serie[0])
    residuos = []
    for valor in serie[1:]:
        residuos.append(float(valor) - (nivel + tendencia))
        anterior = nivel
        nivel = alfa * valor + (1 - alfa) * (nivel + tendencia)
        tendencia = beta * (nivel - anterior) + (1 - beta) * tendencia
    return nivel, tendencia, residuos


def holt(serie, semanas=8):
    if len(serie) < 8 or semanas < 1:
        raise ValueError("Se necesitan al menos ocho semanas de historia")
    valores = [float(x) for x in serie]
    entrenamiento, validacion = valores[:-4], valores[-4:]
    mejor = None
    for a in (0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9):
        for b in (0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9):
            nivel, tendencia, _ = _ajustar(entrenamiento, a, b)
            error = sum((v - (nivel + (i + 1) * tendencia)) ** 2 for i, v in enumerate(validacion))
            if mejor is None or error < mejor[0]:
                mejor = (error, a, b, nivel, tendencia)
    _, a, b, nivel, tendencia = mejor
    errores = [abs(v - (nivel + (i + 1) * tendencia)) / abs(v) for i, v in enumerate(validacion) if v != 0]
    mape = round(100 * sum(errores) / len(errores), 2) if errores else None
    nivel, tendencia, residuos = _ajustar(valores, a, b)
    sigma = sqrt(sum(x*x for x in residuos) / len(residuos))
    pronostico = []
    for h in range(1, semanas + 1):
        centro = max(0, nivel + h * tendencia)
        margen = 1.28155 * sigma * sqrt(h)
        pronostico.append({"valor": round(centro, 2), "inferior": round(max(0, centro-margen), 2), "superior": round(centro+margen, 2)})
    return {"parametros": {"alfa": a, "beta": b}, "mape": mape, "pronostico": pronostico}
