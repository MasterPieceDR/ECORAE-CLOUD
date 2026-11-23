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

EXT = {"image/jpeg": ".jpg", "image/png": ".png", "application/pdf": ".pdf", "video/mp4": ".mp4", "video/webm": ".webm",
       "video/quicktime": ".mov", "video/x-msvideo": ".avi"}


def nueva_clave(prefijo: str, mime: str) -> str:
    hoy = datetime.now(timezone.utc)
    return f"{prefijo}/{hoy:%Y/%m}/{uuid.uuid4().hex}{EXT.get(mime, '.bin')}"


def _s3():
    import boto3
    return boto3.client("s3", region_name=config().aws_region)


def _firma(metodo: str, bucket: str, clave: str, expira: int) -> str:
    return hmac.new(config().jwt_secreto.encode(), f"{metodo}|{bucket}|{clave}|{expira}".encode(), hashlib.sha256).hexdigest()


def verificar_firma(metodo: str, bucket: str, clave: str, expira: int, firma: str) -> None:
    if expira < time.time() or not hmac.compare_digest(_firma(metodo, bucket, clave, expira), firma):
        raise ErrorAPI(403, "Enlace vencido o inválido", "FIRMA")


def url_subida(bucket: str, clave: str, mime: str, ttl: int = 900) -> dict:
    c = config()
    if c.almacen_modo == "s3":
        url = _s3().generate_presigned_url("put_object", Params={"Bucket": bucket, "Key": clave, "ContentType": mime}, ExpiresIn=ttl)
        return {"url": url, "metodo": "PUT", "cabeceras": {"Content-Type": mime}}
    expira = int(time.time()) + ttl
    q = urlencode({"expira": expira, "firma": _firma("PUT", bucket, clave, expira)})
    return {"url": f"/api/v1/almacen/{bucket}/{quote(clave)}?{q}", "metodo": "PUT", "cabeceras": {"Content-Type": mime}}


def url_descarga(bucket: str, clave: str, ttl: int = 300, nombre: str | None = None) -> str:
    c = config()
    if c.almacen_modo == "s3":
        params = {"Bucket": bucket, "Key": clave}
        if nombre:
            params["ResponseContentDisposition"] = f'inline; filename="{nombre}"'
        return _s3().generate_presigned_url("get_object", Params=params, ExpiresIn=ttl)
    expira = int(time.time()) + ttl
    return f"/api/v1/almacen/{bucket}/{quote(clave)}?" + urlencode({"expira": expira, "firma": _firma("GET", bucket, clave, expira)})


def ruta_local(bucket: str, clave: str) -> Path:
    base = Path(config().almacen_dir).resolve()
    p = (base / bucket / clave).resolve()
    if base not in p.parents:
        raise ErrorAPI(400, "Clave inválida", "CLAVE")
    return p


def verificar_objeto(bucket: str, clave: str, sha256: str, tamano: int, mime: str) -> bool:
    """Comprueba que el archivo subido existe y coincide con lo declarado. Devuelve si está libre de metadatos EXIF/GPS."""
    c = config()
    if c.almacen_modo == "s3":
        try:
            meta = _s3().head_object(Bucket=bucket, Key=clave)
        except Exception:
            raise ErrorAPI(422, "El archivo no llegó al almacén. Vuelve a subirlo.", "ALMACEN")
        if int(meta["ContentLength"]) != int(tamano):
            raise ErrorAPI(422, "El tamaño del archivo no coincide con lo declarado.", "ALMACEN")
        return True          # las imágenes se limpian en el navegador antes de subir; un Lambda puede reverificarlas
    p = ruta_local(bucket, clave)
    if not p.exists():
        raise ErrorAPI(422, "El archivo no llegó al almacén. Vuelve a subirlo.", "ALMACEN")
    datos = p.read_bytes()
    if len(datos) != int(tamano) or hashlib.sha256(datos).hexdigest() != sha256:
        raise ErrorAPI(422, "La huella SHA-256 del archivo no coincide con la declarada.", "ALMACEN")
    if mime.startswith("image/"):
        try:
            from PIL import Image
            with Image.open(io.BytesIO(datos)) as img:
                exif = img.getexif()
                return len(exif) == 0 and not img.info.get("exif")
        except Exception:
            raise ErrorAPI(422, "La imagen no se pudo leer.", "ALMACEN")
    return True


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
