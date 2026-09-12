# Commercial transaction chain

Production target: `lisciandraj/Pro-manager-Gama`, Supabase `mknsaibrewksgomuslev`.

## Scope

- Reuse the existing checked sales-order reservation and partial-dispatch transactions.
- Show physical stock, order reservations, global availability and outstanding allocation.
- Calculate purchase suggestions from pending sales, all reservations and outstanding sent/partial purchases; no double counting or physical-stock fallback.
- Preserve opportunity and quotation foreign keys on orders; expose the quote-to-order action in CRM.
- Allocate purchase receipts to confirmed orders in creation-date/ID order, with reservation audit events.
- Link external invoices to one or more dispatches, atomically on creation or subsequently from the invoice card.
- Record partial payments with idempotency keys, invoice-row locking, strict balance checks and cancellation history.

## Deployment

Apply `supabase/migrations/20260912125649_commercial_transaction_chain.sql` once before publishing the frontend. The public RPC signatures remain compatible with existing clients. Invoice fiscal status remains a manual declaration; no SRI emission or accounting entries are introduced.

Sales transactions and purchase receipts acquire the same transaction-scoped advisory lock before their row locks. This deliberately serializes these operations for correctness in this small ERP; review throughput before scaling to high transaction volumes. Incoming purchase orders are suggestions' coverage, not dedicated allocations to particular sales orders.

## Verification

Run `npm ci` then `npm test -- --workers=4` (set `PLAYWRIGHT_CHROMIUM_PATH` when using a preinstalled browser). Browser tests use a mock backend and do not modify production business records.

Run `tests/sql/sales-flow.sql` and `tests/sql/commercial-chain.sql` inside `BEGIN; ... ROLLBACK;`. The latter covers stock shortages, incoming purchases, two partial receipts and FIFO allocation, cancellation release, non-sales reservations, partial dispatch, atomic invoice links, payment idempotency, partial/full payment, overpayment rejection, payment cancellation, direct-write restrictions and CRM origin linkage. Test fixtures are rolled back; PostgreSQL sequence numbers may advance.

The pre-deployment security advisor also reports pre-existing catalog/team definer views, legacy stock RPC grants and disabled leaked-password protection. This change does not broaden those APIs; new tables have RLS and read-only grants, with checked mutations through private implementations and public invoker wrappers.

## Recovery

If UI rollback is needed, restore the previous frontend release while retaining the additive database schema and all real payment/reservation history. Do not drop payment tables or reverse stock movements to roll back a deployment. Investigate and ship a forward migration for database defects.
