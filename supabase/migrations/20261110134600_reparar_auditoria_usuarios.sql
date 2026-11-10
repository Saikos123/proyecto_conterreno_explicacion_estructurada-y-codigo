-- Repara instalaciones existentes donde falta la bitácora requerida por
-- los triggers de usuarios y la RPC de aprobación de cuentas.
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

CREATE OR REPLACE FUNCTION public.fn_bloquear_modificacion_worm()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    RAISE EXCEPTION 'Los registros de auditoría y Kardex son inalterables.';
END;
$$;

DROP TRIGGER IF EXISTS trg_auditoria_inalterable ON public.auditoria_usuarios;
CREATE TRIGGER trg_auditoria_inalterable
    BEFORE UPDATE OR DELETE ON public.auditoria_usuarios
    FOR EACH ROW EXECUTE FUNCTION public.fn_bloquear_modificacion_worm();

DROP TRIGGER IF EXISTS trg_no_truncate_auditoria ON public.auditoria_usuarios;
CREATE TRIGGER trg_no_truncate_auditoria
    BEFORE TRUNCATE ON public.auditoria_usuarios
    FOR EACH STATEMENT EXECUTE FUNCTION public.fn_bloquear_modificacion_worm();

ALTER TABLE public.auditoria_usuarios ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS auditoria_select_administrador ON public.auditoria_usuarios;
CREATE POLICY auditoria_select_administrador
    ON public.auditoria_usuarios
    FOR SELECT TO authenticated
    USING (public.fn_conterreno_es_administrador());

REVOKE ALL ON public.auditoria_usuarios FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.auditoria_usuarios TO authenticated;

COMMIT;
