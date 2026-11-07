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

Set `SRI_SUPABASE_URL`, the **public** `SRI_SUPABASE_PUBLISHABLE_KEY` and a
separate random 256-bit hex `SRI_RECONCILE_TOKEN` privately in this worker.
Install the same token as an Edge secret. The worker never needs the global
`service_role` key. The FastAPI lifespan consults one oldest pending document
per interval (`SRI_RECONCILE_INTERVAL`, 60–3600 seconds). The Edge handler validates
the capability and accepts **only** `refresh_pending`; it cannot emit, reset,
notify or download documents. It works with `SRI_EMISSION_ENABLED=false`.
No browser session is required. If the dedicated credentials are absent, this
loop stays disabled; the document screen can still consult visible pending
records while open.

Roll out the Edge capability and private worker together. The Edge gateway must
allow the request through (`verify_jwt=false` for `gama-sri`); the handler still
verifies every human bearer with Auth and every machine capability itself.
For a strictly temporary transition of an already-running legacy worker, the
Edge may be given an explicit future `SRI_LEGACY_RECONCILE_UNTIL` ISO timestamp.
When the dedicated token is provisioned, no timestamp means no legacy service-key machine access. Before provisioning it, the old Edge scheduler route remains compatible so a code update alone does not interrupt reconciliation. Remove the old key from
the private host and rotate it after the switch; never use this grace as the
steady-state configuration. Rotation of the dedicated token is coordinated on
both sides and does not change database keys.

The worker must be deployed separately from GitHub Pages. A passing XML/schema/PDF fixture is not SRI certification or proof of successful production signing.

## Open API provider

Set `SRI_PROVIDER=openapi` to use the external NestJS fiscal engine through the
private gateway instead of the original Python signer. Read [OPENAPI.md](OPENAPI.md)
for the pinned contract, deployment prerequisites, scoped credentials, supported
invoice types, PDF renderer license caveat and no-reissue recovery policy.

### Retenciones recibidas

La función `gama-sri-received` usa el mismo trabajador HTTPS/HMAC para verificar XML 07 recibidos. `received_inspect` consulta la autorización real y devuelve los documentos sustentados; `verify_received_batch` compara esos documentos con las facturas obtenidas por RPC, verifica RUC, fechas, bases y porcentajes, y conserva el XML que devolvió el SRI. El navegador no puede suministrar una prueba ni escribir el archivo verificado. Las aplicaciones contables se realizan en lote con `gama_ec_received_batch`; cualquier error revierte todos los offsets y no mueve la caja. La conectividad SRI es necesaria incluso si el archivo cargado incluye una envoltura AUTORIZADO.
