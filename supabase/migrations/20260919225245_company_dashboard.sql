-- Read-only, RLS-preserving company dashboard. No copies of business records.
create function private.dashboard_access(module_id text) returns boolean
language sql stable security invoker set search_path='' as $$
 select coalesce((select p.active
  and p.role in ('administrador','comercial','almacenero')
  and (module_id not in ('payments','quotes','crm','clients','suppliers','accounting','sav','documents') or p.role in ('administrador','comercial'))
  and (module_id<>'tms' or p.role in ('administrador','almacenero'))
  and (module_id<>'fleet' or p.role='administrador')
  and not coalesce(module_id=any(a.disabled_modules),false)
  and not exists(select 1 from public.app_modules m where m.id=module_id and not m.enabled)
 from public.profiles p left join public.role_module_access a on a.role=coalesce(p.access_profile,p.role)
 where p.id=auth.uid()),false)
 and module_id in ('dashboard','payments','sales-orders','quotes','crm','clients','suppliers','products','warehouses','gamaPurchasesV14','tms','fleet','projects','hr','returns','sav','documents','knowledge','accounting')
$$;
revoke all on function private.dashboard_access(text) from public,anon;
grant execute on function private.dashboard_access(text) to authenticated;

create function public.gama_company_dashboard(p_from date default null,p_to date default null) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare
 today date:=(now() at time zone 'America/Guayaquil')::date;
 first_day date:=coalesce(p_from,date_trunc('month',now() at time zone 'America/Guayaquil')::date);
 last_day date:=coalesce(p_to,today);previous_day date;module_id text;value jsonb;sections jsonb:='{}';
 unavailable text[]:='{}';currency_code text;rights jsonb;
