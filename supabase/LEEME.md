# MotoContable en la nube: guía de configuración de Supabase

Esta guía te lleva paso a paso para configurar tu proyecto de Supabase.
**No da por hecho que ya hiciste nada.** Síguela en orden y no te saltes pasos.

- Tu proyecto de Supabase es el que ya usa la app: `https://llyovzgwdqoeunvyczcy.supabase.co`.
- Entra en <https://supabase.com/dashboard> y abre ese proyecto.
- Los nombres de los menús de Supabase cambian a veces. Si un botón no aparece con el nombre exacto de esta guía, busca el más parecido en la misma sección.

---

## Qué hace cada archivo

| Archivo | ¿Cambia algo? | Para qué sirve |
|---|---|---|
| `00_diagnostico.sql` | No, solo lee | Muestra cómo está hoy tu base de datos |
| `01_esquema.sql` | Crea tablas nuevas | `mc_registros` (tus datos) y `mc_historial` (todas las versiones anteriores) |
| `02_rls.sql` | Crea reglas de seguridad | Solo tu cuenta puede leer y escribir tus datos |
| `03_funciones.sql` | Crea funciones | Sincronización con control de versiones y tiempo real |
| `04_migracion.sql` | Copia datos | Pasa tus datos de `mc_datos` a `mc_registros`, y antes guarda un respaldo |
| `05_cerrar_tabla_antigua.sql` | Quita el acceso público a `mc_datos` | **Solo al final.** No borra datos |

Ningún archivo borra la tabla `mc_datos` ni tus datos. Los archivos 01 a 05 se pueden volver a ejecutar sin problema: no duplican ni pisan nada.

---

## FASE 0: Respaldos (antes de todo)

1. **En cada dispositivo donde usas MotoContable** (computador, iPhone, otros), abre la app actual.
   - Ve a **Personalizar paneles → Backup y restauración → Descargar backup completo**.
   - Guarda los archivos `MotoContable_backup_<fecha>.json` en un lugar seguro, por ejemplo tu correo o Google Drive.
   - Ponles un nombre que indique de qué dispositivo son (`backup_iphone.json`, `backup_pc.json`).
2. **Diagnóstico en Supabase:**
   1. En el menú izquierdo, abre **SQL Editor**.
   2. Pulsa **New query** (o el botón **+**).
   3. Abre el archivo `supabase/00_diagnostico.sql` de este repositorio, copia todo su contenido y pégalo en el editor.
   4. Pulsa **Run** (o Ctrl+Enter / Cmd+Enter).
   5. Guarda los resultados que aparecen abajo, con capturas de pantalla o copiando el texto. **Es muy importante el resultado de la consulta 4** (las políticas actuales de `mc_datos`).
   6. Si el editor solo muestra el resultado de la última consulta, ejecuta cada consulta por separado: selecciona su texto y pulsa **Run**.

---

## FASE 1: Crear tu usuario

1. En el menú izquierdo, abre **Authentication**.
2. Entra en **Users**.
3. Pulsa **Add user → Create new user**.
4. Escribe:
   - **Email:** tu correo, el que usarás para entrar a MotoContable.
   - **Password:** una contraseña segura. Guárdala en un gestor de contraseñas; la usarás en cada dispositivo.
   - Marca **Auto Confirm User**, para no tener que confirmar el correo.
5. Pulsa **Create user**.
6. Comprueba que tu usuario aparece en la lista. Si hay una columna "Confirmed" o similar, debe mostrar una fecha.

---

## FASE 2: Configurar Auth

### 2.1 Proveedor de correo y registro de cuentas

1. En **Authentication**, abre **Sign In / Providers**. En versiones anteriores del panel está en **Providers** o en **Settings**.
2. Comprueba que **Email** está **activado** (Enabled).
3. Busca **Allow new users to sign up** y **desactívalo**.
   - Así nadie más puede crearse una cuenta en tu proyecto.
   - Aunque alguien lo lograra, las reglas de seguridad (RLS) le impedirían ver tus datos. Esto es una segunda barrera.
4. **Confirm email:** puede quedar como esté. Tu usuario ya está confirmado.
5. Pulsa **Save** si aparece el botón.

### 2.2 Site URL y Redirect URLs

Sirven para el enlace de **"¿Olvidaste tu contraseña?"**: el correo de recuperación te devuelve a esta dirección.

1. Averigua la dirección exacta de tu GitHub Pages:
   - En GitHub, abre el repositorio **Motocontable**, ve a **Settings → Pages** y copia la dirección que dice *"Your site is live at …"*.
   - Normalmente es `https://samuelmonsalve256-ai.github.io/Motocontable/`. Usa **exactamente** la que te muestre GitHub, respetando mayúsculas y la barra final.
