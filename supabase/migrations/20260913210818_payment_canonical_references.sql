-- Use the same FAC/PED dossier references as the rest of GAMA.
create or replace view private.gama_receivables with(security_invoker=true) as
select i.id,i.order_id,coalesce(nullif(ir.document_reference,''),i.number) number,case when i.document_kind='external' then i.number else i.external_number end external_number,i.document_kind,i.fiscal_status,i.issue_date,
 i.subtotal,i.tax,i.total,i.payment_terms_days,i.payment_delivery_date,i.due_date,
 coalesce(nullif(oref.document_reference,''),o.number) order_number,o.customer_id,o.customer_name,c.identification,c.email,
 coalesce(p.paid,0) paid,greatest(0,i.total-coalesce(p.paid,0)) balance,
 i.due_date-(now() at time zone 'America/Guayaquil')::date days_remaining,
 case when i.fiscal_status in ('cancelled','rejected') then 'cancelled'
 when i.total<=coalesce(p.paid,0) then 'paid'
 when i.payment_terms_days is null then 'missing_terms'
 when i.payment_delivery_date is null then 'awaiting_delivery'
 when i.due_date<(now() at time zone 'America/Guayaquil')::date then 'overdue'
 when i.due_date<=(now() at time zone 'America/Guayaquil')::date+7 then 'due_soon'
 when coalesce(p.paid,0)>0 then 'partial' else 'pending' end payment_status
from public.external_invoices i join public.sales_orders o on o.id=i.order_id
left join public.gama_document_references ir on ir.table_name='external_invoices' and ir.document_id=i.id
left join public.gama_document_references oref on oref.table_name='sales_orders' and oref.document_id=o.id
left join public.customers c on c.id=o.customer_id
left join (select invoice_id,sum(amount) paid from public.external_invoice_payments where status='confirmed' group by invoice_id) p on p.invoice_id=i.id;
