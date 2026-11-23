# Informe del proyecto ConTerreno

**Integrantes:** completar antes de entregar
**Asignatura y sección:** completar
**Docente:** completar
**Fecha:** completar

## 1. Descripción

ConTerreno es un prototipo web para apoyar tareas de una obra de construcción.
Permite iniciar sesión, asignar funciones distintas según el rol y trabajar con
herramientas, préstamos, materiales, pedidos, tareas e incidencias. La
aplicación usa Supabase para autenticación, base de datos y operaciones
autorizadas.

El proyecto está en desarrollo. Este informe separa lo que aparece en el
código de lo que ya fue desplegado y probado: la presencia de una pantalla o
una migración no confirma por sí sola el funcionamiento del proyecto remoto.

## 2. Objetivo

Organizar parte de la operación de una obra en una aplicación que concentre
información y limite las acciones disponibles según las responsabilidades de
cada persona.

## 3. Organización del código

| Ruta | Contenido |
|---|---|
| `Proyecto/index.html` | Registro, inicio de sesión y consulta del rol asignado. |
| `Proyecto/buildtech_field_os_conterreno.html` | Interfaz principal, navegación, incidencias, planificación y secciones generales. |
| `Proyecto/auth-login.js` | Llamadas de acceso a Auth y control de intentos mediante la Edge Function. |
| `Proyecto/role-screens.js` | Paneles y operaciones específicas de cada rol. |
| `Proyecto/administrador.html`, `jefe-obra.html`, `bodeguero.html`, `operario.html` | Accesos directos al panel principal con el rol correspondiente; no son controles de autorización. |
| `Proyecto/supabase-config.example.js` | Ejemplo de configuración pública para conectar el navegador. |
| `supabase/migrations/` | Cambios SQL ordenados para crear el esquema y sus funciones. |
| `supabase/functions/admin-create-user/` | Función Edge para creación administrativa de cuentas. |
| `supabase/functions/auth-lockout/` | Contador temporal con hashes HMAC para correo y origen de acceso. |
| `supabase/migrations/20261123010000_porcentaje_asistencia_mensual.sql` | Consulta mensual autorizada para porcentaje de asistencia por obra y rol. |
| `supabase/migrations/20261123020000_fix_asistencia_mensual_result_types.sql` | Corrección de tipos de texto de la respuesta mensual de asistencia. |
| `supabase/bootstrap_first_admin.sql` | Asignación inicial del primer perfil administrador; se ejecuta manualmente una vez. |
| `supabase/verify_setup.sql` | Consulta para revisar objetos necesarios después de las migraciones. |
| `Base de datos posgreSQL/Base de datos.sql` | Copia para consulta del esquema de la migración inicial; no se instala por separado. |

Las migraciones son la fuente de verdad para instalar el esquema. Los archivos
SQL antiguos sueltos en la carpeta de trabajo no forman parte del procedimiento
de instalación documentado.

## 4. Roles y permisos

| Rol | Acciones disponibles en la aplicación | Límites principales |
|---|---|---|
| Administrador del sistema | Crear cuentas, revisar solicitudes, asignar roles y obras, administrar perfiles y consultar auditoría, alertas y Kardex. | No tiene lectura global de préstamos/pedidos ni operaciones de Bodega. El Kardex se consulta; no se ofrece su modificación o borrado. |
| Jefe de obra | Consultar información de la obra, gestionar tareas e incidencias, revisar préstamos, inventario, alertas, reportes y Kardex. | No administra cuentas ni procesa préstamos, devoluciones o movimientos de stock. |
| Bodeguero | Gestionar herramientas, préstamos, devoluciones y stock; procesar pedidos completos o rechazarlos. | No gestiona cuentas, roles, planificación ni incidencias; no firma por el trabajador ni despacha parcialmente. |
| Trabajador / operario | Consultar sus préstamos y materiales, firmar su recepción, solicitar materiales, reportar incidencias y actualizar tareas asignadas. | No administra inventario, préstamos, pedidos de otras personas, roles ni tareas ajenas. |

