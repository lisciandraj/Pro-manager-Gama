# Coordinated SRI deployment — pruebas

The compose definition prepares PostgreSQL, Redis, Carbone, the reviewed Open API
revision and the Coco Python gateway. It is a deployment recipe, not evidence that
these services are running. GitHub Pages cannot host this stack. Supply a Linux
Docker host and HTTPS endpoints; neither a paid server nor credentials are created
by this repository. Production endpoints are absent from this recipe.

## Deployment order

1. On a private server, clone the same Coco commit as the interface release.
   Run `python3 services/sri/deploy/prepare.py`. It pins upstream, excludes its
   seeded superadministrator/data and restricts certificate file permissions.
2. Copy `deployment.env.example`, `upstream.env.example` and
   `../openapi.env.example` outside Git to `/opt/coco-sri/secrets/`; set permissions
   to 600. Fill database/Redis passwords, encryption key/salt, JWT key, gateway
   shared secret and issuer RUC. Keep all `.runtime/` data outside web publishing.
3. Select a tested Carbone 5 full image by digest. HTML templates and substitutions,
   loops and PDF conversion are documented Community functions. No Enterprise
   subscription is required for that subset. This is a feature review, not a
   redistribution license opinion. The pinned upstream RIDE is `templates/ride.html`.
   Real PDF output, template looping and required fiscal content still need QA.
4. Start the backend together:
   `docker compose --env-file /opt/coco-sri/secrets/deployment.env -f services/sri/deploy/compose.pruebas.yml up -d --build`.
   PostgreSQL bootstrap applies only to an empty new volume; never import it into
   the Coco Supabase database. Provision a private admin and scoped tenant user
   using the reviewed upstream authentication/tenant flows. The scrubbed dump
   deliberately creates no default login. Configure issuer, dedicated fiscal
   series and real certificate `.p12` and password through issuer administration.
5. Put the loopback ports 3001 and 8000 behind validated HTTPS reverse proxies;
   expose Open API only to operators/gateway and the worker to the Edge Function.
   Never publish PostgreSQL, Redis, Carbone or certificate volumes. The worker
   requires HMAC authentication. Its URL plus shared secret are private Edge secrets.
6. Set gateway `SRI_OPENAPI_URL`, scoped credentials, legal accounting obligation,
   `SRI_OPENAPI_ENVIRONMENT=pruebas`, `SRI_PRODUCTION_ENABLED=false`. Confirm the
   actual SOAP endpoints are `celcer.sri.gob.ec`, synchronous emission is false
   for `SRI_EMISION_ASYNC`, and reception has only one attempt. Then set
   `SRI_OPENAPI_SYNC_CONFIRMED=true` and restart gateway. Never auto-retry reception.
7. Apply `sri_invoice_selection` migration to Coco, deploy the matching `gama-sri`
   with JWT verification and `SRI_EMISSION_ENABLED=false`, then release the UI.
   Configure issuer and fiscal profile in Configuration → Facturation SRI.
8. Check status from an authorized Coco session, validate RIDE and XML with isolated
   fixtures, then enable emissions only for supervised `pruebas`. Test acceptance,
   rejection, timeout reconciliation and downloads using the real certificate.
   Production remains disabled until separately authorized and validated.

Back up database and certificate/XML/PDF volumes encrypted, with a tested restore.
No secrets, .p12, XML/PDF customer data or database dumps belong in GitHub Pages.

## Carbone sources reviewed (2026-10-01)

- https://carbone.io/documentation/developer/on-premise-installation/licensing.html
- https://carbone.io/documentation/design/template-formats/html.html
- https://carbone.io/documentation/design/overview/template-feature.html

The Community HTML feature declaration is not proof that a particular Docker tag
contains the necessary Chromium converter; validate the pinned image before use.
