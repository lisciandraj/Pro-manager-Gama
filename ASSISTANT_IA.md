# Assistant IA

Administrator-only GAMA module, available in French, Spanish and English.

## Activation

Open **Assistant IA → Connecter l’IA**, enter an OpenAI API key with available
credit, and save. The default API model is `gpt-4.1-mini`; the administrator may
specify another compatible GPT model. Model access is checked before saving.
No API key belongs in the repository, browser storage, screenshots or tests.

An existing `OPENAI_API_KEY` Edge Function secret also works, with optional
`OPENAI_MODEL`. An explicitly saved module connection takes precedence.

The calculated diagnostic works without an AI provider and is explicitly marked
as calculated. Free-form AI questions require the configured provider. A missing
key or provider failure never becomes a pretend AI response.

## Data and behavior

- `gama_ai_catalog` explicitly allowlists the 82 existing business tables and
  their readable fields. Extend it when adding a business module. Authentication
  internals, API credentials, binary attachments and nested audit snapshots are
  excluded. Knowledge text is read in chunks when necessary.
- `gama_ai_query` accepts a restricted read description, never model SQL. It
  checks table and field names, quotes identifiers and values, enforces time and
  pagination limits, and calculates aggregates over all matching records.
- `gama_ai_overview` computes current stock, canonical receivables, operational
  delays and activity indicators. Only invoicing/receipts/orders use the selected
  period; dates follow `America/Guayaquil`, monetary values follow the existing
  GAMA convention of USD. Quotes and linked external invoice numbers are not
  added a second time to the invoice register. Cancelled payments do not count.
- Answers contain findings, evidence IDs, proposed actions with priorities,
  owner roles, deadlines and success criteria, plus limitations. Evidence has
  timestamps, query descriptions and explicit truncation indicators. Counts in
  “data coverage” show available data, not a claim to have analyzed every row.
- Plans never modify business data or send messages. The only writes are AI
  configuration and this administrator's private analysis history.
- This application currently has one company per Supabase project. The assistant
  retains the existing RLS scope; it does not introduce a multi-company model.

## Security and operation

`gama-assistant-ia` has gateway JWT verification enabled. It independently verifies
the user through Auth, checks the current `profiles.active` and administrator role
before every operation and again before returning an answer. Its data requests
use the caller's token, retaining RLS. The database RPCs repeat the role and module
enablement checks. No business query uses the service-role token.

History SELECT is restricted to its owner, while the owner is an active
administrator and the module is enabled. Browser roles cannot insert or update
history, call the rate-limit claim, or read/write AI settings. A shared database
rate limit admits at most 4 requests/minute, 30/hour and 100/day per administrator;
request IDs prevent duplicate execution.

Provider keys are AES-GCM encrypted with a random nonce before storage in a table
accessible only to the server's service role. Prefer a stable, random
`GAMA_AI_ENCRYPTION_KEY` Edge Function secret for encryption. Without it, the
service-role key derives the encryption key: rotating it requires reconnecting
the AI account. Keys and provider errors are never logged or returned. Model
requests use `store:false`; OpenAI's separate account data retention terms still
apply. Only relevant company evidence should be retrieved for a question.

## Deployment and verification

Publish frontend changes using the existing GitHub Pages deployment. Apply the
committed Supabase migrations and deploy `supabase/functions/gama-assistant-ia`
with `index.ts` as entrypoint and `verify_jwt=true`. No frontend build step or new
runtime package is required.

Checks:

- `node --test tests/assistant-server.test.mjs`: authorization, truthful missing-key
  state, calculations from server input, encrypted configuration, provider errors,
  restricted tools and evidence validation (provider calls are mocked).
- `npm test -- tests/assistant-ia.spec.js`: admin/non-admin navigation, chat,
  history, evidence, XSS escaping, settings, logout, mobile and language changes.
- `supabase/tests/assistant-ia.sql`: actual PostgreSQL role/RLS, injection,
  aggregation and period checks. Fixtures are enclosed in a rolled-back transaction.

The live overview and unauthenticated Edge Function rejection were checked during
deployment. A paid model response must also be checked after supplying the real
provider key; mocked provider tests do not establish real account access.

## Coco Intelligence inventory (V1.1)

The user-facing module is now **Coco Intelligence**; `assistant-ia` remains its
stable permission/history ID. Its stock panel works without OpenAI credit.

- Demand uses observed outbound delivery, production and manual consumption over
  30/60/90 days. Transfers, adjustments, supplier returns and future movements do
  not count. The weighted daily mean is 50%/30%/20% across those fixed windows.
- Suggested minimum is 1.5 × lead-time demand; maximum is demand over lead time
  plus 14 days, plus a 50% lead-time safety buffer. Missing lead time defaults to
  7 days. Confidence is an indicative heuristic based on history and settings.
- Without demand, retain configured min/max and label the result as configuration
  based with limited confidence. Service and inactive products are excluded.
- Available stock excludes reservations. Sent/partial purchases count as incoming;
  draft purchases are shown separately and deducted to prevent duplicate proposals.
  Order quantity is positive only below the proposed minimum. Stock above minimum
  can still receive a threshold-review proposal, with zero purchase quantity.
- The panel shows all pending recommendations through pages ordered by priority,
  calculation inputs, a timestamp, refresh/retry controls and a link to Purchases.
  It never changes product thresholds, physical stock or purchase orders.
- Each AI question refreshes deterministic recommendations, receives a first page
  as cited evidence, and can read further pages with `read_inventory`. The model
  explains supplied quantities; it cannot calculate or apply inventory policy.
- Both read RPCs and cache refresh require an active administrator and enabled
  module. Public RPCs use invoker rights; the guarded cache writer resides in the
  non-exposed private schema with an empty search path. Tables are read-only to
  browser roles and RLS denies non-admin reads. Refreshes serialize with a
  transaction advisory lock; refreshed proposals retain IDs and stale ones expire.

Verify with `node --test tests/coco-intelligence-db.test.cjs
 tests/assistant-server.test.mjs` and `npx playwright test tests/assistant-ia.spec.js`.
Deploy the reliability migration before the updated Edge Function and frontend.
