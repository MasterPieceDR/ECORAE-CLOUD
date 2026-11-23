# EcoRAEE Cloud — /database

Base de datos final del Proyecto Integrador (Grupo 7, UIDE). PostgreSQL 16 / Amazon RDS.

## Recrear desde cero (RNF-09)

```bash
export PGHOST=<host> PGUSER=<usuario_admin>
./run.sh                                   # 01 → 05: estructura, lógica, api/MCP, seguridad, semillas
psql -d ecoraee -f 06_pruebas.sql          # 84 pruebas → tabla prueba.resultado
python3 ../math/flujo_maximo.py            # flujo máximo E0–E3 leído desde la base (requiere psycopg2, networkx)
./07_concurrencia.sh                       # dos sesiones simultáneas sobre la misma arista
python3 08_rendimiento.py                  # planes y tiempos con/sin índices (crea ecoraee_perf)
python3 09_exportar.py                     # diccionario.json y diagramas (Graphviz + Mermaid)
```

En RDS, crear antes los logins de servicio y asignarles los roles de grupo:
`ecoraee_api_svc → ecoraee_app`, `ecoraee_mcp_svc → ecoraee_mcp`, `ecoraee_ro_svc → ecoraee_lectura`, `ecoraee_audit_svc → ecoraee_auditor`.
Los objetos deben pertenecer a un rol propietario (no al usuario maestro) para que las funciones `SECURITY DEFINER` operen con mínimo privilegio.

## Contrato para la API y el servidor MCP

1. Al inicio de cada transacción: `SELECT api.fn_iniciar_contexto(:uid_usuario, 'WEB'|'API'|'MCP'|'BATCH', :request_id);`
2. Lecturas: vistas `api.v1_*` (RLS aplicado al usuario del contexto).
3. Escrituras: funciones `api.fn_*`. Errores propios: EC401, EC403, EC404, EC409, EC422 → HTTP 401/403/404/409/422.
4. MCP: `api.v1_mcp_catalogo` (tools/list), `api.fn_mcp_autorizar`, ejecutar el objeto registrado, `api.fn_mcp_registrar`; recursos con `api.fn_mcp_leer_recurso('ecoraee://…')`.

Usuarios de prueba: uid `00000000-0000-4000-8000-0000000000NN` (01 generador … 15 comité). Todos los datos son sintéticos.
