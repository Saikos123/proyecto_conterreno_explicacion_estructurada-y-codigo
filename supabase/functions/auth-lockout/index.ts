import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "npm:@supabase/supabase-js@2/cors";

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
}

function getDefaultKey(environmentVariable: string): string | null {
    const rawKeys = Deno.env.get(environmentVariable);
    if (!rawKeys) return null;
    try {
        const keys: unknown = JSON.parse(rawKeys);
        if (typeof keys !== "object" || keys === null || !("default" in keys)) return null;
        const defaultKey = (keys as { default?: unknown }).default;
        return typeof defaultKey === "string" ? defaultKey : null;
    } catch {
        return null;
    }
}

function getClientIp(request: Request): string | null {
    const forwardedFor = request.headers.get("x-forwarded-for");
    const forwarded = request.headers.get("cf-connecting-ip")
        ?? forwardedFor?.split(",").pop()?.trim();
    if (!forwarded || forwarded.length > 64 || /[\s,]/.test(forwarded)) return null;
    return forwarded;
}

async function hashIdentifier(secret: string, value: string): Promise<string> {
    const encoder = new TextEncoder();
    const key = await crypto.subtle.importKey(
        "raw",
        encoder.encode(secret),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"],
    );
    const digest = await crypto.subtle.sign("HMAC", key, encoder.encode(value));
    return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async request => {
    if (request.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }
    if (request.method !== "POST") {
        return jsonResponse({ error: "Método no permitido." }, 405);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const publishableKey = getDefaultKey("SUPABASE_PUBLISHABLE_KEYS");
    const secretKey = getDefaultKey("SUPABASE_SECRET_KEYS");
    const hashSecret = Deno.env.get("AUTH_LOCKOUT_HASH_SECRET");
    if (!supabaseUrl || !publishableKey || !secretKey || !hashSecret || hashSecret.length < 32) {
        console.error("La función de control de acceso no está configurada.");
        return jsonResponse({ error: "El control de intentos no está disponible." }, 500);
    }

    let payload: unknown;
    try {
        payload = await request.json();
    } catch {
        return jsonResponse({ error: "El cuerpo de la solicitud debe ser JSON válido." }, 400);
    }

    if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
        return jsonResponse({ error: "El cuerpo de la solicitud debe ser un objeto JSON." }, 400);
    }
    const body = payload as Record<string, unknown>;
    const action = body.action;
    if (action !== "check" && action !== "failure" && action !== "reset") {
        return jsonResponse({ error: "Acción de autenticación no válida." }, 400);
    }

    const ipAddress = getClientIp(request);
    if (!ipAddress) {
        return jsonResponse({ error: "No se pudo determinar el origen de la solicitud; no se inició sesión." }, 503);
    }
    const ipHash = await hashIdentifier(hashSecret, ipAddress);
    const adminClient = createClient(supabaseUrl, secretKey, {
        auth: { autoRefreshToken: false, persistSession: false },
    });

    if (action === "reset") {
        const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
        if (!token) return jsonResponse({ error: "La sesión no es válida." }, 401);

        const userClient = createClient(supabaseUrl, publishableKey, {
            global: { headers: { Authorization: `Bearer ${token}` } },
            auth: { autoRefreshToken: false, persistSession: false },
        });
        const { data: userData, error: userError } = await userClient.auth.getUser(token);
        if (userError || !userData.user?.email) {
            return jsonResponse({ error: "La sesión no es válida o no contiene un correo." }, 401);
        }

        const emailHash = await hashIdentifier(hashSecret, userData.user.email.trim().toLowerCase());
        const { error } = await adminClient
            .from("conterreno_auth_intentos")
            .delete()
            .eq("email_hash", emailHash)
            .eq("ip_hash", ipHash);
        if (error) {
            console.error("No se pudo reiniciar el contador de intentos.");
            return jsonResponse({ error: "No se pudo reiniciar el contador de seguridad." }, 500);
        }
        return jsonResponse({ cleared: true });
    }

    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 150) {
        return jsonResponse({ error: "Ingresa un correo válido." }, 400);
    }
    const emailHash = await hashIdentifier(hashSecret, email);
    const { data: current, error: lookupError } = await adminClient
        .from("conterreno_auth_intentos")
        .select("intentos_fallidos,ventana_inicio,bloqueado_hasta")
        .eq("email_hash", emailHash)
        .eq("ip_hash", ipHash)
        .maybeSingle();
    if (lookupError) {
        console.error("No se pudo consultar el contador de intentos.");
        return jsonResponse({ error: "No se pudo comprobar el estado de seguridad." }, 500);
    }

    const now = Date.now();
    const blockedUntil = current?.bloqueado_hasta ? Date.parse(current.bloqueado_hasta) : 0;
    if (blockedUntil > now) {
        return jsonResponse({
            locked: true,
            remainingSeconds: Math.ceil((blockedUntil - now) / 1000),
            message: "Se alcanzó el límite de intentos. Espera 15 minutos antes de volver a intentarlo.",
        });
    }

    if (action === "check") {
        const windowStart = current?.ventana_inicio ? Date.parse(current.ventana_inicio) : 0;
        const attempts = windowStart > now - 15 * 60 * 1000 ? current?.intentos_fallidos || 0 : 0;
        return jsonResponse({ locked: false, attemptsRemaining: Math.max(0, 3 - attempts) });
    }

    const { data, error } = await adminClient.rpc("fn_conterreno_registrar_fallo_login", {
        p_email_hash: emailHash,
        p_ip_hash: ipHash,
    });
    if (error) {
        console.error("No se pudo registrar el fallo de autenticación.");
        return jsonResponse({ error: "No se pudo registrar el intento de seguridad." }, 500);
    }
    const attempt = Array.isArray(data) ? data[0] : data;
    if (!attempt) {
        console.error("El registro de intento no devolvió un resultado.");
        return jsonResponse({ error: "No se pudo registrar el intento de seguridad." }, 500);
    }

    const lockUntil = attempt.bloqueado_hasta ? Date.parse(attempt.bloqueado_hasta) : 0;
    if (lockUntil > now) {
        return jsonResponse({
            locked: true,
            remainingSeconds: Math.ceil((lockUntil - now) / 1000),
            message: "Se alcanzó el límite de intentos. Espera 15 minutos antes de volver a intentarlo.",
        });
    }
    return jsonResponse({
        locked: false,
        attemptsRemaining: Math.max(0, 3 - Number(attempt.intentos)),
    });
});