begin
 if not private.dashboard_access('dashboard') then raise exception 'DASHBOARD_ACCESS_DENIED' using errcode='42501';end if;
 if first_day>last_day or last_day>today or last_day-first_day>730 then raise exception 'DASHBOARD_INVALID_PERIOD' using errcode='22023';end if;
 previous_day:=first_day-(last_day-first_day+1);
 select currency into currency_code from public.company_settings where id;
 foreach module_id in array array['payments','sales-orders','quotes','crm','clients','suppliers','products','warehouses','gamaPurchasesV14','tms','fleet','projects','hr','returns','sav','documents','knowledge','accounting'] loop
  if not private.dashboard_access(module_id) then continue;end if;
  if module_id='hr' and not private.hr_admin() then continue;end if;
  if module_id='accounting' then
   rights:=private.gama_accounting_rights();
   if not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then continue;end if;
  end if;
  value:=null;
  begin
   case module_id
   when 'payments' then
    -- One canonical ledger: attaching an external reference never adds a second sale.
    -- Payments and credits are aggregated BEFORE the invoice join.
    with paid as (select invoice_id,sum(amount) amount from public.external_invoice_payments where status='confirmed' and paid_at<=today group by invoice_id),
    credits as (select invoice_id,sum(amount) amount from public.return_credits where issued_on<=today group by invoice_id),
    invoices as (select i.*,greatest(0,i.total-coalesce(p.amount,0)-coalesce(c.amount,0)) balance from public.external_invoices i
     left join paid p on p.invoice_id=i.id left join credits c on c.invoice_id=i.id
     where i.fiscal_status not in ('cancelled','rejected')),
    cash as (select p.paid_at,p.amount from public.external_invoice_payments p join invoices i on i.id=p.invoice_id where p.status='confirmed'),
    buckets as (select d::date as bucket_day,least(last_day,(d+case when last_day-first_day<=45 then interval '1 day' else interval '1 month' end)::date-1) end_day
     from generate_series(case when last_day-first_day<=45 then first_day else date_trunc('month',first_day)::date end,last_day,case when last_day-first_day<=45 then interval '1 day' else interval '1 month' end) d)
    select jsonb_build_object(
     'current',jsonb_build_object('net',coalesce(sum(subtotal) filter(where issue_date between first_day and last_day),0),
      'total',coalesce(sum(total) filter(where issue_date between first_day and last_day),0),'count',count(*) filter(where issue_date between first_day and last_day),
      'collected',(select coalesce(sum(amount),0) from cash where paid_at between first_day and last_day)),
     'previous',jsonb_build_object('net',coalesce(sum(subtotal) filter(where issue_date between previous_day and first_day-1),0),
      'collected',(select coalesce(sum(amount),0) from cash where paid_at between previous_day and first_day-1)),
     'receivable',coalesce(sum(balance) filter(where issue_date<=today),0),
     'overdue',coalesce(sum(balance) filter(where issue_date<=today and due_date<today),0),
     'overdue_count',count(*) filter(where issue_date<=today and due_date<today and balance>0),
     'trend',(select coalesce(jsonb_agg(jsonb_build_object('from',greatest(bucket_day,first_day),'to',end_day,
       'invoiced',(select coalesce(sum(total),0) from invoices where issue_date between greatest(bucket_day,first_day) and end_day),
       'collected',(select coalesce(sum(amount),0) from cash where paid_at between greatest(bucket_day,first_day) and end_day)) order by bucket_day),'[]') from buckets),
     'customers',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from (select o.customer_id id,o.customer_name name,sum(i.subtotal) amount from invoices i
      join public.sales_orders o on o.id=i.order_id where i.issue_date between first_day and last_day group by o.customer_id,o.customer_name order by sum(i.subtotal) desc,o.customer_name limit 5) c)
    ) into value from invoices;
   when 'sales-orders' then
    with shipped as (select order_line_id,sum(quantity) quantity from public.sales_delivery_lines group by order_line_id),
    lines as (select l.order_id,sum(l.quantity*l.unit_price*(1+l.tax_rate/100)) amount,sum(greatest(l.quantity-coalesce(s.quantity,0),0)) remaining
     from public.sales_order_lines l left join shipped s on s.order_line_id=l.id group by l.order_id)
    select jsonb_build_object('current',count(*) filter(where o.status='confirmed' and (o.created_at at time zone 'America/Guayaquil')::date between first_day and last_day),
     'previous',count(*) filter(where o.status='confirmed' and (o.created_at at time zone 'America/Guayaquil')::date between previous_day and first_day-1),
     'to_ship',count(*) filter(where o.status='confirmed' and l.remaining>0),'drafts',count(*) filter(where o.status='draft')) into value
     from public.sales_orders o left join lines l on l.order_id=o.id;
   when 'quotes' then
    select jsonb_build_object('waiting',count(*) filter(where quote_state='sent'),'accepted',count(*) filter(where quote_state='accepted')) into value from public.invoices;
   when 'crm' then
    select jsonb_build_object('open',count(*),'pipeline',coalesce(sum(o.amount),0),'weighted',coalesce(sum(o.amount*o.probability/100),0),
     'late',(select count(*) from public.crm_activities where due_at<now() and status not in ('hecha','cancelada'))) into value
     from public.crm_opportunities o join public.crm_pipeline_stages s on s.id=o.stage_id where o.active and not s.is_won and not s.is_lost;
   when 'clients' then
    select jsonb_build_object('active',count(*) filter(where active),'new',count(*) filter(where (created_at at time zone 'America/Guayaquil')::date between first_day and last_day)) into value from public.customers;
   when 'suppliers' then
    select jsonb_build_object('active',count(*) filter(where active)) into value from public.suppliers;
   when 'products' then
    select jsonb_build_object('active',count(*) filter(where active)) into value from public.products;
   when 'warehouses' then
    -- Only the stock source is needed; do not disclose hidden purchasing/order totals.
    with quantities as (select product_id,sum(quantity-reserved_quantity) available from public.stock_quants group by product_id)
    select jsonb_build_object('low',count(*) filter(where coalesce(q.available,0)<p.min_stock),
     'out',count(*) filter(where coalesce(q.available,0)<=0)) into value from public.products p left join quantities q on q.product_id=p.id where p.active;
   when 'gamaPurchasesV14' then
    select jsonb_build_object('open',count(*) filter(where status in ('sent','partial')),
     'late',count(*) filter(where status in ('sent','partial') and (expected_date at time zone 'America/Guayaquil')::date<today),
     'current',count(*) filter(where status not in ('draft','cancelled') and (order_date at time zone 'America/Guayaquil')::date between first_day and last_day)) into value from public.purchase_orders;
   when 'tms' then
    select jsonb_build_object('pending',count(*) filter(where status not in ('Entregada','Cancelada')),
     'late',count(*) filter(where status not in ('Entregada','Cancelada') and delivery_date<today),
     'delivered',count(*) filter(where status='Entregada' and (delivered_at at time zone 'America/Guayaquil')::date between first_day and last_day),
     'on_time',count(*) filter(where status='Entregada' and (delivered_at at time zone 'America/Guayaquil')::date between first_day and last_day and (delivered_at at time zone 'America/Guayaquil')::date<=delivery_date),
     'dated_deliveries',count(*) filter(where status='Entregada' and delivery_date is not null and (delivered_at at time zone 'America/Guayaquil')::date between first_day and last_day)) into value from public.tms_deliveries;
   when 'fleet' then
    select jsonb_build_object('active',count(*) filter(where v.active),
     'documents_due',(select count(*) from public.fleet_documents d join public.fleet_vehicles x on x.id=d.vehicle_id where x.active and d.expires_on<=today+30),
     'fuel',(select coalesce(sum(amount),0) from public.fleet_fuel_logs where logged_on between first_day and last_day),
     'maintenance',(select coalesce(sum(cost),0) from public.fleet_maintenance where performed_on between first_day and last_day)) into value from public.fleet_vehicles v;
   when 'projects' then
    select jsonb_build_object('active',count(*) filter(where status='active'),
     'late',count(*) filter(where status not in ('completed','cancelled') and due_date<today),
     'late_tasks',(select count(*) from public.pm_items i join public.pm_projects p on p.id=i.project_id where i.kind='task' and i.status not in ('done','cancelled') and i.due_date<today and p.status not in ('completed','cancelled'))) into value from public.pm_projects;
   when 'hr' then
    select jsonb_build_object('active',count(*) filter(where active),
     'pending',(select count(*) from public.hr_absences where status='pendiente'),
     'absent',(select count(distinct a.employee_id) from public.hr_absences a join public.hr_employees e on e.id=a.employee_id where e.active and a.status='aprobada' and today between a.start_date and a.end_date)) into value from public.hr_employees;
   when 'returns' then
    select jsonb_build_object('open',count(*) filter(where status not in ('closed','cancelled')),
     'current',count(*) filter(where status<>'cancelled' and (created_at at time zone 'America/Guayaquil')::date between first_day and last_day)) into value from public.return_orders;
   when 'sav' then
    select jsonb_build_object('open',count(*) filter(where not archived and status in ('new','progress','waiting')),
     'late',count(*) filter(where not archived and status in ('new','progress','waiting') and due_date<today),
     'unassigned',count(*) filter(where not archived and status in ('new','progress','waiting') and assigned_to is null),
     'resolved',count(*) filter(where status in ('resolved','closed') and (resolved_at at time zone 'America/Guayaquil')::date between first_day and last_day)) into value from public.service_tickets;
   when 'documents' then
    select jsonb_build_object('active',count(*) filter(where not archived),'expired',count(*) filter(where not archived and expires_on<today),
     'expiring',count(*) filter(where not archived and expires_on between today and today+30)) into value from public.business_documents;
   when 'knowledge' then
    select jsonb_build_object('articles',count(*),'updated',count(*) filter(where (updated_at at time zone 'America/Guayaquil')::date between first_day and last_day)) into value from public.knowledge_articles;
   when 'accounting' then
    -- Debts are net of supplier credits. Cash is grouped by currency; no FX guess.
    with paid as (select supplier_invoice_id,sum(amount) amount from public.supplier_invoice_payments where status='confirmed' and paid_at<=today group by supplier_invoice_id),
    credits as (select supplier_invoice_id,sum(amount) amount from public.return_credits where issued_on<=today group by supplier_invoice_id),
    bills as (select i.*,greatest(0,i.total-coalesce(p.amount,0)-coalesce(c.amount,0)) balance from public.supplier_invoices i
     left join paid p on p.supplier_invoice_id=i.id left join credits c on c.supplier_invoice_id=i.id where i.status<>'cancelled' and i.issue_date<=today)
    select jsonb_build_object('payable',coalesce(sum(balance),0),'overdue',coalesce(sum(balance) filter(where due_date<today),0),'overdue_count',count(*) filter(where due_date<today and balance>0),
     'expenses',(select coalesce(jsonb_agg(to_jsonb(e)),'[]') from (select currency,sum(amount_total) amount from public.expenses where status='posted' and expense_date between first_day and last_day group by currency) e),
     'accounts',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from (select f.currency,count(*) count,sum(f.opening_balance
      +coalesce((select sum(p.amount) from public.external_invoice_payments p where p.financial_account_id=f.id and p.status='confirmed' and p.paid_at<=today),0)
      -coalesce((select sum(p.amount) from public.supplier_invoice_payments p where p.financial_account_id=f.id and p.status='confirmed' and p.paid_at<=today),0)
      -coalesce((select sum(e.amount_total) from public.expenses e where e.financial_account_id=f.id and e.status='posted' and e.expense_date<=today),0)) amount
     from public.financial_accounts f where f.active group by f.currency) a)) into value from bills;
   end case;
  exception when others then
   -- Keep a broken source distinct from an empty source; no invented zeros.
   value:=null;raise log 'company_dashboard source % unavailable (%)',module_id,sqlstate;
  end;
  sections:=sections||jsonb_build_object(module_id,value);
  if value is null then unavailable:=array_append(unavailable,module_id);end if;
 end loop;
 return jsonb_build_object('user_id',auth.uid(),'period',jsonb_build_object('from',first_day,'to',last_day,'previous_from',previous_day,'previous_to',first_day-1),
  'today',today,'time_zone','America/Guayaquil','currency',currency_code,'generated_at',now(),'sections',sections,'unavailable',unavailable);
end $$;
revoke all on function public.gama_company_dashboard(date,date) from public,anon;
grant execute on function public.gama_company_dashboard(date,date) to authenticated;
