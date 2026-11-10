const ROLE_WORKSPACES = {
    ADMIN_GENERAL: {
        navigationLabel: 'Centro de control',
        title: 'Administración del sistema',
        description: 'Cuentas, asignaciones, obras y trazabilidad del sistema.'
    },
    JEFE_OBRA: {
        navigationLabel: 'Resumen de obra',
        title: 'Control de obra',
        description: 'Seguimiento de préstamos, alertas e información operativa de la obra.'
    },
    BODEGUERO: {
        navigationLabel: 'Operación de bodega',
        title: 'Bodega e inventario',
        description: 'Escaneo, pedidos, préstamos, devoluciones y control de existencias.'
    },
    OPERARIO_MAESTRO: {
        navigationLabel: 'Mi jornada',
        title: 'Mi espacio de trabajador',
        description: 'Tus herramientas, solicitudes y disponibilidad de materiales.'
    }
};
let adminWorkspaceUsers = [];
let adminWorkspaceProjects = [];
let adminWorkspaceRequests = [];
let roleWorkspaceGeneration = 0;
let workspaceActionBusy = false;

function roleWorkspaceReady() {
    return Boolean(supabaseClient && currentUser && !state.isOffline);
}

async function loadKardex(targetId) {
    const generation = roleWorkspaceGeneration;
    const { data, error } = await supabaseClient.from('kardex_transaccional')
        .select('id_kardex,codigo_operacion,id_usuario_ejecutor,fecha_hora,payload_jsonb')
        .eq('proyecto_id', state.currentProject)
        .order('fecha_hora', { ascending: false }).limit(25);
    if (generation !== roleWorkspaceGeneration || !document.getElementById(targetId)) return;
    if (error) {
        showWorkspaceError(targetId, new Error(error.message));
        return;
    }
    const rows = data || [];
    document.getElementById(targetId).innerHTML = rows.length
        ? rows.map(row => `<article class="rounded-lg border border-slate-100 bg-slate-50 p-3">
            <div class="flex flex-wrap justify-between gap-2"><strong>${escapeHtml(row.codigo_operacion)}</strong><time class="text-xs text-slate-500">${escapeHtml(new Date(row.fecha_hora).toLocaleString('es-CL'))}</time></div>
            <p class="mt-1 break-all text-[11px] text-slate-500">${escapeHtml(JSON.stringify(row.payload_jsonb))}</p>
        </article>`).join('')
        : '<p>No hay movimientos registrados para esta obra.</p>';
}

function workspaceCard(title, description, body, icon = 'fa-clipboard-list', id = '') {
    const role = ROLE_WORKSPACES[state.currentRole] ? state.currentRole : (roleRoute || 'OPERARIO_MAESTRO');
    const style = {
        ADMIN_GENERAL: ['border-t-slate-800', 'bg-slate-100 text-slate-700'],
        JEFE_OBRA: ['border-t-blue-700', 'bg-blue-50 text-blue-700'],
        BODEGUERO: ['border-t-amber-500', 'bg-amber-50 text-amber-800'],
        OPERARIO_MAESTRO: ['border-t-emerald-600', 'bg-emerald-50 text-emerald-700']
    }[role] || ['border-t-slate-800', 'bg-slate-100 text-slate-700'];
    return `<details ${id ? `id="${id}"` : ''} class="workspace-card scroll-mt-24 overflow-hidden rounded-2xl border border-slate-200 border-t-4 ${style[0]} bg-white shadow-sm">
        <summary class="flex cursor-pointer list-none items-center gap-3 px-4 py-3.5 outline-none transition hover:bg-slate-50 focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-amber-500 sm:px-5">
            <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl ${style[1]}"><i class="fa-solid ${icon}" aria-hidden="true"></i></span>
            <span class="min-w-0 flex-1"><span class="block text-sm font-bold text-slate-900 sm:text-base">${title}</span><span class="mt-0.5 block truncate text-[11px] text-slate-500">${description}</span></span>
            <i class="workspace-card-chevron fa-solid fa-chevron-down shrink-0 text-xs text-slate-400 transition-transform" aria-hidden="true"></i>
        </summary>
        <div class="border-t border-slate-100 p-4 sm:p-5">${body}</div>
    </details>`;
}

function workspaceField(label, id, type = 'text', required = true, attrs = '') {
    return `<label class="block text-xs font-semibold text-slate-700">${label}
        <input id="${id}" type="${type}" ${required ? 'required' : ''} ${attrs}
            class="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-amber-500 focus:outline-none focus:ring-2 focus:ring-amber-200">
    </label>`;
}

function workspaceSelect(label, id, options, required = true) {
    return `<label class="block text-xs font-semibold text-slate-700">${label}
        <select id="${id}" ${required ? 'required' : ''} class="mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm">
            ${options}
        </select>
    </label>`;
}

function renderRoleWorkspace() {
    roleWorkspaceGeneration += 1;
    const role = ROLE_WORKSPACES[state.currentRole] ? state.currentRole : (roleRoute || 'OPERARIO_MAESTRO');
    if (role !== 'BODEGUERO') stopToolCameraScan();
    const workspace = ROLE_WORKSPACES[role];
    const title = document.getElementById('role-workspace-title');
    const description = document.getElementById('role-workspace-description');
    const content = document.getElementById('role-workspace-content');
    if (!title || !description || !content) return;

    title.textContent = workspace.title;
    description.textContent = workspace.description;
    const kicker = document.getElementById('role-workspace-kicker');
    if (kicker) kicker.textContent = workspace.navigationLabel;
    document.getElementById('view-role-workspace').dataset.role = role.toLowerCase();
    const dashboard = renderRoleDashboard(role);
    if (role === 'ADMIN_GENERAL') {
        content.innerHTML = `${dashboard}${renderAdminWorkspace()}`;
        if (roleWorkspaceReady()) {
            loadAdminWorkspace();
            loadRoleDashboard(role);
        }
    } else if (role === 'JEFE_OBRA') {
        content.innerHTML = `${dashboard}${renderManagerWorkspace()}`;
        if (roleWorkspaceReady()) {
            loadManagerWorkspace();
            loadRoleDashboard(role);
        }
    } else if (role === 'BODEGUERO') {
        content.innerHTML = `${dashboard}${renderStorekeeperWorkspace()}`;
        if (roleWorkspaceReady()) {
            loadWorkers();
            loadTools();
            loadOpenLoans('storekeeper-open-loans');
            loadStorekeeperOrders();
            loadMaterialStock();
            loadKardex('storekeeper-kardex');
            loadRoleDashboard(role);
        }
    } else {
        content.innerHTML = `${dashboard}${renderWorkerWorkspace()}`;
        if (roleWorkspaceReady()) {
            loadWorkerLoans();
            loadRoleDashboard(role);
        }
    }
    content.querySelectorAll('details.workspace-card').forEach(card => {
        card.addEventListener('toggle', () => {
            if (!card.open) return;
            content.querySelectorAll('details.workspace-card[open]').forEach(other => {
                if (other !== card) other.open = false;
            });
        });
    });
    if (workspaceActionBusy) setWorkspaceActionLocks(true);
}

