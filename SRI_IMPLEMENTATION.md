# Facturación SRI — integration status

The Accounting module now has a SRI section. It creates one fiscal issue from an accepted, confirmed internal invoice, preserves its original line and customer snapshot, and assigns a separate nine-digit tax sequence. The invoice remains a management invoice until the SRI authorization is verified.

The workflow is: configure company and establishment → choose payment means → prepare → sign `.p12` on the private worker → submit to the SRI reception SOAP endpoint → query the authorization endpoint by the same 49-digit key → archive signed/authorized XML and RIDE in a private bucket → link the verified authorization to the commercial invoice → email XML and PDF to the customer. No signing key is accepted in the browser.

The signer deliberately supports only ordinary Ecuadorian domestic invoices with numeric cédula/RUC customer identity, payment code 01/16/19/20, and supported VAT rates. It rejects unsupported tax rates and mismatched totals. Credit/debit notes, withholding, delivery notes, RIMPE, ICE, exports and specialized regimes need their own SRI models. These are not silently converted into ordinary invoices.

## Deployment prerequisites

1. Apply `20260927213000_sri_invoice_workflow.sql` to a development database first. Verify its RLS policies and check the existing invoice and accounting flows.
2. Host `services/sri` privately behind HTTPS. Install the pinned `requirements.txt` into its own environment. Provision `SRI_P12_BASE64`, `SRI_P12_PASSWORD`, `SRI_ISSUER_RUC`, `SRI_WORKER_SECRET` and SMTP environment variables on the server. Restrict inbound traffic to the Edge Function if infrastructure permits.
3. Set the matching `SRI_WORKER_URL` and `SRI_WORKER_SECRET` in Supabase Edge secrets, then deploy `gama-sri` with JWT verification on. The service-role key exists only in Edge secrets. The authenticated `status` action reports readiness to the interface; issuance controls remain disabled by default. Set `SRI_EMISSION_ENABLED=true` only when the private signer is configured and ready for supervised SRI tests in `pruebas`.
4. Configure the company's Ecuadorian legal identity in Coco; enter the establishment, emission point and registered software provider's RUC in the SRI tab. Run SRI certification tests in `pruebas` with representative real tax cases and the official invoice XSD. Confirm the signed XAdES-BES document, RIDE and email with the SRI responses.
5. Only after successful certification and provider registration, explicitly enable `SRI_PRODUCTION_ENABLED=true` on the isolated signer instance and select `produccion` in Coco. An actual production SRI document has tax consequences.

The SRI technical sheet v2.34 (July 2026), including its annex 26 provider field, is the primary specification: https://www.sri.gob.ec/web/intersri/facturacion-electronica . Somatech's LGPL-3.0 Odoo repository was used only to study workflow and the key layout; its code is not bundled or loaded into Coco. This component still needs live certification against SRI's test service. No certificate, provider identity, or live SRI credentials are committed.

When reception times out after transmission, do not issue a new key or send blindly again. Use **Consultar SRI**; retain the same signed XML and sequence for recovery. Email transport can time out after a successful delivery; verify with the mail provider before clicking **Enviar al cliente** again.
