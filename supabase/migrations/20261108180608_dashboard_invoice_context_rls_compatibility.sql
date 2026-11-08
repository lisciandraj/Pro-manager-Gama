-- Dashboard and drilldown functions remain SECURITY INVOKER. These filtered
-- projections were introduced for autonomous invoices and cancelled refunds;
-- their readers need SELECT, with every underlying table's RLS still applied.
begin;
alter view private.coco_posted_invoices set(security_invoker=true);
alter view private.coco_invoice_party_context set(security_invoker=true);
alter view private.coco_active_refunds set(security_invoker=true);
grant select on private.coco_posted_invoices,private.coco_invoice_party_context,private.coco_active_refunds to authenticated;
commit;