function renderRoleDashboard(role) {
    const dashboards = {
        ADMIN_GENERAL: {
            icon: 'fa-compass-drafting',
            signal: 'CONTROL GLOBAL',
            eyebrow: 'CONSOLA ADMINISTRATIVA',
            headline: 'Una vista clara para decidir y actuar.',
            description: 'Gestiona accesos y obras; consulta alertas y trazabilidad desde un solo lugar.',
            theme: 'bg-slate-950 text-white',
            accent: 'text-amber-300',
            metrics: [
                ['admin-pending', 'Solicitudes pendientes', 'fa-user-clock', "scrollToRoleCard('admin-requests')"],
                ['admin-users', 'Perfiles activos', 'fa-users', "scrollToRoleCard('admin-profiles')"],
                ['admin-projects', 'Obras activas', 'fa-building', "scrollToRoleCard('admin-projects')"],
                ['admin-alerts', 'Alertas de stock', 'fa-bell', "scrollToRoleCard('admin-stock-card')"]
            ],
            actions: [
                ['Cuentas y accesos', "scrollToRoleCard('admin-requests')"],
                ['Perfiles', "scrollToRoleCard('admin-profiles')"],
                ['Obras', "scrollToRoleCard('admin-projects')"]
            ]
        },
        JEFE_OBRA: {
            icon: 'fa-helmet-safety',
            signal: 'OBRA ACTIVA',
            eyebrow: 'SUPERVISIÓN DE OBRA',
            headline: 'Estado de obra, sin ruido.',
            description: 'Prioriza pendientes y revisa señales operativas antes de intervenir.',
            theme: 'bg-blue-950 text-white',
            accent: 'text-sky-300',
            metrics: [
                ['manager-loans', 'Préstamos abiertos', 'fa-screwdriver-wrench', "scrollToRoleCard('manager-pending-loans-card')"],
                ['manager-alerts', 'Alertas activas', 'fa-triangle-exclamation', "scrollToRoleCard('manager-stock-alerts-card')"],
                ['manager-reports', 'Reportes diarios', 'fa-file-lines', "scrollToRoleCard('manager-daily-reports-card')"],
                ['manager-kardex', 'Movimientos Kardex', 'fa-clock-rotate-left', "scrollToRoleCard('manager-kardex-card')"]
            ],
            actions: [
                ['Plan semanal', "switchTab('kanban')"],
                ['Incidencias', "switchTab('incidencias')"],
                ['Préstamos', "scrollToRoleCard('manager-pending-loans-card')"]
            ]
        },
        BODEGUERO: {
            icon: 'fa-boxes-stacked',
            signal: 'PUESTO OPERATIVO',
            eyebrow: 'PUESTO OPERATIVO',
            headline: 'Bodega lista para operar.',
            description: 'Escanea primero, atiende la cola y registra cada movimiento con su trazabilidad.',
            theme: 'bg-amber-300 text-slate-950',
            accent: 'text-amber-950',
            metrics: [
                ['storekeeper-orders', 'Pedidos por resolver', 'fa-truck-ramp-box', "scrollToRoleCard('storekeeper-orders')"],
                ['storekeeper-loans', 'Préstamos abiertos', 'fa-arrow-up-right-from-square', "scrollToRoleCard('storekeeper-returns')"],
                ['storekeeper-alerts', 'Alertas de stock', 'fa-bell', "scrollToRoleCard('storekeeper-stock-card')"],
                ['storekeeper-stock', 'Materiales con stock', 'fa-boxes-stacked', "scrollToRoleCard('storekeeper-stock-card')"]
            ],
            actions: [
                ['Escanear herramienta', "scrollToRoleCard('storekeeper-scan')"],
                ['Atender pedidos', "scrollToRoleCard('storekeeper-orders')"],
                ['Registrar devolución', "scrollToRoleCard('storekeeper-returns')"]
            ]
        },
        OPERARIO_MAESTRO: {
            icon: 'fa-person-digging',
            signal: 'TU ESPACIO PERSONAL',
            eyebrow: 'TU JORNADA',
            headline: 'Lo que necesitas para seguir trabajando.',
            description: 'Consulta tus herramientas, confirma recepciones y solicita materiales para tu obra.',
            theme: 'bg-emerald-950 text-white',
            accent: 'text-emerald-300',
            metrics: [
                ['worker-loans', 'Mis préstamos', 'fa-screwdriver-wrench', "scrollToRoleCard('worker-loans-card')"],
                ['worker-signatures', 'Por firmar', 'fa-file-signature', "scrollToRoleCard('worker-signature-card')"],
                ['worker-orders', 'Pedidos pendientes', 'fa-cart-shopping', "switchTab('bodega')"],
                ['worker-stock', 'Materiales disponibles', 'fa-boxes-stacked', "scrollToRoleCard('worker-material-stock-card')"]
            ],
            actions: [
                ['Mis herramientas', "scrollToRoleCard('worker-loans-card')"],
                ['Solicitar material', "switchTab('bodega')"],
                ['Reportar un problema', "openModal('modal-incidencia')"]
            ]
        }
    };
    const view = dashboards[role] || dashboards.OPERARIO_MAESTRO;
    return `<section class="role-hero role-hero-${role.toLowerCase()} relative isolate overflow-hidden rounded-[1.75rem] ${view.theme} shadow-xl">
        <div class="role-hero-orb pointer-events-none absolute right-0 top-0 z-0 flex h-64 w-64 translate-x-1/3 -translate-y-1/3 items-center justify-center rounded-full border border-white/10 bg-white/[0.04] sm:h-80 sm:w-80" aria-hidden="true">
            <i class="fa-solid ${view.icon} text-8xl opacity-[0.08] sm:text-9xl"></i>
        </div>
        <div class="role-hero-layout relative z-10 grid gap-5 p-4 sm:p-6 xl:grid-cols-[0.95fr_2.05fr]">
            <div class="role-hero-copy flex min-w-0 flex-col justify-between gap-5">
                <div>
                    <div class="flex flex-wrap items-center gap-2">
                        <span class="inline-flex items-center gap-2 rounded-full border border-current/15 bg-white/10 px-2.5 py-1 text-[9px] font-black tracking-[0.14em]">
                            <span class="h-1.5 w-1.5 rounded-full bg-current"></span>${view.signal}
                        </span>
                        <span class="rounded-full bg-black/10 px-2.5 py-1 text-[9px] font-bold uppercase tracking-wider opacity-75">${view.eyebrow}</span>
                    </div>
                    <h2 class="mt-4 max-w-xl text-[1.65rem] font-black leading-tight tracking-tight sm:text-3xl">${view.headline}</h2>
                    <p class="mt-2 max-w-xl text-sm leading-relaxed opacity-75">${view.description}</p>
                </div>
                <div class="flex flex-wrap gap-2">${view.actions.map(([label, action], index) =>
                    `<button type="button" onclick="${action}" class="inline-flex max-w-full items-center gap-2 rounded-xl border ${index === 0 ? 'border-transparent bg-white text-slate-950 shadow-md hover:bg-slate-100' : 'border-current/20 bg-white/10 hover:bg-white/20'} px-3 py-2.5 text-xs font-bold transition focus:outline-none focus:ring-2 focus:ring-current"><span class="truncate">${label}</span><i class="fa-solid ${index === 0 ? 'fa-arrow-right' : 'fa-chevron-right'} text-[9px]" aria-hidden="true"></i></button>`
                ).join('')}</div>
            </div>
            <div class="role-hero-metrics grid grid-cols-2 gap-2 sm:gap-3 xl:grid-cols-4">
                ${view.metrics.map(([id, label, icon, action]) => `<button type="button" onclick="${action}" aria-label="${label}: abrir detalle" class="role-metric group relative min-h-24 min-w-0 overflow-hidden rounded-2xl border border-white/10 bg-white/[0.09] p-3 text-left transition hover:-translate-y-0.5 hover:border-white/25 hover:bg-white/[0.15] focus:outline-none focus:ring-2 focus:ring-white/70 sm:p-4">
                    <span class="flex h-8 w-8 items-center justify-center rounded-lg bg-white/10 ${view.accent}"><i class="fa-solid ${icon}" aria-hidden="true"></i></span>
                    <span id="metric-${id}" class="mt-3 block text-2xl font-black tabular-nums" aria-live="polite">—</span>
                    <span class="mt-1 block text-[10px] font-semibold leading-snug opacity-75 sm:text-[11px]">${label}</span>
                    <i class="fa-solid fa-arrow-up-right-from-square absolute right-3 top-3 text-[9px] opacity-0 transition group-hover:opacity-50" aria-hidden="true"></i>
                </button>`).join('')}
            </div>
        </div>
        <p id="role-dashboard-status" class="flex items-center gap-2 border-t border-white/10 bg-black/[0.08] px-4 py-2 text-[10px] opacity-80 sm:px-6" role="status"><i class="fa-solid fa-circle-info" aria-hidden="true"></i><span>Conecta una cuenta para consultar datos autorizados.</span></p>
    </section>`;
}

async function loadRoleDashboard(role) {
    if (!roleWorkspaceReady()) return;
    const generation = roleWorkspaceGeneration;
    const projectId = state.currentProject;
    const metrics = {
        ADMIN_GENERAL: [
            ['admin-pending', supabaseClient.from('conterreno_solicitudes_acceso').select('usuario_auth_id', { count: 'exact', head: true }).eq('estado', 'PENDIENTE')],
            ['admin-users', supabaseClient.from('usuarios').select('id_usuario', { count: 'exact', head: true }).eq('activo', true)],
            ['admin-projects', supabaseClient.from('conterreno_proyectos').select('id', { count: 'exact', head: true }).eq('activo', true)],
            ['admin-alerts', supabaseClient.from('conterreno_alertas_stock').select('id', { count: 'exact', head: true }).eq('estado', 'ACTIVA')]
        ],
        JEFE_OBRA: [
            ['manager-loans', supabaseClient.from('prestamos').select('id_prestamo', { count: 'exact', head: true }).eq('proyecto_id', projectId).is('fecha_hora_devolucion', null)],
            ['manager-alerts', supabaseClient.from('conterreno_alertas_stock').select('id', { count: 'exact', head: true }).eq('proyecto_id', projectId).eq('estado', 'ACTIVA')],
            ['manager-reports', supabaseClient.from('conterreno_reportes_prestamos_diarios').select('fecha_reporte', { count: 'exact', head: true }).eq('proyecto_id', projectId)],
            ['manager-kardex', supabaseClient.from('kardex_transaccional').select('id_kardex', { count: 'exact', head: true }).eq('proyecto_id', projectId)]
        ],
        BODEGUERO: [
            ['storekeeper-orders', supabaseClient.from('conterreno_pedidos_materiales').select('id', { count: 'exact', head: true }).eq('proyecto_id', projectId).eq('estado', 'Pendiente')],
            ['storekeeper-loans', supabaseClient.from('prestamos').select('id_prestamo', { count: 'exact', head: true }).eq('proyecto_id', projectId).is('fecha_hora_devolucion', null)],
            ['storekeeper-alerts', supabaseClient.from('conterreno_alertas_stock').select('id', { count: 'exact', head: true }).eq('proyecto_id', projectId).eq('estado', 'ACTIVA')],
            ['storekeeper-stock', supabaseClient.from('conterreno_stock_materiales').select('material_id,conterreno_catalogo_materiales!inner(activo)', { count: 'exact', head: true }).eq('proyecto_id', projectId).eq('conterreno_catalogo_materiales.activo', true)]
        ],
        OPERARIO_MAESTRO: [
            ['worker-loans', supabaseClient.from('prestamos').select('id_prestamo', { count: 'exact', head: true }).eq('proyecto_id', projectId).eq('id_trabajador', currentUser.id)],
            ['worker-signatures', supabaseClient.from('prestamos').select('id_prestamo', { count: 'exact', head: true }).eq('proyecto_id', projectId).eq('id_trabajador', currentUser.id).eq('estado_devolucion', 'PENDIENTE_FIRMA')],
            ['worker-orders', supabaseClient.from('conterreno_pedidos_materiales').select('id', { count: 'exact', head: true }).eq('proyecto_id', projectId).eq('estado', 'Pendiente')],
            ['worker-stock', supabaseClient.from('conterreno_stock_materiales').select('material_id,conterreno_catalogo_materiales!inner(activo)', { count: 'exact', head: true }).eq('proyecto_id', projectId).eq('conterreno_catalogo_materiales.activo', true)]
        ]
    }[role];
    if (!metrics) return;

    const status = document.querySelector('#role-dashboard-status span');
    if (status) status.textContent = 'Actualizando datos de tu perfil…';
    const results = await Promise.all(metrics.map(async ([key, query]) => {
        const { count, error } = await query;
        if (generation !== roleWorkspaceGeneration) return { key, error: null, count: null };
        const metric = document.getElementById(`metric-${key}`);
        if (metric) {
            metric.textContent = error ? 'Error' : count === null ? '—' : String(count);
            if (error) metric.title = `No se pudo cargar: ${error.message}`;
        }
        return { key, error, count };
    }));
    if (generation !== roleWorkspaceGeneration) return;
    const failed = results.filter(result => result.error || result.count === null);
    if (status) {
        status.textContent = failed.length
            ? `No se pudieron cargar algunos indicadores: ${failed.map(({ key, error }) => {
                const label = document.getElementById(`metric-${key}`)?.parentElement?.querySelector('span:last-of-type')?.textContent || key;
                return `${label}: ${error?.message || 'sin recuento'}`;
            }).join(' · ')}`
            : `Datos actualizados ${new Date().toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit' })} · La visibilidad y las acciones siguen sujetas a permisos de Supabase.`;
    }
}

function scrollToRoleCard(cardId) {
    const card = document.getElementById(cardId);
    if (!card) return;
    if (card instanceof HTMLDetailsElement) card.open = true;
    card.scrollIntoView({ behavior: 'smooth', block: 'start' });
    if (cardId === 'storekeeper-scan') {
        window.setTimeout(() => document.getElementById('tool-scan-code')?.focus(), 250);
    }
}

