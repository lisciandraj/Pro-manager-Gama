create table public.erp_approvals(
 id uuid primary key default gen_random_uuid(),module text not null check(module in ('gamaPurchasesV14','quotes','credit')),
 document_id uuid not null,fingerprint text not null,reason text not null check(length(btrim(reason))>=3),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 requested_by uuid not null default auth.uid() references auth.users(id),requested_at timestamptz not null default now(),
 reviewed_by uuid references auth.users(id),reviewed_at timestamptz,decision_reason text,
 unique(module,document_id,fingerprint)
);
alter table public.erp_approvals enable row level security;
revoke all on public.erp_approvals from public,anon,authenticated;
grant select on public.erp_approvals to authenticated;
create policy erp_approvals_read on public.erp_approvals for select to authenticated using(private.current_user_role()='administrador' or requested_by=auth.uid());
create index erp_approvals_status on public.erp_approvals(status,requested_at);
create trigger erp_audit_capture after insert or update or delete on public.erp_approvals for each row execute function private.erp_audit_capture();

create function private.erp_document_fingerprint(p_module text,p_id uuid) returns text language plpgsql stable security definer set search_path='' as $$
declare h jsonb;l jsonb;begin
 if p_module='gamaPurchasesV14' then
  select to_jsonb(p)-array['status','updated_at'] into h from public.purchase_orders p where id=p_id;
  select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]') into l from public.purchase_order_lines p where purchase_order_id=p_id;
 elsif p_module='quotes' then
  select to_jsonb(p)-array['quote_state','quote_sent_at','quote_accepted_at','quote_accepted_by','quote_acceptance_channel','quote_acceptance_reference','updated_at'] into h from public.invoices p where id=p_id;
  select coalesce(jsonb_agg(to_jsonb(ln)||jsonb_build_object('current_cost',p.purchase_price) order by ln.id),'[]') into l from public.invoice_lines ln join public.products p on p.id=ln.product_id where ln.invoice_id=p_id;
 elsif p_module='credit' then
  select to_jsonb(p)-array['status','updated_at'] into h from public.sales_orders p where id=p_id;
  select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]') into l from public.sales_order_lines p where order_id=p_id;
 else raise exception 'INVALID_MODULE';end if;
 if h is null then raise exception 'DOCUMENT_NOT_FOUND';end if;return md5(jsonb_build_object('header',h,'lines',l)::text);
