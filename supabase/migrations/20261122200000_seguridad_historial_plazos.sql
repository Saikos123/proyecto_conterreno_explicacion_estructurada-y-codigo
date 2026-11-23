BEGIN;

ALTER TABLE public.conterreno_proyectos
    ADD COLUMN IF NOT EXISTS fecha_inicio DATE,
    ADD COLUMN IF NOT EXISTS fecha_termino DATE,
    ADD COLUMN IF NOT EXISTS dias_laborales SMALLINT[],
    ADD COLUMN IF NOT EXISTS hora_inicio_jornada TIME,
    ADD COLUMN IF NOT EXISTS hora_termino_jornada TIME;

ALTER TABLE public.conterreno_tareas
    ADD COLUMN IF NOT EXISTS fecha_inicio DATE,
    ADD COLUMN IF NOT EXISTS fecha_limite DATE;

ALTER TABLE public.prestamos
    ADD COLUMN IF NOT EXISTS fecha_devolucion_prevista DATE;

CREATE OR REPLACE FUNCTION public.fn_conterreno_dias_laborales_validos(
    p_dias SMALLINT[]
)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
SET search_path = ''
AS $$
    SELECT p_dias IS NULL OR (
        cardinality(p_dias) BETWEEN 1 AND 7
        AND NOT EXISTS (
            SELECT 1 FROM unnest(p_dias) AS dia
            WHERE dia < 1 OR dia > 7
        )
        AND cardinality(p_dias) = (
            SELECT count(DISTINCT dia) FROM unnest(p_dias) AS dia
        )
    );
$$;

ALTER TABLE public.conterreno_proyectos
    DROP CONSTRAINT IF EXISTS conterreno_proyectos_fechas_validas,
    ADD CONSTRAINT conterreno_proyectos_fechas_validas
        CHECK (fecha_inicio IS NULL OR fecha_termino IS NULL OR fecha_termino >= fecha_inicio),
    DROP CONSTRAINT IF EXISTS conterreno_proyectos_jornada_valida,
    ADD CONSTRAINT conterreno_proyectos_jornada_valida CHECK (
        (dias_laborales IS NULL AND hora_inicio_jornada IS NULL AND hora_termino_jornada IS NULL)
        OR (
            dias_laborales IS NOT NULL
            AND cardinality(dias_laborales) BETWEEN 1 AND 7
            AND hora_inicio_jornada IS NOT NULL
            AND hora_termino_jornada IS NOT NULL
            AND hora_termino_jornada > hora_inicio_jornada
            AND public.fn_conterreno_dias_laborales_validos(dias_laborales)
        )
    );

ALTER TABLE public.conterreno_tareas
    DROP CONSTRAINT IF EXISTS conterreno_tareas_fechas_validas,
    ADD CONSTRAINT conterreno_tareas_fechas_validas
        CHECK (fecha_inicio IS NULL OR fecha_limite IS NULL OR fecha_limite >= fecha_inicio);

CREATE INDEX IF NOT EXISTS idx_conterreno_tareas_fecha_limite
    ON public.conterreno_tareas(proyecto_id, fecha_limite);
CREATE INDEX IF NOT EXISTS idx_prestamos_fecha_devolucion_prevista
    ON public.prestamos(proyecto_id, fecha_devolucion_prevista)
    WHERE fecha_hora_devolucion IS NULL;

CREATE OR REPLACE FUNCTION public.fn_conterreno_validar_plazo_tarea()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
    v_fecha_inicio DATE;
    v_fecha_termino DATE;
BEGIN
    SELECT p.fecha_inicio, p.fecha_termino
      INTO v_fecha_inicio, v_fecha_termino
    FROM public.conterreno_proyectos AS p
    WHERE p.id = NEW.proyecto_id;

    IF v_fecha_inicio IS NOT NULL AND NEW.fecha_inicio IS NOT NULL
       AND NEW.fecha_inicio < v_fecha_inicio THEN
        RAISE EXCEPTION 'El inicio de la tarea no puede ser anterior al inicio de la obra.';
    END IF;
    IF v_fecha_inicio IS NOT NULL AND NEW.fecha_limite IS NOT NULL
       AND NEW.fecha_limite < v_fecha_inicio THEN
        RAISE EXCEPTION 'El vencimiento de la tarea no puede ser anterior al inicio de la obra.';
    END IF;
    IF v_fecha_termino IS NOT NULL AND NEW.fecha_inicio IS NOT NULL
       AND NEW.fecha_inicio > v_fecha_termino THEN
        RAISE EXCEPTION 'El inicio de la tarea no puede exceder el término de la obra.';
    END IF;
    IF v_fecha_termino IS NOT NULL AND NEW.fecha_limite IS NOT NULL
       AND NEW.fecha_limite > v_fecha_termino THEN
        RAISE EXCEPTION 'El vencimiento de la tarea no puede exceder el término de la obra.';
    END IF;
    IF NEW.fecha_inicio IS NOT NULL AND NEW.fecha_limite IS NOT NULL
       AND NEW.fecha_limite < NEW.fecha_inicio THEN
        RAISE EXCEPTION 'El vencimiento no puede ser anterior al inicio de la tarea.';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_conterreno_tarea_validar_plazo
    ON public.conterreno_tareas;
CREATE TRIGGER trg_conterreno_tarea_validar_plazo
    BEFORE INSERT OR UPDATE OF proyecto_id, fecha_inicio, fecha_limite
    ON public.conterreno_tareas
    FOR EACH ROW EXECUTE FUNCTION public.fn_conterreno_validar_plazo_tarea();

INSERT INTO public.permisos (codigo_permiso, modulo, descripcion)
VALUES (
    'HISTORIAL_CONSULTAR',
    'AUDITORIA',
    'Consultar y exportar el historial permitido para el rol y la obra asignada.'
)
ON CONFLICT (codigo_permiso) DO UPDATE
SET modulo = EXCLUDED.modulo,
    descripcion = EXCLUDED.descripcion;

