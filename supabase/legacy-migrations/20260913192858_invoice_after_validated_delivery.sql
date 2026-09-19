-- Invoice eligibility uses delivered quantities with a signed proof for every line.
create function private.gama_order_delivery_validated(p_order uuid)
returns boolean language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.sales_order_lines where order_id=p_order)
 and not exists(
  select 1 from public.sales_order_lines l where l.order_id=p_order
  and l.quantity > coalesce((
   select sum(dl.quantity) from public.sales_delivery_lines dl
   join public.sales_deliveries sd on sd.id=dl.delivery_id and sd.order_id=p_order
   join public.tms_deliveries td on td.id=sd.tms_delivery_id
   where dl.order_line_id=l.id and td.status='Entregada'
   and exists(select 1 from public.tms_proofs p where p.delivery_id=td.id and nullif(btrim(p.signature),'') is not null)
  ),0)
 );
$$;
revoke all on function private.gama_order_delivery_validated(uuid) from public,anon,authenticated;

do $migration$
declare src text;anchor text;
begin
 select pg_get_functiondef('private.gama_internal_invoice_action(text,jsonb)'::regprocedure) into src;
 anchor:='if p_action=''report'' then';
 if strpos(src,anchor)=0 then raise exception 'INVOICE_REPORT_ANCHOR_MISSING';end if;
 src:=replace(src,anchor,$patch$if p_action='eligibility' then
  return coalesce((select jsonb_agg(jsonb_build_object(
   'quote_id',quote_row.id,'order_id',order_row.id,
   'invoice_id',(select f.id from public.external_invoices f where f.source_quote_id=quote_row.id and f.document_kind='internal' and f.fiscal_status<>'cancelled' limit 1),
   'ready',quote_row.quote_state='accepted' and order_row.status='confirmed' and private.gama_order_delivery_validated(order_row.id)
  )) from public.invoices quote_row left join public.sales_orders order_row on order_row.source_quote_id=quote_row.id
   where quote_row.id in (select value::uuid from jsonb_array_elements_text(p_data->'quote_ids'))),'[]'::jsonb);
 elsif p_action='report' then$patch$);
 anchor:='if found then return to_jsonb(i);end if;';
 if strpos(src,anchor)=0 then raise exception 'INVOICE_CREATE_ANCHOR_MISSING';end if;
 src:=replace(src,anchor,anchor||$patch$
  if not private.gama_order_delivery_validated(o.id) then raise exception 'DELIVERY_VALIDATION_REQUIRED';end if;
$patch$);
 execute src;
end $migration$;