function renderAdminWorkspace() {
    const roleOptions = [
        ['ADMIN_GENERAL', 'Administrador del sistema'],
        ['JEFE_OBRA', 'Jefe de obra'],
        ['BODEGUERO', 'Bodeguero'],
        ['OPERARIO_MAESTRO', 'Trabajador / operario']
    ].map(([value, name]) => `<option value="${value}">${name}</option>`).join('');
    return `<div class="grid gap-6 xl:grid-cols-2">
        ${workspaceCard('Crear cuenta de acceso', 'Crea la identidad sin enviar correo. La contraseña inicial se muestra una sola vez; entrégala al usuario por un canal privado.', `
            <form onsubmit="adminCreateAuthUser(event)" class="grid gap-3">
                ${workspaceField('Nombre completo', 'admin-new-user-name')}
                ${workspaceField('Correo electrónico', 'admin-new-user-email', 'email')}
                <button class="rounded-lg bg-slate-900 px-4 py-2.5 text-sm font-bold text-white hover:bg-slate-700">Crear cuenta</button>
            </form>
            <div id="admin-created-credential" class="mt-4 hidden rounded-lg border border-amber-300 bg-amber-50 p-4" aria-live="polite">
                <p class="text-sm font-bold text-amber-950">Contraseña inicial: mostrar y copiar ahora</p>
                <p id="admin-created-email" class="mt-2 text-xs text-amber-900"></p>
                <code id="admin-created-password" class="mt-2 block break-all rounded bg-white p-3 text-sm text-slate-900"></code>
                <div class="mt-3 flex gap-2">
                    <button type="button" onclick="adminCopyInitialPassword()" class="rounded bg-slate-900 px-3 py-2 text-xs font-bold text-white">Copiar contraseña</button>
                    <button type="button" onclick="adminDismissInitialPassword()" class="rounded bg-white px-3 py-2 text-xs font-bold text-slate-700">Ocultar</button>
                </div>
                <p class="mt-2 text-xs text-amber-900">No se vuelve a mostrar después de ocultarla o cerrar esta página. La cuenta aparecerá abajo como pendiente para asignarle perfil, rol y obra.</p>
            </div>`, 'fa-user-plus')}
        ${workspaceCard('Solicitudes de cuenta', 'Asigna un rol y una obra a cada cuenta registrada para habilitar su acceso.', `
            <div id="admin-pending-requests" class="space-y-4 text-sm text-slate-600">Cargando solicitudes...</div>`, 'fa-user-check', 'admin-requests')}
        ${workspaceCard('Crear obra', 'El identificador debe ser único (por ejemplo, obra-norte).', `
            <form onsubmit="adminCreateProject(event)" class="grid gap-3">
                ${workspaceField('Identificador', 'admin-project-id', 'text', true, 'pattern="[a-z0-9][a-z0-9_-]{1,39}"')}
                ${workspaceField('Nombre de la obra', 'admin-project-name')}
                <button class="rounded-lg bg-slate-900 px-4 py-2.5 text-sm font-bold text-white hover:bg-slate-700">Crear obra</button>
            </form>
            <div id="admin-project-list" class="mt-4 text-sm text-slate-600">Cargando obras...</div>`, 'fa-building', 'admin-projects')}
        ${workspaceCard('Perfiles y asignaciones', 'Asigna una cuenta existente a una obra o cambia su rol con justificación. Desactivar el perfil bloquea RLS; la identidad Auth debe deshabilitarse por separado en Supabase.', `
            <div id="admin-user-list" class="overflow-x-auto text-sm text-slate-600">Cargando perfiles...</div>`, 'fa-users-gear', 'admin-profiles')}
        ${workspaceCard('Auditoría reciente', 'Solo lectura. Los cambios administrativos quedan registrados.', `
            <div id="admin-audit-list" class="space-y-2 text-sm text-slate-600">Cargando auditoría...</div>`, 'fa-shield-halved')}
        ${workspaceCard('Alertas de stock', 'Resumen de alertas activas para las obras donde tienes acceso.', `
            <div id="admin-stock-alerts" class="space-y-2 text-sm text-slate-600">Cargando alertas...</div>`, 'fa-bell', 'admin-stock-card')}
        ${workspaceCard('Kardex de obra', 'Historial de solo lectura. Los cambios se generan desde operaciones autorizadas.', `
            <div id="admin-kardex" class="space-y-2 text-sm text-slate-600">Cargando Kardex...</div>`, 'fa-clock-rotate-left')}
    </div>`;
}

function renderManagerWorkspace() {
    return `<div class="grid gap-4 xl:grid-cols-3">
        ${workspaceCard('Préstamos pendientes', 'Herramientas que todavía no registran devolución. Panel de consulta para Jefatura.', `
            <div id="manager-pending-loans" class="overflow-x-auto text-sm text-slate-600">Cargando préstamos...</div>`, 'fa-triangle-exclamation', 'manager-pending-loans-card')}
        ${workspaceCard('Reportes diarios', 'Historial de snapshots generado por la tarea programada (18:00 hora Chile cuando pg_cron quede configurado).', `
            <div id="manager-daily-reports" class="space-y-2 text-sm text-slate-600">Cargando reportes...</div>`, 'fa-file-lines', 'manager-daily-reports-card')}
        ${workspaceCard('Inventario de herramientas', 'Consulta las herramientas de la obra sin modificar su estado.', `
            <div id="manager-tool-inventory" class="overflow-x-auto text-sm text-slate-600">Cargando inventario...</div>`, 'fa-screwdriver-wrench')}
        ${workspaceCard('Alertas de stock bajo', 'Alertas activas de materiales bajo su mínimo configurado.', `
            <div id="manager-stock-alerts" class="space-y-2 text-sm text-slate-600">Cargando alertas...</div>`, 'fa-bell', 'manager-stock-alerts-card')}
        ${workspaceCard('Kardex de obra', 'Historial de solo lectura de los movimientos operativos.', `
            <div id="manager-kardex" class="space-y-2 text-sm text-slate-600">Cargando Kardex...</div>`, 'fa-clock-rotate-left', 'manager-kardex-card')}
        ${workspaceCard('Acceso rápido', 'La jefatura supervisa, no procesa movimientos de bodega.', `
            <div class="flex flex-wrap gap-2">
                <button onclick="switchTab('kanban')" class="rounded-lg bg-slate-900 px-4 py-2 text-xs font-bold text-white">Plan semanal</button>
                <button onclick="switchTab('incidencias')" class="rounded-lg bg-slate-100 px-4 py-2 text-xs font-bold text-slate-800">Incidencias</button>
            </div>`, 'fa-compass')}
    </div>`;
}

function renderStorekeeperWorkspace() {
    return `<div class="grid gap-4 lg:grid-cols-2">
        ${workspaceCard('Lectura de etiqueta y alta rápida', 'Un lector QR/barra que actúa como teclado puede escribir el código y confirmar con Enter. También se puede ingresar manualmente.', `
            <form onsubmit="findToolByTag(event)" class="flex gap-2">
                <input id="tool-scan-code" required placeholder="Escanea o escribe el código QR"
                    class="min-w-0 flex-1 rounded-lg border border-slate-300 px-3 py-3 text-sm">
                <button class="rounded-lg bg-amber-500 px-4 py-2 font-bold text-slate-950">Buscar</button>
            </form>
            <div class="mt-3 flex flex-wrap gap-2">
                <button type="button" onclick="startToolCameraScan()" class="rounded-lg bg-slate-900 px-3 py-2 text-xs font-bold text-white">Usar cámara</button>
                <button type="button" onclick="stopToolCameraScan()" class="rounded-lg bg-slate-100 px-3 py-2 text-xs font-bold text-slate-700">Cerrar cámara</button>
            </div>
            <video id="tool-camera-preview" class="mt-3 hidden max-h-64 w-full rounded-xl bg-slate-950 object-cover" playsinline></video>
            <p id="tool-camera-status" class="mt-2 text-xs text-slate-500"></p>
            <div id="tool-scan-result" class="mt-3 text-sm text-slate-600"></div>
            <form onsubmit="storekeeperCreateTool(event)" class="mt-5 grid gap-3 sm:grid-cols-2 border-t border-slate-100 pt-4">
                ${workspaceField('Código QR / etiqueta', 'new-tool-tag')}
                ${workspaceField('Número de serie', 'new-tool-serial')}
                ${workspaceField('Nombre de herramienta', 'new-tool-name')}
                ${workspaceField('Descripción', 'new-tool-description', 'text', false)}
                <button class="sm:col-span-2 rounded-lg bg-slate-900 px-4 py-2.5 text-sm font-bold text-white">Registrar herramienta</button>
            </form>`, 'fa-qrcode', 'storekeeper-scan')}
        ${workspaceCard('Registrar préstamo', 'Selecciona la herramienta disponible y el trabajador asignado a esta obra.', `
            <form onsubmit="storekeeperRegisterLoan(event)" class="grid gap-3">
                ${workspaceSelect('Herramienta disponible', 'loan-tool-select', '<option value="">Cargando herramientas...</option>')}
                ${workspaceSelect('Trabajador', 'loan-worker-select', '<option value="">Cargando trabajadores...</option>')}
                <button class="rounded-lg bg-amber-500 px-4 py-3 text-sm font-extrabold text-slate-950">Registrar entrega</button>
            </form>`, 'fa-arrow-up-right-from-square')}
        ${workspaceCard('Préstamos activos y devolución', 'Registra la condición al recibir el equipo. Si llega dañado, adjunta evidencia fotográfica.', `
            <div id="storekeeper-open-loans" class="mb-4 overflow-x-auto text-sm text-slate-600">Cargando préstamos...</div>
            <form onsubmit="storekeeperRegisterReturn(event)" class="grid gap-3 border-t border-slate-100 pt-4">
                ${workspaceSelect('Préstamo a recibir', 'return-loan-select', '<option value="">Cargando préstamos...</option>')}
                ${workspaceSelect('Condición', 'return-condition', '<option value="DEVUELTO_OK">Devuelto en buen estado</option><option value="DEVUELTO_CON_DANOS">Devuelto con daños</option>')}
                ${workspaceField('Observación', 'return-observation', 'text', false)}
                ${workspaceField('Foto de evidencia (obligatoria si hay daño)', 'return-evidence', 'file', false, 'accept="image/*" capture="environment"')}
                <button class="rounded-lg bg-slate-900 px-4 py-3 text-sm font-bold text-white">Registrar devolución</button>
            </form>`, 'fa-arrow-down-left', 'storekeeper-returns')}
        ${workspaceCard('Pedidos de materiales', 'Despacha el pedido completo cuando hay stock suficiente o recházalo indicando el motivo. El despacho descuenta existencias y registra el movimiento en el Kardex.', `
            <div id="storekeeper-material-orders" class="space-y-3 text-sm text-slate-600">Cargando pedidos...</div>`, 'fa-truck-ramp-box', 'storekeeper-orders')}
        ${workspaceCard('Materiales y stock', 'Las entradas, salidas y ajustes quedan en el historial; el stock bajo genera una alerta automáticamente.', `
            <form onsubmit="storekeeperCreateMaterial(event)" class="grid gap-3 sm:grid-cols-2">
                ${workspaceField('Código', 'new-material-code')}
                ${workspaceField('Nombre del material', 'new-material-name')}
                ${workspaceField('Unidad', 'new-material-unit', 'text', true, 'placeholder="unidad, caja, saco..."')}
                ${workspaceField('Stock mínimo', 'new-material-min', 'number', true, 'min="0" step="0.01" value="0"')}
                <button class="sm:col-span-2 rounded-lg bg-slate-900 px-4 py-2.5 text-sm font-bold text-white">Crear material</button>
            </form>
            <div id="storekeeper-material-stock" class="my-4 overflow-x-auto text-sm text-slate-600">Cargando existencias...</div>
            <form onsubmit="storekeeperAdjustStock(event)" class="grid gap-3 sm:grid-cols-2 border-t border-slate-100 pt-4">
                ${workspaceSelect('Material', 'stock-material-select', '<option value="">Cargando materiales...</option>')}
                ${workspaceSelect('Movimiento', 'stock-movement-type', '<option value="ENTRADA">Entrada</option><option value="SALIDA">Salida</option><option value="AJUSTE">Ajuste a cantidad exacta</option>')}
                ${workspaceField('Cantidad', 'stock-quantity', 'number', true, 'min="0.01" step="0.01"')}
                ${workspaceField('Nuevo mínimo', 'stock-minimum', 'number', true, 'min="0" step="0.01"')}
                <label class="sm:col-span-2 block text-xs font-semibold text-slate-700">Motivo
                    <textarea id="stock-reason" required minlength="3" class="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"></textarea>
                </label>
                <button class="sm:col-span-2 rounded-lg bg-amber-500 px-4 py-2.5 text-sm font-bold text-slate-950">Registrar movimiento</button>
            </form>`, 'fa-boxes-stacked', 'storekeeper-stock-card')}
        ${workspaceCard('Kardex de obra', 'Consulta el historial; no se ofrecen acciones de modificación o borrado.', `
            <div id="storekeeper-kardex" class="space-y-2 text-sm text-slate-600">Cargando Kardex...</div>`, 'fa-clock-rotate-left')}
    </div>`;
}