INSERT INTO public.rol_permisos (id_rol, id_permiso)
SELECT r.id_rol, p.id_permiso
FROM public.roles AS r
CROSS JOIN public.permisos AS p
WHERE r.codigo_rol IN ('ADMIN_GENERAL', 'JEFE_OBRA', 'BODEGUERO', 'OPERARIO_MAESTRO')
  AND p.codigo_permiso = 'HISTORIAL_CONSULTAR'
ON CONFLICT (id_rol, id_permiso) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.conterreno_auth_intentos (
    email_hash VARCHAR(64) NOT NULL CHECK (email_hash ~ '^[0-9a-f]{64}$'),
    ip_hash VARCHAR(64) NOT NULL CHECK (ip_hash ~ '^[0-9a-f]{64}$'),
    intentos_fallidos INTEGER NOT NULL DEFAULT 1 CHECK (intentos_fallidos BETWEEN 1 AND 3),
    ventana_inicio TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bloqueado_hasta TIMESTAMPTZ,
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (email_hash, ip_hash)
);

CREATE INDEX IF NOT EXISTS idx_conterreno_auth_intentos_actualizado
    ON public.conterreno_auth_intentos(actualizado_en);

ALTER TABLE public.conterreno_auth_intentos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.conterreno_auth_intentos FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON public.conterreno_auth_intentos TO service_role;

