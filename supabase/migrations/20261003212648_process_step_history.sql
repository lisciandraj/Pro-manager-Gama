-- Scope audit metadata to one process. Raw audit payloads remain administrator-only.
create trigger process_return_audit after insert or update or delete on public.return_orders for each row execute function private.erp_audit_capture();
create trigger process_return_line_audit after insert or update or delete on public.return_lines for each row execute function private.erp_audit_capture();
create trigger process_return_credit_audit after insert or update or delete on public.return_credits for each row execute function private.erp_audit_capture();
create trigger process_request_audit after insert or update or delete on public.customer_requests for each row execute function private.erp_audit_capture();
create function private.gama_process_history(p_key text,p_step integer default 0,p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare k text:=split_part(p_key,':',1);source uuid;oid uuid;qid uuid;rid uuid;poid uuid;ret public.return_orders;
 model jsonb;result jsonb;fin boolean:=false;is_return boolean:=false;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if p_key !~ '^(o|q|r|p|return):[0-9a-fA-F-]{36}$' or p_step not between 0 and 8 or p_offset not between 0 and 1000000 then raise exception 'INVALID_PROCESS_KEY';end if;
 source:=split_part(p_key,':',2)::uuid;is_return:=k='return';
 if is_return then
  if not private.erp_module_allowed('returns',array['administrador','comercial','almacenero']) or not coalesce((private.gama_returns_rights()->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
  select * into ret from public.return_orders where id=source;if not found then raise exception 'DOSSIER_NOT_FOUND';end if;
  fin:=coalesce((private.gama_returns_rights()->>'refund')::boolean,false);
 else
  model:=private.gama_processes('state',jsonb_build_object('key',p_key));
  if k='o' then select id,source_quote_id,source_request_id into oid,qid,rid from public.sales_orders where id=source;
  elsif k='q' then qid:=source;
  elsif k='r' then rid:=source;select invoice_id into qid from public.customer_requests where id=source;
  elsif k='p' then poid:=source;end if;
  fin:=coalesce(model->'steps'->(case when k='p' then 4 else 5 end)->>'state','restricted')<>'restricted';
 end if;
 with related as (
  select 'customer_requests'::text tbl,rid::text id,1 stage,'request'::text action where rid is not null and private.erp_module_allowed('customer-requests',array['administrador','comercial'])
  union all select 'crm_opportunities',x.id::text,1,'opportunity' from public.crm_opportunities x where private.erp_module_allowed('crm',array['administrador','comercial']) and (x.id=(select source_opportunity_id from public.sales_orders where id=oid) or x.quote_invoice_id=qid)
  union all select 'purchase_orders',poid::text,2,'purchase' where poid is not null
  union all select 'purchase_order_lines',l.id::text,3,'receipt' from public.purchase_order_lines l where l.purchase_order_id=poid
  union all select 'supplier_invoices',i.id::text,5,'supplier_invoice' from public.supplier_invoices i where fin and (i.purchase_order_id=poid or exists(select 1 from public.supplier_invoice_matches m where m.invoice_id=i.id and m.purchase_order_id=poid))
  union all select 'supplier_invoice_matches',m.id::text,5,'invoice_match' from public.supplier_invoice_matches m where m.purchase_order_id=poid and fin
  union all select 'supplier_invoice_payments',p.id::text,6,'supplier_payment' from public.supplier_invoice_payments p join public.supplier_invoices i on i.id=p.supplier_invoice_id where fin and (i.purchase_order_id=poid or exists(select 1 from public.supplier_invoice_matches m where m.invoice_id=i.id and m.purchase_order_id=poid))
  union all select 'external_invoices',i.id::text,6,'invoice' from public.external_invoices i where i.order_id=oid and fin
  union all select 'external_invoice_payments',p.id::text,7,'payment' from public.external_invoice_payments p join public.external_invoices i on i.id=p.invoice_id where i.order_id=oid and fin
  union all select 'dossier_followups',f.id::text,case when k='p' then 7 else 8 end,'closure' from public.dossier_followups f where f.dossier_key=p_key and fin
  union all select 'return_orders',ret.id::text,2,'return_request' where is_return
  union all select 'return_lines',l.id::text,4,'return_treatment' from public.return_lines l where is_return and ret.kind='customer' and l.return_id=ret.id
  union all select 'return_credits',c.id::text,case when ret.kind='customer' then 5 else 4 end,'credit' from public.return_credits c where is_return and fin and c.return_id=ret.id
  union all select 'return_refunds',f.id::text,5,'refund' from public.return_refunds f where is_return and fin and f.return_id=ret.id
 ), audited as (
  select 'audit:'||a.id id,a.created_at at,a.actor_id,
   case when x.tbl='return_orders' then case
    when a.after_data->>'closed_at' is distinct from a.before_data->>'closed_at' and a.after_data->>'closed_at' is not null then case when ret.kind='customer' then 6 else 5 end
    when a.after_data->>'status'='cancelled' then 2
    when a.after_data->>'received_at' is distinct from a.before_data->>'received_at' and a.after_data->>'received_at' is not null then 3
    when a.after_data->>'shipped_on' is distinct from a.before_data->>'shipped_on' and a.after_data->>'shipped_on' is not null then 3
    when a.after_data->>'financial_action' is distinct from a.before_data->>'financial_action' then case when ret.kind='customer' then 5 else 4 end
    else 2 end else x.stage end stage,
   case when x.tbl='return_orders' then case
    when a.after_data->>'closed_at' is distinct from a.before_data->>'closed_at' and a.after_data->>'closed_at' is not null then 'closure'
    when a.after_data->>'status'='cancelled' then 'cancel'
    when a.after_data->>'received_at' is distinct from a.before_data->>'received_at' and a.after_data->>'received_at' is not null then 'receipt'
    when a.after_data->>'shipped_on' is distinct from a.before_data->>'shipped_on' and a.after_data->>'shipped_on' is not null then 'dispatch'
    when a.after_data->>'financial_action' is distinct from a.before_data->>'financial_action' then 'financial_decision'
    else x.action end else x.action end action,
   coalesce(a.after_data->>'status',a.after_data->>'fiscal_status',a.after_data->>'quote_state') status,
   coalesce(a.after_data->>'erp_reference',a.after_data->>'number',a.after_data->>'order_number') reference
  from related x join public.erp_audit_events a on a.table_name=x.tbl and a.record_id=x.id
  where (a.operation='INSERT' and x.tbl not in ('purchase_orders','customer_requests','return_orders','return_credits','return_refunds','external_invoice_payments','supplier_invoice_payments')) or
   (a.operation='UPDATE' and exists(select 1 from unnest(array['status','fiscal_status','received_quantity','processed_at','closed_at','received_at','shipped_on','financial_action','approved_at','cancelled_at','external_status']) f where a.before_data->f is distinct from a.after_data->f))
 ), native as (
  select 'sale:'||e.id id,e.created_at at,e.actor_id,
   case when e.action='created' or e.action in ('confirm','cancel','update') then 3
    when e.action='quote_accepted' then 2
    when e.action like 'internal_%' or e.action like 'invoice_%' then 6
    when e.action like 'service_%' or e.action in ('dispatch','shipment','ship') or e.action='fulfillment_dispatch' then 5 else 4 end stage,
   e.action action,null::text status,null::text reference
  from public.sales_events e where e.order_id=oid and e.action<>'invoice_auto_failed' and e.action not in ('payment','payment_cancelled') and
   (private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero']) or e.action like 'fulfillment_%' and private.erp_module_allowed('tms',array['administrador','comercial','almacenero','transportista'])) and (fin or e.action not like 'internal_%' and e.action not like 'invoice_%') and (e.action<>'quote_accepted' or private.erp_module_allowed('quotes',array['administrador','comercial']))
  union all select 'quote:'||e.id,e.at,e.actor_id,2,'quote_'||e.action,null,null from public.quote_events e where e.quote_id=qid and private.erp_module_allowed('quotes',array['administrador','comercial'])
  union all select 'delivery:'||e.id,e.at,e.user_id,5,'delivery_'||e.type,null,null from public.tms_events e join public.sales_deliveries s on s.tms_delivery_id=e.delivery_id where s.order_id=oid and private.erp_module_allowed('tms',array['administrador','comercial','almacenero','transportista'])
  union all select 'stock:'||m.id,m.created_at,m.user_id,4,'stock',null,m.erp_reference from public.stock_movements m where m.reference_type='purchase_order' and m.reference_id=poid
  union all select 'opportunity-created:'||x.id,x.created_at,x.created_by,1,'opportunity_created',null,x.erp_reference from public.crm_opportunities x where private.erp_module_allowed('crm',array['administrador','comercial']) and (x.id=(select source_opportunity_id from public.sales_orders where id=oid) or x.quote_invoice_id=qid)
  union all select 'order-created:'||o.id,o.created_at,o.created_by,3,'created',null,o.erp_reference from public.sales_orders o where o.id=oid and private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero']) and not exists(select 1 from public.sales_events e where e.order_id=o.id and e.action='created')
  union all select 'proof:'||p.delivery_id,p.captured_at,p.captured_by,5,'proof',null,p.erp_reference from public.tms_proofs p join public.sales_deliveries s on s.tms_delivery_id=p.delivery_id where s.order_id=oid and private.erp_module_allowed('tms',array['administrador','comercial','almacenero','transportista'])
  union all select 'request-created:'||r.id,r.created_at,r.created_by,1,'request_created',null,r.erp_reference from public.customer_requests r where r.id=rid and private.erp_module_allowed('customer-requests',array['administrador','comercial'])
  union all select 'purchase-created:'||p.id,p.created_at,p.created_by,1,'purchase_created',null,p.erp_reference from public.purchase_orders p where p.id=poid
  union all select 'return-created:'||ret.id,ret.created_at,ret.created_by,2,'return_created',null,ret.erp_reference where is_return
  union all select 'payment-created:'||p.id,p.created_at,p.created_by,7,'payment',null,p.erp_reference from public.external_invoice_payments p join public.external_invoices i on i.id=p.invoice_id where i.order_id=oid and fin
  union all select 'supplier-payment-created:'||p.id,p.created_at,p.created_by,6,'supplier_payment',null,p.erp_reference from public.supplier_invoice_payments p join public.supplier_invoices i on i.id=p.supplier_invoice_id where fin and (i.purchase_order_id=poid or exists(select 1 from public.supplier_invoice_matches m where m.invoice_id=i.id and m.purchase_order_id=poid))
  union all select 'credit-created:'||c.id,c.created_at,c.created_by,case when is_return then case when ret.kind='customer' then 5 else 4 end when poid is not null then 6 else 7 end,'credit',null,c.erp_reference from public.return_credits c where fin and (is_return and c.return_id=ret.id or exists(select 1 from public.external_invoices i where i.id=c.invoice_id and i.order_id=oid) or exists(select 1 from public.supplier_invoices i where i.id=c.supplier_invoice_id and (i.purchase_order_id=poid or exists(select 1 from public.supplier_invoice_matches m where m.invoice_id=i.id and m.purchase_order_id=poid))))
  union all select 'refund-created:'||f.id,f.created_at,f.created_by,5,'refund',null,f.erp_reference from public.return_refunds f where is_return and fin and f.return_id=ret.id
 ), events as (
  select * from audited union all select * from native
 ), permitted as (
  select e.*,coalesce(nullif(p.full_name,''),case when e.actor_id is not null then 'USER_UNAVAILABLE' else 'AUTHOR_NOT_RECORDED' end) actor_name
  from events e left join public.profiles p on p.id=e.actor_id
  where (p_step=0 or e.stage=p_step) and e.stage between 1 and 8 and
   (is_return and (fin or e.stage<>case when ret.kind='customer' then 5 else 4 end) or not is_return and model->'steps'->(e.stage-1)->>'state' is distinct from 'restricted')
 ), numbered as (
  select *,row_number() over(partition by stage order by at desc,id desc) rn,count(*) over(partition by stage) total from permitted
 ) select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('id',id,'step',stage,'at',at,'actor_name',actor_name,'action',action,'status',status,'reference',reference,'total',total) order by stage,at desc,id desc),'[]')) into result from numbered where rn>p_offset and rn<=p_offset+50;
 return result;
end $$;
revoke all on function private.gama_process_history(text,integer,integer) from public,anon;
grant execute on function private.gama_process_history(text,integer,integer) to authenticated;
create function public.gama_process_history(p_key text,p_step integer default 0,p_offset integer default 0) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_process_history(p_key,p_step,p_offset)$$;
revoke all on function public.gama_process_history(text,integer,integer) from public,anon;
grant execute on function public.gama_process_history(text,integer,integer) to authenticated;
notify pgrst,'reload schema';
