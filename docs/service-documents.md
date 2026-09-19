# SAV and Documents

Small-business workflows inspired by Odoo Helpdesk and Documents:
- https://www.odoo.com/documentation/19.0/applications/services/helpdesk.html
- https://www.odoo.com/documentation/19.0/applications/productivity/documents.html

`gama-service-documents.js` lazily exposes `GamaService.open/openTicket` and `GamaDocuments.open({ticket_id})`. Registry entries, shared icons, controls, dialogs and table/card modes are reused. Spanish source strings are translated through the existing French/English catalog.

SAV: customer and optional sales order, category, warranty date, assignee, priority, deadline, five statuses, required resolution before closing, internal notes, append-only status history, attachments and archive/restore. Notes do not send email or messages to customers. Resolving a claim does not initiate refunds, stock movements or accounting entries.

Documents: file upload (PDF/JPEG/PNG/WebP/DOCX/XLSX/TXT/CSV, 20 MiB), title, flat folder name, notes, expiry date and optional customer/supplier/order/SAV links. Files are immutable versions; metadata uses optimistic concurrency. Downloads use authenticated Storage requests, not public URLs. Metadata and history are included in Excel exports; binary files remain in Storage and can be downloaded from the module.

Access: active administrators and sales staff; existing custom profiles inherit their base role. Module restrictions and app-wide switches are enforced by `private.service_access` in RLS. Documents marked management-only are visible only to administrators. A SAV-enabled profile may access attachments on its claims even if the standalone Documents module is disabled. Clients and warehouse profiles have no access to these two modules by default or via direct API calls. Profile access settings retain the application's base-role boundaries.

The private Storage bucket is `business-documents`. Uploads are user-prefixed random paths. Registration checks the file exists; a failed registration can clean up only the uploader's unregistered objects. Registered files cannot be overwritten or deleted. Restricted files cannot be mistaken for orphans. Document/file registration is transactional; ticket/document composite foreign keys preserve linked customer/order consistency. The private security-definer functions are limited to the minimal assignee directory, append-only audit and a registered-path existence check. Public RPCs use invoker security.

Verification: `node --test tests/service-documents-db.test.cjs tests/excel-export.test.cjs`, `npx playwright test tests/service-documents.spec.js`, `npm run check`, `npm run verify:migrations`. The DB test restores all migrations and exercises real PostgreSQL RLS/constraints; browser tests mock network services and exercise the real interface. Binary Storage transport still requires the managed Supabase service.
