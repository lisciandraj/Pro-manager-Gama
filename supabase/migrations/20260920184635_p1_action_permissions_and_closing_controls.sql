-- Action restrictions narrow the existing business roles; they never grant privileges.
create table public.erp_action_permissions(role text not null references public.role_module_access(role),module text not null,allow_create boolean not null default true,allow_edit boolean not null default true,allow_delete boolean not null default true,allow_validate boolean not null default true,allow_export boolean not null default true,updated_at timestamptz not null default now(),updated_by uuid not null default auth.uid() references public.profiles(id),primary key(role,module));
alter table public.erp_action_permissions enable row level security;revoke all on public.erp_action_permissions from public,anon,authenticated;grant select,insert,update on public.erp_action_permissions to authenticated;
create policy action_rights_read on public.erp_action_permissions for select to authenticated using(private.current_user_role()='administrador' or role=(select coalesce(p.access_profile,p.role) from public.profiles p where p.id=auth.uid()));
create policy action_rights_admin on public.erp_action_permissions for all to authenticated using(private.current_user_role()='administrador') with check(private.current_user_role()='administrador');
create index action_rights_actor on public.erp_action_permissions(updated_by);
create trigger erp_audit_capture after insert or update or delete on public.erp_action_permissions for each row execute function private.erp_audit_capture();
create function private.erp_action_allowed(p_module text,p_action text) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select p.active and private.erp_mfa_ok() and coalesce(case p_action when 'create' then a.allow_create when 'edit' then a.allow_edit when 'delete' then a.allow_delete when 'validate' then a.allow_validate when 'export' then a.allow_export else false end,true) from public.profiles p left join public.erp_action_permissions a on a.role=coalesce(p.access_profile,p.role) and a.module=p_module where p.id=auth.uid()),false)
$$;
revoke all on function private.erp_action_allowed(text,text) from public,anon;grant execute on function private.erp_action_allowed(text,text) to authenticated;
create function public.gama_action_allowed(p_module text,p_action text) returns boolean language sql stable security invoker set search_path='' as $$select private.erp_action_allowed(p_module,p_action)$$;
revoke all on function public.gama_action_allowed(text,text) from public,anon;grant execute on function public.gama_action_allowed(text,text) to authenticated;
create function private.erp_action_guard() returns trigger language plpgsql security definer set search_path='' as $$declare action text:=case tg_op when 'INSERT' then 'create' when 'DELETE' then 'delete' else 'edit' end;n jsonb;o jsonb;begin
 if auth.uid() is null then if tg_op='DELETE' then return old;else return new;end if;end if;
 if not private.erp_action_allowed(tg_argv[0],action) then raise exception 'ACTION_NOT_ALLOWED:%:%',tg_argv[0],action;end if;
 if tg_op in ('INSERT','UPDATE') then n:=to_jsonb(new);o:=case when tg_op='UPDATE' then to_jsonb(old) else '{}'::jsonb end;
 if ((n->>'status' is distinct from o->>'status' and n->>'status' in ('accepted','confirmed','posted','approved','validated','closed','received','completed','Entregada','Terminada')) or (n->>'quote_state' is distinct from o->>'quote_state' and n->>'quote_state' in ('sent','accepted'))) and not private.erp_action_allowed(tg_argv[0],'validate') then raise exception 'ACTION_NOT_ALLOWED:%:validate',tg_argv[0];end if;
 end if;if tg_op='DELETE' then return old;else return new;end if;
end $$;
revoke all on function private.erp_action_guard() from public,anon,authenticated;
do $$declare r record;begin for r in select * from (values
 ('products','products'),('product_units','products'),('customers','clients'),('customer_addresses','clients'),('suppliers','suppliers'),('supplier_product_offers','suppliers'),
 ('crm_leads','crm'),('crm_opportunities','crm'),('crm_contacts','crm'),('crm_activities','crm'),('invoices','quotes'),('invoice_lines','quotes'),('sales_orders','sales-orders'),('sales_order_lines','sales-orders'),
 ('purchase_orders','gamaPurchasesV14'),('purchase_order_lines','gamaPurchasesV14'),('stock_movements','movement'),('inventory_counts','warehouses'),('inventory_count_lines','warehouses'),
 ('customer_receipts','payments'),('external_invoice_payments','payments'),('receivable_followups','payments'),('service_tickets','sav'),('service_messages','sav'),('business_documents','documents'),
 ('expenses','accounting'),('supplier_invoices','accounting'),('supplier_invoice_payments','accounting'),('return_orders','returns'),('return_refunds','returns'),('hr_employees','hr'),('hr_absences','hr'),('hr_lifecycle_tasks','hr'),('pm_projects','projects'),('pm_items','projects'),('pm_cost_entries','projects'),('tms_routes','tms'),('tms_deliveries','tms'),('fleet_vehicles','fleet'))m(tbl,module) loop
 if to_regclass('public.'||r.tbl) is not null then execute format('create trigger erp_action_guard before insert or update or delete on public.%I for each row execute function private.erp_action_guard(%L)',r.tbl,r.module);end if;end loop;end $$;
