# Checklist de preparación para Supabase

## Alcance y criterio de estado

Este checklist describe el esquema y el cliente de ConTerreno. **Implementado
en archivos** no significa desplegado o probado en el proyecto Supabase remoto.
La base fue eliminada para recrearla; por eso el historial versionado
`supabase/migrations/` es ahora la única fuente de verdad para instalar el
esquema completo.

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
   - [ ] Confirmar que el proyecto remoto correcto está enlazado y vacío.
   - [ ] Aplicar en orden las seis migraciones; no usar `migration repair` ni
     reset remoto.
   - [ ] Ejecutar `supabase/verify_setup.sql` y resolver cualquier fila que no
     indique `OK`.
   - [ ] Crear el primer Administrador y ejecutar el bootstrap una sola vez.
   - [ ] Desplegar la Edge Function `admin-create-user` y probar la creación
     desde el panel.

2. **Probar permisos y operaciones con cuentas reales**
   - [ ] Crear cuentas de prueba para Administrador, Jefatura, Bodega y
     Trabajador y asignarlas a obras.
   - [ ] Probar los permisos permitidos y denegados por rol en RLS, RPC y
     Storage, incluida la separación de datos entre obras.
   - [ ] Probar el ciclo de pedido completo: solicitud, despacho, stock
     insuficiente, rechazo, reintento y doble procesamiento.
   - [ ] Confirmar firma propia, devolución/evidencia de daño y que nadie pueda
     modificar o borrar el Kardex directamente.
   - [ ] Validar errores de red/permisos: la interfaz debe informar el fallo y
     nunca mostrar como guardada una operación rechazada.

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

4. **Trabajador**
   - [ ] Implementar asistencia propia (entrada/salida, jornada, duplicados,
     desconexión y corrección autorizada).
   - [ ] Completar la sección “Mis solicitudes” con el historial propio,
     cantidades, estado y motivo de rechazo.
   - [ ] Probar que solo vea y firme sus préstamos, y que no pueda operar stock,
     herramientas, tareas ni solicitudes ajenas.

5. **Jefe de obra**
   - [ ] Completar el resumen con tareas por estado/PPC e incidencias abiertas
     o críticas, usando datos reales de su obra.
   - [ ] Retirar o etiquetar como demostración la curva S, costos y avance que
     no tengan una fuente de datos confiable.
   - [ ] Configurar `pg_cron`, zona horaria `America/Santiago`, snapshot diario
     y destinatarios; o indicar claramente que el reporte no es automático.

6. **Administrador**
   - [ ] Completar filtros/búsqueda para cuentas, solicitudes, obras y
     auditoría.
   - [ ] Incorporar métricas pendientes de préstamos y pedidos; ofrecer enlaces
     directos a las listas.
   - [ ] Definir qué operaciones globales de Bodega necesita usar Admin y
     exponerlas solo mediante las RPC existentes y autorizadas.

7. **Bodega y notificaciones**
   - [ ] Confirmar en Supabase alertas y pedidos por obra, con migración
     desplegada y acceso autorizado.
   - [ ] Definir destinatarios/canal para alertas de stock bajo; hoy la
     aplicación las registra y consulta, pero no las envía.
   - [ ] Probar escáner/cámara, préstamos concurrentes, devoluciones repetidas
     y evidencia obligatoria si hay daño.

### Mejoras transversales

- [x] Bloquear temporalmente controles del espacio de trabajo mientras una
  operación está en curso y anunciar el estado/error.
- [x] Evitar dobles envíos desde la interfaz, y restaurar la tarjeta abierta y
  la posición de desplazamiento tras una operación exitosa.
- [ ] Probar dobles clics, fallos de red y reintentos con cada rol contra
  Supabase; la interfaz no sustituye la idempotencia y autorización del servidor.
- [x] Excluir configuración local, contraseñas y PDFs del repositorio; ofrecer
  un ejemplo de configuración sin claves.
- [x] Quitar la referencia a un `seed.sql` ausente; roles y permisos iniciales
  se siembran desde la migración base.
- [x] Sustituir los datos personales del bootstrap por marcadores que deben
  reemplazarse localmente antes de ejecutarlo.

### Cierre de diseño, publicación y operación

