# Open API Facturación SRI — Coco connector

This is a real HTTP adapter, not a copy of Odoo or a replacement financial ledger.
`openapi-upstream.json` pins the reviewed API contract. The upstream application
is MIT-licensed; it is not bundled into Coco. Deployment dependencies, including
the PDF renderer, need their own license/security review.

## Scope and data ownership

Coco's existing `gama_sri_prepare` function creates the immutable snapshot of an
accepted internal invoice: customer identity, legal company identity, net line
prices, tax and total. It reserves the fiscal series once. The connector handles
ordinary domestic invoice `01` only. Credit/debit notes, withholding, delivery
notes, RIMPE, ICE, exports and other regimes are NOT implemented in this adapter.
A supplier purchase is never converted into a customer invoice.

`gama-sri` checks the authenticated active administrator, accounting action
permissions and row visibility. Only then can it reach this private gateway.
All existing tables and policies are preserved; **no schema migration is needed**.
The server-write-only `sri_invoice_issues.receipt.provider` field records the
chosen provider when the draft is claimed. Switching the deployment default
does not change the backend of an already submitted document.

Only the verified fiscal reference is linked back to `external_invoices`.
No new sales, payments, inventory movements or accounting entries are generated.
The interface links the same invoice to its payment screen and process dossier.
The old Accounting → SRI tab remains compatible. The dedicated `sri` menu entry
loads the same finance renderer lazily; server authorization still uses the
existing `accounting` permissions. Hiding a tile is not an authorization control.

## Deployment (not performed by a static-site build)

1. Deploy the upstream source at revision
   `b41a7c79ba3fb2f0977efd3065bc126e1d9651ac` on a private application host.
   Do not deploy an unpinned `latest` container. Provision its isolated database,
   Redis, certificate storage, encryption secrets and PDF templates/renderer.
   Remove/change seeded example accounts and use a dedicated account restricted
   to the company's tenant/RUC, not a shared superadministrator account.
2. On upstream, set `SRI_EMISION_ASYNC=false` and, defensively,
   `QUEUE_SRI_ATTEMPTS=1`. Ensure the SOAP reception/authorization endpoints and
   `SRI_ENVIRONMENT` actually target **pruebas**. The DTO's `ambiente` alone does
   not choose the deployed SOAP endpoints. Assign a fiscal emission point that
   no other client uses; the upstream automatic counter must not compete with
   Coco's reserved sequence.
3. Upstream's example compose uses `carbone/carbone-ee:latest` for RIDE rendering.
   Do not equate that image with the MIT license of the application. Provision
   an appropriately licensed, pinned renderer and the `ride` template, or audit
   and implement a replacement before fiscal acceptance. This connector refuses
   to mark the Coco document authorized if a valid PDF cannot be archived.
4. Deploy the existing Python gateway using `services/sri/requirements.txt` in
   an isolated environment. Copy `openapi.env.example` to a server-only secret
   file. Set the real issuer RUC, scoped Open API credentials, HTTPS URL and
   the legally correct `SRI_OPENAPI_ACCOUNTING=SI` or `NO`. Set
   `SRI_OPENAPI_SYNC_CONFIRMED=true` only after step 2. A gateway instance remains
   intentionally **single-company**; use an isolated instance per issuer.
5. Run `uvicorn services.sri.api:app --host 127.0.0.1 --port 8000` behind HTTPS.
   Restrict ingress to the Edge gateway and expose no debug interface. Set the
   matching `SRI_WORKER_URL`, `SRI_WORKER_SECRET`, `SRI_PROVIDER=openapi` on
   Supabase, then deploy `gama-sri` with JWT verification enabled.
   Keep `SRI_EMISSION_ENABLED=false` initially. Never put these secrets in a
   frontend configuration, an invoice snapshot, a public bucket or GitHub.
6. In Coco, open **Facturación SRI** → **Configuración SRI**. Confirm company
   identity, establishment, emission point and software provider RUC. Prepare an
   internal invoice and review the frozen amounts. Enable
   `SRI_EMISSION_ENABLED=true` only for supervised tests. The worker performs a
   non-emitting preview before claiming the invoice and sending it once.
7. Validate real signatures, official XSD, SRI responses, rejection cases, RIDE,
   decimal rounding, document retention and customer email. Production requires
   explicit `SRI_PRODUCTION_ENABLED=true` on the private gateway **and** a
   correctly configured production upstream, matching environment and Coco
   settings. No live SRI test/certification is implied by the automated tests.

## Actual endpoints used

| Purpose | Upstream route |
| --- | --- |
| Scoped authentication | `POST /auth/login` |
| Non-emitting preflight | `POST /sri/preview/factura` |
| Single emission | `POST /sri/emitir/factura` |
| Reconcile reserved fiscal series | `GET /sri/comprobantes` |
| Consult SRI authorization | `GET /sri/autorizar/:claveAcceso` |
| Verify stored document state | `GET /sri/comprobantes/:claveAcceso` |
| Retrieve RIDE | `GET /sri/comprobantes/:claveAcceso/ride` |

These routes come from the pinned controllers, not older README examples.
The connector does **not** call reissue, cancellation, or synchronization routes.

## Recovery and known upstream limitations

Upstream does not expose a durable idempotency key. Its synchronous path can
contact the SRI before persisting the document. A crash in that interval cannot
be made safe by retrying `POST /emitir/factura`. Therefore Coco claims the issue
atomically **before** that request and keeps it `processing` after any uncertain
response. Its `retry` action refuses all Open API claims, even without an access
key. Do not reset such records to draft manually.

Use **Consultar SRI**. With a key, only that key is queried. Without a key, the
connector scans a bounded set of records filtered by RUC, date and emission
point and matches the exact sequence, environment, buyer and total. Multiple
matches or incomplete pagination stop with an explicit reconciliation error.
No match is **not** proof of non-emission: operator review is required, and the
connector never creates a new key to recover automatically. A returned `EN_COLA`
means the deployment violates the synchronous contract and also requires review.

The 49-digit key's checksum, date, issuer, document type, environment and fiscal
series are checked in Python and again in Edge. Only the upstream's eight random
digits may differ from the initial Coco snapshot. The authorization lookup must
return `AUTORIZADO`, the same authorization/key and a timestamp with timezone.
The signed invoice XML must match the frozen identity, amounts and all line
quantities/prices/taxes; XML entities and duplicate fields are rejected. This is
structural binding, not an independent cryptographic XAdES verification.

A pending upstream local record cannot supply a final RIDE even when the SRI
already authorized it. The UI then stays pending with
`AUTHORIZED_ARCHIVE_PENDING`; resolve the upstream local record without
re-emission. Private XML and PDF are archived before the invoice is marked
`authorized`. PDF filenames are content-addressed to support partial-upload
recovery when the renderer changes its creation timestamp. Original authorized
XML remains immutable. Signed download URLs expire after 60 seconds.

The emission kill switch does not prevent authorization lookups. Email remains
an explicit separate action using the gateway's SMTP configuration. As with the
legacy worker, a mail timeout needs provider review before a second send.

## Tests

```sh
python3 -m unittest discover -s tests -p 'test_sri*.py' -v
node --test tests/sri-openapi-edge.test.cjs tests/sri-deployment-db.test.cjs
npx playwright test tests/sri-integration.spec.js tests/accounting.spec.js tests/internal-invoices.spec.js tests/payments.spec.js
npm run build
npm run validate
```

The HTTP/Edge tests use synthetic responses and structural XML fixtures, not
real certificates or SRI authorizations. Browser tests intercept the database;
no fixture writes are permitted against production.
