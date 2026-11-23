-- Verificación de correo: las cuentas previas conservan su estado.
ALTER TABLE seg.usuario ALTER COLUMN estado TYPE varchar(24);
ALTER TABLE seg.usuario DROP CONSTRAINT IF EXISTS usuario_estado_check;
ALTER TABLE seg.usuario ADD CONSTRAINT usuario_estado_check CHECK (estado IN ('ACTIVO','BLOQUEADO','BAJA','PENDIENTE_VERIFICACION'));
ALTER TABLE aud.evento_seguridad DROP CONSTRAINT IF EXISTS evento_seguridad_tipo_check;
ALTER TABLE aud.evento_seguridad ADD CONSTRAINT evento_seguridad_tipo_check CHECK (tipo IN ('LOGIN_OK','LOGIN_FALLIDO','ACCESO_DENEGADO','CAMBIO_ROL','MCP_RECHAZO','REGLA_VIOLADA','VERIF_ENVIO','VERIF_INTENTO','VERIF_ACTIVADA'));
CREATE TABLE IF NOT EXISTS seg.verificacion_correo (
 usuario_id bigint PRIMARY KEY REFERENCES seg.usuario(id),
 codigo_hash text NOT NULL,
 enviado_en timestamptz NOT NULL DEFAULT now(),
 vence_en timestamptz NOT NULL,
 intentos integer NOT NULL DEFAULT 0,
 envios timestamptz[] NOT NULL DEFAULT '{}'
);
COMMENT ON TABLE seg.verificacion_correo IS 'Estado de verificación del correo de una cuenta local.';
COMMENT ON COLUMN seg.verificacion_correo.usuario_id IS 'Cuenta pendiente.';
COMMENT ON COLUMN seg.verificacion_correo.codigo_hash IS 'Código con hash bcrypt y sal.';
COMMENT ON COLUMN seg.verificacion_correo.enviado_en IS 'Hora del último envío.';
COMMENT ON COLUMN seg.verificacion_correo.vence_en IS 'Caducidad del código.';
COMMENT ON COLUMN seg.verificacion_correo.intentos IS 'Intentos realizados con el código vigente.';
COMMENT ON COLUMN seg.verificacion_correo.envios IS 'Instantes de los envíos de la última hora.';
DROP TRIGGER IF EXISTS tg_auditoria ON seg.verificacion_correo;
CREATE TRIGGER tg_auditoria AFTER INSERT OR UPDATE OR DELETE ON seg.verificacion_correo FOR EACH ROW EXECUTE FUNCTION aud.fn_auditar('usuario_id');
CREATE OR REPLACE FUNCTION api.fn_registrar_cuenta(p_alias text, p_correo text, p_password text, p_organizacion text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE o org.organizacion; v_id bigint; v_uid uuid;
BEGIN
  IF length(coalesce(p_password, '')) < 10 THEN
    RAISE EXCEPTION 'La contraseña necesita al menos 10 caracteres' USING ERRCODE = 'EC422';
  END IF;
  IF p_alias !~ '^[a-z0-9][a-z0-9._-]{2,40}$' THEN
    RAISE EXCEPTION 'El alias usa de 3 a 40 letras minúsculas, números, punto o guion' USING ERRCODE = 'EC422';
  END IF;
  IF p_correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'Correo electrónico inválido' USING ERRCODE = 'EC422';
  END IF;
  SELECT * INTO o FROM org.organizacion WHERE codigo = p_organizacion AND estado = 'ACTIVA' AND eliminado_en IS NULL
   ORDER BY ecosistema_id LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Organización % no existe', p_organizacion USING ERRCODE = 'EC404'; END IF;
  IF EXISTS (SELECT 1 FROM seg.usuario WHERE ecosistema_id = o.ecosistema_id AND (lower(correo) = lower(p_correo) OR alias = p_alias)) THEN
    RAISE EXCEPTION 'Ya existe una cuenta con ese correo o alias' USING ERRCODE = 'EC409';
  END IF;
  INSERT INTO seg.usuario(ecosistema_id, organizacion_id, alias, correo, proveedor_identidad, hash_credencial, estado)
  VALUES (o.ecosistema_id, o.id, p_alias, lower(p_correo), 'LOCAL', crypt(p_password, gen_salt('bf', 10)), 'PENDIENTE_VERIFICACION')
  RETURNING id, uid INTO v_id, v_uid;
  INSERT INTO seg.usuario_rol(usuario_id, rol_id, motivo)
  SELECT v_id, id, 'Autorregistro: rol base hasta que el administrador asigne funciones' FROM seg.rol WHERE codigo = 'USUARIO_BASE';
  RETURN v_uid;
END $$;


-- Serializa reenvíos por cuenta; no devuelve información sobre cuentas inexistentes.
CREATE OR REPLACE FUNCTION api.fn_enviar_codigo(p_correo text, p_codigo text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE u seg.usuario; v seg.verificacion_correo; horas timestamptz[];
BEGIN
 IF p_codigo !~ '^[0-9]{6}$' THEN RETURN false; END IF;
 SELECT * INTO u FROM seg.usuario WHERE lower(correo)=lower(btrim(p_correo)) AND estado='PENDIENTE_VERIFICACION' AND eliminado_en IS NULL ORDER BY id LIMIT 1 FOR UPDATE;
 IF NOT FOUND THEN RETURN false; END IF;
 SELECT * INTO v FROM seg.verificacion_correo WHERE usuario_id=u.id;
 SELECT coalesce(array_agg(t), '{}') INTO horas FROM unnest(coalesce(v.envios, '{}'::timestamptz[])) t WHERE t > now()-interval '1 hour';
 IF v.usuario_id IS NOT NULL AND (v.enviado_en > now()-interval '60 seconds' OR cardinality(horas)>=5) THEN RETURN false; END IF;
 INSERT INTO seg.verificacion_correo(usuario_id,codigo_hash,enviado_en,vence_en,intentos,envios)
 VALUES(u.id,crypt(p_codigo,gen_salt('bf',10)),now(),now()+interval '15 minutes',0,array_append(horas,now()))
 ON CONFLICT(usuario_id) DO UPDATE SET codigo_hash=excluded.codigo_hash,enviado_en=excluded.enviado_en,vence_en=excluded.vence_en,intentos=0,envios=excluded.envios;
 INSERT INTO aud.evento_seguridad(tipo,usuario_id,detalle) VALUES ('VERIF_ENVIO',u.id,'{}');
 RETURN true;
END $$;
CREATE OR REPLACE FUNCTION api.fn_verificar_correo(p_correo text,p_codigo text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE u seg.usuario; v seg.verificacion_correo; correcto boolean := false;
BEGIN
 IF p_codigo !~ '^[0-9]{6}$' THEN RETURN false; END IF;
 SELECT * INTO u FROM seg.usuario WHERE lower(correo)=lower(btrim(p_correo)) AND estado='PENDIENTE_VERIFICACION' AND eliminado_en IS NULL ORDER BY id LIMIT 1 FOR UPDATE;
 IF NOT FOUND THEN RETURN false; END IF;
 SELECT * INTO v FROM seg.verificacion_correo WHERE usuario_id=u.id FOR UPDATE;
 IF FOUND THEN
   correcto := v.intentos < 5 AND v.vence_en > now() AND crypt(p_codigo,v.codigo_hash)=v.codigo_hash;
   UPDATE seg.verificacion_correo SET intentos=intentos+1 WHERE usuario_id=u.id;
 END IF;
 INSERT INTO aud.evento_seguridad(tipo,usuario_id,detalle) VALUES ('VERIF_INTENTO',u.id,jsonb_build_object('correcto',correcto));
 IF correcto THEN
   UPDATE seg.usuario SET estado='ACTIVO' WHERE id=u.id;
   DELETE FROM seg.verificacion_correo WHERE usuario_id=u.id;
   INSERT INTO aud.evento_seguridad(tipo,usuario_id,detalle) VALUES ('VERIF_ACTIVADA',u.id,'{}');
 END IF;
 RETURN correcto;
END $$;
CREATE OR REPLACE FUNCTION api.fn_login_pendiente(p_correo text,p_password text) RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
 SELECT EXISTS(SELECT 1 FROM seg.usuario WHERE lower(correo)=lower(btrim(p_correo)) AND estado='PENDIENTE_VERIFICACION' AND proveedor_identidad='LOCAL' AND eliminado_en IS NULL AND hash_credencial IS NOT NULL AND crypt(p_password,hash_credencial)=hash_credencial)
$$;
REVOKE ALL ON FUNCTION api.fn_enviar_codigo(text,text), api.fn_verificar_correo(text,text), api.fn_login_pendiente(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION api.fn_enviar_codigo(text,text), api.fn_verificar_correo(text,text), api.fn_login_pendiente(text,text) TO ecoraee_app;
