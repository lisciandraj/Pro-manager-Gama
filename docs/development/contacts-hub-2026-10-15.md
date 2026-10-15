# Contacts hub — release integration

## Runtime scope

Contacts provides a Contact dossier action with visible Overview, People and addresses, Sales and purchases, Finance, Activities, Documents, Cloud account and Shared profile tabs, filtered by module permissions. Lazy assets preserve startup loading. The dossier reuses existing document, credit, statement and portal screens.

The tab callback now executes after ArcUI's existing keyboard and mouse navigation. Previously a second bindTabs call was ignored because the dialog had already mounted its tabs, so newly selected panels stayed empty. Save callbacks are awaited, activity reads use the installed `coco_contact_activities` projection, and quotation creation loads its editor before invoking it.

Native records retain their IDs. Shared profile metadata includes nature, language, industry, website, tags and parent relation. Associating customer and supplier roles requires explicit administrator review. Operational coordinates/terms remain per role. Association grants no portal access.

## Database state (verified 15 October 2026)

`20261015202048_coco_contacts_hub` is already installed in Supabase. It includes `coco_contact_activities`, converted-lead activity history, versioned site addresses, default-address clearing on archive and atomic conversion transferring people/opportunities without changing their IDs. Do not reapply the SQL draft.

The installed migration's single SQL statement has 32,466 characters and MD5 `985c1c5b56df463567be4202d62c6dcc`. Its attempt to be archived into GitHub was blocked by the tool security control. No alternative upload or reapplication was attempted. `supabase/pending/coco_contacts_hub.sql` remains the earlier development fixture, NOT an authoritative production migration. Repository restoration therefore does not yet include the complete installed Contacts schema; this remains a migration-reconciliation task.

A local isolated reconstruction using the exact installed SQL (verified checksum) passed profile association, role filters, default-address rollback, stale saves, required activity dates, conversion idempotency, preservation of person IDs and lead activity origin, hierarchy cycle rejection and portal/anonymous access denial. Existing Contacts/person database tests passed against that schema too. These checks do not send messages or modify production records.

Six browser scenarios exercise the current UI and server contract. Local Chromium navigation is blocked by administrator policy; final UI acceptance must use the existing GitHub release workflow. No CI policy or deployment permission has been relaxed. The original draft database test remains a draft test, not proof of a full production schema restoration.

## Access and rollout

Open Administration → Contacts → Contact dossier on a record. Use People and addresses to save a delivery site, Activities to plan a follow-up or internal note, and Shared profile for tags, language and relationships. A single Back action dismisses the dossier.

Deployment must follow successful PR validation and the existing `deploy-coco-pages.yml`. Verify its deploy job and the exact revision in `coco-build.json`; a successful build alone is not a deployment. The pre-release main reference is `e03de7b5a89d977ce036980cc8dedeb8a195f442`; a source rollback must not remove additive contact data from Supabase.

## Remaining scope

This release does not implement the entire initial Odoo-inspired specification. Raw CRM lead-directory unification, synchronization of all operational coordinates across roles, multisite KPI consolidation, full receiving-site propagation to every sales/TMS snapshot, fiscal enrichment and advanced import/general duplicate merging remain separate integration work. Existing prices, credit, SRI, marketing exclusions and portal permissions are retained.
