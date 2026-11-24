# Checklist de preparación para Supabase

## Alcance y criterio de estado

Este checklist describe el esquema y el cliente de ConTerreno. **Implementado
en archivos** no significa que cada flujo de la aplicación esté probado.
El usuario confirmó que ya hizo pruebas manuales de las migraciones; no es
necesario repetirlas en remoto en esta etapa. El historial versionado
`supabase/migrations/` sigue siendo la fuente de verdad para instalaciones
nuevas.

## Informe por fases

### Fase 1 — Base funcional remota: parcialmente lista

- [x] Esquema relacional principal, roles y permisos definidos.
- [x] Supabase Auth y asignación de rol/obra implementados.
- [x] Migraciones versionadas preparadas.
- [x] El usuario confirmó pruebas manuales de las migraciones existentes; no
  repetirlas durante la actual etapa de pruebas locales de la aplicación.
- [x] RLS, RPC y almacenamiento privado definidos.
- [x] `admin-create-user` está desplegada y activa; la creación de cuentas
  desde el panel aún requiere una prueba funcional.
- [x] El usuario confirmó que `20261122200000_seguridad_historial_plazos.sql`
  está aplicada; se comprobaron en remoto los objetos que valida
  `verify_setup.sql`.
- [x] Hay cuentas activas de prueba para los cuatro roles y se verificó su
  autenticación y perfil remoto.
- [ ] Registrar y reconciliar el historial de migraciones. El 23-11-2026 la
  CLI no mostró versiones remotas y `supabase_migrations.schema_migrations`
  no existe, aunque el esquema y las funciones sí están desplegados. No hacer
  `db push` ni `migration repair` sobre este proyecto hasta resolver el
  historial de forma controlada.

### Fase 2 — Tareas e incidencias: mejoras locales listas, remotas pendientes

- [x] La interfaz carga responsables desde cuentas reales de la obra.
- [x] Las tareas pueden guardar `responsable_id`, además del nombre visible.
- [x] Las incidencias pueden guardar `responsable_id`, además del nombre visible.
- [x] La vista de Operario filtra tareas e incidencias propias o asignadas.
- [x] Jefatura/Admin conservan la creación y administración general de tareas.
- [x] El Operario recibe permiso local para cambiar sus tareas asignadas.
- [x] Agregar la migración
  `20261122170000_relaciones_tareas_incidencias.sql`.
- [x] Verificar las columnas `responsable_id` y la función
  `fn_conterreno_listar_responsables` en el proyecto remoto.
- [x] Validar que Jefatura puede crear tareas y asignar Operarios.
- [x] Validar que el Operario solo puede actualizar sus tareas asignadas.
- [x] Validar que el Operario ve sus tareas asignadas y sus incidencias propias.
- [x] Validar que Jefatura puede atender la incidencia creada y cambiar su estado.
- [ ] Validar que Jefatura puede cerrar la incidencia y confirmar su estado remoto.
- [x] Crear cuentas reales de prueba Jefe de obra, Operario y probar su inicio
  de sesión en el proyecto remoto.
- [x] Crear una tarea Jefatura→Operario y comprobar actualización remota a
  "En Ejecución".
- [x] Crear una incidencia desde el Operario y comprobar su persistencia.
- [x] Verificar que Jefatura puede ver la incidencia creada y disponer de
  controles de atención y cierre.
- [x] Verificar que Admin inicia sesión y muestra perfiles, obras y solicitudes.
- [x] Verificar que Bodega inicia sesión y muestra su panel operativo.

### Fase 3 — Herramientas y préstamos: parcialmente lista

- [x] CRUD de herramientas en Bodega implementado por RPC.
- [x] Alta rápida y búsqueda por etiqueta/QR implementadas.
- [x] Registro de préstamo y devolución implementado.
- [x] Firma de recepción con Canvas y hash SHA-256 implementada.
- [ ] Verificar firma, Storage privado y devolución en Supabase remoto.
- [ ] Verificar permisos concurrentes y rechazo de préstamos duplicados.
- [ ] Sustituir la eliminación física por baja lógica en toda la operación y
  documentación.
- [x] Incorporar contenedores con scroll y encabezados visibles para inventarios
  extensos.

### Fase 4 — Materiales y pedidos: parcialmente lista

- [x] Catálogo, stock, movimientos y alertas preparados.
- [x] Solicitud operativa y despacho transaccional implementados.
- [ ] Validar stock insuficiente, rechazo y doble despacho remoto.
- [ ] Verificar que Jefatura, Bodega y Operario ven únicamente datos
  correspondientes a sus permisos.
- [ ] Completar trazabilidad de materiales usados y devueltos por tarea.
- [x] Limitar cargas masivas principales a lotes de 200-300 registros.
- [x] Añadir búsqueda de perfiles y scroll interno en tablas administrativas.

### Fase 5 — Compras, facturas y proveedores: base SQL preparada; interfaz y pruebas pendientes

- [ ] Crear catálogo de proveedores.
- [ ] Registrar órdenes de compra y aprobaciones.
- [ ] Registrar recepciones físicas separadas de facturación.
- [ ] Vincular facturas a proveedor, orden y recepción.
- [ ] Detectar duplicados y diferencias de cantidades o montos.
- [ ] Definir permisos de consulta y aprobación financiera.
- [x] Preparar migración de proveedores, órdenes, recepciones y facturas.
- [x] Preparar funciones RPC seguras para proveedores y órdenes.
- [ ] Aplicar y probar el módulo remoto de compras y facturas.

### Fase 7 — Asistencia: parcialmente lista

- [x] Agregar marcaje propio de entrada y salida por obra.
- [x] Aplicar la migración de asistencia y comprobar entrada remota.
- [x] Comprobar que una segunda entrada abierta sea rechazada.
- [x] Comprobar que la salida cierre el marcaje abierto.

### Migración 8 — asistencia y compras

- [x] Aplicar `20261122180000_asistencia_compras.sql` en el proyecto remoto.
- [x] Ejecutar `supabase/verify_setup.sql`; todas las comprobaciones de
  objetos, roles y permisos dieron `OK`.
- [x] Probar entrada, salida y proveedor por cuenta autenticada.
- [ ] Completar pruebas de proveedores, órdenes, recepciones y facturas.

### Fase 8 — Seguridad, historial y plazos: migración aplicada; validación pendiente

- [x] Incluir control de tres intentos consecutivos por cuenta y origen, con
  bloqueo de 15 minutos, sin almacenar correo o dirección IP en texto claro.
- [x] Conectar los formularios de acceso con la función Edge `auth-lockout`;
  si falla el control, el inicio de sesión no continúa desde esos formularios.
- [x] Cerrar la sesión local tras 15 minutos de inactividad y sincronizar la
  actividad entre pestañas; dejar 15 minutos en la configuración local de Auth.
- [ ] Configurar y verificar el timeout de 15 minutos en el Auth remoto (puede
  depender del plan de Supabase).
- [x] Añadir historial por rol con filtro de hasta 31 días, salida XLSX e
  impresión/guardar como PDF; los resultados tienen tope de 1.000 filas y
  exigen reducir el rango antes de exportar si se alcanza ese tope.
- [x] Añadir vigencia y jornada por obra, fechas de tareas y vencimiento de
  préstamos, con validación en SQL.
- [x] El usuario confirmó la aplicación de
  `20261122200000_seguridad_historial_plazos.sql`; `verify_setup.sql` encontró
  los objetos requeridos en el remoto.
- [x] Desplegar `auth-lockout` con verificación JWT desactivada para permitir
  la comprobación previa al inicio de sesión; generar y guardar
  `AUTH_LOCKOUT_HASH_SECRET` solo en Supabase.
- [x] Verificar que la función quede activa y que la llamada del SDK desde el
  navegador a `action: check` responda HTTP 200 con el contador disponible.
