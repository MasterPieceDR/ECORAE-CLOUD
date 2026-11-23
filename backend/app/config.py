"""Configuración externa (RNF-06): variables de entorno y, en AWS, Secrets Manager. Ningún secreto vive en el código."""
from __future__ import annotations

import json
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Config(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    entorno: str = "desarrollo"                     # desarrollo | produccion
    version: str = "1.0.0"

    # Base de datos: un login por servicio (mínimo privilegio, script 11)
    db_host: str = "localhost"
    db_port: int = 5432
    db_nombre: str = "ecoraee"
    db_usuario_api: str = "ecoraee_api_svc"
    db_clave_api: str = ""
    db_usuario_mcp: str = "ecoraee_mcp_svc"
    db_clave_mcp: str = ""
    db_secret_arn: str | None = None               # en AWS: {"host","port","dbname","api":{...},"mcp":{...}}
    db_ssl: bool = False
    db_pool_min: int = 1
    db_pool_max: int = 10

    # Identidad
    auth_modo: str = "local"                        # local (MVP) | cognito
    jwt_secreto: str = "cambiar-en-produccion"
    jwt_secret_arn: str | None = None
    jwt_minutos: int = 480
    cognito_region: str = "us-east-1"
    cognito_user_pool_id: str = ""
    cognito_client_id: str = ""
    demo: bool = True                               # expone las cuentas sintéticas en el inicio de sesión

    # Almacenamiento de evidencias y videos
    almacen_modo: str = "local"                     # local | s3
    almacen_dir: str = "./almacen"
    bucket_evidencias: str = "ecoraee-evidencias"
    bucket_contenidos: str = "ecoraee-contenidos"
    aws_region: str = "us-east-1"
    aws_endpoint_url: str | None = None

    # Web
    cors_origenes: str = "http://localhost:5171,http://127.0.0.1:5171"

    # Asistente con Claude (opcional): sin clave, el panel funciona en modo herramientas
    anthropic_api_key: str | None = None
    anthropic_modelo: str = "claude-sonnet-5-5"

    @property
    def origenes(self) -> list[str]:
        return [o.strip() for o in self.cors_origenes.split(",") if o.strip()]


def _secreto(arn: str, region: str) -> str:
    import boto3
    return boto3.client("secretsmanager", region_name=region).get_secret_value(SecretId=arn)["SecretString"]


@lru_cache
def config() -> Config:
    c = Config()
    if c.db_secret_arn:                             # RF-CL-04: credenciales desde Secrets Manager
        s = json.loads(_secreto(c.db_secret_arn, c.aws_region))
        c.db_host, c.db_port, c.db_nombre = s.get("host", c.db_host), int(s.get("port", c.db_port)), s.get("dbname", c.db_nombre)
        c.db_usuario_api, c.db_clave_api = s["api"]["username"], s["api"]["password"]
        c.db_usuario_mcp, c.db_clave_mcp = s["mcp"]["username"], s["mcp"]["password"]
    if c.jwt_secret_arn:
        c.jwt_secreto = _secreto(c.jwt_secret_arn, c.aws_region)
    if c.entorno == "produccion" and c.jwt_secreto == "cambiar-en-produccion":
        raise RuntimeError("JWT_SECRETO no configurado en producción")
    return c