function renderWorkerWorkspace() {
    return `<div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        ${workspaceCard('Mis préstamos', 'Solo se muestran las herramientas asignadas a tu cuenta.', `
            <div id="worker-loans" class="space-y-3 text-sm text-slate-600">Cargando tus préstamos...</div>`, 'fa-screwdriver-wrench', 'worker-loans-card')}
        ${workspaceCard('Herramientas disponibles', 'Consulta el inventario de tu obra. Solo Bodega puede cambiar existencias o registrar entregas.', `
            <div id="worker-tool-inventory" class="overflow-x-auto text-sm text-slate-600">Cargando inventario...</div>`, 'fa-boxes-stacked')}
        ${workspaceCard('Disponibilidad de materiales', 'Consulta existencias y mínimos; las solicitudes se envían desde Pedidos Bodega.', `
            <div id="worker-material-stock" class="overflow-x-auto text-sm text-slate-600">Cargando existencias...</div>`, 'fa-cubes-stacked', 'worker-material-stock-card')}
        ${workspaceCard('Firma de recepción', 'Firma en el recuadro para confirmar la recepción de la herramienta seleccionada.', `
            <div id="worker-signature-loan" class="mb-3 text-sm text-slate-600">Selecciona un préstamo pendiente de firma en la lista.</div>
            <canvas id="worker-signature-pad" width="800" height="280" class="h-44 w-full touch-none rounded-xl border-2 border-dashed border-slate-300 bg-white"></canvas>
            <div class="mt-3 flex gap-2">
                <button type="button" onclick="clearWorkerSignature()" class="rounded-lg bg-slate-100 px-4 py-2 text-xs font-bold text-slate-800">Limpiar</button>
                <button type="button" onclick="workerSignLoan()" class="rounded-lg bg-amber-500 px-4 py-2 text-xs font-extrabold text-slate-950">Firmar recepción</button>
            </div>
            <p class="mt-2 text-[11px] text-slate-500">La imagen y su hash se guardan en Storage privado y se vinculan al préstamo.</p>`, 'fa-signature', 'worker-signature-card')}
        ${workspaceCard('Solicitudes de materiales', 'El trabajador puede solicitar, pero no aprobar ni alterar existencias.', `
            <button onclick="switchTab('bodega')" class="rounded-lg bg-slate-900 px-4 py-2.5 text-xs font-bold text-white">Crear o consultar solicitud</button>`, 'fa-cart-shopping')}
    </div>`;
}

function showWorkspaceError(targetId, error) {
    const target = document.getElementById(targetId);
    if (target) target.innerHTML = `<div class="flex items-start gap-3 rounded-xl border border-rose-200 bg-rose-50 p-3 text-xs text-rose-800" role="alert">
        <i class="fa-solid fa-circle-exclamation mt-0.5" aria-hidden="true"></i>
        <p>${escapeHtml(error.message || String(error))}</p>
    </div>`;
}

async function workspaceQuery(targetId, query, render) {
    const generation = roleWorkspaceGeneration;
    const { data, error } = await query;
    if (generation !== roleWorkspaceGeneration || !document.getElementById(targetId)) return null;
    if (error) {
        showWorkspaceError(targetId, new Error(error.message));
        return null;
    }
    render(data || []);
    return data || [];
}

async function loadAdminWorkspace() {
    await Promise.all([
        workspaceQuery('admin-pending-requests', supabaseClient
            .from('conterreno_solicitudes_acceso')
            .select('usuario_auth_id,email,nombre_completo,nombres,apellidos,email_confirmado,estado,creado_en')
            .eq('estado', 'PENDIENTE')
            .order('creado_en', { ascending: true }), renderAdminAccessRequests),
        workspaceQuery('admin-user-list', supabaseClient
            .from('usuarios')
            .select('id_usuario,rut,nombres,apellidos,email,activo,roles!inner(codigo_rol,nombre)')
            .order('apellidos'), renderAdminUsers),
        workspaceQuery('admin-project-list', supabaseClient
            .from('conterreno_proyectos').select('id,nombre,activo').order('nombre'), renderAdminProjects),
        workspaceQuery('admin-audit-list', supabaseClient
            .from('auditoria_usuarios')
            .select('id_auditoria,tabla_afectada,operacion,datos_nuevos,fecha_hora')
            .order('fecha_hora', { ascending: false }).limit(8), renderAdminAudit),
        workspaceQuery('admin-stock-alerts', supabaseClient
            .from('conterreno_alertas_stock')
            .select('id,proyecto_id,material_id,cantidad_actual,stock_minimo,creada_en,conterreno_catalogo_materiales(nombre,unidad)')
            .eq('estado', 'ACTIVA').order('creada_en', { ascending: false }).limit(20),
            alerts => renderStockAlerts(alerts, 'admin-stock-alerts')),
        loadKardex('admin-kardex')
    ]);
}

function renderAdminAccessRequests(requests) {
    const target = document.getElementById('admin-pending-requests');
    if (!target) return;
    adminWorkspaceRequests = requests;
    const projects = adminWorkspaceProjects
        .filter(project => project.activo)
        .map(project => `<option value="${escapeHtml(project.id)}">${escapeHtml(project.name)}</option>`)
        .join('');
    const roles = Object.entries(ROLE_WORKSPACES)
        .map(([code, role]) => `<option value="${escapeHtml(code)}">${escapeHtml(role.title)}</option>`)
        .join('');

    target.innerHTML = requests.length
        ? requests.map(request => `<form onsubmit="adminApproveAccess(event, '${escapeHtml(request.usuario_auth_id)}')" class="rounded-xl border border-slate-200 p-4">
            <div class="mb-3">
                <strong class="text-slate-900">${escapeHtml(request.nombre_completo || request.email)}</strong>
                <p class="text-xs text-slate-500">${escapeHtml(request.email)} · ${escapeHtml(new Date(request.creado_en).toLocaleString('es-CL'))}</p>
                ${request.email_confirmado ? '' : '<p class="mt-1 text-xs font-semibold text-amber-700">Pendiente de confirmación del correo</p>'}
            </div>
            <div class="grid gap-3 sm:grid-cols-2">
                ${workspaceField('RUT', `request-rut-${request.usuario_auth_id}`, 'text', true, 'minlength="8"')}
                ${workspaceField('Cargo', `request-cargo-${request.usuario_auth_id}`)}
                ${workspaceField('Nombres', `request-first-${request.usuario_auth_id}`, 'text', true, `value="${escapeHtml(request.nombres)}"`)}
                ${workspaceField('Apellidos', `request-last-${request.usuario_auth_id}`, 'text', true, `value="${escapeHtml(request.apellidos)}"`)}
                ${workspaceSelect('Rol asignado', `request-role-${request.usuario_auth_id}`, `<option value="" selected disabled>Selecciona un rol</option>${roles}`)}
                ${workspaceSelect('Obra asignada', `request-project-${request.usuario_auth_id}`, `<option value="" selected disabled>${projects ? 'Selecciona una obra' : 'Crea primero una obra'}</option>${projects}`)}
                <button ${projects && request.email_confirmado ? '' : 'disabled'} class="sm:col-span-2 rounded-lg bg-amber-500 px-4 py-2.5 text-sm font-extrabold text-slate-950 disabled:cursor-not-allowed disabled:opacity-50">Aprobar y asignar acceso</button>
            </div>
        </form>`).join('')
        : '<p class="rounded-lg bg-slate-50 p-3">No hay cuentas pendientes de aprobación.</p>';
}

