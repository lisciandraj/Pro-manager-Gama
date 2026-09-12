-- One financial ledger: internal invoices and external-only records never duplicate amounts.
alter table public.external_invoices
 add column document_kind text not null default 'external' check(document_kind in ('external','internal')),
 add column source_quote_id uuid references public.invoices(id),
 add column document_snapshot jsonb,
 add column external_number text check(length(btrim(external_number)) between 1 and 80),
 add column external_issue_date date,
 add column external_status text check(external_status in ('unverified','authorized','rejected','cancelled'));
alter table public.external_invoices alter column issuer_ruc drop not null;
alter table public.external_invoices add constraint invoice_kind_integrity check(
 (document_kind='external' and issuer_ruc is not null and source_quote_id is null and external_number is null)
 or (document_kind='internal' and source_quote_id is not null and document_snapshot is not null and fiscal_status in ('unverified','cancelled')
 and (external_number is null or (issuer_ruc is not null and external_issue_date is not null and external_status is not null)))
);
create index internal_invoice_quote_idx on public.external_invoices(source_quote_id) where source_quote_id is not null;
create unique index one_live_internal_invoice_per_quote on public.external_invoices(source_quote_id) where document_kind='internal' and fiscal_status<>'cancelled';
create unique index invoice_external_identity on public.external_invoices(issuer_ruc,(case when document_kind='external' then number else external_number end)) where document_kind='external' or external_number is not null;
create unique index internal_invoice_number_unique on public.external_invoices(number) where document_kind='internal';
create sequence private.gama_internal_invoice_number;
revoke all on sequence private.gama_internal_invoice_number from public,anon,authenticated;

