# GAMA — Gestión de flota

Producción: `lisciandraj/Pro-manager-Gama`, proyecto `mknsaibrewksgomuslev`.

El módulo cubre los dos vehículos que tiene una PYME: el coche de empresa y el
camión de transporte. Responde a cinco preguntas: qué vehículos hay y en qué
estado, quién conduce cada uno, qué papeles caducan pronto, cuánto consume y
cuánto cuesta cada kilómetro, y qué se ha gastado este mes en carburante y
taller.

## Acceso

**Administración → Gestión de flota**. Sólo el administrador entra. No es una
convención de pantalla: `private.gama_fleet_may()` exige el rol
`administrador` y lo comprueban tres capas independientes —la RPC del módulo,
las políticas RLS de las siete tablas y la rama de flota del centro de acción—,
así que un perfil comercial o de almacén no ve la flota ni por la interfaz ni
por la API ni por sus alertas.

## Las cuatro secciones

| Sección | Para qué |
|---|---|
| Tablero | Vehículos por estado, vencimientos a 30 días, gasto del mes y consumo medio por vehículo |
| Vehículos | Lista con filtros y buscador; la ficha se abre con sus cuatro pestañas |
| Conductores | Personas, permisos, categorías y vehículo asignado |
| Vencimientos | Todo lo que caduca a 60 días y el registro de avisos ya enviados |

La ficha del vehículo tiene cuatro pestañas: **Información** (datos,
foto, conductor actual e historial), **Documentos**, **Carburante** y
**Entretenimientos**.

## El permiso de conducir se sigue desde RRHH

El permiso es de la persona, no del vehículo, así que quien vigila su caducidad
es RRHH. **RRHH → Documentos e historial → Permisos de conducir** lista a los
empleados con su número de permiso, sus categorías, la fecha de caducidad, lo
que queda y el vehículo que llevan; lo que caduca dentro del mes se marca, y lo
ya vencido en rojo.

El dato **no se duplica**: se guarda en `fleet_drivers`, que es exactamente lo
que alimenta las alertas de la flota. Renovar un permiso desde RRHH mueve la
misma fila que lee `gama_fleet_deadlines`, así que el aviso a 30 días se
recalcula solo. Si el empleado todavía no tiene ficha de conductor, RRHH la
crea al registrar el permiso y la flota se la encuentra hecha.

La puerta es la de RRHH, no la de flota: `public.gama_hr_licences` exige
`private.hr_admin()` —administrador o rol `hr`—, de modo que RRHH sigue los
permisos sin tener acceso al módulo de flota. Un responsable de equipo sin
derechos de RRHH no ve nada. RRHH toca el permiso y el teléfono; la asignación
de vehículo es de la flota y no se cambia desde ahí.

Los conductores que no son empleados —externos, temporales— no salen en esa
lista porque RRHH no los gestiona, pero se cuentan al pie para que nadie lea la
lista como si fuera toda la flota.

## El TMS ya no guarda conductores ni vehículos

El módulo de transporte tenía su propio registro de conductores, y dentro de
cada conductor un vehículo escrito a mano con su capacidad: tres nociones —la
persona, el vehículo y lo que ese vehículo carga— metidas en una fila. Ese
registro se ha retirado y la pestaña «Conductores y vehículos» ya no existe.

Ahora el reparto lee lo que ya está: la persona viene de **RRHH**, el vehículo
y su capacidad de **Flota**, y el emparejamiento de los dos de las afectaciones
de Flota, que ya garantizan un conductor por vehículo a la vez y guardan el
historial. Para el TMS, un recurso de reparto es exactamente eso: un conductor
con el vehículo que Flota le tiene asignado hoy.

Eso **no** abre Flota al almacén. El TMS lee por una puerta estrecha,
`public.gama_tms_resources`, abierta a administración y almacén, que devuelve
sólo lo que hace falta para repartir: nombre, teléfono, matrícula, capacidad,
si el vehículo está en servicio y si RRHH tiene una ausencia aprobada para hoy.
Ni permisos de conducir, ni costes, ni documentos, ni fotos. El módulo de Flota
sigue siendo únicamente del administrador.

Cuando no hay nada emparejado, la planificación y la salida de bultos lo dicen
y mandan al sitio correcto —alta en RRHH, emparejamiento en Flota— en vez de
ofrecer un formulario que ya no existe. Una salida sin vehículo asignado se
rechaza con `DRIVER_REQUIRED`.

La capacidad, por tanto, es del vehículo: `payload_kg` en kilos y
`cargo_volume_m3` en metros cúbicos, y se piden para cualquier vehículo, no
sólo para los camiones —una furgoneta de reparto también carga—. El PTAC sigue
siendo cosa de camiones.

## Modelo de datos

Siete tablas, todas nuevas: el módulo no toca ninguna existente.

