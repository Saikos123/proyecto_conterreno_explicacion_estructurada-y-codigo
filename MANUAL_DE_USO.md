# Manual de uso y configuración

## 1. Qué hace el sistema

ConTerreno reúne herramientas de trabajo en una aplicación web conectada con
Supabase. Cada persona inicia sesión con su propia cuenta. La obra asignada y
el rol determinan qué información y acciones muestra la aplicación.

Los cuatro roles son:

| Rol | Uso principal |
|---|---|
| Administrador del sistema | Crear cuentas, revisar solicitudes, asignar roles y obras, administrar perfiles y consultar auditoría, alertas y Kardex. |
| Jefe de obra | Revisar préstamos, inventario, alertas, reportes, tareas e incidencias de la obra asignada. |
| Bodeguero | Registrar herramientas, préstamos, devoluciones y movimientos de materiales; atender pedidos completos o rechazarlos. |
| Trabajador / operario | Consultar sus préstamos, firmar la recepción de herramientas, revisar materiales, enviar pedidos y reportar incidencias. |

El Kardex es de consulta desde la interfaz. Los movimientos se producen como
parte de operaciones autorizadas; no se ofrecen acciones para editarlo o
borrarlo.

## 2. Abrir la aplicación

La aplicación debe servirse desde un servidor HTTP local o un sitio HTTPS. No
se recomienda abrir los HTML directamente como archivos.

Desde la carpeta raíz del proyecto:

```powershell
python -m http.server 8000
```

Después abre `http://localhost:8000/Proyecto/index.html`. En VS Code también se
puede usar una extensión de servidor local.

Para detener el servidor, vuelve a la terminal y presiona `Ctrl+C`.

## 3. Preparar Supabase

1. Crea o selecciona un proyecto Supabase de prueba. Verifica que sea el
   proyecto correcto antes de aplicar cambios.
2. Instala y autentica Supabase CLI:

   ```powershell
   supabase login
   supabase link --project-ref <PROJECT_ID>
   ```

3. Crea el archivo local de configuración web:

   ```powershell
   Copy-Item Proyecto\supabase-config.example.js Proyecto\supabase-config.js
   ```

4. Completa la URL y la clave publicable del proyecto en
   `Proyecto\supabase-config.js`. Ese archivo no debe enviarse al repositorio.
   No pongas una clave `service_role` en el navegador.
5. Revisa el plan antes de ejecutar las migraciones:

   ```powershell
   supabase migration list --remote
   supabase db push --dry-run
   ```

   Si la base no está vacía o el plan propone algo inesperado, detente y pide
   revisión. No uses `db reset` contra una base remota con datos.
6. Aplica las migraciones a la base de prueba y revisa el resultado:

   ```powershell
   supabase db push
   ```

7. Abre `supabase/verify_setup.sql` en el SQL Editor del proyecto. Cada fila
   debe indicar `OK`; revisa cualquier resultado `FALTA` antes de continuar.
8. Despliega la función de creación de cuentas si se usará esa opción:

   ```powershell
   supabase functions deploy admin-create-user
   supabase functions deploy auth-lockout
   ```

   Define el secreto de la función `auth-lockout` con un valor aleatorio
   criptográficamente seguro de al menos 32 caracteres:

   ```powershell
   supabase secrets set AUTH_LOCKOUT_HASH_SECRET=<valor-seguro>
   ```

9. Configura en Auth la inactividad máxima de 15 minutos, confirmación de
   correo, SMTP y URLs permitidas en Supabase. `supabase/config.toml` incluye
   este valor para el entorno local; revisa que también esté habilitado en el
   proyecto remoto y que el plan contratado lo permita.
   Para pruebas locales usa las URL de desarrollo; para una publicación se
   requiere dominio HTTPS y sus redirect URLs correspondientes.

Las migraciones de `supabase/migrations/` instalan el esquema en orden. No
ejecutes además `Base de datos posgreSQL/Base de datos.sql`: es una copia de la
migración inicial para lectura. El script
`supabase/bootstrap_first_admin.sql` tampoco es una migración.

## 4. Crear el primer Administrador

