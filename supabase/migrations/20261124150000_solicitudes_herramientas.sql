BEGIN;

INSERT INTO public.permisos (codigo_permiso, modulo, descripcion)
VALUES
    ('HERRAMIENTA_SOLICITAR', 'TERRENO', 'Solicitar herramientas disponibles de una obra asignada.'),
    ('HERRAMIENTA_SOLICITUD_GESTIONAR', 'BODEGA', 'Aprobar, rechazar y entregar solicitudes de herramientas.')
ON CONFLICT (codigo_permiso) DO UPDATE
SET modulo = EXCLUDED.modulo,
    descripcion = EXCLUDED.descripcion;

INSERT INTO public.rol_permisos (id_rol, id_permiso)
SELECT r.id_rol, p.id_permiso
FROM public.roles r
CROSS JOIN public.permisos p
WHERE (
    r.codigo_rol = 'OPERARIO_MAESTRO' AND p.codigo_permiso = 'HERRAMIENTA_SOLICITAR'
) OR (
    r.codigo_rol = 'BODEGUERO' AND p.codigo_permiso = 'HERRAMIENTA_SOLICITUD_GESTIONAR'
)
ON CONFLICT (id_rol, id_permiso) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.conterreno_solicitudes_herramientas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    proyecto_id TEXT NOT NULL REFERENCES public.conterreno_proyectos(id) ON DELETE RESTRICT,
    solicitado_por UUID NOT NULL DEFAULT auth.uid() REFERENCES public.usuarios(id_usuario) ON DELETE RESTRICT,
    nombre_herramienta VARCHAR(150) NOT NULL,
    cantidad INTEGER NOT NULL CHECK (cantidad BETWEEN 1 AND 100),
    fecha_devolucion_prevista DATE NOT NULL,
    motivo TEXT,
    estado VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE'
        CHECK (estado IN ('PENDIENTE','APROBADA','RECHAZADA','ENTREGADA','CANCELADA')),
    procesado_por UUID REFERENCES public.usuarios(id_usuario) ON DELETE RESTRICT,
    motivo_resolucion TEXT,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    procesado_en TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_solicitudes_herramientas_proyecto
    ON public.conterreno_solicitudes_herramientas(proyecto_id, estado, creado_en DESC);
