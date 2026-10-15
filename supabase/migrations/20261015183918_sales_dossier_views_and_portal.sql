-- Bounded commercial reads; accounting status and payment remain separate.
create function private.sales_invoice_board(p_data jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),1000000));
 term text:=left(coalesce(p_data->>'search',''),120);begin
 perform private.sales_access('invoice_preview');
 with candidates as(select o.*,q.invoice_number quote_reference,q.quote_details->>'customer_reference' customer_reference
  from public.sales_orders o left join public.invoices q on q.id=o.source_quote_id
  where o.status<>'cancelled'
  and (nullif(p_data->>'from','') is null or o.created_at::date>=(p_data->>'from')::date)
  and (nullif(p_data->>'to','') is null or o.created_at::date<=(p_data->>'to')::date)
  and (nullif(p_data->>'owner_id','') is null or o.created_by=(p_data->>'owner_id')::uuid)
  and (term='' or concat_ws(' ',o.number,o.customer_name,q.invoice_number,q.quote_details->>'customer_reference') ilike '%'||term||'%'
   or exists(select 1 from public.sales_order_lines l where l.order_id=o.id and concat_ws(' ',l.product_name,l.reference) ilike '%'||term||'%'))),
 amounts as(select o.id,o.number,o.quote_reference,o.customer_reference,o.customer_id,o.customer_name,o.created_by,o.created_at,o.status,
  sum(round(l.quantity*l.unit_price,2)) ordered_net,
  sum(round(greatest(0,private.sales_line_entitlement(l.id)-b.qty)*l.unit_price,2)) billable_net,
  sum(greatest(0,private.sales_line_entitlement(l.id)-b.qty)) billable_quantity,
  sum(b.qty) billed_quantity,sum(l.quantity) quantity,
  sum(least(l.quantity,coalesce(private.gama_line_performed(l.id,true),0))) delivered_quantity
  from candidates o join public.sales_order_lines l on l.order_id=o.id
  cross join lateral(select coalesce(sum(il.quantity),0) qty from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id
   where il.order_line_id=l.id and i.fiscal_status not in ('cancelled','rejected'))b
  group by o.id,o.number,o.quote_reference,o.customer_reference,o.customer_id,o.customer_name,o.created_by,o.created_at,o.status),
 filtered as(select a.*,case when a.status<>'confirmed' then 'CONFIRM_ORDER_FIRST' when billable_quantity<=0 and billed_quantity>=quantity then 'FULLY_INVOICED'
  when billable_quantity<=0 then 'DELIVERY_REQUIRED' else null end blocking_reason
  from amounts a where (coalesce(p_data->>'view','eligible')<>'eligible' or a.billable_quantity>0)
  and (coalesce(p_data->>'view','eligible')<>'partial_delivery' or (a.delivered_quantity>0 and a.delivered_quantity<a.quantity))
  and (coalesce(p_data->>'view','eligible')<>'partial_invoice' or (a.billed_quantity>0 and a.billed_quantity<a.quantity))
  and (coalesce(p_data->>'view','eligible')<>'blocked' or a.billable_quantity<=0)),
 page as(select * from filtered order by created_at desc,id offset off limit 30)
 select jsonb_build_object('actor_id',auth.uid(),'total',(select count(*) from filtered),
  'rows',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('states',private.sales_order_summary(p.id)-'invoices'-'lines') order by created_at desc,id) from page p),'[]'),
  'currency',(select currency from public.company_settings where id)) into result;return result;
end $$;