Este paso es necesario solo si el proyecto Supabase todavía no tiene un perfil
administrador.

1. Crea una cuenta Auth mediante el proceso configurado para el proyecto y
   confirma su correo.
2. En Supabase SQL Editor, consulta la tabla `conterreno_proyectos` y anota el
   identificador de una obra activa.
3. Abre `supabase/bootstrap_first_admin.sql` y reemplaza **todos** los valores
   `REEMPLAZAR_...` con el correo confirmado, RUT, nombres, apellidos, cargo e
   identificador de obra.
4. Verifica cuidadosamente los datos y ejecuta el script **una sola vez**.
   No guardes en el repositorio la copia con datos reales.
5. Inicia sesión en la web. El panel de Administración permite aprobar y
   asignar las cuentas que se registren posteriormente.

## 5. Registro e inicio de sesión

1. Abre `Proyecto/index.html`.
2. Para una cuenta nueva, selecciona **Crear cuenta**, completa nombre, correo,
   contraseña y confirmación.
3. Confirma el mensaje que llegue al correo si la configuración de Auth lo
   requiere.
4. La cuenta nueva queda pendiente. El Administrador debe revisar la solicitud
   y asignar rol y obra antes de que la persona pueda entrar a las funciones de
   la aplicación.
5. Para entrar, usa el correo y la contraseña de esa cuenta.

La aplicación busca la asignación guardada en Supabase para decidir el rol. Las
páginas `administrador.html`, `jefe-obra.html`, `bodeguero.html` y `operario.html`
son accesos directos al panel; no reemplazan el inicio de sesión ni conceden
permisos por sí mismas. Tres fallos consecutivos desde la misma combinación de
cuenta y origen activan un bloqueo temporal de 15 minutos en estos formularios.
Si el control no está disponible, el formulario no continúa con el login.

El panel principal cierra la sesión del navegador al acumular 15 minutos sin
actividad. Este control de interfaz no sustituye la expiración y los límites
del servidor Auth; configura también el timeout remoto y sus límites nativos.

## 6. Recorrido de cada rol

### Administrador del sistema

- En **Solicitudes de cuenta**, revisa el correo y la confirmación; completa RUT,
  cargo, nombres, apellidos, rol y obra para aprobar.
- En **Perfiles y asignaciones**, revisa los perfiles existentes y administra
  rol, obra o estado según corresponda.
- En **Crear obra**, registra las obras que se usarán en las asignaciones.
- Al crear una obra, puedes indicar fechas de vigencia y jornada (días y
  horario); desde la lista puedes editar estos valores. Las fechas de tareas y
  préstamos se validan respecto de la vigencia configurada. La jornada es
  común a la obra y a las personas asignadas; si se necesitan turnos
  individuales, habrá que agregar ese modelo antes de usarlo para nómina.
- Consulta auditoría, alertas de stock y Kardex en modo lectura.
- Al crear una cuenta desde el panel, guarda la contraseña inicial y entrégala
  por un canal privado. La aplicación la muestra una sola vez.

### Jefe de obra

- Revisa las tarjetas de préstamos, reportes, herramientas, alertas y Kardex.
- Usa **Plan semanal** para consultar y gestionar las tareas disponibles.
- Al crear una tarea, registra opcionalmente inicio y fecha límite. El sistema
  rechaza fechas inconsistentes o fuera de la vigencia de la obra.
- Usa **Incidencias** para revisar y actualizar los reportes de terreno.
- Este rol supervisa; no registra préstamos ni modifica herramientas o stock.

### Bodeguero

- En la tarjeta del escáner, ingresa una etiqueta o usa la cámara para buscar
  una herramienta.
- **Registrar herramienta y stock** crea una unidad con cantidad 1 o varias
  unidades en lote hasta 100. Los campos de etiqueta y serie son opcionales;
  si se omiten, el sistema genera identificadores únicos.
- **Inventario de herramientas** es una cuadrícula independiente con búsqueda
  por nombre, etiqueta o serie y filtro por estado. Puede exportarse a Excel
  o imprimir/guardar como PDF; la exportación contiene solo las filas filtradas.
  Las filas muestran la fecha y hora de registro en hora local de Chile.
