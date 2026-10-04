# Coco SRI signer

Private HTTPS service. Configure `SRI_WORKER_SECRET`, `SRI_ISSUER_RUC`,
`SRI_P12_BASE64`, `SRI_P12_PASSWORD`, `SRI_SMTP_HOST`, `SRI_SMTP_PORT`,
`SRI_SMTP_USER`, `SRI_SMTP_PASSWORD`, and `SRI_SMTP_FROM` on the server.
Set `SRI_PRODUCTION_ENABLED=true` only after SRI certification tests and
schema/signature validation. Never upload the `.p12` through the browser.

Start with `uvicorn services.sri.api:app --host 127.0.0.1 --port 8000` behind
an HTTPS reverse proxy. The Supabase function sends an HMAC-authenticated JSON
request. A different company requires its own isolated signer deployment and
issuer RUC; this version is intentionally single-company.

In Supabase Edge secrets, configure `SRI_WORKER_URL` and the matching
`SRI_WORKER_SECRET`. Set `SRI_EMISSION_ENABLED=true` to enable supervised
test issuance after the signer is configured. The interface stays disabled
until this explicit gate is enabled; production has the separate signer gate
described above.

Ordinary domestic documents are supported through immutable ERP snapshots:

| Code | Document | Source | Private signer | Pinned Open API |
| --- | --- | --- | --- | --- |
| 01 | Factura | Internal invoice | Yes | Yes |
| 03 | Liquidación de compra | Posted supplier bill, cédula and reviewed product lines | Yes | No upstream endpoint; use the private certificate |
| 04 | Nota de crédito | Inspected customer return and authorized original invoice | Yes | Yes |
| 06 | Guía de remisión | Prepared TMS route, actual shipped goods, identified recipients and carrier | Yes | Yes, carrier must have a RUC for this upstream contract |
| 07 | Comprobante de retención v2 | Reviewed supplier bill, confirmed withholding-agent status and dated supplier policy | Yes | Yes |

The [bundled official schemas](schemas/README.md) are checked before signing. Rates come from reviewed supplier policies and dated accounting taxes, never from guessed defaults. Foreign purchases, dividends, reimbursements, ICE and special fiscal regimes need their own mapping and are rejected explicitly. The RIDE includes the ERP reference and legal fiscal number separately; only verified authorizations permit archive download.

The Edge Function atomically claims drafts, binds access keys to document type, issuer, date and series, and keeps private, immutable XML/PDF archives. A timeout leaves a claimed document pending: consultation uses the same access key or exact upstream source lookup, without a second emission. Draft route guides can be discarded before any claim so that the manager can adjust and regenerate a route; sent guides and their goods are immutable.

## Automatic consultation

Set `SRI_SUPABASE_URL` and `SRI_SUPABASE_SERVICE_ROLE_KEY` privately in this worker deployment. The FastAPI lifespan then consults one oldest pending document every 60 seconds (`SRI_RECONCILE_INTERVAL`, 60–3600 seconds), across all document types. `gama-sri` accepts this service credential only for `refresh_pending`; scheduled code cannot emit, reset, notify or download documents. This also works with `SRI_EMISSION_ENABLED=false`. No browser session is required. With no private scheduler credentials, this loop stays disabled and the document screen consults visible pending documents while open.

The worker must be deployed separately from GitHub Pages. A passing XML/schema/PDF fixture is not SRI certification or proof of successful production signing.

## Open API provider

Set `SRI_PROVIDER=openapi` to use the external NestJS fiscal engine through the
private gateway instead of the original Python signer. Read [OPENAPI.md](OPENAPI.md)
for the pinned contract, deployment prerequisites, scoped credentials, supported
invoice types, PDF renderer license caveat and no-reissue recovery policy.
