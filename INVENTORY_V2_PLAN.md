# GAMA · Inventario V2 — auditoría y plan

Estado real de lo que hay hoy y el camino hacia un motor de inventario con
almacenes, ubicaciones, reservas y conteos. Describe lo que existe, no lo que
se planeó. Escrito antes de tocar código, a partir del repositorio y de la
base de datos de producción (proyecto `mknsaibrewksgomuslev`, leída en modo
consulta).

---

## 1. Arquitectura actual

Tres capas, y conviene no confundirlas:

**a) El `db` local de index.html.** Un objeto en memoria que se guarda en
`localStorage` bajo `stock_manager_v6_ecuador`. Tiene `db.products`,
`db.moves`, `db.clients`, `db.invoices`. Usa nombres propios —`stock`, `min`,
`maxStock`, `price`, `barcode`— que NO son los de Postgres. De aquí se pintan
el Inventario, los movimientos y la facturación local.

**b) `gama-central-sync.js`.** El puente. Traduce en los dos sentidos entre el
`db` local y las tablas de Supabase, y es quien llama a las RPC cuando una
operación toca stock de verdad.

**c) Supabase/PostgreSQL.** Las tablas reales y las dos funciones
transaccionales. Es donde está —o debería estar— la verdad.

El resto de módulos (Compras, Tarifas, CRM, RRHH, TMS, Catálogo) hablan
directamente con Supabase a través de `window.GamaCloud`, sin pasar por el
`db` local.

---

## 2. Dónde está hoy la verdad del stock

En `products.stock`, una sola columna numérica por producto. No hay almacén,
no hay ubicación real y no hay reserva.

