-- Registra cuentas nuevas de Supabase Auth como pendientes y permite que un
-- administrador les asigne perfil, rol y obra desde la aplicación.
-- Requiere que Base de datos posgreSQL/Base de datos.sql ya esté aplicado.
BEGIN;

CREATE TABLE IF NOT EXISTS public.conterreno_solicitudes_acceso (
    usuario_auth_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email VARCHAR(150) NOT NULL,
    nombre_completo VARCHAR(200) NOT NULL DEFAULT '',
    nombres VARCHAR(100) NOT NULL DEFAULT '',
    apellidos VARCHAR(100) NOT NULL DEFAULT '',
    email_confirmado BOOLEAN NOT NULL DEFAULT FALSE,

    estado VARCHAR(12) NOT NULL DEFAULT 'PENDIENTE'
        CHECK (estado IN ('PENDIENTE', 'APROBADA', 'RECHAZADA')),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resuelto_en TIMESTAMPTZ,
    resuelto_por UUID REFERENCES public.usuarios(id_usuario) ON DELETE SET NULL,
    proyecto_asignado TEXT REFERENCES public.conterreno_proyectos(id) ON DELETE RESTRICT,
    codigo_rol_asignado VARCHAR(50) REFERENCES public.roles(codigo_rol) ON DELETE RESTRICT
);
ALTER TABLE public.conterreno_solicitudes_acceso
    ADD COLUMN IF NOT EXISTS email_confirmado BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_conterreno_solicitudes_pendientes
    ON public.conterreno_solicitudes_acceso(creado_en)
    WHERE estado = 'PENDIENTE';

CREATE OR REPLACE FUNCTION public.fn_conterreno_registrar_solicitud_auth()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_nombre_completo TEXT;
    v_nombres TEXT;
    v_apellidos TEXT;
    v_separador INTEGER;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        UPDATE public.conterreno_solicitudes_acceso
        SET email = COALESCE(NEW.email, ''),
            email_confirmado = NEW.email_confirmed_at IS NOT NULL
        WHERE usuario_auth_id = NEW.id
          AND estado = 'PENDIENTE';
        RETURN NEW;
    END IF;

    v_nombre_completo := pg_catalog.btrim(
        COALESCE(NEW.raw_user_meta_data ->> 'full_name', '')
    );
    v_separador := pg_catalog.strpos(v_nombre_completo, ' ');
    v_nombres := CASE
        WHEN v_separador > 0 THEN pg_catalog.substr(v_nombre_completo, 1, v_separador - 1)
        ELSE v_nombre_completo
    END;
    v_apellidos := CASE
        WHEN v_separador > 0 THEN pg_catalog.btrim(pg_catalog.substr(v_nombre_completo, v_separador + 1))
        ELSE ''
    END;

    INSERT INTO public.conterreno_solicitudes_acceso (
        usuario_auth_id, email, nombre_completo, nombres, apellidos,
        email_confirmado
    )
    VALUES (
        NEW.id, COALESCE(NEW.email, ''), v_nombre_completo, v_nombres,
        v_apellidos, NEW.email_confirmed_at IS NOT NULL
    )
    ON CONFLICT (usuario_auth_id) DO NOTHING;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_conterreno_registrar_solicitud_auth ON auth.users;
CREATE TRIGGER trg_conterreno_registrar_solicitud_auth
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_conterreno_registrar_solicitud_auth();

DROP TRIGGER IF EXISTS trg_conterreno_actualizar_solicitud_confirmacion ON auth.users;
CREATE TRIGGER trg_conterreno_actualizar_solicitud_confirmacion
    AFTER UPDATE OF email, email_confirmed_at ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_conterreno_registrar_solicitud_auth();

-- Incluye cuentas Auth creadas antes de instalar esta migración que todavía
-- no tengan perfil, para que Administración pueda aprobarlas desde la web.
INSERT INTO public.conterreno_solicitudes_acceso (
    usuario_auth_id, email, nombre_completo, nombres, apellidos,
    email_confirmado
)
SELECT
    au.id,
    COALESCE(au.email, ''),
    pg_catalog.btrim(COALESCE(au.raw_user_meta_data ->> 'full_name', '')),
    CASE
        WHEN pg_catalog.strpos(pg_catalog.btrim(COALESCE(au.raw_user_meta_data ->> 'full_name', '')), ' ') > 0
        THEN pg_catalog.substr(
            pg_catalog.btrim(COALESCE(au.raw_user_meta_data ->> 'full_name', '')),
            1,
            pg_catalog.strpos(pg_catalog.btrim(COALESCE(au.raw_user_meta_data ->> 'full_name', '')), ' ') - 1
        )
        ELSE pg_catalog.btrim(COALESCE(au.raw_user_meta_data ->> 'full_name', ''))
    END,
    CASE
        WHEN pg_catalog.strpos(pg_catalog.btrim(COALESCE(au.raw_user_meta_data ->> 'full_name', '')), ' ') > 0
        THEN pg_catalog.btrim(pg_catalog.substr(
            pg_catalog.btrim(COALESCE(au.raw_user_meta_data ->> 'full_name', '')),
            pg_catalog.strpos(pg_catalog.btrim(COALESCE(au.raw_user_meta_data ->> 'full_name', '')), ' ') + 1
        ))
        ELSE ''
    END,
    au.email_confirmed_at IS NOT NULL
