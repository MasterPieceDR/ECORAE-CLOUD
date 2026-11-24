"""Almacenamiento de evidencias y videos.

- s3: URL prefirmadas (PUT para subir, GET de 5 minutos para descargar); el bucket es privado (RN-07).
- local: emula las URL prefirmadas con una firma HMAC y guarda los archivos en disco (desarrollo y pruebas).
El navegador sube directo al almacén: la API nunca recibe el binario en modo s3.
"""
from __future__ import annotations

import hashlib
import hmac
import io
import mimetypes
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote, urlencode

from .config import config
from .errores import ErrorAPI

EXT = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp", "application/pdf": ".pdf", "video/mp4": ".mp4", "video/webm": ".webm",
       "video/quicktime": ".mov", "video/x-msvideo": ".avi"}


def nueva_clave(prefijo: str, mime: str) -> str:
    hoy = datetime.now(timezone.utc)
    return f"{prefijo}/{hoy:%Y/%m}/{uuid.uuid4().hex}{EXT.get(mime, '.bin')}"


def _s3(para_firmar: bool = False):
    import boto3
    from botocore.config import Config

    ajustes = config()
    endpoint = ajustes.aws_endpoint_url_publica if para_firmar and ajustes.aws_endpoint_url_publica else ajustes.aws_endpoint_url
    if endpoint:
        return boto3.client("s3", region_name=ajustes.aws_region, endpoint_url=endpoint)
    return boto3.client(
        "s3", region_name=ajustes.aws_region,
        endpoint_url=f"https://s3.{ajustes.aws_region}.amazonaws.com",
        config=Config(signature_version="s3v4", s3={"addressing_style": "virtual"}),
    )


def _firma(metodo: str, bucket: str, clave: str, expira: int) -> str:
    return hmac.new(config().jwt_secreto.encode(), f"{metodo}|{bucket}|{clave}|{expira}".encode(), hashlib.sha256).hexdigest()


def verificar_firma(metodo: str, bucket: str, clave: str, expira: int, firma: str) -> None:
    if expira < time.time() or not hmac.compare_digest(_firma(metodo, bucket, clave, expira), firma):
        raise ErrorAPI(403, "Enlace vencido o inválido", "FIRMA")


def ruta_local(bucket: str, clave: str) -> Path:
    base = Path(config().almacen_dir).resolve()
    p = (base / bucket / clave).resolve()
    if base not in p.parents:
        raise ErrorAPI(400, "Clave inválida", "CLAVE")
    return p


def _verificar_datos(datos: bytes, sha256: str, tamano: int, mime: str) -> bool:
    if len(datos) != int(tamano) or hashlib.sha256(datos).hexdigest() != sha256:
        raise ErrorAPI(422, "El tamaño o la huella SHA-256 no coincide con lo declarado.", "ALMACEN")
    if mime.startswith("image/"):
        try:
            from PIL import Image
            with Image.open(io.BytesIO(datos)) as img:
                formatos = {"image/jpeg": "JPEG", "image/png": "PNG", "image/webp": "WEBP"}
                if formatos.get(mime) != img.format:
                    raise ValueError("El formato no coincide")
                img.load()
                return len(img.getexif()) == 0 and not img.info.get("exif")
        except Exception:
            raise ErrorAPI(422, "La imagen no se pudo leer o no coincide con el formato declarado.", "ALMACEN")
    return True


class AlmacenLocal:
    def url_subida(self, bucket: str, clave: str, mime: str, ttl: int = 900) -> dict:
        expira = int(time.time()) + ttl
        q = urlencode({"expira": expira, "firma": _firma("PUT", bucket, clave, expira)})
        return {"url": f"/api/v1/almacen/{bucket}/{quote(clave)}?{q}", "metodo": "PUT", "cabeceras": {"Content-Type": mime}}

    def url_descarga(self, bucket: str, clave: str, ttl: int = 300, nombre: str | None = None) -> str:
        expira = int(time.time()) + ttl
        return f"/api/v1/almacen/{bucket}/{quote(clave)}?" + urlencode({"expira": expira, "firma": _firma("GET", bucket, clave, expira)})

    def verificar_objeto(self, bucket: str, clave: str, sha256: str, tamano: int, mime: str) -> bool:
        p = ruta_local(bucket, clave)
        if not p.is_file():
            raise ErrorAPI(422, "El archivo no llegó al almacén. Vuelve a subirlo.", "ALMACEN")
        return _verificar_datos(p.read_bytes(), sha256, tamano, mime)

    def eliminar(self, bucket: str, clave: str) -> None:
        ruta_local(bucket, clave).unlink(missing_ok=True)

    async def recibir(self, bucket: str, clave: str, request) -> None:
        destino = ruta_local(bucket, clave)
        destino.parent.mkdir(parents=True, exist_ok=True)
        tamano = 0
        with destino.open("wb") as archivo:
            async for trozo in request.stream():
                tamano += len(trozo)
                if tamano > 500 * 1024 * 1024:
                    archivo.close()
                    destino.unlink(missing_ok=True)
                    raise ErrorAPI(413, "Archivo demasiado grande", "ALMACEN")
                archivo.write(trozo)

    def respuesta(self, bucket: str, clave: str):
        from fastapi.responses import FileResponse, Response
        ruta = ruta_local(bucket, clave)
        if ruta.exists():
            return FileResponse(ruta)
        if clave.startswith("demo/"):
            contenido, tipo = placeholder(clave)
            return Response(contenido, media_type=tipo)
        raise ErrorAPI(404, "Archivo no encontrado en el almacén", "ALMACEN")


