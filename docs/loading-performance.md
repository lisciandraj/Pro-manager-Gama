# Page-loading investigation — 2026-09-20

Baseline: commit `40150835e0df512a022f5ec652629be56db59929`.

## Confirmed causes and corrections

- The router called `renderAll` for every module. It rebuilt the hidden product,
  customer, stock and audit tables, plus the client selector. The router now
  renders only the selected legacy screen; modern modules keep their own loader.
  Data-change refreshes also render only the visible legacy screen.
- Reference enrichment added serial registry requests after every list read,
  including independent documents that already have `erp_reference`. Those rows
  now use their authorized source data directly. Sales-chain metadata remains
  registry-backed. Own and parent lookups are table-scoped, deduplicated and
  batched at 100 IDs, with at most four concurrent requests. Maps replace repeated
  linear searches. No cross-account reference cache was introduced.
- The registry policy planned 31 source-policy trees for each query. A static
  PL/pgSQL branch now plans only the requested source. The helper is **SECURITY
  INVOKER**, uses an empty search path, and preserves source row/column permissions.
- Concurrent cloud initialization could create multiple Supabase clients and
  authentication subscriptions. Callers now share the initialization promise.
  The supplier bridge also had two loaders; only the central loader remains,
  with an additional execution guard.
- Permission polling rebuilt the menu and invalidated dashboard/KPI loads even
  when no rights changed. Polling and realtime checks remain enabled, but only a
  changed permission/session snapshot emits the refresh event.

## Measurements

Production, same authenticated administrator, same ten sales-order references,
three consecutive samples on each side of the SQL change. These are database
planning/execution times, **not whole-page or mobile-network latency**.

| Sample | Before planning + execution (ms) | After planning + execution (ms) |
| --- | ---: | ---: |
| 1 | 15.541 + 6.402 | 0.466 + 3.592 |
| 2 | 15.174 + 1.184 | 0.415 + 3.609 |
| 3 | 14.715 + 1.165 | 0.417 + 3.394 |

Median total: **16.358 → 4.024 ms** (about 75% lower). An earlier cold baseline
also showed 166.856 ms planning; it is excluded from this warm comparison.

A local Chromium comparison with 1,000 synthetic products and 100 customers,
390px viewport and eight unrelated page transitions produced 40 unnecessary
legacy render calls before the change and **zero** afterwards. This fixture
checks the rendering mechanism, not an authenticated production session.

## Verification

- 49 Node/database tests and 30 focused browser tests passed.
- New regression coverage: bounded/deduplicated reference requests, native-number
  fast path, one cloud client under concurrent startup, scoped navigation on PC
  and mobile, unchanged permission polling and immediate real revocation.
- Database fixtures compare old/new reference visibility for six role contexts,
  exercise all 31 source branches, and verify confidential document revocation,
  protected proof columns and anonymous denial.
- Production visibility fingerprints match exactly for all five existing profiles.
- Build, source/asset checks, TypeScript and migration-history checks passed.

The migration changes only the read policy/helper: no document contents, issued
numbers, account permissions or business transactions are rewritten.

## Cold home follow-up — 2026-09-20

Baseline for this follow-up: `338a42964fcb93d53472d23e7dca012818d2c092`.
The three administrative recovery tiles were visible while the initial access
snapshot was still loading. Profile and role-module reads were sequential.
Initial module events plus a complete menu remount also launched four KPI RPCs.

- Fetch profile and role-module access concurrently, committing the snapshot only
  when both succeed. Keep restricted modules closed until validation completes.
- Share concurrent profile reads only for the exact user/access token; do not
  persist profile permissions or reuse them for later refreshes.
- Preserve the menu DOM when access changes. Existing visibility and router
  listeners continue to apply actual grants/revocations.
- Coalesce initial module configuration reads and wait for initial access/config
  before one KPI calculation. Ignore unchanged configuration notifications and
  keep existing values on a menu remount. Account changes and actual access
  changes still invalidate old KPI responses.
- Preload the pinned, integrity-checked Supabase client and preconnect to the
  existing API host while the page's other scripts are loading.

Controlled local Chromium mobile comparison (390px, mocked 300 ms profile and
access reads, 500 ms KPI response): access critical path **607 → 301 ms**;
initial KPI RPCs **4 → 1**. These measure the corrected startup mechanisms,
not the user's real iPhone or authenticated production network latency.

Validation: 21 focused browser tests (cold start at 390/1440px, permissions,
account switching, KPI editing, order persistence) and the profile single-flight
unit regression pass. Build, source checks and type checks also pass. No database
schema, business data or stored permissions are changed by this follow-up.