2. En Supabase: **Authentication → URL Configuration**.
3. **Site URL:** pega la dirección de tu GitHub Pages, por ejemplo `https://samuelmonsalve256-ai.github.io/Motocontable/`.
4. En **Redirect URLs**, pulsa **Add URL** y agrega, una por una:
   - `https://samuelmonsalve256-ai.github.io/Motocontable/`
   - `https://samuelmonsalve256-ai.github.io/Motocontable/index.html`
   - `https://samuelmonsalve256-ai.github.io/Motocontable/**`
   - Si vas a usar el enlace de prueba de la FASE 5: `https://raw.githack.com/**`
5. Pulsa **Save**.

### 2.3 Correo de recuperación de contraseña

- El correo de recuperación lo envía Supabase con su servidor de correo incluido.
- Ese servidor tiene un **límite muy bajo de correos por hora**, pensado solo para pruebas. Para ti, que eres el único usuario, alcanza.
- Si algún día no te llega el correo, espera una hora y vuelve a intentarlo, y revisa la carpeta de spam.
- La plantilla está en **Authentication → Emails → Reset Password**. No hace falta cambiarla.

### 2.4 Claves de la API

- La app usa la clave pública **anon**, que ya está en `index.html`. **No hay que cambiarla.** Con las reglas RLS de este proyecto, esa clave sola no da acceso a ningún dato.
- **Nunca** pongas la clave `service_role` (ni ninguna clave "secret") en la app ni en GitHub: esa clave salta todas las reglas de seguridad.

---

## FASE 3: Ejecutar los SQL (en este orden)

Haz lo mismo con cada archivo: **SQL Editor → New query → pegar el contenido → Run**.
Si un archivo muestra un error en rojo, **detente** y guarda el mensaje. No sigas con el siguiente.

1. **`01_esquema.sql`:** crea `mc_registros`, `mc_historial` y los disparadores. Resultado esperado: *Success. No rows returned*.
2. **`02_rls.sql`:** activa la seguridad. Resultado esperado: *Success*.
3. **`03_funciones.sql`:** crea `mc_push`, `mc_pull` y `mc_indice`, y activa el tiempo real. Resultado esperado: *Success*.
4. **`04_migracion.sql`:** copia tus datos.
   1. **Antes de pulsar Run**, busca la línea `v_email  text := 'PON_AQUI_TU_CORREO';` y cambia `PON_AQUI_TU_CORREO` por tu correo, el mismo de la FASE 1. Deja las comillas.
   2. Pulsa **Run**.
   3. Al final verás una tabla con cuántos registros quedaron en cada colección (`motos`, `ventas`, etc.). **Compárala** con la consulta 5 del diagnóstico: los números deben coincidir.
   4. Si ves el error *"No existe un usuario con el correo…"*, revisa que el correo esté bien escrito y que el usuario exista (FASE 1).
   5. Ese cambio de correo **no** lo guardes en GitHub: es solo para ejecutarlo en Supabase.

**Comprobaciones después de la FASE 3:**

1. En **Table Editor** deben aparecer `mc_registros`, `mc_historial` y `mc_datos_respaldo_pre_migracion`. `mc_datos` sigue ahí intacta.
2. Abre `mc_registros`: debe mostrar un candado o el aviso "RLS enabled".
3. En **Database → Publications**, abre `supabase_realtime`: `mc_registros` debe estar marcada.
   - Si no lo está, actívala ahí mismo. Sirve para que los cambios aparezcan al instante en tus otros dispositivos.
   - Aunque no la actives, la app igual sincroniza al abrirse, al volver a la pestaña y cada 60 segundos.

> **Importante, desde que ejecutas `04_migracion.sql` hasta que empiezas a usar la versión nueva:**
> - No hagas cambios en la versión antigua de la app.
> - Lo que **crees** en la versión antigua se subirá igual la primera vez que ese dispositivo abra la versión nueva.
> - Pero si **editas** algo que ya existía, la nube conservará la versión de la migración y tu edición quedará guardada en `mc_historial` (no se pierde, pero no queda como principal).

---

## FASE 4: Primer uso de la versión nueva

1. Abre la versión nueva de la app. Mientras no se haga merge a `main`, usa el enlace de prueba de la FASE 5.
2. Aparece la pantalla **"Inicia sesión"**. Escribe tu correo y tu contraseña.
3. La primera vez en **cada dispositivo**, la app compara lo que ese navegador tenía guardado con la nube:

   | Lo que tiene el navegador | Qué hace la app |
   |---|---|
   | Un registro que no está en la nube | Lo sube |
   | Uno igual al de la nube | Nada |
   | Uno distinto al de la nube | Deja la versión de la nube como principal y guarda la del dispositivo en `mc_historial` (motivo `migracion`) |

4. Al terminar muestra un resumen, por ejemplo *"3 subidos, 1 guardado en historial"*.
5. Repite en cada dispositivo: computador, iPhone, etc.

**Guardado automático:** no hace falta pulsar nada.
- Cada vez que creas, editas o eliminas una moto, movimiento, venta, carro, contacto, meta o la personalización, la app lo envía sola a la nube.
- Los cambios seguidos se agrupan: se envían 1,2 segundos después del último, y nunca más de 5 segundos después del primero.
- El botón de la nube sigue funcionando como respaldo: envía y trae los cambios de inmediato.

