> État relu le 30 septembre 2026. Factures et encaissements est un onglet de Ventes ; son identifiant technique payments et ses contrôles d’accès restent distincts.

# Pagos de clientes

The `payments` module uses `external_invoices` and the existing append-only
`external_invoice_payments` ledger. Internal invoices and their optional external
reference are counted once. Access is restricted to active administrators and
commercial staff through the private checked RPC and existing customer RLS.

## Deadlines

- Set `customers.payment_terms_days` in the customer record (0 means payment on
  delivery). Existing clients start without a term; the UI requests configuration.
- `external_invoices.payment_delivery_date` is the date of the last actual signed
  delivery, in `America/Guayaquil`. Internal invoices cover the whole order;
  historical external invoices use their explicitly linked shipments. All relevant
  deliveries need a completion status, actual timestamp and signature.
- Due date = actual delivery date + calendar days. Planned delivery and invoice
  issue dates never substitute for actual delivery. A late-issued invoice can
  already be overdue.
- Changing customer terms updates outstanding invoices; fully paid invoices retain
  their stored term. Changing a linked delivery or proof refreshes the deadline.
- Dates, status and balances are calculated in the database. Missing terms or
  incomplete deliveries never produce a fabricated deadline.

## Alerts, reminders and closure

- At due date minus 7 days through the due date: orange `due_soon_invoice` alert.
  Starting the following day: the existing red `overdue_invoice` alert.
- These are live notifications: opening/refreshing Notifications computes their
  current state, and visible screens refresh every minute. No daily batch job is
  needed. Confirmed payments reduce balances, complete payment clears the alert,
  and cancelling a payment can reopen it. Cancelled/rejected invoices are excluded.
- Both notifications open the exact payment dossier and offer an editable email
  reminder. Recipient, dates and outstanding balance are refreshed from the server
  before composing. The user sends through the existing Gmail/Outlook/mail-app
  composer; preparing a message is never recorded as delivery of an email.
- The final dossier step is payment and closure. Full signed delivery, per-line
  invoice coverage and zero balance on each active invoice are all required.
  Closure is derived from the linked records and reopens after a payment reversal.

## Verification

- `tests/payments.spec.js`: UI, partial/cancelled payments, customer term editing,
  reminders, notification links, mobile layout, localization and role boundaries.
- `tests/dossier-flow.spec.js`: per-line billing coverage, signed deliveries,
  partial/reversed payments and dossier closure.
- `tests/sql/payment-tracking.sql`: run inside a rollback-only transaction. Covers
  J−8/J−7/due date/overdue boundaries, actual delivery dates, idempotency,
  overpayment prevention, payment reversal, customer terms and RPC permissions.
- Existing automatic-delivery-invoice and legacy-delivery-invoice SQL regressions
  are also checked with the new migration inside rollback-only transactions.

## Balance y crédito Ecuador

`gama_customer_aging` calcula los vencimientos pendientes a partir de la cartera
canónica: cobros, retenciones, créditos y ajustes. Pagos y Contactos abren el
balance por cliente (sin vencer, 0–30, 31–60, 61–90, más de 90 días y sin fecha).
Una cuota que vence hoy todavía no está vencida. El estado de cuenta exportable
incluye las referencias ERP y prepara una relance editable por correo o WhatsApp
con PDF. Preparar o descargar no envía ningún mensaje ni registra un envío.

`gama_customer_credit_status` muestra facturas pendientes y pedidos confirmados
sin facturar. Cualquier cuota vencida, retención explícita del crédito o exceso
del límite bloquea la confirmación, incluso sin límite configurado. La excepción
exige administrador, permiso de validación, motivo y huella de la deuda y del
pedido; caduca al cambiar los importes, las líneas o el día. Modificar líneas de
un pedido confirmado aplica el mismo control. Los bloqueos y cambios de deuda
se serializan sobre el cliente.

Las ventas consultan `gama_sales_invoice_balances` por lotes de 100 facturas para
mostrar el mismo saldo que contabilidad. `gama-collections.js` y los generadores
PDF se cargan únicamente al abrir estas acciones.

Al crear o cambiar una identificación ecuatoriana se comprueba la cédula/RUC de
persona natural y se bloquea el duplicado normalizado en el directorio. El tipo
de identificación permite documentos extranjeros y RUC asignados de sociedades,
organismos públicos y extranjeros; estos últimos no reciben un algoritmo de
control que el SRI no publica. Los registros históricos sin cambios de identidad
siguen siendo editables. La validación formal no sustituye una consulta al SRI.

Prueba: `tests/ec-credit-identity-db.test.cjs` restaura el esquema completo y
comprueba vencimientos parciales, retenes, aprobaciones, cambios de líneas,
duplicados y acceso denegado.
