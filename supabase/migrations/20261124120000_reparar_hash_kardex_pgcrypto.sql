BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.fn_calcular_hash_kardex(
    p_contenido JSONB
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN encode(
        extensions.digest(convert_to(p_contenido::TEXT, 'UTF8'), 'sha256'),
        'hex'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_calcular_hash_kardex(JSONB) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_generar_hash_kardex()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
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
    NEW.hash_integridad := public.fn_calcular_hash_kardex(v_contenido);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_establecer_hash_kardex()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
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
    NEW.hash_integridad := public.fn_calcular_hash_kardex(v_contenido);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_establecer_hash_kardex ON public.kardex_transaccional;
DROP TRIGGER IF EXISTS trg_kardex_hash ON public.kardex_transaccional;
CREATE TRIGGER trg_establecer_hash_kardex
    BEFORE INSERT ON public.kardex_transaccional
    FOR EACH ROW EXECUTE FUNCTION public.fn_establecer_hash_kardex();

COMMIT;