function renderAdminUsers(users) {
    adminWorkspaceUsers = users;
    const projects = adminWorkspaceProjects.filter(project => project.activo).map(project =>
        `<option value="${escapeHtml(project.id)}">${escapeHtml(project.name)}</option>`
    ).join('');
    const rolesFor = currentRole => Object.entries(ROLE_WORKSPACES).map(([code, role]) =>
        `<option value="${code}" ${code === currentRole ? 'selected' : ''}>${escapeHtml(role.title)}</option>`
    ).join('');
    document.getElementById('admin-user-list').innerHTML = users.length ? `
        <table class="w-full min-w-[760px] text-left text-xs">
            <thead class="text-slate-500"><tr><th class="p-2">Persona</th><th class="p-2">RUT / correo</th><th class="p-2">Rol</th><th class="p-2">Cambiar rol</th><th class="p-2">Asignar obra</th></tr></thead>
            <tbody>${users.map(user => `<tr class="border-t border-slate-100">
                <td class="p-2 font-semibold">${escapeHtml(`${user.nombres} ${user.apellidos}`)}${user.activo ? '' : ' (inactivo)'}</td>
                <td class="p-2">${escapeHtml(user.rut)}<br>${escapeHtml(user.email)}</td>
                <td class="p-2">${escapeHtml(user.roles.nombre)}</td>
                <td class="p-2"><select id="role-${user.id_usuario}" class="rounded border border-slate-300 p-1">${rolesFor(user.roles.codigo_rol)}</select><button onclick="adminChangeRole('${user.id_usuario}')" class="ml-1 rounded bg-slate-900 px-2 py-1 text-white">Aplicar</button></td>
                <td class="p-2"><select id="project-${user.id_usuario}" class="rounded border border-slate-300 p-1">${projects}</select><button onclick="adminAssignProject('${user.id_usuario}')" class="ml-1 rounded bg-amber-500 px-2 py-1 font-bold">Asignar</button>
                <button onclick="adminDeactivateUser('${user.id_usuario}')" ${user.activo && user.id_usuario !== currentUser.id ? '' : 'disabled'} class="ml-1 rounded bg-rose-50 px-2 py-1 font-bold text-rose-700 disabled:opacity-40">Desactivar</button></td>
            </tr>`).join('')}</tbody>
        </table>` : '<p>No hay perfiles activos.</p>';
}

function renderAdminProjects(projects) {
    adminWorkspaceProjects = projects.map(project => ({
        id: project.id,
        name: project.nombre,
        activo: project.activo
    }));
    renderAdminUsers(adminWorkspaceUsers);
    renderAdminAccessRequests(adminWorkspaceRequests);
    document.getElementById('admin-project-list').innerHTML = projects.length
        ? `<ul class="space-y-2">${projects.map(project => `<li class="flex justify-between gap-3 border-b border-slate-100 py-2">
            <span><strong>${escapeHtml(project.nombre)}</strong> <span class="text-xs text-slate-400">(${escapeHtml(project.id)})</span></span>
            <span class="flex items-center gap-2"><span class="text-xs ${project.activo ? 'text-emerald-700' : 'text-rose-700'}">${project.activo ? 'Activa' : 'Inactiva'}</span>
            <button data-project-id="${escapeHtml(project.id)}" data-project-name="${escapeHtml(project.nombre)}" onclick="adminUpdateProject(this.dataset.projectId,this.dataset.projectName,${!project.activo})" class="rounded bg-slate-100 px-2 py-1 text-[10px] font-bold text-slate-700">${project.activo ? 'Desactivar' : 'Activar'}</button></span>
        </li>`).join('')}</ul>`
        : '<p>No hay obras configuradas.</p>';
}

function renderAdminAudit(events) {
    document.getElementById('admin-audit-list').innerHTML = events.length
        ? events.map(event => `<div class="rounded-lg bg-slate-50 p-3">
            <div class="flex justify-between gap-2"><strong>${escapeHtml(event.operacion)}</strong><time class="text-xs text-slate-500">${escapeHtml(new Date(event.fecha_hora).toLocaleString('es-CL'))}</time></div>
            <p class="text-xs text-slate-500">${escapeHtml(event.tabla_afectada)} · ${escapeHtml(JSON.stringify(event.datos_nuevos || {}))}</p>
        </div>`).join('')
        : '<p>Sin movimientos de auditoría todavía.</p>';
}

async function adminApproveAccess(event, userId) {
    event.preventDefault();
    await workspaceAction(async () => supabaseClient.rpc('fn_conterreno_admin_asignar_acceso', {
        p_id_usuario: userId,
        p_rut: document.getElementById(`request-rut-${userId}`).value.trim(),
        p_nombres: document.getElementById(`request-first-${userId}`).value.trim(),
        p_apellidos: document.getElementById(`request-last-${userId}`).value.trim(),
        p_cargo: document.getElementById(`request-cargo-${userId}`).value.trim(),
        p_codigo_rol: document.getElementById(`request-role-${userId}`).value,
        p_proyecto_id: document.getElementById(`request-project-${userId}`).value
    }), 'Cuenta aprobada y acceso asignado.');
}

function generateInitialPassword() {
    const bytes = crypto.getRandomValues(new Uint8Array(24));
    return Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
}

async function adminCreateAuthUser(event) {
    event.preventDefault();
    if (!roleWorkspaceReady() || state.currentRole !== 'ADMIN_GENERAL') {
        showToast('Solo Administración puede crear cuentas.', 'error');
        return;
    }

    const form = event.currentTarget;
    const button = form.querySelector('button[type="submit"], button:not([type])');
    const email = document.getElementById('admin-new-user-email').value.trim().toLowerCase();
    const fullName = document.getElementById('admin-new-user-name').value.trim();
    const password = generateInitialPassword();
    const credentialPanel = document.getElementById('admin-created-credential');
    if (!credentialPanel.classList.contains('hidden') &&
        !window.confirm('La contraseña anterior dejará de mostrarse. ¿Ya la guardaste y quieres crear otra cuenta?')) {
        return;
    }
    adminDismissInitialPassword();
    if (button) button.disabled = true;

    try {
        const { data, error } = await supabaseClient.functions.invoke('admin-create-user', {
            body: { email, fullName, password }
        });
        if (error) {
            let detail = error.message || 'No se pudo crear la cuenta.';
            if (error.name === 'FunctionsFetchError') {
                detail = 'No se pudo contactar la Edge Function. Verifica que admin-create-user esté desplegada en el mismo proyecto Supabase y que la red no bloquee la solicitud.';
            }
            if (error.context instanceof Response) {
                const responseBody = await error.context.clone().text();
                if (responseBody) {
                    try {
                        const payload = JSON.parse(responseBody);
                        detail = payload.error || responseBody;
                    } catch {
                        detail = responseBody;
                    }
                }
                detail = `HTTP ${error.context.status}: ${detail}`;
            }
            throw new Error(detail);
        }
        if (!data?.userId) throw new Error('La función no confirmó la creación de la cuenta.');
        if (data.alreadyExists) {
            adminDismissInitialPassword();
            form.reset();
            await loadAdminWorkspace();
            showToast('Ya existe una cuenta Auth con ese correo. No se modificó su contraseña; revisa si aparece en solicitudes pendientes.', 'error');
            return;
        }

        document.getElementById('admin-created-email').textContent = data.email || email;
        document.getElementById('admin-created-password').textContent = password;
        document.getElementById('admin-created-credential').classList.remove('hidden');
        form.reset();
        await loadAdminWorkspace();
        showToast('Cuenta creada. Guarda la contraseña inicial y asigna su rol y obra.', 'success');
    } catch (error) {
        showToast(error.message || 'No se pudo crear la cuenta.', 'error');
    } finally {
        if (button) button.disabled = false;
    }
}

async function adminCopyInitialPassword() {
    const password = document.getElementById('admin-created-password')?.textContent;
    if (!password) return;
    try {
        await navigator.clipboard.writeText(password);
        showToast('Contraseña copiada. Compártela por un canal privado.', 'success');
    } catch (error) {
        showToast(`No se pudo copiar la contraseña: ${error.message}`, 'error');
    }
}

function adminDismissInitialPassword() {
    const panel = document.getElementById('admin-created-credential');
    if (!panel) return;
    document.getElementById('admin-created-email').textContent = '';
    document.getElementById('admin-created-password').textContent = '';
    panel.classList.add('hidden');
}

async function adminCreateProject(event) {
    event.preventDefault();
    await workspaceAction(async () => supabaseClient.rpc('fn_conterreno_admin_crear_proyecto', {
        p_id: document.getElementById('admin-project-id').value.trim().toLowerCase(),
        p_nombre: document.getElementById('admin-project-name').value.trim()
    }), 'Obra creada.');
}

async function adminUpdateProject(id, currentName, active) {
    const name = window.prompt('Nombre de la obra:', currentName);
    if (!name) return;
    await workspaceAction(async () => supabaseClient.rpc('fn_conterreno_admin_actualizar_proyecto', {
        p_id: id,
        p_nombre: name.trim(),
        p_activo: active
    }), active ? 'Obra activada.' : 'Obra desactivada.');
}

async function adminChangeRole(userId) {
    const role = document.getElementById(`role-${userId}`).value;
    const reason = window.prompt('Justificación del cambio de rol (mínimo 10 caracteres):');
    if (!reason) return;
    await workspaceAction(async () => supabaseClient.rpc('fn_promover_usuario', {
        p_id_usuario_a_promover: userId,
        p_nuevo_codigo_rol: role,
        p_justificacion_capacitacion: reason
    }), 'Rol actualizado.');
}

async function adminAssignProject(userId) {
    const projectId = document.getElementById(`project-${userId}`).value;
    await workspaceAction(async () => supabaseClient.rpc('fn_conterreno_admin_asignar_proyecto', {
        p_id_usuario: userId,
        p_proyecto_id: projectId
    }), 'Asignación de obra actualizada.');
    if (userId === currentUser.id) {
        try {
            await loadUserProjects();
        } catch (error) {
            showToast(error.message, 'error');
        }
    }
}

async function adminDeactivateUser(userId) {
    const reason = window.prompt('Motivo de desactivación (mínimo 5 caracteres):');
    if (!reason) return;
    await workspaceAction(async () => supabaseClient.rpc('fn_conterreno_admin_desactivar_usuario', {
        p_id_usuario: userId,
        p_motivo: reason
    }), 'Usuario desactivado.');
}

async function loadStorekeeperOrders() {
    await workspaceQuery('storekeeper-material-orders', supabaseClient
        .from('conterreno_pedidos_materiales')
        .select('id,solicitado_por,solicitante_nombre,destino,urgencia,estado,items,creado_en,motivo_resolucion')
        .eq('proyecto_id', state.currentProject)
        .order('creado_en', { ascending: true })
        .limit(50), renderStorekeeperOrders);
}

