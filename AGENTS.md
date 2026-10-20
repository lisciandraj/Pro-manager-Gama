# Coco ERP maintenance

Read README.md and docs/architecture.md before structural changes.
- Edit canonical files under src/, not generated root scripts/styles or index.html.
- config/runtime-assets.json maps runtime addresses to their source files and preserves CSS order.
- Keep public module IDs, database/RPC names, stored localStorage keys and deployed Edge Function names compatible.
- Run npm run build after source changes. Production publishes the validated dist/ artifact through deploy-coco-pages.yml; see docs/development/pages-publication.md. Do not hand-edit generated root files. npm run check:generated verifies build reproducibility.
- Use relevant existing tests; database fixtures must run in isolated test databases.
- Update current documentation when routes, permissions, loading or UI behavior changes.
- Historical documents belong in docs/history/ and are not current specifications.

## Delivery preference

- The owner asks to always push maintenance commits after the relevant tests pass (20 October 2026). Push the tested task branch to `lisciandraj/Pro-manager-Gama` without asking again for that routine step; retain the existing CI gates before production publication.

## AI database writes

- Every AI business mutation must be attributed to Agent Coco in module history. Prefer the existing authenticated agent gateway, which sets provenance during execution and retains approval checks.
- For authorized direct SQL maintenance, set transaction-local `coco.activity_source_type='chat'`, `coco.activity_source_id` to a unique operation identifier, and `coco.activity_source_label` to `Agent Coco · <short operation description>` in the same transaction as the writes. Never infer an agent from a missing user alone.
- Before writing, verify the affected business tables are registered in `private.coco_history_tables` with enabled capture triggers. If not, implement the appropriate sanitized history mapping first; do not silently leave a module mutation unlogged.
- Verify the committed history contains the affected record references, action, timestamp and `actor_name='Agent Coco'`. Retain the authenticated account ID and existing row access rules. Do not copy credentials, private HR details or binary content into history.
- Technical migrations and schema maintenance remain in the migration ledger; do not invent business events for reads, failed writes or schema-only operations.
