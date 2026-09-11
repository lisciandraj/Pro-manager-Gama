# Pedidos de venta y facturación externa

Entrada: **Ventas → Pedidos de venta**. El módulo contiene Pedidos, Expediciones,
Pendiente de facturar y Facturas externas. También hay un botón «Crear / ver
pedido» en cada presupuesto archivado y solicitud de cliente.

## Uso

1. Crear un pedido directo o convertir un presupuesto/solicitud. Se copian el
   cliente, dirección, productos, cantidades, precios e impuestos; un origen ya
   convertido abre su pedido existente. Los presupuestos siguen siendo documentos
   informativos en las tablas actuales, sin migrar ni emitir facturas fiscales.
2. Confirmar. Se reservan las existencias disponibles por ubicación, sin cambiar
   el stock físico. «Reservar pendientes» completa reservas tras una reposición.
3. El almacenero selecciona cantidades y ubicaciones reservadas en «Registrar
   expedición». Al validar, una sola transacción consume las reservas, registra
   movimientos de salida, sincroniza el stock y crea una entrega en el TMS.
   La recepción final por el cliente se sigue con los estados/pruebas del TMS.
4. El comercial registra la factura emitida en su otro software: emisor,
   receptor, número, fechas, clave de acceso opcional, importes y cantidades de
   cada línea. PDF/XML opcionales (5 MB cada uno, 2 por carga, 4 por factura).
   El registro fiscal y sus cambios de estado **no mueven existencias**.
5. «Actualizar estado declarado» registra una autorización/rechazo/cancelación
   comprobada en el software externo, con motivo obligatorio. No realiza ninguna
   consulta ni anulación ante el SRI. Los archivos se descargan bajo sesión.

## Límites explícitos de esta versión

- Una factura externa se vincula a un pedido; un pedido admite varias facturas
  y expediciones parciales. No se distribuye una factura entre varios pedidos.
- Cantidades con hasta 3 decimales para respetar el stock existente. Las líneas
  duplicadas del mismo producto en el origen se agrupan con precio ponderado;
  impuestos distintos para el mismo producto requieren corregir el origen.
- Los importes se contrastan con las líneas a precios del pedido, con tolerancia
  de 0,02 USD por subtotal/IVA para redondeos. Fletes u otros conceptos no presentes
  en el pedido no se aceptan silenciosamente.
- Los registros «por verificar» apartan cantidades para impedir doble vínculo,
  pero sólo «autorizada» cuenta como facturado autorizado. Rechazados/cancelados
  conservan su historial y dejan de apartar cantidades.
- La cancelación del pedido sólo se permite antes de expediciones y sin facturas
  vigentes. Un pedido ya expedido requiere un futuro flujo de devolución; cancelar
  en TMS o anular una factura no significa que haya regresado mercancía.
- Esta entrega no implementa cobros, notas de crédito, emisión SRI ni integración
  API con proveedores. El indicador de ventas del dashboard anterior conserva su
  comportamiento y no debe confundirse con este registro fiscal separado.
- El módulo reutiliza el modelo de una empresa de la instalación actual; no añade
  aislamiento multiempresa.

## Integridad y seguridad

Todas las mutaciones pasan por `public.gama_sales_action`, una función invoker que
llama al procedimiento privado con comprobación de `auth.uid()` y perfil activo.
El esquema privado contiene la implementación definer con `search_path` vacío.
No se concede ejecución a `anon`. Las nuevas tablas sólo tienen SELECT con RLS:
no pueden editarse directamente por PostgREST. El cliente externo no tiene acceso.

Administrador/comercial: crear/confirmar/cancelar pedidos, reservar y gestionar
facturas. Administrador/almacenero: expediciones. Almacenero: lectura logística y
reservas, sin lectura de tablas fiscales. Los permisos de menú no sustituyen RLS.

Se bloquean pedidos, reservas y productos en orden estable. Pedido y líneas se
crean en una transacción; expedir y vincular factura son idempotentes mediante
claves UUID. La unicidad del origen y de emisor/número/clave evita duplicados.
Archivos almacenados aparte y descargados sólo a petición: ninguna lista transfiere
su contenido. Historial append-only en `sales_events` con usuario y fecha.

## Instalación y pruebas

Migración aditiva: `supabase/migrations/20260911154806_gama_sales_orders_external_invoices.sql`.
Aplicar una vez, antes del frontend. Usa los helpers y tablas de Inventario V2
ya existentes en producción. No reconstruir ni borrar el esquema actual.

`tests/sql/sales-flow.sql` se ejecuta dentro de BEGIN/ROLLBACK, con un perfil admin
activo. Comprueba idempotencia, salida parcial, rollback ante error de una línea,
no doble descuento al facturar, límites de cantidad/importe/receptor, archivos,
conversión de presupuesto, RLS y denegación sin sesión. Los perfiles existentes
se usan sólo como identidad de prueba; no se cambian. No deja fixtures persistentes.

`tests/sales-orders.spec.js` comprueba el contrato de interfaz con el servicio:
menú, expedición, factura con XML, reintento tras error, permisos y formulario móvil.
Las reglas de stock se prueban contra PostgreSQL, no mediante una imitación JS.
El workflow validate-sales ejecuta los tests de interfaz en los cambios futuros.