function renderStorekeeperOrders(orders) {
    const target = document.getElementById('storekeeper-material-orders');
    if (!target) return;
    target.innerHTML = orders.length
        ? orders.map(order => {
            const pending = order.estado === 'Pendiente';
            const statusClass = order.estado === 'Entregado'
                ? 'bg-emerald-100 text-emerald-800'
                : order.estado === 'Rechazado'
                    ? 'bg-rose-100 text-rose-800'
                    : 'bg-amber-100 text-amber-800';
            const items = Array.isArray(order.items) ? order.items : [];
            return `<article class="rounded-xl border border-slate-200 p-4">
                <div class="flex flex-wrap items-start justify-between gap-2">
                    <div>
                        <strong class="text-slate-900">Pedido ${escapeHtml(order.id)}</strong>
                        <p class="mt-1 text-xs text-slate-500">${escapeHtml(new Date(order.creado_en).toLocaleString('es-CL'))} · Solicitante ${escapeHtml(order.solicitante_nombre || order.solicitado_por)}</p>
                    </div>
                    <span class="rounded-full px-2 py-1 text-[10px] font-bold ${statusClass}">${escapeHtml(order.estado)} · ${escapeHtml(order.urgencia)}</span>
                </div>
                <p class="mt-2 text-xs"><strong>Destino:</strong> ${escapeHtml(order.destino)}</p>
                <ul class="mt-2 space-y-1 text-xs">${items.map(item =>
                    `<li>${escapeHtml(item.name || item.material_id || 'Material')} — ${escapeHtml(item.qty)} ${escapeHtml(item.unit || '')}</li>`
                ).join('')}</ul>
                ${order.motivo_resolucion ? `<p class="mt-2 rounded-lg bg-rose-50 p-2 text-xs text-rose-800"><strong>Motivo de rechazo:</strong> ${escapeHtml(order.motivo_resolucion)}</p>` : ''}
                ${pending ? `<div class="mt-3 flex flex-wrap gap-2">
                    <button type="button" data-order-id="${escapeHtml(order.id)}" onclick="storekeeperProcessMaterialOrder(this.dataset.orderId, 'DESPACHAR')" class="rounded-lg bg-emerald-700 px-3 py-2 text-xs font-bold text-white">Despachar pedido completo</button>
                    <button type="button" data-order-id="${escapeHtml(order.id)}" onclick="storekeeperProcessMaterialOrder(this.dataset.orderId, 'RECHAZAR')" class="rounded-lg bg-rose-50 px-3 py-2 text-xs font-bold text-rose-700">Rechazar</button>
                </div>` : ''}
            </article>`;
        }).join('')
        : '<p class="rounded-lg bg-emerald-50 p-3 text-emerald-800">No hay pedidos de materiales para esta obra.</p>';
}

async function storekeeperProcessMaterialOrder(orderId, action) {
    let reason = null;
    if (action === 'DESPACHAR') {
        if (!window.confirm('Se descontarán todos los materiales solicitados. El pedido debe despacharse completo. ¿Continuar?')) return;
    } else if (action === 'RECHAZAR') {
        reason = window.prompt('Motivo del rechazo (mínimo 3 caracteres):');
        if (reason === null) return;
        if (reason.trim().length < 3) {
            showToast('El motivo del rechazo debe tener al menos 3 caracteres.', 'error');
            return;
        }
    } else {
        showToast('Acción de pedido no válida.', 'error');
        return;
    }

    await workspaceAction(async () => supabaseClient.rpc(
        'fn_conterreno_bodeguero_procesar_pedido',
        {
            p_proyecto_id: state.currentProject,
            p_pedido_id: orderId,
            p_accion: action,
            p_motivo: reason
        }
    ), action === 'DESPACHAR' ? 'Pedido despachado y stock actualizado.' : 'Pedido rechazado.');
}

async function loadManagerWorkspace() {
    await Promise.all([
        workspaceQuery('manager-pending-loans', supabaseClient
            .from('prestamos')
            .select('id_prestamo,id_equipo,id_trabajador,id_bodeguero,fecha_hora_salida,estado_devolucion')
            .eq('proyecto_id', state.currentProject)
            .is('fecha_hora_devolucion', null)
            .order('fecha_hora_salida'), renderPendingLoans),
        loadAvailableTools('manager-tool-inventory'),
        workspaceQuery('manager-stock-alerts', supabaseClient
            .from('conterreno_alertas_stock')
            .select('id,material_id,cantidad_actual,stock_minimo,creada_en,conterreno_catalogo_materiales(nombre,unidad)')
            .eq('proyecto_id', state.currentProject).eq('estado', 'ACTIVA')
            .order('creada_en', { ascending: false }), renderStockAlerts),
        workspaceQuery('manager-daily-reports', supabaseClient
            .from('conterreno_reportes_prestamos_diarios')
            .select('fecha_reporte,total_pendientes,prestamos_pendientes,generado_en')
            .eq('proyecto_id', state.currentProject)
            .order('fecha_reporte', { ascending: false }).limit(7), renderDailyReports),
        loadKardex('manager-kardex')
    ]);
}

function renderStockAlerts(alerts, targetId = 'manager-stock-alerts') {
    document.getElementById(targetId).innerHTML = alerts.length
        ? alerts.map(alert => `<div class="rounded-lg border border-rose-200 bg-rose-50 p-3">
            <strong class="text-rose-900">${escapeHtml(alert.conterreno_catalogo_materiales?.nombre || 'Material')}</strong>
            <p class="text-xs text-rose-800">Disponible: ${escapeHtml(alert.cantidad_actual)} ${escapeHtml(alert.conterreno_catalogo_materiales?.unidad || '')} · mínimo ${escapeHtml(alert.stock_minimo)}</p>
        </div>`).join('')
        : '<p class="rounded-lg bg-emerald-50 p-3 text-emerald-800">Sin alertas de stock activas.</p>';
}

function renderDailyReports(reports) {
    document.getElementById('manager-daily-reports').innerHTML = reports.length
        ? reports.map(report => `<details class="rounded-lg border border-slate-200 p-3">
            <summary class="cursor-pointer text-xs font-bold">${escapeHtml(report.fecha_reporte)} · ${escapeHtml(report.total_pendientes)} pendientes</summary>
            <p class="mt-1 text-[11px] text-slate-500">Generado: ${escapeHtml(new Date(report.generado_en).toLocaleString('es-CL'))}</p>
            <pre class="mt-2 overflow-auto rounded bg-slate-50 p-2 text-[10px]">${escapeHtml(JSON.stringify(report.prestamos_pendientes, null, 2))}</pre>
        </details>`).join('')
        : '<p>No hay reportes diarios guardados. Debe habilitarse pg_cron y programar la tarea en Supabase.</p>';
}

async function loadWorkers() {
    const generation = roleWorkspaceGeneration;
    const { data, error } = await supabaseClient.rpc('fn_conterreno_listar_trabajadores', {
        p_proyecto_id: state.currentProject
    });
    if (generation !== roleWorkspaceGeneration) return;
    const select = document.getElementById('loan-worker-select');
    if (!select) return;
    if (error) {
        select.innerHTML = '<option value="">No fue posible cargar trabajadores</option>';
        showToast(`No se pudieron cargar trabajadores: ${error.message}`, 'error');
        return;
    }
    select.innerHTML = '<option value="">Selecciona un trabajador</option>' +
        (data || []).map(worker => `<option value="${worker.id_usuario}">${escapeHtml(worker.nombre_completo)} · ${escapeHtml(worker.rut)}</option>`).join('');
}

async function loadTools() {
    const generation = roleWorkspaceGeneration;
    const { data, error } = await supabaseClient.from('equipos_herramientas')
        .select('id_equipo,codigo_tag_iot,numero_serie,nombre,descripcion,estado_fisico,disponible')
        .eq('proyecto_id', state.currentProject).eq('activo', true).order('nombre');
    if (generation !== roleWorkspaceGeneration) return;
    if (error) {
        showToast(`No se pudo cargar el inventario: ${error.message}`, 'error');
        return;
    }
    const available = (data || []).filter(tool => tool.disponible && tool.estado_fisico === 'OPTIMO');
    const select = document.getElementById('loan-tool-select');
    if (select) select.innerHTML = '<option value="">Selecciona una herramienta disponible</option>' +
        available.map(tool => `<option value="${tool.id_equipo}">${escapeHtml(tool.nombre)} · ${escapeHtml(tool.codigo_tag_iot)}</option>`).join('');
    const target = document.getElementById('tool-scan-result');
    if (target) {
        target.innerHTML = data?.length
            ? `<div class="overflow-x-auto"><table class="w-full min-w-[720px] text-left text-xs"><thead class="text-slate-500"><tr><th class="p-2">Herramienta</th><th class="p-2">Etiqueta</th><th class="p-2">Estado</th><th class="p-2">Disponibilidad</th><th class="p-2">Acción Bodega</th></tr></thead><tbody>${data.map(tool =>
                `<tr class="border-t border-slate-100"><td class="p-2">${escapeHtml(tool.nombre)}</td><td class="p-2">${escapeHtml(tool.codigo_tag_iot)}</td><td class="p-2">${escapeHtml(tool.estado_fisico)}</td><td class="p-2">${tool.disponible ? 'Disponible' : 'En uso'}</td><td class="p-2"><select id="tool-state-${tool.id_equipo}" class="rounded border border-slate-300 p-1"><option value="OPTIMO" ${tool.estado_fisico === 'OPTIMO' ? 'selected' : ''}>Óptimo</option><option value="DANIADO" ${tool.estado_fisico === 'DANIADO' ? 'selected' : ''}>Dañado</option><option value="EN_MANTENCION" ${tool.estado_fisico === 'EN_MANTENCION' ? 'selected' : ''}>En mantención</option><option value="DADO_DE_BAJA" ${tool.estado_fisico === 'DADO_DE_BAJA' ? 'selected' : ''}>Dado de baja</option></select><button data-tool-id="${tool.id_equipo}" data-tool-name="${escapeHtml(tool.nombre)}" data-tool-description="${escapeHtml(tool.descripcion || '')}" onclick="storekeeperUpdateTool(this.dataset.toolId,this.dataset.toolName,this.dataset.toolDescription)" class="ml-1 rounded bg-slate-900 px-2 py-1 text-white">Editar</button></td></tr>`
            ).join('')}</tbody></table></div>`
            : '<p>No hay herramientas registradas en esta obra.</p>';
    }
}

async function loadAvailableTools(targetId) {
    const generation = roleWorkspaceGeneration;
    const { data, error } = await supabaseClient.from('equipos_herramientas')
        .select('codigo_tag_iot,numero_serie,nombre,estado_fisico,disponible')
        .eq('proyecto_id', state.currentProject).eq('activo', true).order('nombre');
    if (generation !== roleWorkspaceGeneration || !document.getElementById(targetId)) return;
    if (error) {
        showWorkspaceError(targetId, new Error(error.message));
        return;
    }
    const tools = data || [];
    document.getElementById(targetId).innerHTML = tools.length
        ? `<table class="w-full min-w-[460px] text-left text-xs"><thead class="text-slate-500"><tr><th class="p-2">Herramienta</th><th class="p-2">Etiqueta</th><th class="p-2">Estado</th><th class="p-2">Disponibilidad</th></tr></thead><tbody>${tools.map(tool =>
            `<tr class="border-t border-slate-100"><td class="p-2">${escapeHtml(tool.nombre)}</td><td class="p-2">${escapeHtml(tool.codigo_tag_iot)}</td><td class="p-2">${escapeHtml(tool.estado_fisico)}</td><td class="p-2">${tool.disponible ? 'Disponible' : 'En uso'}</td></tr>`
        ).join('')}</tbody></table>`
        : '<p>No hay herramientas registradas en esta obra.</p>';
}

