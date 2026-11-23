"""Evidencias (RN-03, RN-07, RNF-10): subida directa al almacén con URL prefirmada y descarga con propósito explícito."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from .. import almacen, db
from ..config import config
from ..errores import ErrorAPI
from ..seguridad import Sesion, sesion

router = APIRouter(prefix="/evidencias", tags=["Evidencias"])
MAX_BYTES = 25 * 1024 * 1024
MAX_IMAGEN = 10 * 1024 * 1024


def validar_tamano(mime: str, tamano: int):
    if mime.startswith("image/") and tamano > MAX_IMAGEN:
        raise ErrorAPI(422, "La imagen supera el límite de 10 MB", "EC422")


class SubidaIn(BaseModel):
    tipo: str
    mime: str
    tamano: int = Field(gt=0, le=MAX_BYTES)


class RegistroIn(BaseModel):
    tipo: str
    clave: str
    sha256: str = Field(pattern="^[0-9a-f]{64}$")
    mime: str
    tamano: int = Field(gt=0, le=MAX_BYTES)
    objeto: str | None = None            # solo para evidencias del objeto (p. ej. certificado de borrado)


@router.post("/subida")
async def preparar_subida(d: SubidaIn, s: Sesion = Depends(sesion)):
    """Devuelve la URL donde el navegador sube el archivo. La API no recibe el binario."""
    validar_tamano(d.mime, d.tamano)
    async with s.tx() as conn:
        cat = await conn.fetchval("SELECT api.fn_catalogos() -> 'tipos_evidencia'")
        eco = await conn.fetchval("SELECT (api.fn_perfil() ->> 'ecosistema')")
    tipo = next((t for t in cat if t["codigo"] == d.tipo), None)
    if not tipo:
        raise ErrorAPI(404, f"Tipo de evidencia {d.tipo} no existe", "EC404")
    if d.mime not in tipo["mime"]:
        raise ErrorAPI(422, f"Formato {d.mime} no permitido para {tipo['nombre']}: usa {', '.join(tipo['mime'])}", "EC422")
    bucket = config().bucket_evidencias
    clave = almacen.nueva_clave(f"eco-{eco}/{d.tipo.lower()}", d.mime)
    return {"bucket": bucket, "clave": clave, **almacen.url_subida(bucket, clave, d.mime)}


@router.post("", status_code=201)
async def registrar(d: RegistroIn, s: Sesion = Depends(sesion)):
    validar_tamano(d.mime, d.tamano)
    bucket = config().bucket_evidencias
    if not d.clave.startswith("eco-"):
        raise ErrorAPI(422, "Clave de almacenamiento inválida", "EC422")
    limpio = almacen.verificar_objeto(bucket, d.clave, d.sha256, d.tamano, d.mime)
    async with s.tx() as conn:
        uid = await conn.fetchval("SELECT api.fn_registrar_evidencia($1, $2, $3, $4, $5, $6, $7, $8::uuid)",
                                  d.tipo, bucket, d.clave, d.sha256, d.mime, d.tamano, limpio, d.objeto)
    return {"uid": uid}


@router.get("/{uid}/descarga")
async def descargar(uid: str, proposito: str = "TRAZABILIDAD", s: Sesion = Depends(sesion)):
    """RN-07: la base decide si el rol puede descargar ese tipo con ese propósito y deja el acceso en bitácora."""
    async with s.tx() as conn:
        r = await conn.fetchval("SELECT api.fn_obtener_evidencia($1::uuid, $2)", uid, proposito)
    if not r["permitido"]:
        raise ErrorAPI(403, f"Tu rol no puede descargar esta evidencia con el propósito {proposito} (RN-07). El intento quedó registrado.", "EC403")
    return {"url": almacen.url_descarga(r["bucket"], r["clave"], r.get("ttl_segundos", 300)), "expira_en": r.get("ttl_segundos", 300),
            "sha256": r["sha256"]}
