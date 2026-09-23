# Estanterías simuladas

**Almacenes y existencias → Ubicaciones.** Cada almacén describe sus
estanterías y Coco ERP genera un espacio de almacenamiento por celda.

## La referencia AAXX-XX

`AB03-02` es la estantería **AB** (dos letras), la **columna 03** y la
**fila 02**. Columnas y filas van de 01 a 99. En la vista de la estantería la
fila 01 está abajo y la columna 01 a la izquierda; los espacios con
existencias se ven en color, con sus unidades.

## Ver lo que guarda un espacio

Cada celda es un botón: al pulsarla (o con Intro desde el teclado) se abre una
ventana con lo que hay en ese espacio, producto por producto y por orden
alfabético: cantidad, reservado y disponible, con el total debajo. Un espacio
vacío lo dice. Las otras ubicaciones con existencias tienen el mismo botón,
**Ver contenido**. Es sólo lectura: lo ve cualquiera que abra la pantalla.

## Encontrar un producto

Encima de los almacenes, **Encontrar un producto** busca por nombre,
referencia o código de barras, sin distinguir tildes ni mayúsculas. Por cada
producto encontrado dice cuántas unidades hay y en cuántas ubicaciones, con un
botón por sitio (`AB02-01 · 40 uds.`); primero los que tienen existencias, y
los que no, con «Sin existencias en ninguna ubicación». Las estanterías y las
zonas donde está quedan rodeadas en naranja sin abrirse; pulsar un sitio abre
su estantería y señala el espacio. La búsqueda se conserva al cambiar de
pestaña.

Pruebas: `tests/warehouse-locate.spec.js`.

## Configurar

«＋ Nueva estantería» pide el código (dos letras), el nombre (opcional), las
columnas, las filas y, si se quiere, la zona de la que cuelga. La vista previa
dice qué espacios se van a crear. «Configurar» cambia el nombre, la zona y las
medidas; el código no se cambia, porque ya está en etiquetas y movimientos.

Lo configuran el administrador y el almacenero; el comercial lo ve.

## Dónde se usan los espacios

Cada espacio es una ubicación de verdad (`warehouse_locations`, tipo `bin`,
con `shelf_id`), así que aparece en todos los desplegables que ya listan
ubicaciones: transferencias, recuentos, ajustes, recepción de compras,
preparación… Sin nada más que hacer.

## Quitar

Reducir una estantería o eliminarla sólo quita espacios **vacíos**: sin
existencias, reservas activas, lotes ni compras abiertas con ese destino. Si
alguno no lo está, el servidor dice cuáles (`SHELF_SPACE_IN_USE`,
`SHELF_NOT_EMPTY`). Un espacio vacío se borra; si su historial lo nombra
(movimientos, recuentos…) se archiva, y volver a crear la estantería lo
reutiliza.

## Servidor

`public.gama_shelf_action('save'|'delete', datos)` — la única puerta de
escritura, con control de versión (`SHELF_STALE`). Tabla
`warehouse_shelves`, sólo lectura para el personal. Migración
`warehouse_shelves`; pruebas `tests/warehouse-shelves-db.test.cjs` y
`tests/warehouse-shelves.spec.js`.

## Otras ubicaciones

Debajo de las estanterías, la lista de **otras ubicaciones** es a medida. Cada
almacén trae tres zonas por defecto, marcadas y en cabeza:

| Zona | Código | Para qué |
|---|---|---|
| Zona de llegada | `LLEGADA` | Entran las recepciones de compra y las entradas manuales (`gama_default_location`). |
| Zona de salida | `SALIDA` | La preparación de pedidos deja aquí lo preparado (antes, una zona `PR-…` por preparación). |
| Cuarentena | `CUARENTENA` | Esperan las devoluciones de clientes hasta revisarlas (antes `RET-QUARANTINE`). |

Los procesos las buscan por su papel (`warehouse_locations.role`), no por el
código: se renombran pero no se eliminan (`LOCATION_ROLE_REQUIRED`). Las demás
se crean, renombran y eliminan desde **＋ Nueva ubicación** con
`public.gama_location_action('save'|'delete', datos)`: código de letras,
cifras, punto o guion (nunca con la forma AAXX-XX de un espacio de estantería),
fijo una vez creado; sólo se elimina lo vacío y lo que ninguna preparación en
curso usa. Un código archivado que se vuelve a crear recupera su historial.

La migración `warehouse_default_zones` vació lo que había: las existencias de
las antiguas ubicaciones y de la raíz `STOCK` pasaron a la zona de llegada con
un movimiento de transferencia interna («Reorganización de ubicaciones»), sin
cambiar el total de ningún producto; las ubicaciones se borraron o, si el
historial las nombraba, se archivaron. Las estanterías no se tocaron.

## Transferencias

Al elegir el producto, **Desde** sólo ofrece las ubicaciones donde hay
existencias suyas, con lo disponible; si sólo hay una, queda elegida. **Hacia**
ofrece todas las demás, nunca la misma ni la raíz del almacén.

Pruebas: `tests/warehouse-zones-db.test.cjs`, `tests/warehouse-zones.spec.js`,
`tests/inventory-transfer.spec.js`.
