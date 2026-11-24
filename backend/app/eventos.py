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
        asunto = {"trazabilidad.cerrada": "Trazabilidad cerrada", "transferencia.enviada": "Transferencia enviada", "transferencia.recibida": "Transferencia recibida"}.get(tipo, "Evento EcoRAEE")
        lineas = [f"Tipo: {asunto} ({tipo})", f"Número de documento: {datos.get('numero', 'No disponible')}"]
        for clave, etiqueta in (("objeto", "Objeto"), ("objetos", "Objetos"), ("nodo_origen", "Nodo de origen"), ("nodo_destino", "Nodo de destino"), ("estado", "Estado"), ("fecha", "Fecha")):
            if clave in datos:
                valor = datos[clave]
                lineas.append(f"{etiqueta}: {', '.join(map(str, valor)) if isinstance(valor, list) else valor}")
        if not any(k in datos for k in ("objeto", "objetos", "nodo_origen", "nodo_destino")):
            lineas.append("Objetos y nodos: no disponibles en este evento")
        mensaje = {"default": json.dumps({"tipo": tipo, "datos": datos}, ensure_ascii=False, default=str), "email": "\n".join(lineas)}
        boto3.client("sns", region_name=os.getenv("AWS_REGION")).publish(
            TopicArn=arn, Message=json.dumps(mensaje, ensure_ascii=False, default=str), MessageStructure="json",
            Subject={"trazabilidad.cerrada": "Trazabilidad cerrada", "transferencia.enviada": "Transferencia enviada", "transferencia.recibida": "Transferencia recibida"}.get(tipo, "Evento EcoRAEE"),
            MessageAttributes={"tipo": {"DataType": "String", "StringValue": tipo}},
        )
    except Exception:
        log.exception("No se pudo publicar el evento SNS")
