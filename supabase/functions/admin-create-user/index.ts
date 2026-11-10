import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "npm:@supabase/supabase-js@2/cors";

function jsonResponse(body: Record<string, unknown>, status: number): Response {
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
    if (!supabaseUrl || !publishableKey || !secretKey) {
        console.error("Falta configurar URL, publishable key o secret key en el runtime de Supabase.");
        return jsonResponse({ error: "La función de administración no está configurada." }, 500);
    }

    const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
    if (!token) {
        return jsonResponse({ error: "Debes iniciar sesión como administrador." }, 401);
    }

    const userClient = createClient(supabaseUrl, publishableKey, {
        global: { headers: { Authorization: `Bearer ${token}` } },
        auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser(token);
    if (userError || !userData.user) {
        return jsonResponse({ error: "La sesión no es válida o expiró." }, 401);
    }

    const { data: isAdmin, error: permissionError } = await userClient.rpc(
        "fn_conterreno_es_administrador",
    );
    if (permissionError) {
        console.error("No se pudo validar el permiso administrativo.", permissionError);
        return jsonResponse({ error: "No se pudo validar el permiso administrativo." }, 500);
    }
    if (isAdmin !== true) {
        return jsonResponse({ error: "Solo Administración puede crear cuentas." }, 403);
    }

    let body: Record<string, unknown>;
    try {
        body = await request.json();
    } catch {
        return jsonResponse({ error: "El cuerpo de la solicitud debe ser JSON válido." }, 400);
    }

    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body.password === "string" ? body.password : "";
    const fullName = typeof body.fullName === "string" ? body.fullName.trim() : "";
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 150) {
        return jsonResponse({ error: "Ingresa un correo válido." }, 400);
    }
    if (!/^[a-f0-9]{48}$/.test(password)) {
        return jsonResponse({ error: "La contraseña generada no cumple el formato esperado." }, 400);
    }
    if (fullName.length < 2 || fullName.length > 200) {
        return jsonResponse({ error: "Ingresa el nombre completo (máximo 200 caracteres)." }, 400);
    }

    const adminClient = createClient(supabaseUrl, secretKey, {
        auth: { autoRefreshToken: false, persistSession: false },
    });
    const findExistingUser = async () => {
        for (let page = 1; page <= 100; page += 1) {
            const { data, error } = await adminClient.auth.admin.listUsers({
                page,
                perPage: 1000,
            });
            if (error) throw error;
            const existing = data.users.find(user => user.email?.toLowerCase() === email);
            if (existing) return existing;
            if (data.users.length < 1000) return null;
        }
        throw new Error("No se pudo completar la búsqueda de cuentas Auth.");
    };

    try {
        const existingUser = await findExistingUser();
        if (existingUser) {
            return jsonResponse({
                userId: existingUser.id,
                email: existingUser.email,
                alreadyExists: true,
            }, 200);
        }
    } catch (error) {
        console.error("No se pudo comprobar si la cuenta Auth ya existe.", error);
        return jsonResponse({ error: "No se pudo comprobar el estado de la cuenta en Auth." }, 500);
    }

    const { data: createdUser, error: createError } = await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name: fullName, created_by_admin: true },
    });
    if (createError) {
        try {
            const existingUser = await findExistingUser();
            if (existingUser) {
                return jsonResponse({
                    userId: existingUser.id,
                    email: existingUser.email,
                    alreadyExists: true,
                }, 200);
            }
        } catch (lookupError) {
            console.error("No se pudo verificar el resultado del alta Auth.", lookupError);
        }

        const rateLimited = createError.status === 429 ||
            /email rate limit exceeded/i.test(createError.message);
        if (rateLimited) {
            return jsonResponse({
                error: "Supabase Auth rechazó el alta por límite de correo. Este flujo no envía invitaciones; revisa Authentication > Users y los logs de Auth antes de reintentar. No vuelvas a enviar el formulario repetidamente.",
            }, 429);
        }
        return jsonResponse({ error: `No se pudo crear la cuenta: ${createError.message}` }, 400);
    }

    return jsonResponse({ userId: createdUser.user.id, email: createdUser.user.email }, 201);
});
