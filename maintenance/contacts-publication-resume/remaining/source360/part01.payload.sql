-- Read-only, reviewed collection preparation. No outbox entry is created or sent.
-- It shares the accounting maturity balances and the existing collection holds.
create function private.coco_collection_preview_rows(p_customer uuid default null)
returns table(invoice_id uuid,customer_id uuid,customer_name text,number text,due_date date,balance numeric,eligible_amount numeric,exclusion text)
language sql stable security invoker set search_path='' as $$
 with invoices as (
  select d.document_id,d.customer_id,d.customer_name,d.number,min(d.due_date) due_date,
   sum(d.balance) balance,coalesce(sum(d.balance) filter(where d.due_date<(now() at time zone private.erp_timezone())::date),0) overdue
  from private.gama_customer_dues(p_customer) d where d.balance>0
  group by d.document_id,d.customer_id,d.customer_name,d.number
 ),classified as (
  select d.document_id,d.customer_id,c.name customer_name,d.number,d.due_date,d.balance,d.overdue,case
   when not c.active then 'inactive_customer'
   when not coalesce(p.invoice_reminders,false) then 'preference'
   when coalesce(c.email,'')!~'^[^\s@<>;,?]+@[^\s@<>;,?]+\.[^\s@<>;,?]+$' then 'email'
   when h.disputed then 'dispute'
   when h.promise_date>=(now() at time zone private.erp_timezone())::date then 'promise'
   when h.suspend_until>=(now() at time zone private.erp_timezone())::date then 'suspended'
   when d.due_date is null then 'missing_due'
   when d.overdue<=0 then 'not_due'
   else null end reason
  from invoices d join public.customers c on c.id=d.customer_id
  left join private.customer_message_preferences p on p.customer_id=d.customer_id
  left join private.collection_holds h on h.invoice_id=d.document_id
 )
 select document_id,customer_id,customer_name,number,due_date,balance,
  case when reason is null then overdue else 0 end,reason from classified
$$;
revoke all on function private.coco_collection_preview_rows(uuid) from public,anon,authenticated,service_role;

create function private.gama_collections_preview(p_customer uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;today date:=(now() at time zone private.erp_timezone())::date;
 off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
 search text:=left(coalesce(p_data->>'search',''),120);begin
 if auth.uid() is null or not private.erp_mfa_ok()
  or not private.erp_module_allowed('payments',array['administrador','comercial'])
  or not private.erp_action_allowed('payments','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_customer is not null then
  if not exists(select 1 from public.customers where id=p_customer) then raise exception 'CUSTOMER_REQUIRED';end if;
  with rows as(select * from private.coco_collection_preview_rows(p_customer))
  select jsonb_build_object('today',today,
   'customer',(select jsonb_build_object('id',c.id,'name',c.name) from public.customers c where c.id=p_customer),
   'currency',(select currency from public.company_settings where id),
   'total',coalesce((select sum(eligible_amount) from rows),0),
   'eligible_count',(select count(*) from rows where eligible_amount>0),
   'excluded_count',(select count(*) from rows where exclusion is not null),
   'complete',(select count(*)<=1000 from rows),
   'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.due_date nulls last,z.invoice_id)
    from(select invoice_id,number,due_date,balance,eligible_amount,exclusion from rows order by due_date nulls last,invoice_id limit 1000)z),'[]'::jsonb)) into result;
 else
  with grouped as(
   select customer_id id,customer_name name,sum(eligible_amount) total,
    count(*) filter(where eligible_amount>0) eligible_count,count(*) filter(where exclusion is not null) excluded_count,
    min(due_date) oldest_due
   from private.coco_collection_preview_rows(null) where customer_name ilike '%'||search||'%'
   group by customer_id,customer_name
  )
  select jsonb_build_object('today',today,'currency',(select currency from public.company_settings where id),
   'total',(select count(*) from grouped),
   'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.oldest_due nulls last,z.id)
    from(select * from grouped order by oldest_due nulls last,id offset off limit 30)z),'[]'::jsonb)) into result;
 end if;
 return result;
end $$;
create function public.gama_collections_preview(p_customer uuid default null,p_data jsonb default '{}')
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.gama_collections_preview(p_customer,p_data)
$$;
revoke all on function private.gama_collections_preview(uuid,jsonb),public.gama_collections_preview(uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.gama_collections_preview(uuid,jsonb),public.gama_collections_preview(uuid,jsonb) to authenticated;
