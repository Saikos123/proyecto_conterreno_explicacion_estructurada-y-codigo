-- Asegura la bitacora y evita que el trigger dependa del search_path de la
-- sesion que crea o actualiza perfiles.
BEGIN;

CREATE TABLE IF NOT EXISTS public.auditoria_usuarios (
    id_auditoria BIGSERIAL PRIMARY KEY,
    tabla_afectada VARCHAR(50) NOT NULL DEFAULT 'usuarios',
    id_usuario_afectado UUID REFERENCES public.usuarios(id_usuario) ON DELETE SET NULL,
    operacion VARCHAR(50) NOT NULL,
    id_usuario_ejecutor UUID REFERENCES public.usuarios(id_usuario) ON DELETE SET NULL,
    datos_anteriores JSONB,
    datos_nuevos JSONB,
    ip_origen VARCHAR(45) DEFAULT '0.0.0.0',
    agente_usuario TEXT,
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_auditoria_afectado
    ON public.auditoria_usuarios(id_usuario_afectado);
CREATE INDEX IF NOT EXISTS idx_auditoria_fecha
    ON public.auditoria_usuarios(fecha_hora DESC);

CREATE OR REPLACE FUNCTION public.fn_auditar_cambios_tabla_usuarios()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
    v_datos_anteriores JSONB;
    v_datos_nuevos JSONB;
BEGIN
    v_datos_nuevos := pg_catalog.to_jsonb(NEW);

    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.auditoria_usuarios (
            id_usuario_afectado, operacion, datos_nuevos
        )
        VALUES (NEW.id_usuario, 'INSERT', v_datos_nuevos);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        v_datos_anteriores := pg_catalog.to_jsonb(OLD);

        IF NEW.rut LIKE 'ANON-%' THEN
            v_datos_anteriores := v_datos_anteriores
                || pg_catalog.jsonb_build_object(
                    'rut', 'ANONIMIZADO_LEY_19628',
                    'nombres', 'USUARIO',
                    'apellidos', 'ANONIMIZADO',
                    'email', 'ANONIMIZADO@local',
                    'telefono', NULL
                );
        END IF;

        INSERT INTO public.auditoria_usuarios (
            id_usuario_afectado, operacion, datos_anteriores, datos_nuevos
        )
        VALUES (
            NEW.id_usuario, 'UPDATE', v_datos_anteriores, v_datos_nuevos
        );
        RETURN NEW;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_auditoria_tabla_usuarios ON public.usuarios;
CREATE TRIGGER trg_auditoria_tabla_usuarios
    AFTER INSERT OR UPDATE ON public.usuarios
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_auditar_cambios_tabla_usuarios();

ALTER TABLE public.auditoria_usuarios ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS auditoria_select_administrador
    ON public.auditoria_usuarios;
CREATE POLICY auditoria_select_administrador
    ON public.auditoria_usuarios
    FOR SELECT TO authenticated
    USING (public.fn_conterreno_es_administrador());

REVOKE ALL ON public.auditoria_usuarios FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.auditoria_usuarios TO authenticated;

COMMIT;
