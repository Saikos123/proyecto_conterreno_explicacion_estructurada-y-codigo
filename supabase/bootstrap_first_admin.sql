-- Ejecutar una sola vez en Supabase SQL Editor DESPUES de aplicar todas las
-- migraciones y crear/confirmar la identidad Auth del administrador.
-- Reemplazar todos los valores de ejemplo antes de ejecutar.
-- Este archivo es aprovisionamiento inicial, no una migracion versionada.
BEGIN;

DO $bootstrap$
DECLARE
    v_email TEXT := pg_catalog.lower('REEMPLAZAR_EMAIL_VERIFICADO');
    v_rut TEXT := 'REEMPLAZAR_RUT';
    v_nombres TEXT := 'REEMPLAZAR_NOMBRES';
    v_apellidos TEXT := 'REEMPLAZAR_APELLIDOS';
    v_cargo TEXT := 'REEMPLAZAR_CARGO';
    v_proyecto_id TEXT := 'REEMPLAZAR_ID_OBRA';

    v_user_id UUID;
    v_id_rol INTEGER;
    v_nombre_completo TEXT;
BEGIN
    IF v_email ILIKE '%reemplazar%'
       OR v_rut ILIKE '%reemplazar%'
       OR v_nombres ILIKE '%reemplazar%'
       OR v_apellidos ILIKE '%reemplazar%'
       OR v_cargo ILIKE '%reemplazar%'
       OR v_proyecto_id ILIKE '%reemplazar%'
       OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
       OR pg_catalog.btrim(v_rut) = ''
       OR pg_catalog.btrim(v_nombres) = ''
       OR pg_catalog.btrim(v_apellidos) = '' THEN
        RAISE EXCEPTION 'Reemplaza los valores de ejemplo en supabase/bootstrap_first_admin.sql.';
    END IF;

    SELECT au.id, pg_catalog.btrim(
        COALESCE(au.raw_user_meta_data ->> 'full_name', '')
    )
    INTO v_user_id, v_nombre_completo
    FROM auth.users AS au
    WHERE pg_catalog.lower(au.email) = v_email
      AND au.email_confirmed_at IS NOT NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Crea y confirma primero esta cuenta en Supabase Authentication > Users.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.usuarios AS u
        WHERE u.id_usuario = v_user_id
    ) THEN
        RAISE EXCEPTION 'La cuenta ya tiene perfil; no se modificó ningún dato.';
    END IF;

    SELECT r.id_rol
    INTO v_id_rol
    FROM public.roles AS r
    WHERE r.codigo_rol = 'ADMIN_GENERAL'
      AND r.activo = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el rol ADMIN_GENERAL activo. Revisa las migraciones.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.conterreno_proyectos AS cp
        WHERE cp.id = v_proyecto_id
          AND cp.activo = TRUE
    ) THEN
        RAISE EXCEPTION 'No existe la obra activa %. Usa un ID existente de conterreno_proyectos.', v_proyecto_id;
    END IF;

    INSERT INTO public.conterreno_solicitudes_acceso (
        usuario_auth_id,
        email,
        nombre_completo,
        nombres,
        apellidos,
        email_confirmado
    )
    VALUES (
        v_user_id,
        v_email,
        v_nombre_completo,
        COALESCE(NULLIF(v_nombres, ''), v_nombre_completo),
        COALESCE(NULLIF(v_apellidos, ''), ''),
        TRUE
    )
    ON CONFLICT (usuario_auth_id) DO NOTHING;

    INSERT INTO public.usuarios (
        id_usuario,
        rut,
        nombres,
        apellidos,
        email,
        cargo_contrato,
        id_rol
    )
    VALUES (
        v_user_id,
        pg_catalog.btrim(v_rut),
        pg_catalog.btrim(v_nombres),
        pg_catalog.btrim(v_apellidos),
        v_email,
        pg_catalog.btrim(v_cargo),
        v_id_rol
    );

    INSERT INTO public.conterreno_usuarios_proyectos (
        proyecto_id,
        usuario_auth_id,
        activo
    )
    VALUES (v_proyecto_id, v_user_id, TRUE)
    ON CONFLICT (proyecto_id, usuario_auth_id)
    DO UPDATE SET activo = TRUE;

    UPDATE public.conterreno_solicitudes_acceso
    SET estado = 'APROBADA',
        email = v_email,
        email_confirmado = TRUE,
        resuelto_en = CURRENT_TIMESTAMP,
        resuelto_por = v_user_id,
        proyecto_asignado = v_proyecto_id,
        codigo_rol_asignado = 'ADMIN_GENERAL'
    WHERE usuario_auth_id = v_user_id
      AND estado = 'PENDIENTE';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe la solicitud pendiente de la cuenta; no se completó el bootstrap.';
    END IF;
END;
$bootstrap$;

COMMIT;
