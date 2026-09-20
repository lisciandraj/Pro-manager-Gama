create table public.dossier_followups(id uuid primary key default gen_random_uuid(),dossier_key text not null unique,owner_id uuid not null references public.profiles(id),next_action text not null check(length(btrim(next_action))>0),due_date date not null,updated_at timestamptz not null default now(),updated_by uuid not null default auth.uid() references public.profiles(id),closed_at timestamptz,closed_by uuid references public.profiles(id),closure_fingerprint text,closure_note text);
alter table public.dossier_followups enable row level security;revoke all on public.dossier_followups from public,anon,authenticated;grant select on public.dossier_followups to authenticated;
create policy dossier_followup_read on public.dossier_followups for select to authenticated using(private.erp_module_allowed('dossier-flow',array['administrador','comercial']));
create index dossier_followup_owner on public.dossier_followups(owner_id,due_date);create index dossier_followup_actor on public.dossier_followups(updated_by);create index dossier_followup_closer on public.dossier_followups(closed_by);
create trigger erp_audit_capture after insert or update or delete on public.dossier_followups for each row execute function private.erp_audit_capture();
create function private.gama_dossier_followup(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare k text:=p_data->>'key';source uuid;kind text;f public.dossier_followups;checks jsonb;fp text;missing numeric;unbilled numeric;balance numeric;ret bigint;begin
 if not private.erp_module_allowed('dossier-flow',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 kind:=split_part(k,':',1);source:=split_part(k,':',2)::uuid;
 if (kind='o' and not exists(select 1 from public.sales_orders where id=source)) or (kind='q' and not exists(select 1 from public.invoices where id=source)) or (kind='r' and not exists(select 1 from public.customer_requests where id=source)) or kind not in ('o','q','r') then raise exception 'DOSSIER_NOT_FOUND';end if;
 if kind='o' then
 perform 1 from public.sales_orders where id=source for update;
 select coalesce(sum(greatest(0,l.quantity-coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl join public.sales_deliveries s on s.id=dl.delivery_id join public.tms_deliveries t on t.id=s.tms_delivery_id join public.tms_proofs pr on pr.delivery_id=t.id where dl.order_line_id=l.id and t.status='Entregada' and nullif(pr.signature,'') is not null),0))),0) into missing from public.sales_order_lines l where l.order_id=source;
 select coalesce(sum(greatest(0,l.quantity-coalesce((select sum(il.quantity) from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('rejected','cancelled')),0))),0) into unbilled from public.sales_order_lines l where l.order_id=source;
 select coalesce(sum(r.balance),0) into balance from private.gama_receivables r where r.order_id=source and r.payment_status<>'cancelled';select count(*) into ret from public.return_orders where order_id=source and status not in ('closed','cancelled');
 checks:=jsonb_build_object('delivery_remainder',missing,'unbilled_quantity',unbilled,'unpaid_amount',balance,'open_returns',ret,'empty_order',not exists(select 1 from public.sales_order_lines where order_id=source),'order_confirmed',exists(select 1 from public.sales_orders where id=source and status='confirmed'));
 else checks:=jsonb_build_object('order_required',true);end if;
 fp:=md5(checks::text);select * into f from public.dossier_followups where dossier_key=k for update;
 if p_action='save' then
 if not exists(select 1 from public.profiles where id=(p_data->>'owner_id')::uuid and active and role in ('administrador','comercial')) then raise exception 'OWNER_REQUIRED';end if;
 insert into public.dossier_followups(dossier_key,owner_id,next_action,due_date) values(k,(p_data->>'owner_id')::uuid,p_data->>'next_action',(p_data->>'due_date')::date) on conflict(dossier_key) do update set owner_id=excluded.owner_id,next_action=excluded.next_action,due_date=excluded.due_date,updated_by=auth.uid(),updated_at=now() returning * into f;
 elsif p_action='close' then
 if f.id is null then raise exception 'FOLLOWUP_REQUIRED';end if;
 if kind<>'o' or missing>0 or unbilled>0 or balance>0.005 or ret>0 or (checks->>'empty_order')::boolean or not(checks->>'order_confirmed')::boolean then raise exception 'DOSSIER_INCOMPLETE';end if;
 if length(btrim(coalesce(p_data->>'note','')))<3 then raise exception 'CLOSURE_NOTE_REQUIRED';end if;
 update public.dossier_followups set closed_at=now(),closed_by=auth.uid(),closure_note=p_data->>'note',closure_fingerprint=fp where id=f.id returning * into f;
 elsif p_action<>'context' then raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('followup',case when f.id is null then null else to_jsonb(f) end,'checks',checks,'closed',coalesce(f.closed_at is not null and f.closure_fingerprint=fp,false),'reopened',coalesce(f.closed_at is not null and f.closure_fingerprint<>fp,false));
