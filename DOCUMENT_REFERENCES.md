# GAMA — Referencias de documento

Producción: `lisciandraj/Pro-manager-Gama`, proyecto `mknsaibrewksgomuslev`.

Una venta deja un rastro de documentos —solicitud, presupuesto, pedido,
preparación, paquete, expedición, entrega, prueba, factura, cobro, devolución—
y todos comparten **un solo número de expediente**. Por eso `SOL-00001246` y
`PED-00000001246` no existen a la vez: si el pedido nace de esa solicitud, el
pedido es `PED-00001246`. El prefijo dice qué es el documento, el número dice
de qué venta habla.

| Prefijo | Documento |
|---|---|
| `SOL` | Solicitud de cliente |
| `COT` | Presupuesto |
| `PED` | Pedido de venta |
| `PREP` · `PAQ` | Preparación y paquete |
| `ENV` · `ENT` · `PDE` | Expedición, entrega y prueba de entrega |
| `FAC` · `COB` | Factura y cobro |
| `DEV` | Devolución |

Cuando un expediente tiene dos documentos del mismo tipo —dos facturas de un
pedido, por ejemplo— el segundo lleva una letra: `FAC-B-00001246`.

## Procesos: PDV y PDC

El número del expediente es el del proceso. En «Seguimiento de procesos» la
venta se muestra como `PDV-00001246` y la compra como `PDC-00001330`: el
acrónimo del proceso y el número que llevan todos sus documentos.

Desde septiembre de 2026 la compra entra en el mismo registro. El pedido de
compra abre su expediente; la factura del proveedor entra en el de su pedido
y el pago en el de su factura: `OCO-`, `FPR-` y `PPR-00001330`. Una factura de
proveedor sin pedido no es un proceso de compra y conserva su contador propio.
Los diez pedidos anteriores recibieron un expediente (1328–1337) sin cambiar
su referencia `OCO-0000000x`; el número único vale para los procesos nuevos.

El pedido de compra guarda también su origen, el paso 1 del proceso:
`manual` (módulo Compras), `low_stock` (alerta de stock bajo el mínimo) o
`sales_order` (pedido de cliente que supera el stock, con `source_order_id`).

Si un proceso tiene dos documentos del mismo tipo —dos facturas, dos
movimientos—, el primero lleva el número del proceso y el siguiente el próximo
libre de su tipo: `erp_issued_references` no admite dos veces el mismo número
para un mismo tipo. El número del proceso encabeza siempre la ficha.

## Cómo se asigna

`private.gama_register_document` lo hace, desde un disparador
`AFTER INSERT OR UPDATE` en cada tabla de la cadena. Su regla es **mirar antes
de pedir**:

1. Busca si el documento, o alguno de los documentos con los que enlaza, ya
   tiene expediente.
2. Si lo hay, se queda con el más bajo y los demás se fusionan en él: así una
   cadena que se descubre en dos trozos acaba con un solo número.
3. **Sólo si no hay ninguno** pide un número nuevo a
   `private.gama_dossier_sequence`.
4. Vuelve a numerar los ordinales y reescribe las referencias del expediente.

Un `pg_advisory_xact_lock` serializa el conjunto: dos documentos creados a la
vez no pueden abrir dos expedientes para la misma venta.

## El hueco que hubo, y por qué

Las referencias saltaban: de `SOL-00001196` a `SOL-00001244`, y antes de 609 a
1055. Treinta y un expedientes reales, y la secuencia por 1367.

La causa estaba en una línea:

    insert into gama_document_references(...,dossier_number)
     values(t, id, nextval('private.gama_dossier_sequence'))
     on conflict do nothing;

`nextval()` se evalúa **antes** de comprobar el conflicto. Así que gastaba un
número aunque la fila ya existiera y no se insertara nada. Y como el disparador
es `AFTER INSERT OR UPDATE`, cada edición de cualquier documento de la cadena
quemaba uno, más otro por cada enlace del bucle: una solicitud editada cinco
veces con dos enlaces se llevaba quince números por delante.

El segundo goteo era el bucle de enlaces: a un documento enlazado todavía sin
registrar se le abría expediente propio para fusionarlo acto seguido. Ahora
entra directamente en el expediente de destino.

Con el arreglo, una solicitud nueva avanza exactamente **+1**, editarla no
gasta nada, y un pedido nacido de ella entra en su mismo expediente sin
consumir. La secuencia se devolvió al último expediente realmente usado.

Las referencias ya emitidas **no se tocaron**: quien tiene `SOL-00001196` lo
sigue teniendo. Los huecos del pasado se quedan donde están; lo que no vuelve a
crecer es la distancia.

## Lo que sigue pudiendo dejar un hueco

Una secuencia de Postgres no es transaccional: si una transacción pide un
número y luego se deshace, ese número no vuelve. Es raro en uso normal —hace
falta que la creación falle después de registrar el documento— y es el precio
de no serializar todas las ventas contra una tabla de contadores. El goteo
sistemático, que era lo que disparaba la numeración, ya no existe.

## Ficheros

    supabase/migrations/20260918120000_dossier_number_no_gaps.sql   el arreglo
    tests/sql/document-references.sql                              la prueba