end $$;
revoke all on function private.erp_document_fingerprint(text,uuid) from public,anon,authenticated;
create function private.gama_approval_action(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m text:=p_data->>'module';doc uuid:=nullif(p_data->>'document_id','')::uuid;a public.erp_approvals;fp text;begin
 if auth.uid() is null or coalesce(private.current_user_role(),'') not in ('administrador','comercial') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='request' then
  if not private.erp_module_allowed(case when m='credit' then 'sales-orders' else m end,array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  fp:=private.erp_document_fingerprint(m,doc);
  insert into public.erp_approvals(module,document_id,fingerprint,reason,requested_by) values(m,doc,fp,p_data->>'reason',auth.uid())
   on conflict(module,document_id,fingerprint) do update set reason=excluded.reason where erp_approvals.status='pending' returning * into a;
  if not found then select * into a from public.erp_approvals where module=m and document_id=doc and fingerprint=fp;end if;
  return to_jsonb(a);
 elsif p_action='decide' then
  if coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'APPROVAL_ADMIN_REQUIRED';end if;
  select * into a from public.erp_approvals where id=(p_data->>'id')::uuid for update;
  if not found or a.status<>'pending' then raise exception 'APPROVAL_NOT_PENDING';end if;
  if a.fingerprint<>private.erp_document_fingerprint(a.module,a.document_id) then raise exception 'DOCUMENT_CHANGED';end if;
  if p_data->>'decision' not in ('approved','rejected') or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  update public.erp_approvals set status=p_data->>'decision',reviewed_by=auth.uid(),reviewed_at=now(),decision_reason=p_data->>'reason' where id=a.id returning * into a;
  return to_jsonb(a);
 end if;raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_approval_action(text,jsonb) from public,anon;
grant execute on function private.gama_approval_action(text,jsonb) to authenticated;
create function public.gama_approval_action(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_approval_action(p_action,p_data)$$;
revoke all on function public.gama_approval_action(text,jsonb) from public,anon;
grant execute on function public.gama_approval_action(text,jsonb) to authenticated;

create function private.erp_commercial_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare policy public.erp_policies;m text;requires_approval boolean:=false;gross numeric;cost numeric;discount numeric;customer public.customers;exposure numeric;begin
 select * into policy from public.erp_policies where id;
 if tg_table_name='purchase_orders' then
  if new.status<>'sent' or old.status<>'draft' then return new;end if;
  m:='gamaPurchasesV14';requires_approval:=policy.purchase_approval_amount is not null and new.total>policy.purchase_approval_amount;
 elsif tg_table_name='invoices' then
  if new.quote_state not in ('sent','accepted') or new.quote_state is not distinct from old.quote_state then return new;end if;
  m:='quotes';
  select sum(l.quantity*l.unit_price),sum(l.quantity*p.purchase_price),max(coalesce(l.quote_discount,0)) into gross,cost,discount from public.invoice_lines l join public.products p on p.id=l.product_id where l.invoice_id=new.id;
  requires_approval:=(policy.quote_discount_limit is not null and coalesce(discount,0)>policy.quote_discount_limit)
   or (policy.minimum_margin is not null and (gross<=0 or 100*(gross-cost)/gross<policy.minimum_margin));
 elsif tg_table_name='sales_orders' then
  if new.status<>'confirmed' or old.status<>'draft' then return new;end if;
  m:='credit';select * into customer from public.customers where id=new.customer_id for update;
  if customer.credit_limit is null and nullif(customer.credit_hold_reason,'') is null then return new;end if;
  select coalesce(sum(greatest(0,i.total-coalesce((select sum(p.amount) from public.external_invoice_payments p where p.invoice_id=i.id and p.status='confirmed'),0)-coalesce((select sum(c.amount) from public.return_credits c where c.invoice_id=i.id),0))),0) into exposure
   from public.external_invoices i join public.sales_orders o on o.id=i.order_id where o.customer_id=customer.id and i.fiscal_status not in ('cancelled','rejected');
  select exposure+coalesce(sum(greatest(0,(select sum(l.quantity*l.unit_price*(1+l.tax_rate/100)) from public.sales_order_lines l where l.order_id=o.id)-coalesce((select sum(i.total) from public.external_invoices i where i.order_id=o.id and i.fiscal_status not in ('cancelled','rejected')),0))),0) into exposure from public.sales_orders o where o.customer_id=customer.id and (o.status='confirmed' or o.id=new.id);
  requires_approval:=nullif(customer.credit_hold_reason,'') is not null or (customer.credit_limit is not null and exposure>customer.credit_limit);
 else return new;end if;
 if requires_approval and not exists(select 1 from public.erp_approvals a where a.module=m and a.document_id=new.id and a.status='approved' and a.fingerprint=private.erp_document_fingerprint(m,new.id)) then
  raise exception 'APPROVAL_REQUIRED:%:%',m,new.id;
 end if;return new;
end $$;
revoke all on function private.erp_commercial_guard() from public,anon,authenticated;
create trigger erp_commercial_guard before update on public.purchase_orders for each row execute function private.erp_commercial_guard();
create trigger erp_commercial_guard before update on public.invoices for each row execute function private.erp_commercial_guard();
create trigger erp_commercial_guard before update on public.sales_orders for each row execute function private.erp_commercial_guard();
create function private.erp_customer_credit_guard() returns trigger language plpgsql security invoker set search_path='' as $$begin
 if auth.uid() is not null and ((tg_op='INSERT' and (new.credit_limit is not null or nullif(new.credit_hold_reason,'') is not null)) or (tg_op='UPDATE' and (new.credit_limit is distinct from old.credit_limit or new.credit_hold_reason is distinct from old.credit_hold_reason))) and coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'CREDIT_ADMIN_REQUIRED';end if;return new;end $$;
revoke all on function private.erp_customer_credit_guard() from public,anon,authenticated;
create trigger erp_customer_credit_guard before insert or update on public.customers for each row execute function private.erp_customer_credit_guard();

-- Explicit, previewable merge. Existing issued-document snapshots remain unchanged.
create function private.gama_merge_partner(p_kind text,p_source uuid,p_target uuid,p_confirm boolean default false,p_reason text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare tbl text;source jsonb;target jsonb;fk record;n integer;links jsonb:='[]';begin
 if auth.uid() is null or coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_source=p_target then raise exception 'MERGE_SAME_RECORD';end if;
 perform pg_advisory_xact_lock(hashtextextended('merge:'||p_kind,0));
 tbl:=case p_kind when 'customer' then 'customers' when 'lead' then 'crm_leads' when 'supplier' then 'suppliers' end;
 if tbl is null then raise exception 'INVALID_KIND';end if;
 if not private.erp_module_allowed(case p_kind when 'customer' then 'clients' when 'supplier' then 'suppliers' else 'crm' end,array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 execute format('select to_jsonb(t) from public.%I t where id=$1 for update',tbl) into source using p_source;
 execute format('select to_jsonb(t) from public.%I t where id=$1 for update',tbl) into target using p_target;
 if source is null or target is null or not (source->>'active')::boolean or not (target->>'active')::boolean then raise exception 'MERGE_RECORD_REQUIRED';end if;
 if p_kind='customer' and lower(coalesce(source->>'email',''))<>lower(coalesce(target->>'email',''))
  and exists(select 1 from auth.users u join public.profiles p on p.id=u.id where p.role='cliente' and lower(u.email)=lower(source->>'email')) then raise exception 'MERGE_PORTAL_IDENTITY_CONFLICT';end if;
 if p_kind='lead' and source->>'converted_customer_id' is not null and source->>'converted_customer_id' is distinct from target->>'converted_customer_id' then raise exception 'MERGE_CONVERTED_LEAD_CONFLICT';end if;
 for fk in select c.conrelid::regclass rel,a.attname col from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1] where c.contype='f' and c.confrelid=format('public.%I',tbl)::regclass and array_length(c.conkey,1)=1 loop
  execute format('select count(*) from %s where %I=$1',fk.rel,fk.col) into n using p_source;
  links:=links||jsonb_build_array(jsonb_build_object('table',fk.rel::text,'column',fk.col,'rows',n));
 end loop;
 if not p_confirm then return jsonb_build_object('source',source,'target',target,'links',links);end if;
 if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'REASON_REQUIRED';end if;
 perform set_config('architect.change_reason','Merge: '||p_reason,true);
 -- Unique collisions intentionally abort the transaction; users resolve competing
 -- contractual prices before merging instead of silently losing either record.
 for fk in select c.conrelid::regclass rel,a.attname col from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1] where c.contype='f' and c.confrelid=format('public.%I',tbl)::regclass and array_length(c.conkey,1)=1 loop
  execute format('update %s set %I=$2 where %I=$1',fk.rel,fk.col,fk.col) using p_source,p_target;
 end loop;
 execute format('update public.%I set notes=concat_ws(E''\n'',notes,$2) where id=$1',tbl) using p_target,'['||coalesce(source->>'name',source->>'company',source->>'first_name',p_source::text)||'] '||coalesce(source->>'notes','');
 execute format('update public.%I set active=false where id=$1',tbl) using p_source;
 return jsonb_build_object('source_id',p_source,'target_id',p_target,'merged',true,'links',links);
end $$;
revoke all on function private.gama_merge_partner(text,uuid,uuid,boolean,text) from public,anon;
grant execute on function private.gama_merge_partner(text,uuid,uuid,boolean,text) to authenticated;
create function public.gama_merge_partner(p_kind text,p_source uuid,p_target uuid,p_confirm boolean default false,p_reason text default null) returns jsonb language sql security invoker set search_path='' as $$select private.gama_merge_partner(p_kind,p_source,p_target,p_confirm,p_reason)$$;
revoke all on function public.gama_merge_partner(text,uuid,uuid,boolean,text) from public,anon;
grant execute on function public.gama_merge_partner(text,uuid,uuid,boolean,text) to authenticated;
