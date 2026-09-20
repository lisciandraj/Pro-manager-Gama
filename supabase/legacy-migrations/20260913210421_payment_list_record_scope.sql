-- Keep the detail record distinct from the SQL relation alias in the list branch.
create or replace function private.gama_payment_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;invoice_record record;off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 if coalesce(private.current_user_role(),'') not in ('administrador','comercial') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('payment','cancel_payment') then
  return private.gama_commercial_action(p_action,p_data);
 elsif p_action in ('detail','reminder') then
  select * into invoice_record from private.gama_receivables where id=(p_data->>'invoice_id')::uuid;
  if not found then raise exception 'INVOICE_NOT_FOUND';end if;
  if p_action='reminder' and invoice_record.payment_status not in ('due_soon','overdue') then raise exception 'REMINDER_NOT_DUE';end if;
  return to_jsonb(invoice_record)||jsonb_build_object(
   'lines',coalesce((select jsonb_agg(jsonb_build_object('name',l.product_name,'reference',l.reference,'quantity',il.quantity,'unit_price',l.unit_price,'tax_rate',l.tax_rate) order by il.id)
    from public.external_invoice_lines il join public.sales_order_lines l on l.id=il.order_line_id where il.invoice_id=invoice_record.id),'[]'::jsonb),
   'payments',coalesce((select jsonb_agg(to_jsonb(p) order by p.paid_at desc,p.created_at desc) from public.external_invoice_payments p where p.invoice_id=invoice_record.id),'[]'::jsonb));
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