8. **Diseño responsive y accesible**
   - [ ] Revisar cada rol en móvil/tablet/escritorio, navegación por teclado,
     contraste, lectores de pantalla y tamaño de botones.
   - [ ] Revisar tablas extensas y formularios desplegables en móvil, errores,
     vacíos y estados de carga.
   - [ ] Eliminar las vistas, gráficos, KPIs y actividad de demostración que
     permanezcan en el HTML y puedan confundirse con datos reales.

9. **Operación continua**
   - [ ] Definir respaldos y restauración probada, rotación de credenciales y
     procedimiento de despliegue/rollback.
   - [ ] Confirmar dominio, HTTPS, SMTP, redirects y pruebas de aceptación antes
     de invitar a todo el personal.

## Instalación limpia de Supabase

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
aplicadas. El `dry-run` debe listar las seis versiones locales, en este orden:

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

Si `migration list` ya muestra versiones remotas o `dry-run` no lista las seis,
**detente**: no uses `migration repair` ni un reset remoto. Verifica que enlazaste
el proyecto correcto y que está realmente vacío. `db reset` debe reservarse para
el entorno local (requiere Docker); no lo uses para limpiar datos remotos.

`login` usa un personal access token del propietario/desarrollador y `link`
puede pedir la contraseña de la base de datos. No uses la contraseña del
administrador de la aplicación y no guardes tokens ni contraseñas en archivos
del proyecto.

Después de `db push`, ejecuta [`supabase/verify_setup.sql`](./supabase/verify_setup.sql)
en SQL Editor de Supabase. Todas las filas deben indicar `OK`.
Si aparece `relation "auditoria_usuarios" does not exist`, no repitas el alta:
confirma primero que la migración `20261110160900` esté aplicada y vuelve a
ejecutar la consulta de verificación para revisar la tabla y su trigger.

### Crear el primer administrador

Las migraciones no pueden crear la identidad de Auth ni una contraseña inicial.
Después de aplicar las seis migraciones:

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
| 🟡 Parcial | La web inicia/cierra sesión, consulta asignaciones y ejecuta las operaciones integradas con Supabase. | Reconstruir el remoto desde las seis migraciones y volver a probarlo. |
| 🟡 Parcial | La configuración del navegador contiene el Project URL y publishable key del proyecto Supabase. | Confirmar que el `PROJECT_ID` enlazado por CLI corresponde al mismo proyecto; jamás usar claves secret/service_role en el navegador. |
| ✅ Listo en archivos | Las seis migraciones versionadas contienen el esquema base, solicitudes de acceso, permisos globales de Admin, reparación de auditoría y despacho transaccional de pedidos de materiales. | Aplicar en orden con Supabase CLI; no ejecutar el SQL base por separado ni usar `migration repair`. |
| ✅ Listo en archivos | Se añadió un bootstrap manual para crear el primer perfil `ADMIN_GENERAL` después de crear su identidad en Auth. | [`supabase/bootstrap_first_admin.sql`](./supabase/bootstrap_first_admin.sql); reemplazar datos y ejecutar una sola vez. |
| ✅ Listo en archivos | Se añadió una consulta de verificación para tablas, funciones y RLS requeridos. | [`supabase/verify_setup.sql`](./supabase/verify_setup.sql); ejecutar después de `db push` y revisar que cada estado sea `OK`. |
| 🟡 Parcial | El panel crea cuentas Auth sin invitación, con contraseña inicial aleatoria de un solo vistazo. | Desplegar `admin-create-user`; esa ruta no debe enviar correo. El registro público es un flujo separado y sí puede consumir límites de email. |
| 🟡 Parcial | El alta evita duplicar una cuenta Auth que ya existe si una respuesta anterior se perdió. | Desplegar la función y probarla contra la base reconstruida. Si el error aparece en el registro público, configurar SMTP propio; si aparece desde Administración, confirmar que la Edge Function desplegada no sea una versión antigua y revisar Auth Logs. |
| 🟡 Parcial | Las seis migraciones, el bootstrap y la verificación pasan análisis sintáctico; la Edge Function pasa `deno check`. | No hay Docker disponible para reset local; falta aplicar y validar end-to-end en Supabase. |
| ⬜ Pendiente | Enlazar CLI al proyecto vacío, aplicar las seis migraciones y confirmar el historial remoto. | Seguir “Instalación limpia de Supabase”. Si el historial no está vacío, detenerse y verificar proyecto. |
| ⬜ Pendiente | Publicar la web en un host HTTPS para que otras computadoras puedan usarla. | Live Server solo sirve para desarrollo local; configurar después las Redirect URLs de Auth para el dominio publicado. |
| ⬜ Pendiente | Ejecutar pruebas de aceptación y de denegación para cada rol, RLS, RPC y Storage en Supabase. | Ver matriz de cierre más abajo. |
| 🟡 Parcial | Existe una función SQL para generar snapshots diarios de préstamos pendientes y una pantalla de historial para Jefatura. | Falta habilitar pg_cron, programarlo a las 18:00 hora Chile y definir el canal de notificación/entrega. |
| 🟡 Parcial | La solicitud de materiales se valida en una RPC y Bodega puede despachar el pedido completo o rechazarlo; el despacho descuenta stock y registra movimientos/Kardex en una transacción. | El flujo está en `20261110162800_pedidos_materiales_despacho_atomico.sql`; falta aplicar esa migración y validar concurrencia, rechazos, falta de stock y permisos en Supabase remoto. |