**Indicador de la barra lateral:**

| Indicador | Significado |
|---|---|
| ☁️ Guardando… | Hay cambios que se están enviando o están por enviarse |
| ☁️ Guardado en la nube | Todo está confirmado en la nube |
| ☁️ Error al guardar — toca para reintentar | La nube no respondió. Tus cambios están a salvo en este dispositivo y la app reintenta sola (a los 5 s, 10 s, 20 s… hasta 1 minuto) |
| ☁️ Sin conexión — n cambios en este dispositivo | Sin internet. Se envían solos cuando vuelva la conexión. No borres la caché de ese dispositivo mientras tanto |
| ☁️ Sin conexión con la nube — toca para reintentar | Tus datos ya están guardados, pero no se pudieron traer los cambios de otros dispositivos |
| ☁️ Sin sesión | Estás usando la app sin iniciar sesión: los cambios quedan solo en este dispositivo. Toca para iniciar sesión |

---

## FASE 5: Probar antes del merge

GitHub Pages publica solo la rama `main`, y los cambios están en la rama `claude/busy-einstein-kv8c0p`. Para probar sin tocar la app que usas a diario:

- **Opción A: enlace de prueba** (servicio externo gratuito que muestra archivos de GitHub):
  `https://raw.githack.com/Samuelmonsalve256-ai/Motocontable/claude/busy-einstein-kv8c0p/index.html`
  - Funciona si el repositorio es público.
  - Es un sitio distinto a tu GitHub Pages, así que empieza "vacío", como un dispositivo nuevo. Es ideal para comprobar que al iniciar sesión se descargan todos tus datos.
  - Usa los **mismos datos reales** de Supabase.
- **Opción B:** abrir `index.html` en el computador con un servidor local, por ejemplo con la extensión *Live Server* de VS Code.

**Qué probar:**

1. **Iniciar sesión** en el computador → deben aparecer todas tus motos, ventas, etc.
2. **Crear una moto de prueba** → el indicador pasa a "Guardado ✓".
3. **Abrir en el iPhone**, iniciar sesión → la moto de prueba aparece.
4. **Editarla en el iPhone** → en el computador el cambio aparece solo, o al volver a la pestaña.
5. **Eliminarla** → desaparece en ambos. Recargar las dos páginas → no vuelve a aparecer.
6. **Borrar la caché** del navegador de prueba y volver a entrar → tras iniciar sesión, todo está de nuevo.
7. **Guardar algo y cerrar la pestaña de inmediato** → al abrir en otro dispositivo, el cambio está.
8. **Restaurar un backup JSON** → primero pide confirmación.

---

## FASE 6: Publicar (merge a `main`)

- Solo cuando estés conforme con las pruebas: se hace merge de la rama a `main` y GitHub Pages publica la versión nueva en tu dirección de siempre.
- Abre la app en cada dispositivo e inicia sesión. Así se ejecuta la migración de ese dispositivo (FASE 4).

## FASE 7: Cerrar la tabla antigua (unos días después)

- Cuando todos tus dispositivos ya usen la versión nueva y verifiques que todo está bien:
  **SQL Editor → pegar `05_cerrar_tabla_antigua.sql` → Run**.
- Esto quita el acceso público a `mc_datos`. **No borra** la tabla ni sus datos.

---

## Consultas útiles (SQL Editor)

**Ver los cambios que perdieron un conflicto o se apartaron en la migración:**

```sql
select guardado_en, motivo, coleccion, id, device_id, data
from public.mc_historial
where motivo in ('conflicto', 'migracion') and device_id <> 'migracion-sql'
order by guardado_en desc;
```

**Ver el historial completo de un registro** (cambia `ID_DEL_REGISTRO`):

```sql
select guardado_en, motivo, version, device_id, data
from public.mc_historial
where id = 'ID_DEL_REGISTRO'
order by guardado_en desc;
```

**Ver lo eliminado:**

```sql
select coleccion, id, deleted_at, data
from public.mc_registros
where deleted_at is not null
order by deleted_at desc;
```

**Restaurar un registro eliminado** (cambia `motos` e `ID_DEL_REGISTRO`):

```sql
update public.mc_registros set deleted_at = null
where coleccion = 'motos' and id = 'ID_DEL_REGISTRO';
```

Tus dispositivos lo recibirán en la próxima sincronización.

**Espacio usado:**
- El historial guarda una copia por cada edición, fotos incluidas.
- El plan gratuito de Supabase tiene 500 MB de base de datos. Revisa el uso en **Project Settings → Usage**.
- Si algún día se acerca al límite, se puede limpiar el historial más antiguo (por ejemplo, de más de un año). Pídelo antes de hacerlo.

---

## Si algo sale mal

- **La versión anterior de la app sigue en `main`** hasta que se haga el merge.
- **`mc_datos` y `mc_datos_respaldo_pre_migracion` conservan tus datos originales.**
- **Los backups JSON de la FASE 0** se pueden restaurar desde la app.
