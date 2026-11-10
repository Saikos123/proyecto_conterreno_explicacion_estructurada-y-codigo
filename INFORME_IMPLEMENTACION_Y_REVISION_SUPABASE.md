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
| `Proyecto/role-screens.js` | Paneles y operaciones específicas de cada rol. |
| `Proyecto/administrador.html`, `jefe-obra.html`, `bodeguero.html`, `operario.html` | Accesos directos al panel principal con el rol correspondiente; no son controles de autorización. |
| `Proyecto/supabase-config.example.js` | Ejemplo de configuración pública para conectar el navegador. |
| `supabase/migrations/` | Cambios SQL ordenados para crear el esquema y sus funciones. |
| `supabase/functions/admin-create-user/` | Función Edge para creación administrativa de cuentas. |
| `supabase/bootstrap_first_admin.sql` | Asignación inicial del primer perfil administrador; se ejecuta manualmente una vez. |
| `supabase/verify_setup.sql` | Consulta para revisar objetos necesarios después de las migraciones. |
| `Base de datos posgreSQL/Base de datos.sql` | Copia para consulta del esquema de la migración inicial; no se instala por separado. |

Las migraciones son la fuente de verdad para instalar el esquema. Los archivos
SQL antiguos sueltos en la carpeta de trabajo no forman parte del procedimiento
de instalación documentado.

## 4. Roles y permisos

| Rol | Acciones disponibles en la aplicación | Límites principales |
|---|---|---|
| Administrador del sistema | Crear cuentas, revisar solicitudes, asignar roles y obras, administrar perfiles y consultar auditoría, alertas y Kardex. | El Kardex se consulta; no se ofrece su modificación o borrado. Las escrituras operativas deben pasar por operaciones autorizadas. |
| Jefe de obra | Consultar información de la obra, gestionar tareas e incidencias, revisar préstamos, inventario, alertas, reportes y Kardex. | No administra cuentas ni procesa préstamos, devoluciones o movimientos de stock. |
| Bodeguero | Gestionar herramientas, préstamos, devoluciones y stock; procesar pedidos completos o rechazarlos. | No gestiona cuentas, roles, planificación ni incidencias; no firma por el trabajador ni despacha parcialmente. |
| Trabajador / operario | Consultar sus préstamos y materiales, firmar su recepción, solicitar materiales y reportar incidencias. | No administra inventario, préstamos, pedidos de otras personas, roles ni tareas. |

La interfaz oculta secciones según el rol para facilitar el uso. La
autorización efectiva debe aplicarse también en PostgreSQL mediante RLS y
funciones RPC; ocultar un botón no protege los datos.

## 5. Estado de implementación

| Funcionalidad | Estado en el código | Pendiente |
|---|---|---|
| Registro e inicio de sesión con Supabase Auth | Implementado | Confirmar SMTP, URLs de redirección y flujo en el dominio final. |
| Asignación de rol y obra | Implementado mediante flujo administrativo y funciones SQL | Probar aceptación y denegación con cuentas reales. |
| Paneles diferenciados por rol | Implementados para los cuatro roles | Revisión final de experiencia con usuarios y datos reales. |
| Herramientas, préstamos, firma y devolución | Formularios y operaciones integrados | Probar concurrencia, evidencia de daño y permisos en el remoto. |
| Pedidos y stock de materiales | Solicitud de trabajador y despacho/rechazo transaccional incluidos en migraciones | Aplicar migraciones y validar rechazo, falta de stock y doble procesamiento. |
| Incidencias y planificación | Vistas y operaciones presentes | Completar pruebas por rol y separar cualquier dato de demostración restante. |
| Auditoría y Kardex | Lectura e inserciones desde operaciones autorizadas | Confirmar restricciones e inmutabilidad en Supabase desplegado. |
| Asistencia del trabajador | La base contempla parte del modelo/permisos | No está completa la pantalla ni el flujo de jornada. |
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

Se revisó la sintaxis de JavaScript y se verificó en navegador la presentación
de los paneles y la respuesta común de las operaciones (bloqueo durante el
guardado, conservación de la sección y comunicación de errores). Estas pruebas
no equivalen a una prueba de integración con usuarios de Supabase.

Queda pendiente:

1. Aplicar las migraciones en una instancia Supabase de prueba y ejecutar
   `supabase/verify_setup.sql`.
2. Recorrer las funciones con cuentas de los cuatro roles y al menos dos obras.
3. Probar intentos no autorizados, fallos de red, concurrencia de pedidos,
   préstamos y devoluciones.
4. Configurar el envío de correo, las URLs de Auth y el hosting HTTPS.
5. Completar asistencia, notificaciones y programación de reportes si se
   mantienen dentro del alcance final.

Para ver la lista de tareas completa, consultar
[CHECKLIST_SUPABASE.md](./CHECKLIST_SUPABASE.md). No se afirma que estas pruebas
remotas se hayan completado.

## 9. Material entregado

El repositorio contiene el código de la aplicación, la plantilla de
configuración, las seis migraciones, la función Edge, scripts de
aprovisionamiento/verificación, este informe y el manual. Los PDFs académicos,
las contraseñas y la configuración local no se incluyen en el repositorio del
código.