## Roles y límites de responsabilidad

Los nombres y descripciones deben mantenerse consistentes en SQL y web. Los
permisos siguientes se aplican por obra asignada; tener un botón visible en la
interfaz nunca concede acceso por sí solo.

| Rol | Puede hacer | No puede hacer |
|---|---|---|
| **Administrador del sistema** (`ADMIN_GENERAL`) | Control global de la aplicación y las obras; crear cuentas Auth, asignar perfiles/roles/obras, operar módulos y consultar auditoría/Kardex. | El Kardex sigue siendo append-only: Administración puede consultarlo y generar movimientos mediante operaciones autorizadas, pero no alterar ni borrar registros manualmente. |
| **Jefe de obra** (`JEFE_OBRA`) | Consultar inventario, préstamos pendientes y alertas de stock de sus obras; gestionar incidencias y planificar/eliminar tareas. | Administrar cuentas/roles; registrar préstamos/devoluciones; cambiar herramientas o existencias. |
| **Bodeguero** (`BODEGUERO`) | Consultar y mantener herramientas y stock; registrar préstamos/devoluciones; despachar o rechazar pedidos de materiales completos. | Administrar usuarios/roles; planificar tareas o gestionar incidencias; firmar la recepción en nombre del trabajador; realizar despachos parciales. |
| **Trabajador / operario** (`OPERARIO_MAESTRO`) | Consultar inventario disponible y sus propios préstamos; firmar la recepción propia; registrar asistencia propia, reportar incidencias y solicitar materiales. | Crear/modificar herramientas, registrar préstamos o devoluciones, gestionar pedidos, tareas, roles o incidencias de otras personas. |

### Inventario funcional actual por rol

Este inventario describe lo que existe en los archivos de la web y migraciones,
no certifica que esté desplegado ni probado contra el proyecto remoto. `✅`
significa que hay pantalla y operación conectada en el código; `🟡` indica que
hay una parte implementada o falta validar/desplegar; `⬜` indica que falta la
función de interfaz o el flujo completo.

| Rol | Disponible ahora | Parcial o pendiente |
|---|---|---|
| **Administrador del sistema** | ✅ Crear cuentas, asignar roles/obras, crear/desactivar obras y perfiles, consultar auditoría, alertas y Kardex. ✅ Centro de control con recuentos en vivo de solicitudes pendientes, perfiles activos, obras activas y alertas. | 🟡 Faltan recuentos de préstamos/pedidos y las operaciones globales de Bodega dentro del panel Admin. Los gráficos/demo del dashboard heredado siguen en el HTML, pero no son una pestaña de usuarios autenticados. ⬜ Falta probar con la cuenta Admin real. |
| **Jefe de obra** | ✅ Consultar préstamos abiertos, reportes diarios existentes, herramientas, alertas y Kardex; gestionar tareas e incidencias. ✅ Resumen de obra con recuentos en vivo y accesos directos a planificación, incidencias y préstamos. | 🟡 Reportes requieren pg_cron para generarse automáticamente. El dashboard general heredado conserva datos demo, pero no se muestra en el menú autenticado. ⬜ Falta validar denegación de operaciones de Bodega y Administración. |
| **Bodeguero** | ✅ Buscar/crear herramientas, registrar préstamos/devoluciones, mantener stock, atender pedidos completos y leer Kardex. ✅ Puesto operativo con accesos directos y métricas en vivo de pedidos, préstamos, alertas y materiales con stock. | 🟡 El ciclo de pedidos requiere aplicar la migración `20261110162800` y probarse en Supabase. La primera versión no admite despacho parcial; pedido completo o rechazo. |
| **Trabajador / operario** | ✅ Consultar sus préstamos, firmar recepción, revisar herramientas/stock y reportar incidencias. ✅ Inicio personal con recuentos de préstamos propios, firmas pendientes, pedidos pendientes sujetos a RLS y materiales con stock; acceso directo a solicitar material. | 🟡 Catálogo y solicitud validada por RPC requieren aplicar la migración `20261110162800`. ⬜ Hay permiso SQL de asistencia, pero falta pantalla y operación. El dashboard heredado aún contiene datos demo fuera de su navegación. |
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
- [ ] 🟡 El dashboard y la actividad heredados aún tienen indicadores/datos de
  demostración; no se muestran en la navegación autenticada.
