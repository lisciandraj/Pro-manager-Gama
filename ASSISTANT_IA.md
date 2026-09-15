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
