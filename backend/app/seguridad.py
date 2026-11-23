"""Autenticación (JWT local para el MVP o Cognito) y autorización por permisos efectivos de la base."""
from __future__ import annotations

import hashlib
import time
import uuid
from collections import defaultdict, deque
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from . import db
from .config import config
from .errores import ErrorAPI

_bearer = HTTPBearer(auto_error=False)
EMISOR, AUDIENCIA = "ecoraee-api", "ecoraee-web"


def crear_token(uid: str, alias: str) -> str:
    c = config()
    ahora = datetime.now(timezone.utc)
    return jwt.encode({"sub": uid, "alias": alias, "iss": EMISOR, "aud": AUDIENCIA, "iat": ahora,
                       "exp": ahora + timedelta(minutes=c.jwt_minutos), "jti": uuid.uuid4().hex}, c.jwt_secreto, algorithm="HS256")


_jwks = None


async def _uid_desde_token(token: str) -> str:
    c = config()
    try:
        if c.auth_modo == "cognito":
            global _jwks
            if _jwks is None:
                _jwks = jwt.PyJWKClient(f"https://cognito-idp.{c.cognito_region}.amazonaws.com/{c.cognito_user_pool_id}/.well-known/jwks.json")
            clave = _jwks.get_signing_key_from_jwt(token).key
            datos = jwt.decode(token, clave, algorithms=["RS256"],
                               issuer=f"https://cognito-idp.{c.cognito_region}.amazonaws.com/{c.cognito_user_pool_id}",
                               options={"verify_aud": False})
            if datos.get("token_use") == "id" and datos.get("aud") != c.cognito_client_id:
                raise ErrorAPI(401, "Token de otra aplicación", "EC401")
            async with db.sin_contexto() as conn:
                uid = await conn.fetchval("SELECT api.fn_resolver_identidad('COGNITO', $1)", datos["sub"])
            if not uid:
                raise ErrorAPI(401, "La cuenta de Cognito no está vinculada a un usuario de la red", "EC401")
            return uid
        datos = jwt.decode(token, c.jwt_secreto, algorithms=["HS256"], audience=AUDIENCIA, issuer=EMISOR)
        return datos["sub"]
    except jwt.ExpiredSignatureError:
        raise ErrorAPI(401, "La sesión expiró: vuelve a iniciar sesión", "EC401")
    except jwt.PyJWTError:
        raise ErrorAPI(401, "Token inválido", "EC401")


@dataclass
class Sesion:
    uid: str
    request_id: str
    canal: str = "WEB"

    def tx(self, canal: str | None = None, pool: str = "api"):
        return db.transaccion(self.uid, canal or self.canal, self.request_id, pool)


async def sesion(request: Request, cred: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> Sesion:
    if not cred or cred.scheme.lower() != "bearer":
        raise ErrorAPI(401, "Inicia sesión para continuar", "EC401")
    uid = await _uid_desde_token(cred.credentials)
    request.state.usuario = uid
    return Sesion(uid=uid, request_id=request.state.request_id)


# ---------------------------------------------------------------------------
# Permisos efectivos (con herencia de roles y alcance por centro), leídos de api.fn_perfil
# ---------------------------------------------------------------------------
@dataclass
class Perfil:
    datos: dict
    _permisos: dict[str, set] = field(default_factory=dict)

    def __post_init__(self):
        for p in self.datos.get("permisos", []):
            self._permisos.setdefault(p["codigo"], set()).add(p.get("centro"))

    def tiene(self, permiso: str, centro: str | None = None) -> bool:
        """Igual que seg.fn_tiene_permiso: un rol global vale en cualquier centro; uno con alcance, solo en el suyo."""
        alcances = self._permisos.get(permiso)
        if not alcances:
            return False
        return centro is None or None in alcances or centro in alcances

    def centros(self, permiso: str) -> set | None:
        """None = en todos los centros; set() = en ninguno."""
        alcances = self._permisos.get(permiso, set())
        return None if None in alcances else set(alcances)

    def rol(self, codigo: str) -> bool:
        return codigo in self.datos.get("roles_efectivos", [])

    @property
    def organizacion(self) -> str | None:
        return (self.datos.get("organizacion") or {}).get("codigo")


async def perfil(conn) -> Perfil:
    return Perfil(await conn.fetchval("SELECT api.fn_perfil()"))


# ---------------------------------------------------------------------------
# Límite de intentos de inicio de sesión por IP (protección básica contra fuerza bruta)
# ---------------------------------------------------------------------------
_intentos: dict[str, deque] = defaultdict(deque)


def huella_ip(request: Request) -> str:
    ip = request.headers.get("x-forwarded-for", request.client.host if request.client else "?").split(",")[0].strip()
    return hashlib.sha256(f"{ip}|{config().jwt_secreto[:8]}".encode()).hexdigest()    # RNF-10: la IP no se guarda en claro


def controlar_intentos(ip_hash: str, maximo: int = 8, ventana: int = 300) -> None:
    """Bloquea temporalmente una IP con demasiados intentos fallidos recientes."""
    ahora = time.monotonic()
    q = _intentos[ip_hash]
    while q and ahora - q[0] > ventana:
        q.popleft()
    if len(q) >= maximo:
        raise ErrorAPI(429, "Demasiados intentos fallidos. Espera unos minutos.", "LIMITE")


def registrar_fallo(ip_hash: str) -> None:
    _intentos[ip_hash].append(time.monotonic())
