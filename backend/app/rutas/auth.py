"""Inicio de sesión, registro y perfil."""
from __future__ import annotations

import secrets

import asyncpg
from fastapi import APIRouter, Depends, Request
from starlette.concurrency import run_in_threadpool
from pydantic import BaseModel, Field

from .. import db, correo
from ..config import config
from ..errores import ErrorAPI
from ..seguridad import Sesion, controlar_intentos, crear_token, huella_ip, registrar_fallo, sesion

router = APIRouter(prefix="/auth", tags=["Identidad"])

# Cuentas sintéticas de demostración (RNF-10): solo se exponen si DEMO=true
DEMO = [
    ("coordinador", "Coordinador logístico", "Programa, despacha y analiza la red"),
    ("gen.universidad", "Generador · Universidad Andina", "Registra equipos y pide recolección"),
    ("gen.municipio", "Generador · GAD Municipal", "Registra equipos y pide recolección"),
    ("operador.c1", "Operador · Acopio Norte (C1)", "Recibe y verifica en C1"),
    ("operador.c2", "Operador · Acopio Sur (C2)", "Recibe y verifica en C2"),
    ("operador.e1", "Operador · Laboratorio (E1)", "Confirma llegadas al laboratorio"),
    ("tecnico.e1", "Técnico evaluador · E1", "Evalúa y clasifica (RN-02)"),
    ("tecnico.r1", "Técnico · Taller (R1)", "Control de calidad y borrado seguro"),
    ("gestor.r1", "Gestor · Taller de reacondicionamiento", "Registra reacondicionamientos"),
    ("gestor.k1", "Gestor · Planta de reciclaje", "Registra reciclaje y cierra"),
    ("gestor.d1", "Gestor · Disposición controlada", "Recibe y dispone residuos no recuperables"),
    ("beneficiario", "Entidad beneficiaria", "Confirma entregas y destino final"),
    ("admin", "Administrador", "Usuarios, roles y moderación"),
    ("auditor", "Auditor", "Auditoría, evidencias y bitácoras"),
    ("comite", "Comité de arquitectura", "Escenarios, decisiones y gobierno"),
]
CLAVE_DEMO = "EcoRAEE-2026"


class LoginIn(BaseModel):
    correo: str = Field(min_length=3, max_length=160)
    password: str = Field(min_length=1, max_length=200)


class RegistroIn(BaseModel):
    alias: str = Field(min_length=3, max_length=40)
    correo: str = Field(min_length=5, max_length=160)
    password: str = Field(min_length=10, max_length=200)
    organizacion: str


async def _respuesta_sesion(uid: str, request: Request) -> dict:
    async with db.transaccion(uid, "WEB", request.state.request_id) as conn:
        perfil = await conn.fetchval("SELECT api.fn_perfil()")
    return {"access_token": crear_token(uid, perfil["alias"]), "token_type": "bearer", "usuario": perfil}


@router.post("/login")
async def login(datos: LoginIn, request: Request):
    if config().auth_modo != "local":
        raise ErrorAPI(400, "El inicio de sesión se hace con Cognito", "AUTH")
    ip = huella_ip(request)
    controlar_intentos(ip)
    async with db.sin_contexto() as conn:
        uid = await conn.fetchval("SELECT api.fn_autenticar_local($1, $2, $3)", datos.correo, datos.password, ip)
    if not uid:
        async with db.sin_contexto() as conn:
            pendiente = await conn.fetchval("SELECT api.fn_login_pendiente($1, $2)", datos.correo, datos.password)
        if pendiente:
            raise ErrorAPI(403, "Verifica tu correo antes de iniciar sesión", "VERIFICACION_PENDIENTE")
        registrar_fallo(ip)
        raise ErrorAPI(401, "Correo o contraseña incorrectos", "EC401")
    return await _respuesta_sesion(uid, request)


@router.post("/registro", status_code=201)
async def registro(datos: RegistroIn, request: Request):
    if config().auth_modo != "local":
        raise ErrorAPI(400, "El registro se hace con Cognito", "AUTH")
    ip = huella_ip(request)
    controlar_intentos(ip)
    registrar_fallo(ip)                       # cada registro cuenta: limita la creación masiva de cuentas
    codigo = f"{secrets.randbelow(1000000):06d}"
    enviar = False
    try:
        async with db.sin_contexto() as conn:
            await conn.fetchval("SELECT api.fn_registrar_cuenta($1, $2, $3, $4)",
                                datos.alias.strip().lower(), datos.correo.strip(), datos.password, datos.organizacion)
            enviar = await conn.fetchval("SELECT api.fn_enviar_codigo($1, $2)", datos.correo, codigo)
    except asyncpg.PostgresError as exc:
        if exc.sqlstate not in ("EC409", "23505"):
            raise
    if enviar:
        await run_in_threadpool(correo.enviar_codigo, datos.correo.strip(), codigo)
    return {"estado": "PENDIENTE_VERIFICACION", "mensaje": "Si corresponde, recibirás un código de verificación."}


class CorreoIn(BaseModel):
    correo: str = Field(min_length=5, max_length=160)


class VerificarIn(CorreoIn):
    codigo: str = Field(pattern=r"^[0-9]{6}$")


@router.post("/verificar")
async def verificar(datos: VerificarIn, request: Request):
    controlar_intentos(huella_ip(request))
    async with db.sin_contexto() as conn:
        correcto = await conn.fetchval("SELECT api.fn_verificar_correo($1,$2)", datos.correo, datos.codigo)
    if not correcto:
        raise ErrorAPI(422, "Código inválido, vencido o sin intentos disponibles. Solicita uno nuevo.", "CODIGO_INVALIDO")
    return {"mensaje": "Correo verificado. Ya puedes iniciar sesión."}


@router.post("/reenviar-codigo")
async def reenviar_codigo(datos: CorreoIn, request: Request):
    controlar_intentos(huella_ip(request))
    codigo = f"{secrets.randbelow(1000000):06d}"
    async with db.sin_contexto() as conn:
        enviar = await conn.fetchval("SELECT api.fn_enviar_codigo($1,$2)", datos.correo, codigo)
    if enviar:
        await run_in_threadpool(correo.enviar_codigo, datos.correo.strip(), codigo)
    return {"mensaje": "Si corresponde, recibirás un código. Espera 60 segundos entre solicitudes; máximo 5 envíos por hora."}


@router.get("/organizaciones")
async def organizaciones():
    async with db.sin_contexto() as conn:
        return await conn.fetchval("SELECT api.fn_organizaciones_publicas()")


@router.get("/demo")
async def cuentas_demo():
    """Cuentas sintéticas para la demostración (desactivar con DEMO=false en producción)."""
    if not config().demo:
        return {"habilitado": False, "cuentas": []}
    return {"habilitado": True, "clave": CLAVE_DEMO,
            "cuentas": [{"correo": f"{a}@ejemplo.invalid", "alias": a, "rol": r, "descripcion": d} for a, r, d in DEMO]}


@router.get("/me")
async def yo(s: Sesion = Depends(sesion)):
    async with s.tx() as conn:
        return await conn.fetchval("SELECT api.fn_perfil()")
