BEGIN;

ALTER TABLE public.conterreno_tareas
    ADD COLUMN IF NOT EXISTS responsable_id UUID
        REFERENCES public.usuarios(id_usuario) ON DELETE RESTRICT;

ALTER TABLE public.conterreno_incidencias
    ADD COLUMN IF NOT EXISTS responsable_id UUID
        REFERENCES public.usuarios(id_usuario) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_conterreno_tareas_responsable
    ON public.conterreno_tareas(responsable_id);

CREATE INDEX IF NOT EXISTS idx_conterreno_incidencias_responsable
    ON public.conterreno_incidencias(responsable_id);

CREATE OR REPLACE FUNCTION public.fn_conterreno_listar_responsables(
    p_proyecto_id TEXT,
    p_solo_operarios BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    id_usuario UUID,
    nombre_completo TEXT,
    rut TEXT,
    codigo_rol TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT (
        public.fn_conterreno_tiene_permiso(p_proyecto_id, 'TAREA_PLANIFICAR')
        OR public.fn_conterreno_tiene_permiso(p_proyecto_id, 'INCIDENCIA_REGISTRAR')
        OR public.fn_conterreno_tiene_permiso(p_proyecto_id, 'INCIDENCIA_GESTIONAR')
    ) THEN
        RAISE EXCEPTION 'No tienes permiso para consultar responsables de esta obra.';
    END IF;

    RETURN QUERY
    SELECT u.id_usuario,
           trim(u.nombres || ' ' || u.apellidos)::TEXT,
           u.rut::TEXT,
           r.codigo_rol::TEXT
    FROM public.conterreno_usuarios_proyectos AS up
    JOIN public.usuarios AS u ON u.id_usuario = up.usuario_auth_id
    JOIN public.roles AS r ON r.id_rol = u.id_rol
    WHERE up.proyecto_id = p_proyecto_id
      AND up.activo = TRUE
      AND u.activo = TRUE
      AND u.bloqueado = FALSE
      AND r.activo = TRUE
      AND (
          NOT p_solo_operarios
          OR r.codigo_rol = 'OPERARIO_MAESTRO'
      )
    ORDER BY u.apellidos, u.nombres;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_conterreno_listar_responsables(TEXT, BOOLEAN)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_listar_responsables(TEXT, BOOLEAN)
    TO authenticated;

INSERT INTO public.permisos (codigo_permiso, modulo, descripcion)
VALUES (
    'TAREA_ACTUALIZAR_PROPIO',
    'OBRA',
    'Actualizar el estado de una tarea asignada al usuario autenticado.'
)
ON CONFLICT (codigo_permiso) DO UPDATE
SET modulo = EXCLUDED.modulo,
    descripcion = EXCLUDED.descripcion;

INSERT INTO public.rol_permisos (id_rol, id_permiso)
SELECT r.id_rol, p.id_permiso
FROM public.roles r
CROSS JOIN public.permisos p
WHERE r.codigo_rol = 'OPERARIO_MAESTRO'
  AND p.codigo_permiso = 'TAREA_ACTUALIZAR_PROPIO'
ON CONFLICT (id_rol, id_permiso) DO NOTHING;

DROP POLICY IF EXISTS conterreno_tareas_update_asignado ON public.conterreno_tareas;
CREATE POLICY conterreno_tareas_update_asignado ON public.conterreno_tareas
    FOR UPDATE TO authenticated
    USING (
        responsable_id = auth.uid()
        AND public.fn_conterreno_tiene_permiso(proyecto_id, 'TAREA_ACTUALIZAR_PROPIO')
    )
    WITH CHECK (
        responsable_id = auth.uid()
        AND public.fn_conterreno_tiene_permiso(proyecto_id, 'TAREA_ACTUALIZAR_PROPIO')
    );

GRANT UPDATE (estado, restriccion)
    ON public.conterreno_tareas TO authenticated;

GRANT INSERT (proyecto_id, titulo, sector, responsable, responsable_id, estado, restriccion)
    ON public.conterreno_tareas TO authenticated;

GRANT INSERT (
    proyecto_id, titulo, sector, categoria, prioridad, estado,
    responsable, responsable_id, descripcion, foto_url, fecha_reporte
)
    ON public.conterreno_incidencias TO authenticated;

COMMIT;
