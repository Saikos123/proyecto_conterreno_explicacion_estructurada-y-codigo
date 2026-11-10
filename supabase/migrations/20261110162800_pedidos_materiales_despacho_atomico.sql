-- Conecta solicitudes de materiales con el stock y el Kardex en operaciones
-- transaccionales. El despacho es completo o se rechaza; no hay parciales.
BEGIN;

ALTER TABLE public.conterreno_pedidos_materiales
    ADD COLUMN IF NOT EXISTS motivo_resolucion TEXT,
    ADD COLUMN IF NOT EXISTS procesado_por UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS procesado_en TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS solicitante_nombre VARCHAR(200) NOT NULL DEFAULT '';

UPDATE public.conterreno_pedidos_materiales AS pedido
SET solicitante_nombre = pg_catalog.btrim(usuario.nombres || ' ' || usuario.apellidos)
FROM public.usuarios AS usuario
WHERE pedido.solicitado_por = usuario.id_usuario
  AND pedido.solicitante_nombre = '';

ALTER TABLE public.conterreno_pedidos_materiales
    DROP CONSTRAINT IF EXISTS conterreno_pedidos_materiales_urgencia_check;
ALTER TABLE public.conterreno_pedidos_materiales
    ADD CONSTRAINT conterreno_pedidos_materiales_urgencia_check
    CHECK (urgencia IN ('Urgente', 'Normal', 'Crítica'));

