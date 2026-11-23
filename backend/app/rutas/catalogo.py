"""Catálogo de modelos y sus imágenes; las reglas de edición viven en PostgreSQL."""
from __future__ import annotations

import re
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from .. import almacen, db
from ..config import config
from ..errores import ErrorAPI
from ..seguridad import Sesion, sesion

router = APIRouter(prefix="/catalogo", tags=["Catálogo"])
MAX_IMAGEN = 10 * 1024 * 1024
MimeImagen = Literal["image/jpeg", "image/png", "image/webp"]


class ModeloIn(BaseModel):
    categoria: str = Field(min_length=1, max_length=40)
    marca: str = Field(min_length=1, max_length=40)
    nombre: str = Field(min_length=1, max_length=120)
    anio: int | None = Field(None, ge=1970, le=2100)
    peso: float | None = Field(None, gt=0, le=2000)


class ModeloUpd(BaseModel):
    nombre: str = Field(min_length=1, max_length=120)
    anio: int | None = Field(None, ge=1970, le=2100)
    peso: float | None = Field(None, gt=0, le=2000)
    activo: bool


class ReaperturaIn(BaseModel):
    motivo: str = Field(min_length=5, max_length=300)


class ImagenSubidaIn(BaseModel):
    mime: MimeImagen
    tamano: int = Field(gt=0, le=MAX_IMAGEN)


class ImagenIn(ImagenSubidaIn):
    clave: str = Field(min_length=1, max_length=512)
    sha256: str = Field(pattern=r"^[0-9a-f]{64}$")


@router.get("/modelos")
async def modelos(categoria: str | None = None, marca: str | None = None, q: str | None = None,
                  incluir_inactivos: bool = False, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        return db.filas(await conn.fetch("""SELECT * FROM api.v1_modelo_equipo
            WHERE ($1::text IS NULL OR categoria = $1) AND ($2::text IS NULL OR marca = $2)
              AND ($3::text IS NULL OR nombre ILIKE $3 OR marca_nombre ILIKE $3 OR categoria_nombre ILIKE $3)
              AND ($4::boolean OR activo)
            ORDER BY categoria_nombre, marca_nombre, nombre""",
            categoria, marca, f"%{q.strip()}%" if q and q.strip() else None, incluir_inactivos))


@router.post("/modelos", status_code=201)
async def crear(d: ModeloIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        uid = await conn.fetchval("SELECT api.fn_crear_modelo($1, $2, $3, $4, $5)", d.categoria, d.marca, d.nombre, d.anio, d.peso)
    return {"uid": uid}


@router.put("/modelos/{uid}")
async def actualizar(uid: UUID, d: ModeloUpd, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        await conn.execute("SELECT api.fn_actualizar_modelo($1::uuid, $2, $3, $4, $5)", str(uid), d.nombre, d.anio, d.peso, d.activo)
    return {"ok": True}


@router.post("/modelos/{uid}/reabrir")
async def reabrir(uid: UUID, d: ReaperturaIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        await conn.execute("SELECT api.fn_reabrir_modelo($1::uuid, $2)", str(uid), d.motivo)
    return {"ok": True}


@router.post("/modelos/{uid}/imagen/subida")
async def preparar_imagen(uid: UUID, d: ImagenSubidaIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        await conn.execute("SELECT api.fn_preparar_imagen_modelo($1::uuid)", str(uid))
    bucket = config().bucket_evidencias
    clave = almacen.nueva_clave(f"catalogo/{uid}", d.mime)
    return {"bucket": bucket, "clave": clave, **almacen.actual().url_subida(bucket, clave, d.mime)}


@router.put("/modelos/{uid}/imagen")
async def asignar_imagen(uid: UUID, d: ImagenIn, s: Sesion = Depends(sesion)):
    patron = rf"catalogo/{uid}/[0-9]{{4}}/[0-9]{{2}}/[0-9a-f]{{32}}\.(jpg|png|webp)"
    if not re.fullmatch(patron, d.clave) or not d.clave.endswith(almacen.EXT[d.mime]):
        raise ErrorAPI(422, "Clave de imagen inválida para el modelo", "EC422")
    async with s.tx() as conn:
        await conn.execute("SELECT api.fn_preparar_imagen_modelo($1::uuid)", str(uid))
    if not almacen.actual().verificar_objeto(config().bucket_evidencias, d.clave, d.sha256, d.tamano, d.mime):
        raise ErrorAPI(422, "Las fotografías deben subirse sin metadatos EXIF/GPS", "EC422")
    async with s.tx() as conn:
        await conn.execute("SELECT api.fn_asignar_imagen_modelo($1::uuid, $2)", str(uid), d.clave)
    return {"ok": True}


@router.get("/modelos/{uid}/imagen")
async def imagen(uid: UUID, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        clave = await conn.fetchval("SELECT imagen_clave FROM api.v1_modelo_imagen WHERE uid = $1::uuid", str(uid))
        if not clave:
            raise ErrorAPI(404, "Imagen del modelo no encontrada", "EC404")
    return {"url": almacen.actual().url_descarga(config().bucket_evidencias, clave, 300), "expira_en": 300}
