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
        ('conterreno_pedidos_materiales'),
        ('conterreno_proveedores'),
        ('conterreno_ordenes_compra'),
        ('conterreno_recepciones_compra'),
        ('conterreno_facturas'),
        ('conterreno_auth_intentos'),
        ('conterreno_historial_eventos')
),
required_functions(signature) AS (
    VALUES
        ('public.fn_conterreno_es_administrador()'),
        ('public.fn_conterreno_es_miembro(text)'),
        ('public.fn_conterreno_tiene_permiso(text,text)'),
        ('public.fn_conterreno_admin_asignar_acceso(uuid,text,text,text,text,text,text)'),
        ('public.fn_conterreno_operario_solicitar_materiales(text,text,text,jsonb)'),
        ('public.fn_conterreno_bodeguero_procesar_pedido(text,uuid,text,text)'),
        ('public.fn_conterreno_listar_responsables(text,boolean)'),
        ('public.fn_conterreno_marcar_asistencia(text,text)'),
        ('public.fn_conterreno_gestionar_proveedor(text,text,text,text,text)'),
        ('public.fn_conterreno_crear_orden_compra(text,uuid,text,jsonb,numeric)'),
        ('public.fn_conterreno_listar_proveedores(text)'),
        ('public.fn_auditar_cambios_tabla_usuarios()'),
        ('public.fn_conterreno_dias_laborales_validos(smallint[])'),
        ('public.fn_conterreno_registrar_fallo_login(text,text)'),
        ('public.fn_conterreno_consultar_historial(text,date,date)'),
        ('public.fn_conterreno_admin_crear_proyecto_con_plazo(text,text,date,date,smallint[],time,time)'),
        ('public.fn_conterreno_admin_actualizar_plazo_proyecto(text,date,date,smallint[],time,time)'),
        ('public.fn_conterreno_registrar_prestamo(text,uuid,uuid,date)'),
        ('public.fn_conterreno_consultar_asistencia_mensual(text,date)'),
        ('public.fn_conterreno_crear_herramienta(text,text,text,text,text)'),
        ('public.fn_conterreno_actualizar_herramienta(text,uuid,text,text,text)'),
        ('public.fn_conterreno_retirar_herramienta(text,uuid,text)'),
        ('public.fn_conterreno_registrar_stock_herramientas(text,text,text,integer,boolean,text,text)'),
        ('public.fn_conterreno_confirmar_prestamo(uuid,text,text)'),
        ('public.fn_conterreno_registrar_devolucion(uuid,text,text,text)'),
        ('public.fn_calcular_hash_kardex(jsonb)')
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
        'function definition',
        'fn_conterreno_consultar_asistencia_mensual text output casts',
        EXISTS (
            SELECT 1
            FROM pg_proc AS p
            WHERE p.oid = to_regprocedure(
                'public.fn_conterreno_consultar_asistencia_mensual(text,date)'
            )
              AND position(
                  'r.proyecto_nombre::text' IN lower(pg_get_functiondef(p.oid))
              ) > 0
              AND position(
                  'r.codigo_rol::text' IN lower(pg_get_functiondef(p.oid))
              ) > 0
        )
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
        'permission',
        r.codigo_rol || ':HISTORIAL_CONSULTAR',
        EXISTS (
            SELECT 1
            FROM public.rol_permisos AS rp
            JOIN public.permisos AS p ON p.id_permiso = rp.id_permiso
            WHERE rp.id_rol = r.id_rol
              AND p.codigo_permiso = 'HISTORIAL_CONSULTAR'
        )
    FROM public.roles AS r
    WHERE r.codigo_rol IN (
        'ADMIN_GENERAL', 'JEFE_OBRA', 'BODEGUERO', 'OPERARIO_MAESTRO'
    )
    UNION ALL
    SELECT
        'permission',
        r.codigo_rol || ':ASISTENCIA_CONSULTAR',
        EXISTS (
            SELECT 1
            FROM public.rol_permisos AS rp
            JOIN public.permisos AS p ON p.id_permiso = rp.id_permiso
            WHERE rp.id_rol = r.id_rol
              AND p.codigo_permiso = 'ASISTENCIA_CONSULTAR'
        )
    FROM public.roles AS r
    WHERE r.codigo_rol IN ('ADMIN_GENERAL', 'JEFE_OBRA')
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
        ('conterreno_stock_materiales'),
        ('conterreno_proveedores'),
        ('conterreno_ordenes_compra'),
        ('conterreno_recepciones_compra'),
        ('conterreno_facturas'),
        ('conterreno_auth_intentos'),
        ('conterreno_historial_eventos')
    ) AS r(table_name)
    UNION ALL
    SELECT
        'column',
        'conterreno_proyectos.fecha_inicio / fecha_termino / jornada',
        (
            SELECT count(*) = 5
            FROM pg_attribute AS a
            WHERE a.attrelid = to_regclass('public.conterreno_proyectos')
              AND a.attname IN (
                  'fecha_inicio', 'fecha_termino', 'dias_laborales',
                  'hora_inicio_jornada', 'hora_termino_jornada'
              )
              AND NOT a.attisdropped
        )
    UNION ALL
    SELECT
        'column',
        'conterreno_tareas.fecha_inicio / fecha_limite',
        (
            SELECT count(*) = 2
            FROM pg_attribute AS a
            WHERE a.attrelid = to_regclass('public.conterreno_tareas')
              AND a.attname IN ('fecha_inicio', 'fecha_limite')
              AND NOT a.attisdropped
        )
    UNION ALL
    SELECT
        'column',
        'prestamos.fecha_devolucion_prevista',
        EXISTS (
            SELECT 1
            FROM pg_attribute AS a
            WHERE a.attrelid = to_regclass('public.prestamos')
              AND a.attname = 'fecha_devolucion_prevista'
              AND NOT a.attisdropped
        )
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
        'column',
        'conterreno_tareas.responsable_id',
        EXISTS (
            SELECT 1
            FROM pg_attribute AS a
            WHERE a.attrelid = to_regclass('public.conterreno_tareas')
              AND a.attname = 'responsable_id'
              AND NOT a.attisdropped
        )
    UNION ALL
    SELECT
        'column',
        'conterreno_incidencias.responsable_id',
        EXISTS (
            SELECT 1
            FROM pg_attribute AS a
            WHERE a.attrelid = to_regclass('public.conterreno_incidencias')
              AND a.attname = 'responsable_id'
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
    UNION ALL
    SELECT
        'trigger',
        'trg_conterreno_tarea_validar_plazo',
        EXISTS (
            SELECT 1
            FROM pg_trigger AS t
            WHERE t.tgrelid = to_regclass('public.conterreno_tareas')
              AND t.tgname = 'trg_conterreno_tarea_validar_plazo'
              AND NOT t.tgisinternal
        )
    UNION ALL
    SELECT
        'trigger',
        'trg_historial_tareas',
        EXISTS (
            SELECT 1
            FROM pg_trigger AS t
            WHERE t.tgrelid = to_regclass('public.conterreno_tareas')
              AND t.tgname = 'trg_historial_tareas'
              AND NOT t.tgisinternal
        )
    UNION ALL
    SELECT
        'trigger',
        'trg_establecer_hash_kardex',
        EXISTS (
            SELECT 1
            FROM pg_trigger AS t
            WHERE t.tgrelid = to_regclass('public.kardex_transaccional')
              AND t.tgname = 'trg_establecer_hash_kardex'
              AND NOT t.tgisinternal
        )
    UNION ALL
    SELECT
        'extension',
        'pgcrypto',
        EXISTS (
            SELECT 1
            FROM pg_extension
            WHERE extname = 'pgcrypto'
        )
    UNION ALL
    SELECT
        'function definition',
        'fn_calcular_hash_kardex uses extensions.digest',
        EXISTS (
            SELECT 1
            FROM pg_proc AS p
            WHERE p.oid = to_regprocedure(
                'public.fn_calcular_hash_kardex(jsonb)'
            )
              AND position(
                  'extensions.digest' IN lower(pg_get_functiondef(p.oid))
              ) > 0
        )
)
SELECT
    object_type,
    object_name,
    CASE WHEN is_present THEN 'OK' ELSE 'FALTA' END AS status
FROM checks
ORDER BY object_type, object_name;