-- Direct stock routines predate the common role helper. Gate all authenticated
-- public PL/pgSQL security-definer entrypoints before their first statement.
do $$declare r record;src text;begin for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang where n.nspname='public' and p.prokind='f' and p.prosecdef and l.lanname='plpgsql' and has_function_privilege('authenticated',p.oid,'EXECUTE') loop
 src:=pg_get_functiondef(r.oid);src:=regexp_replace(src,'\mBEGIN\M',E'BEGIN\n IF auth.uid() IS NOT NULL AND NOT private.erp_mfa_ok() THEN RAISE EXCEPTION ''MFA_REQUIRED''; END IF;','i');execute src;
 end loop;end $$;
-- An inactive/AAL1 account must not recover permissions through an accounting override.
do $$declare src text;begin select pg_get_functiondef('private.gama_accounting_rights()'::regprocedure) into src;src:=replace(src,' select * into p from public.accounting_permissions', ' if r='''' then return rights;end if; select * into p from public.accounting_permissions');execute src;end $$;

create function private.erp_timezone() returns text language sql stable security definer set search_path='' as $$select coalesce((select timezone from public.erp_policies where id),'America/Guayaquil')$$;
revoke all on function private.erp_timezone() from public,anon;grant execute on function private.erp_timezone() to authenticated;
-- Replace hard-coded reporting timezone expressions, retaining source timestamps.
do $$declare r record;src text;opts text;begin
 for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang where n.nspname in ('private','public') and p.prokind='f' and l.lanname in ('plpgsql','sql') and p.proname<>'erp_timezone' and position('''America/Guayaquil''' in p.prosrc)>0 loop
 src:=pg_get_functiondef(r.oid);src:=replace(src,'''America/Guayaquil''','private.erp_timezone()');src:=replace(src,'IMMUTABLE','STABLE');execute src;end loop;
 for r in select c.oid,n.nspname,c.relname,c.reloptions from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('private','public') and c.relkind='v' loop
 src:=pg_get_viewdef(r.oid,true);if position('''America/Guayaquil''' in src)>0 then
 opts:=case when r.reloptions is null then '' else ' with ('||array_to_string(r.reloptions,',')||')' end;
 execute format('create or replace view %I.%I%s as %s',r.nspname,r.relname,opts,replace(src,'''America/Guayaquil''','private.erp_timezone()'));end if;end loop;
end $$;
-- Surface the same timezone to every client through the safe company profile.
do $$declare src text;begin select pg_get_functiondef('private.gama_company_public(public.company_settings)'::regprocedure) into src;src:=replace(src,'IMMUTABLE','STABLE');src:=replace(src,'''legal_name'',c.legal_name','''timezone'',private.erp_timezone(),''legal_name'',c.legal_name');execute src;end $$;

create function private.gama_closing_review(p_month date) returns jsonb language plpgsql stable security definer set search_path='' as $$declare rights jsonb:=private.gama_accounting_rights();first date:=date_trunc('month',p_month)::date;last date:=(date_trunc('month',p_month)+interval '1 month - 1 day')::date;begin
 if not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 return jsonb_build_object('from',first,'to',last,'draft_entries',(select count(*) from public.accounting_entries where entry_date between first and last and status='draft'),
 'unposted_invoices',(select count(*) from public.external_invoices i where i.issue_date between first and last and i.fiscal_status not in ('cancelled','rejected') and not exists(select 1 from public.accounting_entries e where e.source_type='sales_invoice' and e.source_id=i.id and e.status='posted')),
 'unposted_payments',(select count(*) from public.external_invoice_payments p where p.paid_at between first and last and p.status='confirmed' and not exists(select 1 from public.accounting_entries e where e.source_type='customer_payment' and e.source_id=p.id and e.status='posted')),
 'unmatched_bank',(select count(*) from public.bank_transactions where value_date between first and last and status='unmatched'),
 'unmatched_bills',(select count(*) from public.supplier_invoices b where b.issue_date between first and last and b.status='posted' and b.purchase_order_id is not null and b.match_required and not exists(select 1 from public.supplier_invoice_matches m where m.invoice_id=b.id)),
 'unassigned_payments',(select count(*) from public.external_invoice_payments where paid_at between first and last and status='confirmed' and financial_account_id is null));
end $$;
revoke all on function private.gama_closing_review(date) from public,anon;grant execute on function private.gama_closing_review(date) to authenticated;
create function public.gama_closing_review(p_month date) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_closing_review(p_month)$$;
revoke all on function public.gama_closing_review(date) from public,anon;grant execute on function public.gama_closing_review(date) to authenticated;
create function private.erp_closing_guard() returns trigger language plpgsql security definer set search_path='' as $$declare checks jsonb;begin
 if new.status='closed' and old.status<>'closed' and auth.uid() is not null then
 if not private.erp_action_allowed('accounting','validate') then raise exception 'ACTION_NOT_ALLOWED:accounting:validate';end if;
 checks:=private.gama_closing_review(new.period_start);
 if (checks->>'draft_entries')::int+(checks->>'unposted_invoices')::int+(checks->>'unposted_payments')::int>0 then raise exception 'CLOSING_POSTINGS_REQUIRED';end if;
 end if;return new;end $$;
revoke all on function private.erp_closing_guard() from public,anon,authenticated;
create trigger erp_closing_guard before update on public.accounting_periods for each row execute function private.erp_closing_guard();