| Tabla | Contenido |
|---|---|
| `fleet_vehicles` | Matrícula, marca, modelo, tipo, energía, matriculación, kilometraje, estado, foto, carga útil y volumen de carga; el PTAC sólo para camiones |
| `fleet_drivers` | Nombre, teléfono, número y categorías de permiso, caducidad |
| `fleet_assignments` | Qué conductor lleva qué vehículo, con fecha de inicio y de fin |
| `fleet_documents` | Seguro, inspección técnica y permiso de circulación, con caducidad y adjunto |
| `fleet_fuel_logs` | Repostajes: fecha, kilometraje, litros, importe, estación |
| `fleet_maintenance` | Intervenciones y próxima revisión prevista, por fecha o por kilometraje |
| `fleet_alert_log` | Qué vencimiento se avisó y cuándo, para no repetir el aviso |

Las personas siguen viviendo en **RRHH** y los repartidores en **TMS**:
`fleet_drivers` enlaza opcionalmente con `hr_employees` en lugar de duplicarlo,
y el TMS ha dejado de tener registro propio: lee éste. Lo único que guarda de su cosecha es el permiso de
conducir, que no tenía sitio en ninguna de las dos.

Tres reglas viven en la base y no en la pantalla, para que se cumplan venga la
escritura de donde venga:

- Un coche no declara PTAC ni carga útil (`check(kind='truck' or …)`), y la
  carga útil nunca supera el PTAC.
- Un vehículo tiene **un** conductor a la vez: un índice único parcial sobre
  `(vehicle_id) where ended_on is null`. Asignar otro cierra el anterior, que
  queda en el historial.
- Un vencimiento se avisa una sola vez: `unique nulls not distinct
  (alert_key, due_on)`. El `nulls not distinct` es lo que hace que una revisión
  prevista **por kilometraje** —que no tiene fecha— tampoco se repita.

## Consumo y coste por kilómetro

No se teclean: salen de los repostajes, por el método de **depósito lleno a
depósito lleno**. La ventana de medida va del primer al último repostaje con
el depósito lleno; dentro de ella cuentan todos los litros repostados, llenos
o parciales. El primer lleno no cuenta como consumido: sólo marca el punto de
partida del cuentakilómetros.

    ventana    = del primer al último repostaje con «Depósito lleno» marcado
    L/100 km   = litros repostados dentro de la ventana ÷ km de la ventana × 100
    coste / km = importe repostado dentro de la ventana ÷ km de la ventana

Un repostaje parcial **fuera** de esa ventana no alarga los kilómetros medidos
—si lo hiciera, el consumo medio bajaría solo—, pero sí cuenta en el gasto del
vehículo. Con menos de dos repostajes llenos no hay nada que medir y las dos
cifras quedan vacías en vez de enseñar un cero que parecería un dato.

El kilometraje del vehículo tampoco se teclea aparte: lo arrastra el repostaje
o el entretenimiento más reciente, y sólo hacia arriba —registrar un plein
antiguo no hace retroceder el contador.

## Vencimientos y alerta automática

`private.gama_fleet_deadlines` reúne en un solo sitio lo que caduca: permiso de
conducir, los tres documentos del vehículo y la próxima revisión por fecha o
por kilometraje. Todo lo demás lo lee de ahí —el tablero, la lista, el centro
de acción y la tarea programada—, así que la regla de «qué caduca» se escribe
una vez.

La tarea corre sola: `pg_cron` llama a
`private.gama_fleet_check_deadlines(30)` **cada día a las 07:00 de Guayaquil**
(12:00 UTC, trabajo `gama-fleet-deadlines`). Avisa 30 días antes de una fecha y
1 000 km antes de una revisión por kilometraje, y deja constancia en
`fleet_alert_log`. GAMA no envía correo: el aviso se entrega dentro de la
aplicación, en el **Centro de acción**, junto al resto de alertas. Lo que vence
en una semana —o a menos de 200 km— sube a prioridad alta. El botón
«Comprobar vencimientos ahora» del tablero hace la misma pasada sin esperar a
mañana.

## API

Un solo punto de entrada, como el resto de GAMA:
`public.gama_fleet_action(p_action text, p_data jsonb)`, invoker, que delega en
las dos funciones privadas `SECURITY DEFINER`. Toda escritura pasa por ahí: las
tablas sólo conceden `select` a `authenticated`, y aun ése lo filtra la RLS.

| Acción | Qué hace |
|---|---|
| `overview` | Estado de la flota, gasto del periodo, vencimientos y consumo |
| `vehicles` · `vehicle` | Lista (sin la foto) y ficha completa |
| `vehicle_save` · `vehicle_photo` · `vehicle_delete` | Alta, modificación, foto y baja |
| `drivers` · `driver_save` · `driver_delete` | Conductores |
| `assign` · `unassign` | Afectación de un vehículo a un conductor |
| `document_save` · `document_file` · `document_delete` | Documentos y su adjunto |
| `fuel_save` · `fuel_delete` | Repostajes |
| `maintenance_save` · `maintenance_delete` | Entretenimientos |
| `assignment_delete` | Una línea del historial de conductores |
| `deadlines` · `check_deadlines` · `alert_log` | Vencimientos y avisos |
| `alert_delete` · `alert_clear` | Un aviso enviado, o el registro entero |
| `export` | Vehículos y gastos del periodo, para Excel |

