# Presupuestos y entregas del cliente

Production: `lisciandraj/Pro-manager-Gama`, Supabase `mknsaibrewksgomuslev`.

## Usage

- **Ventas → Presupuestos**: create or review a quote. The existing records remain in `invoices`/`invoice_lines`; the previous form and archive are still accessible from the landing page.
- Edit the customer record link, displayed customer and seller details, number, dates, address, payment/delivery conditions, descriptions, product replacements, quantities, list prices, discounts and per-line taxes. Save a draft, review its PDF, then **Enviar al cliente en la aplicación**.
- The client sees sent quotes belonging to their customer record and explicitly accepts their terms. Admin/commercial can record acceptance by email, phone, in person or other channel; the agreement reference is required and recorded with actor, date and revision. “Preparar correo” opens the existing mail composition flow; it does not send email automatically.
- Acceptance atomically records the approval, creates a confirmed sales order, and allocates available stock using the existing FIFO allocator. Physical stock changes only at dispatch. The detail distinguishes ordered, reserved, shipped and outstanding quantities. Future purchase receipts continue to allocate outstanding stock.
- Sent/rejected quotes must be reopened before editing. Reopening withdraws the sent version and increments its revision; a stale client acceptance fails. Accepted quotes remain immutable; cancellation of the sales order uses the existing checked sales workflow.
- **Ventas → Mis entregas**: clients see only deliveries linked by `tms_deliveries.customer_id` to their customer record, including dispatch lines, status, date/address and available photos/signatures. Admin/commercial can inspect this projection too. Warehouse staff continue registering proofs in the existing TMS. Lists never fetch image contents; proofs load only when opened.

## Identity and access

The portal links the client's active customer record through their verified Supabase Auth email, matching the installation's existing customer-account model. The email in the quotation's editable display fields does not grant access. Deliveries require a real customer ID; an unlinked legacy delivery is not guessed from its name or address. Internal route details and other customers' stops are never exposed by the portal.

New writes use `gama_quote_action`; client read projections use `gama_client_deliveries` and `gama_quote_reservations`. Public functions are invoker wrappers around private, checked implementations. Direct edits to managed quote headers/lines are rejected. New tables have RLS with explicit read-only grants. The older sales conversion cannot bypass acceptance of a managed quotation. Creation retries use a request UUID; acceptance retries return the same order.

No legal electronic signature or SRI invoice issuance is introduced; acceptance is an authenticated, timestamped business approval. Fiscal invoices stay in the external software.

## Deployment and verification

Apply `supabase/migrations/20260912133221_client_quotes_delivery_portal.sql` before publishing the static frontend. It extends existing records without deleting or republishing previous quotes.

Browser checks: `tests/client-quotes.spec.js`, plus the existing sales, quote, PDF, price-list, archive, security and header tests. The legacy form tests enter through the new archive/form button. SQL checks: execute `tests/sql/client-quotes.sql`, `sales-flow.sql` and `commercial-chain.sql` within BEGIN/ROLLBACK. Fixtures (including Auth users) are rolled back; sequence numbers may advance.

The security advisor's pre-existing catalog/team definer views, legacy stock-function grants and leaked-password warning are unchanged by this feature. New portal functions have no anonymous execution grants.

For UI rollback, restore the previous frontend while retaining the additive schema and real approvals/orders/reservations. Do not delete business events or reverse stock allocations as a rollback shortcut.
