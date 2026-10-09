# Coco ERP maintenance

Read README.md and docs/architecture.md before structural changes.
- Edit canonical files under src/, not generated root scripts/styles or index.html.
- config/runtime-assets.json maps runtime addresses to their source files and preserves CSS order.
- Keep public module IDs, database/RPC names, stored localStorage keys and deployed Edge Function names compatible.
- Run npm run build after source changes. Production publishes the validated dist/ artifact through deploy-coco-pages.yml; see docs/development/pages-publication.md. Do not hand-edit generated root files. npm run check:generated verifies build reproducibility.
- Use relevant existing tests; database fixtures must run in isolated test databases.
- Update current documentation when routes, permissions, loading or UI behavior changes.
- Historical documents belong in docs/history/ and are not current specifications.
