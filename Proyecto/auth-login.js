(function () {
    function errorMessage(error) {
        return error && typeof error.message === 'string'
            ? error.message
            : 'No se pudo completar la comprobación de seguridad.';
    }

    async function invokeLockout(client, body) {
        const { data, error } = await client.functions.invoke('auth-lockout', { body });
        if (error) {
            const response = error.context;
            if (response instanceof Response) {
                let payload = null;
                try {
                    payload = await response.clone().json();
                } catch (parseError) {
                    if (!(parseError instanceof SyntaxError)) throw parseError;
                }
                if (typeof payload?.error === 'string') throw new Error(payload.error);
            }
            throw new Error(errorMessage(error));
        }
        if (!data || typeof data !== 'object') {
            throw new Error('El servicio de control de intentos devolvió una respuesta no válida.');
        }
        if (typeof data.error === 'string') throw new Error(data.error);
        return data;
    }

    function isInvalidCredentials(error) {
        return error?.code === 'invalid_credentials' ||
            /invalid login credentials/i.test(error?.message || '');
    }

    async function signIn(client, email, password) {
        const normalizedEmail = email.trim().toLowerCase();
        const status = await invokeLockout(client, {
            action: 'check',
            email: normalizedEmail,
        });
        if (status.locked) {
            throw new Error(status.message || 'El acceso está bloqueado temporalmente. Inténtalo más tarde.');
        }

        const { data, error } = await client.auth.signInWithPassword({
            email: normalizedEmail,
            password,
        });
        if (error) {
            if (!isInvalidCredentials(error)) {
                throw new Error(`No se pudo iniciar sesión: ${error.message}`);
            }
            const attempt = await invokeLockout(client, {
                action: 'failure',
                email: normalizedEmail,
            });
            if (attempt.locked) {
                throw new Error(attempt.message || 'Se alcanzó el límite de intentos. Espera 15 minutos.');
            }
            const remaining = Number.isInteger(attempt.attemptsRemaining)
                ? ` Quedan ${attempt.attemptsRemaining} intento(s) antes del bloqueo.`
                : '';
            throw new Error(`No se pudo iniciar sesión: ${error.message}.${remaining}`);
        }

        try {
            await invokeLockout(client, { action: 'reset' });
        } catch (resetError) {
            const { error: signOutError } = await client.auth.signOut({ scope: 'local' });
            if (signOutError) {
                throw new Error(
                    `No se pudo reiniciar el contador de seguridad (${errorMessage(resetError)}) ` +
                    `ni cerrar la sesión local (${signOutError.message}).`,
                );
            }
            throw new Error(`No se pudo confirmar el acceso seguro: ${errorMessage(resetError)}`);
        }
        return data;
    }

    window.ConTerrenoAuth = { signIn };
})();
