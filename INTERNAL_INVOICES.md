# Internal invoices from accepted quotes

Commercial/admin users open an accepted quote and choose Crear / ver factura interna. The database locks the quote and order, validates acceptance and unchanged amounts, and creates one active FI-YYYY-NNNNNNNN document for the complete order. Retries return the same document. Existing active external/partial invoices block conversion to prevent duplicate billing. No stock movement, new order or reservation is generated.

The shared financial ledger (external_invoices, document_kind=internal) stores immutable quote/customer/line snapshots and the internal invoice date/due date. The original accepted quote stays intact. PDF and copyable text use this snapshot, including original prices/discounts and net prices. The PDF says Factura interna de gestión. Sin validez fiscal. No es un comprobante SRI.

External entry is manual: copy data into the external software, then attach its reference to the same internal record. Receiver identification, subtotal and tax must match; external identity is unique across internal-linked and traditional external documents. Internal number/date/amount, payments and delivery links are preserved. External fiscal status is separate from the internal financial lifecycle; it never implies fiscal emission by GAMA.

Both dashboards, sales analysis, overdue alerts, unbilled quantities and collection balances use this single ledger. Quotes alone no longer count as revenue in the old dashboard. Revenue totals include VAT, while product margin analysis remains an estimate using current purchase costs. Invoice dates drive invoicing KPIs; confirmed payment dates drive collections.

Internal cancellation preserves history and removes its amount from active financial totals; confirmed payments must first be cancelled through the existing audited correction workflow. It does not cancel an external fiscal document or change inventory.

Validation: SQL rollback fixture covers acceptance, idempotency, snapshot lines, financial KPIs, partial payment, reference linking without double count, mismatched amounts, paid-invoice cancellation and warehouse denial. Browser tests cover conversion, copy/PDF, external reference, access boundaries and legacy dashboard source/period alignment. Shared quote/sales/operations/PDF regression suites also run.
