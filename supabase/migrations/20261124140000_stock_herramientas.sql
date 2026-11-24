BEGIN;

CREATE OR REPLACE FUNCTION public.fn_conterreno_registrar_stock_herramientas(
    p_proyecto_id TEXT,
    p_nombre TEXT,
    p_descripcion TEXT,
    p_cantidad INTEGER,
    p_es_prueba BOOLEAN DEFAULT FALSE,
    p_codigo_base TEXT DEFAULT NULL,
    p_serie_base TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_stamp TEXT;
    v_lote TEXT;
    v_prefijo TEXT;
    v_codigo TEXT;
    v_serie TEXT;
    v_index INTEGER;
    v_id_equipo UUID;
BEGIN
    IF NOT public.fn_conterreno_tiene_permiso(p_proyecto_id, 'HERRAMIENTA_CREAR') THEN
        RAISE EXCEPTION 'No tienes permiso para registrar herramientas en esta obra.';
    END IF;
    IF p_nombre IS NULL OR length(trim(p_nombre)) < 2 THEN
        RAISE EXCEPTION 'Indica el nombre del modelo de herramienta.';
    END IF;
    IF p_cantidad IS NULL OR p_cantidad < 1 OR p_cantidad > 100 THEN
        RAISE EXCEPTION 'La cantidad debe estar entre 1 y 100 unidades.';
    END IF;

    v_stamp := upper(to_char(CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago', 'YYMMDD-HH24MISS'));
    v_lote := replace(substr(gen_random_uuid()::TEXT, 1, 8), '-', '');
    v_prefijo := CASE
        WHEN COALESCE(p_es_prueba, FALSE) THEN 'PRUEBA-'
        WHEN nullif(trim(COALESCE(p_codigo_base, '')), '') IS NOT NULL
            THEN upper(trim(p_codigo_base))
        ELSE 'HERR-'
    END;
    IF nullif(trim(COALESCE(p_codigo_base, '')), '') IS NULL THEN
        v_prefijo := v_prefijo || '-' || v_stamp || '-' || v_lote;
    END IF;

    FOR v_index IN 1..p_cantidad LOOP
        IF p_cantidad = 1 AND nullif(trim(COALESCE(p_codigo_base, '')), '') IS NOT NULL THEN
            v_codigo := upper(trim(p_codigo_base));
        ELSE
            v_codigo := v_prefijo || '-' || lpad(v_index::TEXT, 3, '0');
        END IF;
        IF p_cantidad = 1 AND nullif(trim(COALESCE(p_serie_base, '')), '') IS NOT NULL THEN
            v_serie := trim(p_serie_base);
        ELSE
            v_serie := CASE
                WHEN nullif(trim(COALESCE(p_serie_base, '')), '') IS NOT NULL
                    THEN trim(p_serie_base) || '-' || lpad(v_index::TEXT, 3, '0')
                ELSE v_prefijo || '-SN-' || lpad(v_index::TEXT, 3, '0')
            END;
        END IF;

        INSERT INTO public.equipos_herramientas (
            proyecto_id,
            codigo_tag_iot,
            numero_serie,
            nombre,
            descripcion,
            estado_fisico,
            disponible,
            activo
        )
        VALUES (
            p_proyecto_id,
            v_codigo,
            v_serie,
            trim(p_nombre),
            NULLIF(trim(COALESCE(p_descripcion, '')), ''),
            'OPTIMO',
            TRUE,
            TRUE
        )
        RETURNING id_equipo INTO v_id_equipo;

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
            'HERRAMIENTA_STOCK_REGISTRADO',
            auth.uid(),
            v_id_equipo::TEXT,
            jsonb_build_object(
                'id_equipo', v_id_equipo,
                'tag', v_codigo,
                'lote_cantidad', p_cantidad,
                'es_prueba', COALESCE(p_es_prueba, FALSE)
            )
        );
    END LOOP;

    RETURN p_cantidad;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_conterreno_registrar_stock_herramientas(
    TEXT, TEXT, TEXT, INTEGER, BOOLEAN, TEXT, TEXT
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.fn_conterreno_registrar_stock_herramientas(
    TEXT, TEXT, TEXT, INTEGER, BOOLEAN, TEXT, TEXT
) TO authenticated;

COMMIT;
