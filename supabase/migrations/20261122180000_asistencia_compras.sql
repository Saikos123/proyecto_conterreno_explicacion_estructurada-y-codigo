BEGIN;

-- Permisos complementarios
INSERT INTO public.permisos (codigo_permiso, modulo, descripcion)
VALUES
    ('COMPRA_CONSULTAR', 'COMPRAS', 'Consultar proveedores, órdenes, recepciones y facturas de una obra autorizada.'),
    ('COMPRA_GESTIONAR', 'COMPRAS', 'Crear proveedores, órdenes, recepciones y facturas autorizadas.')
ON CONFLICT (codigo_permiso) DO UPDATE
SET modulo = EXCLUDED.modulo,
    descripcion = EXCLUDED.descripcion;

INSERT INTO public.rol_permisos (id_rol, id_permiso)
SELECT r.id_rol, p.id_permiso
FROM public.roles r
JOIN public.permisos p ON (
    (r.codigo_rol = 'ADMIN_GENERAL' AND p.codigo_permiso IN ('COMPRA_CONSULTAR','COMPRA_GESTIONAR'))
    OR (r.codigo_rol = 'JEFE_OBRA' AND p.codigo_permiso = 'COMPRA_CONSULTAR')
    OR (r.codigo_rol = 'BODEGUERO' AND p.codigo_permiso IN ('COMPRA_CONSULTAR','COMPRA_GESTIONAR'))
)
ON CONFLICT (id_rol, id_permiso) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.conterreno_proveedores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rut VARCHAR(20) UNIQUE,
    nombre VARCHAR(200) NOT NULL,
    contacto VARCHAR(200),
    telefono VARCHAR(30),
    email VARCHAR(150),
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS public.conterreno_ordenes_compra (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    proyecto_id TEXT NOT NULL REFERENCES public.conterreno_proyectos(id) ON DELETE RESTRICT,
    proveedor_id UUID NOT NULL REFERENCES public.conterreno_proveedores(id) ON DELETE RESTRICT,
    folio VARCHAR(100),
    estado VARCHAR(20) NOT NULL DEFAULT 'BORRADOR'
        CHECK (estado IN ('BORRADOR','APROBADA','RECIBIDA','ANULADA')),
    items JSONB NOT NULL CHECK (jsonb_typeof(items) = 'array' AND jsonb_array_length(items) > 0),
    monto_estimado NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (monto_estimado >= 0),
    creado_por UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE RESTRICT,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS public.conterreno_recepciones_compra (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    orden_id UUID NOT NULL REFERENCES public.conterreno_ordenes_compra(id) ON DELETE RESTRICT,
    proyecto_id TEXT NOT NULL REFERENCES public.conterreno_proyectos(id) ON DELETE RESTRICT,
    items_recibidos JSONB NOT NULL CHECK (jsonb_typeof(items_recibidos) = 'array' AND jsonb_array_length(items_recibidos) > 0),
    recibido_por UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE RESTRICT,
    fecha_recepcion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    observacion TEXT
);

CREATE TABLE IF NOT EXISTS public.conterreno_facturas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    proyecto_id TEXT NOT NULL REFERENCES public.conterreno_proyectos(id) ON DELETE RESTRICT,
    proveedor_id UUID NOT NULL REFERENCES public.conterreno_proveedores(id) ON DELETE RESTRICT,
    orden_id UUID REFERENCES public.conterreno_ordenes_compra(id) ON DELETE RESTRICT,
    recepcion_id UUID REFERENCES public.conterreno_recepciones_compra(id) ON DELETE RESTRICT,
    numero_factura VARCHAR(100) NOT NULL,
    fecha_factura DATE NOT NULL,
    monto NUMERIC(14,2) NOT NULL CHECK (monto >= 0),
    moneda VARCHAR(10) NOT NULL DEFAULT 'CLP',
    estado VARCHAR(20) NOT NULL DEFAULT 'REGISTRADA'
        CHECK (estado IN ('REGISTRADA','OBSERVADA','PAGADA','ANULADA')),
    registrado_por UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE RESTRICT,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (proveedor_id, numero_factura)
);

CREATE INDEX IF NOT EXISTS idx_conterreno_ordenes_proyecto
    ON public.conterreno_ordenes_compra(proyecto_id, creado_en DESC);
CREATE INDEX IF NOT EXISTS idx_conterreno_recepciones_orden
    ON public.conterreno_recepciones_compra(orden_id);
CREATE INDEX IF NOT EXISTS idx_conterreno_facturas_proveedor
    ON public.conterreno_facturas(proveedor_id, fecha_factura DESC);

ALTER TABLE public.conterreno_proveedores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conterreno_ordenes_compra ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conterreno_recepciones_compra ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conterreno_facturas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS conterreno_compras_select ON public.conterreno_ordenes_compra;
CREATE POLICY conterreno_compras_select ON public.conterreno_ordenes_compra
    FOR SELECT TO authenticated
    USING (fn_conterreno_tiene_permiso(proyecto_id, 'COMPRA_CONSULTAR'));

DROP POLICY IF EXISTS conterreno_proveedores_select ON public.conterreno_proveedores;
CREATE POLICY conterreno_proveedores_select ON public.conterreno_proveedores
    FOR SELECT TO authenticated
    USING (activo = TRUE AND EXISTS (
        SELECT 1 FROM public.conterreno_ordenes_compra o
        WHERE o.proveedor_id = conterreno_proveedores.id
          AND fn_conterreno_tiene_permiso(o.proyecto_id, 'COMPRA_CONSULTAR')
    ));

DROP POLICY IF EXISTS conterreno_recepciones_select ON public.conterreno_recepciones_compra;
CREATE POLICY conterreno_recepciones_select ON public.conterreno_recepciones_compra
    FOR SELECT TO authenticated
    USING (fn_conterreno_tiene_permiso(proyecto_id, 'COMPRA_CONSULTAR'));