create function private.sales_metrics(p_data jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare start_date date:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',now() at time zone private.erp_timezone())::date);
 end_date date:=coalesce(nullif(p_data->>'to','')::date,(now() at time zone private.erp_timezone())::date);
 dimension text:=coalesce(p_data->>'group_by','customer');result jsonb;begin
 perform private.sales_access('invoice_preview');
 if start_date>end_date or end_date-start_date>3660 then raise exception 'INVALID_DATE';end if;
 if dimension not in ('customer','product','category','owner') then raise exception 'INVALID_DATA';end if;
 with orders as(select * from public.sales_orders where status='confirmed' and (created_at at time zone private.erp_timezone())::date between start_date and end_date),
 totals as(select o.id,sum(round(l.quantity*l.unit_price,2)) net,
  case when bool_and(d.unit_cost is not null) then sum(l.quantity*(l.unit_price-d.unit_cost)) end estimated_margin,
  sum(greatest(0,l.quantity-coalesce((select sum(il.quantity) from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('cancelled','rejected')),0))*l.unit_price) remaining_net
  from orders o join public.sales_order_lines l on l.order_id=o.id left join private.order_cost_snapshots d on d.line_id=l.id group by o.id),
 quotes as(select * from public.invoices where (issue_date at time zone private.erp_timezone())::date between start_date and end_date and quote_state not in ('cancelled','rejected')),
 posted as(select i.* from public.external_invoices i where i.issue_date between start_date and end_date and private.sales_invoice_accounting_state(i.id)='posted'),
 grouped as(select case dimension when 'product' then l.product_id::text when 'category' then coalesce(p.category,'') when 'owner' then o.created_by::text else o.customer_id::text end key,
  case dimension when 'product' then l.product_name when 'category' then coalesce(p.category,'Sin categoría') when 'owner' then coalesce(pr.full_name,'Sin responsable') else o.customer_name end name,
  sum(round(l.quantity*l.unit_price,2)) ordered_net,count(distinct o.id) orders
  from orders o join public.sales_order_lines l on l.order_id=o.id left join public.products p on p.id=l.product_id left join public.profiles pr on pr.id=o.created_by group by 1,2)
 select jsonb_build_object('from',start_date,'to',end_date,'currency',(select currency from public.company_settings where id),
 'ordered_net',(select coalesce(sum(net),0) from totals),'ordered_count',(select count(*) from orders),
 'invoiced_net',(select coalesce(sum(subtotal),0) from posted),
 'credited_net',coalesce((select sum((private.gama_return_split(c.return_id,c.amount)->>'net')::numeric) from public.return_credits c
  where c.created_at::date between start_date and end_date and exists(select 1 from public.accounting_entries e where e.source_type='return_credit' and e.source_id=c.id and e.status='posted')),0),
 'open_quotes',(select count(*) from quotes where quote_state in ('draft','sent')),
 'open_quotes_net',(select coalesce(sum(subtotal),0) from quotes where quote_state in ('draft','sent')),
 'conversion_percent',(select case when count(*)>0 then round(100.0*count(*) filter(where quote_state='accepted')/count(*),2) end from quotes),
 'average_basket',(select round(avg(net),2) from totals),
 'average_conversion_days',(select round(avg(extract(epoch from quote_accepted_at-created_at)/86400),2) from quotes where quote_state='accepted'),
 'estimated_margin',(select case when count(*) filter(where estimated_margin is null)=0 then sum(estimated_margin) end from totals),
 'remaining_to_invoice_net',(select coalesce(sum(remaining_net),0) from totals),
 'partial_deliveries',(select count(*) from orders o where exists(select 1 from public.sales_order_lines l where l.order_id=o.id and private.gama_line_performed(l.id,true)>0)
  and exists(select 1 from public.sales_order_lines l where l.order_id=o.id and private.gama_line_performed(l.id,true)<l.quantity)),
 'groups',coalesce((select jsonb_agg(to_jsonb(x) order by ordered_net desc,key) from(select * from grouped order by ordered_net desc,key limit 100)x),'[]'),
 'definitions',jsonb_build_object('ordered','Confirmed orders created in the period; net of tax; cancelled orders excluded.',
  'invoiced','Active invoices issued in the period with a posted sales_invoice entry; deposits included; credit notes shown separately.',
  'conversion','Accepted / non-cancelled and non-rejected quotes issued in the period. No mixed currencies.',
  'margin','Estimated product margin using costs observed for new order lines; unavailable if any historical cost is missing; delivery costs excluded.',
  'groups','Confirmed order amounts net of tax, grouped by the selected dimension; top 100 groups.')) into result;return result;
end $$;

alter function private.gama_sales_dossier(text,jsonb) rename to gama_sales_dossier_before_views;
revoke all on function private.gama_sales_dossier_before_views(text,jsonb) from public,anon,authenticated;
create function private.gama_sales_dossier(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;d private.sales_dossiers;begin
 if p_action='invoice_board' then return private.sales_invoice_board(p_data);end if;
 if p_action='metrics' then return private.sales_metrics(p_data);end if;
 result:=private.gama_sales_dossier_before_views(p_action,p_data);
 if p_action='dossier' then
  select * into d from private.sales_dossiers where id=(result->>'dossier_id')::uuid;
  result:=result||jsonb_build_object('related',jsonb_build_object(
   'preparations',case when private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero']) then
    coalesce((select jsonb_agg(jsonb_build_object('id',id,'status',status)) from public.fulfillment_preparations where order_id=d.order_id),'[]') else '[]'::jsonb end,
   'packages',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'number',p.barcode,'status',p.status)) from public.fulfillment_packages p join public.fulfillment_preparations f on f.id=p.preparation_id where f.order_id=d.order_id),'[]'),
   'deliveries',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'reference',t.erp_reference,'status',t.status)) from public.sales_deliveries sd join public.tms_deliveries t on t.id=sd.tms_delivery_id where sd.order_id=d.order_id),'[]'),
   'payments',case when private.erp_module_allowed('payments',array['administrador','comercial']) then coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'invoice_id',p.invoice_id,'amount',p.amount,'status',p.status))
    from public.external_invoice_payments p join public.external_invoices i on i.id=p.invoice_id where i.order_id=d.order_id or exists(select 1 from private.sales_invoice_orders a where a.invoice_id=i.id and a.order_id=d.order_id)),'[]') else '[]'::jsonb end,
   'returns',case when private.erp_module_allowed('returns',array['administrador','comercial','almacenero']) then coalesce((select jsonb_agg(jsonb_build_object('id',id,'number',number,'status',status)) from public.return_orders where order_id=d.order_id),'[]') else '[]'::jsonb end));
 end if;return result;
