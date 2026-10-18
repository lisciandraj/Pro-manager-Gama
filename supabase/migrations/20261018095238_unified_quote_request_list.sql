-- One displayed row per request/quote. Canonical COT numbers remain immutable.
-- Drafts created directly in Sales receive a genuine SOL from the existing
-- reference issuer, without manufacturing a second customer request or document.
create function private.sales_draft_request_reference() returns trigger
language plpgsql security definer set search_path='' as $$begin
 if new.quote_state='draft' and not exists(select 1 from public.customer_requests r where r.id=new.quote_request_key or r.invoice_id=new.id) then
  perform private.erp_issue_reference('request','draft/invoices/'||new.id);
 end if;
 return new;
end $$;
revoke all on function private.sales_draft_request_reference() from public,anon,authenticated,service_role;
create trigger sales_draft_request_reference after insert or update of quote_state on public.invoices
 for each row execute function private.sales_draft_request_reference();
do $$declare q record;begin
 for q in select i.id from public.invoices i where i.quote_state='draft'
  and not exists(select 1 from public.customer_requests r where r.invoice_id=i.id or r.id=i.quote_request_key)
  order by i.created_at,i.id loop
  perform private.erp_issue_reference('request','draft/invoices/'||q.id);
 end loop;
end $$;

create function private.sales_unified_quote_list(p_data jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare result jsonb;off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
 search text:=left(coalesce(p_data->>'search',''),120);can_requests boolean;
begin
 perform private.sales_access('quote_list');
 if not private.erp_module_allowed('quotes',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 can_requests:=private.erp_module_allowed('customer-requests',array['administrador','comercial']);
 with documents as (
  select q.id,'quote'::text row_kind,coalesce(r.id,q.id) row_key,r.id request_id,
   coalesce(nullif(dr.document_reference,''),q.invoice_number) invoice_number,
   case when q.quote_state='draft' then coalesce(r.erp_reference,s.reference,dr.document_reference,q.invoice_number)
    else coalesce(nullif(dr.document_reference,''),q.invoice_number) end display_reference,
   r.erp_reference request_reference,q.archive_number,q.quote_state,q.quote_valid_until,q.total,
   coalesce(nullif(q.quote_details->>'client',''),c.name,r.requester_company,r.requester_name) client,
   coalesce(r.created_at,q.created_at) created_at,coalesce(r.created_at::date,q.issue_date::date) document_date,
   q.user_id,q.quote_sent_at,q.quote_details->>'customer_reference' customer_reference,
   concat_ws(' ',q.erp_reference,r.website_reference,r.requester_email,r.requester_name,r.requester_company,c.identification) search_details
  from public.invoices q
  left join public.gama_document_references dr on dr.table_name='invoices' and dr.document_id=q.id
  left join lateral(select x.* from public.customer_requests x where can_requests and x.invoice_id=q.id order by x.created_at,x.id limit 1) r on true
  left join private.erp_issued_references s on s.kind='request' and s.document_key='draft/invoices/'||q.id
  left join public.customers c on c.id=q.customer_id
  union all
  select r.id,'request',r.id,r.id,null,r.erp_reference,r.erp_reference,null,
   case when r.status in ('cancelled','rejected') then r.status else 'draft' end,null,coalesce((select sum(l.line_total+round(l.line_total*l.tax_rate/100,2)) from public.customer_request_lines l where l.request_id=r.id),r.total),
   coalesce(c.name,nullif(r.requester_company,''),r.requester_name),r.created_at,r.created_at::date,
   r.created_by,null,null,concat_ws(' ',r.website_reference,r.requester_email,r.requester_name,r.requester_company,c.identification)
  from public.customer_requests r left join public.customers c on c.id=r.customer_id
  where can_requests and r.invoice_id is null
 ), filtered as(select d.* from documents d
  where (search='' or concat_ws(' ',d.display_reference,d.invoice_number,d.request_reference,d.client,d.customer_reference,d.search_details) ilike '%'||search||'%'
   or exists(select 1 from public.invoice_lines l join public.products p on p.id=l.product_id where d.row_kind='quote' and l.invoice_id=d.id and concat_ws(' ',p.name,p.reference,p.barcode) ilike '%'||search||'%')
   or exists(select 1 from public.customer_request_lines l join public.products p on p.id=l.product_id where d.row_kind='request' and l.request_id=d.id and concat_ws(' ',p.name,p.reference,p.barcode) ilike '%'||search||'%'))
  and (coalesce(p_data->>'status','all')='all' or coalesce(d.quote_state,'draft')=p_data->>'status')
  and (nullif(p_data->>'from','') is null or d.document_date>=nullif(p_data->>'from','')::date)
  and (nullif(p_data->>'to','') is null or d.document_date<=nullif(p_data->>'to','')::date)
  and (coalesce(p_data->>'view','all')='all' or (p_data->>'view'='mine' and d.user_id=auth.uid())
   or (p_data->>'view'='followup' and d.quote_state='sent' and d.quote_sent_at<now()-interval '7 days')
   or (p_data->>'view'='expiring' and d.quote_state='sent' and d.quote_valid_until<=(now() at time zone private.erp_timezone())::date+7)))
 select jsonb_build_object('actor_id',auth.uid(),'total',count(*),'rows',coalesce((select jsonb_agg(to_jsonb(z)-'search_details'-'user_id'-'customer_reference'-'document_date'-'quote_sent_at')
  from (select * from filtered order by created_at desc,id offset off limit 20) z),'[]')) into result from filtered;
 return result;
end $$;
revoke all on function private.sales_unified_quote_list(jsonb) from public,anon,authenticated,service_role;
-- Keep the public RPC and all other actions/permissions unchanged.
do $$declare body text;start_at integer;end_at integer;begin
 select pg_get_functiondef('private.gama_sales_workspace(text,jsonb)'::regprocedure) into body;
 start_at:=strpos(body,' if p_action=''quote_list'' then');
 end_at:=strpos(body,' elsif p_action in (''review_order'',''approve_order'',''request_order_approval'') then');
 if start_at=0 or end_at<=start_at then raise exception 'UNIFIED_QUOTE_LIST_ANCHOR';end if;
 body:=left(body,start_at-1)||' if p_action=''quote_list'' then return private.sales_unified_quote_list(p_data);'||substr(body,end_at);
 execute body;
end $$;
notify pgrst,'reload schema';
