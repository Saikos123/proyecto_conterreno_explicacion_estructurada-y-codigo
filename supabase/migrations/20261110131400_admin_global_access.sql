-- Concede al Administrador del sistema acceso global a las obras y módulos
-- protegidos por los helpers centrales, sin alterar los permisos de los demás roles.
BEGIN;

CREATE OR REPLACE FUNCTION public.fn_conterreno_es_miembro(p_proyecto_id TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT public.fn_conterreno_es_administrador()
        AND EXISTS (
            SELECT 1
            FROM public.conterreno_proyectos AS cp
            WHERE cp.id = p_proyecto_id
        )
    OR EXISTS (
        SELECT 1
        FROM public.conterreno_usuarios_proyectos AS up
        JOIN public.conterreno_proyectos AS cp
          ON cp.id = up.proyecto_id AND cp.activo = TRUE
        JOIN public.usuarios AS u ON u.id_usuario = up.usuario_auth_id
        WHERE up.proyecto_id = p_proyecto_id
          AND up.usuario_auth_id = auth.uid()
          AND up.activo = TRUE
          AND u.activo = TRUE
          AND u.bloqueado = FALSE
    );
$$;

CREATE OR REPLACE FUNCTION public.fn_conterreno_tiene_permiso(
    p_proyecto_id TEXT,
    p_codigo_permiso TEXT
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT (
        public.fn_conterreno_es_administrador()
        AND EXISTS (
            SELECT 1
            FROM public.conterreno_proyectos AS cp
            WHERE cp.id = p_proyecto_id
        )
    )
    OR EXISTS (
        SELECT 1
        FROM public.conterreno_usuarios_proyectos AS up
        JOIN public.conterreno_proyectos AS cp
          ON cp.id = up.proyecto_id AND cp.activo = TRUE
        JOIN public.usuarios AS u ON u.id_usuario = up.usuario_auth_id
        JOIN public.roles AS r ON r.id_rol = u.id_rol
        JOIN public.rol_permisos AS rp ON rp.id_rol = r.id_rol
        JOIN public.permisos AS p ON p.id_permiso = rp.id_permiso
        WHERE up.proyecto_id = p_proyecto_id
          AND up.usuario_auth_id = auth.uid()
          AND up.activo = TRUE
          AND u.activo = TRUE
          AND u.bloqueado = FALSE
          AND r.activo = TRUE
          AND p.codigo_permiso = p_codigo_permiso
    );
$$;

COMMIT;
