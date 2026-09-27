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

Only standard domestic invoices with ordinary VAT and identification are
supported. Specialized tax regimes and credit/debit notes need dedicated XML
models and tests. SRI outages may leave documents in `processing`; consult
authorization by the same access key before any further transmission.
