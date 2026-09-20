-- Per-account selection uses the existing owner-only preference policies.
alter table public.user_home_preferences add column kpi_selected text[] check(kpi_selected is null or cardinality(kpi_selected)<=4);
create function public.gama_home_kpis(p_selected text[] default null,p_user uuid default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare u uuid:=auth.uid();r text:=private.current_user_role();allowed text[];chosen text[];preferred text[];k text;v numeric;ops jsonb;vals jsonb:='{}';unavailable text[]:='{}';
 today date:=(now() at time zone 'America/Guayaquil')::date;month_start date:=date_trunc('month',now() at time zone 'America/Guayaquil')::date;
begin
 if u is null or r is null then raise exception 'AUTH_REQUIRED';end if;
 select coalesce(array_agg(c.id order by c.pos),'{}') into allowed from (values
 ('invoiced','operations','finance',1),('collected','operations','finance',2),('receivable','operations','finance',3),('unbilled','operations','finance',4),('overdue_amount','operations','finance',5),
 ('orders','operations','staff',6),('order_amount','operations','finance',7),('quotes_waiting','quotes','finance',8),('clients_active','clients','finance',9),('quotes_accepted','quotes','finance',10),
 ('dispatches','operations','staff',11),('delivered','operations','staff',12),('late_deliveries','operations','staff',13),('blocked','operations','staff',14),('backorders','operations','staff',15),
 ('products_active','products','staff',16),('low_stock','warehouses','staff',17),('out_stock','warehouses','staff',18),('stock_variances','operations','warehouse',19),
 ('open_purchases','gamaPurchasesV14','staff',20),('late_receipts','operations','staff',21),('suppliers_active','suppliers','finance',22),
 ('open_opportunities','crm','finance',23),('pipeline','crm','finance',24),('overdue_activities','crm','finance',25),
 ('active_projects','projects','staff',26),('late_projects','projects','staff',27),('late_tasks','projects','staff',28),
 ('active_employees','hr','hr',29),('pending_absences','hr','hr',30)
 ) c(id,module,scope,pos)
 where r in ('administrador','comercial','almacenero')
 and not exists(select 1 from public.app_modules m where m.id=c.module and not m.enabled)
 and (c.scope='staff' or c.scope='finance' and r in ('administrador','comercial') or c.scope='warehouse' and r in ('administrador','almacenero') or c.scope='hr' and private.hr_admin());
 if p_selected is not null then
  if p_user is distinct from u then raise exception 'AUTH_CHANGED';end if;
  if cardinality(p_selected)<>least(4,cardinality(allowed)) or cardinality(p_selected)<>(select count(distinct x) from unnest(p_selected) x) or exists(select 1 from unnest(p_selected) x where x is null or not x=any(allowed)) then raise exception 'INVALID_KPI_SELECTION';end if;
  insert into public.user_home_preferences(user_id,kpi_selected) values(u,p_selected) on conflict(user_id) do update set kpi_selected=excluded.kpi_selected,updated_at=now();
 end if;
 select kpi_selected into preferred from public.user_home_preferences where user_id=u;
 preferred:=coalesce(preferred,case when r='almacenero' then array['orders','late_deliveries','low_stock','late_receipts'] else array['invoiced','orders','late_deliveries','clients_active'] end);
 select coalesce(array_agg(id order by rank),'{}') into chosen from (select id,min(rank) rank from unnest(preferred||allowed) with ordinality t(id,rank) where id=any(allowed) group by id order by min(rank) limit 4) x;
 if chosen && array['invoiced','collected','receivable','unbilled','overdue_amount','orders','order_amount','dispatches','delivered','late_deliveries','blocked','backorders','stock_variances','late_receipts'] then
  begin ops:=public.gama_operations_action('snapshot','{}');exception when others then ops:=null;end;
 end if;
 foreach k in array chosen loop
  v:=null;
  begin
   case k
    when 'overdue_amount' then v:=(ops#>>'{action_center,overdue_invoice}')::numeric;
    when 'late_receipts' then v:=(ops#>>'{action_center,receipt}')::numeric;
    when 'invoiced','collected','receivable','unbilled','orders','order_amount','dispatches','delivered','late_deliveries','blocked','backorders','stock_variances' then v:=(ops->'metrics'->>k)::numeric;
    when 'clients_active' then select count(*) into v from public.customers where active;
    when 'quotes_waiting' then select count(*) into v from public.invoices where quote_state='sent';
    when 'quotes_accepted' then select count(*) into v from public.invoices where quote_state='accepted' and (quote_accepted_at at time zone 'America/Guayaquil')::date between month_start and today;
    when 'products_active' then select count(*) into v from public.products where active;
    when 'low_stock' then select count(*) into v from public.replenishment_needs where available<min_stock;
    when 'out_stock' then select count(*) into v from public.replenishment_needs where available<=0;
    when 'open_purchases' then select count(*) into v from public.purchase_orders where status in ('sent','partial');
    when 'suppliers_active' then select count(*) into v from public.suppliers where active;
    when 'open_opportunities' then select count(*) into v from public.crm_opportunities o join public.crm_pipeline_stages s on s.id=o.stage_id where o.active and not s.is_won and not s.is_lost;
    when 'pipeline' then select coalesce(sum(o.amount),0) into v from public.crm_opportunities o join public.crm_pipeline_stages s on s.id=o.stage_id where o.active and not s.is_won and not s.is_lost;
    when 'overdue_activities' then select count(*) into v from public.crm_activities where due_at<now() and status not in ('hecha','cancelada');
    when 'active_projects' then select count(*) into v from public.pm_projects where status='active';
    when 'late_projects' then select count(*) into v from public.pm_projects where due_date<today and status not in ('completed','cancelled');
    when 'late_tasks' then select count(*) into v from public.pm_items i join public.pm_projects p on p.id=i.project_id where i.kind='task' and i.status<>'done' and i.due_date<today and p.status not in ('completed','cancelled');
    when 'active_employees' then select count(*) into v from public.hr_employees where active;
    when 'pending_absences' then select count(*) into v from public.hr_absences where status='pendiente';
   end case;
  exception when others then v:=null;
  end;
  vals:=vals||jsonb_build_object(k,v);
  if v is null then unavailable:=array_append(unavailable,k);end if;
 end loop;
 return jsonb_build_object('user_id',u,'allowed',allowed,'selected',chosen,'values',vals,'unavailable',unavailable,'from',month_start,'to',today,'generated_at',now());
end $$;
revoke all on function public.gama_home_kpis(text[],uuid) from public,anon;
grant execute on function public.gama_home_kpis(text[],uuid) to authenticated;
