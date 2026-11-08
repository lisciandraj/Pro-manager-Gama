# Cobro de presupuestos y facturas a distancia

Los enlaces de un solo documento permiten solicitar un anticipo de presupuesto o el saldo actual de una factura. Conservan el PDF y su SHA-256, revisión, moneda, cliente y emisor. La firma y el porcentaje de anticipo se eligen al emitir el enlace. Cuando se exige anticipo, la firma sola no confirma el pedido: primero hace falta el cobro real verificado y después se ejecuta la aceptación comercial nativa, con sus controles de crédito, existencias y aprobación.

## Medios y configuración

Los dos medios están desactivados de forma predeterminada. Un administrador con permisos contables configura la cuenta y las instrucciones desde **Firma y pago a distancia → Configurar cobros**:

- **Stripe Checkout** abre el formulario alojado por Stripe. Las claves solo se guardan en secretos del servidor. La cuenta financiera elegida representa el saldo del procesador: conserva el cobro bruto; los abonos al banco y comisiones se concilian por las operaciones contables habituales.
- **Transferencia** muestra instrucciones facilitadas por el administrador. Comunicar una referencia no crea dinero. Un contable vincula un recibo canónico del mismo cliente, ya verificado por conciliación bancaria. Las declaraciones están limitadas por enlace y día.

Los nombres de variables están en `supabase/functions/coco-checkout-payments/.env.example`. `COCO_CHECKOUT_APP_ORIGIN` debe ser el origen exacto de la aplicación; `COCO_CHECKOUT_PUBLIC_URL` es la dirección completa de `coco-checkout.html`. El adaptador usa únicamente la [API pública de Checkout](https://docs.stripe.com/api/checkout/sessions/create), la [API de PaymentIntents](https://docs.stripe.com/api/payment_intents/retrieve) y los [webhooks firmados de Stripe](https://docs.stripe.com/webhooks/signature). El webhook usa la función `coco-checkout-payments?webhook=1` y los eventos `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, `checkout.session.expired`, `charge.refunded`, `charge.dispute.created` y `charge.dispute.closed`.

La implementación y sus pruebas no activan ningún proveedor ni escriben en producción. El usuario mantiene sus propias cuentas y claves. Las pruebas de transporte Stripe nunca crean recibos ni confirman pedidos; el modo real exige un intento fijado en un entorno asignado explícitamente a producción. El acceso público en desarrollo continúa bloqueado; la vista previa requiere un administrador autenticado y verificado por el servidor.

## Contabilidad y reservas

Un pago real verificado crea un único `customer_receipts` por la API canónica. Para una factura se aplica únicamente el importe todavía necesario; cualquier excedente queda como anticipo real. El escompte usa las condiciones vigentes y la fecha efectiva del dinero recibido: el pago contiene efectivo y el descuento ganado genera su crédito independiente. En un presupuesto, el recibo permanece como anticipo hasta que exista una factura vinculada.

El dinero reservado no puede financiar a la vez una tarjeta regalo, un monedero, otro presupuesto o una factura ajena. La disponibilidad usa el mismo cálculo que los fondos de valor almacenado. Una factura vinculada libera solo el importe aplicado. Un contable con permiso de validación puede liberar expresamente una reserva contabilizada, con motivo e historial; el dinero deja de cubrir el anticipo solicitado. La cancelación de un recibo reservado queda bloqueada.

Cada intento fija importe, moneda, revisión, reglas del escompte, modo real/prueba y cuenta. Solo puede existir un intento abierto por documento. Las sesiones cuyo importe o condiciones cambiaron se caducan en Stripe antes de preparar otra. Un intento sin sesión y caducado puede recuperarse; una sesión ligada necesita la confirmación de caducidad del proveedor. Si se recibe dinero mientras otra operación cambia el saldo, se aplica el saldo autorizado y se conserva el resto como anticipo, sin sobreasignación.

## Verificación y revisión

La firma HMAC se comprueba sobre los bytes originales, con caducidad de cinco minutos, antes de acceder a la función de máquina. Cada identificador de evento es único. Una disputa que llega antes del pago se resuelve mediante los metadatos del PaymentIntent en la API oficial; no se pierde por el orden de entrega. Se rechazan moneda, importe, sesión o modo incompatibles.

Los fondos de prueba, declaraciones del cliente y parámetros de retorno del navegador nunca se consideran cobros reales. El token del enlace no se envía a Stripe: el retorno usa el identificador del intento y la sesión temporal del mismo navegador. La página consulta los estados verificados del servidor.

Si los permisos del emisor o la contabilización nativa impiden registrar un cobro real, el evento se conserva para revisión y reintento autorizado. Si crédito, existencias o aprobación impiden confirmar un pedido, el recibo real permanece como anticipo y la aceptación sigue pendiente. Reembolsos y disputas del proveedor generan revisión contable bloqueante; no inventan automáticamente un abono comercial ni un movimiento de inventario. El contable utiliza el flujo canónico de abono/reembolso y verifica la correspondencia con el proveedor antes de resolver la incidencia.

## Validación

- `tests/checkout-payments-edge.test.mjs`: firmas, bytes, tiempos, cambios de importe, URL alojada, orden de eventos y ausencia del token en Stripe.
- `tests/checkout-payments-db.test.cjs`: recibos e intentos únicos, factura con escompte, permisos, modo de prueba sin dinero, revisión, reservas compartidas, conciliación, disputas y recuperación de sesiones.
- `tests/checkout-payments.spec.js`: RPC reales sobre base desechable, recorrido alojado simulado, retorno verificado, transferencia sin falso cobro, configuración y accesibilidad en varios idiomas y tamaños.
