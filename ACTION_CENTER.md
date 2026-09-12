# Centro de acción

Notifications shows six live categories, independent of pagination and reporting dates; includes snoozed dossiers. Counts are derived, never seeded.

- Confirmed orders with quantities neither shipped nor reserved: view order / prepare supplier purchase.
- Deliveries past their Ecuador planned date, excluding delivered/cancelled: TMS for warehouse staff, linked sales order for commercial staff.
- Sent quotes with quote_sent_at strictly older than 7 days: prepare a reviewable reminder with the GAMA PDF.
- Active products with available stock below min_stock: inspect stock / prepare purchase. Suggestions deduct incoming purchases and account for demand.
- Sent/partial supplier orders with overdue expected reception and remaining quantities: exact purchase dossier.
- Valid external invoices due before today: outstanding total less confirmed payments, linked to the invoice collection controls. Cancelled/rejected invoices are excluded.

Financial categories and purchase preparation are limited to commercial/admin profiles. Warehouse staff retain logistics and stock actions. Existing handling notes, assignments, snoozes and other alert types remain available.

Purchases require supplier selection and review before saving; existing local drafts are preserved. Multi-supplier needs are prepared one supplier at a time. Reminder buttons prepare a message for user review; they do not automatically send it or change quote state.

Validation: operations UI, purchase, quote and sales regression suites; transactional SQL fixture operations-p2.sql (BEGIN / ROLLBACK) exercises threshold, overdue balance, date boundary, role restrictions, pagination and alert lifecycle.