CREATE OR REPLACE FUNCTION public.fn_conterreno_registrar_fallo_login(
    p_email_hash TEXT,
    p_ip_hash TEXT
)
RETURNS TABLE (intentos INTEGER, bloqueado_hasta TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF p_email_hash !~ '^[0-9a-f]{64}$' OR p_ip_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'Identificador de intento no válido.';
    END IF;

    RETURN QUERY
    INSERT INTO public.conterreno_auth_intentos AS actual (
        email_hash, ip_hash, intentos_fallidos, ventana_inicio,
        bloqueado_hasta, actualizado_en
    )
    VALUES (p_email_hash, p_ip_hash, 1, CURRENT_TIMESTAMP, NULL, CURRENT_TIMESTAMP)
    ON CONFLICT (email_hash, ip_hash) DO UPDATE
    SET intentos_fallidos = CASE
            WHEN actual.bloqueado_hasta > CURRENT_TIMESTAMP THEN actual.intentos_fallidos
            WHEN actual.ventana_inicio <= CURRENT_TIMESTAMP - INTERVAL '15 minutes' THEN 1
            ELSE LEAST(actual.intentos_fallidos + 1, 3)
        END,
        ventana_inicio = CASE
            WHEN actual.bloqueado_hasta > CURRENT_TIMESTAMP THEN actual.ventana_inicio
            WHEN actual.ventana_inicio <= CURRENT_TIMESTAMP - INTERVAL '15 minutes' THEN CURRENT_TIMESTAMP
            ELSE actual.ventana_inicio
        END,
        bloqueado_hasta = CASE
            WHEN actual.bloqueado_hasta > CURRENT_TIMESTAMP THEN actual.bloqueado_hasta
            WHEN actual.ventana_inicio <= CURRENT_TIMESTAMP - INTERVAL '15 minutes' THEN NULL
            WHEN actual.intentos_fallidos + 1 >= 3 THEN CURRENT_TIMESTAMP + INTERVAL '15 minutes'
            ELSE NULL
        END,
        actualizado_en = CURRENT_TIMESTAMP
    RETURNING actual.intentos_fallidos, actual.bloqueado_hasta;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_conterreno_registrar_fallo_login(TEXT, TEXT)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_registrar_fallo_login(TEXT, TEXT)
    TO service_role;

CREATE TABLE IF NOT EXISTS public.conterreno_historial_eventos (
    id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    proyecto_id TEXT REFERENCES public.conterreno_proyectos(id) ON DELETE RESTRICT,
    entidad VARCHAR(40) NOT NULL,
    registro_id TEXT NOT NULL,
    accion VARCHAR(40) NOT NULL,
    actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    usuario_relacionado_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    resumen TEXT NOT NULL,
    datos_anteriores JSONB,
    datos_nuevos JSONB,
    ocurrido_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_conterreno_historial_proyecto_fecha
    ON public.conterreno_historial_eventos(proyecto_id, ocurrido_en DESC);
CREATE INDEX IF NOT EXISTS idx_conterreno_historial_actor_fecha
    ON public.conterreno_historial_eventos(actor_id, ocurrido_en DESC);
CREATE INDEX IF NOT EXISTS idx_conterreno_historial_usuario_fecha
    ON public.conterreno_historial_eventos(usuario_relacionado_id, ocurrido_en DESC);

ALTER TABLE public.conterreno_historial_eventos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.conterreno_historial_eventos FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_conterreno_historial_inmutable()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    RAISE EXCEPTION 'El historial es inalterable.';
END;
$$;

DROP TRIGGER IF EXISTS trg_conterreno_historial_inmutable
    ON public.conterreno_historial_eventos;
CREATE TRIGGER trg_conterreno_historial_inmutable
    BEFORE UPDATE OR DELETE ON public.conterreno_historial_eventos
    FOR EACH ROW EXECUTE FUNCTION public.fn_conterreno_historial_inmutable();

CREATE OR REPLACE FUNCTION public.fn_conterreno_auditar_historial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_anterior JSONB;
    v_nuevo JSONB;
    v_proyecto_id TEXT;
    v_registro_id TEXT;
    v_actor_id UUID;
    v_usuario_relacionado_id UUID;
    v_entidad TEXT;
    v_accion TEXT;
    v_resumen TEXT;
    v_datos_anteriores JSONB;
    v_datos_nuevos JSONB;
BEGIN
    v_anterior := CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) ELSE NULL END;
    v_nuevo := CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) ELSE NULL END;
    v_proyecto_id := COALESCE(
        v_nuevo ->> 'proyecto_id',
        v_anterior ->> 'proyecto_id',
        CASE WHEN TG_TABLE_NAME = 'conterreno_proyectos'
             THEN COALESCE(v_nuevo ->> 'id', v_anterior ->> 'id') END
    );
    v_registro_id := COALESCE(
        v_nuevo ->> 'id',
        v_nuevo ->> 'id_prestamo',
        v_nuevo ->> 'id_marcaje',
        v_nuevo ->> 'id_equipo',
        v_nuevo ->> 'id_kardex',
        v_anterior ->> 'id',
        v_anterior ->> 'id_prestamo',
        v_anterior ->> 'id_marcaje',
        v_anterior ->> 'id_equipo',
        v_anterior ->> 'id_kardex',
        'sin-id'
    );
    v_actor_id := COALESCE(
        auth.uid(),
        NULLIF(COALESCE(v_nuevo ->> 'creado_por', v_anterior ->> 'creado_por'), '')::UUID,
        NULLIF(COALESCE(v_nuevo ->> 'id_usuario', v_anterior ->> 'id_usuario'), '')::UUID,
        NULLIF(COALESCE(v_nuevo ->> 'id_bodeguero', v_anterior ->> 'id_bodeguero'), '')::UUID,
        NULLIF(COALESCE(v_nuevo ->> 'ejecutado_por', v_anterior ->> 'ejecutado_por'), '')::UUID,
        NULLIF(COALESCE(v_nuevo ->> 'solicitado_por', v_anterior ->> 'solicitado_por'), '')::UUID,
        NULLIF(COALESCE(v_nuevo ->> 'registrado_por', v_anterior ->> 'registrado_por'), '')::UUID,
        NULLIF(COALESCE(v_nuevo ->> 'recibido_por', v_anterior ->> 'recibido_por'), '')::UUID
    );
    v_usuario_relacionado_id := COALESCE(
        NULLIF(COALESCE(v_nuevo ->> 'responsable_id', v_anterior ->> 'responsable_id'), '')::UUID,
        NULLIF(COALESCE(v_nuevo ->> 'id_usuario', v_anterior ->> 'id_usuario'), '')::UUID,
        NULLIF(COALESCE(v_nuevo ->> 'id_trabajador', v_anterior ->> 'id_trabajador'), '')::UUID,
        NULLIF(COALESCE(v_nuevo ->> 'solicitado_por', v_anterior ->> 'solicitado_por'), '')::UUID
    );
    v_entidad := CASE TG_TABLE_NAME
        WHEN 'conterreno_proyectos' THEN 'PROYECTOS'
        WHEN 'conterreno_tareas' THEN 'TAREAS'
        WHEN 'conterreno_incidencias' THEN 'INCIDENCIAS'
        WHEN 'marcajes_asistencia' THEN 'ASISTENCIA'
        WHEN 'prestamos' THEN 'PRESTAMOS'
        WHEN 'equipos_herramientas' THEN 'HERRAMIENTAS'
        WHEN 'conterreno_movimientos_materiales' THEN 'MATERIALES'
        WHEN 'conterreno_pedidos_materiales' THEN 'PEDIDOS'
        WHEN 'conterreno_ordenes_compra' THEN 'COMPRAS'
        WHEN 'conterreno_recepciones_compra' THEN 'COMPRAS'
        WHEN 'conterreno_facturas' THEN 'COMPRAS'
        WHEN 'kardex_transaccional' THEN 'KARDEX'
        ELSE upper(TG_TABLE_NAME)
    END;
    v_accion := TG_OP;
    IF TG_OP = 'UPDATE' AND
       COALESCE(v_anterior ->> 'estado', v_anterior ->> 'estado_devolucion', '') <>
       COALESCE(v_nuevo ->> 'estado', v_nuevo ->> 'estado_devolucion', '') THEN
        v_accion := 'ESTADO_ACTUALIZADO';
    END IF;
    v_resumen := CASE TG_TABLE_NAME
        WHEN 'conterreno_proyectos' THEN 'Obra: ' || COALESCE(v_nuevo ->> 'nombre', v_anterior ->> 'nombre', v_registro_id)
        WHEN 'conterreno_tareas' THEN 'Tarea: ' || COALESCE(v_nuevo ->> 'titulo', v_anterior ->> 'titulo', v_registro_id)
        WHEN 'conterreno_incidencias' THEN 'Incidencia: ' || COALESCE(v_nuevo ->> 'titulo', v_anterior ->> 'titulo', v_registro_id)
        WHEN 'marcajes_asistencia' THEN 'Registro de asistencia'
        WHEN 'prestamos' THEN 'Préstamo de herramienta'
        WHEN 'equipos_herramientas' THEN 'Herramienta: ' || COALESCE(v_nuevo ->> 'nombre', v_anterior ->> 'nombre', v_registro_id)
        WHEN 'conterreno_movimientos_materiales' THEN 'Movimiento de materiales: ' || COALESCE(v_nuevo ->> 'tipo', v_anterior ->> 'tipo', 'registrado')
        WHEN 'conterreno_pedidos_materiales' THEN 'Pedido de materiales'
        WHEN 'conterreno_ordenes_compra' THEN 'Orden de compra'
        WHEN 'conterreno_recepciones_compra' THEN 'Recepción de compra'
        WHEN 'conterreno_facturas' THEN 'Factura de proveedor'
        WHEN 'kardex_transaccional' THEN 'Movimiento de Kardex: ' || COALESCE(v_nuevo ->> 'codigo_operacion', v_anterior ->> 'codigo_operacion', 'registrado')
        ELSE TG_TABLE_NAME
    END;
    v_datos_anteriores := CASE TG_TABLE_NAME
        WHEN 'conterreno_proyectos' THEN jsonb_build_object(
            'activo', v_anterior -> 'activo', 'fecha_inicio', v_anterior -> 'fecha_inicio',
            'fecha_termino', v_anterior -> 'fecha_termino', 'dias_laborales', v_anterior -> 'dias_laborales'
        )
        WHEN 'conterreno_tareas' THEN jsonb_build_object(
            'estado', v_anterior -> 'estado', 'fecha_inicio', v_anterior -> 'fecha_inicio',
            'fecha_limite', v_anterior -> 'fecha_limite', 'restriccion', v_anterior -> 'restriccion'
        )
        WHEN 'conterreno_incidencias' THEN jsonb_build_object(
            'estado', v_anterior -> 'estado', 'prioridad', v_anterior -> 'prioridad'
        )
        WHEN 'marcajes_asistencia' THEN jsonb_build_object(
            'fecha_hora_entrada', v_anterior -> 'fecha_hora_entrada',
            'fecha_hora_salida', v_anterior -> 'fecha_hora_salida',
            'horas_ordinarias', v_anterior -> 'horas_ordinarias'
        )
        WHEN 'prestamos' THEN jsonb_build_object(
            'fecha_hora_salida', v_anterior -> 'fecha_hora_salida',
            'fecha_devolucion_prevista', v_anterior -> 'fecha_devolucion_prevista',
            'fecha_hora_devolucion', v_anterior -> 'fecha_hora_devolucion',
            'estado_devolucion', v_anterior -> 'estado_devolucion'
        )
        WHEN 'equipos_herramientas' THEN jsonb_build_object(
            'estado_fisico', v_anterior -> 'estado_fisico', 'disponible', v_anterior -> 'disponible'
        )
        WHEN 'conterreno_pedidos_materiales' THEN jsonb_build_object(
            'estado', v_anterior -> 'estado', 'urgencia', v_anterior -> 'urgencia'
        )
        WHEN 'conterreno_ordenes_compra' THEN jsonb_build_object('estado', v_anterior -> 'estado')
        WHEN 'conterreno_facturas' THEN jsonb_build_object('estado', v_anterior -> 'estado')
        ELSE NULL
    END;
    v_datos_nuevos := CASE TG_TABLE_NAME
        WHEN 'conterreno_proyectos' THEN jsonb_build_object(
            'activo', v_nuevo -> 'activo', 'fecha_inicio', v_nuevo -> 'fecha_inicio',
            'fecha_termino', v_nuevo -> 'fecha_termino', 'dias_laborales', v_nuevo -> 'dias_laborales'
        )
        WHEN 'conterreno_tareas' THEN jsonb_build_object(
            'estado', v_nuevo -> 'estado', 'fecha_inicio', v_nuevo -> 'fecha_inicio',
            'fecha_limite', v_nuevo -> 'fecha_limite', 'restriccion', v_nuevo -> 'restriccion'
        )
        WHEN 'conterreno_incidencias' THEN jsonb_build_object(
            'estado', v_nuevo -> 'estado', 'prioridad', v_nuevo -> 'prioridad'
        )
        WHEN 'marcajes_asistencia' THEN jsonb_build_object(
            'fecha_hora_entrada', v_nuevo -> 'fecha_hora_entrada',
            'fecha_hora_salida', v_nuevo -> 'fecha_hora_salida',
            'horas_ordinarias', v_nuevo -> 'horas_ordinarias'
        )
        WHEN 'prestamos' THEN jsonb_build_object(
            'fecha_hora_salida', v_nuevo -> 'fecha_hora_salida',
            'fecha_devolucion_prevista', v_nuevo -> 'fecha_devolucion_prevista',
            'fecha_hora_devolucion', v_nuevo -> 'fecha_hora_devolucion',
            'estado_devolucion', v_nuevo -> 'estado_devolucion'
        )
        WHEN 'equipos_herramientas' THEN jsonb_build_object(
            'estado_fisico', v_nuevo -> 'estado_fisico', 'disponible', v_nuevo -> 'disponible'
        )
        WHEN 'conterreno_pedidos_materiales' THEN jsonb_build_object(
            'estado', v_nuevo -> 'estado', 'urgencia', v_nuevo -> 'urgencia'
        )
        WHEN 'conterreno_ordenes_compra' THEN jsonb_build_object('estado', v_nuevo -> 'estado')
        WHEN 'conterreno_facturas' THEN jsonb_build_object('estado', v_nuevo -> 'estado')
        ELSE NULL
    END;

    INSERT INTO public.conterreno_historial_eventos (
        proyecto_id, entidad, registro_id, accion, actor_id,
        usuario_relacionado_id, resumen, datos_anteriores, datos_nuevos
    )
    VALUES (
        v_proyecto_id, v_entidad, v_registro_id, v_accion, v_actor_id,
        v_usuario_relacionado_id, v_resumen, v_datos_anteriores, v_datos_nuevos
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_historial_proyectos ON public.conterreno_proyectos;
CREATE TRIGGER trg_historial_proyectos
    AFTER INSERT OR UPDATE OR DELETE ON public.conterreno_proyectos
    FOR EACH ROW EXECUTE FUNCTION public.fn_conterreno_auditar_historial();
DROP TRIGGER IF EXISTS trg_historial_tareas ON public.conterreno_tareas;
CREATE TRIGGER trg_historial_tareas
    AFTER INSERT OR UPDATE OR DELETE ON public.conterreno_tareas
    FOR EACH ROW EXECUTE FUNCTION public.fn_conterreno_auditar_historial();
DROP TRIGGER IF EXISTS trg_historial_incidencias ON public.conterreno_incidencias;
CREATE TRIGGER trg_historial_incidencias
    AFTER INSERT OR UPDATE OR DELETE ON public.conterreno_incidencias
    FOR EACH ROW EXECUTE FUNCTION public.fn_conterreno_auditar_historial();
DROP TRIGGER IF EXISTS trg_historial_asistencia ON public.marcajes_asistencia;
CREATE TRIGGER trg_historial_asistencia
    AFTER INSERT OR UPDATE OR DELETE ON public.marcajes_asistencia
    FOR EACH ROW EXECUTE FUNCTION public.fn_conterreno_auditar_historial();
DROP TRIGGER IF EXISTS trg_historial_prestamos ON public.prestamos;
CREATE TRIGGER trg_historial_prestamos
    AFTER INSERT OR UPDATE OR DELETE ON public.prestamos
    FOR EACH ROW EXECUTE FUNCTION public.fn_conterreno_auditar_historial();
DROP TRIGGER IF EXISTS trg_historial_herramientas ON public.equipos_herramientas;
CREATE TRIGGER trg_historial_herramientas
    AFTER INSERT OR UPDATE OR DELETE ON public.equipos_herramientas
    FOR EACH ROW EXECUTE FUNCTION public.fn_conterreno_auditar_historial();
DROP TRIGGER IF EXISTS trg_historial_movimientos_materiales ON public.conterreno_movimientos_materiales;
CREATE TRIGGER trg_historial_movimientos_materiales
    AFTER INSERT OR UPDATE OR DELETE ON public.conterreno_movimientos_materiales
    FOR EACH ROW EXECUTE FUNCTION public.fn_conterreno_auditar_historial();
DROP TRIGGER IF EXISTS trg_historial_pedidos_materiales ON public.conterreno_pedidos_materiales;
CREATE TRIGGER trg_historial_pedidos_materiales
    AFTER INSERT OR UPDATE OR DELETE ON public.conterreno_pedidos_materiales
    FOR EACH ROW EXECUTE FUNCTION public.fn_conterreno_auditar_historial();
DROP TRIGGER IF EXISTS trg_historial_ordenes_compra ON public.conterreno_ordenes_compra;
CREATE TRIGGER trg_historial_ordenes_compra
    AFTER INSERT OR UPDATE OR DELETE ON public.conterreno_ordenes_compra
    FOR EACH ROW EXECUTE FUNCTION public.fn_conterreno_auditar_historial();
DROP TRIGGER IF EXISTS trg_historial_recepciones_compra ON public.conterreno_recepciones_compra;
CREATE TRIGGER trg_historial_recepciones_compra
    AFTER INSERT OR UPDATE OR DELETE ON public.conterreno_recepciones_compra
    FOR EACH ROW EXECUTE FUNCTION public.fn_conterreno_auditar_historial();
DROP TRIGGER IF EXISTS trg_historial_facturas ON public.conterreno_facturas;
CREATE TRIGGER trg_historial_facturas
    AFTER INSERT OR UPDATE OR DELETE ON public.conterreno_facturas
    FOR EACH ROW EXECUTE FUNCTION public.fn_conterreno_auditar_historial();
DROP TRIGGER IF EXISTS trg_historial_kardex ON public.kardex_transaccional;
CREATE TRIGGER trg_historial_kardex
    AFTER INSERT ON public.kardex_transaccional
    FOR EACH ROW EXECUTE FUNCTION public.fn_conterreno_auditar_historial();

CREATE OR REPLACE FUNCTION public.fn_conterreno_consultar_historial(
    p_proyecto_id TEXT,
    p_desde DATE,
    p_hasta DATE
)
RETURNS TABLE (
    event_id TEXT,
    proyecto_id TEXT,
    proyecto_nombre TEXT,
    entidad TEXT,
    registro_id TEXT,
    accion TEXT,
    actor TEXT,
    usuario_relacionado TEXT,
    ocurrido_en TIMESTAMPTZ,
    resumen TEXT,
    datos_anteriores JSONB,
    datos_nuevos JSONB
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
BEGIN
    IF v_usuario IS NULL OR p_desde IS NULL OR p_hasta IS NULL
       OR p_desde > p_hasta OR p_hasta - p_desde > 30 THEN
        RAISE EXCEPTION 'Rango de historial no válido; selecciona hasta 31 días.';
    END IF;

    SELECT r.codigo_rol INTO v_rol
    FROM public.usuarios AS u
    JOIN public.roles AS r ON r.id_rol = u.id_rol
    WHERE u.id_usuario = v_usuario
      AND u.activo = TRUE
      AND u.bloqueado = FALSE
      AND r.activo = TRUE;
    IF v_rol IS NULL THEN
        RAISE EXCEPTION 'No tienes un perfil activo para consultar el historial.';
    END IF;

    v_admin := public.fn_conterreno_es_administrador();
    IF NOT v_admin AND (
        p_proyecto_id IS NULL
        OR NOT public.fn_conterreno_tiene_permiso(p_proyecto_id, 'HISTORIAL_CONSULTAR')
    ) THEN
        RAISE EXCEPTION 'No tienes permiso para consultar el historial de esta obra.';
    END IF;

    RETURN QUERY
    WITH eventos AS (
        SELECT h.id::TEXT AS event_id,
               h.proyecto_id,
               p.nombre::TEXT AS proyecto_nombre,
               h.entidad::TEXT AS entidad,
               h.registro_id,
               h.accion::TEXT AS accion,
               NULLIF(trim(ua.nombres || ' ' || ua.apellidos), '')::TEXT AS actor,
               NULLIF(trim(us.nombres || ' ' || us.apellidos), '')::TEXT AS usuario_relacionado,
               h.ocurrido_en,
               h.resumen,
               h.datos_anteriores,
               h.datos_nuevos
        FROM public.conterreno_historial_eventos AS h
        LEFT JOIN public.conterreno_proyectos AS p ON p.id = h.proyecto_id
        LEFT JOIN public.usuarios AS ua ON ua.id_usuario = h.actor_id
        LEFT JOIN public.usuarios AS us ON us.id_usuario = h.usuario_relacionado_id
        WHERE h.ocurrido_en >= (p_desde::TIMESTAMP AT TIME ZONE 'America/Santiago')
          AND h.ocurrido_en < ((p_hasta + 1)::TIMESTAMP AT TIME ZONE 'America/Santiago')
          AND (p_proyecto_id IS NULL OR h.proyecto_id = p_proyecto_id)
          AND h.entidad <> 'ASISTENCIA'
          AND (
              v_admin
              OR (v_rol = 'JEFE_OBRA' AND h.entidad IN (
                  'TAREAS', 'INCIDENCIAS'
              ))
              OR (v_rol = 'BODEGUERO' AND h.entidad IN (
                  'PRESTAMOS', 'HERRAMIENTAS', 'MATERIALES', 'PEDIDOS',
                  'COMPRAS', 'KARDEX'
              ))
              OR (v_rol = 'OPERARIO_MAESTRO' AND (
                  h.actor_id = v_usuario OR h.usuario_relacionado_id = v_usuario
              ))
          )
    ),
    marcas AS (
        SELECT ('asistencia-' || m.id_marcaje::TEXT || '-entrada')::TEXT AS event_id,
               m.proyecto_id,
               p.nombre::TEXT AS proyecto_nombre,
               'ASISTENCIA'::TEXT AS entidad,
               m.id_marcaje::TEXT AS registro_id,
               'ENTRADA'::TEXT AS accion,
               NULLIF(trim(u.nombres || ' ' || u.apellidos), '')::TEXT AS actor,
               NULLIF(trim(u.nombres || ' ' || u.apellidos), '')::TEXT AS usuario_relacionado,
               m.fecha_hora_entrada AS ocurrido_en,
               'Entrada registrada'::TEXT AS resumen,
               NULL::JSONB AS datos_anteriores,
               jsonb_build_object('fecha_hora_entrada', m.fecha_hora_entrada) AS datos_nuevos
        FROM public.marcajes_asistencia AS m
        JOIN public.conterreno_proyectos AS p ON p.id = m.proyecto_id
        JOIN public.usuarios AS u ON u.id_usuario = m.id_usuario
        WHERE (m.fecha_hora_entrada AT TIME ZONE 'America/Santiago')::DATE
                  BETWEEN p_desde AND p_hasta
          AND (p_proyecto_id IS NULL OR m.proyecto_id = p_proyecto_id)
          AND (v_admin OR v_rol = 'JEFE_OBRA' OR
               (v_rol = 'OPERARIO_MAESTRO' AND m.id_usuario = v_usuario))
        UNION ALL
        SELECT ('asistencia-' || m.id_marcaje::TEXT || '-salida')::TEXT,
               m.proyecto_id,
               p.nombre::TEXT,
               'ASISTENCIA'::TEXT,
               m.id_marcaje::TEXT,
               'SALIDA'::TEXT,
               NULLIF(trim(u.nombres || ' ' || u.apellidos), '')::TEXT,
               NULLIF(trim(u.nombres || ' ' || u.apellidos), '')::TEXT,
               m.fecha_hora_salida,
               'Salida registrada'::TEXT,
               jsonb_build_object('fecha_hora_entrada', m.fecha_hora_entrada),
               jsonb_build_object('fecha_hora_salida', m.fecha_hora_salida,
                                  'horas_ordinarias', m.horas_ordinarias)
        FROM public.marcajes_asistencia AS m
        JOIN public.conterreno_proyectos AS p ON p.id = m.proyecto_id
        JOIN public.usuarios AS u ON u.id_usuario = m.id_usuario
        WHERE m.fecha_hora_salida IS NOT NULL
          AND (m.fecha_hora_salida AT TIME ZONE 'America/Santiago')::DATE
                  BETWEEN p_desde AND p_hasta
          AND (p_proyecto_id IS NULL OR m.proyecto_id = p_proyecto_id)
          AND (v_admin OR v_rol = 'JEFE_OBRA' OR
               (v_rol = 'OPERARIO_MAESTRO' AND m.id_usuario = v_usuario))
    ),
    sin_marcaje AS (
        SELECT ('sin-marcaje-' || up.proyecto_id || '-' || up.usuario_auth_id::TEXT ||
                '-' || dias.fecha::DATE::TEXT)::TEXT AS event_id,
               up.proyecto_id,
               p.nombre::TEXT AS proyecto_nombre,
               'ASISTENCIA'::TEXT AS entidad,
               up.usuario_auth_id::TEXT AS registro_id,
               'SIN_MARCAJE'::TEXT AS accion,
               NULL::TEXT AS actor,
               NULLIF(trim(u.nombres || ' ' || u.apellidos), '')::TEXT AS usuario_relacionado,
               ((dias.fecha::DATE + p.hora_inicio_jornada) AT TIME ZONE 'America/Santiago') AS ocurrido_en,
               'Sin marcaje en una jornada programada; no implica ausencia injustificada.'::TEXT AS resumen,
               NULL::JSONB AS datos_anteriores,
               jsonb_build_object('fecha', dias.fecha::DATE,
                                  'hora_inicio_programada', p.hora_inicio_jornada,
                                  'hora_termino_programada', p.hora_termino_jornada) AS datos_nuevos
        FROM public.conterreno_usuarios_proyectos AS up
        JOIN public.conterreno_proyectos AS p ON p.id = up.proyecto_id
        JOIN public.usuarios AS u ON u.id_usuario = up.usuario_auth_id
        CROSS JOIN LATERAL generate_series(
            GREATEST(p_desde, COALESCE(p.fecha_inicio, p_desde))::TIMESTAMP,
            LEAST(
                p_hasta,
                COALESCE(p.fecha_termino, p_hasta),
                (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::DATE
            )::TIMESTAMP,
            INTERVAL '1 day'
        ) AS dias(fecha)
        WHERE p.dias_laborales IS NOT NULL
          AND up.activo = TRUE
          AND u.activo = TRUE
          AND p.activo = TRUE
          AND extract(ISODOW FROM dias.fecha)::SMALLINT = ANY(p.dias_laborales)
          AND (
              dias.fecha::DATE < (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::DATE
              OR (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::TIME >= p.hora_termino_jornada
          )
          AND (p_proyecto_id IS NULL OR up.proyecto_id = p_proyecto_id)
          AND (v_admin OR v_rol = 'JEFE_OBRA' OR
               (v_rol = 'OPERARIO_MAESTRO' AND up.usuario_auth_id = v_usuario))
          AND NOT EXISTS (
              SELECT 1
              FROM public.marcajes_asistencia AS m
              WHERE m.proyecto_id = up.proyecto_id
                AND m.id_usuario = up.usuario_auth_id
                AND (m.fecha_hora_entrada AT TIME ZONE 'America/Santiago')::DATE = dias.fecha::DATE
          )
    ),
    auditoria_admin AS (
        SELECT ('auditoria-' || a.id_auditoria::TEXT)::TEXT AS event_id,
               COALESCE(a.datos_nuevos ->> 'proyecto_id',
                        a.datos_anteriores ->> 'proyecto_id') AS proyecto_id,
               p.nombre::TEXT AS proyecto_nombre,
               'AUDITORIA'::TEXT AS entidad,
               a.tabla_afectada::TEXT AS registro_id,
               a.operacion::TEXT AS accion,
               NULLIF(trim(ua.nombres || ' ' || ua.apellidos), '')::TEXT AS actor,
               NULLIF(trim(us.nombres || ' ' || us.apellidos), '')::TEXT AS usuario_relacionado,
               a.fecha_hora AS ocurrido_en,
               ('Cambio administrativo: ' || a.tabla_afectada || ' · ' || a.operacion)::TEXT AS resumen,
               NULL::JSONB AS datos_anteriores,
               NULL::JSONB AS datos_nuevos
        FROM public.auditoria_usuarios AS a
        LEFT JOIN public.conterreno_proyectos AS p
          ON p.id = COALESCE(a.datos_nuevos ->> 'proyecto_id',
                             a.datos_anteriores ->> 'proyecto_id')
        LEFT JOIN public.usuarios AS ua ON ua.id_usuario = a.id_usuario_ejecutor
        LEFT JOIN public.usuarios AS us ON us.id_usuario = a.id_usuario_afectado
        WHERE v_admin
          AND a.fecha_hora >= (p_desde::TIMESTAMP AT TIME ZONE 'America/Santiago')
          AND a.fecha_hora < ((p_hasta + 1)::TIMESTAMP AT TIME ZONE 'America/Santiago')
          AND (p_proyecto_id IS NULL OR
               COALESCE(a.datos_nuevos ->> 'proyecto_id',
                        a.datos_anteriores ->> 'proyecto_id') = p_proyecto_id)
    )
    SELECT historial.*
    FROM (
        SELECT * FROM eventos
        UNION ALL
        SELECT * FROM marcas
        UNION ALL
        SELECT * FROM sin_marcaje
        UNION ALL
        SELECT * FROM auditoria_admin
    ) AS historial
    ORDER BY historial.ocurrido_en DESC
    LIMIT 1000;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_conterreno_consultar_historial(TEXT, DATE, DATE)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_consultar_historial(TEXT, DATE, DATE)
    TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_conterreno_admin_crear_proyecto_con_plazo(
    p_id TEXT,
    p_nombre TEXT,
    p_fecha_inicio DATE,
    p_fecha_termino DATE,
    p_dias_laborales SMALLINT[],
    p_hora_inicio TIME,
    p_hora_termino TIME
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT public.fn_conterreno_es_administrador() THEN
        RAISE EXCEPTION 'Solo el Administrador del sistema puede crear obras.';
    END IF;
    IF p_id IS NULL OR p_id !~ '^[a-z0-9][a-z0-9_-]{1,39}$'
       OR p_nombre IS NULL OR length(trim(p_nombre)) < 3 THEN
        RAISE EXCEPTION 'Identificador o nombre de obra no válido.';
    END IF;
    IF p_fecha_inicio IS NOT NULL AND p_fecha_termino IS NOT NULL
       AND p_fecha_termino < p_fecha_inicio THEN
        RAISE EXCEPTION 'El término de la obra no puede ser anterior a su inicio.';
    END IF;
    IF (p_dias_laborales IS NULL) <> (p_hora_inicio IS NULL)
       OR (p_dias_laborales IS NULL) <> (p_hora_termino IS NULL) THEN
        RAISE EXCEPTION 'Configura juntos los días y horarios de jornada, o déjalos todos vacíos.';
    END IF;
    IF p_dias_laborales IS NOT NULL AND (
        cardinality(p_dias_laborales) NOT BETWEEN 1 AND 7
        OR EXISTS (SELECT 1 FROM unnest(p_dias_laborales) AS dia WHERE dia < 1 OR dia > 7)
        OR cardinality(p_dias_laborales) <>
           (SELECT count(DISTINCT dia) FROM unnest(p_dias_laborales) AS dia)
        OR p_hora_termino <= p_hora_inicio
    ) THEN
        RAISE EXCEPTION 'Los días u horario de la jornada no son válidos.';
    END IF;

    INSERT INTO public.conterreno_proyectos (
        id, nombre, fecha_inicio, fecha_termino, dias_laborales,
        hora_inicio_jornada, hora_termino_jornada
    )
    VALUES (
        lower(trim(p_id)), trim(p_nombre), p_fecha_inicio, p_fecha_termino,
        p_dias_laborales, p_hora_inicio, p_hora_termino
    );
    RETURN lower(trim(p_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_conterreno_admin_actualizar_plazo_proyecto(
    p_id TEXT,
    p_fecha_inicio DATE,
    p_fecha_termino DATE,
    p_dias_laborales SMALLINT[],
    p_hora_inicio TIME,
    p_hora_termino TIME
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT public.fn_conterreno_es_administrador() THEN
        RAISE EXCEPTION 'Solo Administración puede configurar la vigencia y jornada de una obra.';
    END IF;
    IF p_fecha_inicio IS NOT NULL AND p_fecha_termino IS NOT NULL
       AND p_fecha_termino < p_fecha_inicio THEN
        RAISE EXCEPTION 'El término de la obra no puede ser anterior a su inicio.';
    END IF;
    IF (p_dias_laborales IS NULL) <> (p_hora_inicio IS NULL)
       OR (p_dias_laborales IS NULL) <> (p_hora_termino IS NULL) THEN
        RAISE EXCEPTION 'Configura juntos los días y horarios de jornada, o déjalos todos vacíos.';
    END IF;
    IF p_dias_laborales IS NOT NULL AND (
        cardinality(p_dias_laborales) NOT BETWEEN 1 AND 7
        OR EXISTS (SELECT 1 FROM unnest(p_dias_laborales) AS dia WHERE dia < 1 OR dia > 7)
        OR cardinality(p_dias_laborales) <>
           (SELECT count(DISTINCT dia) FROM unnest(p_dias_laborales) AS dia)
        OR p_hora_termino <= p_hora_inicio
    ) THEN
        RAISE EXCEPTION 'Los días u horario de la jornada no son válidos.';
    END IF;
    PERFORM 1 FROM public.conterreno_proyectos WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La obra solicitada no existe.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.conterreno_tareas AS t
        WHERE t.proyecto_id = p_id
          AND (
              (p_fecha_inicio IS NOT NULL AND (
                  t.fecha_inicio < p_fecha_inicio OR t.fecha_limite < p_fecha_inicio
              ))
              OR (p_fecha_termino IS NOT NULL AND (
                  t.fecha_inicio > p_fecha_termino OR t.fecha_limite > p_fecha_termino
              ))
          )
    ) THEN
        RAISE EXCEPTION 'Ajusta primero las fechas de las tareas que quedarían fuera de la vigencia de la obra.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.prestamos AS pr
        WHERE pr.proyecto_id = p_id
          AND pr.fecha_hora_devolucion IS NULL
          AND (
              (p_fecha_inicio IS NOT NULL AND pr.fecha_devolucion_prevista < p_fecha_inicio)
              OR (p_fecha_termino IS NOT NULL AND pr.fecha_devolucion_prevista > p_fecha_termino)
          )
    ) THEN
        RAISE EXCEPTION 'Ajusta primero los vencimientos de préstamos abiertos que excedan el término de la obra.';
    END IF;

    UPDATE public.conterreno_proyectos
    SET fecha_inicio = p_fecha_inicio,
        fecha_termino = p_fecha_termino,
        dias_laborales = p_dias_laborales,
        hora_inicio_jornada = p_hora_inicio,
        hora_termino_jornada = p_hora_termino
    WHERE id = p_id;
END;
$$;

DROP FUNCTION IF EXISTS public.fn_conterreno_registrar_prestamo(TEXT, UUID, UUID);
CREATE FUNCTION public.fn_conterreno_registrar_prestamo(
    p_proyecto_id TEXT,
    p_id_equipo UUID,
    p_id_trabajador UUID,
    p_fecha_devolucion_prevista DATE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_id_prestamo UUID;
    v_fecha_termino DATE;
    v_hoy DATE := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::DATE;
BEGIN
    IF NOT public.fn_conterreno_tiene_permiso(p_proyecto_id, 'PRESTAMO_REGISTRAR') THEN
        RAISE EXCEPTION 'Solo el bodeguero asignado puede registrar el préstamo.';
    END IF;
    IF p_fecha_devolucion_prevista IS NULL
       OR p_fecha_devolucion_prevista < v_hoy THEN
        RAISE EXCEPTION 'Indica una fecha de devolución igual o posterior a hoy.';
    END IF;
    SELECT fecha_termino INTO v_fecha_termino
    FROM public.conterreno_proyectos
    WHERE id = p_proyecto_id;
    IF v_fecha_termino IS NOT NULL
       AND p_fecha_devolucion_prevista > v_fecha_termino THEN
        RAISE EXCEPTION 'La devolución prevista no puede exceder el término de la obra.';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM public.conterreno_usuarios_proyectos AS up
        JOIN public.usuarios AS u ON u.id_usuario = up.usuario_auth_id
        JOIN public.roles AS r ON r.id_rol = u.id_rol
        WHERE up.proyecto_id = p_proyecto_id
          AND up.usuario_auth_id = p_id_trabajador
          AND up.activo = TRUE
          AND u.activo = TRUE
          AND u.bloqueado = FALSE
          AND r.codigo_rol = 'OPERARIO_MAESTRO'
          AND r.activo = TRUE
    ) THEN
        RAISE EXCEPTION 'El trabajador no tiene una asignación activa en esta obra.';
    END IF;

    UPDATE public.equipos_herramientas
    SET disponible = FALSE
    WHERE id_equipo = p_id_equipo
      AND proyecto_id = p_proyecto_id
      AND activo = TRUE
      AND disponible = TRUE
      AND estado_fisico = 'OPTIMO';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La herramienta no existe, no está disponible o requiere revisión.';
    END IF;

    INSERT INTO public.prestamos (
        proyecto_id, id_equipo, id_trabajador, id_bodeguero,
        fecha_devolucion_prevista
    )
    VALUES (
        p_proyecto_id, p_id_equipo, p_id_trabajador, auth.uid(),
        p_fecha_devolucion_prevista
    )
    RETURNING id_prestamo INTO v_id_prestamo;

    INSERT INTO public.kardex_transaccional (
        modulo, proyecto_id, codigo_operacion, id_usuario_ejecutor,
        id_registro_referencia, payload_jsonb
    )
    VALUES (
        'BODEGA_IOT', p_proyecto_id, 'PRESTAMO_REGISTRADO', auth.uid(),
        v_id_prestamo::TEXT,
        jsonb_build_object(
            'id_prestamo', v_id_prestamo,
            'id_equipo', p_id_equipo,
            'id_trabajador', p_id_trabajador,
            'fecha_devolucion_prevista', p_fecha_devolucion_prevista
        )
    );
    RETURN v_id_prestamo;
END;
$$;

GRANT INSERT (fecha_inicio, fecha_limite)
    ON public.conterreno_tareas TO authenticated;

REVOKE ALL ON FUNCTION public.fn_conterreno_consultar_historial(TEXT, DATE, DATE)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_conterreno_admin_crear_proyecto_con_plazo(
    TEXT, TEXT, DATE, DATE, SMALLINT[], TIME, TIME
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_conterreno_admin_actualizar_plazo_proyecto(
    TEXT, DATE, DATE, SMALLINT[], TIME, TIME
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_conterreno_registrar_prestamo(
    TEXT, UUID, UUID, DATE
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_admin_crear_proyecto_con_plazo(
    TEXT, TEXT, DATE, DATE, SMALLINT[], TIME, TIME
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_admin_actualizar_plazo_proyecto(
    TEXT, DATE, DATE, SMALLINT[], TIME, TIME
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_registrar_prestamo(
    TEXT, UUID, UUID, DATE
) TO authenticated;

COMMIT;