- [x] Crear un centro de control inicial con solicitudes pendientes, perfiles
  activos, obras activas y alertas, con accesos a sus listas.
- [ ] Completar los indicadores Admin con préstamos/pedidos pendientes y
  enlaces más granulares a cada lista.
- [ ] Agregar búsqueda y filtros de personas, solicitudes, obras y auditoría;
  mantener visibles los estados de cuenta y asignación.
- [ ] Dar acceso desde Administración a las operaciones globales de terreno y
  Bodega que el rol está autorizado a ejecutar, mediante las RPC existentes y
  sin crear escrituras directas a tablas protegidas.
- [ ] Separar visualmente las acciones de alto impacto (crear Admin, cambiar
  roles, desactivar usuarios/obras) y pedir confirmación/motivo donde aplique.
- [ ] Probar con cuenta Admin que el acceso global respeta las mismas reglas
  transaccionales que para el rol operativo y nunca permite editar/borrar
  auditoría o Kardex.
- [ ] Validar creación de cuentas, sesión, bloqueo/desactivación, auditoría y
  permisos después de desplegar la Edge Function y las migraciones.

#### Jefe de obra — supervisión y planificación

- [x] Consultar herramientas, préstamos pendientes, reportes existentes,
  alertas y Kardex de sus obras.
- [x] Iniciar en un resumen propio con métricas de préstamos, alertas, reportes
  y Kardex, además de accesos a Plan semanal e Incidencias.
- [x] Crear, mover y eliminar tareas; revisar y actualizar incidencias.
- [x] Mostrar accesos a Plan semanal e Incidencias y ocultar la operación de
  Bodega.
- [ ] 🟡 El PPC y el conteo de incidencias se calculan con datos cargados, pero
  avance/costo, curva S y parte de la actividad siguen siendo demostrativos.
- [ ] Crear un dashboard centrado en obra con tareas por estado/PPC,
  incidencias abiertas/críticas, préstamos vencidos/pendientes y alertas de
  stock; usar solo datos de obras asignadas.
- [ ] Completar seguimiento de incidencias (responsable, prioridad, estado,
  fecha y evidencia) y filtros de abiertas, críticas y por sector.
- [ ] Completar planificación semanal con responsable, sector, restricción y
  fechas/periodo, más un historial de cambios cuando corresponda.
- [ ] Mostrar tendencias de avance únicamente cuando exista una fuente real de
  avance planificado/real; retirar o etiquetar como demostración la curva S y
  el desvío de costo mientras no haya datos confiables.
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
- [ ] Aplicar la migración y validar rechazo, falta de stock, doble clic,
  pedidos legacy, permisos por obra y concurrencia en Supabase.
- [ ] Añadir dashboard operativo: pedidos por preparar, entregas del día,
  préstamos por devolver y stock bajo; accesos directos a escanear, entregar y
  registrar devolución.
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
- [ ] Aplicar la migración y confirmar que RLS limita la lectura a los pedidos
  del propio usuario, mientras Bodega solo gestiona su obra asignada.
- [ ] Crear un inicio móvil que priorice la acción necesaria ahora: marcar
  asistencia (cuando esté implementada), firmar una entrega pendiente,
  consultar herramienta propia o solicitar material.
- [ ] Agregar marcación de entrada/salida propia con reglas explícitas de
  jornada, duplicados, desconexión y corrección autorizada; el permiso SQL
  existente no sustituye la pantalla ni las reglas operativas.
- [ ] Mostrar historial propio de solicitudes, estado, cantidades entregadas o
  motivo de rechazo, sin exponer pedidos de otros trabajadores.