La interfaz oculta secciones según el rol para facilitar el uso. La
autorización efectiva debe aplicarse también en PostgreSQL mediante RLS y
funciones RPC; ocultar un botón no protege los datos.

## 5. Estado de implementación

El usuario confirma que ya probó manualmente las migraciones. En esta etapa no
se repiten esas pruebas; lo pendiente descrito aquí corresponde principalmente
a la aplicación, su comportamiento ante errores y sus decisiones operativas.

| Funcionalidad | Estado en el código | Pendiente |
|---|---|---|
| Registro e inicio de sesión con Supabase Auth | Implementado | Confirmar SMTP, URLs de redirección y flujo en el dominio final; probar la Edge Function de intentos. |
| Asignación de rol y obra | Implementado mediante flujo administrativo y funciones SQL | Probar aceptación y denegación con cuentas reales. |
| Paneles diferenciados por rol | Implementados para los cuatro roles; se retiró el dashboard heredado con indicadores y actividad ficticios. Se probaron vistas locales en 390, 768, 1024 y 1440 px; se mejoraron Kanban, filtros administrativos y el historial de solicitudes del Operario. | Revisión con usuarios/datos reales, accesibilidad completa y validación de permisos en Supabase. |
| Errores de guardado | Sin sesión, filas no afectadas y errores reportados por el servicio ya no producen un éxito falso; verificado localmente con respuestas simuladas. | Probar fallos de red/RLS reales en una futura etapa de integración. |
| Herramientas, préstamos, firma y devolución | Formularios y operaciones integrados; devolución prevista añadida | Probar concurrencia, evidencia de daño y permisos del flujo cuando se retomen las pruebas de integración; no repetir la prueba de migraciones. |
| Pedidos y stock de materiales | Solicitud de trabajador y despacho/rechazo transaccional incluidos en migraciones | Probar el flujo de aplicación ante rechazo, falta de stock y doble procesamiento; la prueba manual de migraciones ya está hecha. |
| Incidencias y planificación | Vistas y operaciones presentes; el resumen de Jefatura cuenta tareas sin completar e incidencias abiertas por obra. Incidencias filtra por estado, prioridad y sector y permite búsqueda de texto. | Completar pruebas por rol; no se calcula PPC hasta definir una medida semanal basada en compromisos reales. |
| Auditoría y Kardex | Lectura e inserciones desde operaciones autorizadas | Confirmar restricciones e inmutabilidad en Supabase desplegado. |
| Asistencia del trabajador | Marcaje de entrada/salida implementado; la migración correctiva se aplicó manualmente y la RPC mensual fue probada con los cuatro roles y sus denegaciones. | Las obras consultadas no tienen días ni horas de jornada configurados; el porcentaje queda correctamente como `SIN_JORNADA_CONFIGURADA` hasta que Administración registre horarios reales. |
| Inactividad y bloqueo de acceso | Temporizador local de 15 minutos; `auth-lockout` desplegada y verificada con una respuesta HTTP 200; secreto HMAC configurado solo en Supabase | Probar el bloqueo por tres fallos y su expiración, además del timeout/límites nativos de Auth. El bloqueo propio solo protege estos formularios, no sustituye Auth ni bloquea clientes externos. |
| Historial y exportación | Consulta por rol con rango de hasta 31 días; XLSX e impresión/guardar como PDF, máximo 1.000 filas por consulta | Validar permisos de la RPC y exportaciones con datos reales autorizados. |
| Vigencia y plazos | Configuración de fecha/jornada común por obra; fechas límite de tareas y préstamos con validación SQL | Configurar jornadas reales y probar límites temporales en la aplicación; no repetir ahora las pruebas manuales de migraciones. |
| Notificaciones de pedidos y stock | No están implementadas como envío a usuarios | Definir canal, destinatarios y cuándo avisar. |
| Reportes diarios | Consulta e historial previstos | Programar y probar `pg_cron`, zona horaria y entrega automática. |

## 6. Seguridad y datos

- Supabase Auth administra las identidades; no se guardan contraseñas propias en
  las tablas de la aplicación.
- El navegador usa únicamente la clave publicable. La clave `service_role` no
  debe incluirse en HTML, JavaScript público ni commits.