- [ ] Probar con los cuatro roles consultas permitidas/denegadas, intentos,
  expiración, exportaciones y validaciones de plazo en Supabase.
- [ ] Configurar el límite de inactividad de Auth en el proyecto remoto y
  confirmar que el plan permite aplicarlo.
- [ ] Recordar que el contador propio protege los formularios de la web, no es
  una barrera de Auth para clientes externos; conservar y probar los límites
  nativos de Supabase Auth.
- [x] Confirmar que el control de intentos a nivel de formulario es una
  protección adicional aceptada; conservar y probar los límites nativos.
  Supabase Auth no aplica este contador personalizado a sus endpoints públicos;
  un cliente externo puede omitir el formulario.
- [x] Mantener la jornada como configuración común por obra. Los turnos
  individuales por trabajador no forman parte del alcance actual.

### Fase 9 — Porcentaje mensual de asistencia: corregido y validado; jornadas pendientes

- [x] Calcular porcentaje mensual usando jornadas programadas transcurridas con
  entrada marcada; una salida pendiente se señala aparte.
- [x] Incorporar el día actual cuando se marca entrada o al terminar la
  jornada; así el porcentaje se actualiza con cada marcaje sin asumir ausencias
  durante una jornada todavía en curso.
- [x] Mostrar “No calculable” cuando la obra no tenga jornada configurada o no
  existan jornadas programadas transcurridas en el mes.
- [x] Restringir la consulta: Administración global, Jefatura en su obra y
  Bodega/Operario solo su propio registro.
- [x] Añadir paginación para informes grandes y un límite explícito que obliga
  a filtrar por obra antes de presentar resultados incompletos.
- [x] El usuario confirmó la aplicación de
  `20261123010000_porcentaje_asistencia_mensual.sql`; remoto confirma la función,
  permisos y lógica para incorporar el día de entrada.
- [x] Autenticar cuentas de los cuatro roles y verificar que sus perfiles
  coinciden con el rol esperado.
- [x] Confirmar que Jefatura, Bodega y Operario reciben denegación al omitir la
  obra o consultar una obra no asignada.
- [x] Aplicar manualmente `20261123020000_fix_asistencia_mensual_result_types.sql`;
  la verificación remota confirmó los casts y todas las comprobaciones en `OK`.
- [x] Probar la RPC con los cuatro roles: Administración recibió 7 filas en
  2 obras; Jefatura 6 filas de su obra; Bodega y Operario recibieron una fila
  propia cada uno. Se confirmaron denegaciones de alcance y de fecha inválida.
- [ ] Configurar los días y horarios reales de las obras antes de validar
  porcentajes calculables. Las obras consultadas no tienen jornada configurada;
  el estado `SIN_JORNADA_CONFIGURADA` es correcto y no debe reemplazarse por
  horarios supuestos.

### Fase 6 — Diseño local actualizado; publicación y pruebas remotas pendientes

- [x] Revisar los cuatro roles localmente a 390, 768, 1024 y 1440 px; no se
  detectó desbordamiento horizontal de la página.
- [x] Comprobar la navegación visible por rol con datos aislados; Bodega y
  las acciones operativas no se presentan igual a todos los perfiles.
- [x] Mejorar el Kanban móvil con columnas desplazables horizontalmente y menor
  altura; añadir tamaños táctiles y prioridad de acciones para Operario.
- [x] Añadir historial filtrable de solicitudes del Operario y filtros de
  incidencias por estado, prioridad y sector; búsqueda en solicitudes, obras
  y auditoría.
- [x] Comprobar con un cliente simulado que, sin sesión, ante error del servicio
  o si la operación afecta cero filas, no se modifica la vista ni se informa
  éxito.
- [ ] Completar revisión de teclado, contraste, lector de pantalla y pruebas
  con cuentas/datos reales en el proyecto remoto.
- [x] Retirar KPIs, porcentajes, curvas y actividad que eran datos ficticios;
  el acceso inicia ahora en el panel correspondiente al rol.
- [ ] Ejecutar pruebas remotas con cuentas reales y registrar evidencias.
- [ ] Preparar el informe final con resultados comprobados y pendientes.

El esquema cubre cuatro roles humanos: Administrador del sistema, Jefe de obra,
Bodeguero y Trabajador/operario. El Kardex sigue siendo inalterable: incluso el
Administrador consulta y registra movimientos por operaciones autorizadas, no
edita ni borra eventos.

## Qué falta implementar — lista priorizada

Este es el orden recomendado para terminar el sistema. El código local contiene
las funciones marcadas como implementadas, pero aún no se ha certificado contra
la base Supabase remota ni con usuarios reales.

### Bloqueadores antes de abrirlo al equipo

1. **Terminar la configuración de Supabase**
   - [ ] Para un proyecto **vacío**, aplicar en orden las once migraciones y
     ejecutar `supabase/verify_setup.sql`.
   - [ ] Para el proyecto existente, resolver primero el historial remoto
     ausente; no ejecutar `db push`, `migration repair` ni reset hasta tener
     un procedimiento revisado y un respaldo.
   - [ ] Crear el primer Administrador y ejecutar el bootstrap una sola vez.
   - [x] La Edge Function `admin-create-user` está desplegada.
   - [ ] Probar la creación de cuenta desde el panel sin repetir las pruebas
     manuales de migraciones.
   - [ ] Probar los tres intentos, el bloqueo y su expiración; revisar también
     los límites nativos de Auth del proyecto.

2. **Probar permisos y operaciones con cuentas reales**
   - [x] Ya existen cuentas de prueba para los cuatro roles; reutilizarlas en
     las pruebas funcionales cuando se realicen.
   - [ ] Probar los permisos permitidos y denegados por rol en RLS, RPC y
     Storage, incluida la separación de datos entre obras.
   - [ ] Probar el flujo de pedido en la aplicación: solicitud, despacho, stock
     insuficiente, rechazo, reintento y doble procesamiento.
   - [ ] Confirmar firma propia, devolución/evidencia de daño y que nadie pueda
     modificar o borrar el Kardex directamente.
   - [x] La interfaz ahora rechaza operaciones sin sesión/Supabase y no reporta
     éxito cuando una actualización o eliminación afecta cero filas; se
     comprobó localmente con respuestas simuladas.
   - [ ] Probar errores reales de red y permisos con la matriz de roles cuando
     se retomen las pruebas de integración.

3. **Preparar cuentas y correo de producción**
   - [ ] Comprar o disponer de un dominio propio; verificarlo con el proveedor
     de correo y configurar DNS (DKIM/SPF y DMARC recomendado).
   - [ ] Configurar un SMTP de producción en Supabase y ajustar el límite de
     correo al volumen que soporta el proveedor.
   - [ ] Publicar la web con HTTPS y configurar Site URL, Redirect URLs y
     enlaces de confirmación/recuperación para el dominio definitivo.
   - [ ] Probar altas, confirmación, inicio de sesión y recuperación con varios
     proveedores de correo; revisar Auth Logs y spam.

### Funcionalidad pendiente por rol

#### Matriz de chequeos funcionales por rol

| Rol | Debe poder probar | Debe rechazar | Evidencia requerida | Estado |
|---|---|---|---|---|
| Administrador | Crear cuenta, revisar solicitudes, asignar rol/obra, crear obra, gestionar proveedores, consultar auditoría e historial global dentro de su permiso | Prestar herramientas, despachar pedidos, registrar devoluciones, registrar asistencia propia como Operario | Captura del alta, asignación aplicada y registros persistidos | Pendiente de pruebas remotas |
| Jefatura | Consultar su obra, inventario, préstamos abiertos, alertas, Kardex, tareas, incidencias y asistencia mensual | Crear herramientas, registrar préstamos/devoluciones, despachar pedidos, cambiar stock o firmar por Operarios | Captura de consulta permitida y error esperado al intentar una acción ajena | Pendiente de pruebas remotas |
| Bodeguero | Crear/actualizar herramientas, consultar inventario, registrar préstamos/devoluciones, crear materiales, ajustar stock, procesar pedidos y consultar Kardex | Consultar obras no asignadas, aprobar cuentas, crear obras o cambiar roles | Alta, consulta, actualización, mantenimiento, devolución y Kardex persistido | Sin ejecutar por sesión perdida |
| Operario | Ver tareas/incidencias propias, marcar asistencia propia, solicitar materiales, ver préstamos propios y firmar recepción propia | Crear herramientas, actualizar inventario, registrar préstamos/devoluciones ajenas, despachar pedidos, cambiar stock o consultar obras ajenas | Entrada/salida, firma propia, solicitud propia y denegación al intentar operaciones ajenas | Pendiente de pruebas remotas |