- [ ] Conectar el formulario de solicitud al catálogo real; elegir cantidades,
  unidad, destino y prioridad según las reglas aprobadas, y confirmar el envío.
- [ ] Mostrar sus incidencias reportadas y su estado sin permitir gestionar o
  cerrar incidencias ajenas.
- [ ] Reducir el dashboard a información personal y de su obra autorizada;
  quitar KPIs corporativos, costo/presupuesto y contenido ficticio.
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
- [x] Hacer que los accesos rápidos abran la sección objetivo y compactar
  cabecera, navegación y tarjetas KPI para escritorio y móvil.

#### Cierre compartido

- [ ] Retirar la actividad/KPI/curva de demostración del dashboard heredado;
  ya no está en la navegación autenticada. Los nuevos indicadores muestran
  errores de carga y hora de actualización, pero requieren validación remota.
- [ ] Revisar diseño adaptable, teclado, lectores de pantalla, contraste,
  tamaños de toque y mensajes de error/confirmación en cada flujo.
- [ ] Ejecutar pruebas de aceptación y denegación con una cuenta real de cada
  rol, en más de una obra; comprobar tanto la interfaz como RLS/RPC/Storage.
- [ ] Probar funcionamiento en la URL publicada con HTTPS y las redirect URLs
  de Auth definitivas.

#### Orden recomendado

1. Cerrar y probar el ciclo de pedidos Trabajador → Bodega → stock/Kardex.
2. Completar y validar en Supabase los dashboards por rol ya implementados;
   retirar la vista heredada con datos de demostración.
3. Decidir y construir asistencia propia del Trabajador.
4. Dar al Admin las herramientas operativas globales faltantes sin romper la
   segregación ni la inmutabilidad del Kardex.
5. Aplicar los layouts diferenciados, retirar contenido ficticio y ejecutar
   pruebas de aceptación/denegación en Supabase.

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
- [ ] Aplicar las seis migraciones en el nuevo proyecto y resolver cualquier
  incompatibilidad de ejecución antes de invitar/crear usuarios.
- [ ] Ejecutar `supabase/verify_setup.sql`; todas las filas deben indicar `OK`.
- [ ] Verificar en la base desplegada funciones, triggers, RLS, grants,
  secuencias, políticas de Storage e índices.
- [x] Implementar en archivos solicitudes validadas y despacho completo o
  rechazo de pedidos con actualización transaccional de stock, movimiento y
  Kardex; no se permiten despachos parciales en esta primera versión.
- [ ] Aplicar la nueva migración y probar el ciclo en Supabase, incluido stock
  insuficiente, rechazo, reintento y concurrencia.
- [ ] Habilitar pg_cron, configurar su zona horaria como
  `America/Santiago`, programar el snapshot diario a las 18:00 y definir cómo
  notificar/entregar el reporte a Jefatura.
- [x] Aplicar cambios futuros mediante migraciones nuevas y el historial de
  Supabase CLI; no volver a pegar manualmente scripts aplicados en SQL Editor.
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
- [ ] Desplegar `admin-create-user` y probar que una cuenta creada aparece
  pendiente, conserva la contraseña inicial y solo entra tras recibir rol/obra.
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
- [ ] Completar asistencia propia del Trabajador, pendiente de definir reglas.

## Pruebas de aceptación obligatorias antes de darlo por listo

- [ ] **Administrador:** puede gestionar obras, cuentas, perfiles y roles;
  probar operaciones de terreno y bodega con alcance global. Puede consultar
  auditoría/Kardex, pero no alterar ni borrar eventos del Kardex.
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

1. Aplicar la nueva migración de pedidos junto con el resto en el proyecto
   Supabase de prueba y ejecutar `verify_setup.sql`.
2. Probar solicitud de Trabajador, despacho completo, rechazo, stock
   insuficiente, doble despacho y aislamiento por obra.
3. Crear el primer Admin con el
   bootstrap y desplegar la Edge Function.
4. Completar la matriz de pruebas por rol y corregir cualquier denegación o
   acceso inesperado antes de cargar datos reales.
5. Completar dashboards reales, asistencia del Trabajador y layouts específicos
   por rol; configurar notificaciones/reportes si se mantienen en el alcance.
6. Repetir las pruebas de aceptación en el proyecto final y preparar respaldo y
   operación.