end $$;
revoke all on function private.gama_dossier_followup(text,jsonb) from public,anon;grant execute on function private.gama_dossier_followup(text,jsonb) to authenticated;
create function public.gama_dossier_followup(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_dossier_followup(p_action,p_data)$$;
revoke all on function public.gama_dossier_followup(text,jsonb) from public,anon;grant execute on function public.gama_dossier_followup(text,jsonb) to authenticated;

create table public.pm_cost_entries(id uuid primary key default gen_random_uuid(),project_id uuid not null references public.pm_projects(id),entry_date date not null,kind text not null check(kind in ('labor','other')),description text not null check(length(btrim(description))>=3),quantity numeric(14,3) not null check(quantity>0),unit_cost numeric(16,4) not null check(unit_cost>=0),amount numeric(18,2) generated always as(round(quantity*unit_cost,2)) stored,source_reference text not null,created_by uuid not null default auth.uid() references public.profiles(id),created_at timestamptz not null default now(),cancelled_at timestamptz,cancellation_reason text,unique(project_id,source_reference));
create table public.pm_baselines(id uuid primary key default gen_random_uuid(),project_id uuid not null references public.pm_projects(id),name text not null check(length(btrim(name))>=3),snapshot jsonb not null,created_by uuid not null default auth.uid() references public.profiles(id),created_at timestamptz not null default now());
do $$declare t text;begin foreach t in array array['pm_cost_entries','pm_baselines'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);execute format('create policy pm_finance_read on public.%I for select to authenticated using(private.pm_manage(project_id))',t);execute format('create index %I on public.%I(project_id)',t||'_project',t);execute format('create index %I on public.%I(created_by)',t||'_actor',t);execute format('create trigger erp_audit_capture after insert or update or delete on public.%I for each row execute function private.erp_audit_capture()',t);end loop;end $$;
create function private.pm_financials(pid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with p as(select * from public.pm_projects where id=pid),extra as(
 select coalesce((select sum(amount) from public.pm_cost_entries where project_id=pid and cancelled_at is null),0) entered,
 coalesce((select sum(e.amount_untaxed) from public.expenses e,p where e.project_id=pid and e.status='posted' and e.currency=p.currency),0) expenses,
 coalesce((select sum(b.subtotal) from public.supplier_invoices b,p where b.project_id=pid and b.status='posted' and p.currency=(select currency from public.company_settings where id) and not exists(select 1 from public.pm_links l where l.kind='purchase' and l.target_id=b.purchase_order_id)),0) supplier_bills,
 (select count(*) from public.expenses e,p where e.project_id=pid and e.status='posted' and e.currency<>p.currency)+(select count(*) from public.supplier_invoices b,p where b.project_id=pid and b.status='posted' and p.currency<>(select currency from public.company_settings where id) and not exists(select 1 from public.pm_links l where l.kind='purchase' and l.target_id=b.purchase_order_id)) unconverted_costs
 ),revenue as(select distinct i.id,i.subtotal-coalesce((select sum((private.gama_return_split(c.return_id,c.amount)->>'net')::numeric) from public.return_credits c where c.invoice_id=i.id),0) net,
 case when p.currency=(select currency from public.company_settings where id) then 1 when l.currency=(select currency from public.company_settings where id) then l.exchange_rate else null end fx
 from public.external_invoices i join public.sales_orders o on o.id=i.order_id join public.pm_links l on l.project_id=pid and ((l.kind='order' and l.target_id=o.id) or (l.kind='quote' and l.target_id=o.source_quote_id)) cross join p where i.fiscal_status not in ('rejected','cancelled'))
 select jsonb_build_object('entered',entered,'expenses',expenses,'supplier_bills',supplier_bills,'additional_cost',entered+expenses+supplier_bills,'unconverted_costs',unconverted_costs,'revenue',coalesce((select sum(net*fx) from (select id,max(net) net,max(fx) fx from revenue group by id)r),0),'unconverted_revenue',(select count(distinct id) from revenue where fx is null)) from extra
$$;
revoke all on function private.pm_financials(uuid) from public,anon,authenticated;
-- Retain the existing metrics contract while completing its actual cost base.
alter function private.pm_metrics(uuid) rename to pm_metrics_purchases;
create function private.pm_metrics(pid uuid) returns jsonb language plpgsql stable security invoker set search_path='' as $$declare m jsonb:=private.pm_metrics_purchases(pid);f jsonb:=private.pm_financials(pid);p public.pm_projects;actual numeric;forecast numeric;ch int;begin
 select * into p from public.pm_projects where id=pid;actual:=(m->>'actual')::numeric+(f->>'additional_cost')::numeric;forecast:=actual+(m->>'committed')::numeric+coalesce(p.estimate_remaining,greatest(0,p.budget-actual-(m->>'committed')::numeric));ch:=case when p.status in ('completed','cancelled') then 0 when forecast>p.budget*(1+p.budget_tolerance/100) then 2 when forecast>p.budget then 1 else 0 end;
 return m||f||jsonb_build_object('actual',actual,'remaining',p.budget-actual,'forecast',forecast,'etc',forecast-actual,'vac',p.budget-forecast,'cost_health',ch,'health',greatest(ch,(m->>'schedule_health')::int,(m->>'risk_health')::int),'margin',(f->>'revenue')::numeric-actual);
end $$;
revoke all on function private.pm_metrics(uuid) from public,anon,authenticated;
create function private.gama_project_finance(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare pid uuid:=(p_data->>'project_id')::uuid;p public.pm_projects;x jsonb;begin
 if not private.erp_module_allowed('projects',array['administrador','comercial','almacenero']) or not private.pm_manage(pid) then raise exception 'ROLE_NOT_ALLOWED';end if;select * into p from public.pm_projects where id=pid for update;
 if p_action='cost' then
 if p.status in ('completed','cancelled') then raise exception 'PROJECT_CLOSED';end if;
 insert into public.pm_cost_entries(id,project_id,entry_date,kind,description,quantity,unit_cost,source_reference) values((p_data->>'id')::uuid,pid,(p_data->>'entry_date')::date,p_data->>'kind',p_data->>'description',(p_data->>'quantity')::numeric,(p_data->>'unit_cost')::numeric,p_data->>'source_reference') on conflict(id) do nothing;
 elsif p_action='cancel_cost' then if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;update public.pm_cost_entries set cancelled_at=coalesce(cancelled_at,now()),cancellation_reason=p_data->>'reason' where id=(p_data->>'id')::uuid and project_id=pid;
 elsif p_action='baseline' then
 insert into public.pm_baselines(id,project_id,name,snapshot) values((p_data->>'id')::uuid,pid,p_data->>'name',jsonb_build_object('project',to_jsonb(p),'metrics',private.pm_metrics(pid),'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]') from public.pm_items i where project_id=pid))) on conflict(id) do nothing;
 elsif p_action<>'context' then raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('project',to_jsonb(p),'metrics',private.pm_metrics(pid),'costs',(select coalesce(jsonb_agg(to_jsonb(e) order by entry_date desc),'[]') from public.pm_cost_entries e where project_id=pid),'baselines',(select coalesce(jsonb_agg(to_jsonb(b) order by created_at desc),'[]') from public.pm_baselines b where project_id=pid));
end $$;
revoke all on function private.gama_project_finance(text,jsonb) from public,anon;grant execute on function private.gama_project_finance(text,jsonb) to authenticated;
create function public.gama_project_finance(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_project_finance(p_action,p_data)$$;
revoke all on function public.gama_project_finance(text,jsonb) from public,anon;grant execute on function public.gama_project_finance(text,jsonb) to authenticated;