create function private.gama_internal_invoice_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();oid uuid;q public.invoices;o public.sales_orders;i public.external_invoices;s numeric;t numeric;items jsonb;issue date;due date;n text;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if coalesce(private.current_user_role(),'') not in ('administrador','comercial') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='report' then
  return coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'number',f.number,'date',f.issue_date::text||'T12:00:00','total',f.total,'pay',coalesce(f.document_snapshot#>>'{details,payment}','No especificado'),'items',coalesce((select jsonb_agg(jsonb_build_object('product_id',ol.product_id,'barcode',pr.barcode,'qty',il.quantity,'price',ol.unit_price,'name',ol.product_name,'category',pr.category)) from public.external_invoice_lines il join public.sales_order_lines ol on ol.id=il.order_line_id left join public.products pr on pr.id=ol.product_id where il.invoice_id=f.id),'[]'::jsonb)) order by f.issue_date,f.id) from public.external_invoices f where f.fiscal_status not in ('cancelled','rejected')),'[]'::jsonb);
 elsif p_action='create' then
  select * into q from public.invoices where id=(p_data->>'quote_id')::uuid for update;
  if not found or q.quote_state is distinct from 'accepted' then raise exception 'QUOTE_NOT_ACCEPTED';end if;
  select * into o from public.sales_orders where source_quote_id=q.id for update;
  if not found or o.status<>'confirmed' then raise exception 'CONFIRM_ORDER_FIRST';end if;
  select * into i from public.external_invoices where source_quote_id=q.id and document_kind='internal' and fiscal_status<>'cancelled';
  if found then return to_jsonb(i);end if;
  if exists(select 1 from public.external_invoices where order_id=o.id and fiscal_status not in ('cancelled','rejected')) then raise exception 'ORDER_ALREADY_INVOICED';end if;
  issue:=coalesce(nullif(p_data->>'issue_date','')::date,(now() at time zone 'America/Guayaquil')::date);due:=nullif(p_data->>'due_date','')::date;
  if due<issue then raise exception 'INVALID_DUE_DATE';end if;
  select sum(round(quantity*unit_price,2)),sum(round(round(quantity*unit_price,2)*tax_rate/100,2)),
   jsonb_agg(jsonb_build_object('line_id',id,'product_id',product_id,'name',product_name,'reference',reference,'qty',quantity,'price',unit_price,'listPrice',coalesce((select ql.quote_list_price from public.invoice_lines ql where ql.invoice_id=q.id and ql.product_id=sales_order_lines.product_id limit 1),unit_price),'discount',coalesce((select ql.quote_discount from public.invoice_lines ql where ql.invoice_id=q.id and ql.product_id=sales_order_lines.product_id limit 1),0),'taxRate',tax_rate,'subtotal',round(quantity*unit_price,2),'tax',round(round(quantity*unit_price,2)*tax_rate/100,2)) order by id)
   into s,t,items from public.sales_order_lines where order_id=o.id;
  if items is null then raise exception 'INVALID_LINES';end if;
  if s<>q.subtotal or t<>q.tax then raise exception 'QUOTE_ORDER_MISMATCH';end if;
  n:='FI-'||to_char(issue,'YYYY')||'-'||lpad(nextval('private.gama_internal_invoice_number')::text,8,'0');
  insert into public.external_invoices(request_key,order_id,number,issuer_ruc,software,issue_date,due_date,subtotal,tax,fiscal_status,notes,created_by,document_kind,source_quote_id,document_snapshot)
  values(gen_random_uuid(),o.id,n,null,'GAMA ERP',issue,due,s,t,'unverified','Factura interna de gestión. Sin validez fiscal.',u,'internal',q.id,
   jsonb_build_object('details',q.quote_details,'quote_number',q.invoice_number,'quote_revision',q.quote_revision,'accepted_at',q.quote_accepted_at,'order_number',o.number,'customer',o.customer_name,'customer_identification',o.customer_identification,'lines',items,'original_quote_lines',(select jsonb_agg(to_jsonb(l) order by l.id) from public.invoice_lines l where l.invoice_id=q.id))) returning * into i;
  insert into public.external_invoice_lines(invoice_id,order_line_id,quantity) select i.id,id,quantity from public.sales_order_lines where order_id=o.id;
  insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(o.id,'internal_invoice',i.id,u,jsonb_build_object('number',n,'quote_id',q.id,'total',i.total));
 elsif p_action='link_external' then
  -- Same lock order as the existing sales/payment workflows.
  select order_id into oid from public.external_invoices where id=(p_data->>'invoice_id')::uuid;
  select * into o from public.sales_orders where id=oid for update;
  select * into i from public.external_invoices where id=(p_data->>'invoice_id')::uuid and document_kind='internal' for update;
  if not found then raise exception 'INVOICE_NOT_FOUND';end if;
  if i.fiscal_status='cancelled' then raise exception 'INVOICE_CLOSED';end if;
  if nullif(btrim(p_data->>'number'),'') is null or nullif(btrim(p_data->>'issuer_ruc'),'') is null or nullif(btrim(p_data->>'software'),'') is null or nullif(p_data->>'issue_date','') is null then raise exception 'EXTERNAL_REFERENCE_REQUIRED';end if;
  if p_data->>'customer_identification' is distinct from i.document_snapshot->>'customer_identification' then raise exception 'CUSTOMER_MISMATCH';end if;
  if (p_data->>'subtotal')::numeric is distinct from i.subtotal or (p_data->>'tax')::numeric is distinct from i.tax then raise exception 'AMOUNT_MISMATCH';end if;
  if i.external_number is not null and (i.external_number<>btrim(p_data->>'number') or i.issuer_ruc<>btrim(p_data->>'issuer_ruc')) then raise exception 'EXTERNAL_ALREADY_LINKED';end if;
  update public.external_invoices set external_number=btrim(p_data->>'number'),issuer_ruc=btrim(p_data->>'issuer_ruc'),software=btrim(p_data->>'software'),external_issue_date=(p_data->>'issue_date')::date,external_status=coalesce(p_data->>'status','unverified'),access_key=nullif(btrim(p_data->>'access_key'),''),updated_at=now() where id=i.id returning * into i;
  insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(i.order_id,'internal_external_link',i.id,u,jsonb_build_object('number',i.external_number,'status',i.external_status));
 else raise exception 'INVALID_ACTION';end if;
 return to_jsonb(i);
end $$;
revoke all on function private.gama_internal_invoice_action(text,jsonb) from public,anon;
grant execute on function private.gama_internal_invoice_action(text,jsonb) to authenticated;
create function public.gama_internal_invoice_action(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_internal_invoice_action(p_action,p_data)$$;
revoke all on function public.gama_internal_invoice_action(text,jsonb) from public,anon;
grant execute on function public.gama_internal_invoice_action(text,jsonb) to authenticated;

create function private.gama_internal_invoice_cancel_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.document_kind='internal' and new.fiscal_status='cancelled' and old.fiscal_status<>'cancelled'
 and exists(select 1 from public.external_invoice_payments where invoice_id=old.id and status='confirmed') then raise exception 'CANCEL_PAYMENTS_FIRST';end if;
 return new;
end $$;
revoke all on function private.gama_internal_invoice_cancel_guard() from public,anon,authenticated;
create trigger internal_invoice_cancel_guard before update on public.external_invoices for each row execute function private.gama_internal_invoice_cancel_guard();