#### Chequeos mínimos antes de cada ejecución

- [ ] Aplicar la migración correctiva de hash Kardex y ejecutar
  `supabase/verify_setup.sql`; todas las filas deben mostrar `OK`.
- [ ] Iniciar sesión desde la página de acceso sin conservar sesiones antiguas
  entre roles.
- [ ] Confirmar obra, rol y correo visibles en el panel sin mostrar la
  contraseña ni datos personales en la captura.
- [ ] Usar solo códigos y series que comiencen con `PRUEBA-` y nombres
  ficticios para herramientas y materiales.
- [ ] Repetir cada operación permitida una vez para verificar persistencia y
  una vez como otro rol para verificar denegación.
- [ ] Capturar el resultado del navegador y el estado remoto, cuando la tabla o
  RPC permita consultarlo sin exponer datos personales.
- [ ] Verificar que una operación fallida no muestre éxito, no altere la vista
  local ni genere filas Kardex inexistentes.

4. **Trabajador**
   - [x] Implementar marcaje propio de entrada/salida y resumen mensual de
     asistencia.
   - [x] La corrección de tipos de la RPC se aplicó y se probó con los cuatro
     roles; las jornadas reales por obra todavía deben configurarse.
   - [x] Mostrar “Mis solicitudes” con material, destino, fecha, estado,
     motivo de rechazo, filtro y actualización. Usa la lista que retorna la
     consulta existente, sujeta a RLS; queda pendiente repetir la prueba de
     aislamiento de pedidos en remoto.
   - [ ] Probar que solo vea y firme sus préstamos, y que no pueda operar stock,
     herramientas, tareas ni solicitudes ajenas.

5. **Jefe de obra**
   - [x] El panel consulta por obra préstamos, alertas, reportes, Kardex,
     tareas sin completar e incidencias abiertas.
   - [ ] Definir una fuente semanal confiable antes de calcular PPC; no
     presentar curvas, costos ni avances que no estén respaldados por datos.
   - [ ] Configurar `pg_cron`, zona horaria `America/Santiago`, snapshot diario
     y destinatarios; o indicar claramente que el reporte no es automático.

6. **Administrador**
   - [x] Búsqueda disponible para cuentas, solicitudes, obras y auditoría.
   - [x] Decisión del usuario: mantener a Administración sin lectura global
     de préstamos y pedidos; no añadir esas métricas ni operaciones de Bodega.

7. **Bodega y notificaciones**
   - [ ] Confirmar en Supabase alertas y pedidos por obra, con migración
     desplegada y acceso autorizado.
   - [ ] Definir destinatarios/canal para alertas de stock bajo; hoy la
     aplicación las registra y consulta, pero no las envía.
   - [ ] Probar escáner/cámara, préstamos concurrentes, devoluciones repetidas
     y evidencia obligatoria si hay daño.
   - [ ] Aplicar y probar el alta masiva de herramientas: máximo 100 unidades,
     etiquetas y series únicas por lote, marca opcional de prueba y Kardex.
   - [ ] Confirmar que “En préstamo” solo se muestra con un préstamo abierto;
     mantenimiento, daño y baja se muestran como estados físicos independientes.
   - [ ] Aplicar y probar las solicitudes de herramientas: Operario solicita y
     cancela pendientes; Bodega aprueba o rechaza; Jefatura solo supervisa.
   - [ ] Verificar el resumen de stock por modelo junto con el listado individual
     de etiquetas y estados en Bodega, Jefatura y Operario.

### Mejoras transversales

- [x] Bloquear temporalmente controles del espacio de trabajo mientras una
  operación está en curso y anunciar el estado/error.
- [x] Evitar dobles envíos desde la interfaz, y restaurar la tarjeta abierta y
  la posición de desplazamiento tras una operación exitosa.
- [ ] Probar dobles clics y reintentos con cada rol contra Supabase; la
  interfaz no sustituye la idempotencia y autorización del servidor.
- [x] Evitar el éxito falso si falta la sesión/Supabase o si actualizar/eliminar
  no afecta filas; comprobado localmente con un cliente simulado.
- [ ] Validar la migración nueva y ejecutar las pruebas de lockout, inactividad,
  historial/exportación y fechas en una instancia Supabase de prueba.
- [x] Excluir configuración local, contraseñas y PDFs del repositorio; ofrecer
  un ejemplo de configuración sin claves.
- [x] Quitar la referencia a un `seed.sql` ausente; roles y permisos iniciales
  se siembran desde la migración base.
- [x] Sustituir los datos personales del bootstrap por marcadores que deben
  reemplazarse localmente antes de ejecutarlo.

### Cierre de diseño, publicación y operación

8. **Diseño responsive y accesible**
   - [x] Revisar localmente los cuatro roles en móvil/tablet/escritorio y
     ajustar controles táctiles, formularios de jornada y navegación del
     Kanban para móvil.
   - [ ] Completar verificación de teclado, contraste, lectores de pantalla,
     tablas extensas, errores y estados vacíos/de carga.
   - [ ] Eliminar las vistas, gráficos, KPIs y actividad de demostración que
     permanezcan en el HTML y puedan confundirse con datos reales.

9. **Operación continua**
   - [ ] Definir respaldos y restauración probada, rotación de credenciales y
     procedimiento de despliegue/rollback.
   - [ ] Confirmar dominio, HTTPS, SMTP, redirects y pruebas de aceptación antes
     de invitar a todo el personal.

## Instalación limpia de Supabase

Este procedimiento es solo para un proyecto nuevo y vacío. El proyecto remoto
actual ya tiene objetos desplegados, pero no conserva la tabla de historial de
migraciones; **no ejecutes aquí `db push` ni `migration repair`**. Primero debe
revisarse y reconciliarse ese historial con un plan de respaldo.

Ejecuta estos comandos desde la carpeta raíz del proyecto en la terminal de
VS Code. `PROJECT_ID` es el identificador del proyecto Supabase, no la URL ni la
contraseña de la cuenta de la aplicación:

```powershell
npx supabase login
npx supabase link --project-ref <PROJECT_ID>
npx supabase migration list --remote
npx supabase db push --remote --dry-run
npx supabase db push --remote
npx supabase migration list --remote
npx supabase functions deploy admin-create-user
```

La base remota recién creada debe mostrar inicialmente cero migraciones
aplicadas. El `dry-run` debe listar las once versiones locales, en este orden:

1. `20261110120000_base_esquema.sql` — esquema, roles, permisos, RLS,
   auditoría/Kardex, obras de ejemplo y datos base.
2. `20261110125700_solicitudes_asignacion_roles.sql` — registro Auth pendiente
   y asignación administrativa de rol/obra.
3. `20261110131400_admin_global_access.sql` — acceso global del administrador
   en las funciones de autorización.
4. `20261110134600_reparar_auditoria_usuarios.sql` — asegura tabla, RLS,
   permisos e inmutabilidad de auditoría.
5. `20261110160900_fix_auditoria_usuarios_search_path.sql` — asegura la tabla
   y corrige el trigger para resolver la bitácora siempre en `public`.