Y, fuera del módulo, dos puertas estrechas que leen las mismas tablas con otro
permiso, porque quien las cruza no es el administrador de flota:

| Puerta | Quién | Para qué |
|---|---|---|
| `public.gama_hr_licences(p_action, p_data)` | `private.hr_admin()` | RRHH lee y renueva el permiso de conducir de sus empleados |
| `public.gama_tms_resources()` | administración y almacén | El TMS lee conductor, matrícula y capacidad para repartir |

Ninguna de las dos devuelve nada más de Flota, y ninguna permite escribir en
ella salvo el permiso de conducir desde RRHH.

`fuel_save` y `maintenance_save` aceptan un `request_key`: un doble envío del
formulario devuelve la fila ya creada en vez de duplicarla.

Dar de baja no borra a ciegas. Un vehículo o un conductor **con historial** se
archiva —deja de aparecer en las listas y conserva sus datos—; sólo se elimina
lo que nunca llegó a usarse.

El administrador puede además **borrar de verdad**, marcando la casilla de
borrado definitivo: es un segundo gesto a propósito, nunca el que sale por
defecto. Todo lo que se teclea en Flota se puede quitar —vehículos, conductores,
documentos, repostajes, entretenimientos, líneas del historial de conductores y
el registro de avisos, entero o fila a fila—. Dos reglas al borrar:

- Un vehículo se lleva en cascada sus documentos, repostajes, entretenimientos
  e historial: era todo suyo.
- Un conductor **no** se lleva sus repostajes. Un plein es un gasto de la
  empresa y sigue contando en el consumo del vehículo; lo que se pierde es a
  quién se atribuía. El formulario lo dice antes de borrar.

Borrar no borra el rastro de haber borrado: los triggers de auditoría dejan en
`gama_audit` quién lo hizo, cuándo y con qué contenido. Y vaciar el registro de
avisos no silencia nada: lo que siga vencido se vuelve a señalar en la próxima
pasada de la tarea programada.

La foto viaja en la ficha pero **no** en la lista: la lista devuelve
`has_photo` y las columnas que pinta. El adjunto de un documento tampoco viaja
en la ficha: se pide con `document_file` cuando alguien lo descarga.

## Formularios en el teléfono

Un repostaje se rellena de pie junto al surtidor, así que todos los campos
miden 16 px y 42 px de alto —por debajo de eso iOS hace zoom al entrar en el
campo y el formulario deja de poder usarse—. La foto del vehículo y el adjunto
de un documento abren la cámara (`capture="environment"`) y la imagen se reduce
en el navegador antes de subirse. `tests/fleet.spec.js` comprueba las cuatro
anchuras (móvil, tableta en ambos sentidos y escritorio) sin desplazamiento
horizontal, y mide los campos del formulario.

## Divisa e idioma

Los importes se formatean con `GamaCurrency`, nunca con un símbolo escrito a
mano: si la empresa trabaja en dólares se ve `$`, si trabaja en euros se ve `€`,
y las cifras no cambian. La interfaz está en español, francés e inglés por el
catálogo `locales/catalog.tsv`; los números que acompañan a una unidad van
fuera del texto traducido —«5 días restantes», «5 jours restants», «5 days
left»— porque el catálogo busca la frase entera.

## Exportación

Dos caminos, y hacen cosas distintas. El botón **Exportar a Excel** del tablero
saca lo que pide la dirección: la lista de vehículos con su conductor y su
consumo, y los gastos del mes —carburante y taller— en un CSV que Excel abre de
doble clic en las tres lenguas.

La **copia de seguridad Excel** de Informes lleva además las siete tablas
completas, en su propia hoja «Flota». Las fotos de los vehículos y los adjuntos
de los documentos quedan fuera, como el resto de binarios de GAMA: una celda de
Excel se corta a 32 767 caracteres y el libro anuncia ese límite en su resumen.

## Datos de demostración

La migración carga 4 coches, 2 camiones y 3 conductores, con sus documentos,
repostajes y entretenimientos, sólo si la tabla está vacía. Van marcados para
poder retirarlos de una orden cuando entren los reales:

    delete from public.fleet_vehicles where is_demo;
    delete from public.fleet_drivers  where is_demo;

Los documentos, repostajes y entretenimientos caen con el vehículo.

## Ficheros

    gama-fleet.js                                        el módulo
    gama-hr-p1.js                                        la sección de permisos en RRHH
    supabase/migrations/20260917190000_fleet_management.sql   tablas, vistas, API, cron y demo
    supabase/migrations/20260918010000_fleet_purge_and_hr_licences.sql   purga y permisos en RRHH
    supabase/migrations/20260918020000_tms_drivers_into_fleet.sql        el TMS deja de guardar conductores
    gama-tms-module.js · gama-tms-loading.js             leen la puerta de reparto
    tests/fleet.spec.js                                  22 pruebas
    tests/hr-p1.spec.js                                  3 de ellas, las de RRHH
