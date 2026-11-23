"""Preparación reversible de producción sobre una transacción aislada."""
import os

import asyncpg
import pytest

from app import db, flujo


@pytest.mark.asyncio
async def test_preparar_produccion(base_de_datos):
    conn = await asyncpg.connect(host=os.environ['PGHOST'], user=os.environ['PGUSER'],
                                 password=os.environ['PGPASSWORD'], database='ecoraee')
    await db._init(conn)
    tx = conn.transaction()
    await tx.start()
    try:
        admin = await conn.fetchval("SELECT seg.fn_preparar_produccion($1,$2,$3,NULL)",
                                    'nuevo@produccion.invalid', 'admin.nuevo', 'Clave-administrador-1234')
        cuentas = await conn.fetch("""SELECT correo FROM seg.usuario WHERE
            uid BETWEEN '00000000-0000-4000-8000-000000000001'::uuid AND '00000000-0000-4000-8000-000000000018'::uuid
            OR correo='gestor.d1@ejemplo.invalid'""")
        assert len(cuentas) == 19
        for cuenta in cuentas:
            assert await conn.fetchval('SELECT api.fn_autenticar_local($1,$2)', cuenta['correo'], 'EcoRAEE-2026') is None
        assert await conn.fetchval('SELECT api.fn_autenticar_local($1,$2)', 'nuevo@produccion.invalid', 'Clave-administrador-1234') == admin
        assert not await conn.fetchval("SELECT has_function_privilege('ecoraee_api_svc','seg.fn_preparar_produccion(text,text,text,text)','EXECUTE')")
        await conn.fetchval("SELECT api.fn_iniciar_contexto($1::uuid,'BATCH',NULL)", '00000000-0000-4000-8000-000000000099')
        resultado = await flujo.calcular(conn, 'E0', registrar=True)
        assert resultado['ejecucion_id']
        await conn.fetchval('SELECT seg.fn_preparar_produccion($1,$2,$3,$4)',
                            'nuevo@produccion.invalid', 'admin.nuevo', 'Clave-administrador-1234', 'Clave-evaluacion-1234')
        for cuenta in cuentas:
            assert await conn.fetchval('SELECT api.fn_autenticar_local($1,$2)', cuenta['correo'], 'Clave-evaluacion-1234')
    finally:
        await tx.rollback()
        await conn.close()