6. `20261110162800_pedidos_materiales_despacho_atomico.sql` — conecta los
   pedidos al catálogo y stock reales, con despacho completo o rechazo
   transaccional y registro en Kardex.
7. `20261122170000_relaciones_tareas_incidencias.sql` — vincula tareas e
   incidencias con responsables reales de la obra y agrega actualización propia
   de tareas para el Operario.
8. `20261122180000_asistencia_compras.sql` — agrega control de asistencia y
   operaciones de proveedores y compras.
9. `20261122200000_seguridad_historial_plazos.sql` — agrega intentos de acceso,
   historial, vigencia de obras y plazos de tareas y préstamos.
10. `20261123010000_porcentaje_asistencia_mensual.sql` — agrega el resumen de
    asistencia mensual con permisos específicos por rol.
11. `20261123020000_fix_asistencia_mensual_result_types.sql` — corrige los
    tipos de texto devueltos por la RPC mensual de asistencia.

Si `migration list` ya muestra versiones remotas, `dry-run` no lista las once,
o existen objetos pero no hay historial, **detente**. No uses `migration repair`
ni un reset remoto sin un plan específico. `db reset` debe reservarse para el
entorno local (requiere Docker); no lo uses para limpiar datos remotos.

`login` usa un personal access token del propietario/desarrollador y `link`
puede pedir la contraseña de la base de datos. No uses la contraseña del
administrador de la aplicación y no guardes tokens ni contraseñas en archivos
del proyecto.

Después de `db push` en el proyecto nuevo, ejecuta
[`supabase/verify_setup.sql`](./supabase/verify_setup.sql)
en SQL Editor de Supabase. Todas las filas deben indicar `OK`.
Si aparece `relation "auditoria_usuarios" does not exist`, no repitas el alta:
confirma primero que la migración `20261110160900` esté aplicada y vuelve a
ejecutar la consulta de verificación para revisar la tabla y su trigger.

### Crear el primer administrador

Las migraciones no pueden crear la identidad de Auth ni una contraseña inicial.
Después de aplicar las once migraciones en un proyecto nuevo:

1. En **Authentication → Users → Add user**, crea el usuario inicial y marca
   su correo como confirmado. Define allí su contraseña.
2. Abre [`supabase/bootstrap_first_admin.sql`](./supabase/bootstrap_first_admin.sql),
   reemplaza los valores de ejemplo por correo, RUT, nombres y apellidos de esa
   cuenta, y ejecútalo una sola vez en SQL Editor.
3. Inicia sesión en la web. El bootstrap asigna `ADMIN_GENERAL` y la obra
   `p1`, que viene creada por la migración base.

El archivo de bootstrap es aprovisionamiento inicial, **no una migración**:
contiene datos específicos de una persona y no debe subirse al historial.

### Crear más cuentas desde el panel

La función `admin-create-user` se despliega después de la base. Administración
crea la identidad sin invitación ni correo, recibe una contraseña aleatoria
una sola vez y luego asigna rol/obra desde las solicitudes pendientes. Si la
cuenta Auth ya existe, la función la identifica y no inventa ni revela una
contraseña nueva. Nunca pongas una clave `secret` o `service_role` en el cliente.

Para cada cambio futuro de base de datos, crea una migración nueva y aplícala
con `db push`; no edites versiones ya aplicadas:

```powershell
npx supabase migration new descripcion_corta_del_cambio
# Escribir/revisar SQL en supabase/migrations/
npx supabase db push --remote --dry-run
npx supabase db push --remote
```

Para que otros equipos usen la aplicación, publica la carpeta `Proyecto` en un
hosting HTTPS y permite su URL en **Authentication → URL Configuration**. La
URL del hosting no es la conexión a la base; el cliente sigue usando Project
URL + publishable key en `Proyecto/supabase-config.js`.

### Correo de confirmación para decenas de cuentas

El registro público de `Proyecto/index.html` usa `auth.signUp` y solicita un
correo de confirmación. El SMTP de prueba de Supabase permite actualmente solo
2 correos por hora. La cuota es por proyecto y cuenta cada mensaje enviado,
aunque cada usuario use una dirección distinta; no es un límite de usuarios.
Para producción, sigue este proceso:

1. **Elige un proveedor SMTP.** Por ejemplo Resend, Brevo, SendGrid, Postmark,
   AWS SES o el SMTP de tu organización. Crea una cuenta y revisa sus cuotas,
   precios y límites de envío. Para 40 altas en poco tiempo, el proveedor debe
   permitir ese volumen, además de los mensajes posteriores de recuperación y
   cambio de correo.
2. **Verifica tu dominio remitente en el proveedor.** Usa un dominio que
   controles, por ejemplo `tudominio.cl`, y define un remitente como
   `no-reply@tudominio.cl`. Copia los registros DNS que el proveedor indique
   (normalmente DKIM y SPF; configura DMARC si el proveedor lo recomienda).
   Añádelos donde administras el DNS del dominio y espera a que el proveedor lo
   marque como verificado. No uses una dirección remitente de un dominio que no
   controlas.
3. **Obtén las credenciales SMTP del proveedor.** Guarda host, puerto, usuario
   y contraseña SMTP (algunos proveedores entregan una clave SMTP distinta de
   la clave general de API). No las pongas en `Proyecto`, en el HTML, en
   `supabase-config.js`, ni en este archivo.