- El cambio de estado se guarda al seleccionar una opción en la misma fila:
  Óptimo, Dañado, En mantención o Dado de baja. Las herramientas no óptimas
  dejan de estar disponibles para nuevos préstamos.
- “En préstamo” significa que existe un préstamo abierto real. En mantención,
  dañada o dada de baja no se muestra como “En uso”.
- Registra herramientas, préstamos y devoluciones desde las tarjetas
  correspondientes.
- Cada préstamo requiere fecha prevista de devolución; el panel señala
  vencimientos atrasados.
- Si una devolución tiene daños, adjunta la evidencia solicitada.
- En **Pedidos de materiales**, despacha el pedido completo si hay stock
  suficiente o lo rechaza indicando el motivo. El despacho parcial no forma
  parte del flujo actual.
- En **Materiales y stock**, consulta existencias y registra entradas, salidas
  o ajustes con motivo.

### Trabajador / operario

- Consulta sus préstamos y selecciona una entrega pendiente para firmar su
  recepción.
- Revisa las herramientas y materiales disponibles para su obra.
- Abre **Pedidos Bodega** para solicitar materiales y revisar sus pedidos.
- Usa **Incidencias** para reportar un problema de terreno.
- No puede gestionar solicitudes de otras personas ni modificar stock.

### Porcentaje de asistencia

- En **Asistencia mensual**, la persona ve su porcentaje en Bodega y Operario;
  Jefatura consulta a las personas asignadas a su obra y Administración puede
  consultar todas las obras o filtrar una.
- El cálculo es: jornadas programadas transcurridas con entrada marcada
  divididas por las jornadas programadas transcurridas del mes. Se cuenta el
  día con entrada aunque todavía falte la salida; las salidas pendientes se
  muestran aparte.
- El día actual se incorpora cuando se marca entrada o al llegar la hora de
  término configurada. Sin jornada de obra o sin jornadas programadas
  transcurridas se indica **No calculable**, no 0%.
- “Sin marcaje” no determina por sí solo una ausencia injustificada. El
  porcentaje es informativo y no reemplaza la revisión laboral de la persona
  responsable.

### Historial para todos los roles

- En **Historial de actividad**, filtra hasta 31 días y exporta los resultados
  permitidos para tu rol a Excel (.xlsx) o mediante impresión/guardar como PDF.
- Administración consulta globalmente; Jefatura ve la obra asignada; Bodega
  ve movimientos de bodega; Trabajador ve su propia actividad.
- Un día programado sin registro se muestra como **Sin marcaje** y no se
  interpreta como ausencia injustificada. Para el día actual, solo aparece
  después de terminar el horario programado.

## 7. Entender estados y errores

- **Pendiente de aprobación:** el Administrador todavía debe asignar rol y
  obra; confirmar el correo por sí solo no habilita el acceso operativo.
- **Sin datos o lista vacía:** no hay registros visibles para esa obra/cuenta o
  la consulta no devolvió resultados.
- **Error de permiso o conexión:** la operación no debe considerarse guardada.
  Lee el mensaje, confirma tu conexión y pide al Administrador revisar permisos
  si el problema continúa.
- **Botones bloqueados al guardar:** espera el resultado; la interfaz bloquea
  temporalmente los controles para reducir envíos repetidos.
- **Kardex:** es un historial de consulta; las operaciones autorizadas generan
  movimientos automáticamente.

## 8. Qué está implementado y qué falta

Las pantallas y flujos descritos existen en el código. Aun así, el despliegue
de migraciones, Auth, correo y función Edge debe hacerse en el proyecto elegido.
Antes de usar cuentas reales hay que probar permisos permitidos y denegados
para los cuatro roles y más de una obra.

El [informe de implementación](./INFORME_IMPLEMENTACION_Y_REVISION_SUPABASE.md)
resume lo disponible, lo parcial y lo que no está implementado. El
[checklist de Supabase](./CHECKLIST_SUPABASE.md) contiene el procedimiento
detallado de verificación y los pendientes.
