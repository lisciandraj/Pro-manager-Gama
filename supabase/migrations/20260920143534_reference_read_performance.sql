-- Keep source-table RLS, but plan only the requested source. An inline CASE
-- with 31 subqueries expands every source's policies on every reference read.
-- PL/pgSQL lazily plans each static branch; SECURITY INVOKER preserves the
-- caller's table/column privileges and row policies, including HR attachments.
create or replace function private.gama_can_read_reference(p_table text,p_id uuid)
returns boolean language plpgsql stable security invoker set search_path='' as $$
begin
 case p_table
 when 'customer_requests' then return exists(select 1 from public.customer_requests x where x.id=p_id);
 when 'invoices' then return exists(select 1 from public.invoices x where x.id=p_id);
 when 'sales_orders' then return exists(select 1 from public.sales_orders x where x.id=p_id);
 when 'fulfillment_preparations' then return exists(select 1 from public.fulfillment_preparations x where x.id=p_id);
 when 'fulfillment_packages' then return exists(select 1 from public.fulfillment_packages x where x.id=p_id);
 when 'sales_deliveries' then return exists(select 1 from public.sales_deliveries x where x.id=p_id);
 when 'tms_deliveries' then return exists(select 1 from public.tms_deliveries x where x.id=p_id);
 when 'tms_proofs' then return exists(select 1 from public.tms_proofs x where x.delivery_id=p_id);
 when 'external_invoices' then return exists(select 1 from public.external_invoices x where x.id=p_id);
 when 'external_invoice_payments' then return exists(select 1 from public.external_invoice_payments x where x.id=p_id);
 when 'return_orders' then return exists(select 1 from public.return_orders x where x.id=p_id);
 when 'purchase_orders' then return exists(select 1 from public.purchase_orders x where x.id=p_id);
 when 'inventory_counts' then return exists(select 1 from public.inventory_counts x where x.id=p_id);
 when 'stock_reservations' then return exists(select 1 from public.stock_reservations x where x.id=p_id);
 when 'stock_movements' then return exists(select 1 from public.stock_movements x where x.id=p_id);
 when 'crm_opportunities' then return exists(select 1 from public.crm_opportunities x where x.id=p_id);
 when 'pm_projects' then return exists(select 1 from public.pm_projects x where x.id=p_id);
 when 'fleet_vehicles' then return exists(select 1 from public.fleet_vehicles x where x.id=p_id);
 when 'hr_documents' then return exists(select 1 from public.hr_documents x where x.id=p_id);
 when 'hr_payroll' then return exists(select 1 from public.hr_payroll x where x.id=p_id);
 when 'service_tickets' then return exists(select 1 from public.service_tickets x where x.id=p_id);
 when 'business_documents' then return exists(select 1 from public.business_documents x where x.id=p_id);
 when 'accounting_entries' then return exists(select 1 from public.accounting_entries x where x.id=p_id);
 when 'expenses' then return exists(select 1 from public.expenses x where x.id=p_id);
 when 'supplier_invoices' then return exists(select 1 from public.supplier_invoices x where x.id=p_id);
 when 'supplier_invoice_payments' then return exists(select 1 from public.supplier_invoice_payments x where x.id=p_id);
 when 'return_credits' then return exists(select 1 from public.return_credits x where x.id=p_id);
 when 'return_refunds' then return exists(select 1 from public.return_refunds x where x.id=p_id);
 when 'tms_routes' then return exists(select 1 from public.tms_routes x where x.id=p_id);
 when 'knowledge_articles' then return exists(select 1 from public.knowledge_articles x where x.id=p_id);
 when 'pm_items' then return exists(select 1 from public.pm_items x where x.id=p_id);
 else return false;
 end case;
end $$;
revoke all on function private.gama_can_read_reference(text,uuid) from public,anon;
grant execute on function private.gama_can_read_reference(text,uuid) to authenticated;
alter policy dossier_reference_read on public.gama_document_references
 using(private.gama_can_read_reference(table_name,document_id));