DROP POLICY IF EXISTS conterreno_facturas_select ON public.conterreno_facturas;
CREATE POLICY conterreno_facturas_select ON public.conterreno_facturas
    FOR SELECT TO authenticated
    USING (fn_conterreno_tiene_permiso(proyecto_id, 'COMPRA_CONSULTAR'));

CREATE OR REPLACE FUNCTION public.fn_conterreno_gestionar_proveedor(
    p_nombre TEXT,
    p_rut TEXT DEFAULT NULL,
    p_contacto TEXT DEFAULT NULL,
    p_telefono TEXT DEFAULT NULL,
    p_email TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_id UUID;
BEGIN
    IF NOT public.fn_conterreno_es_administrador() THEN
        RAISE EXCEPTION 'Solo Administración puede mantener proveedores.';
    END IF;
    IF p_nombre IS NULL OR length(trim(p_nombre)) < 2 THEN
        RAISE EXCEPTION 'El nombre del proveedor no es válido.';
    END IF;
    INSERT INTO public.conterreno_proveedores(rut,nombre,contacto,telefono,email)
    VALUES (nullif(trim(p_rut),''), trim(p_nombre), nullif(trim(p_contacto),''),
            nullif(trim(p_telefono),''), nullif(trim(p_email),''))
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_conterreno_crear_orden_compra(
    p_proyecto_id TEXT,
    p_proveedor_id UUID,
    p_folio TEXT,
    p_items JSONB,
    p_monto_estimado NUMERIC
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_id UUID;
BEGIN
    IF NOT public.fn_conterreno_tiene_permiso(p_proyecto_id, 'COMPRA_GESTIONAR') THEN
        RAISE EXCEPTION 'No tienes permiso para crear órdenes de compra en esta obra.';
    END IF;
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
       OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'La orden debe incluir al menos una línea.';
    END IF;
    IF p_monto_estimado IS NULL OR p_monto_estimado < 0 THEN
        RAISE EXCEPTION 'El monto estimado no es válido.';
    END IF;
    INSERT INTO public.conterreno_ordenes_compra(
        proyecto_id, proveedor_id, folio, estado, items, monto_estimado
    ) VALUES (
        p_proyecto_id, p_proveedor_id, nullif(trim(p_folio),''),
        'BORRADOR', p_items, p_monto_estimado
    ) RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_conterreno_gestionar_proveedor(TEXT,TEXT,TEXT,TEXT,TEXT)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_conterreno_crear_orden_compra(TEXT,UUID,TEXT,JSONB,NUMERIC)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_gestionar_proveedor(TEXT,TEXT,TEXT,TEXT,TEXT)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_crear_orden_compra(TEXT,UUID,TEXT,JSONB,NUMERIC)
    TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_conterreno_listar_proveedores(
    p_proyecto_id TEXT
)
RETURNS TABLE (
    id UUID,
    rut TEXT,
    nombre TEXT,
    contacto TEXT,
    telefono TEXT,
    email TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT public.fn_conterreno_tiene_permiso(p_proyecto_id, 'COMPRA_CONSULTAR') THEN
        RAISE EXCEPTION 'No tienes permiso para consultar proveedores en esta obra.';
    END IF;
    RETURN QUERY
    SELECT p.id,p.rut,p.nombre,p.contacto,p.telefono,p.email
    FROM public.conterreno_proveedores p
    WHERE p.activo = TRUE
    ORDER BY p.nombre;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_conterreno_listar_proveedores(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_listar_proveedores(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_conterreno_marcar_asistencia(
    p_proyecto_id TEXT,
    p_accion TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_marcaje UUID;
BEGIN
    IF NOT public.fn_conterreno_tiene_permiso(p_proyecto_id, 'ASISTENCIA_MARCAR_PROPIA') THEN
        RAISE EXCEPTION 'Solo el trabajador asignado puede marcar asistencia.';
    END IF;
    IF upper(trim(p_accion)) NOT IN ('ENTRADA','SALIDA') THEN
        RAISE EXCEPTION 'Acción de asistencia no válida.';
    END IF;

    IF upper(trim(p_accion)) = 'ENTRADA' THEN
        IF EXISTS (
            SELECT 1 FROM public.marcajes_asistencia
            WHERE id_usuario = auth.uid()
              AND proyecto_id = p_proyecto_id
              AND fecha_hora_salida IS NULL
        ) THEN
            RAISE EXCEPTION 'Ya existe una entrada abierta en esta obra.';
        END IF;
        INSERT INTO public.marcajes_asistencia(id_usuario, proyecto_id)
        VALUES (auth.uid(), p_proyecto_id)
        RETURNING id_marcaje INTO v_marcaje;
    ELSE
        UPDATE public.marcajes_asistencia
        SET fecha_hora_salida = CURRENT_TIMESTAMP,
            horas_ordinarias = ROUND(
                EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - fecha_hora_entrada)) / 3600,
                2
            )
        WHERE id_usuario = auth.uid()
          AND proyecto_id = p_proyecto_id
          AND fecha_hora_salida IS NULL
        RETURNING id_marcaje INTO v_marcaje;
        IF v_marcaje IS NULL THEN
            RAISE EXCEPTION 'No existe una entrada abierta para registrar salida.';
        END IF;
    END IF;
    RETURN v_marcaje;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_conterreno_marcar_asistencia(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_conterreno_marcar_asistencia(TEXT, TEXT) TO authenticated;

GRANT SELECT ON public.conterreno_proveedores, public.conterreno_ordenes_compra,
    public.conterreno_recepciones_compra, public.conterreno_facturas TO authenticated;

COMMIT;
