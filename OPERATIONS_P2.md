# P2 — Notificaciones y control comercial / logístico

## Acceso

Menú Resumen → **Notificaciones** o **Control comercial y logístico**.
El Panel de control existente también enlaza al nuevo panel. Administrador y
comercial ven las cifras comerciales; el almacenero ve los indicadores logísticos.
Los clientes no tienen acceso al RPC ni a estas pantallas. Los permisos existentes
siguen protegiendo las acciones de cada dossier. Compras se habilita en el menú
para los roles comercial y almacenero que ya crean / reciben pedidos.

## Alertas

- Presupuestos enviados sin respuesta (prioridad mayor si vencieron).
- Pedidos confirmados con cantidades sin reserva.
- Recepciones previstas antes de hoy y cantidades todavía pendientes.
- Entregas con Excepción, o con fecha pasada sin entrega ni cancelación.
- Pedidos parcialmente expedidos con reliquat.
- Recuentos físicos no validados con cantidades contadas distintas de las esperadas.
- Cantidades de pedidos confirmados sin factura externa vinculada.

Cada alerta abre el dossier exacto, incluidas compras, recuentos y entregas fuera
de las listas iniciales o del día. Para el comercial, una alerta de entrega abre
el pedido relacionado; las entregas TMS independientes corresponden al almacén.
Se puede tomar la alerta, guardar una nota, posponer 24 horas o reactivarla.
La toma asigna al usuario actual y cada cambio se registra en un historial privado.
No se puede cerrar manualmente un bloqueo que sigue existiendo. Las alertas son
calculadas y desaparecen al resolverse la causa; si cambia su contenido, la alerta
vuelve a estar abierta y se rechazan las modificaciones de una versión antigua.
Se muestran 50 resultados por página, con totales calculados en la base completa.
El contador y las listas se actualizan cada minuto mientras la aplicación está
visible, al recuperar el foco o mediante Actualizar. Son notificaciones dentro de
GAMA, sin envío automático de correos ni push del sistema operativo.

## Indicadores

La actividad del periodo usa las fechas de Ecuador (America/Guayaquil):
- pedidos actualmente confirmados, por fecha de creación;
- expediciones, por fecha de despacho y salida de stock;
- entregas completadas, por fecha real (incluye TMS independiente);
- facturas externas, por fecha de emisión, excluidas rechazadas/anuladas;
- cobros confirmados, por fecha del pago, excluidos pagos anulados y facturas cerradas.

La situación actual incluye todos los periodos: bloqueos, reliquats, atrasos,
recuentos con diferencias, pendiente de facturar, expedido sin factura y saldo
por cobrar. Los importes de venta incluyen IVA y están en USD.

El pendiente de facturar se calcula por línea: cantidad pedida menos cantidad
vinculada a facturas vigentes, multiplicada por precio e IVA. El expedido sin
factura limita esa base a lo expedido. Los registros por verificar también
apartan cantidades para evitar duplicados. Un cobro no modifica lo facturado.
Los abonos externos de retornos no son asientos de cobro: no se descuentan
automáticamente y se consultan en el dossier. Los recuentos validados dejan de
ser diferencias pendientes. La expedición parcial no equivale a una entrega.

## Verificación

`tests/sql/operations-p2.sql` se ejecuta con la migración dentro de BEGIN/ROLLBACK:
alertas, cantidades expuestas, IVA, fechas, cobros, toma, reporte, causa modificada,
resolución automática y restricciones de acceso. No deja datos de prueba.
`tests/operations.spec.js` verifica navegación, filtros, toma, errores, móvil,
ausencia de acceso cliente y accesos directos fuera de las listas del día.