4. **Configura Supabase.** Abre el proyecto correcto en
   [Supabase Dashboard](https://supabase.com/dashboard) y ve a
   **Authentication → SMTP Settings** (en algunas versiones aparece como
   **Authentication → Settings → SMTP**). Activa el envío por SMTP personalizado
   y completa los campos:
   - **Sender email / From address:** `no-reply@tudominio.cl`
   - **Sender name:** `BuildTech ConTerreno`
   - **Host:** host SMTP entregado por el proveedor
   - **Port:** el puerto SMTP indicado, comúnmente `587` con STARTTLS
   - **Username / Password:** credenciales SMTP del proveedor

   Guarda los cambios. No copies credenciales a código del navegador; deben
   guardarse únicamente en la configuración protegida de Supabase.
5. **Ajusta el límite de Auth.** En el mismo proyecto abre
   **Authentication → Rate Limits** y busca el límite de correos enviados
   (`Email sent` / `rate_limit_email_sent`). Con SMTP personalizado, Supabase
   aplica inicialmente un límite conservador de 30 mensajes por hora. Define un
   valor que cubra el pico real (por ejemplo, 60 correos/hora si esperas 40
   registros confirmados en una hora) y que no supere la cuota ni la velocidad
   contratada al proveedor. Este límite incluye los demás correos de Auth, no
   solo las altas.
6. **Prueba antes de abrir el registro a todo el personal.** Crea una cuenta de
   prueba desde la web con un correo que puedas revisar; confirma que llega el
   mensaje y que su enlace vuelve al dominio publicado correcto. Prueba también
   una segunda dirección y revisa **Authentication → Logs** y spam. Después
   ejecuta varias altas de prueba dentro del ritmo esperado y confirma que no
   aparezca `email rate limit exceeded`. No hagas pruebas masivas con correos
   reales de trabajadores.
7. **Habilita el despliegue.** Cuando las pruebas pasen, comparte el enlace de
   registro. Si el proveedor alcanza su propia cuota, elevar el límite de Auth
   no aumenta la capacidad SMTP: amplía el plan o baja la velocidad de envíos.

La aplicación tiene dos caminos distintos:

- **Registro público / `Crear cuenta`:** manda el correo de confirmación y usa
  SMTP. Este camino necesita los pasos anteriores.
- **Panel de Administración / `Crear cuenta de acceso`:** la Edge Function
  `admin-create-user` crea la identidad ya confirmada y no envía correo. No
  consume el límite de confirmaciones; Administración debe entregar la
  contraseña inicial por un canal privado. Si aquí aparece `email rate limit
  exceeded`, revisa que esté desplegada la versión actual de la función y
  consulta **Authentication → Logs**; no aumentes el límite SMTP como primera
  solución.

`supabase/config.toml` aplica a desarrollo local o a proyectos autohospedados;
editar `email_sent` en ese archivo no cambia los límites de un proyecto Supabase
alojado. Consulta la documentación oficial de [SMTP personalizado](https://supabase.com/docs/guides/auth/auth-smtp)
y [límites de Auth](https://supabase.com/docs/guides/auth/rate-limits).

## Resumen

| Estado | Elemento | Evidencia / pendiente |
|---|---|---|
| ✅ Listo en archivos | El SQL usa Supabase Auth como autoridad de identidad; el perfil referencia el UUID de `auth.users`. No guarda contraseñas propias. | `Base de datos posgreSQL/Base de datos.sql` |
| ✅ Listo en archivos | Están definidos cuatro roles legibles, una matriz explícita de permisos y reglas distintas para cada responsabilidad. | Sección de roles y permisos del SQL |
| ✅ Listo en archivos | Se configuraron RLS, privilegios mínimos, operaciones administrativas protegidas y un bucket privado para evidencias. | El SQL es la autoridad; ocultar botones en la web no protege datos. |
| ✅ Listo en archivos | El Kardex tiene política append-only: lectura autorizada; los movimientos se agregan en operaciones validadas, no por INSERT directo del cliente. | RPC autorizadas escriben el movimiento dentro de la transacción operativa. |
| ✅ Listo en archivos | Hay funciones SQL para alta/actualización de herramientas, préstamo, firma de recepción y devolución con estado/evidencia. | Implementadas en el esquema; aún sin validación contra Supabase. |
| ✅ Listo en archivos | Se añadieron paneles de trabajo y navegación diferenciados para los cuatro roles; las pestañas visibles coinciden con las secciones permitidas y sus accesos rápidos funcionan con el mismo control. | `Proyecto/role-screens.js` y `Proyecto/buildtech_field_os_conterreno.html`; las operaciones deben seguir protegidas por RLS/RPC. |
| ✅ Listo en archivos | La entrada `index.html` ofrece inicio de sesión y registro sin selector de rol; consulta la asignación real en Supabase antes de redirigir a la interfaz correspondiente. | `Proyecto/index.html` y las páginas de rol. |
| ✅ Listo en archivos | Se añadieron tablas de catálogo, stock por obra, movimientos inalterables y alertas automáticas al alcanzar el mínimo configurado. | El movimiento también genera evento Kardex. No está probado contra un proyecto Supabase. |
| ✅ Verificado | La web inicia/cierra sesión y los perfiles Auth de los cuatro roles coinciden con sus roles asignados en remoto. | La RPC mensual fue corregida y probada por rol. Las obras aún requieren jornadas reales para obtener porcentajes calculables. |
| ✅ Verificado | La URL configurada en el navegador coincide con el proyecto Supabase enlazado por CLI y usa una clave publicable. | No incluir nunca claves `secret` o `service_role` en el cliente. |
| ✅ Listo en archivos | Las once migraciones versionadas contienen el esquema base, roles, asistencia, compras, seguridad, historial, plazos y reporte mensual. | El remoto carece de tabla de historial de migraciones; no ejecutar `db push` ni `migration repair` hasta reconciliarlo. |
| ✅ Listo en archivos | Se añadió un bootstrap manual para crear el primer perfil `ADMIN_GENERAL` después de crear su identidad en Auth. | [`supabase/bootstrap_first_admin.sql`](./supabase/bootstrap_first_admin.sql); reemplazar datos y ejecutar una sola vez. |
| ✅ Listo en archivos | Se añadió una consulta de verificación para tablas, funciones y RLS requeridos. | [`supabase/verify_setup.sql`](./supabase/verify_setup.sql); ejecutar después de `db push` y revisar que cada estado sea `OK`. |
| 🟡 Parcial | El panel crea cuentas Auth sin invitación, con contraseña inicial aleatoria de un solo vistazo. | `admin-create-user` está activa en remoto; falta probar el alta desde el panel. El registro público sí puede consumir límites de email. |
| 🟡 Parcial | El alta evita duplicar una cuenta Auth que ya existe si una respuesta anterior se perdió. | La función está desplegada; falta probar esa ruta. Si el error aparece desde Administración, revisar Auth Logs antes de reintentar. |
| 🟡 Parcial | El SQL de verificación remoto informó `OK`, incluidos los casts de la RPC mensual; las cuatro cuentas demo autenticaron y la consulta quedó probada por rol. | Las jornadas de las obras siguen sin configurar y el historial remoto de migraciones no existe. |
| 🟡 Parcial | El esquema y las funciones están desplegados según `verify_setup.sql`. | Las versiones no están registradas en CLI; el historial debe resolverse antes de volver a usar `db push`. |
| ⬜ Pendiente | Publicar la web en un host HTTPS para que otras computadoras puedan usarla. | Live Server solo sirve para desarrollo local; configurar después las Redirect URLs de Auth para el dominio publicado. |
| ⬜ Pendiente | Ejecutar pruebas de aceptación y de denegación para cada rol, RLS, RPC y Storage en Supabase. | Ver matriz de cierre más abajo. |
| 🟡 Parcial | Existe una función SQL para generar snapshots diarios de préstamos pendientes y una pantalla de historial para Jefatura. | Falta habilitar pg_cron, programarlo a las 18:00 hora Chile y definir el canal de notificación/entrega. |
| 🟡 Parcial | La solicitud de materiales se valida en una RPC y Bodega puede despachar el pedido completo o rechazarlo; el despacho descuenta stock y registra movimientos/Kardex en una transacción. | Los objetos están presentes en remoto; falta validar concurrencia, rechazos, falta de stock y permisos en Supabase. |

## Roles y límites de responsabilidad

Los nombres y descripciones deben mantenerse consistentes en SQL y web. Los
permisos siguientes se aplican por obra asignada; tener un botón visible en la
interfaz nunca concede acceso por sí solo.

| Rol | Puede hacer | No puede hacer |
|---|---|---|
| **Administrador del sistema** (`ADMIN_GENERAL`) | Gestión global de cuentas, roles y obras; consulta de auditoría, alertas y Kardex según las políticas existentes. | No procesa préstamos, pedidos ni movimientos de stock en nombre de Bodega. El Kardex es de solo lectura y no se modifica ni borra. |
| **Jefe de obra** (`JEFE_OBRA`) | Consultar inventario, préstamos pendientes y alertas de stock de sus obras; gestionar incidencias y planificar/eliminar tareas. | Administrar cuentas/roles; registrar préstamos/devoluciones; cambiar herramientas o existencias. |
| **Bodeguero** (`BODEGUERO`) | Consultar y mantener herramientas y stock; registrar préstamos/devoluciones; despachar o rechazar pedidos de materiales completos. | Administrar usuarios/roles; planificar tareas o gestionar incidencias; firmar la recepción en nombre del trabajador; realizar despachos parciales. |
| **Trabajador / operario** (`OPERARIO_MAESTRO`) | Consultar inventario y préstamos propios; firmar su recepción; marcar su asistencia; reportar incidencias; solicitar materiales y actualizar tareas asignadas. | Crear/eliminar tareas o modificar las de otros; cambiar herramientas/stock, registrar préstamos/devoluciones, procesar pedidos, administrar roles o gestionar incidencias ajenas. |

### Inventario funcional actual por rol

Este inventario describe lo que existe en los archivos de la web y migraciones,
no certifica que esté desplegado ni probado contra el proyecto remoto. `✅`
significa que hay pantalla y operación conectada en el código; `🟡` indica que
hay una parte implementada o falta validar/desplegar; `⬜` indica que falta la
función de interfaz o el flujo completo.

| Rol | Disponible ahora | Parcial o pendiente |
|---|---|---|
| **Administrador del sistema** | ✅ Crear cuentas, asignar roles/obras, crear/desactivar obras y perfiles, consultar auditoría, alertas y Kardex. ✅ Centro de control con recuentos en vivo de solicitudes pendientes, perfiles activos, obras activas y alertas; búsqueda de cuentas, solicitudes, obras y auditoría. | ✅ Decisión del usuario: conservar la separación; sin lectura global de préstamos/pedidos ni operaciones de Bodega. ⬜ Falta probar con la cuenta Admin real. |
| **Jefe de obra** | ✅ Consultar préstamos abiertos, reportes diarios existentes, herramientas, alertas y Kardex; gestionar tareas e incidencias. ✅ Resumen de obra con recuentos en vivo de tareas sin completar e incidencias abiertas y accesos directos a planificación, incidencias y préstamos. | 🟡 Reportes requieren pg_cron para generarse automáticamente. ⬜ Falta validar denegación de operaciones de Bodega y Administración. |
| **Bodeguero** | ✅ Buscar/crear herramientas, registrar préstamos/devoluciones, mantener stock, atender pedidos completos y leer Kardex. ✅ Puesto operativo con accesos directos y métricas en vivo de pedidos, préstamos, alertas y materiales con stock. | 🟡 Los objetos de pedidos existen en remoto; falta probar concurrencia, stock insuficiente, rechazo y permisos. La primera versión no admite despacho parcial. |
| **Trabajador / operario** | ✅ Consultar sus préstamos, firmar recepción, revisar herramientas/stock, registrar asistencia y reportar incidencias. ✅ Inicio personal con recuentos propios; acceso prioritario a asistencia, firmas y solicitudes; historial filtrable de sus pedidos y resumen mensual de asistencia. | 🟡 Confirmar en remoto que RLS limita las solicitudes y préstamos a la identidad del trabajador. El porcentaje mensual depende de configurar la jornada real de cada obra; las obras consultadas muestran `SIN_JORNADA_CONFIGURADA`. |
| **Todos** | ✅ Inicio/cierre de sesión, selección de obra y navegación por rol. ✅ Paneles con identidad, acento, prioridades, densidad y accesos distintos; los indicadores consultan datos de Supabase y muestran errores de carga. | 🟡 La navegación es solo UX; RLS/RPC siguen siendo autoridad. ⬜ Falta recorrido de aceptación en Supabase con cuentas reales y pruebas negativas. |

### Checklist completo de evolución por rol

Este es el backlog de interfaz y funcionalidad que se debe cerrar antes de
considerar completa la experiencia por rol. `✅` = ya existe en archivos;
`🟡` = existe parcialmente, usa datos de demostración o requiere despliegue y
validación; `⬜` = falta implementar. Una casilla marcada no significa que se
haya probado en el Supabase remoto.

#### Administrador del sistema — centro de control

- [x] Crear cuentas desde la web sin invitación; mostrar la contraseña inicial
  una sola vez.
- [x] Revisar solicitudes y asignar perfil, rol y obra.
- [x] Crear/desactivar obras; cambiar rol y asignaciones; desactivar perfiles.
- [x] Consultar auditoría, alertas y Kardex en modo lectura.
- [x] Retirar el dashboard heredado con indicadores y actividad ficticios.
- [x] Crear un centro de control inicial con solicitudes pendientes, perfiles
  activos, obras activas y alertas, con accesos a sus listas.
- [x] Mantener a Administración sin lectura global de préstamos/pedidos, según
  decisión del usuario; no añadir esas métricas ni operaciones de Bodega.
- [x] Agregar búsqueda de personas, solicitudes, obras y últimos movimientos
  de auditoría; mantener visibles los estados de cuenta y asignación.
- [x] Mantener la separación actual de roles; Administración no recibe
  operaciones globales de terreno/Bodega.
- [ ] Separar visualmente las acciones de alto impacto (crear Admin, cambiar
  roles, desactivar usuarios/obras) y pedir confirmación/motivo donde aplique.
- [ ] Probar con cuenta Admin las operaciones permitidas y confirmar que no
  puede consultar préstamos/pedidos globalmente ni editar/borrar auditoría o
  Kardex.
- [ ] Validar creación de cuentas, sesión, bloqueo/desactivación, auditoría y
  permisos con los despliegues existentes; no volver a ejecutar migraciones
  durante esta etapa.

#### Jefe de obra — supervisión y planificación

- [x] Consultar herramientas, préstamos pendientes, reportes existentes,
  alertas y Kardex de sus obras.
- [x] Iniciar en un resumen propio con métricas de préstamos, alertas, reportes
  y Kardex, además de accesos a Plan semanal e Incidencias.
- [x] Crear, mover y eliminar tareas; revisar y actualizar incidencias.
- [x] Mostrar accesos a Plan semanal e Incidencias y ocultar la operación de
  Bodega.
- [x] Mostrar en el resumen de obra conteos reales de tareas sin completar e
  incidencias abiertas, con alcance filtrado por la obra asignada.
- [ ] Completar el resumen con tareas por estado, incidencias críticas y
  préstamos vencidos; no publicar PPC hasta definir compromisos semanales como
  fuente verificable.
- [x] Mostrar responsable, prioridad, estado, fecha y evidencia; filtrar
  incidencias por estado, prioridad, sector y texto.
- [ ] Completar planificación semanal con responsable, sector, restricción y
  fechas/periodo, más un historial de cambios cuando corresponda.
- [x] Retirar la curva S, el desvío de costo y los porcentajes de avance
  ficticios. Queda pendiente incorporar tendencias cuando haya una fuente real
  de avance planificado/real.
- [ ] Configurar y probar generación diaria de reportes, zona horaria,
  retención y entrega; hasta entonces comunicar que los snapshots no son
  automáticos.
- [ ] Probar que Jefatura no puede crear usuarios, aprobar roles, registrar
  préstamos/devoluciones ni cambiar herramientas o stock.

#### Bodeguero — puesto de operación de bodega

- [x] Buscar herramientas por etiqueta/código y ofrecer escaneo por cámara o
  lector/entrada manual.
- [x] Crear herramientas; actualizar descripción, nombre y estado físico.
- [x] Registrar entregas/préstamos, devoluciones y evidencia de daño.
- [x] Crear materiales, ajustar existencias con motivo, consultar alertas y
  leer Kardex.
- [x] Crear una bandeja de pedidos por estado/prioridad/fecha y mostrar
  solicitante, obra, destino, materiales y cantidades pedidas.
- [x] Definir el ciclo inicial: `Pendiente` → `Entregado` (despacho completo)
  o `Rechazado` (con motivo); no permitir parciales ni reprocesar solicitudes.
- [x] Implementar despacho/rechazo por RPC; el despacho descuenta existencias,
  registra movimientos y Kardex en una transacción, con validación de stock y
  bloqueo del pedido para impedir doble procesamiento.
- [x] Iniciar en un puesto de bodega diferenciado con métricas y accesos al
  escáner, pedidos y devoluciones.
- [x] Reemplazar el catálogo fijo de solicitudes por catálogo/stock activo y
  validar material, unidad, obra y cantidades en la base.
- [x] El usuario confirma que aplicó y probó manualmente las migraciones; no
  repetir esa validación ahora.
- [ ] Probar después el flujo de pedidos (rechazo, falta de stock, doble clic,
  pedidos legacy, permisos por obra y concurrencia) como prueba de aplicación,
  separada de la prueba del SQL.
- [x] Añadir dashboard operativo con pedidos por preparar, préstamos abiertos,
  alertas/stock y accesos directos al escáner, pedidos y devoluciones.
- [ ] Probar concurrencia de despachos, devoluciones repetidas, fotos
  obligatorias por daño, permisos por obra y denegación de gestión de usuarios,
  tareas e incidencias.

#### Trabajador / operario — autoservicio personal

- [x] Consultar únicamente sus préstamos; ver herramientas disponibles y stock
  de su obra.
- [x] Iniciar en un resumen personal con métricas de préstamos, firmas, pedidos
  y materiales; reportar incidencia desde el panel.
- [x] Firmar recepción de sus préstamos con evidencia privada.
- [x] Enviar solicitudes de materiales y reportar incidencias.
- [x] Consultar los pedidos propios y su estado; actualizar manualmente la vista.
- [x] Solicitar desde el catálogo real; la creación valida obra, material,
  cantidad y permiso antes de insertar.
- [x] El usuario confirma que las migraciones ya fueron probadas manualmente.
- [ ] En una futura prueba de integración, confirmar que RLS limita la lectura
  a los pedidos propios y Bodega solo gestiona su obra asignada.
- [x] Priorizar en el inicio móvil la marcación de asistencia, la firma
  pendiente y la solicitud de materiales.
- [x] Agregar marcación de entrada/salida propia con rechazo de una segunda
  entrada abierta y cierre del marcaje al registrar la salida; validar la
  jornada real por obra antes de interpretar el porcentaje.
- [x] Mostrar historial de pedidos propios con materiales/cantidades, estado,
  fecha, destino y motivo de rechazo, sin consulta adicional que amplíe RLS.
- [x] Conectar el formulario de solicitud al catálogo real; elegir cantidades,
  unidad, destino y prioridad, y confirmar el envío.
- [ ] Mostrar sus incidencias reportadas y su estado sin permitir gestionar o
  cerrar incidencias ajenas.
- [x] Reducir el dashboard a información personal y de su obra autorizada;
  retirar KPIs corporativos, costos/presupuestos y contenido ficticio.
- [ ] Probar que no puede firmar préstamos de otros, consultar perfiles o
  solicitudes ajenas, modificar stock/herramientas, procesar pedidos ni
  cambiar tareas/roles.

#### Diferencias de diseño que deben conservarse

- [x] **Administrador:** aspecto de consola de gestión; navegación orientada a
  Cuentas, Solicitudes, Obras, Operaciones, Auditoría. Priorizar tablas,
  filtros, estados y confirmaciones de acciones sensibles. No copiar el panel
  de terreno como dashboard principal.
- [x] **Jefe de obra:** aspecto de tablero de supervisión por obra; poner
  indicadores, alertas, incidencias y planificación primero. Priorizar lectura
  rápida y seguimiento; no mostrar formularios de ajustes de stock o entrega.
- [x] **Bodeguero:** aspecto de puesto de trabajo de bodega, optimizado para
  tablet/teléfono y uso rápido; escáner, disponibilidad, cola de pedidos,
  préstamos y devoluciones primero. Botones grandes y flujo paso a paso;
  separar claramente entrada, salida, ajuste y despacho.
- [x] **Trabajador/operario:** experiencia móvil de autoservicio con lenguaje
  simple y pocas opciones; mostrar “Mis herramientas”, “Firmar recepción”,
  “Solicitar material”, “Mis solicitudes” y “Mi asistencia”. No mostrar
  controles administrativos ni inventario editable.
- [x] Mantener identidad visual común (marca, sesión, obra asignada,
  accesibilidad), pero dar a cada rol su nombre de panel, navegación, orden de
  contenido, acciones principales y densidad de información.
- [ ] No diferenciar permisos solo por color o por ocultar botones: mostrar el
  rol en texto y hacer cumplir cada acción mediante RLS/RPC/Storage.
- [x] Se corrigieron pestañas visibles y accesos rápidos para respetar el mapa
  actual de permisos; se renombró “Mi espacio” según el rol.
- [x] Añadir dashboards iniciales y layouts operativos propios por rol; cada
  rol tiene métricas y accesos rápidos diferentes.
- [x] Pulir la jerarquía visual con una identidad cromática y composición
  específica por rol, KPI accionables, descripciones visibles en tarjetas y
  accesos directos verificados; los cuatro paneles no desbordan a 390 px.
- [x] Convertir los formularios y operaciones secundarios del panel en
  secciones desplegables accesibles; solo una sección de trabajo permanece
  abierta a la vez para reducir el scroll.
- [x] Evitar que una tarjeta abierta estire la tarjeta contigua en escritorio;
  las opciones se acomodan en columnas independientes y se apilan en móvil.
- [x] Reorganizar perfiles y asignaciones como tarjetas individuales con
  controles separados para cambiar rol, asignar obra y desactivar el perfil.
- [x] Mantener búsqueda visible incluso cuando un filtro no devuelve perfiles;
  mejorar la lectura y el desplazamiento del historial y los registros largos.
- [x] Hacer que los accesos rápidos abran la sección objetivo y compactar
  cabecera, navegación y tarjetas KPI para escritorio y móvil.

#### Cierre compartido

- [x] Retirar la actividad/KPI/curva de demostración del dashboard heredado;
  ya no existe esa vista. Los nuevos indicadores muestran errores de carga y
  hora de actualización, pero requieren validación remota por rol.
- [x] Revisar localmente los cuatro roles a 390, 768, 1024 y 1440 px; no se
  encontró desbordamiento horizontal de la página.
- [ ] Completar revisión de teclado, lectores de pantalla, contraste, errores
  y confirmaciones con datos reales.
- [ ] Ejecutar pruebas de aceptación y denegación con una cuenta real de cada
  rol, en más de una obra; comprobar tanto la interfaz como RLS/RPC/Storage.
- [ ] Probar funcionamiento en la URL publicada con HTTPS y las redirect URLs
  de Auth definitivas.

#### Orden recomendado

1. Cerrar y probar el ciclo de pedidos Trabajador → Bodega → stock/Kardex.
2. Completar y validar en Supabase los dashboards por rol ya implementados.
3. Configurar jornadas reales en las obras y validar porcentajes calculables.
4. Conservar la decisión de no conceder lectura global de préstamos/pedidos ni
   operaciones de Bodega a Administración.
5. Completar pruebas de accesibilidad y de aceptación/denegación en Supabase.

### Regla específica del Kardex

- Los roles con permiso `KARDEX_CONSULTAR` solo pueden leer los registros que
  autoriza RLS para su obra.
- No se concede `INSERT`, `UPDATE`, `DELETE` ni `TRUNCATE` directo del Kardex a
  `anon` ni a `authenticated`. El permiso de matriz `KARDEX_INSERTAR` describe
  operaciones del sistema, no escritura libre desde el cliente.
- Las funciones operativas autorizadas insertan eventos de Kardex en la misma
  transacción que el cambio que registran. No deben añadirse escrituras manuales
  desde la interfaz.

## Checklist detallado

### Base de datos y seguridad

- [x] Definir perfiles enlazados con `auth.users` y delegar las contraseñas a
  Supabase Auth.
- [x] Definir roles, permisos y asignaciones explícitas sin permisos generales
  por módulo.
- [x] Aplicar políticas RLS por identidad, obra y permiso.
- [x] Revocar privilegios generales al cliente y otorgar únicamente operaciones
  explícitas.
- [x] Mantener el Kardex append-only y registrar movimientos desde funciones
  operativas validadas.
- [x] Mantener privadas las evidencias de Storage y restringir acceso por obra
  y usuario.
- [x] Añadir restricciones e índices para estados de préstamos y evitar más de
  un préstamo abierto por herramienta.
- [x] Normalizar catálogo y stock de materiales por obra, mantener movimientos
  append-only y generar alertas en la base cuando el stock cae al mínimo.
- [x] Versionar el esquema completo como una secuencia ordenada de migraciones
  reproducible en un proyecto Supabase vacío.
- [ ] Registrar las once migraciones en un proyecto nuevo y resolver cualquier
  incompatibilidad de ejecución antes de invitar/crear usuarios.
- [x] Ejecutar `supabase/verify_setup.sql`; todas las filas indicaron `OK`.
- [ ] Verificar en la base desplegada funciones, triggers, RLS, grants,
  secuencias, políticas de Storage e índices.
- [x] Implementar en archivos solicitudes validadas y despacho completo o
  rechazo de pedidos con actualización transaccional de stock, movimiento y
  Kardex; no se permiten despachos parciales en esta primera versión.
- [x] No repetir la prueba manual de migraciones que confirma el usuario.
- [ ] Probar por separado el flujo de pedidos desde la aplicación: stock
  insuficiente, rechazo, reintento y concurrencia.
- [ ] Habilitar pg_cron, configurar su zona horaria como
  `America/Santiago`, programar el snapshot diario a las 18:00 y definir cómo
  notificar/entregar el reporte a Jefatura.
- [ ] Resolver el historial remoto, luego aplicar los cambios futuros mediante
  migraciones; no volver a pegar manualmente scripts aplicados en SQL Editor.
- [ ] Definir respaldos, recuperación, rotación de claves y procedimiento de
  despliegue de cambios.

### Cuentas y acceso

- [x] Implementar inicio/cierre de sesión con Supabase Auth en la web.
- [x] Añadir login y registro sin selección de rol en `Proyecto/index.html`,
  además de entradas separadas por rol que verifican la asignación autenticada.
- [x] Resolver el rol y la obra desde el perfil y las asignaciones de Supabase.
- [x] Configurar `Proyecto/supabase-config.js` con Project URL y clave publicable.
- [x] Implementar registro de identidades Auth sin rol en metadatos; el
  registro no asigna permisos.
- [x] Registrar las altas nuevas y cuentas existentes sin perfil en una cola
  de solicitudes; Administración asigna perfil, rol y obra en una operación.
- [x] Crear [`supabase/bootstrap_first_admin.sql`](./supabase/bootstrap_first_admin.sql)
  para aprovisionar el primer perfil Admin de forma transaccional, después de
  crear la identidad en Auth.
- [ ] Crear/confirmar la identidad Auth inicial y ejecutar el bootstrap una vez.
- [x] Definir el alta de cuentas: registro propio o creación desde el panel
  producen una identidad Auth pendiente; la aprobación asigna perfil, rol y obra.
- [x] Implementar en archivos la creación de cuentas por Administración para el
  prototipo, sin invitación por correo ni claves privilegiadas en la web.
- [x] Desplegar `admin-create-user`; la función está activa en remoto.
- [ ] Probar desde el panel que una cuenta creada aparece pendiente, conserva
  la contraseña inicial y solo entra tras recibir rol/obra.
- [ ] Probar inicio de sesión, sesión vencida, cierre de sesión, perfil
  desactivado, usuario sin obra asignada y usuario con obra asignada.
- [ ] Probar que ningún usuario pueda cambiarse el rol, crear perfiles ni
  consultar información de otros usuarios salvo las operaciones administrativas
  previstas.

### Funciones y conexión de la web

- [x] Crear una pantalla diferenciada para cada rol dentro de la aplicación.
- [x] Integrar en las pantallas RPC de perfil/obra, herramientas, préstamos,
  firma de recepción, devolución, stock y consulta de Kardex.
- [x] Añadir escaneo QR/barra por cámara cuando el navegador lo soporta, con
  ingreso manual/lector teclado como alternativa.
- [x] Conectar incidencias, tareas y pedidos de materiales al proyecto/obra
  seleccionado para las operaciones implementadas.
- [x] Conectar solicitudes de materiales al catálogo real y procesar desde
  Bodega el despacho total o rechazo mediante RPC transaccional.
- [ ] Probar las pantallas de cada rol contra Supabase y comprobar rechazo de
  acciones no permitidas.
- [x] Añadir la modificación de herramientas desde la pantalla Bodeguero.
- [x] Vincular el despacho de pedidos con el descuento de stock, el movimiento
  inalterable y el evento Kardex en la misma transacción.
- [ ] Probar el nuevo ciclo de pedidos en Supabase antes de considerarlo listo
  para producción.
- [ ] Verificar manejo de errores de red y que la interfaz no muestre como
  guardado un cambio que Supabase rechazó.
- [x] No permitir acceso operativo sin Supabase configurado ni ofrecer un
  cambio a modo local que simule persistencia remota.

### Inventario, alertas y reportes

- [x] Definir que los materiales consumibles se gestionan en el inventario
  normalizado por obra.
- [x] Normalizar catálogo, unidades, existencias y movimientos de materiales;
  mantener mínimos y reglas de ajuste en las funciones de Bodega.
- [ ] 🟡 Definir destinatarios/frecuencia para notificaciones de stock bajo; hoy
  las alertas se crean y consultan en la aplicación, pero no se envían.
- [ ] 🟡 La función y la pantalla de reporte diario existen; falta comprobar
  programación, zona horaria, destinatarios y fallos de entrega.
- [x] Incluir tareas, incidencias y pedidos de materiales en el alcance de la
  aplicación.
- [x] Implementar la asistencia propia del Trabajador en interfaz y SQL.
- [x] Aplicar la corrección de tipos de la RPC mensual y probarla con los
  cuatro roles, incluyendo denegaciones por obra y fecha inválida.

## Pruebas de aceptación obligatorias antes de darlo por listo

- [ ] **Administrador:** puede gestionar obras, cuentas, perfiles y roles;
  probar solo las consultas/operaciones de su matriz. No debe acceder a
  préstamos/pedidos de Bodega; puede consultar auditoría/Kardex, pero no
  alterarlos/borrarlos.
- [ ] **Jefe de obra:** puede consultar inventario/préstamos, gestionar
  incidencias y planificar tareas; no puede administrar cuentas ni registrar
  préstamos/devoluciones.
- [ ] **Bodeguero:** puede crear/actualizar herramientas y registrar préstamos y
  devoluciones en su obra; puede despachar pedidos completos o rechazarlos con
  motivo; no puede asignar roles ni firmar por el trabajador.
- [ ] **Trabajador/operario:** solo puede consultar sus préstamos, firmar los
  propios, reportar y solicitar materiales desde catálogo real; no puede
  modificar herramientas, préstamos, devoluciones ni solicitudes ajenas.
- [ ] **Pedidos:** el despacho completo descuenta cada línea de stock y crea
  movimientos/Kardex de forma atómica; stock insuficiente, doble despacho,
  solicitudes mal formadas y acceso desde otra obra se rechazan.
- [ ] **Kardex:** lectura autorizada funciona; escritura directa, modificación y
  borrado por roles cliente son rechazados; cada operación permitida genera el
  evento correspondiente de forma atómica.
- [ ] **Obras:** un usuario no puede leer ni cambiar datos de una obra sin
  membresía activa, aunque manipule la petición o cambie el identificador.
- [ ] **Evidencias:** bucket privado; solo usuarios autorizados pueden cargar y
  leer rutas de su obra; las firmas y fotos no son públicas.
- [ ] **Concurrencia:** dos préstamos simultáneos de la misma herramienta no
  producen dos préstamos abiertos ni dejan una disponibilidad incoherente.
- [ ] **Datos y errores:** estados inválidos, firmas/rutas inválidas y
  devoluciones sin evidencia requerida son rechazados con error visible.

## Orden recomendado para cerrar

1. No repetir las pruebas manuales de migraciones ya confirmadas.
2. Completar las pruebas locales de interacción y estados de error de la web;
   esta etapa ya corrigió el falso éxito de operaciones sin conexión/filas.
3. En una etapa posterior autorizada, probar solicitud, despacho, rechazo,
   stock insuficiente, doble procesamiento y aislamiento por obra.
4. Probar bloqueo de acceso, sesión/inactividad y creación de cuentas desde el
   panel con las cuentas de prueba existentes.
5. Configurar jornadas reales, alertas/reportes y producción solo si se
   mantienen dentro del alcance.
