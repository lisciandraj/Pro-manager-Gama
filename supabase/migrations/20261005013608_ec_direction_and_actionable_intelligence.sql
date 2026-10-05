-- One bounded read for management. Each figure retains its source module's authorization.
create function private.gama_management_overview(p_context text default 'dashboard') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare today date:=(now() at time zone private.erp_timezone())::date;month_start date;metrics jsonb:='{}';clients jsonb:='[]';purchase jsonb:='[]';client_count integer:=0;purchase_count integer:=0;value jsonb;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed(p_context,array['administrador']) or p_context not in ('dashboard','assistant-ia') then raise exception 'ROLE_NOT_ALLOWED';end if;
 month_start:=date_trunc('month',today)::date;
 if private.erp_module_allowed('payments',array['administrador']) then
  with valid as(select i.* from public.external_invoices i where i.fiscal_status not in ('cancelled','rejected')),
  reductions as(select coalesce(sum(c.amount*i.subtotal/nullif(i.total,0)),0) net from public.return_credits c join valid i on i.id=c.invoice_id where c.issued_on between month_start and today),
  movement_cost as(select m.reference_id delivery_id,m.product_id,sum(m.quantity*m.unit_cost_at_movement)/nullif(sum(m.quantity),0) cost,bool_and(m.unit_cost_at_movement is not null) complete
   from public.stock_movements m where m.type='out' and m.movement_type='delivery' and m.reference_type='sales_delivery' group by m.reference_id,m.product_id),
  cost_by_line as(select l.id,sum(d.quantity*c.cost)/nullif(sum(d.quantity),0) cost,bool_and(coalesce(c.complete,false)) complete
   from public.sales_order_lines l join public.sales_delivery_lines d on d.order_line_id=l.id left join movement_cost c on c.delivery_id=d.delivery_id and c.product_id=l.product_id group by l.id),
  invoice_cost as(select x.invoice_id,sum(x.quantity*c.cost) cost,bool_and(coalesce(c.complete,false)) complete from public.external_invoice_lines x left join cost_by_line c on c.id=x.order_line_id group by x.invoice_id),
  restored as(select coalesce(sum(l.quantity*c.cost),0) cost,bool_and(coalesce(c.complete,false)) complete
   from public.return_lines l join public.return_orders r on r.id=l.return_id join public.sales_delivery_lines d on d.id=l.delivery_line_id left join cost_by_line c on c.id=d.order_line_id
   where l.disposition='restocked' and l.processed_at is not null and exists(select 1 from public.return_credits n where n.return_id=r.id and n.invoice_id is not null and n.issued_on between month_start and today)),
  totals as(select coalesce(sum(i.subtotal),0) net,coalesce(sum(c.cost),0) cost,count(*) missing
   from valid i left join invoice_cost c on c.invoice_id=i.id where i.issue_date between month_start and today and not coalesce(c.complete,false)),
  full_totals as(select coalesce(sum(i.subtotal),0) net,coalesce(sum(c.cost),0) cost from valid i left join invoice_cost c on c.invoice_id=i.id where i.issue_date between month_start and today)
  select jsonb_build_object('sales_month',round(f.net-r.net,2),'margin_month',case when t.missing=0 and coalesce(s.complete,true) then round(f.net-r.net-f.cost+s.cost,2) end,'margin_missing_invoices',t.missing,'margin_basis','historical_dispatch_cost',
   'overdue',coalesce((select sum(balance) from private.gama_customer_dues() where coalesce(due_date,issue_date)<today),0)) into value from full_totals f cross join reductions r cross join totals t cross join restored s;
  if not private.erp_module_allowed('accounting',array['administrador']) then value:=value-'margin_month'-'margin_missing_invoices'-'margin_basis';end if;
  metrics:=metrics||value;
  with grouped as(select customer_id id,customer_name name,sum(balance) balance,min(coalesce(due_date,issue_date)) oldest_due from private.gama_customer_dues() where coalesce(due_date,issue_date)<today group by customer_id,customer_name),
  limited as(select * from grouped order by balance desc,oldest_due,id limit 10)
  select (select count(*) from grouped),coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object('days_late',today-l.oldest_due) order by l.balance desc,l.oldest_due,l.id),'[]') into client_count,clients from limited l;
 end if;
 if private.erp_module_allowed('warehouses',array['administrador']) then
  select jsonb_build_object('stockouts',count(*) filter(where (r.data->>'available')::numeric<=0),'dormant_stock_value',coalesce(sum((r.data->>'value')::numeric) filter(where (r.data->>'on_hand')::numeric>0 and (r.data->>'days_without_out')::integer>=90),0)) into value from private.stock_insight_rows(false) r;metrics:=metrics||value;
  if private.erp_module_allowed('gamaPurchasesV14',array['administrador']) then
   with all_rows as(select data from private.stock_insight_rows(true) where (data->>'suggested_quantity')::numeric>0),limited as(select data from all_rows order by (data->>'available')::numeric,data->>'name' limit 20)
   select (select count(*) from all_rows),coalesce(jsonb_agg(data),'[]') into purchase_count,purchase from limited;
  end if;
 end if;
 if private.erp_module_allowed('tms',array['administrador']) then
  select jsonb_build_object('late_deliveries',count(*) filter(where status not in ('Entregada','Cancelada') and (delivery_date<today or (delivery_date=today and eta_at<now())))) into value from public.tms_deliveries;metrics:=metrics||value;
 end if;
 return jsonb_build_object('today',today,'month_start',month_start,'generated_at',now(),'metrics',metrics,'clients',clients,'client_count',client_count,'purchases',purchase,'purchase_count',purchase_count);
end $$;
create function public.gama_management_overview(p_context text default 'dashboard') returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_management_overview(p_context)$$;
revoke all on function private.gama_management_overview(text),public.gama_management_overview(text) from public,anon;
grant execute on function private.gama_management_overview(text),public.gama_management_overview(text) to authenticated;
