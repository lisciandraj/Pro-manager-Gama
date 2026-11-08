# Pronto pago y escompte

Las facturas de clientes y proveedores pueden ofrecer un porcentaje si el pago real completo llega antes del plazo, contado desde la emisión. La factura directa permite elegir las condiciones antes de contabilizar; las cuentas por cobrar y pagar permiten configurar y pagar las condiciones de una factura emitida. Hace falta acceso contable a todos los registros; editar condiciones, pagar y anular respetan sus permisos separados.

Se conservan tres tratamientos fiscales, inspirados en la [documentación pública de Odoo 19](https://www.odoo.com/documentation/19.0/es_419/applications/finance/accounting/customer_invoices/cash_discounts.html), con código propio:

| Tratamiento | Factura: base 100 + IVA 21 %, descuento 2 % | Pago dentro de plazo | Crédito ganado |
| --- | ---: | ---: | ---: |
| Siempre al emitir | 120,58 | 118,58 | 2,00 sin IVA |
| Al pagar a tiempo | 121,00 | 118,58 | 2,00 + 0,42 IVA |
| Sin reducir impuestos | 121,00 | 119,00 | 2,00 sin IVA |

La reducción de impuesto al emitir se define al crear la factura: no se puede cambiar el impuesto de una factura emitida mediante esta opción. Fuera del plazo se paga el saldo completo. Los pagos parciales solo generan el crédito cuando la suma real confirmada alcanza exactamente el importe descontado, con todas sus fechas dentro de plazo. Otros créditos, retenciones y devoluciones impiden combinar automáticamente un segundo descuento.

El registro canónico `accounting_adjustments` conserva el crédito y su asiento; los pagos contienen únicamente el dinero recibido o enviado. Los saldos, exportaciones, informes y mayor usan esos mismos registros. Los modos banco directo, cuenta de espera y sin asiento conservan su tratamiento: en modo sin asiento el importe en efectivo sigue pendiente en contabilidad hasta la conciliación bancaria. La oferta y el crédito conservan eventos de historial con autor y procedencia, incluida la actividad de Agent Coco.

Las reglas, cuentas y componentes fiscales originales quedan congelados. Una modificación o archivo posterior del impuesto no cambia el escompte. Los impuestos fijos se conservan por cantidad; solo las bases porcentuales cambian, respetando impuestos compuestos y la política de redondeo original. Las facturas antiguas se reconstruyen únicamente si sus cantidades y tipos capturados reproducen exactamente los importes y la cuenta fiscal original; si no, se exige revisión contable.

Anular un pago que contribuyó al descuento revierte también el crédito dentro de la misma transacción. La conciliación bancaria debe deshacerse antes; los bloqueos de fechas y periodos siguen vigentes. No se permite anular el crédito de escompte independientemente de su pago. Una referencia contable no sustituye la autorización fiscal externa de un documento: el flujo fiscal existente conserva sus controles.

Implementación: `20261108163658_accounting_early_payment_discounts.sql`, `src/features/finance/early-discounts.js`. Pruebas: `tests/accounting-early-discounts-db.test.cjs` y `tests/accounting-early-discounts.spec.js`, con base desechable y RPC reales.
