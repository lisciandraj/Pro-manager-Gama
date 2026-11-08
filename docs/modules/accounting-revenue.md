# Cifra de negocio y libro mayor

`gama_accounting_action('report_revenue', {from, to})` conserva los tres resultados históricos `by_month`, `by_customer` y `by_product`, con filas `{key, amount}`. Las fechas predeterminadas y los permisos siguen siendo los del módulo contable; clientes y productos conservan el límite de veinte resultados.

Los importes proceden de los movimientos contabilizados de cuentas de ingresos. Los asientos originales y sus contrapartidas se incluyen en su propia fecha contable, aunque el documento comercial esté anulado después. Los borradores no generan ventas. Los anticipos registrados en pasivo no se confunden con ingresos.

Las líneas y cuentas fijadas de las facturas, abonos y devoluciones determinan las dimensiones. Cada importe real del mayor se reparte con redondeo acumulado al centavo; no se vuelve a multiplicar el precio unitario. Las compensaciones del descuento por pronto pago registradas como gasto no reducen nuevamente los ingresos. Un reembolso que sólo mueve banco y cuenta del cliente no crea otro abono de venta.

Los planes individuales y agrupados conservan el vínculo con la factura, cuenta y línea de origen. En lectura contable completa, los ingresos sin dimensión comercial fiable aparecen como `—`. La lectura comercial recibe las dimensiones de ventas autorizadas y no incorpora movimientos manuales ajenos a ese alcance.

La migración `20261108174251_revenue_ledger_credit_projection.sql` sólo modifica lecturas. No reescribe documentos, importes, cuentas, asientos ni historial. `tests/revenue-ledger-projection-db.test.cjs` compara la API con movimientos reales del mayor en una única base aislada.
