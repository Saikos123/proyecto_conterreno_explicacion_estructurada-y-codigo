# ConTerreno

Aplicación web para apoyar la operación de una obra: acceso por cuenta, vistas
según rol, control de herramientas, préstamos, inventario de materiales,
solicitudes, incidencias y planificación.

El proyecto está en desarrollo. Las funciones que aparecen en la interfaz no
se consideran listas para producción hasta probarlas con las políticas y los
datos del proyecto Supabase que se utilizará en la entrega.

## Para empezar

1. Instala [Supabase CLI](https://supabase.com/docs/guides/cli) y configura un
   proyecto de prueba.
2. Desde la raíz del repositorio, copia la plantilla de configuración:

   ```powershell
   Copy-Item Proyecto\supabase-config.example.js Proyecto\supabase-config.js
   ```

3. Edita `Proyecto\supabase-config.js` y completa la URL del proyecto Supabase
   y su clave publicable. **No uses ni publiques la clave `service_role`.**
4. Aplica las migraciones a una base nueva de prueba:

   ```powershell
   supabase login
   supabase link --project-ref <PROJECT_ID>
   supabase db push --dry-run
   supabase db push
   ```

5. Ejecuta `supabase/verify_setup.sql` en el SQL Editor de Supabase y confirma
   que todas las filas muestren `OK`.
6. Despliega las funciones Edge requeridas:

   ```powershell
   supabase functions deploy admin-create-user
   supabase functions deploy auth-lockout
   ```

   Configura `AUTH_LOCKOUT_HASH_SECRET` como secreto de función con un valor
   aleatorio criptográficamente seguro de al menos 32 caracteres. No lo guardes
   en HTML, `supabase-config.js` ni en el repositorio:

   ```powershell
   supabase secrets set AUTH_LOCKOUT_HASH_SECRET=<valor-seguro>
   ```

7. Sirve la carpeta mediante Live Server o ejecuta desde la raíz:

   ```powershell
   python -m http.server 8000
   ```

   Abre `http://localhost:8000/Proyecto/index.html`.

No ejecutes las migraciones sobre una base que tenga información importante sin
revisar antes el plan y hacer un respaldo. El bootstrap del primer administrador
es una operación separada y se ejecuta una sola vez; sigue el [manual de uso y
configuración](./MANUAL_DE_USO.md).

## Estructura del repositorio

```text
Proyecto/
  index.html                         Acceso, registro e inicio de sesión
  buildtech_field_os_conterreno.html Aplicación principal
  auth-login.js                      Inicio de sesión y control de intentos
  role-screens.js                    Paneles y operaciones por rol
  administrador.html                Entrada que redirige al panel Admin
  jefe-obra.html                     Entrada que redirige al panel Jefatura
  bodeguero.html                     Entrada que redirige al panel Bodega
  operario.html                      Entrada que redirige al panel Trabajador
  supabase-config.example.js         Plantilla pública de configuración
supabase/
  migrations/                        Esquema y cambios versionados
  functions/admin-create-user/       Función de creación de cuentas
  functions/auth-lockout/            Contador temporal de intentos de acceso
  bootstrap_first_admin.sql          Aprovisionamiento manual inicial
  verify_setup.sql                   Comprobación posterior a migraciones
  config.toml                        Configuración de Supabase CLI
Base de datos posgreSQL/
  Base de datos.sql                  Copia de consulta del esquema base
```

`supabase/migrations/` es la única ruta de instalación del esquema. El archivo
`Base de datos posgreSQL/Base de datos.sql` duplica la migración inicial para
consulta y no debe ejecutarse además de ella. Los borradores SQL antiguos y los
PDF académicos no se incluyen como parte del código ejecutable.

La aplicación cierra localmente la sesión tras 15 minutos sin actividad. La
migración y la Edge Function de intentos también deben estar instaladas para
usar el límite de tres fallos con bloqueo temporal de 15 minutos. El contador
propio se aplica en los formularios de esta web; no sustituye los límites
nativos de Supabase Auth ni impide que un cliente externo llame directamente
al endpoint público de Auth. Para seguridad efectiva se deben conservar y
configurar los límites de Auth y probar el flujo en el proyecto elegido.

La migración `20261123010000_porcentaje_asistencia_mensual.sql` agrega el
resumen de asistencia mensual con permisos por rol: Administración consulta
todas las obras, Jefatura solo la asignada y Bodega/Operario su propio
porcentaje. Se cuenta la jornada con entrada; una salida pendiente se señala
aparte. El día actual se incorpora al marcar entrada o al terminar el horario
de la obra. El porcentaje requiere una jornada configurada para la obra.
La migración `20261123020000_fix_asistencia_mensual_result_types.sql` corrige
los tipos de texto que devuelve esa consulta. Fue aplicada manualmente y la RPC
se validó con los cuatro roles; los porcentajes seguirán sin calcularse en
obras sin días y horarios reales configurados.

## Guías

- [Manual de uso y configuración](./MANUAL_DE_USO.md): instrucciones para
  preparar el entorno y recorrer la aplicación por rol.
- [Informe del proyecto](./INFORME_IMPLEMENTACION_Y_REVISION_SUPABASE.md):
  estructura, roles, estado y límites de las pruebas.
- [Checklist de Supabase](./CHECKLIST_SUPABASE.md): instalación, seguridad,
  pruebas de aceptación y tareas antes de publicar.
