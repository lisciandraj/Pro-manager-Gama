-- Customer collections use the existing invoice/payment ledger. No duplicate amounts.
alter table public.customers add column payment_terms_days integer
 check(payment_terms_days between 0 and 3650);
alter table public.external_invoices
 add column payment_terms_days integer check(payment_terms_days between 0 and 3650),
 add column payment_delivery_date date;
-- A late-issued invoice can already be overdue: the clock starts at delivery.
alter table public.external_invoices drop constraint external_invoices_check;

create function private.gama_set_invoice_payment_due() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.payment_terms_days is null then
  select c.payment_terms_days into new.payment_terms_days from public.sales_orders o
  join public.customers c on c.id=o.customer_id where o.id=new.order_id;
 end if;
 -- Internal invoices cover the whole order. External invoices use their explicit links.
 select case when count(*)>0 and bool_and(t.status='Entregada' and t.delivered_at is not null
   and exists(select 1 from public.tms_proofs p where p.delivery_id=t.id and nullif(p.signature,'') is not null))
  then max((t.delivered_at at time zone 'America/Guayaquil')::date) end
 into new.payment_delivery_date
 from public.sales_deliveries s left join public.tms_deliveries t on t.id=s.tms_delivery_id
 where s.order_id=new.order_id and (new.document_kind='internal' or exists(
  select 1 from public.external_invoice_deliveries l where l.invoice_id=new.id and l.delivery_id=s.id));
 new.due_date:=new.payment_delivery_date+new.payment_terms_days;
 return new;
end $$;
revoke all on function private.gama_set_invoice_payment_due() from public,anon,authenticated;
create trigger invoice_payment_due before insert or update on public.external_invoices
 for each row execute function private.gama_set_invoice_payment_due();

create function private.gama_refresh_invoice_payment_due() returns trigger
language plpgsql security definer set search_path='' as $$
declare oid uuid;tid uuid;iid uuid;
begin
 if tg_table_name='customers' then
  if new.payment_terms_days is not distinct from old.payment_terms_days then return new;end if;
  update public.external_invoices i set payment_terms_days=new.payment_terms_days
  from public.sales_orders o where o.id=i.order_id and o.customer_id=new.id
  and i.fiscal_status not in ('cancelled','rejected')
  and i.total>coalesce((select sum(p.amount) from public.external_invoice_payments p where p.invoice_id=i.id and p.status='confirmed'),0);
 elsif tg_table_name='external_invoice_deliveries' then
  iid:=case when tg_op='DELETE' then old.invoice_id else new.invoice_id end;
  update public.external_invoices set updated_at=now() where id=iid;
 elsif tg_table_name='sales_deliveries' then
  oid:=case when tg_op='DELETE' then old.order_id else new.order_id end;
  update public.external_invoices set updated_at=now() where order_id=oid;
 else
  if tg_table_name='tms_proofs' then tid:=case when tg_op='DELETE' then old.delivery_id else new.delivery_id end;
  else tid:=new.id;end if;
  update public.external_invoices i set updated_at=now() where exists(
   select 1 from public.sales_deliveries s where s.order_id=i.order_id and s.tms_delivery_id=tid);
 end if;
 return coalesce(new,old);
end $$;
revoke all on function private.gama_refresh_invoice_payment_due() from public,anon,authenticated;
create trigger customer_payment_terms after update of payment_terms_days on public.customers
 for each row execute function private.gama_refresh_invoice_payment_due();
create trigger invoice_delivery_payment_due after insert or update or delete on public.external_invoice_deliveries
 for each row execute function private.gama_refresh_invoice_payment_due();
create trigger sales_delivery_payment_due after insert or update of tms_delivery_id or delete on public.sales_deliveries
 for each row execute function private.gama_refresh_invoice_payment_due();
create trigger tms_delivery_payment_due after update of status,delivered_at on public.tms_deliveries
 for each row execute function private.gama_refresh_invoice_payment_due();
create trigger tms_proof_payment_due after insert or update of signature or delete on public.tms_proofs
 for each row execute function private.gama_refresh_invoice_payment_due();
update public.external_invoices set payment_terms_days=null;