async function storekeeperUpdateTool(toolId, currentName, currentDescription) {
    const name = window.prompt('Nombre de la herramienta:', currentName);
    if (!name) return;
    const description = window.prompt('Descripción:', currentDescription);
    if (description === null) return;
    await workspaceAction(async () => supabaseClient.rpc('fn_conterreno_actualizar_herramienta', {
        p_proyecto_id: state.currentProject,
        p_id_equipo: toolId,
        p_nombre: name.trim(),
        p_descripcion: description.trim(),
        p_estado_fisico: document.getElementById(`tool-state-${toolId}`).value
    }), 'Herramienta actualizada.');
}

async function findToolByTag(event) {
    if (event?.preventDefault) event.preventDefault();
    const tag = typeof event === 'string' ? event : document.getElementById('tool-scan-code').value.trim();
    if (!roleWorkspaceReady()) return showToast('Inicia sesión con Supabase para buscar etiquetas.', 'error');
    const { data, error } = await supabaseClient.from('equipos_herramientas')
        .select('id_equipo,nombre,codigo_tag_iot,estado_fisico,disponible')
        .eq('proyecto_id', state.currentProject).eq('codigo_tag_iot', tag).maybeSingle();
    const result = document.getElementById('tool-scan-result');
    if (error) return showWorkspaceError('tool-scan-result', new Error(error.message));
    result.insertAdjacentHTML('afterbegin', data
        ? `<div class="mb-3 rounded-lg ${data.disponible ? 'bg-emerald-50 text-emerald-900' : 'bg-amber-50 text-amber-900'} p-3">
            <strong>${escapeHtml(data.nombre)}</strong> · ${escapeHtml(data.estado_fisico)} · ${data.disponible ? 'Disponible' : 'No disponible'}
        </div>`
        : '<p class="mb-3 rounded-lg bg-rose-50 p-3 text-rose-800">No se encontró una herramienta activa con esa etiqueta en esta obra.</p>');
}

let toolCameraStream = null;
let toolCameraTimer = null;
let toolCameraProcessing = false;

async function startToolCameraScan() {
    const status = document.getElementById('tool-camera-status');
    const video = document.getElementById('tool-camera-preview');
    if (!roleWorkspaceReady()) {
        showToast('Inicia sesión con Supabase antes de escanear.', 'error');
        return;
    }
    if (!('BarcodeDetector' in window)) {
        if (status) status.textContent = 'Este navegador no ofrece lectura QR/barra por cámara. Usa un escáner USB/Bluetooth o escribe el código.';
        return;
    }
    try {
        const formats = await BarcodeDetector.getSupportedFormats();
        const supported = formats.filter(format => ['qr_code', 'code_128', 'code_39', 'ean_13', 'ean_8', 'upc_a', 'upc_e'].includes(format));
        if (!supported.length) throw new Error('El navegador no admite formatos QR o de barras compatibles.');
        const detector = new BarcodeDetector({ formats: supported });
        toolCameraStream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
        video.srcObject = toolCameraStream;
        video.classList.remove('hidden');
        await video.play();
        status.textContent = 'Apunta la cámara al código de la herramienta.';
        toolCameraTimer = window.setInterval(async () => {
            if (toolCameraProcessing) return;
            toolCameraProcessing = true;
            try {
                const codes = await detector.detect(video);
                if (codes.length) {
                    document.getElementById('tool-scan-code').value = codes[0].rawValue;
                    stopToolCameraScan();
                    await findToolByTag(codes[0].rawValue);
                }
            } catch (error) {
                stopToolCameraScan();
                if (status) status.textContent = `No se pudo leer el código: ${error.message}`;
            } finally {
                toolCameraProcessing = false;
            }
        }, 350);
    } catch (error) {
        stopToolCameraScan();
        if (status) status.textContent = `No se pudo iniciar la cámara: ${error.message}`;
    }
}

function stopToolCameraScan() {
    if (toolCameraTimer) window.clearInterval(toolCameraTimer);
    toolCameraTimer = null;
    toolCameraProcessing = false;
    if (toolCameraStream) toolCameraStream.getTracks().forEach(track => track.stop());
    toolCameraStream = null;
    const video = document.getElementById('tool-camera-preview');
    if (video) {
        video.pause();
        video.srcObject = null;
        video.classList.add('hidden');
    }
}

async function storekeeperCreateTool(event) {
    event.preventDefault();
    await workspaceAction(async () => supabaseClient.rpc('fn_conterreno_crear_herramienta', {
        p_proyecto_id: state.currentProject,
        p_codigo_tag_iot: document.getElementById('new-tool-tag').value.trim(),
        p_numero_serie: document.getElementById('new-tool-serial').value.trim(),
        p_nombre: document.getElementById('new-tool-name').value.trim(),
        p_descripcion: document.getElementById('new-tool-description').value.trim() || null
    }), 'Herramienta registrada.');
}

async function storekeeperRegisterLoan(event) {
    event.preventDefault();
    await workspaceAction(async () => supabaseClient.rpc('fn_conterreno_registrar_prestamo', {
        p_proyecto_id: state.currentProject,
        p_id_equipo: document.getElementById('loan-tool-select').value,
        p_id_trabajador: document.getElementById('loan-worker-select').value
    }), 'Préstamo registrado. El trabajador debe firmar la recepción.');
}

async function loadOpenLoans(targetId) {
    const generation = roleWorkspaceGeneration;
    const { data, error } = await supabaseClient.from('prestamos')
        .select('id_prestamo,id_equipo,id_trabajador,fecha_hora_salida,estado_devolucion')
        .eq('proyecto_id', state.currentProject).is('fecha_hora_devolucion', null)
        .order('fecha_hora_salida');
    if (generation !== roleWorkspaceGeneration) return;
    if (error) {
        showWorkspaceError(targetId, new Error(error.message));
        return;
    }
    const open = data || [];
    const target = document.getElementById(targetId);
    if (target) target.innerHTML = open.length
        ? `<div class="space-y-2">${open.map(loan => `<div class="rounded-lg bg-slate-50 p-3 text-xs">
            <strong>${escapeHtml(loan.id_equipo)}</strong> · ${escapeHtml(loan.estado_devolucion)} · ${escapeHtml(new Date(loan.fecha_hora_salida).toLocaleString('es-CL'))}
        </div>`).join('')}</div>` : '<p>No hay préstamos abiertos.</p>';
    const select = document.getElementById('return-loan-select');
    if (select) select.innerHTML = '<option value="">Selecciona el equipo recibido</option>' +
        open.filter(loan => loan.estado_devolucion === 'PENDIENTE').map(loan =>
            `<option value="${loan.id_prestamo}">${escapeHtml(loan.id_equipo)} · ${escapeHtml(loan.id_trabajador)}</option>`
        ).join('');
}

async function storekeeperRegisterReturn(event) {
    event.preventDefault();
    const condition = document.getElementById('return-condition').value;
    const file = document.getElementById('return-evidence').files[0];
    if (condition === 'DEVUELTO_CON_DANOS' && !file) {
        showToast('Adjunta una foto para registrar una devolución con daños.', 'error');
        return;
    }
    await workspaceAction(async () => {
        let path = null;
        if (file) path = await uploadWorkspaceEvidence(file, 'devolucion');
        return supabaseClient.rpc('fn_conterreno_registrar_devolucion', {
            p_id_prestamo: document.getElementById('return-loan-select').value,
            p_estado_devolucion: condition,
            p_evidencia_storage_path: path,
            p_observacion: document.getElementById('return-observation').value.trim() || null
        });
    }, 'Devolución registrada.');
}

async function loadMaterialStock() {
    const generation = roleWorkspaceGeneration;
    const { data, error } = await supabaseClient.from('conterreno_stock_materiales')
        .select('material_id,cantidad,stock_minimo,conterreno_catalogo_materiales!inner(nombre,codigo,unidad,activo)')
        .eq('proyecto_id', state.currentProject)
        .eq('conterreno_catalogo_materiales.activo', true)
        .order('material_id');
    if (generation !== roleWorkspaceGeneration) return;
    if (error) {
        showWorkspaceError('storekeeper-material-stock', new Error(error.message));
        return;
    }
    const rows = data || [];
    const select = document.getElementById('stock-material-select');
    if (select) select.innerHTML = '<option value="">Selecciona un material</option>' +
        rows.map(row => `<option value="${row.material_id}" data-min="${row.stock_minimo}">${escapeHtml(row.conterreno_catalogo_materiales.nombre)} · ${escapeHtml(row.conterreno_catalogo_materiales.codigo)}</option>`).join('');
    const table = document.getElementById('storekeeper-material-stock');
    if (table) table.innerHTML = rows.length
        ? `<table class="w-full min-w-[460px] text-left text-xs"><thead class="text-slate-500"><tr><th class="p-2">Material</th><th class="p-2">Existencia</th><th class="p-2">Mínimo</th><th class="p-2">Alerta</th></tr></thead><tbody>${rows.map(row =>
            `<tr class="border-t border-slate-100"><td class="p-2">${escapeHtml(row.conterreno_catalogo_materiales.nombre)}</td><td class="p-2">${escapeHtml(row.cantidad)} ${escapeHtml(row.conterreno_catalogo_materiales.unidad)}</td><td class="p-2">${escapeHtml(row.stock_minimo)}</td><td class="p-2">${Number(row.stock_minimo) > 0 && Number(row.cantidad) <= Number(row.stock_minimo) ? '<span class="font-bold text-rose-700">Stock bajo</span>' : 'Normal'}</td></tr>`
        ).join('')}</tbody></table>` : '<p>No hay materiales cargados en esta obra.</p>';
}

async function storekeeperCreateMaterial(event) {
    event.preventDefault();
    await workspaceAction(async () => supabaseClient.rpc('fn_conterreno_bodeguero_crear_material', {
        p_proyecto_id: state.currentProject,
        p_codigo: document.getElementById('new-material-code').value.trim(),
        p_nombre: document.getElementById('new-material-name').value.trim(),
        p_unidad: document.getElementById('new-material-unit').value.trim(),
        p_stock_minimo: Number(document.getElementById('new-material-min').value)
    }), 'Material agregado al catálogo de la obra.');
}