CREATE INDEX IF NOT EXISTS idx_solicitudes_herramientas_operario
    ON public.conterreno_solicitudes_herramientas(solicitado_por, creado_en DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_solicitud_herramienta_pendiente
    ON public.conterreno_solicitudes_herramientas(
        proyecto_id,
        solicitado_por,
        lower(nombre_herramienta),
        cantidad,
        fecha_devolucion_prevista
    )
    WHERE estado = 'PENDIENTE';

ALTER TABLE public.conterreno_solicitudes_herramientas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS solicitudes_herramientas_operario ON public.conterreno_solicitudes_herramientas;
CREATE POLICY solicitudes_herramientas_operario
    ON public.conterreno_solicitudes_herramientas
    FOR SELECT TO authenticated
    USING (
        solicitado_por = auth.uid()
        OR public.fn_conterreno_tiene_permiso(proyecto_id, 'HERRAMIENTA_SOLICITUD_GESTIONAR')
    );

REVOKE ALL ON TABLE public.conterreno_solicitudes_herramientas
    FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.conterreno_solicitudes_herramientas
    TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_auditar_solicitud_herramientas()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_nuevo JSONB;
    v_anterior JSONB;
    v_accion TEXT;
BEGIN
    v_nuevo := CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) ELSE NULL END;
    v_anterior := CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) ELSE NULL END;
    v_accion := CASE
        WHEN TG_OP = 'INSERT' THEN 'SOLICITUD_CREADA'
        WHEN TG_OP = 'DELETE' THEN 'SOLICITUD_ELIMINADA'
        WHEN COALESCE(v_anterior ->> 'estado', '') <>
             COALESCE(v_nuevo ->> 'estado', '')
            THEN 'ESTADO_ACTUALIZADO'
        ELSE 'SOLICITUD_ACTUALIZADA'
    END;

    INSERT INTO public.conterreno_historial_eventos (
        proyecto_id, entidad, registro_id, accion, actor_id,
        usuario_relacionado_id, resumen, datos_anteriores, datos_nuevos
    )
    VALUES (
        COALESCE(v_nuevo ->> 'proyecto_id', v_anterior ->> 'proyecto_id'),
        'HERRAMIENTAS',
        COALESCE(v_nuevo ->> 'id', v_anterior ->> 'id', 'sin-id'),
        v_accion,
        auth.uid(),
        NULLIF(COALESCE(v_nuevo ->> 'solicitado_por', v_anterior ->> 'solicitado_por'), '')::UUID,
        'Solicitud de herramienta: ' ||
            COALESCE(v_nuevo ->> 'nombre_herramienta', v_anterior ->> 'nombre_herramienta', ''),
        CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE jsonb_build_object(
            'estado', v_anterior -> 'estado',
            'cantidad', v_anterior -> 'cantidad',
            'motivo_resolucion', v_anterior -> 'motivo_resolucion'
        ) END,
        CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE jsonb_build_object(
            'estado', v_nuevo -> 'estado',
            'cantidad', v_nuevo -> 'cantidad',
            'fecha_devolucion_prevista', v_nuevo -> 'fecha_devolucion_prevista',
            'motivo', v_nuevo -> 'motivo',
            'motivo_resolucion', v_nuevo -> 'motivo_resolucion'
        ) END
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_auditar_solicitud_herramientas()
    FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_historial_solicitudes_herramientas ON public.conterreno_solicitudes_herramientas;
CREATE TRIGGER trg_historial_solicitudes_herramientas
    AFTER INSERT OR UPDATE OR DELETE ON public.conterreno_solicitudes_herramientas
    FOR EACH ROW EXECUTE FUNCTION public.fn_auditar_solicitud_herramientas();

CREATE OR REPLACE FUNCTION public.fn_conterreno_solicitar_herramientas(
    p_proyecto_id TEXT,
    p_nombre_herramienta TEXT,
    p_cantidad INTEGER,
    p_fecha_devolucion DATE,
    p_motivo TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_id UUID;
    v_hoy DATE := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::DATE;
    v_disponibles INTEGER;
    v_fecha_inicio DATE;
    v_fecha_termino DATE;
BEGIN
    IF NOT public.fn_conterreno_tiene_permiso(p_proyecto_id, 'HERRAMIENTA_SOLICITAR') THEN
        RAISE EXCEPTION 'Solo un trabajador asignado puede solicitar herramientas.';
    END IF;
    IF p_nombre_herramienta IS NULL OR length(trim(p_nombre_herramienta)) < 2 THEN
        RAISE EXCEPTION 'Indica la herramienta que necesitas.';
    END IF;
    IF p_cantidad IS NULL OR p_cantidad < 1 OR p_cantidad > 100 THEN
        RAISE EXCEPTION 'La cantidad debe estar entre 1 y 100.';
    END IF;
    IF p_fecha_devolucion IS NULL OR p_fecha_devolucion < v_hoy THEN
        RAISE EXCEPTION 'Indica una fecha de devolución igual o posterior a hoy.';
    END IF;
    SELECT fecha_inicio, fecha_termino INTO v_fecha_inicio, v_fecha_termino
    FROM public.conterreno_proyectos
    WHERE id = p_proyecto_id;
    IF v_fecha_inicio IS NOT NULL AND p_fecha_devolucion < v_fecha_inicio THEN
        RAISE EXCEPTION 'La devolución no puede ser anterior al inicio de la obra.';
    END IF;
    IF v_fecha_termino IS NOT NULL AND p_fecha_devolucion > v_fecha_termino THEN
        RAISE EXCEPTION 'La devolución no puede exceder el término de la obra.';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM public.conterreno_solicitudes_herramientas
        WHERE proyecto_id = p_proyecto_id
          AND solicitado_por = auth.uid()
          AND estado = 'PENDIENTE'
          AND lower(nombre_herramienta) = lower(trim(p_nombre_herramienta))
          AND cantidad = p_cantidad
          AND fecha_devolucion_prevista = p_fecha_devolucion
    ) THEN
        RAISE EXCEPTION 'Ya existe una solicitud pendiente igual. Puedes esperar su resolución o cancelar esa solicitud.';
    END IF;

    SELECT count(*)
    INTO v_disponibles
    FROM public.equipos_herramientas
    WHERE proyecto_id = p_proyecto_id
      AND activo = TRUE
      AND disponible = TRUE
      AND estado_fisico = 'OPTIMO'
      AND lower(nombre) = lower(trim(p_nombre_herramienta));

    INSERT INTO public.conterreno_solicitudes_herramientas (
        proyecto_id, solicitado_por, nombre_herramienta, cantidad,
        fecha_devolucion_prevista, motivo
    )
    VALUES (
        p_proyecto_id, auth.uid(), trim(p_nombre_herramienta), p_cantidad,
        p_fecha_devolucion, nullif(trim(COALESCE(p_motivo, '')), '')
    )
    RETURNING id INTO v_id;

    INSERT INTO public.kardex_transaccional (
        modulo, proyecto_id, codigo_operacion, id_usuario_ejecutor,
        id_registro_referencia, payload_jsonb
    )
    VALUES (
        'BODEGA_IOT', p_proyecto_id, 'SOLICITUD_HERRAMIENTA',
        auth.uid(), v_id::TEXT,
        jsonb_build_object(
            'cantidad', p_cantidad,
            'nombre_herramienta', trim(p_nombre_herramienta),
            'disponibles_actuales', v_disponibles
        )
    );
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_conterreno_cancelar_solicitud_herramientas(
    p_solicitud_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_solicitud public.conterreno_solicitudes_herramientas%ROWTYPE;
BEGIN
    SELECT * INTO v_solicitud
    FROM public.conterreno_solicitudes_herramientas
    WHERE id = p_solicitud_id
      AND solicitado_por = auth.uid()
      AND estado = 'PENDIENTE'
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La solicitud no existe, no te pertenece o ya fue resuelta.';
    END IF;
    IF NOT public.fn_conterreno_tiene_permiso(
        v_solicitud.proyecto_id, 'HERRAMIENTA_SOLICITAR'
    ) THEN
        RAISE EXCEPTION 'No tienes permiso para cancelar esta solicitud.';
    END IF;

    UPDATE public.conterreno_solicitudes_herramientas
    SET estado = 'CANCELADA',
        procesado_por = auth.uid(),
        motivo_resolucion = 'Cancelada por el solicitante.',
        procesado_en = CURRENT_TIMESTAMP
    WHERE id = p_solicitud_id;

    INSERT INTO public.kardex_transaccional (
        modulo, proyecto_id, codigo_operacion, id_usuario_ejecutor,
        id_registro_referencia, payload_jsonb
    )
    VALUES (
        'BODEGA_IOT', v_solicitud.proyecto_id,
        'SOLICITUD_HERRAMIENTA_CANCELADA',
        auth.uid(), p_solicitud_id::TEXT,
        jsonb_build_object('estado', 'CANCELADA')
    );
    RETURN p_solicitud_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_conterreno_gestionar_solicitud_herramientas(
    p_solicitud_id UUID,
    p_accion TEXT,
    p_motivo TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_solicitud public.conterreno_solicitudes_herramientas%ROWTYPE;
    v_equipos UUID[];
    v_equipo UUID;
    v_hoy DATE := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::DATE;
    v_fecha_inicio DATE;
    v_fecha_termino DATE;
BEGIN
    SELECT * INTO v_solicitud
    FROM public.conterreno_solicitudes_herramientas
    WHERE id = p_solicitud_id
      AND estado = 'PENDIENTE'
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La solicitud no existe o ya fue resuelta.';
    END IF;
    IF NOT public.fn_conterreno_tiene_permiso(
        v_solicitud.proyecto_id, 'HERRAMIENTA_SOLICITUD_GESTIONAR'
    ) THEN
        RAISE EXCEPTION 'Solo Bodega puede gestionar solicitudes de herramientas.';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM public.conterreno_usuarios_proyectos AS up
        JOIN public.usuarios AS u ON u.id_usuario = up.usuario_auth_id
        JOIN public.roles AS r ON r.id_rol = u.id_rol
        WHERE up.proyecto_id = v_solicitud.proyecto_id
          AND up.usuario_auth_id = v_solicitud.solicitado_por
          AND up.activo = TRUE
          AND u.activo = TRUE
          AND u.bloqueado = FALSE
          AND r.codigo_rol = 'OPERARIO_MAESTRO'
          AND r.activo = TRUE
    ) THEN
        RAISE EXCEPTION 'El solicitante ya no tiene una asignación activa de Operario.';
    END IF;
    SELECT fecha_inicio, fecha_termino INTO v_fecha_inicio, v_fecha_termino
    FROM public.conterreno_proyectos
    WHERE id = v_solicitud.proyecto_id;
    IF v_fecha_inicio IS NOT NULL
       AND v_solicitud.fecha_devolucion_prevista < v_fecha_inicio THEN
        RAISE EXCEPTION 'La devolución solicitada es anterior al inicio de la obra.';
    END IF;
    IF v_fecha_termino IS NOT NULL
       AND v_solicitud.fecha_devolucion_prevista > v_fecha_termino THEN
        RAISE EXCEPTION 'La devolución solicitada excede el término de la obra.';
    END IF;
    IF upper(trim(p_accion)) = 'APROBAR_ENTREGAR'
       AND v_solicitud.fecha_devolucion_prevista < v_hoy THEN
        RAISE EXCEPTION 'La devolución solicitada ya venció; rechaza o pide una nueva fecha.';
    END IF;

    IF upper(trim(p_accion)) = 'RECHAZAR' THEN
        IF p_motivo IS NULL OR length(trim(p_motivo)) < 3 THEN
            RAISE EXCEPTION 'Indica el motivo del rechazo.';
        END IF;
        UPDATE public.conterreno_solicitudes_herramientas
        SET estado = 'RECHAZADA',
            procesado_por = auth.uid(),
            motivo_resolucion = trim(p_motivo),
            procesado_en = CURRENT_TIMESTAMP
        WHERE id = p_solicitud_id;
    ELSIF upper(trim(p_accion)) = 'APROBAR_ENTREGAR' THEN
        v_equipos := ARRAY[]::UUID[];
        FOR v_equipo IN
            SELECT id_equipo
            FROM public.equipos_herramientas
            WHERE proyecto_id = v_solicitud.proyecto_id
              AND activo = TRUE
              AND disponible = TRUE
              AND estado_fisico = 'OPTIMO'
              AND lower(nombre) = lower(v_solicitud.nombre_herramienta)
            ORDER BY creado_en, id_equipo
            LIMIT v_solicitud.cantidad
            FOR UPDATE
        LOOP
            v_equipos := array_append(v_equipos, v_equipo);
        END LOOP;
        IF coalesce(array_length(v_equipos, 1), 0) < v_solicitud.cantidad THEN
            RAISE EXCEPTION 'No hay suficientes unidades disponibles para esta solicitud.';
        END IF;

        FOREACH v_equipo IN ARRAY v_equipos LOOP
            UPDATE public.equipos_herramientas
            SET disponible = FALSE
            WHERE id_equipo = v_equipo
              AND proyecto_id = v_solicitud.proyecto_id
              AND activo = TRUE
              AND disponible = TRUE
              AND estado_fisico = 'OPTIMO';
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Una herramienta dejó de estar disponible mientras se procesaba la solicitud.';
            END IF;

            INSERT INTO public.prestamos (
                proyecto_id, id_equipo, id_trabajador, id_bodeguero,
                fecha_devolucion_prevista
            )
            VALUES (
                v_solicitud.proyecto_id, v_equipo, v_solicitud.solicitado_por,
                auth.uid(), v_solicitud.fecha_devolucion_prevista
            );

            INSERT INTO public.kardex_transaccional (
                modulo, proyecto_id, codigo_operacion, id_usuario_ejecutor,
                id_registro_referencia, payload_jsonb
            )
            VALUES (
                'BODEGA_IOT',
                v_solicitud.proyecto_id,
                'PRESTAMO_REGISTRADO_DESDE_SOLICITUD',
                auth.uid(),
                v_equipo::TEXT,
                jsonb_build_object(
                    'solicitud_id', p_solicitud_id,
                    'id_equipo', v_equipo,
                    'id_trabajador', v_solicitud.solicitado_por,
                    'fecha_devolucion_prevista', v_solicitud.fecha_devolucion_prevista
                )
            );
        END LOOP;

        UPDATE public.conterreno_solicitudes_herramientas
        SET estado = 'ENTREGADA',
            procesado_por = auth.uid(),
            procesado_en = CURRENT_TIMESTAMP
        WHERE id = p_solicitud_id;
    ELSE
        RAISE EXCEPTION 'Acción no válida.';
    END IF;

    INSERT INTO public.kardex_transaccional (
        modulo, proyecto_id, codigo_operacion, id_usuario_ejecutor,
        id_registro_referencia, payload_jsonb
    )
    VALUES (
        'BODEGA_IOT', v_solicitud.proyecto_id,
        upper(trim(p_accion)) || '_SOLICITUD_HERRAMIENTA',
        auth.uid(), p_solicitud_id::TEXT,
        jsonb_build_object('estado', upper(trim(p_accion)), 'motivo', p_motivo)
    );
    RETURN p_solicitud_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_conterreno_solicitar_herramientas(TEXT,TEXT,INTEGER,DATE,TEXT)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_conterreno_cancelar_solicitud_herramientas(UUID)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_conterreno_gestionar_solicitud_herramientas(UUID,TEXT,TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_solicitar_herramientas(TEXT,TEXT,INTEGER,DATE,TEXT)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_cancelar_solicitud_herramientas(UUID)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_gestionar_solicitud_herramientas(UUID,TEXT,TEXT)
    TO authenticated;

COMMIT;