class AlmacenS3:
    def url_subida(self, bucket: str, clave: str, mime: str, ttl: int = 900) -> dict:
        url = _s3(para_firmar=True).generate_presigned_url("put_object", Params={"Bucket": bucket, "Key": clave, "ContentType": mime}, ExpiresIn=ttl)
        return {"url": url, "metodo": "PUT", "cabeceras": {"Content-Type": mime}}

    def url_descarga(self, bucket: str, clave: str, ttl: int = 300, nombre: str | None = None) -> str:
        params = {"Bucket": bucket, "Key": clave}
        if nombre:
            params["ResponseContentDisposition"] = f'inline; filename="{nombre}"'
        return _s3(para_firmar=True).generate_presigned_url("get_object", Params=params, ExpiresIn=ttl)

    def verificar_objeto(self, bucket: str, clave: str, sha256: str, tamano: int, mime: str) -> bool:
        try:
            cliente = _s3()
            if not mime.startswith("image/"):
                objeto = cliente.head_object(Bucket=bucket, Key=clave)
                if int(objeto["ContentLength"]) != int(tamano):
                    raise ErrorAPI(422, "El tamaño del archivo no coincide con lo declarado.", "ALMACEN")
                return True
            if tamano > 10 * 1024 * 1024:
                raise ErrorAPI(422, "La imagen supera el límite de 10 MB.", "ALMACEN")
            objeto = cliente.get_object(Bucket=bucket, Key=clave)
            cuerpo = objeto["Body"]
            try:
                if int(objeto["ContentLength"]) != int(tamano):
                    raise ErrorAPI(422, "El tamaño del archivo no coincide con lo declarado.", "ALMACEN")
                datos = cuerpo.read(tamano + 1)
            finally:
                cuerpo.close()
        except ErrorAPI:
            raise
        except Exception:
            raise ErrorAPI(422, "El archivo no llegó al almacén. Vuelve a subirlo.", "ALMACEN")
        return _verificar_datos(datos, sha256, tamano, mime)

    def eliminar(self, bucket: str, clave: str) -> None:
        _s3().delete_object(Bucket=bucket, Key=clave)


def actual() -> AlmacenLocal | AlmacenS3:
    modo = config().almacen_modo
    if modo == "local":
        return AlmacenLocal()
    if modo == "s3":
        return AlmacenS3()
    raise RuntimeError(f"ALMACEN_MODO desconocido: {modo}")


# Conserva las llamadas existentes mientras los routers migran a la interfaz.
def url_subida(*args, **kwargs):
    return actual().url_subida(*args, **kwargs)


def url_descarga(*args, **kwargs):
    return actual().url_descarga(*args, **kwargs)


def verificar_objeto(*args, **kwargs):
    return actual().verificar_objeto(*args, **kwargs)


def eliminar(*args, **kwargs):
    return actual().eliminar(*args, **kwargs)


def placeholder(clave: str) -> tuple[bytes, str]:
    """Archivos de los datos de demostración (claves demo/…): se generan al vuelo, sin datos reales."""
    tipo = mimetypes.guess_type(clave)[0] or "application/octet-stream"
    nombre = Path(clave).stem.split("-")[0].replace("_", " ").upper()
    if tipo == "image/png":
        from PIL import Image, ImageDraw
        img = Image.new("RGB", (640, 400), (18, 52, 40))
        d = ImageDraw.Draw(img)
        d.rectangle((24, 24, 616, 376), outline=(150, 230, 170), width=3)
        d.text((48, 180), f"EcoRAEE · {nombre} (sintética)", fill=(220, 245, 230))
        buf = io.BytesIO()
        img.save(buf, "PNG")
        return buf.getvalue(), tipo
    texto = f"EcoRAEE Cloud - {nombre} - documento sintetico de demostracion"
    contenido = f"BT /F1 16 Tf 60 760 Td ({texto}) Tj ET".encode()
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            b"<< /Length %d >>\nstream\n" % len(contenido) + contenido + b"\nendstream",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    pdf, offs = b"%PDF-1.4\n", []
    for i, o in enumerate(objs, 1):
        offs.append(len(pdf))
        pdf += b"%d 0 obj\n" % i + o + b"\nendobj\n"
    xref = len(pdf)
    pdf += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1) + b"".join(b"%010d 00000 n \n" % x for x in offs)
    pdf += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
    return pdf, "application/pdf"
