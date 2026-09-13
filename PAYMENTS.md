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
