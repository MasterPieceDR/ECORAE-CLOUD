import json
from uuid import UUID
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import BackgroundTasks

from app import eventos
from app.rutas import documentos


@pytest.mark.asyncio
@pytest.mark.parametrize(('endpoint', 'datos', 'tipo'), [
    (documentos.transferir, documentos.TransferenciaIn(objetos=['obj'], nodo_origen='A', nodo_destino='B'), 'transferencia.enviada'),
    (documentos.recibir_transferencia, documentos.RecibirTransferenciaIn(evidencias=['ev']), 'transferencia.recibida'),
    (documentos.cerrar, documentos.CierreIn(objeto='obj', evidencias=['ev']), 'trazabilidad.cerrada'),
])
async def test_evento_despues_del_commit(endpoint, datos, tipo):
    conn = MagicMock()
    conn.fetchval = AsyncMock(side_effect=['DOC-1'] if endpoint is documentos.recibir_transferencia else ['uid', 'DOC-1'])
    conn.execute = AsyncMock()
    tx = MagicMock()
    tx.__aenter__ = AsyncMock(return_value=conn)
    tx.__aexit__ = AsyncMock(return_value=False)
    sesion = MagicMock()
    sesion.tx.return_value = tx
    tareas = BackgroundTasks()
    args = ('uid', datos, tareas, sesion) if endpoint is documentos.recibir_transferencia else (datos, tareas, sesion)
    await endpoint(*args)
    tx.__aexit__.assert_awaited_once()
    assert len(tareas.tasks) == 1
    assert tareas.tasks[0].args[0] == tipo
    assert tareas.tasks[0].args[1]['numero'] == 'DOC-1'


def test_publicar_evento_sin_configuracion(monkeypatch):
    monkeypatch.delenv('SNS_TOPIC_ARN', raising=False)
    with patch('boto3.client') as cliente:
        eventos.publicar_evento('transferencia.enviada', {})
        cliente.assert_not_called()


def test_publicar_evento_con_atributo(monkeypatch):
    monkeypatch.setenv('SNS_TOPIC_ARN', 'arn:ejemplo')
    with patch('boto3.client') as cliente:
        eventos.publicar_evento('trazabilidad.cerrada', {'numero': 'DOC-1'})
        envio = cliente.return_value.publish.call_args.kwargs
        assert envio['MessageAttributes']['tipo']['StringValue'] == 'trazabilidad.cerrada'
        assert envio['Subject'] == 'Trazabilidad cerrada'



def test_publicar_uuid_y_correo_legible(monkeypatch):
    monkeypatch.setenv('SNS_TOPIC_ARN', 'arn:ejemplo')
    uid = UUID('12345678-1234-5678-1234-567812345678')
    datos = {'uid': uid, 'numero': 'DOC-1', 'objetos': [uid], 'nodo_origen': 'A', 'nodo_destino': 'B', 'estado': 'ENVIADA', 'fecha': '2026-11-23'}
    with patch('boto3.client') as cliente:
        eventos.publicar_evento('transferencia.enviada', datos)
        envio = cliente.return_value.publish.call_args.kwargs
    assert envio['MessageStructure'] == 'json'
    mensajes = json.loads(envio['Message'])
    assert json.loads(mensajes['default'])['datos']['uid'] == str(uid)
    for texto in ('Transferencia enviada', 'DOC-1', str(uid), 'A', 'B', 'ENVIADA', '2026-11-23'):
        assert texto in mensajes['email']
