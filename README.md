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
6. Despliega la función administrativa si se probará la creación de cuentas:

   ```powershell
   supabase functions deploy admin-create-user
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
  role-screens.js                    Paneles y operaciones por rol
  administrador.html                Entrada que redirige al panel Admin
  jefe-obra.html                     Entrada que redirige al panel Jefatura
  bodeguero.html                     Entrada que redirige al panel Bodega
  operario.html                      Entrada que redirige al panel Trabajador
  supabase-config.example.js         Plantilla pública de configuración
supabase/
  migrations/                        Esquema y cambios versionados
  functions/admin-create-user/       Función de creación de cuentas
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

## Guías

- [Manual de uso y configuración](./MANUAL_DE_USO.md): instrucciones para
  preparar el entorno y recorrer la aplicación por rol.
- [Informe del proyecto](./INFORME_IMPLEMENTACION_Y_REVISION_SUPABASE.md):
  estructura, roles, estado y límites de las pruebas.
- [Checklist de Supabase](./CHECKLIST_SUPABASE.md): instalación, seguridad,
  pruebas de aceptación y tareas antes de publicar.
