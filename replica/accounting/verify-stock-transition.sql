-- Read-only readiness audit. A missing cost is not replaced with today's price.
begin transaction read only;
select jsonb_build_object(
 'checked_at',now(),
 'books',(select count(*) from public.stock_cost_books),
 'automatic_books',(select count(*) from public.stock_cost_books where auto_accounting),
 'valuation_rows',(select count(*) from public.stock_valuation_entries),
 'posted_stock_sources',(select count(*) from public.accounting_source_links where source_type in('stock_valuation','stock_invoice','stock_credit')),
 'unconfigured_positive_stock',(select count(distinct p.id) from public.products p join public.stock_quants q on q.product_id=p.id where q.quantity>0 and not exists(select 1 from public.stock_cost_books b where b.product_id=p.id)),
 'movements',(select count(*) from public.stock_movements),
 'missing_cost',(select count(*) from public.stock_movements where unit_cost_at_movement is null),
 'missing_cost_groups',(select jsonb_agg(x) from(select reference_type,count(*) n,min(created_at) first_at,max(created_at) last_at,count(*) filter(where source_location_id is null and destination_location_id is null) missing_locations from public.stock_movements where unit_cost_at_movement is null group by reference_type)x),
 'cost_epoch',(select observed_at from private.erp_stock_cost_epoch where id),
 'customer_invoices',(select count(*) from public.external_invoices),
 'customer_quantity_links',(select count(*) from public.external_invoice_lines),
 'sales_without_quantities',(select count(*) from public.external_invoices i where not exists(select 1 from public.external_invoice_lines l where l.invoice_id=i.id)),
 'supplier_invoices',(select count(*) from public.supplier_invoices),
 'supplier_quantity_lines',(select count(*) from public.supplier_invoice_match_lines),
 'purchases_without_quantities',(select count(*) from public.supplier_invoices i where not exists(select 1 from public.supplier_invoice_matches m join public.supplier_invoice_match_lines l on l.match_id=m.id where m.invoice_id=i.id))
) readiness;
-- Private operational anomaly list. Do not commit the resulting business rows.
select id,erp_reference,product_id,reference_type,reference_id,created_at,quantity,
 source_location_id,destination_location_id,unit_cost_at_movement,
 case when reference_type is null and source_location_id is null and destination_location_id is null
 then 'missing_cost_source_and_locations' else 'missing_historical_cost' end anomaly
from public.stock_movements where unit_cost_at_movement is null order by created_at,id;
rollback;
