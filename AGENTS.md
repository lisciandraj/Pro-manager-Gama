# Coco ERP maintenance

Read README.md and docs/architecture.md before structural changes.
- Edit canonical files under src/, not generated root scripts/styles or index.html.
- config/runtime-assets.json maps runtime addresses to their source files and preserves CSS order.
- Keep public module IDs, database/RPC names, stored localStorage keys and deployed Edge Function names compatible.
- Run npm run build after source changes; commit every generated output. npm run check:generated detects drift.
- Use relevant existing tests; database fixtures must run in isolated test databases.
- Update current documentation when routes, permissions, loading or UI behavior changes.
- Historical documents belong in docs/history/ and are not current specifications.
