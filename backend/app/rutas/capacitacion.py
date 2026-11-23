"""Capacitación (esquema edu, ADR-011): videos educativos, comentarios y reacciones."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from .. import almacen, db
from ..config import config
from ..errores import ErrorAPI
from ..seguridad import Sesion, sesion

router = APIRouter(prefix="/capacitacion", tags=["Capacitación"])
MIMES = {"video/mp4", "video/webm", "video/quicktime", "video/x-msvideo"}
MAX = 500 * 1024 * 1024


class SubidaIn(BaseModel):
    mime: str
    tamano: int = Field(gt=0, le=MAX)


class ContenidoIn(BaseModel):
    titulo: str = Field(min_length=3, max_length=160)
    descripcion: str | None = Field(None, max_length=2000)
    tema: str
    clave: str | None = None
    mime: str | None = None
    tamano: int | None = Field(None, gt=0, le=MAX)
    duracion_seg: int | None = Field(None, ge=0)


class ComentarioIn(BaseModel):
    texto: str = Field(min_length=1, max_length=1000)


class ModeracionIn(BaseModel):
    estado: str = Field(pattern="^(PUBLICADO|OCULTO)$")


@router.get("")
async def listar(q: str | None = None, tema: str | None = None, mios: bool = False, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        t = f"%{q.strip()}%" if q and q.strip() else None
        return db.filas(await conn.fetch("""
            SELECT uid, titulo, descripcion, tema, duracion_seg, estado, autor, organizacion_autor, publicado_en, tiene_archivo,
                   vistas, me_gusta, comentarios, me_gusta_yo, es_mio
              FROM api.v1_contenido
             WHERE ($1::text IS NULL OR titulo ILIKE $1 OR descripcion ILIKE $1) AND ($2::text IS NULL OR tema = $2) AND (NOT $3 OR es_mio)
             ORDER BY publicado_en DESC""", t, tema, mios))


@router.get("/actividad")
async def mi_actividad(s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        contenidos = db.filas(await conn.fetch("SELECT uid, titulo, tema, publicado_en, vistas, me_gusta, comentarios, estado, tiene_archivo "
                                               "FROM api.v1_contenido WHERE es_mio ORDER BY publicado_en DESC"))
        comentarios = db.filas(await conn.fetch("SELECT uid, contenido_uid, contenido_titulo, texto, creado_en FROM api.v1_comentario "
                                                "WHERE es_mio ORDER BY creado_en DESC LIMIT 50"))
    return {"contenidos": contenidos, "comentarios": comentarios}


@router.get("/{uid}")
async def ver(uid: str, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        c = await conn.fetchrow("SELECT * FROM api.v1_contenido WHERE uid = $1", uid)
        if not c:
            raise ErrorAPI(404, "Contenido no encontrado", "EC404")
        await conn.execute("SELECT api.fn_registrar_vista($1::uuid)", uid)
        media = await conn.fetchval("SELECT api.fn_media_contenido($1::uuid)", uid)
        comentarios = db.filas(await conn.fetch("SELECT uid, autor, texto, creado_en, es_mio FROM api.v1_comentario "
                                                "WHERE contenido_uid = $1 ORDER BY creado_en DESC", uid))
    d = dict(c)
    d.pop("ecosistema_id", None)
    d["video_url"] = almacen.url_descarga(media["bucket"], media["clave"], media["ttl_segundos"]) if media else None
    d["comentarios_lista"] = comentarios
    return d


@router.post("/subida")
async def preparar_subida(d: SubidaIn, s: Sesion = Depends(sesion)):
    if d.mime not in MIMES:
        raise ErrorAPI(422, "Formatos permitidos: MP4, WEBM, MOV o AVI", "EC422")
    async with s.tx() as conn:
        eco = await conn.fetchval("SELECT (api.fn_perfil() ->> 'ecosistema')")
    bucket = config().bucket_contenidos
    clave = almacen.nueva_clave(f"eco-{eco}/videos", d.mime)
    return {"bucket": bucket, "clave": clave, **almacen.url_subida(bucket, clave, d.mime, ttl=3600)}


@router.post("", status_code=201)
async def publicar(d: ContenidoIn, s: Sesion = Depends(sesion)):
    bucket = None
    if d.clave:
        if not (d.mime and d.tamano) or not d.clave.startswith("eco-"):
            raise ErrorAPI(422, "Datos del archivo incompletos", "EC422")
        bucket = config().bucket_contenidos
        if config().almacen_modo == "local" and not almacen.ruta_local(bucket, d.clave).exists():
            raise ErrorAPI(422, "El video no llegó al almacén. Vuelve a subirlo.", "ALMACEN")
    async with s.tx() as conn:
        uid = await conn.fetchval("SELECT api.fn_publicar_contenido($1, $2, $3, $4, $5, $6, $7, $8)",
                                  d.titulo, d.descripcion, d.tema, bucket, d.clave, d.mime, d.tamano, d.duracion_seg)
    return {"uid": uid}


@router.post("/{uid}/reaccion")
async def reaccionar(uid: str, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        return await conn.fetchval("SELECT api.fn_reaccionar($1::uuid)", uid)


@router.post("/{uid}/comentarios", status_code=201)
async def comentar(uid: str, d: ComentarioIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        k = await conn.fetchval("SELECT api.fn_comentar($1::uuid, $2)", uid, d.texto)
        return dict(await conn.fetchrow("SELECT uid, autor, texto, creado_en, es_mio FROM api.v1_comentario WHERE uid = $1", k))


@router.post("/{uid}/moderacion")
async def moderar(uid: str, d: ModeracionIn, s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        await conn.execute("SELECT api.fn_moderar_contenido($1::uuid, $2)", uid, d.estado)
    return {"ok": True}