FROM auth.users AS au
WHERE NOT EXISTS (
    SELECT 1
    FROM public.usuarios AS u
    WHERE u.id_usuario = au.id
)
ON CONFLICT (usuario_auth_id) DO NOTHING;

UPDATE public.conterreno_solicitudes_acceso AS s
SET email = COALESCE(au.email, ''),
    email_confirmado = au.email_confirmed_at IS NOT NULL
FROM auth.users AS au
WHERE s.usuario_auth_id = au.id
  AND s.estado = 'PENDIENTE';

ALTER TABLE public.conterreno_solicitudes_acceso ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS conterreno_solicitudes_acceso_select_propias_admin
    ON public.conterreno_solicitudes_acceso;
CREATE POLICY conterreno_solicitudes_acceso_select_propias_admin
    ON public.conterreno_solicitudes_acceso
    FOR SELECT TO authenticated
    USING (
        usuario_auth_id = auth.uid()
        OR public.fn_conterreno_es_administrador()
    );

CREATE OR REPLACE FUNCTION public.fn_conterreno_admin_asignar_acceso(
    p_id_usuario UUID,
    p_rut TEXT,
    p_nombres TEXT,
    p_apellidos TEXT,
    p_cargo TEXT,
    p_codigo_rol TEXT,
    p_proyecto_id TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_solicitud public.conterreno_solicitudes_acceso%ROWTYPE;
    v_email TEXT;
    v_id_rol INTEGER;
BEGIN
    IF NOT public.fn_conterreno_es_administrador() THEN
        RAISE EXCEPTION 'Solo el Administrador del sistema puede aprobar cuentas y asignar roles.';
    END IF;

    IF p_rut IS NULL OR pg_catalog.length(pg_catalog.btrim(p_rut)) < 8
       OR p_nombres IS NULL OR pg_catalog.length(pg_catalog.btrim(p_nombres)) = 0
       OR p_apellidos IS NULL OR pg_catalog.length(pg_catalog.btrim(p_apellidos)) = 0
       OR p_cargo IS NULL OR pg_catalog.length(pg_catalog.btrim(p_cargo)) = 0 THEN
        RAISE EXCEPTION 'RUT, nombres, apellidos y cargo son obligatorios.';
    END IF;

    SELECT *
    INTO v_solicitud
    FROM public.conterreno_solicitudes_acceso
    WHERE usuario_auth_id = p_id_usuario
      AND estado = 'PENDIENTE'
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La solicitud no existe o ya fue resuelta.';
    END IF;

    SELECT au.email
    INTO v_email
    FROM auth.users AS au
    WHERE au.id = p_id_usuario
      AND au.email_confirmed_at IS NOT NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cuenta debe confirmar su correo antes de ser aprobada.';
    END IF;

    SELECT r.id_rol
    INTO v_id_rol
    FROM public.roles AS r
    WHERE r.codigo_rol = p_codigo_rol
      AND r.activo = TRUE;
    IF v_id_rol IS NULL THEN
        RAISE EXCEPTION 'El rol solicitado no existe o está inactivo.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.conterreno_proyectos AS cp
        WHERE cp.id = p_proyecto_id
          AND cp.activo = TRUE
    ) THEN
        RAISE EXCEPTION 'La obra solicitada no existe o está inactiva.';
    END IF;

    INSERT INTO public.usuarios (
        id_usuario, rut, nombres, apellidos, email, cargo_contrato, id_rol
    )
    VALUES (
        p_id_usuario,
        pg_catalog.btrim(p_rut),
        pg_catalog.btrim(p_nombres),
        pg_catalog.btrim(p_apellidos),
        pg_catalog.lower(pg_catalog.btrim(v_email)),
        pg_catalog.btrim(p_cargo),
        v_id_rol
    );

    INSERT INTO public.conterreno_usuarios_proyectos (
        proyecto_id, usuario_auth_id, activo
    )
    VALUES (p_proyecto_id, p_id_usuario, TRUE)
    ON CONFLICT (proyecto_id, usuario_auth_id)
    DO UPDATE SET activo = TRUE;

    UPDATE public.conterreno_solicitudes_acceso
    SET estado = 'APROBADA',
        resuelto_en = CURRENT_TIMESTAMP,
        resuelto_por = auth.uid(),
        proyecto_asignado = p_proyecto_id,
        codigo_rol_asignado = p_codigo_rol
    WHERE usuario_auth_id = p_id_usuario;

    INSERT INTO public.auditoria_usuarios (
        tabla_afectada, id_usuario_afectado, operacion,
        id_usuario_ejecutor, datos_nuevos
    )
    VALUES (
        'conterreno_solicitudes_acceso', p_id_usuario, 'APROBACION_ACCESO',
        auth.uid(),
        pg_catalog.jsonb_build_object(
            'proyecto_id', p_proyecto_id,
            'codigo_rol', p_codigo_rol,
            'email', v_email
        )
    );

    RETURN p_id_usuario;
END;
$$;

REVOKE ALL ON public.conterreno_solicitudes_acceso FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.conterreno_solicitudes_acceso TO authenticated;

REVOKE ALL ON FUNCTION public.fn_conterreno_registrar_solicitud_auth()
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_conterreno_admin_asignar_acceso(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_admin_asignar_acceso(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT)
    TO authenticated;

COMMIT;
