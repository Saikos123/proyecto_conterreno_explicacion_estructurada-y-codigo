-- Esquema inicial para una base Supabase nueva. La autenticación y las
-- contraseñas pertenecen a Supabase Auth; no ejecutar como migración sobre una
-- base que ya tenga datos sin preparar una migración específica.
BEGIN;

-- =============================================================================
-- 1. CONFIGURACIÓN INICIAL Y EXTENSIONES
-- =============================================================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Huso horario oficial de Chile (Ajuste automático de invierno/verano)
SET LOCAL timezone = 'America/Santiago';

-- =============================================================================
-- 2. MÓDULO IAM: ROLES, PERMISOS Y MATRIZ DE SEGREGACIÓN (SoD)
-- =============================================================================

CREATE TABLE IF NOT EXISTS roles (
    id_rol SERIAL PRIMARY KEY,
    codigo_rol VARCHAR(50) UNIQUE NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS permisos (
    id_permiso SERIAL PRIMARY KEY,
    codigo_permiso VARCHAR(100) UNIQUE NOT NULL,
    modulo VARCHAR(50) NOT NULL,
    descripcion TEXT NOT NULL,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Matriz Intermedia de Asignación Granular (Segregación Estricta)
CREATE TABLE IF NOT EXISTS rol_permisos (
    id_rol INT NOT NULL REFERENCES roles(id_rol) ON DELETE RESTRICT,
    id_permiso INT NOT NULL REFERENCES permisos(id_permiso) ON DELETE RESTRICT,
    asignado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_rol, id_permiso)
);

-- =============================================================================
-- 3. MÓDULO PERSONAL: USUARIOS (LEY N° 19.628 / CÓDIGO DEL TRABAJO)
-- =============================================================================
CREATE TABLE IF NOT EXISTS usuarios (
    id_usuario UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,

    -- Validar RUT chileno oficial o identificador de anonimización
    rut VARCHAR(12) UNIQUE NOT NULL
        CONSTRAINT chk_rut_formato CHECK (
            rut ~* '^[0-9]{1,2}\.[0-9]{3}\.[0-9]{3}-[0-9kK]{1}$' OR
            rut ~* '^[0-9]{7,8}-[0-9kK]{1}$' OR
            rut ~* '^ANON-[a-f0-9]{7,8}$'
        ),

    nombres VARCHAR(100) NOT NULL,
    apellidos VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL
        CONSTRAINT chk_email_formato CHECK (
            email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
        ),

    telefono VARCHAR(20),
    cargo_contrato VARCHAR(100) NOT NULL, -- Exigencia del Código del Trabajo

    -- Gestión de Personal Contratado vs Informal / Jornalero
    tiene_contrato BOOLEAN NOT NULL DEFAULT TRUE,
    tarifa_hora NUMERIC(10,2) NOT NULL DEFAULT 0.00 CHECK (tarifa_hora >= 0),

    id_rol INT NOT NULL REFERENCES roles(id_rol) ON DELETE RESTRICT,

    -- Estados y Seguridad
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    bloqueado BOOLEAN NOT NULL DEFAULT FALSE,
    intentos_fallidos INT NOT NULL DEFAULT 0 CHECK (intentos_fallidos >= 0),

    -- Consentimiento explícito de Datos Personales (Ley N° 19.628)
    consentimiento_datos_ley19628 BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_consentimiento TIMESTAMPTZ,

    ultimo_login TIMESTAMPTZ,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- 4. MÓDULO OPERATIVO DE TERRENO: ASISTENCIA, HERRAMIENTAS IOT Y PRÉSTAMOS
-- =============================================================================

-- A. Control de Asistencia y Cálculo de Horas
CREATE TABLE IF NOT EXISTS marcajes_asistencia (
    id_marcaje UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_usuario UUID NOT NULL REFERENCES usuarios(id_usuario) ON DELETE RESTRICT,
    fecha_hora_entrada TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_hora_salida TIMESTAMPTZ,
    horas_ordinarias NUMERIC(5,2) DEFAULT 0.00,
    horas_extras NUMERIC(5,2) DEFAULT 0.00,
    monto_liquidar NUMERIC(12,2) DEFAULT 0.00,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- B. Inventario de Herramientas e Identificadores IoT
CREATE TABLE IF NOT EXISTS equipos_herramientas (
    id_equipo UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_tag_iot VARCHAR(100) UNIQUE NOT NULL, -- RFID / NFC / Código QR
    numero_serie VARCHAR(100) UNIQUE NOT NULL,
    nombre VARCHAR(150) NOT NULL,
    descripcion TEXT,
    estado_fisico VARCHAR(50) NOT NULL DEFAULT 'OPTIMO'
        CHECK (estado_fisico IN ('OPTIMO', 'DANIADO', 'EN_MANTENCION', 'DADO_DE_BAJA')),
    disponible BOOLEAN NOT NULL DEFAULT TRUE,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- C. Préstamos y Devoluciones con Firma Digital y Evidencias
CREATE TABLE IF NOT EXISTS prestamos (
    id_prestamo UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_equipo UUID NOT NULL REFERENCES equipos_herramientas(id_equipo) ON DELETE RESTRICT,
    id_trabajador UUID NOT NULL REFERENCES usuarios(id_usuario) ON DELETE RESTRICT,
    id_bodeguero UUID NOT NULL REFERENCES usuarios(id_usuario) ON DELETE RESTRICT,
    fecha_hora_salida TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_hora_devolucion TIMESTAMPTZ,
    estado_devolucion VARCHAR(50) NOT NULL DEFAULT 'PENDIENTE_FIRMA'
        CHECK (estado_devolucion IN ('PENDIENTE_FIRMA', 'PENDIENTE', 'DEVUELTO_OK', 'DEVUELTO_CON_DANOS')),
    firma_digital_hash VARCHAR(64)
        CHECK (firma_digital_hash IS NULL OR firma_digital_hash ~ '^[0-9a-f]{64}$'),
    firma_storage_path TEXT,
    id_bodeguero_recepcion UUID REFERENCES usuarios(id_usuario) ON DELETE RESTRICT,
    evidencia_devolucion_storage_path TEXT,
    observacion_devolucion TEXT,
    CHECK (
        (estado_devolucion = 'PENDIENTE_FIRMA' AND firma_digital_hash IS NULL AND firma_storage_path IS NULL)
        OR
        (estado_devolucion <> 'PENDIENTE_FIRMA' AND firma_digital_hash IS NOT NULL AND firma_storage_path IS NOT NULL)
    ),
    CHECK (
        (estado_devolucion IN ('PENDIENTE_FIRMA', 'PENDIENTE') AND fecha_hora_devolucion IS NULL)
        OR
        (estado_devolucion IN ('DEVUELTO_OK', 'DEVUELTO_CON_DANOS') AND fecha_hora_devolucion IS NOT NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_prestamo_equipo_abierto
    ON prestamos(id_equipo)
    WHERE fecha_hora_devolucion IS NULL;

-- =============================================================================
-- 5. KARDEX TRANSACCIONAL CENTRAL CON PAYLOAD JSONB (PATRÓN APPEND-ONLY)
-- =============================================================================
CREATE TABLE IF NOT EXISTS kardex_transaccional (
    id_kardex BIGSERIAL PRIMARY KEY,
    modulo VARCHAR(50) NOT NULL CHECK (
        modulo IN ('IAM_SEGURIDAD', 'PERSONAL_HORAS', 'BODEGA_IOT', 'EVIDENCIAS_TERRENO', 'MANTENIMIENTO')
    ),
    proyecto_id TEXT,
    codigo_operacion VARCHAR(100) NOT NULL,
    id_usuario_ejecutor UUID REFERENCES usuarios(id_usuario) ON DELETE SET NULL,
    id_registro_referencia TEXT,
    payload_jsonb JSONB NOT NULL,
    hash_integridad TEXT NOT NULL,
    ip_origen VARCHAR(45) NOT NULL DEFAULT '0.0.0.0',
    agente_usuario TEXT,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- 6. BITÁCORA DE AUDITORÍA DE USUARIOS (PATRÓN WORM)
-- =============================================================================
CREATE TABLE IF NOT EXISTS auditoria_usuarios (
    id_auditoria BIGSERIAL PRIMARY KEY,
    tabla_afectada VARCHAR(50) NOT NULL DEFAULT 'usuarios',
    id_usuario_afectado UUID REFERENCES usuarios(id_usuario) ON DELETE SET NULL,
    operacion VARCHAR(50) NOT NULL,
    id_usuario_ejecutor UUID REFERENCES usuarios(id_usuario) ON DELETE SET NULL,
    datos_anteriores JSONB,
    datos_nuevos JSONB,
    ip_origen VARCHAR(45) DEFAULT '0.0.0.0',
    agente_usuario TEXT,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- 7. ÍNDICES DE ALTO RENDIMIENTO (GIN PARA JSONB)
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_kardex_payload_gin ON kardex_transaccional USING GIN (payload_jsonb);
CREATE INDEX IF NOT EXISTS idx_usuarios_rol ON usuarios(id_rol);
CREATE INDEX IF NOT EXISTS idx_auditoria_afectado ON auditoria_usuarios(id_usuario_afectado);
CREATE INDEX IF NOT EXISTS idx_auditoria_fecha ON auditoria_usuarios(fecha_hora DESC);
CREATE INDEX IF NOT EXISTS idx_kardex_modulo_op ON kardex_transaccional(modulo, codigo_operacion);
CREATE INDEX IF NOT EXISTS idx_kardex_fecha ON kardex_transaccional(fecha_hora DESC);
CREATE INDEX IF NOT EXISTS idx_equipos_tag ON equipos_herramientas(codigo_tag_iot);

-- =============================================================================
-- 8. TRIGGERS DE PROTECCIÓN Y SANITIZACIÓN
-- =============================================================================

-- A. Sanitización y Normalización de RUT
CREATE OR REPLACE FUNCTION fn_normalizar_rut_usuario()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.rut NOT LIKE 'ANON-%' THEN
        NEW.rut := UPPER(REPLACE(NEW.rut, '.', ''));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_normalizar_rut ON usuarios;
CREATE TRIGGER trg_normalizar_rut
BEFORE INSERT OR UPDATE OF rut ON usuarios
FOR EACH ROW EXECUTE FUNCTION fn_normalizar_rut_usuario();

-- B. Refresco Automático de Timestamp
CREATE OR REPLACE FUNCTION fn_actualizar_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.actualizado_en = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_establecer_hash_kardex()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
    v_contenido JSONB;
BEGIN
    NEW.fecha_hora := clock_timestamp();
    v_contenido := jsonb_build_object(
        'modulo', NEW.modulo,
        'proyecto_id', NEW.proyecto_id,
        'codigo_operacion', NEW.codigo_operacion,
        'id_usuario_ejecutor', NEW.id_usuario_ejecutor,
        'id_registro_referencia', NEW.id_registro_referencia,
        'payload_jsonb', NEW.payload_jsonb,
        'fecha_hora', NEW.fecha_hora
    );
    NEW.hash_integridad := encode(
        public.digest(convert_to(v_contenido::TEXT, 'UTF8'), 'sha256'),
        'hex'
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_establecer_hash_kardex ON kardex_transaccional;
CREATE TRIGGER trg_establecer_hash_kardex
    BEFORE INSERT ON kardex_transaccional
    FOR EACH ROW EXECUTE FUNCTION fn_establecer_hash_kardex();

DROP TRIGGER IF EXISTS trg_actualizar_timestamp_usuarios ON usuarios;
CREATE TRIGGER trg_actualizar_timestamp_usuarios BEFORE UPDATE ON usuarios FOR EACH ROW EXECUTE FUNCTION fn_actualizar_timestamp();

DROP TRIGGER IF EXISTS trg_actualizar_timestamp_roles ON roles;
CREATE TRIGGER trg_actualizar_timestamp_roles BEFORE UPDATE ON roles FOR EACH ROW EXECUTE FUNCTION fn_actualizar_timestamp();

DROP TRIGGER IF EXISTS trg_actualizar_timestamp_equipos ON equipos_herramientas;
CREATE TRIGGER trg_actualizar_timestamp_equipos BEFORE UPDATE ON equipos_herramientas FOR EACH ROW EXECUTE FUNCTION fn_actualizar_timestamp();

-- C. Bloqueo Inalterable WORM sobre Auditoría y Kardex
CREATE OR REPLACE FUNCTION fn_bloquear_modificacion_worm()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'BLOQUEO LEGAL (Ley N° 21.595): Los registros de auditoría y Kardex son inalterables. Se prohíbe UPDATE, DELETE o TRUNCATE.';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auditoria_inalterable ON auditoria_usuarios;
CREATE TRIGGER trg_auditoria_inalterable BEFORE UPDATE OR DELETE ON auditoria_usuarios FOR EACH ROW EXECUTE FUNCTION fn_bloquear_modificacion_worm();

DROP TRIGGER IF EXISTS trg_no_truncate_auditoria ON auditoria_usuarios;
CREATE TRIGGER trg_no_truncate_auditoria BEFORE TRUNCATE ON auditoria_usuarios FOR EACH STATEMENT EXECUTE FUNCTION fn_bloquear_modificacion_worm();

DROP TRIGGER IF EXISTS trg_kardex_inalterable ON kardex_transaccional;
CREATE TRIGGER trg_kardex_inalterable BEFORE UPDATE OR DELETE ON kardex_transaccional FOR EACH ROW EXECUTE FUNCTION fn_bloquear_modificacion_worm();

DROP TRIGGER IF EXISTS trg_no_truncate_kardex ON kardex_transaccional;
CREATE TRIGGER trg_no_truncate_kardex BEFORE TRUNCATE ON kardex_transaccional FOR EACH STATEMENT EXECUTE FUNCTION fn_bloquear_modificacion_worm();

-- D. Prohibición Total de Borrados Físicos en Tablas del Sistema
CREATE OR REPLACE FUNCTION fn_prohibir_borrado_fisico()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'VIOLACIÓN DE SEGURIDAD: Prohibido borrar físicamente registros. Utilice la desactivación lógica o anonimización.';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_no_delete_usuarios ON usuarios;
CREATE TRIGGER trg_no_delete_usuarios BEFORE DELETE ON usuarios FOR EACH ROW EXECUTE FUNCTION fn_prohibir_borrado_fisico();

DROP TRIGGER IF EXISTS trg_no_truncate_usuarios ON usuarios;
CREATE TRIGGER trg_no_truncate_usuarios BEFORE TRUNCATE ON usuarios FOR EACH STATEMENT EXECUTE FUNCTION fn_prohibir_borrado_fisico();

DROP TRIGGER IF EXISTS trg_no_delete_roles ON roles;
CREATE TRIGGER trg_no_delete_roles BEFORE DELETE ON roles FOR EACH ROW EXECUTE FUNCTION fn_prohibir_borrado_fisico();

DROP TRIGGER IF EXISTS trg_no_truncate_roles ON roles;
CREATE TRIGGER trg_no_truncate_roles BEFORE TRUNCATE ON roles FOR EACH STATEMENT EXECUTE FUNCTION fn_prohibir_borrado_fisico();

DROP TRIGGER IF EXISTS trg_no_delete_equipos ON equipos_herramientas;
CREATE TRIGGER trg_no_delete_equipos BEFORE DELETE ON equipos_herramientas FOR EACH ROW EXECUTE FUNCTION fn_prohibir_borrado_fisico();

DROP TRIGGER IF EXISTS trg_no_truncate_equipos ON equipos_herramientas;
CREATE TRIGGER trg_no_truncate_equipos BEFORE TRUNCATE ON equipos_herramientas FOR EACH STATEMENT EXECUTE FUNCTION fn_prohibir_borrado_fisico();

-- E. Auditoría Automática de Cambios en Usuarios (PROTEGIENDO PASSWORD_HASH Y REDACTANDO PII HISTÓRICA)
CREATE OR REPLACE FUNCTION fn_auditar_cambios_tabla_usuarios()
RETURNS TRIGGER AS $$
DECLARE
    v_datos_anteriores JSONB;
    v_datos_nuevos JSONB;
BEGIN
    v_datos_nuevos := to_jsonb(NEW);

    IF (TG_OP = 'INSERT') THEN
        INSERT INTO auditoria_usuarios (id_usuario_afectado, operacion, datos_nuevos)
        VALUES (NEW.id_usuario, 'INSERT', v_datos_nuevos);
        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        v_datos_anteriores := to_jsonb(OLD);

        -- Si es una anonimización por Derecho al Olvido (Ley N° 19.628), redactamos la PII histórica
        IF NEW.rut LIKE 'ANON-%' THEN
            v_datos_anteriores := v_datos_anteriores
                || jsonb_build_object(
                    'rut', 'ANONIMIZADO_LEY_19628',
                    'nombres', 'USUARIO',
                    'apellidos', 'ANONIMIZADO',
                    'email', 'ANONIMIZADO@local',
                    'telefono', NULL
                );
        END IF;

        INSERT INTO auditoria_usuarios (id_usuario_afectado, operacion, datos_anteriores, datos_nuevos)
        VALUES (NEW.id_usuario, 'UPDATE', v_datos_anteriores, v_datos_nuevos);
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auditoria_tabla_usuarios ON usuarios;
CREATE TRIGGER trg_auditoria_tabla_usuarios AFTER INSERT OR UPDATE ON usuarios FOR EACH ROW EXECUTE FUNCTION fn_auditar_cambios_tabla_usuarios();

-- =============================================================================
-- 9. PROCEDIMIENTOS ADMINISTRATIVOS (NO EXPUESTOS A LA API REST)
-- =============================================================================

-- Solo el Administrador del sistema puede cambiar el rol; se usa auth.uid()
-- y no se acepta que el cliente indique quién ejecuta la acción.
CREATE OR REPLACE FUNCTION fn_promover_usuario(
    p_id_usuario_a_promover UUID,
    p_nuevo_codigo_rol VARCHAR(50),
    p_justificacion_capacitacion TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_id_nuevo_rol INT;
    v_rol_anterior VARCHAR(50);
BEGIN
    IF auth.uid() IS NULL OR auth.uid() = p_id_usuario_a_promover THEN
        RAISE EXCEPTION 'No puedes cambiar tu propio rol.';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM public.usuarios AS u
        JOIN public.roles AS r ON r.id_rol = u.id_rol
        WHERE u.id_usuario = auth.uid()
          AND u.activo = TRUE AND u.bloqueado = FALSE
          AND r.codigo_rol = 'ADMIN_GENERAL' AND r.activo = TRUE
    ) THEN
        RAISE EXCEPTION 'Solo el Administrador del sistema puede asignar roles.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.usuarios WHERE id_usuario = p_id_usuario_a_promover AND activo = TRUE) THEN
        RAISE EXCEPTION 'ERROR: El usuario objetivo a promover no existe.';
    END IF;

    IF p_justificacion_capacitacion IS NULL OR LENGTH(TRIM(p_justificacion_capacitacion)) < 10 THEN
        RAISE EXCEPTION 'Debes registrar una justificación de al menos 10 caracteres.';
    END IF;

    SELECT id_rol INTO v_id_nuevo_rol
    FROM public.roles
    WHERE codigo_rol = p_nuevo_codigo_rol AND activo = TRUE;
    IF v_id_nuevo_rol IS NULL THEN
        RAISE EXCEPTION 'El rol solicitado "%" no existe o está inactivo.', p_nuevo_codigo_rol;
    END IF;

    SELECT r.codigo_rol INTO v_rol_anterior
    FROM public.usuarios AS u
    JOIN public.roles AS r ON u.id_rol = r.id_rol
    WHERE u.id_usuario = p_id_usuario_a_promover;

    UPDATE public.usuarios
    SET id_rol = v_id_nuevo_rol,
        actualizado_en = CURRENT_TIMESTAMP
    WHERE id_usuario = p_id_usuario_a_promover;

    INSERT INTO public.auditoria_usuarios (
        id_usuario_afectado, operacion, id_usuario_ejecutor, datos_nuevos
    )
    VALUES (
        p_id_usuario_a_promover,
        'ASIGNACION_ROL',
        auth.uid(),
        jsonb_build_object(
            'rol_anterior', v_rol_anterior,
            'rol_nuevo', p_nuevo_codigo_rol,
            'justificacion', p_justificacion_capacitacion
        )
    );
END;
$$;

-- C. Anonimización por Derecho al Olvido (Ley N° 19.628 / N° 21.716 con Control RBAC)
CREATE OR REPLACE FUNCTION fn_solicitar_anonimizacion_usuario(
    p_id_usuario_a_eliminar UUID,
    p_id_usuario_ejecutor UUID,
    p_motivo_solicitud TEXT
)
RETURNS VOID AS $$
DECLARE
    v_rut_original VARCHAR(12);
    v_rol_ejecutor VARCHAR(50);
BEGIN
    -- Validar que un administrador no se anonimice/elimine a sí mismo
    IF p_id_usuario_a_eliminar = p_id_usuario_ejecutor THEN
        RAISE EXCEPTION 'SEGURIDAD: Un administrador no puede solicitar la anonimización de su propia cuenta activa.';
    END IF;

    -- Validar permisos del ejecutor (Solo ADMIN_GENERAL)
    SELECT r.codigo_rol INTO v_rol_ejecutor
    FROM usuarios u
    JOIN roles r ON u.id_rol = r.id_rol
    WHERE u.id_usuario = p_id_usuario_ejecutor AND u.activo = TRUE AND u.bloqueado = FALSE;

    IF v_rol_ejecutor IS NULL OR v_rol_ejecutor != 'ADMIN_GENERAL' THEN
        RAISE EXCEPTION 'ACCESO DENEGADO: Solo el Administrador General puede autorizar el procedimiento de anonimización.';
    END IF;

    -- Validar motivo de la solicitud
    IF p_motivo_solicitud IS NULL OR LENGTH(TRIM(p_motivo_solicitud)) < 5 THEN
        RAISE EXCEPTION 'REQUISITO LEGAL: Debe ingresar un motivo documentado para ejecutar la anonimización.';
    END IF;

    SELECT rut INTO v_rut_original FROM usuarios WHERE id_usuario = p_id_usuario_a_eliminar;

    IF v_rut_original IS NULL THEN
        RAISE EXCEPTION 'ERROR: El usuario especificado no existe.';
    END IF;

    -- Registrar el evento en auditoría con el motivo antes de sobrescribir el usuario
    INSERT INTO auditoria_usuarios (id_usuario_afectado, operacion, id_usuario_ejecutor, datos_nuevos)
    VALUES (
        p_id_usuario_a_eliminar,
        'SOLICITUD_ANONIMIZACION_LEY_19628',
        p_id_usuario_ejecutor,
        jsonb_build_object('motivo_legal', p_motivo_solicitud)
    );

    -- Ejecutar anonimización manteniendo el UUID para no romper FKs en bodega/kardex
    UPDATE usuarios
    SET
        rut = 'ANON-' || SUBSTRING(p_id_usuario_a_eliminar::text FROM 1 FOR 7),
        nombres = 'USUARIO',
        apellidos = 'ANONIMIZADO_LEY_19628',
        email = 'deleted_' || SUBSTRING(p_id_usuario_a_eliminar::text FROM 1 FOR 8) || '@anonimizado.local',
        telefono = NULL,
        cargo_contrato = 'EX_TRABAJADOR_ANONIMIZADO',
        activo = FALSE,
        bloqueado = TRUE,
        consentimiento_datos_ley19628 = FALSE
    WHERE id_usuario = p_id_usuario_a_eliminar;

    -- Supabase Auth administra y revoca sus propias sesiones. Desactivar este
    -- perfil bloquea las políticas RLS; un administrador debe deshabilitar
    -- además la cuenta Auth mediante el panel/API administrativa de Supabase.
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- 11. POBLAMIENTO Y SEGREGACIÓN ESTRICTA DE PERMISOS (0% SOLAPAMIENTO)
-- =============================================================================

INSERT INTO roles (codigo_rol, nombre, descripcion) VALUES
('ADMIN_GENERAL', 'Administrador del sistema', 'Administra cuentas, asignación de roles, configuración de obras y consulta auditorías. No registra préstamos ni devoluciones.'),
('JEFE_OBRA', 'Jefe de obra', 'Supervisa obras, consulta inventario y préstamos pendientes, y planifica tareas. No opera la bodega ni asigna roles.'),
('BODEGUERO', 'Bodeguero', 'Mantiene el catálogo y disponibilidad de herramientas, registra préstamos y devoluciones con evidencias. No administra cuentas ni aprueba sus propios movimientos.'),
('OPERARIO_MAESTRO', 'Trabajador / operario', 'Consulta herramientas disponibles, firma la recepción de sus préstamos, consulta sus propios préstamos y reporta incidencias. No modifica inventario.')
ON CONFLICT (codigo_rol) DO UPDATE
SET nombre = EXCLUDED.nombre,
    descripcion = EXCLUDED.descripcion,
    activo = TRUE;

UPDATE roles SET activo = FALSE WHERE codigo_rol = 'PREVENCIONISTA';

INSERT INTO permisos (codigo_permiso, modulo, descripcion) VALUES
('PROYECTO_CONSULTAR', 'OBRA', 'Consultar únicamente las obras donde el usuario tiene una asignación activa.'),
('USUARIOS_GESTIONAR', 'ADMINISTRACION', 'Crear perfiles de personal, desactivar perfiles y mantener datos laborales.'),
('ROLES_ASIGNAR', 'ADMINISTRACION', 'Asignar roles autorizados a usuarios; no permite autoasignarse privilegios.'),
('PROYECTO_CONFIGURAR', 'ADMINISTRACION', 'Crear y actualizar obras, su estado y configuración.'),
('AUDITORIA_CONSULTAR', 'AUDITORIA', 'Consultar eventos de auditoría sin alterarlos.'),
('INVENTARIO_CONSULTAR', 'BODEGA', 'Consultar herramientas activas y su disponibilidad en la obra asignada.'),
('HERRAMIENTA_CREAR', 'BODEGA', 'Dar de alta herramientas y su identificador QR/barra.'),
('HERRAMIENTA_ACTUALIZAR', 'BODEGA', 'Actualizar ficha, estado físico y disponibilidad de una herramienta.'),
('PRESTAMO_REGISTRAR', 'BODEGA', 'Registrar la salida de una herramienta a un trabajador de la misma obra.'),
('DEVOLUCION_REGISTRAR', 'BODEGA', 'Registrar devolución, condición física y evidencia de daño.'),
('PRESTAMOS_CONSULTAR_OBRA', 'BODEGA', 'Consultar los préstamos de la obra asignada.'),
('PRESTAMOS_CONSULTAR_PROPIOS', 'TERRENO', 'Consultar únicamente los préstamos propios del trabajador.'),
('PRESTAMO_FIRMAR_PROPIO', 'TERRENO', 'Adjuntar la constancia de recepción firmada para un préstamo propio.'),
('REPORTE_PENDIENTES_CONSULTAR', 'OBRA', 'Consultar herramientas prestadas pendientes de devolución.'),
('ASISTENCIA_MARCAR_PROPIA', 'TERRENO', 'Registrar la entrada o salida de asistencia propia.'),
('INCIDENCIA_REGISTRAR', 'TERRENO', 'Registrar hallazgos de obra sin modificar ni cerrar los de otros usuarios.'),
('INCIDENCIA_GESTIONAR', 'OBRA', 'Asignar y actualizar el estado de incidencias de la obra.'),
('TAREA_PLANIFICAR', 'OBRA', 'Crear y actualizar tareas y restricciones del plan semanal.'),
('TAREA_ELIMINAR', 'OBRA', 'Eliminar tareas del plan semanal cuando ya no correspondan.'),
('MATERIAL_SOLICITAR', 'TERRENO', 'Solicitar materiales sin aprobar, recibir ni modificar stock.'),
('MATERIAL_PEDIDO_GESTIONAR', 'BODEGA', 'Revisar solicitudes y registrar su despacho o entrega.'),
('MATERIAL_CATALOGO_GESTIONAR', 'BODEGA', 'Mantener el catálogo y existencias de materiales de la obra.'),
('ALERTA_STOCK_CONSULTAR', 'BODEGA', 'Consultar alertas de stock bajo de las obras asignadas.'),
('KARDEX_CONSULTAR', 'AUDITORIA', 'Leer el Kardex; no permite insertar, actualizar ni eliminar directamente.'),
('KARDEX_INSERTAR', 'AUDITORIA', 'Permite a las operaciones autorizadas generar eventos nuevos de Kardex; nunca modificar los existentes.')
ON CONFLICT (codigo_permiso) DO UPDATE
SET modulo = EXCLUDED.modulo,
    descripcion = EXCLUDED.descripcion;

-- Recalcula solo las asignaciones de estos cuatro roles; no concede permisos
-- completos por módulo y mantiene separadas las responsabilidades operativas.
DELETE FROM rol_permisos
WHERE id_rol IN (SELECT id_rol FROM roles WHERE codigo_rol IN (
    'ADMIN_GENERAL', 'JEFE_OBRA', 'BODEGUERO', 'OPERARIO_MAESTRO'
));

INSERT INTO rol_permisos (id_rol, id_permiso)
SELECT r.id_rol, p.id_permiso
FROM (VALUES
    ('ADMIN_GENERAL', 'PROYECTO_CONSULTAR'),
    ('ADMIN_GENERAL', 'USUARIOS_GESTIONAR'),
    ('ADMIN_GENERAL', 'ROLES_ASIGNAR'),
    ('ADMIN_GENERAL', 'PROYECTO_CONFIGURAR'),
    ('ADMIN_GENERAL', 'AUDITORIA_CONSULTAR'),
    ('ADMIN_GENERAL', 'ALERTA_STOCK_CONSULTAR'),
    ('ADMIN_GENERAL', 'KARDEX_CONSULTAR'),

    ('JEFE_OBRA', 'PROYECTO_CONSULTAR'),
    ('JEFE_OBRA', 'INVENTARIO_CONSULTAR'),
    ('JEFE_OBRA', 'PRESTAMOS_CONSULTAR_OBRA'),
    ('JEFE_OBRA', 'REPORTE_PENDIENTES_CONSULTAR'),
    ('JEFE_OBRA', 'INCIDENCIA_GESTIONAR'),
    ('JEFE_OBRA', 'TAREA_PLANIFICAR'),
    ('JEFE_OBRA', 'TAREA_ELIMINAR'),
    ('JEFE_OBRA', 'ALERTA_STOCK_CONSULTAR'),
    ('JEFE_OBRA', 'KARDEX_CONSULTAR'),

    ('BODEGUERO', 'PROYECTO_CONSULTAR'),
    ('BODEGUERO', 'INVENTARIO_CONSULTAR'),
    ('BODEGUERO', 'HERRAMIENTA_CREAR'),
    ('BODEGUERO', 'HERRAMIENTA_ACTUALIZAR'),
    ('BODEGUERO', 'PRESTAMO_REGISTRAR'),
    ('BODEGUERO', 'DEVOLUCION_REGISTRAR'),
    ('BODEGUERO', 'PRESTAMOS_CONSULTAR_OBRA'),
    ('BODEGUERO', 'MATERIAL_PEDIDO_GESTIONAR'),
    ('BODEGUERO', 'MATERIAL_CATALOGO_GESTIONAR'),
    ('BODEGUERO', 'ALERTA_STOCK_CONSULTAR'),
    ('BODEGUERO', 'KARDEX_CONSULTAR'),

    ('OPERARIO_MAESTRO', 'PROYECTO_CONSULTAR'),
    ('OPERARIO_MAESTRO', 'INVENTARIO_CONSULTAR'),
    ('OPERARIO_MAESTRO', 'PRESTAMOS_CONSULTAR_PROPIOS'),
    ('OPERARIO_MAESTRO', 'PRESTAMO_FIRMAR_PROPIO'),
    ('OPERARIO_MAESTRO', 'ASISTENCIA_MARCAR_PROPIA'),
    ('OPERARIO_MAESTRO', 'INCIDENCIA_REGISTRAR'),
    ('OPERARIO_MAESTRO', 'MATERIAL_SOLICITAR')
) AS asignacion(codigo_rol, codigo_permiso)
JOIN roles r ON r.codigo_rol = asignacion.codigo_rol
JOIN permisos p ON p.codigo_permiso = asignacion.codigo_permiso;

-- =============================================================================
-- 12. MÓDULO CONTERRENO Y ACCESO SEGURO DESDE SUPABASE
-- =============================================================================
-- La autenticación de la aplicación usa Supabase Auth (auth.users), no
-- usuarios.password_hash ni una clave de base de datos en el navegador.
CREATE TABLE IF NOT EXISTS conterreno_proyectos (
    id TEXT PRIMARY KEY,
    nombre VARCHAR(150) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS conterreno_usuarios_proyectos (
    proyecto_id TEXT NOT NULL REFERENCES conterreno_proyectos(id) ON DELETE RESTRICT,
    usuario_auth_id UUID NOT NULL REFERENCES usuarios(id_usuario) ON DELETE RESTRICT,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (proyecto_id, usuario_auth_id)
);

CREATE TABLE IF NOT EXISTS conterreno_incidencias (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    proyecto_id TEXT NOT NULL REFERENCES conterreno_proyectos(id) ON DELETE RESTRICT,
    titulo VARCHAR(200) NOT NULL,
    sector VARCHAR(150) NOT NULL,
    categoria VARCHAR(30) NOT NULL CHECK (categoria IN ('Calidad', 'Seguridad', 'Avance', 'Materiales')),
    prioridad VARCHAR(10) NOT NULL CHECK (prioridad IN ('Alta', 'Media', 'Baja')),
    estado VARCHAR(20) NOT NULL DEFAULT 'Abierta' CHECK (estado IN ('Abierta', 'En Proceso', 'Cerrada')),
    responsable VARCHAR(150) NOT NULL,
    descripcion TEXT NOT NULL,
    foto_url TEXT,
    fecha_reporte DATE NOT NULL DEFAULT CURRENT_DATE,
    creado_por UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE RESTRICT,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS conterreno_tareas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    proyecto_id TEXT NOT NULL REFERENCES conterreno_proyectos(id) ON DELETE RESTRICT,
    titulo VARCHAR(200) NOT NULL,
    sector VARCHAR(150) NOT NULL,
    responsable VARCHAR(150) NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'todo' CHECK (estado IN ('todo', 'progress', 'blocked', 'done')),
    restriccion TEXT,
    creado_por UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE RESTRICT,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK ((estado = 'blocked') OR restriccion IS NULL)
);

CREATE TABLE IF NOT EXISTS conterreno_pedidos_materiales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    proyecto_id TEXT NOT NULL REFERENCES conterreno_proyectos(id) ON DELETE RESTRICT,
    destino VARCHAR(150) NOT NULL,
    urgencia VARCHAR(20) NOT NULL CHECK (urgencia IN ('Urgente', 'Normal')),
    estado VARCHAR(30) NOT NULL DEFAULT 'Pendiente'
        CHECK (estado IN ('Pendiente', 'En Camino', 'Entregado', 'Rechazado')),
    items JSONB NOT NULL CHECK (jsonb_typeof(items) = 'array' AND jsonb_array_length(items) > 0),
    solicitado_por UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE RESTRICT,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS conterreno_catalogo_materiales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo VARCHAR(60) UNIQUE NOT NULL,
    nombre VARCHAR(180) NOT NULL,
    unidad VARCHAR(30) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS conterreno_stock_materiales (
    proyecto_id TEXT NOT NULL REFERENCES conterreno_proyectos(id) ON DELETE RESTRICT,
    material_id UUID NOT NULL REFERENCES conterreno_catalogo_materiales(id) ON DELETE RESTRICT,
    cantidad NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (cantidad >= 0),
    stock_minimo NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (stock_minimo >= 0),
    actualizado_por UUID REFERENCES usuarios(id_usuario) ON DELETE SET NULL,
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (proyecto_id, material_id)
);

CREATE TABLE IF NOT EXISTS conterreno_movimientos_materiales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    proyecto_id TEXT NOT NULL REFERENCES conterreno_proyectos(id) ON DELETE RESTRICT,
    material_id UUID NOT NULL REFERENCES conterreno_catalogo_materiales(id) ON DELETE RESTRICT,
    tipo VARCHAR(12) NOT NULL CHECK (tipo IN ('ENTRADA', 'SALIDA', 'AJUSTE')),
    cantidad NUMERIC(12, 2) NOT NULL CHECK (cantidad > 0),
    motivo TEXT NOT NULL,
    referencia TEXT,
    ejecutado_por UUID REFERENCES usuarios(id_usuario) ON DELETE SET NULL,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS conterreno_alertas_stock (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    proyecto_id TEXT NOT NULL REFERENCES conterreno_proyectos(id) ON DELETE RESTRICT,
    material_id UUID NOT NULL REFERENCES conterreno_catalogo_materiales(id) ON DELETE RESTRICT,
    cantidad_actual NUMERIC(12, 2) NOT NULL CHECK (cantidad_actual >= 0),
    stock_minimo NUMERIC(12, 2) NOT NULL CHECK (stock_minimo >= 0),
    estado VARCHAR(10) NOT NULL DEFAULT 'ACTIVA' CHECK (estado IN ('ACTIVA', 'RESUELTA')),
    creada_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resuelta_en TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS conterreno_reportes_prestamos_diarios (
    id BIGSERIAL PRIMARY KEY,
    proyecto_id TEXT NOT NULL REFERENCES conterreno_proyectos(id) ON DELETE RESTRICT,
    fecha_reporte DATE NOT NULL,
    total_pendientes INTEGER NOT NULL CHECK (total_pendientes >= 0),
    prestamos_pendientes JSONB NOT NULL
        CHECK (jsonb_typeof(prestamos_pendientes) = 'array'),
    generado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (proyecto_id, fecha_reporte)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_conterreno_alerta_stock_activa
    ON conterreno_alertas_stock(proyecto_id, material_id)
    WHERE estado = 'ACTIVA';
CREATE INDEX IF NOT EXISTS idx_conterreno_movimientos_materiales_fecha
    ON conterreno_movimientos_materiales(proyecto_id, material_id, creado_en DESC);

DROP TRIGGER IF EXISTS trg_conterreno_catalogo_materiales_actualizado_en ON conterreno_catalogo_materiales;
CREATE TRIGGER trg_conterreno_catalogo_materiales_actualizado_en
    BEFORE UPDATE ON conterreno_catalogo_materiales
    FOR EACH ROW EXECUTE FUNCTION fn_actualizar_timestamp();

INSERT INTO conterreno_proyectos (id, nombre) VALUES
    ('p1', 'Edificio Altavista - Obra Gruesa'),
    ('p2', 'Residencial Los Olivos - Etapa 2'),
    ('p3', 'Centro Logístico Norte - Bodegas')
ON CONFLICT (id) DO NOTHING;

-- Vincula la asistencia y los activos/prestamos de herramientas a una obra.
ALTER TABLE marcajes_asistencia
    ADD COLUMN IF NOT EXISTS proyecto_id TEXT REFERENCES conterreno_proyectos(id) ON DELETE RESTRICT;
ALTER TABLE equipos_herramientas
    ADD COLUMN IF NOT EXISTS proyecto_id TEXT REFERENCES conterreno_proyectos(id) ON DELETE RESTRICT;
ALTER TABLE prestamos
    ADD COLUMN IF NOT EXISTS proyecto_id TEXT REFERENCES conterreno_proyectos(id) ON DELETE RESTRICT;
ALTER TABLE kardex_transaccional
    ADD COLUMN IF NOT EXISTS proyecto_id TEXT REFERENCES conterreno_proyectos(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_conterreno_membresias_usuario
    ON conterreno_usuarios_proyectos(usuario_auth_id, activo);
CREATE INDEX IF NOT EXISTS idx_conterreno_membresias_proyecto
    ON conterreno_usuarios_proyectos(proyecto_id, activo);
CREATE INDEX IF NOT EXISTS idx_conterreno_incidencias_proyecto_fecha
    ON conterreno_incidencias(proyecto_id, fecha_reporte DESC);
CREATE INDEX IF NOT EXISTS idx_conterreno_tareas_proyecto_estado
    ON conterreno_tareas(proyecto_id, estado);
CREATE INDEX IF NOT EXISTS idx_conterreno_pedidos_proyecto_fecha
    ON conterreno_pedidos_materiales(proyecto_id, creado_en DESC);
CREATE INDEX IF NOT EXISTS idx_conterreno_stock_proyecto
    ON conterreno_stock_materiales(proyecto_id, actualizado_en DESC);
CREATE INDEX IF NOT EXISTS idx_conterreno_alertas_proyecto_estado
    ON conterreno_alertas_stock(proyecto_id, estado, creada_en DESC);
CREATE INDEX IF NOT EXISTS idx_conterreno_reportes_proyecto_fecha
    ON conterreno_reportes_prestamos_diarios(proyecto_id, fecha_reporte DESC);
CREATE INDEX IF NOT EXISTS idx_asistencia_proyecto_fecha
    ON marcajes_asistencia(proyecto_id, fecha_hora_entrada DESC);
CREATE INDEX IF NOT EXISTS idx_equipos_proyecto
    ON equipos_herramientas(proyecto_id);
CREATE INDEX IF NOT EXISTS idx_prestamos_proyecto_fecha
    ON prestamos(proyecto_id, fecha_hora_salida DESC);
CREATE INDEX IF NOT EXISTS idx_prestamos_trabajador_fecha
    ON prestamos(id_trabajador, fecha_hora_salida DESC);
CREATE INDEX IF NOT EXISTS idx_prestamos_pendientes
    ON prestamos(proyecto_id, fecha_hora_salida)
    WHERE fecha_hora_devolucion IS NULL;

DROP TRIGGER IF EXISTS trg_conterreno_incidencias_actualizado_en ON conterreno_incidencias;
CREATE TRIGGER trg_conterreno_incidencias_actualizado_en
    BEFORE UPDATE ON conterreno_incidencias
    FOR EACH ROW EXECUTE FUNCTION fn_actualizar_timestamp();
DROP TRIGGER IF EXISTS trg_conterreno_tareas_actualizado_en ON conterreno_tareas;
CREATE TRIGGER trg_conterreno_tareas_actualizado_en
    BEFORE UPDATE ON conterreno_tareas
    FOR EACH ROW EXECUTE FUNCTION fn_actualizar_timestamp();

CREATE OR REPLACE FUNCTION fn_conterreno_es_miembro(p_proyecto_id TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.conterreno_usuarios_proyectos AS up
        JOIN public.conterreno_proyectos AS cp
          ON cp.id = up.proyecto_id AND cp.activo = TRUE
        JOIN public.usuarios AS u ON u.id_usuario = up.usuario_auth_id
        WHERE up.proyecto_id = p_proyecto_id
          AND up.usuario_auth_id = auth.uid()
          AND up.activo = TRUE
          AND u.activo = TRUE
          AND u.bloqueado = FALSE
    );
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_tiene_permiso(
    p_proyecto_id TEXT,
    p_codigo_permiso TEXT
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.conterreno_usuarios_proyectos AS up
        JOIN public.conterreno_proyectos AS cp
          ON cp.id = up.proyecto_id AND cp.activo = TRUE
        JOIN public.usuarios AS u ON u.id_usuario = up.usuario_auth_id
        JOIN public.roles AS r ON r.id_rol = u.id_rol
        JOIN public.rol_permisos AS rp ON rp.id_rol = r.id_rol
        JOIN public.permisos AS p ON p.id_permiso = rp.id_permiso
        WHERE up.proyecto_id = p_proyecto_id
          AND up.usuario_auth_id = auth.uid()
          AND up.activo = TRUE
          AND u.activo = TRUE
          AND u.bloqueado = FALSE
          AND r.activo = TRUE
          AND p.codigo_permiso = p_codigo_permiso
    );
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_es_administrador()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.usuarios AS u
        JOIN public.roles AS r ON r.id_rol = u.id_rol
        WHERE u.id_usuario = auth.uid()
          AND u.activo = TRUE
          AND u.bloqueado = FALSE
          AND r.codigo_rol = 'ADMIN_GENERAL'
          AND r.activo = TRUE
    );
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_admin_crear_proyecto(
    p_id TEXT,
    p_nombre TEXT
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

    INSERT INTO public.conterreno_proyectos (id, nombre)
    VALUES (lower(trim(p_id)), trim(p_nombre));

    INSERT INTO public.auditoria_usuarios (
        tabla_afectada, operacion, id_usuario_ejecutor, datos_nuevos
    )
    VALUES (
        'conterreno_proyectos', 'CREACION_OBRA', auth.uid(),
        jsonb_build_object('proyecto_id', lower(trim(p_id)), 'nombre', trim(p_nombre))
    );
    RETURN lower(trim(p_id));
END;
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_admin_actualizar_proyecto(
    p_id TEXT,
    p_nombre TEXT,
    p_activo BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_nombre_anterior TEXT;
    v_activo_anterior BOOLEAN;
BEGIN
    IF NOT public.fn_conterreno_es_administrador() THEN
        RAISE EXCEPTION 'Solo el Administrador del sistema puede actualizar obras.';
    END IF;
    IF p_nombre IS NULL OR length(trim(p_nombre)) < 3 OR p_activo IS NULL THEN
        RAISE EXCEPTION 'Nombre o estado de obra no válido.';
    END IF;

    SELECT nombre, activo INTO v_nombre_anterior, v_activo_anterior
    FROM public.conterreno_proyectos
    WHERE id = p_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La obra solicitada no existe.';
    END IF;

    UPDATE public.conterreno_proyectos
    SET nombre = trim(p_nombre), activo = p_activo
    WHERE id = p_id;

    INSERT INTO public.auditoria_usuarios (
        tabla_afectada, operacion, id_usuario_ejecutor,
        datos_anteriores, datos_nuevos
    )
    VALUES (
        'conterreno_proyectos', 'ACTUALIZACION_OBRA', auth.uid(),
        jsonb_build_object('proyecto_id', p_id, 'nombre', v_nombre_anterior, 'activo', v_activo_anterior),
        jsonb_build_object('proyecto_id', p_id, 'nombre', trim(p_nombre), 'activo', p_activo)
    );
END;
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_admin_crear_perfil(
    p_id_usuario UUID,
    p_rut TEXT,
    p_nombres TEXT,
    p_apellidos TEXT,
    p_email TEXT,
    p_cargo TEXT,
    p_codigo_rol TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_id_rol INT;
BEGIN
    IF NOT public.fn_conterreno_es_administrador() THEN
        RAISE EXCEPTION 'Solo el Administrador del sistema puede crear perfiles.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM auth.users AS au
        WHERE au.id = p_id_usuario
          AND lower(au.email) = lower(trim(p_email))
    ) THEN
        RAISE EXCEPTION 'Primero crea la cuenta Auth y usa exactamente su correo.';
    END IF;

    SELECT id_rol INTO v_id_rol
    FROM public.roles
    WHERE codigo_rol = p_codigo_rol AND activo = TRUE;
    IF v_id_rol IS NULL THEN
        RAISE EXCEPTION 'El rol solicitado no existe o está inactivo.';
    END IF;

    INSERT INTO public.usuarios (
        id_usuario, rut, nombres, apellidos, email, cargo_contrato, id_rol
    )
    VALUES (
        p_id_usuario, trim(p_rut), trim(p_nombres), trim(p_apellidos),
        lower(trim(p_email)), trim(p_cargo), v_id_rol
    );
    RETURN p_id_usuario;
END;
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_admin_asignar_proyecto(
    p_id_usuario UUID,
    p_proyecto_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT public.fn_conterreno_es_administrador() THEN
        RAISE EXCEPTION 'Solo el Administrador del sistema puede asignar usuarios a obras.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.usuarios
        WHERE id_usuario = p_id_usuario AND activo = TRUE AND bloqueado = FALSE
    ) OR NOT EXISTS (
        SELECT 1 FROM public.conterreno_proyectos
        WHERE id = p_proyecto_id AND activo = TRUE
    ) THEN
        RAISE EXCEPTION 'Usuario o proyecto inexistente/inactivo.';
    END IF;

    INSERT INTO public.conterreno_usuarios_proyectos (proyecto_id, usuario_auth_id)
    VALUES (p_proyecto_id, p_id_usuario)
    ON CONFLICT (proyecto_id, usuario_auth_id)
    DO UPDATE SET activo = TRUE;

    INSERT INTO public.auditoria_usuarios (
        tabla_afectada, id_usuario_afectado, operacion,
        id_usuario_ejecutor, datos_nuevos
    )
    VALUES (
        'conterreno_usuarios_proyectos', p_id_usuario, 'ASIGNACION_PROYECTO',
        auth.uid(), jsonb_build_object('proyecto_id', p_proyecto_id)
    );
END;
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_admin_desactivar_asignacion(
    p_id_usuario UUID,
    p_proyecto_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT public.fn_conterreno_es_administrador() THEN
        RAISE EXCEPTION 'Solo el Administrador del sistema puede desactivar asignaciones.';
    END IF;
    IF p_id_usuario = auth.uid() THEN
        RAISE EXCEPTION 'No puedes retirar tu propia asignación.';
    END IF;

    UPDATE public.conterreno_usuarios_proyectos
    SET activo = FALSE
    WHERE usuario_auth_id = p_id_usuario AND proyecto_id = p_proyecto_id AND activo = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe una asignación activa para ese usuario y obra.';
    END IF;

    INSERT INTO public.auditoria_usuarios (
        tabla_afectada, id_usuario_afectado, operacion,
        id_usuario_ejecutor, datos_nuevos
    )
    VALUES (
        'conterreno_usuarios_proyectos', p_id_usuario, 'DESACTIVACION_PROYECTO',
        auth.uid(), jsonb_build_object('proyecto_id', p_proyecto_id)
    );
END;
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_admin_desactivar_usuario(
    p_id_usuario UUID,
    p_motivo TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT public.fn_conterreno_es_administrador() THEN
        RAISE EXCEPTION 'Solo el Administrador del sistema puede desactivar usuarios.';
    END IF;
    IF p_id_usuario = auth.uid() THEN
        RAISE EXCEPTION 'No puedes desactivar tu propia cuenta.';
    END IF;
    IF p_motivo IS NULL OR length(trim(p_motivo)) < 5 THEN
        RAISE EXCEPTION 'Debes registrar el motivo de desactivación.';
    END IF;

    UPDATE public.usuarios
    SET activo = FALSE, bloqueado = TRUE
    WHERE id_usuario = p_id_usuario AND activo = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El usuario no existe o ya está desactivado.';
    END IF;

    UPDATE public.conterreno_usuarios_proyectos
    SET activo = FALSE
    WHERE usuario_auth_id = p_id_usuario AND activo = TRUE;

    INSERT INTO public.auditoria_usuarios (
        tabla_afectada, id_usuario_afectado, operacion,
        id_usuario_ejecutor, datos_nuevos
    )
    VALUES (
        'usuarios', p_id_usuario, 'DESACTIVACION_USUARIO',
        auth.uid(), jsonb_build_object('motivo', trim(p_motivo))
    );
END;
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_crear_herramienta(
    p_proyecto_id TEXT,
    p_codigo_tag_iot TEXT,
    p_numero_serie TEXT,
    p_nombre TEXT,
    p_descripcion TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_id_equipo UUID;
BEGIN
    IF NOT public.fn_conterreno_tiene_permiso(p_proyecto_id, 'HERRAMIENTA_CREAR') THEN
        RAISE EXCEPTION 'No tienes permiso para registrar herramientas en esta obra.';
    END IF;

    INSERT INTO public.equipos_herramientas (
        proyecto_id, codigo_tag_iot, numero_serie, nombre, descripcion
    )
    VALUES (
        p_proyecto_id, upper(trim(p_codigo_tag_iot)), trim(p_numero_serie),
        trim(p_nombre), NULLIF(trim(p_descripcion), '')
    )
    RETURNING id_equipo INTO v_id_equipo;

    INSERT INTO public.kardex_transaccional (
        modulo, proyecto_id, codigo_operacion, id_usuario_ejecutor,
        id_registro_referencia, payload_jsonb
    )
    VALUES (
        'BODEGA_IOT', p_proyecto_id, 'HERRAMIENTA_CREADA', auth.uid(),
        v_id_equipo::TEXT,
        jsonb_build_object('id_equipo', v_id_equipo, 'tag', upper(trim(p_codigo_tag_iot)))
    );
    RETURN v_id_equipo;
END;
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_listar_trabajadores(p_proyecto_id TEXT)
RETURNS TABLE (id_usuario UUID, nombre_completo TEXT, rut TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT public.fn_conterreno_tiene_permiso(p_proyecto_id, 'PRESTAMO_REGISTRAR') THEN
        RAISE EXCEPTION 'No tienes permiso para consultar trabajadores de esta obra.';
    END IF;

    RETURN QUERY
    SELECT u.id_usuario,
           trim(u.nombres || ' ' || u.apellidos)::TEXT,
           u.rut::TEXT
    FROM public.conterreno_usuarios_proyectos AS up
    JOIN public.usuarios AS u ON u.id_usuario = up.usuario_auth_id
    JOIN public.roles AS r ON r.id_rol = u.id_rol
    WHERE up.proyecto_id = p_proyecto_id
      AND up.activo = TRUE
      AND u.activo = TRUE
      AND u.bloqueado = FALSE
      AND r.codigo_rol = 'OPERARIO_MAESTRO'
      AND r.activo = TRUE
    ORDER BY u.apellidos, u.nombres;
END;
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_actualizar_herramienta(
    p_proyecto_id TEXT,
    p_id_equipo UUID,
    p_nombre TEXT,
    p_descripcion TEXT,
    p_estado_fisico TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_disponible BOOLEAN;
BEGIN
    IF NOT public.fn_conterreno_tiene_permiso(p_proyecto_id, 'HERRAMIENTA_ACTUALIZAR') THEN
        RAISE EXCEPTION 'No tienes permiso para actualizar herramientas en esta obra.';
    END IF;
    IF p_estado_fisico NOT IN ('OPTIMO', 'DANIADO', 'EN_MANTENCION', 'DADO_DE_BAJA') THEN
        RAISE EXCEPTION 'Estado físico de herramienta no válido.';
    END IF;

    UPDATE public.equipos_herramientas AS e
    SET nombre = trim(p_nombre),
        descripcion = NULLIF(trim(p_descripcion), ''),
        estado_fisico = p_estado_fisico,
        disponible = (
            p_estado_fisico = 'OPTIMO'
            AND NOT EXISTS (
                SELECT 1 FROM public.prestamos AS pr
                WHERE pr.id_equipo = e.id_equipo
                  AND pr.fecha_hora_devolucion IS NULL
            )
        )
    WHERE e.id_equipo = p_id_equipo
      AND e.proyecto_id = p_proyecto_id
      AND e.activo = TRUE
    RETURNING e.disponible INTO v_disponible;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Herramienta no encontrada en esta obra.';
    END IF;

    INSERT INTO public.kardex_transaccional (
        modulo, proyecto_id, codigo_operacion, id_usuario_ejecutor,
        id_registro_referencia, payload_jsonb
    )
    VALUES (
        'BODEGA_IOT', p_proyecto_id, 'HERRAMIENTA_ACTUALIZADA', auth.uid(),
        p_id_equipo::TEXT,
        jsonb_build_object('id_equipo', p_id_equipo, 'estado_fisico', p_estado_fisico, 'disponible', v_disponible)
    );
END;
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_registrar_prestamo(
    p_proyecto_id TEXT,
    p_id_equipo UUID,
    p_id_trabajador UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_id_prestamo UUID;
BEGIN
    IF NOT public.fn_conterreno_tiene_permiso(p_proyecto_id, 'PRESTAMO_REGISTRAR') THEN
        RAISE EXCEPTION 'Solo el bodeguero asignado puede registrar el préstamo.';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM public.conterreno_usuarios_proyectos AS up
        JOIN public.usuarios AS u ON u.id_usuario = up.usuario_auth_id
        JOIN public.roles AS r ON r.id_rol = u.id_rol
        WHERE up.proyecto_id = p_proyecto_id
          AND up.usuario_auth_id = p_id_trabajador
          AND up.activo = TRUE AND u.activo = TRUE AND u.bloqueado = FALSE
          AND r.codigo_rol = 'OPERARIO_MAESTRO' AND r.activo = TRUE
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
        proyecto_id, id_equipo, id_trabajador, id_bodeguero
    )
    VALUES (p_proyecto_id, p_id_equipo, p_id_trabajador, auth.uid())
    RETURNING id_prestamo INTO v_id_prestamo;

    INSERT INTO public.kardex_transaccional (
        modulo, proyecto_id, codigo_operacion, id_usuario_ejecutor,
        id_registro_referencia, payload_jsonb
    )
    VALUES (
        'BODEGA_IOT', p_proyecto_id, 'PRESTAMO_REGISTRADO', auth.uid(),
        v_id_prestamo::TEXT,
        jsonb_build_object('id_prestamo', v_id_prestamo, 'id_equipo', p_id_equipo, 'id_trabajador', p_id_trabajador)
    );
    RETURN v_id_prestamo;
END;
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_confirmar_prestamo(
    p_id_prestamo UUID,
    p_firma_storage_path TEXT,
    p_firma_sha256 TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_prestamo public.prestamos%ROWTYPE;
BEGIN
    SELECT * INTO v_prestamo
    FROM public.prestamos
    WHERE id_prestamo = p_id_prestamo
    FOR UPDATE;

    IF NOT FOUND OR v_prestamo.id_trabajador <> auth.uid()
       OR v_prestamo.estado_devolucion <> 'PENDIENTE_FIRMA' THEN
        RAISE EXCEPTION 'El préstamo no está pendiente de firma para este trabajador.';
    END IF;
    IF NOT public.fn_conterreno_es_miembro(v_prestamo.proyecto_id) THEN
        RAISE EXCEPTION 'El trabajador no tiene una asignación activa en esta obra.';
    END IF;
    IF p_firma_storage_path IS NULL
       OR left(
           p_firma_storage_path,
           length(v_prestamo.proyecto_id || '/' || auth.uid()::TEXT || '/')
       ) <> v_prestamo.proyecto_id || '/' || auth.uid()::TEXT || '/'
       OR p_firma_sha256 IS NULL
       OR p_firma_sha256 !~ '^[0-9a-f]{64}$'
       OR NOT EXISTS (
           SELECT 1 FROM storage.objects AS so
           WHERE so.bucket_id = 'conterreno-evidencias'
             AND so.name = p_firma_storage_path
       ) THEN
        RAISE EXCEPTION 'La ruta o el hash de la firma no es válido.';
    END IF;

    UPDATE public.prestamos
    SET firma_storage_path = p_firma_storage_path,
        firma_digital_hash = p_firma_sha256,
        estado_devolucion = 'PENDIENTE'
    WHERE id_prestamo = p_id_prestamo;

    INSERT INTO public.kardex_transaccional (
        modulo, proyecto_id, codigo_operacion, id_usuario_ejecutor,
        id_registro_referencia, payload_jsonb
    )
    VALUES (
        'EVIDENCIAS_TERRENO', v_prestamo.proyecto_id, 'PRESTAMO_FIRMADO', auth.uid(),
        p_id_prestamo::TEXT,
        jsonb_build_object('id_prestamo', p_id_prestamo, 'firma_sha256', p_firma_sha256)
    );
END;
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_registrar_devolucion(
    p_id_prestamo UUID,
    p_estado_devolucion TEXT,
    p_evidencia_storage_path TEXT DEFAULT NULL,
    p_observacion TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_prestamo public.prestamos%ROWTYPE;
BEGIN
    SELECT * INTO v_prestamo
    FROM public.prestamos
    WHERE id_prestamo = p_id_prestamo
    FOR UPDATE;

    IF NOT FOUND OR v_prestamo.fecha_hora_devolucion IS NOT NULL
       OR v_prestamo.estado_devolucion <> 'PENDIENTE' THEN
        RAISE EXCEPTION 'El préstamo no está firmado o ya fue devuelto.';
    END IF;
    IF NOT public.fn_conterreno_tiene_permiso(v_prestamo.proyecto_id, 'DEVOLUCION_REGISTRAR') THEN
        RAISE EXCEPTION 'Solo el bodeguero asignado puede registrar la devolución.';
    END IF;
    IF p_estado_devolucion NOT IN ('DEVUELTO_OK', 'DEVUELTO_CON_DANOS') THEN
        RAISE EXCEPTION 'Estado de devolución no válido.';
    END IF;
    IF p_estado_devolucion = 'DEVUELTO_CON_DANOS'
       AND (p_evidencia_storage_path IS NULL OR length(trim(p_evidencia_storage_path)) = 0) THEN
        RAISE EXCEPTION 'Se requiere evidencia fotográfica cuando la devolución presenta daños.';
    END IF;
    IF p_evidencia_storage_path IS NOT NULL AND (
        left(
            p_evidencia_storage_path,
            length(v_prestamo.proyecto_id || '/' || auth.uid()::TEXT || '/')
        ) <> v_prestamo.proyecto_id || '/' || auth.uid()::TEXT || '/'
        OR NOT EXISTS (
            SELECT 1 FROM storage.objects AS so
            WHERE so.bucket_id = 'conterreno-evidencias'
              AND so.name = p_evidencia_storage_path
        )
    ) THEN
        RAISE EXCEPTION 'La ruta de evidencia no corresponde a una foto cargada por este bodeguero.';
    END IF;

    UPDATE public.prestamos
    SET fecha_hora_devolucion = CURRENT_TIMESTAMP,
        estado_devolucion = p_estado_devolucion,
        id_bodeguero_recepcion = auth.uid(),
        evidencia_devolucion_storage_path = p_evidencia_storage_path,
        observacion_devolucion = NULLIF(trim(p_observacion), '')
    WHERE id_prestamo = p_id_prestamo;

    UPDATE public.equipos_herramientas
    SET estado_fisico = CASE WHEN p_estado_devolucion = 'DEVUELTO_OK' THEN 'OPTIMO' ELSE 'DANIADO' END,
        disponible = (p_estado_devolucion = 'DEVUELTO_OK')
    WHERE id_equipo = v_prestamo.id_equipo
      AND proyecto_id = v_prestamo.proyecto_id;

    INSERT INTO public.kardex_transaccional (
        modulo, proyecto_id, codigo_operacion, id_usuario_ejecutor,
        id_registro_referencia, payload_jsonb
    )
    VALUES (
        'BODEGA_IOT', v_prestamo.proyecto_id, 'DEVOLUCION_REGISTRADA', auth.uid(),
        p_id_prestamo::TEXT,
        jsonb_build_object(
            'id_prestamo', p_id_prestamo,
            'id_equipo', v_prestamo.id_equipo,
            'estado_devolucion', p_estado_devolucion,
            'evidencia_storage_path', p_evidencia_storage_path
        )
    );
END;
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_actualizar_alerta_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.stock_minimo > 0 AND NEW.cantidad <= NEW.stock_minimo THEN
        INSERT INTO public.conterreno_alertas_stock (
            proyecto_id, material_id, cantidad_actual, stock_minimo
        )
        VALUES (
            NEW.proyecto_id, NEW.material_id, NEW.cantidad, NEW.stock_minimo
        )
        ON CONFLICT (proyecto_id, material_id) WHERE estado = 'ACTIVA'
        DO UPDATE SET cantidad_actual = EXCLUDED.cantidad_actual,
                      stock_minimo = EXCLUDED.stock_minimo;
    ELSE
        UPDATE public.conterreno_alertas_stock
        SET estado = 'RESUELTA', resuelta_en = CURRENT_TIMESTAMP
        WHERE proyecto_id = NEW.proyecto_id
          AND material_id = NEW.material_id
          AND estado = 'ACTIVA';
    END IF;
    NEW.actualizado_en := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_conterreno_alerta_stock ON conterreno_stock_materiales;
CREATE TRIGGER trg_conterreno_alerta_stock
    BEFORE INSERT OR UPDATE ON conterreno_stock_materiales
    FOR EACH ROW EXECUTE FUNCTION fn_conterreno_actualizar_alerta_stock();

DROP TRIGGER IF EXISTS trg_conterreno_movimientos_materiales_inalterables ON conterreno_movimientos_materiales;
CREATE TRIGGER trg_conterreno_movimientos_materiales_inalterables
    BEFORE UPDATE OR DELETE ON conterreno_movimientos_materiales
    FOR EACH ROW EXECUTE FUNCTION fn_bloquear_modificacion_worm();
DROP TRIGGER IF EXISTS trg_conterreno_movimientos_materiales_no_truncate ON conterreno_movimientos_materiales;
CREATE TRIGGER trg_conterreno_movimientos_materiales_no_truncate
    BEFORE TRUNCATE ON conterreno_movimientos_materiales
    FOR EACH STATEMENT EXECUTE FUNCTION fn_bloquear_modificacion_worm();

CREATE OR REPLACE FUNCTION fn_conterreno_bodeguero_crear_material(
    p_proyecto_id TEXT,
    p_codigo TEXT,
    p_nombre TEXT,
    p_unidad TEXT,
    p_stock_minimo NUMERIC
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_id_material UUID;
    v_nombre_existente TEXT;
    v_unidad_existente TEXT;
    v_material_activo BOOLEAN;
BEGIN
    IF NOT public.fn_conterreno_tiene_permiso(p_proyecto_id, 'MATERIAL_CATALOGO_GESTIONAR') THEN
        RAISE EXCEPTION 'No tienes permiso para mantener el catálogo de materiales en esta obra.';
    END IF;
    IF p_codigo IS NULL OR length(trim(p_codigo)) < 2
       OR p_nombre IS NULL OR length(trim(p_nombre)) < 2
       OR p_unidad IS NULL OR length(trim(p_unidad)) < 1
       OR p_stock_minimo IS NULL OR p_stock_minimo < 0 THEN
        RAISE EXCEPTION 'Código, nombre, unidad y stock mínimo son obligatorios y válidos.';
    END IF;

    SELECT id, nombre, unidad, activo
    INTO v_id_material, v_nombre_existente, v_unidad_existente, v_material_activo
    FROM public.conterreno_catalogo_materiales
    WHERE codigo = upper(trim(p_codigo));
    IF v_id_material IS NULL THEN
        INSERT INTO public.conterreno_catalogo_materiales (codigo, nombre, unidad)
        VALUES (upper(trim(p_codigo)), trim(p_nombre), trim(p_unidad))
        RETURNING id INTO v_id_material;
    ELSIF NOT v_material_activo THEN
        RAISE EXCEPTION 'El código de material ya está inactivo y no puede reutilizarse.';
    ELSIF v_nombre_existente <> trim(p_nombre) OR v_unidad_existente <> trim(p_unidad) THEN
        RAISE EXCEPTION 'El código de material ya existe con otro nombre o unidad.';
    END IF;
    INSERT INTO public.conterreno_stock_materiales (
        proyecto_id, material_id, cantidad, stock_minimo
    )
    VALUES (p_proyecto_id, v_id_material, 0, p_stock_minimo);
    RETURN v_id_material;
END;
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_bodeguero_ajustar_stock(
    p_proyecto_id TEXT,
    p_material_id UUID,
    p_tipo TEXT,
    p_cantidad NUMERIC,
    p_stock_minimo NUMERIC,
    p_motivo TEXT
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_cantidad_anterior NUMERIC(12, 2);
    v_cantidad_nueva NUMERIC(12, 2);
    v_cantidad_movimiento NUMERIC(12, 2);
BEGIN
    IF NOT public.fn_conterreno_tiene_permiso(
        p_proyecto_id, 'MATERIAL_CATALOGO_GESTIONAR'
    ) THEN
        RAISE EXCEPTION 'No tienes permiso para actualizar existencias en esta obra.';
    END IF;
    IF p_tipo IS NULL OR p_tipo NOT IN ('ENTRADA', 'SALIDA', 'AJUSTE')
       OR p_cantidad IS NULL OR p_cantidad <= 0
       OR p_stock_minimo IS NULL OR p_stock_minimo < 0
       OR p_motivo IS NULL OR length(trim(p_motivo)) < 3 THEN
        RAISE EXCEPTION 'Tipo, cantidad, mínimo o motivo del movimiento no válido.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.conterreno_catalogo_materiales
        WHERE id = p_material_id AND activo = TRUE
    ) THEN
        RAISE EXCEPTION 'Material inexistente o inactivo.';
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(p_proyecto_id || ':' || p_material_id::TEXT, 0)
    );
    SELECT cantidad INTO v_cantidad_anterior
    FROM public.conterreno_stock_materiales
    WHERE proyecto_id = p_proyecto_id AND material_id = p_material_id
    FOR UPDATE;
    v_cantidad_anterior := COALESCE(v_cantidad_anterior, 0);

    v_cantidad_nueva := CASE p_tipo
        WHEN 'ENTRADA' THEN v_cantidad_anterior + p_cantidad
        WHEN 'SALIDA' THEN v_cantidad_anterior - p_cantidad
        ELSE p_cantidad
    END;
    IF v_cantidad_nueva < 0 THEN
        RAISE EXCEPTION 'La salida excede el stock disponible.';
    END IF;
    v_cantidad_movimiento := abs(v_cantidad_nueva - v_cantidad_anterior);
    IF v_cantidad_movimiento = 0 THEN
        RAISE EXCEPTION 'El movimiento no cambia la existencia actual.';
    END IF;

    INSERT INTO public.conterreno_stock_materiales (
        proyecto_id, material_id, cantidad, stock_minimo, actualizado_por
    )
    VALUES (
        p_proyecto_id, p_material_id, v_cantidad_nueva, p_stock_minimo, auth.uid()
    )
    ON CONFLICT (proyecto_id, material_id)
    DO UPDATE SET cantidad = EXCLUDED.cantidad,
                  stock_minimo = EXCLUDED.stock_minimo,
                  actualizado_por = auth.uid();

    INSERT INTO public.conterreno_movimientos_materiales (
        proyecto_id, material_id, tipo, cantidad, motivo, ejecutado_por
    )
    VALUES (
        p_proyecto_id, p_material_id, p_tipo, v_cantidad_movimiento, trim(p_motivo), auth.uid()
    );
    INSERT INTO public.kardex_transaccional (
        modulo, proyecto_id, codigo_operacion, id_usuario_ejecutor,
        id_registro_referencia, payload_jsonb
    )
    VALUES (
        'BODEGA_IOT', p_proyecto_id, 'MATERIAL_STOCK_' || p_tipo, auth.uid(),
        p_material_id::TEXT,
        jsonb_build_object(
            'material_id', p_material_id,
            'tipo', p_tipo,
            'cantidad_anterior', v_cantidad_anterior,
            'cantidad_nueva', v_cantidad_nueva,
            'motivo', trim(p_motivo)
        )
    );
    RETURN v_cantidad_nueva;
END;
$$;

CREATE OR REPLACE FUNCTION fn_conterreno_generar_reporte_prestamos_diario()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_proyecto RECORD;
    v_fecha DATE := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Santiago')::DATE;
    v_pendientes JSONB;
    v_total INTEGER;
    v_generados INTEGER := 0;
BEGIN
    FOR v_proyecto IN
        SELECT id FROM public.conterreno_proyectos WHERE activo = TRUE
    LOOP
        SELECT count(*)::INTEGER,
               COALESCE(
                   jsonb_agg(
                       jsonb_build_object(
                           'id_prestamo', pr.id_prestamo,
                           'id_equipo', pr.id_equipo,
                           'herramienta', e.nombre,
                           'id_trabajador', pr.id_trabajador,
                           'trabajador', trim(u.nombres || ' ' || u.apellidos),
                           'rut_trabajador', u.rut,
                           'fecha_hora_salida', pr.fecha_hora_salida,
                           'estado', pr.estado_devolucion
                       ) ORDER BY pr.fecha_hora_salida
                   ),
                   '[]'::JSONB
               )
        INTO v_total, v_pendientes
        FROM public.prestamos AS pr
        JOIN public.equipos_herramientas AS e ON e.id_equipo = pr.id_equipo
        JOIN public.usuarios AS u ON u.id_usuario = pr.id_trabajador
        WHERE pr.proyecto_id = v_proyecto.id
          AND pr.fecha_hora_devolucion IS NULL;

        INSERT INTO public.conterreno_reportes_prestamos_diarios (
            proyecto_id, fecha_reporte, total_pendientes, prestamos_pendientes
        )
        VALUES (v_proyecto.id, v_fecha, v_total, v_pendientes)
        ON CONFLICT (proyecto_id, fecha_reporte)
        DO UPDATE SET total_pendientes = EXCLUDED.total_pendientes,
                      prestamos_pendientes = EXCLUDED.prestamos_pendientes,
                      generado_en = CURRENT_TIMESTAMP;
        v_generados := v_generados + 1;
    END LOOP;
    RETURN v_generados;
END;
$$;

-- RLS por proyecto y permiso. Las tablas de identidad/seguridad no quedan
-- disponibles para la API hasta tener una política explícita.
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE permisos ENABLE ROW LEVEL SECURITY;
ALTER TABLE rol_permisos ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE conterreno_proyectos ENABLE ROW LEVEL SECURITY;
ALTER TABLE conterreno_usuarios_proyectos ENABLE ROW LEVEL SECURITY;
ALTER TABLE conterreno_incidencias ENABLE ROW LEVEL SECURITY;
ALTER TABLE conterreno_tareas ENABLE ROW LEVEL SECURITY;
ALTER TABLE conterreno_pedidos_materiales ENABLE ROW LEVEL SECURITY;
ALTER TABLE conterreno_catalogo_materiales ENABLE ROW LEVEL SECURITY;
ALTER TABLE conterreno_stock_materiales ENABLE ROW LEVEL SECURITY;
ALTER TABLE conterreno_movimientos_materiales ENABLE ROW LEVEL SECURITY;
ALTER TABLE conterreno_alertas_stock ENABLE ROW LEVEL SECURITY;
ALTER TABLE conterreno_reportes_prestamos_diarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE marcajes_asistencia ENABLE ROW LEVEL SECURITY;
ALTER TABLE equipos_herramientas ENABLE ROW LEVEL SECURITY;
ALTER TABLE prestamos ENABLE ROW LEVEL SECURITY;
ALTER TABLE kardex_transaccional ENABLE ROW LEVEL SECURITY;
ALTER TABLE auditoria_usuarios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS usuarios_select_propios ON usuarios;
CREATE POLICY usuarios_select_propios ON usuarios
    FOR SELECT TO authenticated USING (id_usuario = auth.uid());
DROP POLICY IF EXISTS usuarios_select_administrador ON usuarios;
CREATE POLICY usuarios_select_administrador ON usuarios
    FOR SELECT TO authenticated USING (fn_conterreno_es_administrador());
DROP POLICY IF EXISTS roles_select_autenticado ON roles;
CREATE POLICY roles_select_autenticado ON roles
    FOR SELECT TO authenticated USING (activo = TRUE);

DROP POLICY IF EXISTS conterreno_proyectos_select_miembro ON conterreno_proyectos;
CREATE POLICY conterreno_proyectos_select_miembro ON conterreno_proyectos
    FOR SELECT TO authenticated USING (
        fn_conterreno_es_administrador()
        OR (activo = TRUE AND fn_conterreno_es_miembro(id))
    );
DROP POLICY IF EXISTS conterreno_membresias_select_propias ON conterreno_usuarios_proyectos;
CREATE POLICY conterreno_membresias_select_propias ON conterreno_usuarios_proyectos
    FOR SELECT TO authenticated USING (usuario_auth_id = auth.uid() AND activo = TRUE);

DROP POLICY IF EXISTS equipos_select_permiso ON equipos_herramientas;
CREATE POLICY equipos_select_permiso ON equipos_herramientas
    FOR SELECT TO authenticated
    USING (activo = TRUE AND fn_conterreno_tiene_permiso(proyecto_id, 'INVENTARIO_CONSULTAR'));

DROP POLICY IF EXISTS prestamos_select_autorizado ON prestamos;
CREATE POLICY prestamos_select_autorizado ON prestamos
    FOR SELECT TO authenticated
    USING (
        id_trabajador = auth.uid()
        OR fn_conterreno_tiene_permiso(proyecto_id, 'PRESTAMOS_CONSULTAR_OBRA')
        OR fn_conterreno_tiene_permiso(proyecto_id, 'REPORTE_PENDIENTES_CONSULTAR')
    );

DROP POLICY IF EXISTS kardex_select_autorizado ON kardex_transaccional;
CREATE POLICY kardex_select_autorizado ON kardex_transaccional
    FOR SELECT TO authenticated
    USING (fn_conterreno_tiene_permiso(proyecto_id, 'KARDEX_CONSULTAR'));

DROP POLICY IF EXISTS auditoria_select_administrador ON auditoria_usuarios;
CREATE POLICY auditoria_select_administrador ON auditoria_usuarios
    FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM public.usuarios AS u
        JOIN public.roles AS r ON r.id_rol = u.id_rol
        WHERE u.id_usuario = auth.uid()
          AND u.activo = TRUE AND u.bloqueado = FALSE
          AND r.codigo_rol = 'ADMIN_GENERAL' AND r.activo = TRUE
    ));

DROP POLICY IF EXISTS conterreno_incidencias_select_miembro ON conterreno_incidencias;
CREATE POLICY conterreno_incidencias_select_miembro ON conterreno_incidencias
    FOR SELECT TO authenticated USING (fn_conterreno_es_miembro(proyecto_id));
DROP POLICY IF EXISTS conterreno_incidencias_insert_reportante ON conterreno_incidencias;
CREATE POLICY conterreno_incidencias_insert_reportante ON conterreno_incidencias
    FOR INSERT TO authenticated
    WITH CHECK (
        creado_por = auth.uid()
        AND (
            fn_conterreno_tiene_permiso(proyecto_id, 'INCIDENCIA_REGISTRAR')
            OR fn_conterreno_tiene_permiso(proyecto_id, 'INCIDENCIA_GESTIONAR')
        )
    );
DROP POLICY IF EXISTS conterreno_incidencias_update_jefatura ON conterreno_incidencias;
CREATE POLICY conterreno_incidencias_update_jefatura ON conterreno_incidencias
    FOR UPDATE TO authenticated
    USING (fn_conterreno_tiene_permiso(proyecto_id, 'INCIDENCIA_GESTIONAR'))
    WITH CHECK (fn_conterreno_tiene_permiso(proyecto_id, 'INCIDENCIA_GESTIONAR'));

DROP POLICY IF EXISTS conterreno_tareas_select_miembro ON conterreno_tareas;
CREATE POLICY conterreno_tareas_select_miembro ON conterreno_tareas
    FOR SELECT TO authenticated USING (fn_conterreno_es_miembro(proyecto_id));
DROP POLICY IF EXISTS conterreno_tareas_insert_planificador ON conterreno_tareas;
CREATE POLICY conterreno_tareas_insert_planificador ON conterreno_tareas
    FOR INSERT TO authenticated
    WITH CHECK (creado_por = auth.uid() AND fn_conterreno_tiene_permiso(proyecto_id, 'TAREA_PLANIFICAR'));
DROP POLICY IF EXISTS conterreno_tareas_update_planificador ON conterreno_tareas;
CREATE POLICY conterreno_tareas_update_planificador ON conterreno_tareas
    FOR UPDATE TO authenticated
    USING (fn_conterreno_tiene_permiso(proyecto_id, 'TAREA_PLANIFICAR'))
    WITH CHECK (fn_conterreno_tiene_permiso(proyecto_id, 'TAREA_PLANIFICAR'));
DROP POLICY IF EXISTS conterreno_tareas_delete_planificador ON conterreno_tareas;
CREATE POLICY conterreno_tareas_delete_planificador ON conterreno_tareas
    FOR DELETE TO authenticated USING (fn_conterreno_tiene_permiso(proyecto_id, 'TAREA_ELIMINAR'));

DROP POLICY IF EXISTS conterreno_pedidos_select_solicitante_bodega ON conterreno_pedidos_materiales;
CREATE POLICY conterreno_pedidos_select_solicitante_bodega ON conterreno_pedidos_materiales
    FOR SELECT TO authenticated
    USING (
        solicitado_por = auth.uid()
        OR fn_conterreno_tiene_permiso(proyecto_id, 'MATERIAL_PEDIDO_GESTIONAR')
    );
DROP POLICY IF EXISTS conterreno_pedidos_insert_solicitante ON conterreno_pedidos_materiales;
CREATE POLICY conterreno_pedidos_insert_solicitante ON conterreno_pedidos_materiales
    FOR INSERT TO authenticated
    WITH CHECK (
        solicitado_por = auth.uid()
        AND fn_conterreno_tiene_permiso(proyecto_id, 'MATERIAL_SOLICITAR')
    );
DROP POLICY IF EXISTS conterreno_pedidos_update_bodega ON conterreno_pedidos_materiales;
CREATE POLICY conterreno_pedidos_update_bodega ON conterreno_pedidos_materiales
    FOR UPDATE TO authenticated
    USING (fn_conterreno_tiene_permiso(proyecto_id, 'MATERIAL_PEDIDO_GESTIONAR'))
    WITH CHECK (fn_conterreno_tiene_permiso(proyecto_id, 'MATERIAL_PEDIDO_GESTIONAR'));

DROP POLICY IF EXISTS conterreno_catalogo_materiales_select_miembro ON conterreno_catalogo_materiales;
CREATE POLICY conterreno_catalogo_materiales_select_miembro ON conterreno_catalogo_materiales
    FOR SELECT TO authenticated
    USING (
        activo = TRUE AND EXISTS (
            SELECT 1
            FROM public.conterreno_stock_materiales AS sm
            WHERE sm.material_id = id
                  AND (
                      fn_conterreno_tiene_permiso(sm.proyecto_id, 'INVENTARIO_CONSULTAR')
                      OR fn_conterreno_es_administrador()
                  )
        )
    );
DROP POLICY IF EXISTS conterreno_stock_materiales_select_permiso ON conterreno_stock_materiales;
CREATE POLICY conterreno_stock_materiales_select_permiso ON conterreno_stock_materiales
    FOR SELECT TO authenticated
    USING (fn_conterreno_tiene_permiso(proyecto_id, 'INVENTARIO_CONSULTAR'));
DROP POLICY IF EXISTS conterreno_movimientos_materiales_select_auditor ON conterreno_movimientos_materiales;
CREATE POLICY conterreno_movimientos_materiales_select_auditor ON conterreno_movimientos_materiales
    FOR SELECT TO authenticated
    USING (fn_conterreno_tiene_permiso(proyecto_id, 'KARDEX_CONSULTAR'));
DROP POLICY IF EXISTS conterreno_alertas_stock_select_permiso ON conterreno_alertas_stock;
CREATE POLICY conterreno_alertas_stock_select_permiso ON conterreno_alertas_stock
    FOR SELECT TO authenticated
    USING (
        fn_conterreno_tiene_permiso(proyecto_id, 'ALERTA_STOCK_CONSULTAR')
        OR fn_conterreno_es_administrador()
    );
DROP POLICY IF EXISTS conterreno_reportes_pendientes_select_jefatura ON conterreno_reportes_prestamos_diarios;
CREATE POLICY conterreno_reportes_pendientes_select_jefatura ON conterreno_reportes_prestamos_diarios
    FOR SELECT TO authenticated
    USING (
        fn_conterreno_tiene_permiso(proyecto_id, 'REPORTE_PENDIENTES_CONSULTAR')
        OR fn_conterreno_es_administrador()
    );

-- Bucket privado: no se aceptan URLs públicas ni borrado de evidencias.
INSERT INTO storage.buckets (id, name, public)
VALUES ('conterreno-evidencias', 'conterreno-evidencias', FALSE)
ON CONFLICT (id) DO UPDATE SET public = FALSE;

DROP POLICY IF EXISTS conterreno_evidencias_select_miembro ON storage.objects;
CREATE POLICY conterreno_evidencias_select_miembro ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'conterreno-evidencias'
        AND fn_conterreno_es_miembro((storage.foldername(name))[1])
        AND (
            (storage.foldername(name))[2] = auth.uid()::TEXT
            OR fn_conterreno_tiene_permiso((storage.foldername(name))[1], 'PRESTAMOS_CONSULTAR_OBRA')
            OR fn_conterreno_tiene_permiso((storage.foldername(name))[1], 'REPORTE_PENDIENTES_CONSULTAR')
        )
    );
DROP POLICY IF EXISTS conterreno_evidencias_insert_autorizado ON storage.objects;
CREATE POLICY conterreno_evidencias_insert_autorizado ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'conterreno-evidencias'
        AND (storage.foldername(name))[2] = auth.uid()::TEXT
        AND (
            fn_conterreno_tiene_permiso((storage.foldername(name))[1], 'PRESTAMO_FIRMAR_PROPIO')
            OR fn_conterreno_tiene_permiso((storage.foldername(name))[1], 'DEVOLUCION_REGISTRAR')
            OR fn_conterreno_tiene_permiso((storage.foldername(name))[1], 'INCIDENCIA_REGISTRAR')
        )
    );

-- El navegador nunca recibe permisos de escritura directa para préstamos ni
-- Kardex: solo RPCs validadas pueden cambiar el estado y anexar movimientos.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON roles, usuarios, conterreno_proyectos, conterreno_usuarios_proyectos,
    equipos_herramientas, prestamos, kardex_transaccional, auditoria_usuarios,
    conterreno_incidencias, conterreno_tareas, conterreno_pedidos_materiales,
    conterreno_catalogo_materiales, conterreno_stock_materiales,
    conterreno_movimientos_materiales, conterreno_alertas_stock,
    conterreno_reportes_prestamos_diarios
TO authenticated;
GRANT INSERT (proyecto_id, titulo, sector, categoria, prioridad, estado, responsable, descripcion, foto_url, fecha_reporte)
    ON conterreno_incidencias TO authenticated;
GRANT UPDATE (estado, responsable, prioridad)
    ON conterreno_incidencias TO authenticated;
GRANT INSERT (proyecto_id, titulo, sector, responsable, estado, restriccion)
    ON conterreno_tareas TO authenticated;
GRANT UPDATE (titulo, sector, responsable, estado, restriccion)
    ON conterreno_tareas TO authenticated;
GRANT DELETE ON conterreno_tareas TO authenticated;
GRANT INSERT (proyecto_id, destino, urgencia, estado, items)
    ON conterreno_pedidos_materiales TO authenticated;
GRANT UPDATE (estado) ON conterreno_pedidos_materiales TO authenticated;

REVOKE ALL ON FUNCTION fn_conterreno_es_miembro(TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_conterreno_tiene_permiso(TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_conterreno_es_administrador() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_conterreno_es_miembro(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_conterreno_tiene_permiso(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_conterreno_es_administrador() TO authenticated;
GRANT EXECUTE ON FUNCTION fn_promover_usuario(UUID, VARCHAR, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_conterreno_admin_crear_proyecto(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_conterreno_admin_actualizar_proyecto(TEXT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_conterreno_admin_crear_perfil(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_conterreno_admin_asignar_proyecto(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_conterreno_admin_desactivar_asignacion(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_conterreno_admin_desactivar_usuario(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_conterreno_listar_trabajadores(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_conterreno_bodeguero_crear_material(TEXT, TEXT, TEXT, TEXT, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_conterreno_bodeguero_ajustar_stock(TEXT, UUID, TEXT, NUMERIC, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_conterreno_crear_herramienta(TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_conterreno_actualizar_herramienta(TEXT, UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_conterreno_registrar_prestamo(TEXT, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_conterreno_confirmar_prestamo(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_conterreno_registrar_devolucion(UUID, TEXT, TEXT, TEXT) TO authenticated;

-- Provisionamiento inicial: crear primero la cuenta en Supabase Auth; luego,
-- insertar su perfil en usuarios con el mismo UUID y asignarle una obra.
-- Los roles se asignan desde este entorno administrativo, nunca desde el cliente.
-- INSERT INTO public.usuarios (id_usuario, rut, nombres, apellidos, email, cargo_contrato, id_rol)
-- SELECT '<UUID de auth.users>', '<RUT>', '<Nombres>', '<Apellidos>', '<Correo Auth>', '<Cargo>', r.id_rol
-- FROM public.roles r WHERE r.codigo_rol = 'BODEGUERO';
-- INSERT INTO public.conterreno_usuarios_proyectos (proyecto_id, usuario_auth_id)
-- VALUES ('p1', '<UUID de auth.users>');
-- Reporte diario: habilitar pg_cron en Supabase, configurar cron.timezone como
-- America/Santiago y programar la función sin exponerla a authenticated:
-- SELECT cron.schedule(
--     'conterreno-pendientes-1800',
--     '0 18 * * *',
--     $$SELECT public.fn_conterreno_generar_reporte_prestamos_diario();$$
-- );
COMMIT;