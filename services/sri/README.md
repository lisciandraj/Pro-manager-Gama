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

Only standard domestic invoices with ordinary VAT and identification are
supported. Specialized tax regimes and credit/debit notes need dedicated XML
models and tests. SRI outages may leave documents in `processing`; consult
authorization by the same access key before any further transmission.

## Open API provider

Set `SRI_PROVIDER=openapi` to use the external NestJS fiscal engine through the
private gateway instead of the original Python signer. Read [OPENAPI.md](OPENAPI.md)
for the pinned contract, deployment prerequisites, scoped credentials, supported
invoice types, PDF renderer license caveat and no-reissue recovery policy.