end $$;
revoke all on function private.gama_sales_dossier(text,jsonb) from public,anon;grant execute on function private.gama_sales_dossier(text,jsonb) to authenticated;

-- The standalone B2B identity stays inactive in the ERP. An acceptance is an
-- explicit customer decision; staff confirmation still checks credit/approvals.
-- No customer is temporarily given an internal role or a forged authorization.
alter function private.gama_b2b_action(text,jsonb) rename to gama_b2b_action_before_sales_acceptance;
revoke all on function private.gama_b2b_action_before_sales_acceptance(text,jsonb) from public,anon,authenticated;
create function private.gama_b2b_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.gama_b2b_customer();q public.invoices;a private.sales_portal_acceptances;result jsonb;begin
 if p_action='quote_accept' then
  perform pg_advisory_xact_lock(741932,1);
  select * into q from public.invoices where id=(p_data->>'id')::uuid and customer_id=cid and quote_state in ('sent','accepted') for update;
  if not found then raise exception 'NOT_FOUND';end if;
  select * into a from private.sales_portal_acceptances where quote_id=q.id;
  if a.quote_id is not null and a.revision=q.quote_revision then return jsonb_build_object('accepted',true,'accepted_at',a.accepted_at,'order_confirmed',a.processed_order_id is not null);end if;
  if q.quote_state='accepted' then return jsonb_build_object('accepted',true,'order_confirmed',true);end if;
  if q.quote_revision is distinct from (p_data->>'revision')::integer then raise exception 'QUOTE_CHANGED';end if;
  if q.quote_valid_until<(now() at time zone private.erp_timezone())::date then raise exception 'QUOTE_EXPIRED';end if;
  if not coalesce((p_data->>'agree')::boolean,false) then raise exception 'ACCEPTANCE_REQUIRED';end if;
  insert into private.sales_portal_acceptances(quote_id,revision,accepted_by,snapshot)
   values(q.id,q.quote_revision,auth.uid(),jsonb_build_object('reference',q.invoice_number,'total',q.total,'terms',q.quote_details->>'terms','delivery_address',q.quote_details->>'delivery_address',
    'lines',(select jsonb_agg(jsonb_build_object('product_id',product_id,'quantity',quantity,'unit_price',unit_price,'tax_rate',tax_rate)) from public.invoice_lines where invoice_id=q.id)))
   on conflict(quote_id) do update set revision=excluded.revision,accepted_by=excluded.accepted_by,accepted_at=now(),snapshot=excluded.snapshot,processed_order_id=null returning * into a;
  insert into public.quote_events(quote_id,revision,action,actor_id,detail) values(q.id,q.quote_revision,'portal_acceptance',auth.uid(),jsonb_build_object('source','b2b','confirmation_pending',true));
  return jsonb_build_object('accepted',true,'accepted_at',a.accepted_at,'order_confirmed',false);
 end if;
 result:=private.gama_b2b_action_before_sales_acceptance(p_action,p_data);
 if p_action='quote_document' then
  select * into q from public.invoices where id=(p_data->>'id')::uuid and customer_id=cid;
  result:=result||jsonb_build_object('revision',q.quote_revision,'can_accept',q.quote_state='sent' and q.quote_valid_until>=(now() at time zone private.erp_timezone())::date,
   'acceptance_recorded',exists(select 1 from private.sales_portal_acceptances where quote_id=q.id and revision=q.quote_revision),
   'offer_blocks',coalesce((select jsonb_agg(jsonb_build_object('kind',x->>'kind','description',x->>'description','quantity',x->'quantity','list_price',x->'list_price','tax_rate',x->'tax_rate')) from private.sales_quote_extras e cross join jsonb_array_elements(e.blocks)x where e.quote_id=q.id),'[]'));
 end if;return result;
