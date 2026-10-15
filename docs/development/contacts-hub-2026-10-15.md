# Contacts hub — 15 October 2026

## Implemented scope

The Contacts dossier adds visible tabs for overview, people and addresses, sales/purchases, finance, activities, documents, cloud accounts and shared profile. It reuses native screens, collections, prices, credit controls and portal administration. The JavaScript and stylesheet are lazy assets rather than new startup dependencies. Document actions open the selected document in the existing library.

An additive canonical identity links complementary customer/supplier roles only after explicit administrator review, preview, version checks and a reason. Native customer, supplier, invoice, order and B2B membership identifiers remain unchanged. Nature, language, website, industry, tags and parent relationship are shared; operational coordinates and commercial terms remain per role. Relationships reject cycles. A role filter opens the chosen role; archiving a supplier does not archive its customer role.

The server directory handles authorized search and pagination. Client delivery/billing addresses gain structured geographic fields, receiving hours, unloading duration, paired coordinates, an active default per purpose and optimistic versions. Changing an address clears unchanged coordinates. Quote/order/TMS propagation of every new site field remains a rollout integration item; the concurrently updated sales editor is deliberately preserved by this change.

Activities and notes reuse the CRM ledger, including a new supplier anchor. Completion rejects stale versions. Prospect conversion is atomic and retry-safe, retaining the canonical identity for a newly created customer. Linking a prospect to an existing customer retains that customer's identity. Prepared emails are not marked sent. No email, invitation, payment or fiscal document is emitted automatically.

## Deployment gate

The SQL is still a draft at `supabase/pending/coco_contacts_hub.sql`, not a production migration. Apply it through the supported migration mechanism after review and integration tests; record the actual assigned migration version in the repository. Do not deploy the new conversion/address UI before its backend. The draft's prior path `supabase/pending/contacts-hub.sql` was renamed without SQL changes to match the tests; there must not be two copies to apply.

The working baseline started at `9b3e988bae73005c243f66707ca18e77c8eef8e7`. Before publication the branch had incorporated sales work at `e09a8a0ef6d3532ccc289eee9bef3ab034765250`. That sales code, its runtime entry, translations, migrations and workflows are preserved. Only the temporary source-snapshot workflow is removed. Never force-update the shared branch over other work.

## Validation evidence and limits

The isolated Contacts database test applies the draft on the restored schema and passed identity/role, stale edit, authorization, address-default rollback, supplier activity, atomic conversion and ancestry-cycle assertions. Four existing Contacts/person/B2B database tests also passed with the draft overlaid on the original baseline. Local build, JavaScript, type, documentation, generated-file and startup checks passed; architecture tests passed 23/23 on that baseline. These results are not a validation of every subsequent merged change.

Five new browser scenarios are included by the existing Contacts browser suite. The local browser rejected navigation with `ERR_BLOCKED_BY_ADMINISTRATOR`; no local visual test is claimed successful. The repository's normal PR checks must validate the final integrated source before release.

This is not full parity with the original specification. Outstanding work includes the raw CRM prospect directory, cross-role synchronization of operational fields, consolidated multi-establishment KPIs, complete site snapshot propagation, additional fiscal enrichment and advanced import/merge workflows. Existing import/export, credit controls, fiscal validation, marketing exclusions and B2B permissions remain in place rather than being replaced.
