# Frozen production bootstrap sources 349–362

These are prepared, locally verified SQL fragments only. The preparing agent
made no remote SQL call and applied no migration.

The source manifest is the original 362-source installation
`6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e`.
Each `sourceNNN/manifest.json` gives exact source and derived fingerprints,
fragment hashes, migration names, wrapper additions and verification results.
The top-level `manifest.json` gives the ordered inventory.

Apply only the next uncommitted fragment with the exact `migration_name` from
the manifest, through the authenticated migration API. Each fragment verifies:

- The production project's frozen installation identity.
- Empty Auth, Storage and business tables under the original bootstrap guard.
- The exact expected preceding canonical-source count.
- Every preceding fragment's committed migration receipt, with no current receipt.

No fragment may be replayed blindly. If a response is uncertain, inspect both
the API migration ledger and the canonical bootstrap-source table before
deciding the next step. The canonical source registration appears only in its
last fragment; the next source's guard requires the completed preceding source.

Every derived source statement and its order are preserved byte-for-byte.
The `.payload.sql` files concatenate to the exact reviewed derived source.
No canonical/derived source digest was rewritten. Wrappers are separately
manifested and provide only guards, temporary permission confinement, exact
canonical final ACL restoration and the original bootstrap registration.

New functions are immediately restricted from PUBLIC/anon/authenticated, then
restricted again at each intermediate fragment's end. New tables/sequences/
views receive similarly bounded permissions; new tables have RLS enabled while
the source is incomplete. At source completion, the wrapper restores the exact
canonical ACL and RLS state observed from the monolithic source replay.
Function renames, replacement definitions and their adjacent canonical ACL
statements stay together. A history trigger's DISABLE and matching ENABLE stay
inside one fragment transaction.

Sources 357 and 358 contain original top-level BEGIN/COMMIT statements. Those
statements are preserved, in their canonical order. Wrapper finalization and
the canonical source registration are inserted immediately before the original
COMMIT, so schema completion and canonical source registration commit together.
An outer transaction may report the usual redundant BEGIN/COMMIT warnings.

The isolated PGlite verification rebuilds exact frozen sources 1–348 and then,
for every source 349–362, compares monolithic execution with the bounded fragment
transactions. It compares all affected schema functions, security modes,
normalized ACLs, table/column definitions, policies and user triggers; checks
the canonical source counter; rejects unintended new anonymous/public definer
access after every intermediate commit; and reruns the empty-business guard
after each completed source. Sources with explicit transaction controls use an
independent database clone for the canonical baseline, preserving those controls.

`verification.json` records the final 362-source canonical and derived
fingerprints. The preparer/verifier is
`/tmp/coco-release-bootstrap/prepare-remaining-fragments.cjs` and its log is
`/tmp/coco-release-bootstrap/.build/remaining-fragments.log`.

The migration API's approval rules remain applicable. Bounded preparation is
not a mechanism to bypass a denied or missing approval.
