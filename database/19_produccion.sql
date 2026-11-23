-- Identidad no interactiva para procesos batch, también disponible en desarrollo.
INSERT INTO seg.rol(codigo,nombre,descripcion,rol_padre_id,es_servicio)
SELECT 'SISTEMA_BATCH','Sistema batch','Cálculo de flujos e indicadores',id,true FROM seg.rol WHERE codigo='USUARIO_BASE'
ON CONFLICT (codigo) DO NOTHING;
INSERT INTO seg.rol_permiso(rol_id,permiso_id)
SELECT r.id,p.id FROM seg.rol r CROSS JOIN seg.permiso p WHERE r.codigo='SISTEMA_BATCH' AND p.codigo='RED.EJECUTAR_FLUJO'
ON CONFLICT DO NOTHING;
INSERT INTO seg.usuario(uid, ecosistema_id, organizacion_id, alias, correo, proveedor_identidad, sub_externo, hash_credencial)
SELECT '00000000-0000-4000-8000-000000000099', o.ecosistema_id, o.id, 'sistema.batch', 'sistema.batch@interno.invalid', 'COGNITO', NULL, NULL
FROM org.organizacion o WHERE o.codigo = 'RED-OPER'
ON CONFLICT (uid) DO NOTHING;
INSERT INTO seg.usuario_rol(usuario_id, rol_id, motivo)
SELECT u.id, r.id, 'Procesos batch de flujos e indicadores' FROM seg.usuario u CROSS JOIN seg.rol r
WHERE u.uid = '00000000-0000-4000-8000-000000000099' AND r.codigo = 'SISTEMA_BATCH'
AND NOT EXISTS (SELECT 1 FROM seg.usuario_rol ur WHERE ur.usuario_id=u.id AND ur.rol_id=r.id AND ur.vigencia @> now());

CREATE OR REPLACE FUNCTION seg.fn_bloquear_cuentas_sinteticas() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  UPDATE seg.usuario SET estado='BLOQUEADO', proveedor_identidad='COGNITO', sub_externo=NULL, hash_credencial=NULL
  WHERE (uid BETWEEN '00000000-0000-4000-8000-000000000001'::uuid AND '00000000-0000-4000-8000-000000000018'::uuid)
     OR correo = 'gestor.d1@ejemplo.invalid';
  INSERT INTO aud.evento_seguridad(tipo, detalle) VALUES ('CAMBIO_ROL', jsonb_build_object('accion','BLOQUEO_CUENTAS_SINTETICAS', 'operador_bd',session_user));
END $$;
REVOKE ALL ON FUNCTION seg.fn_bloquear_cuentas_sinteticas() FROM PUBLIC;

CREATE OR REPLACE FUNCTION seg.fn_preparar_produccion(p_admin_correo text, p_admin_alias text, p_admin_clave text, p_clave_demo text DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_id bigint; v_uid uuid; v_eco bigint; v_org bigint; v_rol smallint;
BEGIN
  IF length(coalesce(p_admin_clave,'')) < 16 THEN RAISE EXCEPTION 'La clave administrativa necesita al menos 16 caracteres'; END IF;
  IF p_admin_alias !~ '^[a-z0-9][a-z0-9._-]{2,40}$' OR p_admin_correo !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN RAISE EXCEPTION 'Alias o correo inválido'; END IF;
  IF p_clave_demo = '' THEN RAISE EXCEPTION 'La clave de evaluación no puede estar vacía'; END IF;
  SELECT ecosistema_id,id INTO v_eco,v_org FROM org.organizacion WHERE codigo='RED-OPER';
  IF EXISTS (SELECT 1 FROM seg.usuario WHERE (lower(correo)=lower(p_admin_correo) OR alias=p_admin_alias) AND (correo LIKE '%@ejemplo.invalid' OR uid='00000000-0000-4000-8000-000000000099')) THEN RAISE EXCEPTION 'La identidad administrativa no puede coincidir con cuentas sintéticas o del sistema'; END IF;
  IF (SELECT count(*) FROM seg.usuario WHERE ecosistema_id=v_eco AND (lower(correo)=lower(p_admin_correo) OR alias=p_admin_alias)) > 1 THEN RAISE EXCEPTION 'Alias y correo pertenecen a cuentas distintas'; END IF;
  PERFORM seg.fn_bloquear_cuentas_sinteticas();
  IF p_clave_demo IS NOT NULL THEN
    UPDATE seg.usuario SET estado='ACTIVO', proveedor_identidad='LOCAL', hash_credencial=crypt(p_clave_demo,gen_salt('bf',10)), sub_externo=NULL
    WHERE (uid BETWEEN '00000000-0000-4000-8000-000000000001'::uuid AND '00000000-0000-4000-8000-000000000018'::uuid) OR correo='gestor.d1@ejemplo.invalid';
  END IF;
  SELECT id,uid INTO v_id,v_uid FROM seg.usuario WHERE ecosistema_id=v_eco AND (lower(correo)=lower(p_admin_correo) OR alias=p_admin_alias);
  IF v_id IS NULL THEN
    INSERT INTO seg.usuario(ecosistema_id,organizacion_id,alias,correo,proveedor_identidad,hash_credencial)
    VALUES(v_eco,v_org,p_admin_alias,lower(p_admin_correo),'LOCAL',crypt(p_admin_clave,gen_salt('bf',10))) RETURNING id,uid INTO v_id,v_uid;
  ELSE
    UPDATE seg.usuario SET alias=p_admin_alias,correo=lower(p_admin_correo),proveedor_identidad='LOCAL',sub_externo=NULL,hash_credencial=crypt(p_admin_clave,gen_salt('bf',10)),estado='ACTIVO',eliminado_en=NULL WHERE id=v_id;
  END IF;
  SELECT id INTO v_rol FROM seg.rol WHERE codigo='ADMINISTRADOR';
  IF NOT EXISTS (SELECT 1 FROM seg.usuario_rol WHERE usuario_id=v_id AND rol_id=v_rol AND centro_id IS NULL AND vigencia @> now()) THEN
    INSERT INTO seg.usuario_rol(usuario_id,rol_id,motivo) VALUES(v_id,v_rol,'Preparación administrativa de producción');
  END IF;
  INSERT INTO aud.evento_seguridad(tipo,usuario_id,detalle) VALUES('CAMBIO_ROL',v_id,jsonb_build_object('accion','PREPARAR_PRODUCCION','evaluacion',p_clave_demo IS NOT NULL,'operador_bd',session_user));
  RETURN v_uid;
END $$;
REVOKE ALL ON FUNCTION seg.fn_preparar_produccion(text,text,text,text) FROM PUBLIC;