create view private.gama_receivables with(security_invoker=true) as
select i.id,i.order_id,i.number,i.external_number,i.document_kind,i.fiscal_status,i.issue_date,
 i.subtotal,i.tax,i.total,i.payment_terms_days,i.payment_delivery_date,i.due_date,
 o.number order_number,o.customer_id,o.customer_name,c.identification,c.email,
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
left join public.customers c on c.id=o.customer_id
left join (select invoice_id,sum(amount) paid from public.external_invoice_payments where status='confirmed' group by invoice_id) p on p.invoice_id=i.id;
revoke all on private.gama_receivables from public,anon,authenticated;

create function private.gama_payment_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;r record;off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 if coalesce(private.current_user_role(),'') not in ('administrador','comercial') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('payment','cancel_payment') then
  return private.gama_commercial_action(p_action,p_data);
 elsif p_action in ('detail','reminder') then
  select * into r from private.gama_receivables where id=(p_data->>'invoice_id')::uuid;
  if not found then raise exception 'INVOICE_NOT_FOUND';end if;
  if p_action='reminder' and r.payment_status not in ('due_soon','overdue') then raise exception 'REMINDER_NOT_DUE';end if;
  return to_jsonb(r)||jsonb_build_object(
   'lines',coalesce((select jsonb_agg(jsonb_build_object('name',l.product_name,'reference',l.reference,'quantity',il.quantity,'unit_price',l.unit_price,'tax_rate',l.tax_rate) order by il.id)
    from public.external_invoice_lines il join public.sales_order_lines l on l.id=il.order_line_id where il.invoice_id=r.id),'[]'::jsonb),
   'payments',coalesce((select jsonb_agg(to_jsonb(p) order by p.paid_at desc,p.created_at desc) from public.external_invoice_payments p where p.invoice_id=r.id),'[]'::jsonb));
 elsif p_action<>'list' then raise exception 'INVALID_ACTION';end if;
 with filtered as (select * from private.gama_receivables r
  where (nullif(p_data->>'order_id','') is null or r.order_id=(p_data->>'order_id')::uuid)
  and (nullif(p_data->>'customer_id','') is null or r.customer_id=(p_data->>'customer_id')::uuid)
  and (coalesce(p_data->>'status','open')='all'
   or (coalesce(p_data->>'status','open')='open' and r.payment_status not in ('paid','cancelled'))
   or r.payment_status=p_data->>'status')
  and (coalesce(p_data->>'search','')='' or concat_ws(' ',r.number,r.external_number,r.customer_name,r.order_number) ilike '%'||(p_data->>'search')||'%'))
 select jsonb_build_object('total',count(*),'metrics',jsonb_build_object(
  'total',coalesce(sum(total) filter(where payment_status<>'cancelled'),0),
  'paid',coalesce(sum(paid) filter(where payment_status<>'cancelled'),0),
  'balance',coalesce(sum(balance) filter(where payment_status<>'cancelled'),0),
  'due_soon',coalesce(sum(balance) filter(where payment_status='due_soon'),0),
  'overdue',coalesce(sum(balance) filter(where payment_status='overdue'),0)),
  'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.due_date nulls last,z.id) from
   (select * from filtered order by due_date nulls last,id offset off limit 30) z),'[]'::jsonb)) into result from filtered;
 return result;
end $$;
revoke all on function private.gama_payment_action(text,jsonb) from public,anon;
grant execute on function private.gama_payment_action(text,jsonb) to authenticated;
create function public.gama_payment_action(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.gama_payment_action(p_action,p_data)$$;
revoke all on function public.gama_payment_action(text,jsonb) from public,anon;
grant execute on function public.gama_payment_action(text,jsonb) to authenticated;

-- Extend the existing live alert view without duplicating overdue invoices.
do $patch$
declare src text;
begin
 src:=rtrim(pg_get_viewdef('private.gama_live_alerts'::regclass,true),E';\n ');
 execute 'create or replace view private.gama_live_alerts with(security_invoker=true) as '||src||$extra$
 union all
 select 'due_soon_invoice:'||i.id,'due_soon_invoice',i.id,'invoice',i.number,i.customer_name,'Pago próximo a vencer',
 'Vencimiento: '||i.due_date||' · saldo: '||round(i.balance,2)||' USD',
 i.due_date::timestamp at time zone 'America/Guayaquil',2,true,false
 from private.gama_receivables i where i.payment_status='due_soon'
 $extra$;
end $patch$;
