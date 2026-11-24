BEGIN;

INSERT INTO public.permisos (codigo_permiso, modulo, descripcion)
VALUES (
    'HERRAMIENTA_RETIRAR',
    'BODEGA',
    'Retirar una herramienta del inventario activo mediante baja lógica autorizada.'
)
ON CONFLICT (codigo_permiso) DO UPDATE
SET modulo = EXCLUDED.modulo,
    descripcion = EXCLUDED.descripcion;

INSERT INTO public.rol_permisos (id_rol, id_permiso)
SELECT r.id_rol, p.id_permiso
FROM public.roles AS r
JOIN public.permisos AS p ON p.codigo_permiso = 'HERRAMIENTA_RETIRAR'
WHERE r.codigo_rol = 'BODEGUERO'
ON CONFLICT (id_rol, id_permiso) DO NOTHING;

CREATE OR REPLACE FUNCTION public.fn_conterreno_retirar_herramienta(
    p_proyecto_id TEXT,
    p_id_equipo UUID,
    p_motivo TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_en_prestamo BOOLEAN;
BEGIN
    IF NOT public.fn_conterreno_tiene_permiso(p_proyecto_id, 'HERRAMIENTA_RETIRAR') THEN
        RAISE EXCEPTION 'Solo el Bodeguero asignado puede dar de baja una herramienta.';
    END IF;
    IF p_motivo IS NULL OR length(trim(p_motivo)) < 3 THEN
        RAISE EXCEPTION 'Indica un motivo de baja de al menos 3 caracteres.';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM public.prestamos
        WHERE id_equipo = p_id_equipo
          AND proyecto_id = p_proyecto_id
          AND fecha_hora_devolucion IS NULL
    ) INTO v_en_prestamo;
    IF v_en_prestamo THEN
        RAISE EXCEPTION 'No puedes dar de baja una herramienta con un préstamo abierto.';
    END IF;

    UPDATE public.equipos_herramientas
    SET activo = FALSE,
        disponible = FALSE,
        estado_fisico = 'DADO_DE_BAJA'
    WHERE id_equipo = p_id_equipo
      AND proyecto_id = p_proyecto_id
      AND activo = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La herramienta no existe, ya fue retirada o pertenece a otra obra.';
    END IF;

    INSERT INTO public.kardex_transaccional (
        modulo,
        proyecto_id,
        codigo_operacion,
        id_usuario_ejecutor,
        id_registro_referencia,
        payload_jsonb
    )
    VALUES (
        'BODEGA_IOT',
        p_proyecto_id,
        'HERRAMIENTA_RETIRADA',
        auth.uid(),
        p_id_equipo::TEXT,
        jsonb_build_object(
            'id_equipo', p_id_equipo,
            'motivo', trim(p_motivo),
            'baja_logica', TRUE
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_conterreno_retirar_herramienta(TEXT, UUID, TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_retirar_herramienta(TEXT, UUID, TEXT)
    TO authenticated;

COMMIT;