`products.location` existe, pero es **texto libre** ("Bodega 2", "Estante
A"): sirve para que una persona lo lea, no para agregar ni para mover.

Consecuencia: hoy la aplicación sabe *cuánto* hay, pero no *dónde*, ni
*cuánto de eso ya está comprometido*.

`stock_movements` sí es un historial correcto —con `stock_before` y
`stock_after`— pero sólo del total del producto, sin origen ni destino.

### Esquema verificado en producción

```
products             id, barcode, name, reference, category, location(text),
                     supplier_id, min_stock, stock, sale_price, tax_rate,
                     active, created_at, updated_at, photo_data, has_photo,
                     description, family, lines, brand, presentation,
                     qty_per_carton, weight_g, volume_cm3, max_stock,
                     sale_price_b, purchase_price
stock_movements      id, product_id, type, quantity, reason, comment,
                     user_id, created_at, stock_before, stock_after
purchase_orders      id, supplier_id, order_number, order_date, expected_date,
                     status, notes, subtotal, tax, total, created_by, ...
purchase_order_lines id, purchase_order_id, product_id, quantity,
                     received_quantity, unit_cost, tax_rate, line_total
```

> **Hallazgo que afecta al plan.** `supabase-migration-2026-09-product-fields-pricing.sql`
> dice sustituir `products.purchase_price` por `price_a`/`price_b`. En la base
> de producción **esa migración no está aplicada**: `purchase_price` sigue ahí
> y `price_a`/`price_b` no existen. `gama_receive_purchase` todavía escribe
> `purchase_price`. Inventario V2 no depende de ese cambio, pero **no debe dar
> por hecho `price_a`/`price_b`**: la valorización de stock usa
> `purchase_price` mientras esa migración siga sin aplicarse.

---

## 3. Qué modifica el stock hoy

Cuatro caminos, y sólo tres son transaccionales:

| # | Camino | Dónde | Transaccional |
|---|--------|-------|---------------|
| 1 | Entrada/Salida (IN/OUT) | `gama-central-sync.js:56` → `gama_register_stock_movement` | sí |
| 2 | Corrección de inventario | `gama-central-sync.js:57` → misma RPC con `adjustment` | sí |
| 3 | Recepción de compra | `gama-purchases-v14.js` → `gama_receive_purchase` | sí |
| 4 | **Alta/edición de producto** | `gama-central-sync.js:41,53` → `insert/update('products')` | **no** |

El camino 4 es el agujero actual: al crear un producto con stock inicial, o al
editarlo, se escribe `products.stock` por PostgREST sin movimiento asociado y
sin pasar por ninguna RPC. No deja rastro en el Audit Trail.

### `gama_register_stock_movement(p_product_id, p_type, p_quantity, p_reason, p_comment)`

`SECURITY DEFINER`, `search_path = public, private`. Exige `auth.uid()`, exige
rol `administrador` o `almacenero`, acepta `in|out|adjustment`, bloquea el
producto con `select … for update`, rechaza dejar el stock negativo
(`INSUFFICIENT_STOCK`), actualiza `products.stock` e inserta el movimiento con
`stock_before`/`stock_after`. Devuelve la fila de `stock_movements`.

### `gama_receive_purchase(p_purchase_order_id, p_lines jsonb, p_comment)`

`SECURITY DEFINER`. Mismo control de rol. Bloquea la orden, cada línea y cada
producto con `for update`. Valida estado (`sent|partial`, nunca `cancelled`) y
que no se reciba más de lo pedido (`RECEIPT_EXCEEDS_ORDERED`). Suma a
`products.stock`, escribe `purchase_price = unit_cost`, acumula
`received_quantity`, inserta un `stock_movements` de tipo `in`, y cierra la
orden a `received` o `partial`. Soporta recepciones parciales.

**Las dos funciones son buenas y hay que construir SOBRE ellas, no al lado.**

### RLS vigente

- `products`: lectura `private.is_staff()`; escritura `administrador|comercial`.
- `stock_movements`: lectura `private.is_staff()`; inserción `administrador|almacenero`.
- `purchase_orders(_lines)`: `administrador|comercial`.

Helpers existentes a reutilizar: `private.current_user_role()` y
`private.is_staff()`. No se inventan roles nuevos.

---

## 4. Dependencias con el resto

- **Compras** (`gama-purchases-v14.js`): recibe contra `gama_receive_purchase`.
  Es el único productor de entradas por compra. `purchase_order_lines`
  (`quantity − received_quantity` de órdenes abiertas) es la fuente natural
  del *entrante*.
- **Facturación** (index.html): `addInvoiceItem()` comprueba
  `p.stock < already + q` contra el `db` local. Es una comprobación de UX; hoy
  no reserva nada y no la respalda el servidor.
- **Catálogo** (`gama-client-catalog.js`): lee la vista `catalog_products`,
  que esconde coste, proveedor y ubicación al rol `cliente`. **Cualquier campo
  nuevo de logística debe quedar fuera de esa vista.**
- **TMS**: entregas y rutas; hoy no descuenta stock. Es el futuro consumidor
  natural de reservas y de la salida física.
- **Excel** (`gama-excel-import-v1.js`): importa productos y toca stock por el
  camino 4.
- **Inventario** (index.html `renderStock`): lee sólo el `db` local; búsqueda,
  filtro por categoría, orden (`GamaSort`), stock bajo y resumen
  (`#stockSummary`) están fijados por `tests/inventory.spec.js`.

---

## 5. Riesgos de regresión

1. **Doble verdad.** Si `stock_quants` y `products.stock` pueden divergir en
   silencio, el sistema queda peor que antes. Mitigación: los quants se tocan
   sólo dentro de RPC que actualizan las dos cosas en la misma transacción, y
   un test del invariante `SUM(quants) = products.stock`.
2. **El `db` local.** Inventario y facturación leen de `localStorage`, no de
   Postgres. V2 no puede asumir que lo que ve la pantalla es la verdad.
3. **`tests/inventory.spec.js`** fija el orden, el filtro y el resumen de la
   tabla actual. La tabla V2 debe conservar esas columnas y esos ids.
4. **`catalog_products`**: si una columna nueva se filtra a esa vista, se
   rompe la frontera del rol `cliente` (hay tests que la vigilan).
5. **El camino 4** seguirá escribiendo `products.stock` sin quant. Hay que
   decidir explícitamente qué hacer con él (ver §7, fase 2).
6. **Rendimiento**: `gama-central-sync.js` ya sincroniza en bloque. Añadir
   quants sin paginar ni filtrar multiplicaría el tráfico. Nunca traer
   `photo_data` en listados de inventario.
7. **RPC no versionadas.** Las funciones viven sólo en Supabase, no en el
   repositorio. Este plan incorpora su fuente a las migraciones para que dejen
   de ser invisibles.

---

## 6. Esquema objetivo

```
warehouses          id, code (unique), name, address, city, active, timestamps
warehouse_locations id, warehouse_id → warehouses, parent_id → self,
                    code, name, type (warehouse|zone|aisle|rack|shelf|bin),
                    barcode, picking_priority, active, created_at
                    unique (warehouse_id, code)
stock_quants        id, product_id → products, location_id → warehouse_locations,
                    quantity, reserved_quantity, updated_at
                    unique (product_id, location_id)
                    check quantity >= 0
                    check reserved_quantity >= 0 and reserved_quantity <= quantity
stock_reservations  id, product_id, location_id, quantity, reference_type,
                    reference_id, status (active|released|consumed),
                    created_by, created_at, released_at
stock_movements     + source_location_id, destination_location_id,
                    + movement_type, reference_type, reference_id
                    (type/quantity/stock_before/stock_after se conservan)
inventory_counts    id, warehouse_id, reference, status
                    (draft|in_progress|validated|cancelled),
                    created_by, started_at, completed_at
inventory_count_lines count_id, product_id, location_id, expected_quantity,
                    counted_quantity, variance, validated
reorder_rules       product_id, warehouse_id, min_quantity, max_quantity,
                    reorder_quantity, supplier_id, lead_time_days, active
```

### Magnitudes y sus fórmulas

| Magnitud | Fórmula | Fuente |
|---|---|---|
| On hand | `SUM(stock_quants.quantity)` | quants |
| Reservado | `SUM(stock_quants.reserved_quantity)` | quants |
| Disponible | `on_hand − reservado` | derivado |
| Entrante | `SUM(pol.quantity − pol.received_quantity)` de órdenes en `sent|partial` | compras |
| Previsto | `disponible + entrante` | derivado |
| Valor de stock | `on_hand × products.purchase_price` | ver §2 |

`products.stock` queda como **caché del total on-hand**, mantenido por las
mismas RPC que tocan los quants. Regla dura: nadie escribe una sin la otra.

### Lotes, series y unidades (§16, §17) — preparado, no implementado

`stock_quants` es el punto de extensión: añadir `lot_id` nullable y ampliar la
clave única a `(product_id, location_id, lot_id)` no rompe nada de lo que se
construye ahora, porque todas las lecturas agregan por producto. FIFO/FEFO
saldrían de ordenar quants por fecha de un futuro `stock_lots`. Igual con las
unidades: `qty_per_carton`, `weight_g` y `volume_cm3` se conservan intactos;
las conversiones Unidad/Caja/Palé vivirían en una tabla aparte que traduce a
la unidad base antes de tocar un quant. **Nada de esto se implementa ahora**:
se deja el esquema sin cerrarle la puerta.

---

## 7. Orden de trabajo

Cada fase es un commit. Las migraciones son ficheros
`supabase-migration-2026-09-*.sql`, aditivas e idempotentes, que **se aplican a
mano** contra Supabase —la convención de este repositorio, escrita en la
cabecera de las migraciones que ya existen—. El código nuevo tolera que la
migración todavía no esté aplicada y cae al comportamiento actual.

**Fase 1 — Esquema y migración del histórico.**
Tablas, índices, RLS, y el traspaso sin pérdida: un almacén `PRINCIPAL`, una
ubicación `STOCK`, y un quant por cada producto con `stock <> 0`.
`products.location` se conserva tal cual y se copia a
`warehouse_locations.name` cuando el texto identifica una ubicación sin
ambigüedad. Idempotente: `on conflict do nothing`.

**Fase 2 — Inventario V2 y agregados.**
Vista `stock_overview` (on hand, reservado, disponible, entrante, previsto por
producto y almacén) y la tabla nueva, conservando búsqueda, filtro, orden,
stock bajo, resumen y export. Aquí se decide el camino 4: el alta de producto
con stock inicial pasa a generar su quant y su movimiento.

**Fase 3 — Transferencias.** `gama_stock_transfer`, atómica, con bloqueo de
las dos ubicaciones en orden estable para no dar pie a interbloqueos.

**Fase 4 — Reservas.** `gama_stock_reserve` / `gama_stock_unreserve` y
`stock_reservations`. La restricción `reserved <= quantity` la garantiza la
tabla, no el frontend.

**Fase 5 — Conteos físicos.** El stock sólo se mueve al validar, y lo hace
generando ajustes normales: un conteo no es una puerta trasera.

**Fase 6 — Reabastecimiento.** `reorder_rules` y la pantalla de sugerencias.
Sin crear órdenes automáticas.

**Fase 7 — Integración con Compras.** Recepción hacia una ubicación concreta,
extendiendo `gama_receive_purchase` en vez de duplicarla: se conserva su firma
exacta —para no crear una sobrecarga ambigua— y cada línea del jsonb admite un
`location_id` opcional. La ficha del pedido ofrece el destino agrupado por
almacén, con la ubicación por defecto ya seleccionada.

Ese `opcional` es deliberado y es lo que hace la fase compatible hacia atrás:
la pantalla de Compras consulta `warehouses` y `warehouse_locations` de forma
tolerante, y si la migración todavía no está aplicada no enseña el desplegable
y envía las líneas sin destino, que es exactamente lo que hacía antes. Una
pantalla de compras no puede dejar de recibir mercancía porque falte una tabla
nueva; la prueba `purchase-receive-location.spec.js` fija las dos ramas.

### Concurrencia

Todas las RPC siguen el patrón que ya usan las dos existentes: `select … for
update` sobre las filas implicadas, validación **después** del bloqueo, y una
sola transacción. Los dos bloqueos de una transferencia se toman siempre en el
mismo orden (por `location_id`) para evitar interbloqueos. Las restricciones
`check` de `stock_quants` son la última línea: aunque una RPC tuviera un fallo
lógico, Postgres no deja que el stock quede negativo ni que lo reservado supere
lo que hay.

---

## 8. Puesta en producción

Las tres migraciones se aplican **a mano** contra Supabase, en este orden, y
cada una es idempotente: volver a ejecutarla no rompe nada.

| # | Fichero | Qué deja |
|---|---------|----------|
| 1 | `supabase-migration-2026-09-inventory-v2-phase1.sql` | `warehouses`, `warehouse_locations`, `stock_quants`, las columnas nuevas de `stock_movements`, las RLS y el traspaso del histórico |
| 2 | `supabase-migration-2026-09-inventory-v2-rpc.sql` | `stock_reservations` y las RPC: transferencia, ajuste, reserva, y el reemplazo de `gama_receive_purchase` y `gama_register_stock_movement` |
| 3 | `supabase-migration-2026-09-inventory-v2-counts.sql` | `inventory_counts`, `inventory_count_lines`, `reorder_rules` y las RPC de recuento |

El orden importa: la 2 crea funciones que referencian tablas de la 1, y la 3
llama a `gama_stock_adjust`, que crea la 2.

**Antes de la 1**, conviene dejar constancia de la foto de partida, porque es
contra ella contra la que se comprueba que el traspaso no perdió nada:

```sql
select count(*) filter (where coalesce(stock,0) <> 0) as con_stock,
       coalesce(sum(stock),0) as total
  from products;
```

**Después de la 1**, esas dos cifras tienen que aparecer intactas del otro
lado. Cero filas en esta consulta es la condición de que todo cuadre, y sigue
siendo cierta después de cualquier operación posterior:

```sql
select p.id, p.stock, coalesce(sum(q.quantity),0) as quants
  from products p
  left join stock_quants q on q.product_id = p.id
 group by p.id, p.stock
having coalesce(sum(q.quantity),0) <> coalesce(p.stock,0);
```

Cada migración lleva sus propias comprobaciones de sólo lectura al final del
fichero.

### Mientras tanto

El frontend no espera a nada de esto. Con las migraciones sin aplicar,
«Almacenes y existencias» avisa de que la migración no está aplicada y el
resto de la aplicación —Inventario, Compras, Ventas— funciona exactamente
igual que antes. Ése es el criterio con el que está escrito todo el código de
estas siete fases, y lo que fijan las pruebas: ninguna pantalla existente
puede empeorar porque falte una tabla nueva.

### Lo que las pruebas no demuestran

El doble de `tests/mock-gama-cloud.js` reproduce las restricciones de
Postgres —los `check` de `stock_quants`, los roles, el invariante
`SUM(quants) = products.stock`— pero es de un solo hilo: **no puede demostrar
la concurrencia**. Que dos traslados simultáneos no se pisen, y que dos
recepciones a la vez no dupliquen un quant, depende de los `select … for
update` y de los índices únicos, y sólo se comprueba contra un Postgres de
verdad. La comprobación, una vez aplicadas las migraciones, es lanzar dos
transferencias cruzadas A→B y B→A del mismo producto en dos sesiones y
verificar que ninguna queda bloqueada y que el invariante de arriba sigue
dando cero filas.

### Comprobación previa contra la base de producción (11-09-2026)

Hecha en sólo lectura, antes de aplicar nada. Ninguna de las tablas de
Inventario V2 existe todavía, así que las tres migraciones están pendientes y
el punto de partida es éste:

| | |
|---|---|
| Productos | 49 |
| Con stock distinto de cero | 9 |
| Stock total | 1143 |
| Stock negativo | **0** |
| Stock nulo o fraccionario | 0 |
| Movimientos en el histórico | 13 |
| Órdenes de compra abiertas | 0 |

Que no haya **ni un solo stock negativo** es la condición que hacía falta
comprobar antes de nada: `stock_quants` lleva un `check (quantity >= 0)`, así
que un stock negativo habría hecho fallar el traspaso del histórico entero. No
lo hay, y el traspaso creará exactamente 9 quants.

**Lo que va a salir de `products.location`.** Hay 49 valores distintos, uno por
producto: casi todos con forma de zona y hueco (`Z01-A01` … `Z06-A02`), más
`A10`, `A10-12`, `A10-49`, `A10-83`, `A-387` y uno literalmente llamado `Nan`
—resto de una importación de Excel, con 1 unidad de stock—. La migración crea
una ubicación por cada valor distinto, así que creará también la llamada
`Nan`. Es deliberado: la instrucción es no perder datos, y decidir por cuenta
propia que un valor de la ficha de un producto es basura sería justamente
perderlos. Renombrarla o fusionarla se hace después, desde la pestaña de
Ubicaciones, sabiendo qué producto había detrás.

**Sobre el reabastecimiento.** 41 de los 49 productos están por debajo de su
mínimo, y **sólo 1 tiene máximo**. Es decir que el caso normal en esta base no
es el de manual —«repón hasta el máximo»— sino el otro: sin máximo, la
sugerencia sube hasta el mínimo y la fila lo dice con un «hasta el mínimo».
Inventarse un techo habría sido pedir de más con cara de dato. Como ése es el
caso que manda en la base real, tiene su propia prueba en
`inventory-count.spec.js`.