async function storekeeperAdjustStock(event) {
    event.preventDefault();
    await workspaceAction(async () => supabaseClient.rpc('fn_conterreno_bodeguero_ajustar_stock', {
        p_proyecto_id: state.currentProject,
        p_material_id: document.getElementById('stock-material-select').value,
        p_tipo: document.getElementById('stock-movement-type').value,
        p_cantidad: Number(document.getElementById('stock-quantity').value),
        p_stock_minimo: Number(document.getElementById('stock-minimum').value),
        p_motivo: document.getElementById('stock-reason').value.trim()
    }), 'Movimiento de stock registrado.');
}

let workerLoanToSign = null;

async function loadWorkerLoans() {
    const generation = roleWorkspaceGeneration;
    loadAvailableTools('worker-tool-inventory');
    loadWorkerMaterialStock();
    const { data, error } = await supabaseClient.from('prestamos')
        .select('id_prestamo,id_equipo,fecha_hora_salida,estado_devolucion,firma_storage_path')
        .eq('proyecto_id', state.currentProject)
        .eq('id_trabajador', currentUser.id)
        .order('fecha_hora_salida', { ascending: false });
    if (generation !== roleWorkspaceGeneration) return;
    if (error) {
        showWorkspaceError('worker-loans', new Error(error.message));
        return;
    }
    const loans = data || [];
    document.getElementById('worker-loans').innerHTML = loans.length
        ? loans.map(loan => `<button onclick="selectWorkerLoan('${loan.id_prestamo}')" class="block w-full rounded-xl border ${loan.estado_devolucion === 'PENDIENTE_FIRMA' ? 'border-amber-300 bg-amber-50' : 'border-slate-200 bg-white'} p-3 text-left">
            <span class="flex justify-between gap-2"><strong>Herramienta ${escapeHtml(loan.id_equipo)}</strong><span class="text-xs">${escapeHtml(loan.estado_devolucion)}</span></span>
            <span class="mt-1 block text-xs text-slate-500">${escapeHtml(new Date(loan.fecha_hora_salida).toLocaleString('es-CL'))}</span>
        </button>`).join('')
        : '<p>No tienes préstamos asociados a esta obra.</p>';
    const pending = loans.find(loan => loan.estado_devolucion === 'PENDIENTE_FIRMA');
    if (pending) selectWorkerLoan(pending.id_prestamo);
    initializeSignaturePad();
}

async function loadWorkerMaterialStock() {
    const generation = roleWorkspaceGeneration;
    const { data, error } = await supabaseClient.from('conterreno_stock_materiales')
        .select('cantidad,stock_minimo,conterreno_catalogo_materiales!inner(nombre,unidad,activo)')
        .eq('proyecto_id', state.currentProject)
        .eq('conterreno_catalogo_materiales.activo', true);
    if (generation !== roleWorkspaceGeneration || !document.getElementById('worker-material-stock')) return;
    if (error) {
        showWorkspaceError('worker-material-stock', new Error(error.message));
        return;
    }
    const stock = data || [];
    document.getElementById('worker-material-stock').innerHTML = stock.length
        ? `<table class="w-full min-w-[400px] text-left text-xs"><thead class="text-slate-500"><tr><th class="p-2">Material</th><th class="p-2">Existencia</th><th class="p-2">Disponibilidad</th></tr></thead><tbody>${stock.map(row =>
            `<tr class="border-t border-slate-100"><td class="p-2">${escapeHtml(row.conterreno_catalogo_materiales.nombre)}</td><td class="p-2">${escapeHtml(row.cantidad)} ${escapeHtml(row.conterreno_catalogo_materiales.unidad)}</td><td class="p-2">${Number(row.stock_minimo) > 0 && Number(row.cantidad) <= Number(row.stock_minimo) ? '<span class="font-bold text-rose-700">Bajo stock</span>' : '<span class="text-emerald-700">Disponible</span>'}</td></tr>`
        ).join('')}</tbody></table>` : '<p>No hay materiales en el catálogo de esta obra.</p>';
}

function selectWorkerLoan(loanId) {
    workerLoanToSign = loanId;
    const label = document.getElementById('worker-signature-loan');
    if (label) label.textContent = `Préstamo seleccionado: ${loanId}`;
}

function initializeSignaturePad() {
    const canvas = document.getElementById('worker-signature-pad');
    if (!canvas || canvas.dataset.ready) return;
    const context = canvas.getContext('2d');
    context.lineWidth = 4;
    context.lineCap = 'round';
    context.strokeStyle = '#0f172a';
    let drawing = false;
    const point = event => {
        const rect = canvas.getBoundingClientRect();
        const source = event.touches?.[0] || event;
        return {
            x: (source.clientX - rect.left) * canvas.width / rect.width,
            y: (source.clientY - rect.top) * canvas.height / rect.height
        };
    };
    const start = event => {
        event.preventDefault();
        drawing = true;
        const p = point(event);
        context.beginPath();
        context.moveTo(p.x, p.y);
    };
    const move = event => {
        if (!drawing) return;
        event.preventDefault();
        const p = point(event);
        context.lineTo(p.x, p.y);
        context.stroke();
    };
    const stop = () => { drawing = false; };
    canvas.addEventListener('pointerdown', start);
    canvas.addEventListener('pointermove', move);
    canvas.addEventListener('pointerup', stop);
    canvas.addEventListener('pointerleave', stop);
    canvas.dataset.ready = 'true';
}

function clearWorkerSignature() {
    const canvas = document.getElementById('worker-signature-pad');
    if (canvas) canvas.getContext('2d').clearRect(0, 0, canvas.width, canvas.height);
}

async function workerSignLoan() {
    const canvas = document.getElementById('worker-signature-pad');
    if (!workerLoanToSign || !canvas) return showToast('Selecciona un préstamo pendiente de firma.', 'error');
    const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
    if (!pixels.some((value, index) => index % 4 === 3 && value > 0)) {
        return showToast('Dibuja tu firma antes de confirmar la recepción.', 'error');
    }
    await workspaceAction(async () => {
        const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
        if (!blob) throw new Error('No se pudo preparar la imagen de firma.');
        const path = await uploadWorkspaceEvidence(blob, 'firma');
        const digest = await crypto.subtle.digest('SHA-256', await blob.arrayBuffer());
        const hash = [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('');
        return supabaseClient.rpc('fn_conterreno_confirmar_prestamo', {
            p_id_prestamo: workerLoanToSign,
            p_firma_storage_path: path,
            p_firma_sha256: hash
        });
    }, 'Firma registrada y recepción confirmada.');
}

async function uploadWorkspaceEvidence(blob, prefix) {
    const path = `${state.currentProject}/${currentUser.id}/${crypto.randomUUID()}-${prefix}`;
    const { error } = await supabaseClient.storage.from('conterreno-evidencias').upload(path, blob, {
        contentType: blob.type || 'image/png',
        upsert: false
    });
    if (error) throw new Error(`No se pudo cargar la evidencia: ${error.message}`);
    return path;
}

async function workspaceAction(action, successMessage) {
    if (!roleWorkspaceReady()) {
        showToast('Acción disponible después de conectar Supabase con una cuenta autorizada.', 'error');
        return;
    }
    if (workspaceActionBusy) {
        showToast('Hay una operación en curso. Espera su resultado antes de continuar.', 'error');
        return;
    }

    const content = document.getElementById('role-workspace-content');
    const openCards = [...(content?.querySelectorAll('details.workspace-card') || [])];
    const openCardIndex = openCards.findIndex(card => card.open);
    const openCardId = openCardIndex >= 0 ? openCards[openCardIndex].id : '';
    const scrollPosition = window.scrollY;
    workspaceActionBusy = true;
    setWorkspaceActionLocks(true);
    const status = document.getElementById('role-workspace-action-status');
    if (status) {
        status.textContent = 'Guardando cambios…';
        status.classList.remove('hidden');
    }

    let actionError = '';
    try {
        const { data, error } = await action();
        if (error) throw new Error(error.message);
        showToast(successMessage, 'success');
        renderRoleWorkspace();
        const updatedContent = document.getElementById('role-workspace-content');
        const updatedCards = [...(updatedContent?.querySelectorAll('details.workspace-card') || [])];
        const restoredCard = openCardId
            ? updatedCards.find(card => card.id === openCardId)
            : updatedCards[openCardIndex];
        if (restoredCard) restoredCard.open = true;
        window.requestAnimationFrame(() => window.scrollTo(0, scrollPosition));
        return data;
    } catch (error) {
        actionError = error.message || 'No se pudo completar la operación.';
        showToast(actionError, 'error');
    } finally {
        workspaceActionBusy = false;
        setWorkspaceActionLocks(false);
        if (status) {
            if (actionError) {
                status.textContent = `No se guardaron los cambios: ${actionError}`;
                status.classList.remove('hidden');
                window.setTimeout(() => {
                    if (status.textContent === `No se guardaron los cambios: ${actionError}`) {
                        status.textContent = '';
                        status.classList.add('hidden');
                    }
                }, 7000);
            } else {
                status.textContent = '';
                status.classList.add('hidden');
            }
        }
    }
}

function setWorkspaceActionLocks(locked) {
    const content = document.getElementById('role-workspace-content');
    if (!content) return;
    content.setAttribute('aria-busy', String(locked));
    if (locked) {
        content.querySelectorAll('button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled])')
            .forEach(control => {
                control.disabled = true;
                control.dataset.workspaceLocked = 'true';
            });
        return;
    }
    content.querySelectorAll('[data-workspace-locked="true"]').forEach(control => {
        control.disabled = false;
        delete control.dataset.workspaceLocked;
    });
}

function renderPendingLoans(loans) {
    document.getElementById('manager-pending-loans').innerHTML = loans.length
        ? `<table class="w-full min-w-[620px] text-left text-xs"><thead class="text-slate-500"><tr><th class="p-2">Equipo</th><th class="p-2">Trabajador (UUID)</th><th class="p-2">Salida</th><th class="p-2">Estado</th></tr></thead><tbody>
            ${loans.map(loan => `<tr class="border-t border-slate-100"><td class="p-2">${escapeHtml(loan.id_equipo)}</td><td class="p-2">${escapeHtml(loan.id_trabajador)}</td><td class="p-2">${escapeHtml(new Date(loan.fecha_hora_salida).toLocaleString('es-CL'))}</td><td class="p-2 font-bold text-rose-700">${escapeHtml(loan.estado_devolucion)}</td></tr>`).join('')}
        </tbody></table>`
        : '<p class="rounded-lg bg-emerald-50 p-3 text-emerald-800">No hay préstamos pendientes de devolución.</p>';
}
