BEGIN;

CREATE OR REPLACE FUNCTION public.fn_conterreno_consultar_asistencia_mensual(
    p_proyecto_id TEXT,
    p_mes DATE
)
RETURNS TABLE (
    proyecto_id TEXT,
    proyecto_nombre TEXT,
    usuario_id UUID,
    nombre_completo TEXT,
    codigo_rol TEXT,
    jornadas_programadas INTEGER,
    jornadas_asistidas INTEGER,
    jornadas_sin_marcaje INTEGER,
    jornadas_sin_salida INTEGER,
    porcentaje_asistencia NUMERIC,
    estado_calculo TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_usuario UUID := auth.uid();
    v_rol TEXT;
    v_admin BOOLEAN;
    v_hoy DATE := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::DATE;
BEGIN
    IF v_usuario IS NULL OR p_mes IS NULL
       OR p_mes <> date_trunc('month', p_mes)::DATE
       OR p_mes > date_trunc('month', v_hoy)::DATE THEN
        RAISE EXCEPTION 'Selecciona el primer día de un mes ya iniciado.';
    END IF;

    SELECT r.codigo_rol
      INTO v_rol
    FROM public.usuarios AS u
    JOIN public.roles AS r ON r.id_rol = u.id_rol
    WHERE u.id_usuario = v_usuario
      AND u.activo = TRUE
      AND u.bloqueado = FALSE
      AND r.activo = TRUE;
    IF v_rol IS NULL THEN
        RAISE EXCEPTION 'No tienes un perfil activo para consultar asistencia.';
    END IF;

    v_admin := v_rol = 'ADMIN_GENERAL';
    IF v_admin THEN
        NULL;
    ELSIF v_rol = 'JEFE_OBRA' THEN
        IF p_proyecto_id IS NULL
           OR NOT public.fn_conterreno_tiene_permiso(
               p_proyecto_id, 'ASISTENCIA_CONSULTAR'
           ) THEN
            RAISE EXCEPTION 'No tienes permiso para consultar asistencia de esta obra.';
        END IF;
    ELSIF v_rol IN ('BODEGUERO', 'OPERARIO_MAESTRO') THEN
        IF p_proyecto_id IS NULL OR NOT EXISTS (
            SELECT 1
            FROM public.conterreno_usuarios_proyectos AS up
            WHERE up.proyecto_id = p_proyecto_id
              AND up.usuario_auth_id = v_usuario
              AND up.activo = TRUE
        ) THEN
            RAISE EXCEPTION 'Solo puedes consultar tu asistencia en una obra asignada.';
        END IF;
    ELSE
        RAISE EXCEPTION 'Tu rol no puede consultar este resumen de asistencia.';
    END IF;

    RETURN QUERY
    WITH personas AS (
        SELECT
            p.id AS proyecto_id,
            p.nombre AS proyecto_nombre,
            up.usuario_auth_id AS usuario_id,
            trim(u.nombres || ' ' || u.apellidos)::TEXT AS nombre_completo,
            r.codigo_rol,
            p.fecha_inicio,
            p.fecha_termino,
            p.dias_laborales,
            p.hora_termino_jornada,
            GREATEST(
                p_mes,
                COALESCE(p.fecha_inicio, p_mes),
                (up.creado_en AT TIME ZONE 'America/Santiago')::DATE
            ) AS fecha_desde,
            LEAST(
                (p_mes + INTERVAL '1 month - 1 day')::DATE,
                COALESCE(p.fecha_termino, (p_mes + INTERVAL '1 month - 1 day')::DATE),
                CASE
                    WHEN (p_mes + INTERVAL '1 month - 1 day')::DATE < v_hoy
                        THEN (p_mes + INTERVAL '1 month - 1 day')::DATE
                    WHEN (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::TIME
                         >= p.hora_termino_jornada
                        THEN v_hoy
                    WHEN EXISTS (
                        SELECT 1
                        FROM public.marcajes_asistencia AS today_mark
                        WHERE today_mark.proyecto_id = p.id
                          AND today_mark.id_usuario = up.usuario_auth_id
                          AND (today_mark.fecha_hora_entrada
                               AT TIME ZONE 'America/Santiago')::DATE = v_hoy
                    )
                        THEN v_hoy
                    ELSE v_hoy - 1
                END
            ) AS fecha_hasta
        FROM public.conterreno_usuarios_proyectos AS up
        JOIN public.conterreno_proyectos AS p ON p.id = up.proyecto_id
        JOIN public.usuarios AS u ON u.id_usuario = up.usuario_auth_id
        JOIN public.roles AS r ON r.id_rol = u.id_rol
        WHERE up.activo = TRUE
          AND u.activo = TRUE
          AND u.bloqueado = FALSE
          AND r.activo = TRUE
          AND (p_proyecto_id IS NULL OR p.id = p_proyecto_id)
          AND (
              v_admin
              OR (v_rol = 'JEFE_OBRA' AND EXISTS (
                  SELECT 1
                  FROM public.conterreno_usuarios_proyectos AS membership
                  WHERE membership.proyecto_id = p.id
                    AND membership.usuario_auth_id = v_usuario
                    AND membership.activo = TRUE
              ))
              OR (
                  v_rol IN ('BODEGUERO', 'OPERARIO_MAESTRO')
                  AND up.usuario_auth_id = v_usuario
                  AND p.id = p_proyecto_id
              )
          )
    ),
    dias_programados AS (
        SELECT pe.proyecto_id, pe.usuario_id, dia.fecha::DATE AS fecha
        FROM personas AS pe
        CROSS JOIN LATERAL generate_series(
            pe.fecha_desde::TIMESTAMP,
            pe.fecha_hasta::TIMESTAMP,
            INTERVAL '1 day'
        ) AS dia(fecha)
        WHERE pe.dias_laborales IS NOT NULL
          AND pe.fecha_desde <= pe.fecha_hasta
          AND extract(ISODOW FROM dia.fecha)::SMALLINT = ANY(pe.dias_laborales)
    ),
    marcas_por_dia AS (
        SELECT
            m.proyecto_id,
            m.id_usuario AS usuario_id,
            (m.fecha_hora_entrada AT TIME ZONE 'America/Santiago')::DATE AS fecha,
            bool_or(m.fecha_hora_salida IS NULL) AS sin_salida
        FROM public.marcajes_asistencia AS m
        JOIN personas AS pe
          ON pe.proyecto_id = m.proyecto_id
         AND pe.usuario_id = m.id_usuario
        WHERE (m.fecha_hora_entrada AT TIME ZONE 'America/Santiago')::DATE
              BETWEEN pe.fecha_desde AND pe.fecha_hasta
        GROUP BY m.proyecto_id, m.id_usuario,
                 (m.fecha_hora_entrada AT TIME ZONE 'America/Santiago')::DATE
    ),
    resumen AS (
        SELECT
            pe.proyecto_id,
            pe.proyecto_nombre,
            pe.usuario_id,
            pe.nombre_completo,
            pe.codigo_rol,
            count(dp.fecha)::INTEGER AS jornadas_programadas,
            count(dp.fecha) FILTER (WHERE md.fecha IS NOT NULL)::INTEGER
                AS jornadas_asistidas,
            count(dp.fecha) FILTER (WHERE md.fecha IS NULL)::INTEGER
                AS jornadas_sin_marcaje,
            count(dp.fecha) FILTER (WHERE md.sin_salida IS TRUE)::INTEGER
                AS jornadas_sin_salida,
            (pe.dias_laborales IS NOT NULL) AS jornada_configurada
        FROM personas AS pe
        LEFT JOIN dias_programados AS dp
          ON dp.proyecto_id = pe.proyecto_id
         AND dp.usuario_id = pe.usuario_id
        LEFT JOIN marcas_por_dia AS md
          ON md.proyecto_id = dp.proyecto_id
         AND md.usuario_id = dp.usuario_id
         AND md.fecha = dp.fecha
        GROUP BY pe.proyecto_id, pe.proyecto_nombre, pe.usuario_id,
                 pe.nombre_completo, pe.codigo_rol, pe.dias_laborales
    )
    SELECT
        r.proyecto_id,
        r.proyecto_nombre::TEXT,
        r.usuario_id,
        r.nombre_completo,
        r.codigo_rol::TEXT,
        r.jornadas_programadas,
        r.jornadas_asistidas,
        r.jornadas_sin_marcaje,
        r.jornadas_sin_salida,
        CASE WHEN r.jornada_configurada AND r.jornadas_programadas > 0
             THEN round(
                 100.0 * r.jornadas_asistidas / r.jornadas_programadas, 2
             )
             ELSE NULL
        END AS porcentaje_asistencia,
        CASE
            WHEN NOT r.jornada_configurada THEN 'SIN_JORNADA_CONFIGURADA'
            WHEN r.jornadas_programadas = 0 THEN 'SIN_JORNADAS_EN_PERIODO'
            ELSE 'CALCULABLE'
        END AS estado_calculo
    FROM resumen AS r
    ORDER BY r.proyecto_nombre, r.nombre_completo;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_conterreno_consultar_asistencia_mensual(TEXT, DATE)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_consultar_asistencia_mensual(TEXT, DATE)
    TO authenticated;

COMMIT;
