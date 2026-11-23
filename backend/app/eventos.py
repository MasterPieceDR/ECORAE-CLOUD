"""Gancho opcional: llamar únicamente después de confirmar la transacción."""
import json
import logging
import os

log = logging.getLogger("ecoraee.eventos")


def publicar_evento(tipo: str, datos: dict) -> None:
    """Publica de forma tolerante a fallos; el llamador debe programarlo tras el commit.

    Si se necesita que la petición tampoco espere a SNS, ejecutar en una tarea de fondo.
    No incluir secretos ni datos personales en datos.
    """
    arn = os.getenv("SNS_TOPIC_ARN")
    if not arn:
        return
    try:
        import boto3
        boto3.client("sns", region_name=os.getenv("AWS_REGION")).publish(
            TopicArn=arn, Message=json.dumps({"tipo": tipo, "datos": datos}, ensure_ascii=False),
        )
    except Exception:
        log.exception("No se pudo publicar el evento SNS")
