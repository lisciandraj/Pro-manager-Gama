# GAMA — Devoluciones

Producción: `lisciandraj/Pro-manager-Gama`, proyecto `mknsaibrewksgomuslev`.

El módulo cubre los dos sentidos de una devolución en una PYME: lo que vuelve
del cliente y lo que se devuelve al proveedor. Está montado sobre tres
preguntas y ninguna más:

1. **¿Qué vuelve?** Producto, cantidad y motivo.
2. **¿Qué se hace con ello?** Stock, rebut o devolución al proveedor.
3. **¿Y con el dinero?** Nada, abono, reembolso o crédito para el cliente.

Todo lo demás lo pone GAMA. Se elige una salida o una recepción y de ahí salen
el cliente o el proveedor, los productos, los precios, los impuestos, la divisa
y los documentos ligados: en la pantalla no se vuelve a teclear nada que ya
exista en otro sitio.

## Acceso

**Logística → Devoluciones**. Lo ven el administrador, el comercial y el
almacenero; el perfil cliente no. Los permisos del pliego se reparten así:

| | ver | crear | tratar | abonar / reembolsar | borrar |
|---|---|---|---|---|---|
| Administrador | sí | sí | sí | sí | sí |
| Comercial | sí | sí | — | — | — |
| Almacenero (logística) | sí | sí | sí | — | — |
| Finanzas | sí | sí | — | sí | — |

«Finanzas» no es un rol de GAMA: es quien tiene `can_validate` en Contabilidad.
`private.gama_returns_rights()` devuelve los cinco derechos en cada lectura y
la pantalla sólo enseña los botones que corresponden; quien decide de verdad es
el servidor, que vuelve a comprobarlos en cada acción.

## Los estados

Cuatro más el anulado, sin estados intermedios de adorno.

**Cliente** · Por tratar → Recibida → Tratada → Cerrada
**Proveedor** · Por tratar → Expedida → Abono recibido → Cerrada

Anulada existe en los dos sentidos, y sólo mientras no se haya movido
mercancía: después hay movimientos de stock detrás y anular en silencio los
dejaría huérfanos.

## Cómo se crea una devolución

Desde la lista, con **+ Nueva devolución**, son tres pantallas: qué clase, de
qué documento y qué vuelve. Pero el camino corto —el que recomienda el
pliego— es el botón **↩ Crear una devolución** que hay en la expedición del
pedido de venta y en el pedido de compra recibido: ahí el documento ya está
elegido y sólo quedan las cantidades y el motivo.

En la tabla de cantidades se ve, por producto, lo entregado o recibido, lo ya
devuelto y lo que queda. El tope lo calcula el servidor y lo vuelve a comprobar
al guardar: `RETURN_EXCEEDS_DELIVERED` y `RETURN_EXCEEDS_RECEIVED`.

## Qué pasa con el stock

Al registrar la recepción, la mercancía entra **retenida** en una zona
`RET-QUARANTINE` del almacén elegido: sube el stock físico y sube la reserva,
de modo que el **stock disponible no se mueve**. Para el usuario no hay ningún
paso de más —recibe y decide—, pero nada de lo devuelto se puede vender
mientras no se haya decidido qué es.

Al decidir línea por línea:

| Decisión | Efecto |
|---|---|
| Reponer en stock | sale de la retención y entra en la ubicación elegida: disponible +cantidad |
| Al rebut | sale de la retención y del stock: disponible sin cambio, físico −cantidad |
| Devolver al proveedor | igual que el rebut; la salida al proveedor se registra aparte |

En el sentido proveedor, la expedición descuenta la cantidad del stock
disponible del almacén de salida y exige que lo haya (`INSUFFICIENT_STOCK`).

Todos los movimientos quedan en el historial de stock, con
`reference_type = customer_return` o `supplier_return` y el número de la
devolución en el comentario.

## Dinero

El importe se calcula con los precios e impuestos que la línea copió del
documento de origen: un abono emitido hace un año se recalcula igual aunque la
tarifa haya cambiado desde entonces.

- **Abono** (`AV-000001`) — sólo si la devolución viene de una factura. El
  usuario autorizado puede ajustar el importe, pero la suma de abonos de esa
  factura no puede superar su total (`CREDIT_EXCEEDS_INVOICE`). Queda atado a
  la devolución y a la factura original.
- **Reembolso** — el importe propuesto es lo que queda por reembolsar. Ni uno
  solo ni varios sumados pueden pasarse del importe devuelto
  (`REFUND_EXCEEDS_RETURN`). Lleva `request_key`, así que reintentar no paga
  dos veces.
- **Abono del proveedor** — no se emite, se registra: referencia, importe,
  fecha y, si hace falta, el documento.

Ninguna de las cuatro acciones es obligatoria: un producto al rebut puede
acabar reembolsado y una devolución comercial puede no mover un céntimo.

## Documentos ligados

La ficha enseña el pedido, la entrega, la factura, el pedido de compra, la
factura del proveedor y los abonos, y cada uno abre su módulo. No se copia
ningún documento: se enlazan por su identificador.