end $$;
revoke all on function private.gama_b2b_action(text,jsonb) from public,anon;grant execute on function private.gama_b2b_action(text,jsonb) to authenticated;

-- Template metadata is a snapshot, never a live link to a quote's extra blocks.
do $$declare src text;old text;begin
 select pg_get_functiondef('private.gama_sales_workspace(text,jsonb)'::regprocedure) into src;
 old:='return jsonb_build_object(''id'',tpl.id);';
 if strpos(src,old)=0 then raise exception 'SALES_TEMPLATE_EXTRAS_ANCHOR';end if;
 src:=replace(src,old,'update private.sales_templates set offer_blocks=coalesce((select blocks from private.sales_quote_extras where quote_id=qid),''[]'') where id=tpl.id;'||old);
 -- Search quote product and customer reference using indexed relationship keys.
 old:='concat_ws('' '',q.invoice_number,q.erp_reference,dr.document_reference,q.quote_details->>''client'') ilike ''%''||search||''%''';
 if strpos(src,old)=0 then raise exception 'SALES_QUOTE_SEARCH_ANCHOR';end if;
 src:=replace(src,old,'concat_ws('' '',q.invoice_number,q.erp_reference,dr.document_reference,q.quote_details->>''client'',q.quote_details->>''customer_reference'') ilike ''%''||search||''%''
 or exists(select 1 from public.invoice_lines l join public.products p on p.id=l.product_id where l.invoice_id=q.id and concat_ws('' '',p.name,p.reference,p.barcode) ilike ''%''||search||''%'')');execute src;
end $$;
-- Do not let a generic fiscal adapter silently treat a deposit as merchandise.
-- Standard invoices remain provider-neutral and use the existing connector.
alter function private.gama_sri_prepare(uuid,text) rename to gama_sri_prepare_before_sales_deposits;
revoke all on function private.gama_sri_prepare_before_sales_deposits(uuid,text) from public,anon,authenticated;
create function private.gama_sri_prepare(p_invoice_id uuid,p_payment_code text) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador']) or private.current_user_role() is distinct from 'administrador' or not private.erp_action_allowed('accounting','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if exists(select 1 from public.external_invoices i where i.id=p_invoice_id and
  (i.document_snapshot->>'invoice_role'='down_payment' or exists(select 1 from private.sales_deposit_uses u where u.invoice_id=i.id))) then raise exception 'SRI_DEPOSIT_MAPPING_REQUIRED';end if;
 return private.gama_sri_prepare_before_sales_deposits(p_invoice_id,p_payment_code);
end $$;
revoke all on function private.gama_sri_prepare(uuid,text) from public,anon,authenticated;
grant execute on function private.gama_sri_prepare(uuid,text) to authenticated;
revoke all on function private.sales_invoice_board(jsonb),private.sales_metrics(jsonb) from public,anon,authenticated;
