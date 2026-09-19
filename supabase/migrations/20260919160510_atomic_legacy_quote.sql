-- The legacy quote form used to insert a header then each line in separate transactions.
-- Keep its document contract while making the operation atomic and safe to retry.
create table private.command_receipts (
 domain text not null,
 request_key uuid not null,
 actor_id uuid not null references auth.users(id),
 payload jsonb not null,
 result jsonb not null,
 created_at timestamptz not null default now(),
 primary key(domain,request_key)
);
alter table private.command_receipts enable row level security;
revoke all on private.command_receipts from public,anon,authenticated;

create or replace function private.gama_legacy_quote_save(p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid(); request uuid:=nullif(p_data->>'request_key','')::uuid;
 customer public.customers; product public.products; invoice public.invoices;
 receipt private.command_receipts; line jsonb; quantity numeric; price numeric; rate numeric;
 v_subtotal numeric:=0; taxes numeric:=0; net numeric; vat numeric; result jsonb;
 payload jsonb:=p_data-'request_key';
begin
 if actor is null then raise exception 'AUTH_REQUIRED';end if;
 if private.current_user_role() not in ('administrador','comercial') or private.current_user_role() is null then raise exception 'ROLE_NOT_ALLOWED';end if;
 if request is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('legacy_quote:'||request::text,0));
 select * into receipt from private.command_receipts where domain='legacy_quote' and request_key=request;
 if found then
  if receipt.actor_id<>actor or receipt.payload<>payload then raise exception 'REQUEST_KEY_REUSED';end if;
  return receipt.result;
 end if;
 select * into customer from public.customers where id=(p_data->>'customer_id')::uuid and active;
 if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 if jsonb_typeof(p_data->'lines') is distinct from 'array' then raise exception 'INVALID_LINES';end if;
 if jsonb_array_length(p_data->'lines') not between 1 and 500 then raise exception 'INVALID_LINES';end if;
 insert into public.invoices(customer_id,user_id,status,quote_state,quote_request_key,quote_details,notes)
 values(customer.id,actor,'issued','draft',request,coalesce(p_data->'details','{}'),nullif(p_data->>'notes','')) returning * into invoice;
 for line in select value from jsonb_array_elements(p_data->'lines') loop
  select * into product from public.products where id=(line->>'product_id')::uuid and active;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  quantity:=(line->>'quantity')::numeric;price:=(line->>'unit_price')::numeric;rate:=(line->>'tax_rate')::numeric;
  if quantity is null or quantity<=0 or quantity>99999999999 or quantity<>round(quantity,3) then raise exception 'INVALID_QUANTITY';end if;
  if price is null or price<0 or price>99999999999 or price<>round(price,2) then raise exception 'INVALID_PRICE';end if;
  if rate is null or rate<0 or rate>100 or rate<>round(rate,3) then raise exception 'INVALID_TAX';end if;
  net:=round(quantity*price,2);vat:=round(net*rate/100,2);
  insert into public.invoice_lines(invoice_id,product_id,quantity,unit_price,tax_rate,line_total)
  values(invoice.id,product.id,quantity,price,rate,net+vat);
  v_subtotal:=v_subtotal+net;taxes:=taxes+vat;
 end loop;
 update public.invoices set invoice_number='COT-'||lpad(invoice.archive_number::text,9,'0'),subtotal=v_subtotal, tax=taxes, total=v_subtotal+taxes where id=invoice.id returning * into invoice;
 result:=jsonb_build_object('id',invoice.id,'number',invoice.invoice_number,'date',invoice.issue_date,'subtotal',invoice.subtotal,'tax',invoice.tax,'total',invoice.total);
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('legacy_quote',request,actor,payload,result);
 return result;
end $$;
revoke all on function private.gama_legacy_quote_save(jsonb) from public,anon;
grant execute on function private.gama_legacy_quote_save(jsonb) to authenticated;
create or replace function public.gama_legacy_quote_save(p_data jsonb)
returns jsonb language sql security invoker set search_path='' as $$ select private.gama_legacy_quote_save(p_data) $$;
revoke all on function public.gama_legacy_quote_save(jsonb) from public,anon;
grant execute on function public.gama_legacy_quote_save(jsonb) to authenticated;
