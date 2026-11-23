"""Envío de códigos después de confirmar la transacción."""
import logging
import smtplib
from email.message import EmailMessage
from .config import config

log = logging.getLogger("ecoraee.correo")


def enviar_codigo(destinatario: str, codigo: str) -> None:
    c = config()
    texto = f"Tu código de verificación de EcoRAEE es {codigo}. Caduca en 15 minutos."
    html = f"<p>Tu código de verificación de EcoRAEE es <strong>{codigo}</strong>.</p><p>Caduca en 15 minutos.</p>"
    try:
        if c.correo_modo == "consola":
            print(f"Correo de verificación para {destinatario}: {texto}", flush=True)
        elif c.correo_modo == "smtp":
            msg = EmailMessage()
            msg["From"], msg["To"], msg["Subject"] = c.correo_remitente, destinatario, "Verifica tu correo en EcoRAEE"
            msg.set_content(texto)
            msg.add_alternative(html, subtype="html")
            with smtplib.SMTP(c.correo_smtp_host, c.correo_smtp_puerto, timeout=10) as smtp:
                if c.correo_smtp_starttls:
                    smtp.starttls()
                if c.correo_smtp_usuario:
                    smtp.login(c.correo_smtp_usuario, c.correo_smtp_clave)
                smtp.send_message(msg)
        elif c.correo_modo == "ses":
            import boto3
            boto3.client("sesv2", region_name=c.aws_region).send_email(
                FromEmailAddress=c.correo_remitente, Destination={"ToAddresses": [destinatario]},
                Content={"Simple": {"Subject": {"Data": "Verifica tu correo en EcoRAEE", "Charset": "UTF-8"},
                                    "Body": {"Text": {"Data": texto, "Charset": "UTF-8"}, "Html": {"Data": html, "Charset": "UTF-8"}}}})
        else:
            raise ValueError("Modo de correo desconocido")
    except Exception:
        log.error("No se pudo enviar el correo de verificación; se puede solicitar otro.")