CREATE OR REPLACE FUNCTION public.fn_conterreno_operario_solicitar_materiales(
    p_proyecto_id TEXT,
    p_destino TEXT,
    p_urgencia TEXT,
    p_items JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_line JSONB;
    v_material_text TEXT;
    v_cantidad_text TEXT;
    v_cantidad NUMERIC;
    v_item RECORD;
    v_nombre_material TEXT;
    v_unidad_material TEXT;
    v_solicitante_nombre TEXT;
    v_items_sanitizados JSONB := '[]'::JSONB;
    v_id_pedido UUID;
BEGIN
    IF NOT public.fn_conterreno_tiene_permiso(p_proyecto_id, 'MATERIAL_SOLICITAR') THEN
        RAISE EXCEPTION 'No tienes permiso para solicitar materiales en esta obra.';
    END IF;
    IF p_destino IS NULL OR pg_catalog.length(pg_catalog.btrim(p_destino)) = 0
       OR pg_catalog.length(pg_catalog.btrim(p_destino)) > 150
       OR p_urgencia IS NULL OR p_urgencia NOT IN ('Urgente', 'Normal', 'Crítica')
       OR p_items IS NULL THEN
        RAISE EXCEPTION 'Destino, prioridad o lista de materiales no válida.';
    END IF;
    IF pg_catalog.jsonb_typeof(p_items) <> 'array' THEN
        RAISE EXCEPTION 'La lista de materiales debe tener formato de arreglo.';
    END IF;
    IF pg_catalog.jsonb_array_length(p_items) = 0
       OR pg_catalog.jsonb_array_length(p_items) > 50 THEN
        RAISE EXCEPTION 'El pedido debe contener entre 1 y 50 líneas de materiales.';
    END IF;
    SELECT pg_catalog.btrim(usuario.nombres || ' ' || usuario.apellidos)
    INTO v_solicitante_nombre
    FROM public.usuarios AS usuario
    WHERE usuario.id_usuario = auth.uid()
      AND usuario.activo = TRUE
      AND usuario.bloqueado = FALSE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se encontró un perfil activo para crear la solicitud.';
    END IF;

    FOR v_line IN SELECT value FROM pg_catalog.jsonb_array_elements(p_items)
    LOOP
        IF pg_catalog.jsonb_typeof(v_line) <> 'object' THEN
            RAISE EXCEPTION 'Cada línea del pedido debe ser un objeto de material.';
        END IF;
        v_material_text := v_line ->> 'material_id';
        v_cantidad_text := v_line ->> 'qty';
        IF v_material_text IS NULL
           OR v_material_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           OR v_cantidad_text IS NULL
           OR pg_catalog.length(v_cantidad_text) > 13
           OR v_cantidad_text !~ '^[0-9]+([.][0-9]{1,2})?$' THEN
            RAISE EXCEPTION 'La línea de material o su cantidad no es válida.';
        END IF;
        v_cantidad := v_cantidad_text::NUMERIC;
        IF v_cantidad <= 0 OR v_cantidad > 9999999999.99 THEN
            RAISE EXCEPTION 'La cantidad solicitada debe ser mayor que cero y válida.';
        END IF;
        IF NOT EXISTS (
            SELECT 1
            FROM public.conterreno_catalogo_materiales AS cm
            JOIN public.conterreno_stock_materiales AS sm
              ON sm.material_id = cm.id
            WHERE cm.id = v_material_text::UUID
              AND cm.activo = TRUE
              AND sm.proyecto_id = p_proyecto_id
        ) THEN
            RAISE EXCEPTION 'Un material solicitado no está activo o no pertenece al inventario de esta obra.';
        END IF;
    END LOOP;

    FOR v_item IN
        SELECT (linea.value ->> 'material_id')::UUID AS material_id,
               pg_catalog.sum((linea.value ->> 'qty')::NUMERIC) AS cantidad
        FROM pg_catalog.jsonb_array_elements(p_items) AS linea(value)
        GROUP BY (linea.value ->> 'material_id')::UUID
        ORDER BY (linea.value ->> 'material_id')::UUID
    LOOP
        IF v_item.cantidad > 9999999999.99 THEN
            RAISE EXCEPTION 'La cantidad total de una línea excede el máximo permitido.';
        END IF;
        SELECT cm.nombre, cm.unidad
        INTO v_nombre_material, v_unidad_material
        FROM public.conterreno_catalogo_materiales AS cm
        WHERE cm.id = v_item.material_id
          AND cm.activo = TRUE;
        v_items_sanitizados := v_items_sanitizados || pg_catalog.jsonb_build_array(
            pg_catalog.jsonb_build_object(
                'material_id', v_item.material_id,
                'name', v_nombre_material,
                'unit', v_unidad_material,
                'qty', v_item.cantidad
            )
        );
    END LOOP;

    INSERT INTO public.conterreno_pedidos_materiales (
        proyecto_id, destino, urgencia, items, solicitado_por,
        solicitante_nombre
    )
    VALUES (
        p_proyecto_id,
        pg_catalog.btrim(p_destino),
        p_urgencia,
        v_items_sanitizados,
        auth.uid(),
        v_solicitante_nombre
    )
    RETURNING id INTO v_id_pedido;

    RETURN v_id_pedido;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_conterreno_bodeguero_procesar_pedido(
    p_proyecto_id TEXT,
    p_pedido_id UUID,
    p_accion TEXT,
    p_motivo TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_pedido public.conterreno_pedidos_materiales%ROWTYPE;
    v_line JSONB;
    v_material_text TEXT;
    v_cantidad_text TEXT;
    v_cantidad NUMERIC;
    v_item RECORD;
    v_stock NUMERIC(12, 2);
    v_nombre TEXT;
    v_unidad TEXT;
    v_items_despachados JSONB := '[]'::JSONB;
    v_motivo TEXT;
BEGIN
    IF NOT public.fn_conterreno_tiene_permiso(
        p_proyecto_id, 'MATERIAL_PEDIDO_GESTIONAR'
    ) THEN
        RAISE EXCEPTION 'No tienes permiso para gestionar pedidos de esta obra.';
    END IF;
    IF p_accion IS NULL OR p_accion NOT IN ('DESPACHAR', 'RECHAZAR') THEN
        RAISE EXCEPTION 'La acción debe ser DESPACHAR o RECHAZAR.';
    END IF;
    IF p_accion = 'RECHAZAR'
       AND (p_motivo IS NULL
            OR pg_catalog.length(pg_catalog.btrim(p_motivo)) < 3
            OR pg_catalog.length(pg_catalog.btrim(p_motivo)) > 500) THEN
        RAISE EXCEPTION 'Indica un motivo de entre 3 y 500 caracteres para rechazar el pedido.';
    END IF;

    SELECT *
    INTO v_pedido
    FROM public.conterreno_pedidos_materiales
    WHERE id = p_pedido_id
      AND proyecto_id = p_proyecto_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se encontró el pedido en esta obra.';
    END IF;
    IF v_pedido.estado <> 'Pendiente' THEN
        RAISE EXCEPTION 'El pedido ya fue procesado y no puede despacharse o rechazarse otra vez.';
    END IF;

    IF p_accion = 'RECHAZAR' THEN
        v_motivo := pg_catalog.btrim(p_motivo);
        UPDATE public.conterreno_pedidos_materiales
        SET estado = 'Rechazado',
            motivo_resolucion = v_motivo,
            procesado_por = auth.uid(),
            procesado_en = CURRENT_TIMESTAMP
        WHERE id = p_pedido_id;

        INSERT INTO public.kardex_transaccional (
            modulo, proyecto_id, codigo_operacion, id_usuario_ejecutor,
            id_registro_referencia, payload_jsonb
        )
        VALUES (
            'BODEGA_MATERIALES', p_proyecto_id, 'PEDIDO_MATERIAL_RECHAZADO',
            auth.uid(), p_pedido_id::TEXT,
            pg_catalog.jsonb_build_object(
                'pedido_id', p_pedido_id,
                'motivo', v_motivo
            )
        );
        RETURN;
    END IF;

    IF pg_catalog.jsonb_typeof(v_pedido.items) <> 'array' THEN
        RAISE EXCEPTION 'El pedido no contiene una lista de materiales válida.';
    END IF;
    IF pg_catalog.jsonb_array_length(v_pedido.items) = 0 THEN
        RAISE EXCEPTION 'El pedido no contiene líneas de materiales válidas.';
    END IF;
    FOR v_line IN SELECT value FROM pg_catalog.jsonb_array_elements(v_pedido.items)
    LOOP
        IF pg_catalog.jsonb_typeof(v_line) <> 'object' THEN
            RAISE EXCEPTION 'El pedido contiene una línea de material no válida.';
        END IF;
        v_material_text := v_line ->> 'material_id';
        v_cantidad_text := v_line ->> 'qty';
        IF v_material_text IS NULL
           OR v_material_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           OR v_cantidad_text IS NULL
           OR pg_catalog.length(v_cantidad_text) > 13
           OR v_cantidad_text !~ '^[0-9]+([.][0-9]{1,2})?$' THEN
            RAISE EXCEPTION 'El pedido contiene una cantidad o identificador inválido.';
        END IF;
        v_cantidad := v_cantidad_text::NUMERIC;
        IF v_cantidad <= 0 OR v_cantidad > 9999999999.99 THEN
            RAISE EXCEPTION 'El pedido contiene una cantidad fuera del rango permitido.';
        END IF;
    END LOOP;

    FOR v_item IN
        SELECT (linea.value ->> 'material_id')::UUID AS material_id,
               pg_catalog.sum((linea.value ->> 'qty')::NUMERIC) AS cantidad
        FROM pg_catalog.jsonb_array_elements(v_pedido.items) AS linea(value)
        GROUP BY (linea.value ->> 'material_id')::UUID
        ORDER BY (linea.value ->> 'material_id')::UUID
    LOOP
        IF v_item.cantidad > 9999999999.99 THEN
            RAISE EXCEPTION 'La cantidad total de una línea excede el máximo permitido.';
        END IF;
        SELECT sm.cantidad, cm.nombre, cm.unidad
        INTO v_stock, v_nombre, v_unidad
        FROM public.conterreno_stock_materiales AS sm
        JOIN public.conterreno_catalogo_materiales AS cm
          ON cm.id = sm.material_id AND cm.activo = TRUE
        WHERE sm.proyecto_id = p_proyecto_id
          AND sm.material_id = v_item.material_id
        FOR UPDATE OF sm;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'El material % ya no pertenece al inventario activo de esta obra.', v_item.material_id;
        END IF;
        IF v_stock < v_item.cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente para "%": disponible %, solicitado %.',
                v_nombre, v_stock, v_item.cantidad;
        END IF;

        UPDATE public.conterreno_stock_materiales
        SET cantidad = cantidad - v_item.cantidad,
            actualizado_por = auth.uid()
        WHERE proyecto_id = p_proyecto_id
          AND material_id = v_item.material_id;

        INSERT INTO public.conterreno_movimientos_materiales (
            proyecto_id, material_id, tipo, cantidad, motivo, referencia, ejecutado_por
        )
        VALUES (
            p_proyecto_id,
            v_item.material_id,
            'SALIDA',
            v_item.cantidad,
            'Despacho de solicitud ' || p_pedido_id::TEXT,
            p_pedido_id::TEXT,
            auth.uid()
        );
        v_items_despachados := v_items_despachados || pg_catalog.jsonb_build_array(
            pg_catalog.jsonb_build_object(
                'material_id', v_item.material_id,
                'nombre', v_nombre,
                'unidad', v_unidad,
                'cantidad', v_item.cantidad
            )
        );
    END LOOP;

    UPDATE public.conterreno_pedidos_materiales
    SET estado = 'Entregado',
        motivo_resolucion = NULL,
        procesado_por = auth.uid(),
        procesado_en = CURRENT_TIMESTAMP
    WHERE id = p_pedido_id;

    INSERT INTO public.kardex_transaccional (
        modulo, proyecto_id, codigo_operacion, id_usuario_ejecutor,
        id_registro_referencia, payload_jsonb
    )
    VALUES (
        'BODEGA_MATERIALES', p_proyecto_id, 'PEDIDO_MATERIAL_DESPACHADO',
        auth.uid(), p_pedido_id::TEXT,
        pg_catalog.jsonb_build_object(
            'pedido_id', p_pedido_id,
            'solicitado_por', v_pedido.solicitado_por,
            'destino', v_pedido.destino,
            'items', v_items_despachados
        )
    );
END;
$$;

REVOKE INSERT, UPDATE ON public.conterreno_pedidos_materiales
    FROM PUBLIC, anon, authenticated;
REVOKE INSERT (proyecto_id, destino, urgencia, estado, items),
       UPDATE (estado)
    ON public.conterreno_pedidos_materiales
    FROM PUBLIC, anon, authenticated;
GRANT INSERT (proyecto_id, destino, urgencia, items)
    ON public.conterreno_pedidos_materiales TO authenticated;

REVOKE ALL ON FUNCTION public.fn_conterreno_operario_solicitar_materiales(TEXT, TEXT, TEXT, JSONB)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_conterreno_bodeguero_procesar_pedido(TEXT, UUID, TEXT, TEXT)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_operario_solicitar_materiales(TEXT, TEXT, TEXT, JSONB)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_bodeguero_procesar_pedido(TEXT, UUID, TEXT, TEXT)
    TO authenticated;

COMMIT;
