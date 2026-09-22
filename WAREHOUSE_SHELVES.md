# Estanterías simuladas

**Almacenes y existencias → Ubicaciones.** Cada almacén describe sus
estanterías y Architect genera un espacio de almacenamiento por celda.

## La referencia AAXX-XX

`AB03-02` es la estantería **AB** (dos letras), la **columna 03** y la
**fila 02**. Columnas y filas van de 01 a 99. En la vista de la estantería la
fila 01 está abajo y la columna 01 a la izquierda; los espacios con
existencias se ven en color, con sus unidades.

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