- Las migraciones activan políticas RLS y definen operaciones para acciones
  que requieren validación transaccional.
- El Kardex y la auditoría se diseñaron para consulta restringida e inserción
  desde operaciones autorizadas.
- La configuración real de la app se guarda localmente en
  `Proyecto/supabase-config.js`, excluido del repositorio. La plantilla que sí
  se entrega es `Proyecto/supabase-config.example.js`.
- El bootstrap del primer administrador tiene marcadores. Se deben reemplazar
  con datos válidos de forma local; no subir al repositorio una copia con datos
  reales.

## 7. Instalación y uso

La configuración de Supabase, el inicio local y el recorrido por cada rol se
explican en el [Manual de uso y configuración](./MANUAL_DE_USO.md). La
instalación SQL se realiza aplicando en orden las migraciones de
`supabase/migrations/`, no ejecutando además el esquema de consulta.

## 8. Pruebas y limitaciones

En la revisión del 23-11-2026:

- `supabase/verify_setup.sql` devolvió `OK` para las tablas, funciones, roles,
  permisos, columnas, triggers y políticas RLS que comprueba.
- Las cuatro cuentas demo pudieron autenticarse y sus perfiles remotos
  coincidieron con los roles de Administración, Jefatura, Bodega y Operario.
- La primera ejecución de la consulta mensual había fallado con `42804` por
  diferencias entre `varchar(150)` y `TEXT`. El usuario aplicó manualmente
  `20261123020000_fix_asistencia_mensual_result_types.sql`; luego
  `verify_setup.sql` confirmó todas las comprobaciones en `OK`, incluidos los
  casts.
- La RPC corregida devolvió 7 filas a Administración en 2 obras, 6 filas a
  Jefatura para su obra y una fila propia a cada uno de Bodega y Operario.
  También se confirmaron denegaciones al omitir la obra, consultar una obra
  ajena y usar una fecha que no fuera el primer día del mes. No se escribieron
  registros operativos durante las pruebas.
- Las tres obras activas consultadas carecen de días y hora de término
  configurados. Las 7 filas vistas por Administración en octubre/noviembre de
  2026 indicaron `SIN_JORNADA_CONFIGURADA`; todavía no se pueden validar
  porcentajes calculables sin que Administración configure jornadas reales.
- `admin-create-user` y `auth-lockout` figuran activas en remoto. Se generó
  `AUTH_LOCKOUT_HASH_SECRET` aleatoriamente y se guardó como secreto remoto, sin
  incluirlo en archivos. Una comprobación `action: check` devolvió HTTP 200,
  `locked: false` y tres intentos disponibles. Falta validar intentos fallidos,
  bloqueo y expiración con cuentas de prueba.
- `supabase migration list --remote` mostró las once versiones locales sin
  versiones remotas; además, `supabase_migrations.schema_migrations` no existe
  en el proyecto. El usuario confirmó que las migraciones previas se aplicaron
  manualmente y los objetos están presentes. No ejecutar `db push` ni
  `migration repair` sobre ese proyecto sin reconciliar antes el historial y
  preparar un respaldo.
- Pasaron el análisis sintáctico local de las once migraciones, el cuerpo
  PL/pgSQL correctivo, `verify_setup.sql` y `node --check` de JavaScript.

También quedan pendientes las pruebas de pedidos, préstamos, Storage, bloqueo
de acceso, inactividad, historial/exportación, fechas límite y errores de red;
además de SMTP, hosting HTTPS y la programación/entrega de reportes.
La validación de objetos y el inicio de sesión no equivalen a aprobar esos
flujos de negocio.

Para ver la lista de tareas completa, consultar
[CHECKLIST_SUPABASE.md](./CHECKLIST_SUPABASE.md). No se afirma que estas pruebas
remotas se hayan completado en su totalidad.

## 9. Material entregado

El repositorio contiene el código de la aplicación, la plantilla de
configuración, las once migraciones, las funciones Edge, scripts de
aprovisionamiento/verificación, este informe y el manual. Los PDFs académicos,
las contraseñas y la configuración local no se incluyen en el repositorio del
código.