La devolución entra además en el **expediente del pedido**, con prefijo `DEV`
y el mismo número de dossier, y aparece en el Seguimiento de expedientes como
el paso 11, «Devolución (flujo inverso)», que sólo se dibuja cuando existe.

## Notificaciones

Cinco avisos en el centro de acción, repartidos por quien tiene que actuar
—el almacén recibe y expide, finanzas abona y reembolsa; el administrador es
las dos cosas—. Al pulsarlos se abre la devolución.

| Aviso | Para |
|---|---|
| Devolución de cliente por recibir | almacén |
| Devolución recibida sin decidir | almacén |
| Devolución a proveedor por expedir | almacén |
| Abono del proveedor pendiente | finanzas |
| Reembolso de cliente pendiente | finanzas |

## Búsqueda y Asistente

La búsqueda global encuentra una devolución por su referencia (`RET-000014`) o
por lo escrito en sus comentarios, y la palabra «retours / devoluciones /
returns» la lleva al módulo. El cliente o el proveedor se enseñan en el
resultado, pero el filtro por nombre de tercero vive en el buscador de la
propia pantalla, que sí consulta por él en el servidor.

El Asistente IA lee las cuatro tablas por el catálogo existente —sin sistema
propio— con los permisos del usuario, así que responde a «qué devoluciones
están abiertas», «qué productos se devuelven más» o «cuánto hemos reembolsado
este mes».

## Reglas que vive el servidor

Ninguna de estas depende de la pantalla:

- no se devuelve más de lo entregado o recibido, menos lo ya devuelto;
- no se abona por encima de la factura ni se reembolsa por encima de lo
  devuelto, ni de una vez ni sumando varios;
- una línea no se procesa dos veces (`LINE_ALREADY_PROCESSED`);
- la retención de cuarentena no se suelta a mano: `gama_stock_unreserve` la
  rechaza con `FULFILLMENT_RESERVATION_LOCKED`;
- una devolución cerrada o anulada no se modifica (`RETURN_CLOSED`);
- lo que ya movió mercancía no se anula ni se borra
  (`RETURN_ALREADY_STARTED`).

## Datos

Cinco tablas nuevas y ninguna copia de lo que ya existía:

| Tabla | Qué guarda |
|---|---|
| `return_orders` | la cabecera: sentido, estado, motivo, decisión financiera y los enlaces a pedido, entrega, factura, compra y factura de proveedor |
| `return_lines` | una línea por producto, con el precio e impuesto copiados del origen, la decisión tomada y su retención |
| `return_credits` | abonos emitidos al cliente y abonos recibidos del proveedor |
| `return_refunds` | reembolsos, con `request_key` para que reintentar no pague dos veces |
| `return_files` | fotos y documentos, hasta seis por devolución |

Todas se leen desde la pantalla y **ninguna se escribe directamente**: la
única puerta es `public.gama_returns_action(text,jsonb)`. `authenticated` tiene
sólo `SELECT`, con RLS para los tres roles; el resto de privilegios está
retirado, incluido `TRUNCATE`, que la RLS no detiene.

Las cinco llevan disparador de auditoría, así que creación, recepción,
reposición, rebut, abono, reembolso, anulación y cierre quedan en
`gama_audit` con usuario, fecha, acción y valores antes y después.

## Qué sustituye

GAMA ya tenía `customer_returns`, `customer_return_credits` y
`customer_return_photos`, con la mecánica de almacén resuelta dentro de
`gama_fulfillment_action` pero sin cabecera de documento, sin varias líneas por
devolución, sin lado proveedor, sin reembolsos y sin pantalla propia: vivía
enterrado en el dossier del pedido. Las tres tablas estaban **vacías**, así que
en vez de dejar dos sistemas para la misma noción se reordenaron en uno solo y
las viejas se retiraron, junto con sus seis acciones y su pantalla.

Lo único que no se conserva es el atajo de «cambio sin cobro», que creaba un
pedido de reposición a precio cero desde la inspección. Nunca se usó (cero
filas) y el pliego pide tres decisiones, no cuatro; un cambio se hace hoy como
lo que es: la devolución por un lado y un pedido nuevo por el otro.

## Pruebas

- `tests/sql/returns.sql` — los ocho casos de servidor del pliego dentro de una
  transacción que siempre se deshace: devolución simple (stock +2), rebut
  (disponible sin cambio al recibir), devolución parcial (máximo 6 de 10),
  tope de reembolso, devolución a proveedor (stock −5), abono atado a la
  factura, doble tratamiento bloqueado y los cuatro perfiles. Añade el
  expediente, la pista de auditoría, la anulación y el borrado.
  Cargar antes `tests/sql/fulfillment-test-helpers.sql` en la misma
  transacción.
- `tests/returns.spec.js` — la pantalla: los cuatro indicadores y la tabla del
  pliego, las dos pestañas, la creación en tres pasos sin doble captura, la
  decisión sobre el producto, el tope del reembolso, los botones de cada
  perfil, PC/tableta/móvil y las tres lenguas.
