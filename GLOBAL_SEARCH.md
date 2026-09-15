# Global search

The main-menu search now opens Spotlight. Ctrl/Cmd+K opens it from any module;
the existing `/` shortcut still works on the main menu. Results use arrow keys,
Enter, Escape, or touch. The module grid remains visible behind the dialog.

## Scope

Authenticated, paginated searches cover customers, CRM contacts, suppliers,
products/barcodes/references, quotes, sales orders, shipments, deliveries,
internal/external invoices, payments, and Knowledge titles/content. Related
customer names are searchable on shipments, invoices, and payments. Matching
ignores case and accents; identifiers rank before partial matches. Canonical
dossier references and original document numbers both work. `CMD-293` resolves
to `PED-00000293`; invoice ordinal letters remain significant.

Simple entity records open a fresh read-only detail card. Documents open their
existing module, shipments open their related order, payments open the invoice
ledger, and Knowledge opens the selected article.

## Business phrases (French / Spanish / English)

| Example | Rule |
| --- | --- |
| commandes en retard / pedidos atrasados / late orders | Confirmed orders with an overdue promised line and quantity still to dispatch, or an overdue, unfinished linked delivery. Missing promised dates are not guessed. |
| factures impayées / facturas sin pagar / unpaid invoices | Existing `gama_payment_action` ledger, status `open`; includes partial balances and excludes cancelled invoices. |
| factures échues / facturas vencidas / overdue invoices | Ledger status `overdue`, using the canonical due date. |
| factures payées / facturas pagadas / paid invoices | Ledger status `paid`. |
| livraisons en retard / entregas atrasadas / late deliveries | Scheduled date before today in America/Guayaquil; excludes delivered/cancelled deliveries. |
| devis sans réponse / presupuestos sin respuesta / unanswered quotes | Sent, with a sent date more than seven days ago. |

A customer name can follow the phrase, e.g. `factures impayées de Juan Perez`.
The interpreted rule appears above the results. This is a deterministic intent
and synonym parser, not a general embedding/LLM search. Unknown expressions
remain literal searches. No OpenAI account, token credits, embeddings, or new
database migration is required.

## Data and permissions

- Reads run through the existing Supabase session and retain the original RLS.
- The server profile is fetched when opening search and again before opening a
  result. Module permissions and disabled modules also apply in the UI.
- Clients search only their catalogue, their RLS-scoped quotes, and the existing
  `gama_client_deliveries` portal. They never query the staff invoice/payment,
  customer directory, supplier, CRM, or Knowledge tables through this feature.
- Financial phrases use the existing server ledger, not locally estimated
  balances. Cancelled payments do not reduce the outstanding balance.
- Explicit column lists exclude photos, signatures, credentials, and private
  HR data. Result titles and content are escaped. No results or query history
  are stored in localStorage. Requests are cancelled and results cleared on
  sign-out, module changes, or a new query.
- Search uses quoted PostgREST filter values; user text cannot supply operators,
  columns, or wildcard expressions. The accent-tolerant candidate filter is
  followed by normalized matching to remove false positives.
- Results are paginated, with explicit buttons for additional candidate pages.
  Counts describe displayed results, not a purported exhaustive global total.
  Business phrases may need additional pages when a customer term narrows a
  larger ledger. A failed category is reported and can be retried.

## Validation

`node --test tests/global-search-core.test.cjs` checks intent parsing, negation,
reference aliases, server-profile restrictions, outstanding balances, overdue
quantities, filter quoting, and pagination.

`npx playwright test tests/global-search.spec.js` checks desktop/mobile, keyboard
navigation, record previews, document links, Knowledge selection, client and
warehouse scopes, cancellation, error states, escaping and language changes.
These tests use fixture data, not writes to production business records.

The Supabase management connector and direct API network path were unavailable
during implementation. Existing checked-in schema, RLS and RPC definitions were
used; live authenticated searches were not exercised from this workspace.
