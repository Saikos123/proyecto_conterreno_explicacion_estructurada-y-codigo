-- Lectura de verificacion para ejecutar en Supabase SQL Editor despues de
-- aplicar todas las migraciones. Cada fila debe informar "OK".
WITH required_tables(table_name) AS (
    VALUES
        ('roles'),
        ('permisos'),
        ('rol_permisos'),
        ('usuarios'),
        ('auditoria_usuarios'),
        ('conterreno_proyectos'),
        ('conterreno_usuarios_proyectos'),
        ('conterreno_solicitudes_acceso'),
        ('equipos_herramientas'),
        ('prestamos'),
        ('kardex_transaccional'),
        ('conterreno_catalogo_materiales'),
        ('conterreno_stock_materiales'),
        ('conterreno_movimientos_materiales'),
        ('conterreno_alertas_stock'),
        ('conterreno_incidencias'),
        ('conterreno_tareas'),
        ('conterreno_pedidos_materiales')
),
required_functions(signature) AS (
    VALUES
        ('public.fn_conterreno_es_administrador()'),
        ('public.fn_conterreno_es_miembro(text)'),
        ('public.fn_conterreno_tiene_permiso(text,text)'),
        ('public.fn_conterreno_admin_asignar_acceso(uuid,text,text,text,text,text,text)'),
        ('public.fn_conterreno_operario_solicitar_materiales(text,text,text,jsonb)'),
        ('public.fn_conterreno_bodeguero_procesar_pedido(text,uuid,text,text)'),
        ('public.fn_auditar_cambios_tabla_usuarios()')
),
required_roles(role_code) AS (
    VALUES
        ('ADMIN_GENERAL'),
        ('JEFE_OBRA'),
        ('BODEGUERO'),
        ('OPERARIO_MAESTRO')
),
checks AS (
    SELECT
        'table'::TEXT AS object_type,
        table_name AS object_name,
        to_regclass('public.' || table_name) IS NOT NULL AS is_present
    FROM required_tables
    UNION ALL
    SELECT
        'function',
        signature,
        to_regprocedure(signature) IS NOT NULL
    FROM required_functions
    UNION ALL
    SELECT
        'role',
        role_code,
        EXISTS (
            SELECT 1 FROM public.roles AS r
            WHERE r.codigo_rol = required_roles.role_code
              AND r.activo = TRUE
        )
    FROM required_roles
    UNION ALL
    SELECT
        'RLS',
        table_name,
        COALESCE((
            SELECT c.relrowsecurity
            FROM pg_class AS c
            WHERE c.oid = to_regclass('public.' || table_name)
        ), FALSE)
    FROM (VALUES
        ('usuarios'),
        ('auditoria_usuarios'),
        ('conterreno_solicitudes_acceso'),
        ('conterreno_proyectos'),
        ('conterreno_usuarios_proyectos'),
        ('kardex_transaccional'),
        ('conterreno_pedidos_materiales'),
        ('conterreno_stock_materiales')
    ) AS r(table_name)
    UNION ALL
    SELECT
        'column',
        'conterreno_pedidos_materiales.motivo_resolucion',
        EXISTS (
            SELECT 1
            FROM pg_attribute AS a
            WHERE a.attrelid = to_regclass('public.conterreno_pedidos_materiales')
              AND a.attname = 'motivo_resolucion'
              AND NOT a.attisdropped
        )
    UNION ALL
    SELECT
        'column',
        'conterreno_pedidos_materiales.procesado_en',
        EXISTS (
            SELECT 1
            FROM pg_attribute AS a
            WHERE a.attrelid = to_regclass('public.conterreno_pedidos_materiales')
              AND a.attname = 'procesado_en'
              AND NOT a.attisdropped
        )
    UNION ALL
    SELECT
        'column',
        'conterreno_pedidos_materiales.solicitante_nombre',
        EXISTS (
            SELECT 1
            FROM pg_attribute AS a
            WHERE a.attrelid = to_regclass('public.conterreno_pedidos_materiales')
              AND a.attname = 'solicitante_nombre'
              AND NOT a.attisdropped
        )
    UNION ALL
    SELECT
        'trigger',
        'trg_conterreno_registrar_solicitud_auth',
        EXISTS (
        SELECT 1
        FROM pg_trigger AS t
        WHERE t.tgrelid = 'auth.users'::regclass
          AND t.tgname = 'trg_conterreno_registrar_solicitud_auth'
          AND NOT t.tgisinternal
        )
    UNION ALL
    SELECT
        'trigger',
        'trg_auditoria_tabla_usuarios',
        EXISTS (
        SELECT 1
        FROM pg_trigger AS t
        WHERE t.tgrelid = to_regclass('public.usuarios')
          AND t.tgname = 'trg_auditoria_tabla_usuarios'
          AND NOT t.tgisinternal
        )
)
SELECT
    object_type,
    object_name,
    CASE WHEN is_present THEN 'OK' ELSE 'FALTA' END AS status
FROM checks
ORDER BY object_type, object_name;
