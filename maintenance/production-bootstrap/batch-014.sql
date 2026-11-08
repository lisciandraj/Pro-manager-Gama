do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>306
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;

-- Canonical source: 20261018081814_website_requests_to_draft_quotes.sql; SHA256 fb03d3eb07143b59a02a4ccf4aa8b33bfbd49b4090c4563a323d488ab919fa3f
-- Headless intake writes only an unsent draft into the existing sales tables.
-- No Auth session, staff identity, order, reservation or fiscal invoice is made.
create table private.website_quote_intakes(
 request_id uuid primary key references public.customer_requests(id),
 quote_id uuid not null unique references public.invoices(id),
 channel text not null check(channel in ('website','portal')),
 created_at timestamptz not null default now()
);
alter table private.website_quote_intakes enable row level security;
revoke all on private.website_quote_intakes from public,anon,authenticated,service_role;
create policy website_quote_intakes_private on private.website_quote_intakes
 for all to authenticated using(false) with check(false);

-- A closed, row-bound write capability for the duration of the intake only.
-- Portal clients gain no general quote permission, JWT or manufactured session.
create table private.website_quote_context(
 backend integer not null,transaction bigint not null,request_id uuid not null,quote_id uuid not null,
 primary key(backend,transaction)
);
alter table private.website_quote_context enable row level security;
revoke all on private.website_quote_context from public,anon,authenticated,service_role;
create policy website_quote_context_private on private.website_quote_context
 for all to authenticated using(false) with check(false);
create function private.website_quote_write_allowed(p_table text,p_operation text,p_row jsonb) returns boolean
language sql stable security definer set search_path='' as $$
 select p_operation in ('INSERT','UPDATE') and exists(
  select 1 from private.website_quote_context x join public.customer_requests r on r.id=x.request_id
  where x.backend=pg_backend_pid() and x.transaction=txid_current()
  and case p_table when 'invoices' then p_row->>'id'=x.quote_id::text
   and p_row->>'quote_state'='draft' and p_row->>'status'='draft'
   and p_row->>'quote_request_key'=r.id::text and p_row->>'user_id' is null
   when 'invoice_lines' then p_row->>'invoice_id'=x.quote_id::text
    and exists(select 1 from public.invoices i where i.id=x.quote_id and i.quote_state='draft' and i.user_id is null)
    and exists(select 1 from public.customer_request_lines l where l.request_id=r.id
     and l.product_id::text=p_row->>'product_id' and l.quantity=(p_row->>'quantity')::numeric)
   else false end
 )
$$;
revoke all on function private.website_quote_write_allowed(text,text,jsonb) from public,anon,authenticated,service_role;
do $$declare body text;anchor text:=' if auth.uid() is null then';begin
 select pg_get_functiondef('private.erp_action_guard()'::regprocedure) into body;
 if strpos(body,anchor)=0 then raise exception 'WEBSITE_ACTION_GUARD_ANCHOR';end if;
 body:=replace(body,anchor,' if tg_table_name in (''invoices'',''invoice_lines'') and tg_op in (''INSERT'',''UPDATE'') and private.website_quote_write_allowed(tg_table_name,tg_op,to_jsonb(new)) then return new;end if;'||E'\n'||anchor);
 execute body;
end $$;

create function private.website_request_quote(p_request uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare r public.customer_requests;q public.invoices;c public.customers;p public.products;
 l public.customer_request_lines;company jsonb;details jsonb;price_info jsonb;price numeric;net numeric;vat numeric;
 v_subtotal numeric:=0;taxes numeric:=0;source text;ref text;links jsonb;refs jsonb:='[]';refresh boolean:=false;
 today date:=(now() at time zone private.erp_timezone())::date;
begin
 perform pg_advisory_xact_lock(741932,1);
 select * into r from public.customer_requests where id=p_request for update;
 if not found or r.status in ('cancelled','rejected') then return null;end if;
 -- Provenance comes from server-owned records, never a browser-supplied flag.
 if r.source_website_id is not null and exists(select 1 from private.website_public_inquiries w
  where w.id=r.source_website_id and w.status<>'archived') then source:='website';
 elsif exists(select 1 from private.command_receipts x where x.domain='b2b-submit'
  and x.result->>'id'=r.id::text and x.actor_id=r.created_by) then source:='portal';
 else return null;end if;
 if r.invoice_id is not null then
  select i.* into q from public.invoices i join private.website_quote_intakes w on w.quote_id=i.id
   where w.request_id=r.id and i.id=r.invoice_id for update of i;
  -- Contact resolution may complete an untouched anonymous draft. Edited or
  -- sent quotes are never repriced by intake retries or contact changes.
  if not found or q.quote_state<>'draft' or q.quote_revision<>1 or q.customer_id is not null
   or r.customer_id is null then return r.invoice_id;end if;
  refresh:=true;
 else
  if r.status not in ('pending','accepted') then return null;end if;
  if exists(select 1 from public.sales_orders where source_request_id=r.id) then return null;end if;
 end if;
 if not exists(select 1 from public.customer_request_lines where request_id=r.id) then return null;end if;
 select * into c from public.customers where id=r.customer_id and active;
 if not refresh then q.id:=gen_random_uuid();end if;
 insert into private.website_quote_context(backend,transaction,request_id,quote_id)
 values(pg_backend_pid(),txid_current(),r.id,q.id);
 select to_jsonb(s) into company from public.company_settings s where s.id;
 details:=jsonb_build_object('client',coalesce(c.name,nullif(r.requester_company,''),r.requester_name),
  'clientId',coalesce(c.identification,''),'clientEmail',coalesce(nullif(r.requester_email,''),c.email,''),
  'clientPhone',coalesce(nullif(r.requester_phone,''),c.phone,''),'clientAddress',coalesce(c.address,''),
  'delivery_address',coalesce(nullif(r.delivery_address_snapshot,''),c.address,''),
  'seller',coalesce(nullif(company->>'trade_name',''),nullif(company->>'legal_name',''),'GAMA'),
  'sellerRuc',coalesce(company->>'tax_id',''),'sellerAddress',coalesce(company->>'address',''),
  'customer_comment',coalesce(r.notes,''),'notes','Borrador automático desde la solicitud del sitio web. Revisar los datos antes de enviar.',
  'source_request_id',r.id,'website_reference',coalesce(r.website_reference,r.erp_reference),
  'requested_delivery_date',r.requested_delivery_date);
 if not refresh then
  insert into public.invoices(id,customer_id,user_id,status,quote_state,quote_request_key,quote_revision,
   issue_date,quote_valid_until,quote_details,notes)
  values(q.id,c.id,null,'draft','draft',r.id,1,today,today+30,details,r.notes) returning * into q;
  insert into private.website_quote_intakes(request_id,quote_id,channel) values(r.id,q.id,source);
 end if;
 for l in select * from public.customer_request_lines where request_id=r.id order by created_at,id loop
  select * into p from public.products where id=l.product_id and active;
  if not found then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;
  if c.id is not null then price_info:=private.erp_price_calculate(c.id,p.id,l.quantity,today);
  else price_info:=jsonb_build_object('unit_price',l.unit_price,'source','website','label','Catálogo público');end if;
  price:=round(coalesce((price_info->>'unit_price')::numeric,0),2);
  net:=round(l.quantity*price,2);vat:=round(net*coalesce(p.tax_rate,0)/100,2);
  if refresh then
   update public.invoice_lines set unit_price=price,quote_list_price=price,tax_rate=p.tax_rate,line_total=net,price_source=price_info
    where invoice_id=q.id and product_id=p.id;
  else
   insert into public.invoice_lines(invoice_id,product_id,quantity,unit_price,tax_rate,line_total,
    quote_description,quote_list_price,quote_discount,sales_quantity,sales_unit_factor,price_source)
   values(q.id,p.id,l.quantity,price,p.tax_rate,net,p.name,price,0,l.quantity,1,price_info);
  end if;
  v_subtotal:=v_subtotal+net;taxes:=taxes+vat;
  refs:=refs||jsonb_build_array(jsonb_build_object('kind','product','id',p.id,'reference',p.reference,'name',p.name,'quantity',l.quantity));
 end loop;
 select document_reference into ref from public.gama_document_references where table_name='invoices' and document_id=q.id;
 ref:=coalesce(ref,q.invoice_number,'COT-'||lpad(q.archive_number::text,9,'0'));
 update public.invoices set customer_id=c.id,invoice_number=ref,subtotal=v_subtotal,tax=taxes,total=v_subtotal+taxes,
  quote_details=details,quote_revision=case when refresh then quote_revision+1 else quote_revision end,updated_at=now()
  where id=q.id;
 update public.customer_requests set invoice_id=q.id,status='invoiced',converted_at=coalesce(converted_at,now()),updated_at=now() where id=r.id;
 if not refresh then
  links:=jsonb_build_array(jsonb_build_object('module','quotes','action','quote','id',q.id,'reference',ref),
   jsonb_build_object('module','customer-requests','action','request','id',r.id,'reference',coalesce(r.website_reference,r.erp_reference)),
   jsonb_build_object('module','website','action','module'));
  insert into private.coco_module_events(module_id,record_table,record_id,type,action,subject,body,reference,
   actor_name,references_list,links,source_type,source_id,source_label)
  values('quotes','invoices',q.id::text,'action','source_linked','Solicitud del sitio web',
   'Solicitud convertida automáticamente en un presupuesto en borrador. No se ha enviado ni confirmado.',ref,
   'Agent Coco',refs,links,'erp',r.id::text,case source when 'portal' then 'Portal de clientes' else 'Sitio web' end);
 end if;
 delete from private.website_quote_context where backend=pg_backend_pid() and transaction=txid_current();
 return q.id;
end $$;
revoke all on function private.website_request_quote(uuid) from public,anon,authenticated,service_role;

-- The public intake already validates its server token, quantities, publication,
-- prices and deduplication before inserting this source and all request lines.
do $$declare body text;old text;begin
 select pg_get_functiondef('private.import_website_request(uuid)'::regprocedure) into body;
 old:='if r is null then return;end if;';
 if strpos(body,old)=0 then raise exception 'WEBSITE_IMPORT_RETRY_ANCHOR';end if;
 body:=replace(body,old,'if r is null then select id into r from public.customer_requests where source_website_id=w.id;perform private.website_request_quote(r);return;end if;');
 old:=' end loop;';
 if strpos(body,old)=0 then raise exception 'WEBSITE_IMPORT_LINES_ANCHOR';end if;
 body:=replace(body,old,old||E'\n perform private.website_request_quote(r);');execute body;
end $$;

-- Keep the portal's signed-in customer scope, price hash, immutable receipt and
-- exact response contract. Its existing wrapper creates the complete request.
alter function private.gama_b2b_action(text,jsonb) rename to gama_b2b_action_before_website_quotes;
revoke all on function private.gama_b2b_action_before_website_quotes(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_b2b_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$declare result jsonb;begin
 result:=private.gama_b2b_action_before_website_quotes(p_action,p_data);
 if p_action='submit' then perform private.website_request_quote((result->>'id')::uuid);end if;
 return result;
end $$;
revoke all on function private.gama_b2b_action(text,jsonb) from public,anon;
grant execute on function private.gama_b2b_action(text,jsonb) to authenticated;

-- Incomplete website drafts can be edited through the normal quote editor.
-- A linked portal address cannot silently migrate to a different company.
create function private.website_quote_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare r public.customer_requests;begin
 select x.* into r from public.customer_requests x join private.website_quote_intakes w on w.request_id=x.id where w.quote_id=new.id;
 if not found then return new;end if;
 if new.customer_id is distinct from old.customer_id and r.delivery_address_id is not null
  and new.customer_id is distinct from r.customer_id then raise exception 'B2B_ADDRESS_CUSTOMER_CHANGED';end if;
 if new.quote_state='sent' and old.quote_state is distinct from 'sent' then
  if not exists(select 1 from public.customers where id=new.customer_id and active) then raise exception 'CUSTOMER_REQUIRED';end if;
  if nullif(btrim(new.quote_details->>'client'),'') is null or nullif(btrim(new.quote_details->>'seller'),'') is null
   or nullif(btrim(new.quote_details->>'delivery_address'),'') is null then raise exception 'DETAILS_REQUIRED';end if;
 end if;return new;
end $$;
revoke all on function private.website_quote_guard() from public,anon,authenticated,service_role;
create trigger website_quote_guard before update on public.invoices for each row execute function private.website_quote_guard();

create function private.website_quote_customer_sync() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_table_name='invoices' then
  update public.customer_requests r set customer_id=new.customer_id,updated_at=now()
   from private.website_quote_intakes w where w.quote_id=new.id and w.request_id=r.id and r.customer_id is distinct from new.customer_id;
 else perform private.website_request_quote(new.id);end if;
 return new;
end $$;
revoke all on function private.website_quote_customer_sync() from public,anon,authenticated,service_role;
create trigger website_quote_customer_sync after update of customer_id on public.invoices for each row
 when(old.customer_id is distinct from new.customer_id and new.customer_id is not null)
 execute function private.website_quote_customer_sync();
create trigger website_request_customer_sync after update of customer_id on public.customer_requests for each row
 when(old.customer_id is distinct from new.customer_id and new.customer_id is not null and new.invoice_id is not null)
 execute function private.website_quote_customer_sync();

-- Preserve the existing staff-only contact workflow for an untouched draft.
create function private.website_quote_matches(p_request uuid,p_quote uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok()
 and private.erp_module_allowed('quotes',array['administrador','comercial'])
 and private.erp_module_allowed('customer-requests',array['administrador','comercial'])
 and exists(select 1 from private.website_quote_intakes where request_id=p_request and quote_id=p_quote)
$$;
revoke all on function private.website_quote_matches(uuid,uuid) from public,anon;
grant execute on function private.website_quote_matches(uuid,uuid) to authenticated;

do $$declare body text;old text;begin
 select pg_get_functiondef('public.gama_request_contact(uuid,text,jsonb)'::regprocedure) into body;
 old:='(r.invoice_id is not null or r.status in (''cancelled'',''rejected''))';
 if strpos(body,old)=0 then raise exception 'WEBSITE_CONTACT_GUARD_ANCHOR';end if;
 body:=replace(body,old,'(r.status in (''cancelled'',''rejected'') or (r.invoice_id is not null and not exists(select 1 from public.invoices q where q.id=r.invoice_id and q.quote_state=''draft'' and ((q.quote_revision=1 and q.customer_id is null) or (r.customer_id is not null and q.customer_id=r.customer_id)) and exists(select 1 from private.website_quote_intakes w where w.request_id=r.id and w.quote_id=q.id))))');
 -- The provenance lookup runs in a private predicate, not under elevated RPC
 -- privileges: the original contact function remains SECURITY INVOKER.
 body:=replace(body,'exists(select 1 from private.website_quote_intakes w where w.request_id=r.id and w.quote_id=q.id)',
  'private.website_quote_matches(r.id,q.id)');execute body;
end $$;

-- Convert the real unprocessed website/portal backlog, preserving every source.
-- Manual ERP requests and already converted, cancelled or rejected records stay
-- under their existing workflow. Global sales lock + request lock serialize races.
do $$declare x record;begin
 for x in select r.id from public.customer_requests r where r.invoice_id is null and r.status in ('pending','accepted')
  and (r.source_website_id is not null or exists(select 1 from private.command_receipts c
   where c.domain='b2b-submit' and c.result->>'id'=r.id::text and c.actor_id=r.created_by))
  order by r.created_at,r.id loop perform private.website_request_quote(x.id);end loop;
end $$;
notify pgrst,'reload schema';


insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261018081814','website_requests_to_draft_quotes','fb03d3eb07143b59a02a4ccf4aa8b33bfbd49b4090c4563a323d488ab919fa3f','fb03d3eb07143b59a02a4ccf4aa8b33bfbd49b4090c4563a323d488ab919fa3f','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261018095238_unified_quote_request_list.sql; SHA256 e62c5bdf42c0d9432fc79a3173ca5405acc58ddd9c70258e73d90bc52d8f79e3
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
-- Opt in from the new screen. Open tabs on the older release keep their
-- quote-only response during deployment; every other workspace action is intact.
do $$declare body text;anchor text:=' if p_action=''quote_list'' then';begin
 select pg_get_functiondef('private.gama_sales_workspace(text,jsonb)'::regprocedure) into body;
 if strpos(body,anchor)=0 then raise exception 'UNIFIED_QUOTE_LIST_ANCHOR';end if;
 body:=replace(body,anchor,' if p_action=''quote_list'' and p_data->>''layout''=''requests-quotes'' then return private.sales_unified_quote_list(p_data);end if;'||E'\n'||anchor);
 execute body;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261018095238','unified_quote_request_list','e62c5bdf42c0d9432fc79a3173ca5405acc58ddd9c70258e73d90bc52d8f79e3','e62c5bdf42c0d9432fc79a3173ca5405acc58ddd9c70258e73d90bc52d8f79e3','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261018102218_unified_legacy_draft_references.sql; SHA256 0638bcca7000732081b8591a06369e7718929a51eae6d959dce134e1c9b9414e
-- Older quotes have no managed quote_state. Only their actual draft status
-- belongs to requests; issued archives retain COT and are never reclassified.
do $$declare body text;anchor text;begin
 select pg_get_functiondef('private.sales_draft_request_reference()'::regprocedure) into body;
 anchor:='if new.quote_state=''draft''';
 if strpos(body,anchor)=0 then raise exception 'LEGACY_DRAFT_TRIGGER_ANCHOR';end if;
 execute replace(body,anchor,'if (new.quote_state=''draft'' or (new.quote_state is null and new.status=''draft''))');
 select pg_get_functiondef('private.sales_unified_quote_list(jsonb)'::regprocedure) into body;
 anchor:='case when q.quote_state=''draft'' then';
 if strpos(body,anchor)=0 then raise exception 'LEGACY_DRAFT_DISPLAY_ANCHOR';end if;
 body:=replace(body,anchor,'case when (q.quote_state=''draft'' or (q.quote_state is null and q.status=''draft'')) then');
 anchor:='q.archive_number,q.quote_state,q.quote_valid_until';
 if strpos(body,anchor)=0 then raise exception 'LEGACY_DRAFT_STATE_ANCHOR';end if;
 body:=replace(body,anchor,'q.archive_number,coalesce(q.quote_state,case when q.status=''draft'' then ''draft'' else ''legacy'' end) quote_state,q.quote_valid_until');
 body:=replace(body,'coalesce(d.quote_state,''draft'')=p_data->>''status''','d.quote_state=p_data->>''status''');
 execute body;
end $$;
drop trigger sales_draft_request_reference on public.invoices;
create trigger sales_draft_request_reference after insert or update of quote_state,status on public.invoices
 for each row execute function private.sales_draft_request_reference();
do $$declare q record;begin
 for q in select i.id from public.invoices i where i.quote_state is null and i.status='draft'
  and not exists(select 1 from public.customer_requests r where r.invoice_id=i.id or r.id=i.quote_request_key)
  order by i.created_at,i.id loop
  perform private.erp_issue_reference('request','draft/invoices/'||q.id);
 end loop;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261018102218','unified_legacy_draft_references','0638bcca7000732081b8591a06369e7718929a51eae6d959dce134e1c9b9414e','0638bcca7000732081b8591a06369e7718929a51eae6d959dce134e1c9b9414e','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261018174016_audit_in_module_and_dossier_history.sql; SHA256 b3c13d258ec1143d0a56b44299bc4b21b2ea5cd43168ee73fec5b217402e3172
-- Read the existing audit trail in context; do not copy or rewrite its journals.
-- The audit permission remains required, in addition to the destination module.
create function private.coco_audit_events() returns table(
 kind text,at timestamptz,actor uuid,action text,label text,detail text,reference text,
 amount numeric,quantity numeric,target_table text,target_id text)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('audit',array['administrador']) then return;end if;
 return query
 with ev(kind,at,actor,action,label,detail,reference,amount,quantity,target_table,target_id) as (
  select 'stock',m.created_at,m.user_id,coalesce(nullif(m.movement_type,''),m.type),
   case m.movement_type when 'receipt' then 'Recepción de compra' when 'delivery' then 'Salida por entrega'
    when 'internal_transfer' then 'Transferencia entre ubicaciones' when 'inventory_adjustment' then 'Ajuste de inventario'
    when 'return_in' then 'Devolución recibida' when 'return_out' then 'Devolución a proveedor'
    else case when m.type='in' then 'Entrada de stock' else 'Salida de stock' end end,
   concat_ws(' · ',p.name,nullif(btrim(coalesce(m.reason,'')),''),nullif(btrim(coalesce(m.comment,'')),'')),
   m.erp_reference,null::numeric,case when m.type='in' then m.quantity else -m.quantity end,'stock_movements',m.id::text
  from public.stock_movements m left join public.products p on p.id=m.product_id
  union all
  select 'transfer',e.at,e.user_id,'delivery_'||e.type,
   case e.type when 'Creada' then 'Entrega creada' when 'Entregada' then 'Entrega completada'
    when 'SALIDA_VALIDADA' then 'Salida de entrega validada' when 'CARGA_ESCANEADA' then 'Carga de entrega escaneada'
    when 'COORDENADAS' then 'Coordenadas de entrega corregidas' when 'RUTA_AJUSTADA' then 'Ruta de entrega ajustada'
    when 'INCIDENTE' then 'Incidencia de entrega registrada' when 'REPROGRAMADA' then 'Entrega reprogramada'
    when 'ENTREGA_PARCIAL' then 'Entrega parcial y retorno' when 'COBRO' then 'Cobro en la entrega'
    when 'AVISO_PREPARADO' then 'Aviso de llegada preparado'
    else 'Entrega · '||e.type end,
   concat_ws(' · ',coalesce(nullif(e.customer,''),d.customer),nullif(e.note,'')),
   d.erp_reference,null,null,'tms_events',e.id::text
  from public.tms_events e left join public.tms_deliveries d on d.id=e.delivery_id
  union all
  select 'payment',x.created_at,x.created_by,'customer_payment','Cobro de cliente',
   concat_ws(' · ',i.number,o.customer_name,x.method),x.erp_reference,x.amount,null,'external_invoice_payments',x.id::text
  from public.external_invoice_payments x left join public.external_invoices i on i.id=x.invoice_id left join public.sales_orders o on o.id=i.order_id
  union all
  select 'payment',x.cancelled_at,x.cancelled_by,'customer_payment_cancelled','Cobro anulado',
   concat_ws(' · ',i.number,o.customer_name,x.cancellation_reason),x.erp_reference,-x.amount,null,'external_invoice_payments',x.id::text
  from public.external_invoice_payments x left join public.external_invoices i on i.id=x.invoice_id left join public.sales_orders o on o.id=i.order_id
  where x.status='cancelled' and x.cancelled_at is not null
  union all
  select 'payment',x.created_at,x.created_by,'supplier_payment',
   case when x.status='cancelled' then 'Pago a proveedor anulado' else 'Pago a proveedor' end,
   concat_ws(' · ',si.number,s.name,x.method),x.erp_reference,-x.amount,null,'supplier_invoice_payments',x.id::text
  from public.supplier_invoice_payments x left join public.supplier_invoices si on si.id=x.supplier_invoice_id left join public.suppliers s on s.id=si.supplier_id
  union all
  select 'payment',x.created_at,x.created_by,'refund','Reembolso a cliente',
   concat_ws(' · ',r.number,c.name,x.method),x.erp_reference,-x.amount,null,'return_refunds',x.id::text
  from public.return_refunds x left join public.return_orders r on r.id=x.return_id left join public.customers c on c.id=r.customer_id
  union all
  select 'invoice',i.created_at,i.created_by,'invoice_issued','Factura emitida',
   concat_ws(' · ',o.customer_name,nullif(i.external_number,'')),coalesce(i.erp_reference,i.number),i.total,null,'external_invoices',i.id::text
  from public.external_invoices i left join public.sales_orders o on o.id=i.order_id
  union all
  select 'invoice',si.created_at,si.created_by,'supplier_invoice','Factura de proveedor registrada',
   concat_ws(' · ',s.name,si.number),coalesce(si.erp_reference,si.number),si.total,null,'supplier_invoices',si.id::text
  from public.supplier_invoices si left join public.suppliers s on s.id=si.supplier_id
  union all
  select 'validation',a.reviewed_at,a.reviewed_by,'approval_'||a.status,
   case when a.status='approved' then 'Validación aprobada' else 'Validación rechazada' end,
   concat_ws(' · ',a.module,a.reason,a.decision_reason),null,null,null,'erp_approvals',a.id::text
  from public.erp_approvals a where a.reviewed_at is not null and a.status in ('approved','rejected')
  union all
  select 'validation',q.reviewed_at,q.reviewed_by,'adjustment_'||q.status,
   case when q.status='approved' then 'Ajuste de stock aprobado' else 'Ajuste de stock rechazado' end,
   concat_ws(' · ',p.name,q.reason,q.decision_reason),null,null,q.target_quantity-q.expected_quantity,'stock_adjustment_requests',q.id::text
  from public.stock_adjustment_requests q left join public.products p on p.id=q.product_id
  where q.reviewed_at is not null and q.status in ('approved','rejected')
  union all
  select 'validation',e.posted_at,e.posted_by,'entry_posted','Asiento contabilizado',
   concat_ws(' · ',e.memo,e.reference),coalesce(e.erp_reference,e.number),null,null,'accounting_entries',e.id::text
  from public.accounting_entries e where e.posted_at is not null
  union all
  select 'access',a.created_at,a.actor_id,lower(a.table_name||'_'||a.operation),
   case a.table_name when 'profiles' then case a.operation when 'INSERT' then 'Usuario creado' when 'DELETE' then 'Usuario eliminado' else 'Usuario modificado' end
    when 'role_module_access' then 'Módulos de un perfil modificados' else 'Permisos de acción modificados' end,
   concat_ws(' · ',coalesce(a.after_data->>'full_name',a.before_data->>'full_name',a.after_data->>'display_name',a.after_data->>'role',a.before_data->>'role'),
    coalesce(a.after_data->>'email',a.before_data->>'email'),a.after_data->>'module',a.reason),
   null,null,null,a.table_name,a.record_id
  from public.erp_audit_events a where a.table_name in ('profiles','role_module_access','erp_action_permissions')
 )
 select * from ev where ev.at is not null;
end $$;
revoke all on function private.coco_audit_events() from public,anon,authenticated;

-- One canonical projection for the standalone audit trail and embedded history.
do $$declare src text;start_at integer;end_at integer;begin
 src:=pg_get_functiondef('private.gama_audit_trail(jsonb)'::regprocedure);
 start_at:=strpos(src,' with ev(');end_at:=strpos(src,' ), hits as (');
 if start_at=0 or end_at<=start_at then raise exception 'AUDIT_TRAIL_PROJECTION_MISMATCH';end if;
 src:=left(src,start_at-1)||' with ev as (select * from private.coco_audit_events()'||substr(src,end_at);
 execute src;
end $$;

-- Explicit foreign-key relationships only. No matching by name, text or UUID alone.
create function private.coco_audit_links(p_table text,p_id text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r jsonb;ln jsonb:='[]';oid uuid;poid uuid;qid uuid;tid uuid;cid uuid;sid uuid;pid uuid;rid uuid;subtable text;
begin
 if p_table not in ('stock_movements','tms_events','external_invoice_payments','supplier_invoice_payments','return_refunds','external_invoices','supplier_invoices','erp_approvals','stock_adjustment_requests','accounting_entries','profiles','role_module_access','erp_action_permissions') then return ln;end if;
 -- Access changes can concern deleted records and composite role keys.
 if p_table in ('profiles','role_module_access','erp_action_permissions') then
  return jsonb_build_array(jsonb_build_object('module',case when p_table='profiles' then 'users' else 'access-settings' end,'action','module','id',p_id));
 end if;
 execute format('select to_jsonb(t) from public.%I t where id=$1::uuid',p_table) into r using p_id;
 if r is null then return ln;end if;
 if p_table='stock_movements' then
  ln:='[{"module":"warehouses","action":"module"}]';pid:=(r->>'product_id')::uuid;
  case r->>'reference_type'
   when 'purchase_order' then poid:=(r->>'reference_id')::uuid;
   when 'sales_order' then oid:=(r->>'reference_id')::uuid;
   when 'sales_delivery' then select order_id,tms_delivery_id into oid,tid from public.sales_deliveries where id=(r->>'reference_id')::uuid;
   when 'customer_return' then rid:=(r->>'reference_id')::uuid;
   when 'supplier_return' then rid:=(r->>'reference_id')::uuid;
   else null;
  end case;
 elsif p_table='stock_adjustment_requests' then
  ln:='[{"module":"warehouses","action":"module"}]';pid:=(r->>'product_id')::uuid;
 elsif p_table='tms_events' then
  tid:=(r->>'delivery_id')::uuid;select order_id into oid from public.sales_deliveries where tms_delivery_id=tid;
 elsif p_table='erp_approvals' then
  if r->>'module'='credit' then oid:=(r->>'document_id')::uuid;
  elsif r->>'module'='quotes' then qid:=(r->>'document_id')::uuid;
  elsif r->>'module'='gamaPurchasesV14' then poid:=(r->>'document_id')::uuid;end if;
 elsif p_table='accounting_entries' then
  ln:=jsonb_build_array(jsonb_build_object('module','accounting','action','module','id',p_id));
  subtable:=case r->>'source_type' when 'sales_invoice' then 'external_invoices' when 'customer_payment' then 'external_invoice_payments' when 'supplier_invoice' then 'supplier_invoices' when 'supplier_payment' then 'supplier_invoice_payments' when 'return_refund' then 'return_refunds' end;
  if subtable is not null and r->>'source_id' is not null then ln:=ln||private.coco_audit_links(subtable,r->>'source_id');end if;
 elsif p_table in ('external_invoices','external_invoice_payments') then
  ln:='[{"module":"accounting","action":"module"}]';
  if p_table='external_invoice_payments' then select to_jsonb(i) into r from public.external_invoices i where id=(r->>'invoice_id')::uuid;end if;
  ln:=ln||jsonb_build_array(jsonb_build_object('module','payments','action','invoice','id',r->>'id','reference',r->>'number'));oid:=(r->>'order_id')::uuid;
 elsif p_table in ('supplier_invoices','supplier_invoice_payments') then
  if p_table='supplier_invoice_payments' then select to_jsonb(i) into r from public.supplier_invoices i where id=(r->>'supplier_invoice_id')::uuid;end if;
  ln:=jsonb_build_array(jsonb_build_object('module','accounting','action','supplier_invoice','id',r->>'id','reference',r->>'number'));poid:=(r->>'purchase_order_id')::uuid;sid:=(r->>'supplier_id')::uuid;
  -- Invoice matching can link a supplier invoice to more than one purchase.
  ln:=ln||coalesce((select jsonb_agg(jsonb_build_object('module','gamaPurchasesV14','action','purchase','id',m.purchase_order_id)) from public.supplier_invoice_matches m where m.invoice_id=(r->>'id')::uuid),'[]');
 elsif p_table='return_refunds' then rid:=(r->>'return_id')::uuid;ln:='[{"module":"accounting","action":"module"}]';
 end if;
 if rid is not null then
  ln:=ln||jsonb_build_array(jsonb_build_object('module','returns','action','return','id',rid));
  select customer_id,supplier_id,order_id,purchase_order_id into cid,sid,oid,poid from public.return_orders where id=rid;
 end if;
 if oid is not null then
  select source_quote_id,customer_id into qid,cid from public.sales_orders where id=oid;
  ln:=ln||jsonb_build_array(jsonb_build_object('module','sales-orders','action','order','id',oid));
 end if;
 if poid is not null then
  select supplier_id into sid from public.purchase_orders where id=poid;
  ln:=ln||jsonb_build_array(jsonb_build_object('module','gamaPurchasesV14','action','purchase','id',poid));
 end if;
 if qid is not null then ln:=ln||jsonb_build_array(jsonb_build_object('module','quotes','action','quote','id',qid));end if;
 if tid is not null then ln:=ln||jsonb_build_array(jsonb_build_object('module','tms','action','delivery','id',tid));end if;
 if pid is not null then ln:=ln||jsonb_build_array(jsonb_build_object('module','products','action','module','id',pid));end if;
 if cid is not null then ln:=ln||jsonb_build_array(jsonb_build_object('module','contacts','action','module','id',cid));end if;
 if sid is not null then ln:=ln||jsonb_build_array(jsonb_build_object('module','contacts','action','module','id',sid));end if;
 return ln;
end $$;
revoke all on function private.coco_audit_links(text,text) from public,anon,authenticated;

-- Is this precise event already represented by the canonical dossier timeline?
-- This runs before pagination, not against only the currently visible page.
create function private.coco_audit_in_process(p_table text,p_id text,p_at timestamptz,p_action text,p_kind text) returns boolean
language sql stable security definer set search_path='' as $$
 select case
 when p_kind is null then false
 when p_table='tms_events' then true
 when p_table='stock_movements' and p_kind='purchase' then exists(select 1 from public.stock_movements where id=p_id::uuid and reference_type='purchase_order')
 when p_table='external_invoice_payments' and p_action='customer_payment' then true
 when p_table='supplier_invoice_payments' and p_action='supplier_payment' then true
 when p_table in ('external_invoices','supplier_invoices','external_invoice_payments','supplier_invoice_payments') then exists(
  select 1 from public.erp_audit_events a where a.table_name=p_table and a.record_id=p_id and a.created_at=p_at and
  (a.operation='INSERT' and p_table in ('external_invoices','supplier_invoices') or a.operation='UPDATE' and exists(select 1 from unnest(array['status','fiscal_status','received_quantity','processed_at','closed_at','received_at','shipped_on','financial_action','approved_at','cancelled_at','external_status']) f where a.before_data->f is distinct from a.after_data->f)))
 else false end
$$;
revoke all on function private.coco_audit_in_process(text,text,timestamptz,text,text) from public,anon,authenticated;

-- Virtual rows preserve the existing grouping and pagination contract. Nothing
-- is inserted into the index, and original timestamps/authors remain unchanged.
create function private.coco_scoped_audit(p_module text,p_record text default null,p_kind text default null)
returns setof private.coco_module_events
language plpgsql stable security definer set search_path='' as $$
declare e record;ln jsonb;author text;ctx jsonb;key text;refs jsonb;
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('audit',array['administrador']) or not private.coco_module_allowed(p_module) then return;end if;
 if p_kind is not null then
  if p_module is distinct from (case p_kind when 'sales' then 'sales-orders' when 'quote' then 'quotes' when 'purchase' then 'gamaPurchasesV14' when 'tms' then 'tms' end) then raise exception 'INVALID_ORDER_KIND';end if;
  ctx:=private.coco_dossier_context(p_kind,p_record::uuid);
 end if;
 for e in select * from private.coco_audit_events() a where
  case p_module
   when 'users' then a.target_table='profiles'
   when 'access-settings' then a.target_table in ('role_module_access','erp_action_permissions')
   when 'products' then a.target_table in ('stock_movements','stock_adjustment_requests')
   when 'warehouses' then a.target_table in ('stock_movements','stock_adjustment_requests')
   when 'payments' then a.target_table in ('external_invoices','external_invoice_payments','accounting_entries')
   when 'accounting' then a.kind in ('payment','invoice') or a.target_table='accounting_entries'
   when 'tms' then a.target_table in ('tms_events','stock_movements')
   when 'returns' then a.target_table in ('stock_movements','return_refunds','accounting_entries')
   when 'contacts' then a.kind<>'access'
   when 'sales-orders' then a.kind<>'access'
   when 'quotes' then a.kind<>'access'
   when 'gamaPurchasesV14' then a.kind<>'access' and a.kind<>'transfer'
   else false end loop
  -- Financial/access traces retain their originating module restrictions, even
  -- when the associated purchase or contact can be read by another profile.
  if e.kind in ('payment','invoice') and not private.coco_module_allowed(case when e.target_table in ('external_invoices','external_invoice_payments') then 'payments' else 'accounting' end) then continue;end if;
  if e.target_table='accounting_entries' and not private.coco_module_allowed('accounting') then continue;end if;
  if e.kind='stock' and not private.coco_module_allowed('warehouses') then continue;end if;
  if e.kind='transfer' and not private.coco_module_allowed('tms') then continue;end if;
  ln:=private.coco_audit_links(e.target_table,e.target_id);
  if not exists(select 1 from jsonb_array_elements(ln) l where l->>'module'=p_module and (p_record is null or l->>'id'=p_record)) then continue;end if;
  if p_record is not null and p_kind is not null and private.coco_audit_in_process(e.target_table,e.target_id,e.at,e.action,p_kind) then continue;end if;
  select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=e.actor;
  select coalesce(jsonb_agg(distinct l),'[]') into ln from jsonb_array_elements(ln) l where private.coco_module_allowed(l->>'module');
  key:='audit-trail:'||e.target_table||':'||e.target_id||':'||e.action||':'||e.at::text;
  refs:=jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('kind','document','id',e.target_id,'reference',coalesce(e.reference,e.target_id),'name',e.detail,'quantity',e.quantity,'amount',e.amount)));
  return next jsonb_populate_record(null::private.coco_module_events,jsonb_build_object(
   'id',md5(key)::uuid,'module_id',p_module,'record_table',e.target_table,'record_id',e.target_id,
   'type','action','action',e.action,'subject',e.label,'body','','reference',e.reference,
   'actor_id',e.actor,'actor_name',coalesce(author,'AUTHOR_NOT_RECORDED'),'created_at',e.at,
   'transaction_id',hashtextextended('audit:'||e.at::text,0),'references_list',refs,'links',ln,'source_type','audit'));
 end loop;
end $$;
revoke all on function private.coco_scoped_audit(text,text,text) from public,anon;
grant execute on function private.coco_scoped_audit(text,text,text) to authenticated;

-- Merge before grouping/pagination; a precise audit event replaces only its
-- matching generic insert/status trace, never a note, deletion or source link.
do $$declare src text;needle text;replacement text;begin
 src:=pg_get_functiondef('public.coco_module_history_events(text,jsonb)'::regprocedure);
 needle:='with visible as materialized(';
 replacement:=$patch$with audit_rows as materialized (
  select * from private.coco_scoped_audit(m,nullif(p_data->>'record_id',''),nullif(p_data->>'dossier_kind',''))
  where not coalesce((p_data->>'annotations_only')::boolean,false) or coalesce((p_data->>'include_audit')::boolean,false)
 ), combined as (
  select e.* from private.coco_module_events e where not exists(
   select 1 from audit_rows a where a.record_table=e.record_table and a.record_id=e.record_id and a.created_at=e.created_at
    and a.actor_id is not distinct from e.actor_id and e.type='action' and e.proposal_id is null and e.source_type='erp' and
    (e.action='insert' and a.action not in ('customer_payment_cancelled','entry_posted','approval_approved','approval_rejected','adjustment_approved','adjustment_rejected')
     or e.action='status' and a.action in ('customer_payment_cancelled','entry_posted','approval_approved','approval_rejected','adjustment_approved','adjustment_rejected')
     or e.action='update' and a.action in ('profiles_update','role_module_access_update','erp_action_permissions_update')))
  union all select * from audit_rows
 ), visible as materialized($patch$;
 if strpos(src,needle)=0 then raise exception 'MODULE_HISTORY_MERGE_MISMATCH';end if;
 src:=replace(src,needle,replacement);
 src:=replace(src,'select * from private.coco_module_events e where module_id=m','select * from combined e where module_id=m');
 src:=replace(src,$text$or e.action='source_linked'$text$,$text$or e.source_type='audit' or e.action='source_linked'$text$);
 execute src;
end $$;

-- Existing sales/purchase/TMS panels request scoped audit as well as annotations.
do $$declare src text;begin
 src:=pg_get_functiondef('public.coco_dossier(text,jsonb)'::regprocedure);
 if strpos(src,$text$'annotations_only',true$text$)=0 then raise exception 'DOSSIER_AUDIT_MERGE_MISMATCH';end if;
 src:=replace(src,$text$'annotations_only',true$text$,$text$'annotations_only',true,'include_audit',true,'dossier_kind',p_data->>'kind'$text$);
 src:=replace(src,$text$e->>'action'='source_linked'$text$,$text$e->>'source_type'='audit' or e->>'action'='source_linked'$text$);
 execute src;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261018174016','audit_in_module_and_dossier_history','b3c13d258ec1143d0a56b44299bc4b21b2ea5cd43168ee73fec5b217402e3172','b3c13d258ec1143d0a56b44299bc4b21b2ea5cd43168ee73fec5b217402e3172','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261018174935_optimize_audit_history_reads.sql; SHA256 2e9c59e3a0edde15c9a88ef62d57d78f650d14f6d63f78a2b671f0af1e5f2662
-- Cache request-wide module permissions once, keep row visibility correlated.
-- Compare the typed primary key, not id::text, so row checks use their indexes.
do $$declare src text;fn text;needle text;replacement text;begin
 foreach fn in array array['private.coco_history_record_exists(text,text)','private.coco_history_record_visible(text,text,uuid)'] loop
  src:=pg_get_functiondef(fn::regprocedure);
  needle:=$old$execute format('select exists(select 1 from %I.%I where %I::text=$1)',cfg.table_schema,p_table,cfg.key_column)$old$;
  replacement:=$new$execute format('select exists(select 1 from %I.%I where %I=(jsonb_populate_record(null::%I.%I,jsonb_build_object(%L,$1))).%I)',cfg.table_schema,p_table,cfg.key_column,cfg.table_schema,p_table,cfg.key_column,cfg.key_column)$new$;
  if strpos(src,needle)=0 then raise exception 'HISTORY_TYPED_KEY_MISMATCH %',fn;end if;
  execute replace(src,needle,replacement);
 end loop;
 src:=pg_get_functiondef('private.coco_scoped_audit(text,text,text)'::regprocedure);
 src:=replace(src,'key text;refs jsonb;','key text;refs jsonb;allowed_modules text[];');
 src:=replace(src,' for e in select *', ' select array_agg(m.module_id) into allowed_modules from private.coco_history_modules m where private.coco_module_allowed(m.module_id);' || chr(10) || ' for e in select *');
 src:=replace(src,$old$not private.coco_module_allowed(case when e.target_table in ('external_invoices','external_invoice_payments') then 'payments' else 'accounting' end)$old$,$new$not ((case when e.target_table in ('external_invoices','external_invoice_payments') then 'payments' else 'accounting' end)=any(allowed_modules))$new$);
 src:=replace(src,$old$not private.coco_module_allowed('accounting')$old$,$new$not ('accounting'=any(allowed_modules))$new$);
 src:=replace(src,$old$not private.coco_module_allowed('warehouses')$old$,$new$not ('warehouses'=any(allowed_modules))$new$);
 src:=replace(src,$old$not private.coco_module_allowed('tms')$old$,$new$not ('tms'=any(allowed_modules))$new$);
 src:=replace(src,$old$where private.coco_module_allowed(l->>'module')$old$,$new$where l->>'module'=any(allowed_modules)$new$);
 execute src;
 src:=pg_get_functiondef('public.coco_module_history_events(text,jsonb)'::regprocedure);
 src:=replace(src,'ctx jsonb;items jsonb;','ctx jsonb;items jsonb;allowed_modules text[];');
 src:=replace(src,' with audit_rows as materialized (',' select array_agg(h.module_id) into allowed_modules from private.coco_history_modules h where private.coco_module_allowed(h.module_id);' || chr(10) || ' with audit_rows as materialized (');
 src:=replace(src,$old$where private.coco_module_allowed(l->>'module')$old$,$new$where l->>'module'=any(allowed_modules)$new$);
 src:=replace(src,'select e.* from private.coco_module_events e where not exists(', 'select e.* from private.coco_module_events e where e.module_id=m and not exists(');
 execute src;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261018174935','optimize_audit_history_reads','2e9c59e3a0edde15c9a88ef62d57d78f650d14f6d63f78a2b671f0af1e5f2662','2e9c59e3a0edde15c9a88ef62d57d78f650d14f6d63f78a2b671f0af1e5f2662','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261018175229_batch_product_history_visibility.sql; SHA256 0b5af6dad497bb49ff5465980271ba35556f7e5e106cae8d3e3b3425c8522ea5
-- Product imports create thousands of history rows for the same product set.
-- Read that set once under the caller's product RLS, rather than re-running
-- product policies for each historical change. Other record policies stay intact.
alter policy coco_module_events_read on private.coco_module_events using(
 module_id=any((select array_agg(m.module_id) from private.coco_history_modules m where private.coco_module_allowed(m.module_id))::text[])
 and (module_id<>'hr' or private.hr_admin() or actor_id=(select auth.uid()))
 and (proposal_id is null or exists(select 1 from private.coco_module_proposals p where p.id=proposal_id))
 and case
 when record_table='products' then (select private.coco_module_allowed('products')) and (
  record_id=any((select array_agg(p.id::text) from public.products p)::text[])
  or (select private.current_user_role())='administrador' and not private.coco_history_record_exists('products',record_id))
 when record_table is not null then private.coco_history_record_visible(record_table,record_id,record_owner)
 when module_id='hr' then private.hr_admin() or actor_id=(select auth.uid())
 else true end
);
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261018175229','batch_product_history_visibility','0b5af6dad497bb49ff5465980271ba35556f7e5e106cae8d3e3b3425c8522ea5','0b5af6dad497bb49ff5465980271ba35556f7e5e106cae8d3e3b3425c8522ea5','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261018181322_remove_audit_from_module_history.sql; SHA256 64fdd5f291c9c250b397eb442f6d1811b3d9a3c75f1721651665daeae753518a
-- Disconnect audit projections only. Preserve business history, RLS and journals.
do $$declare src text;start_at integer;end_at integer;begin
 src:=pg_get_functiondef('public.coco_module_history_events(text,jsonb)'::regprocedure);
 start_at:=strpos(src,'with audit_rows as materialized (');
 end_at:=strpos(src,'visible as materialized(');
 if start_at=0 or end_at<=start_at then raise exception 'MODULE_HISTORY_AUDIT_DISCONNECT_MISMATCH';end if;
 src:=substr(src,1,start_at-1)||'with '||substr(src,end_at);
 src:=replace(src,'select * from combined e where module_id=m','select * from private.coco_module_events e where module_id=m');
 src:=replace(src,$text$or e.source_type='audit' or e.action='source_linked'$text$,$text$or e.action='source_linked'$text$);
 execute src;
 src:=pg_get_functiondef('public.coco_dossier(text,jsonb)'::regprocedure);
 if strpos(src,$text$'include_audit',true$text$)=0 then raise exception 'DOSSIER_AUDIT_DISCONNECT_MISMATCH';end if;
 src:=replace(src,$text$'annotations_only',true,'include_audit',true,'dossier_kind',p_data->>'kind'$text$,$text$'annotations_only',true$text$);
 src:=replace(src,$text$e->>'source_type'='audit' or e->>'action'='source_linked'$text$,$text$e->>'action'='source_linked'$text$);
 execute src;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261018181322','remove_audit_from_module_history','64fdd5f291c9c250b397eb442f6d1811b3d9a3c75f1721651665daeae753518a','64fdd5f291c9c250b397eb442f6d1811b3d9a3c75f1721651665daeae753518a','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261019185130_audit_catalogue_projection.sql; SHA256 6e4b0afc36efb44bc6e029ec29c53097c91880b6fb0967da006f63451c9767eb
-- Audit proposal: apply only to an isolated database until reviewed.
-- No data migration, cache, index, permission expansion or search_path change.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '15s';
set local search_path = '';
do $guard$
begin
 if pg_catalog.md5(pg_catalog.pg_get_functiondef('storefront_api.gama_storefront(text,jsonb)'::regprocedure)) <> '2020e6d50de194f0302f5f389ac52e42' then
  raise exception 'STOREFRONT_DEFINITION_CHANGED: review the current function before applying this proposal';
 end if;
 if pg_catalog.md5(pg_catalog.pg_get_functiondef('private.gama_storefront_items()'::regprocedure)) <> '7a3f485c7a6c6aa86164708834b95851' then
  raise exception 'STOREFRONT_DEFINITION_CHANGED: review the current function before applying this proposal';
 end if;
end $guard$;
create view private.gama_storefront_projection (id,name,reference,category,category_title,brand,badge,description,featured,unit_price,tax_rate,order_minimum,order_multiple,has_photo)
with (security_invoker = true) as
select p.id,coalesce(nullif(w.public_title,''),p.name),p.reference,coalesce(nullif(p.category,''),'Otros productos'),coalesce(nullif(w.public_category_title,''),coalesce(nullif(p.category,''),'Otros productos')),
 w.public_brand,w.public_badge,coalesce(nullif(w.public_description,''),w.description),w.public_featured,
 case when (s.config->>'show_prices')::boolean and p.sale_price>0 then p.sale_price end,
 case when (s.config->>'show_prices')::boolean and p.sale_price>0 then p.tax_rate end,
 coalesce(p.order_minimum,0),coalesce(p.order_multiple,0),coalesce(p.photo_data ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$',false)
 from public.products p join private.website_products w on w.product_id=p.id and w.public_visible cross join private.website_public_settings s where p.active and s.id;
revoke all on private.gama_storefront_projection from public,anon,authenticated;

-- Inline projection lets PostgreSQL filter before reading/validating photo_data.
-- The original private helper and every access/submit check remain unchanged.
CREATE OR REPLACE FUNCTION storefront_api.gama_storefront(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg jsonb;curr text;term text;cat text;brand_filter text;sortby text;off integer;lim integer;count_items integer;rows jsonb;req uuid;prior private.website_public_inquiries;payload jsonb;visitor text;secret text;
 line jsonb;prod public.products;pid uuid;qty numeric;net numeric;tax numeric;total numeric:=0;lines jsonb:='[]';seen uuid[]:='{}';rid uuid;seq bigint;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>24000 then raise exception 'WEBSITE_INVALID_DATA';end if;
 select config into cfg from private.website_public_settings where id;
 select coalesce(currency,'USD') into curr from public.company_settings limit 1;curr:=coalesce(curr,'USD');
 if not coalesce((cfg->>'site_enabled')::boolean,false) then
  if p_action='bootstrap' then return jsonb_build_object('paused',true,'settings',jsonb_build_object('brand_name',cfg->>'brand_name','phone',cfg->>'phone','email',cfg->>'email'));end if;
  raise exception 'WEBSITE_PUBLIC_PAUSED';
 end if;
 if p_action='bootstrap' then
  -- Bootstrap needs the complete publication set for its category photo IDs.
  -- Evaluate the existing protected projection once, instead of four times.
  with items as materialized (select * from private.gama_storefront_items())
  select jsonb_build_object('paused',false,'settings',cfg,'currency',curr,'total',(select count(*) from items),
   'categories',coalesce((select jsonb_agg(to_jsonb(z)) from(select category,min(category_title) title,count(*) count,min(id::text) filter (where has_photo) photo_id from items group by category order by category) z),'[]'),
   'brands',coalesce((select jsonb_agg(brand order by brand) from(select distinct brand from items where brand<>'') z),'[]'),
   'featured',coalesce((select jsonb_agg(to_jsonb(z)) from(select * from items where featured order by name,id limit 8) z),'[]')) into rows;
  return rows;
 elsif p_action='catalog' then
  term:=left(coalesce(p_data->>'search',''),100);cat:=coalesce(p_data->>'category','');brand_filter:=coalesce(p_data->>'brand','');sortby:=coalesce(nullif(p_data->>'sort',''),cfg->>'default_sort');
  if sortby not in ('featured','name','price_asc','price_desc') then raise exception 'WEBSITE_INVALID_DATA';end if;
  off:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));lim:=greatest(1,least(coalesce((p_data->>'limit')::integer,(cfg->>'page_size')::integer),36));
  select count(*) into count_items from private.gama_storefront_projection i where (term='' or strpos(lower(i.name||' '||coalesce(i.reference,'')||' '||i.brand),lower(term))>0) and (cat='' or i.category=cat) and (brand_filter='' or i.brand=brand_filter);
  -- Select the page before constructing the complete JSON row (including
  -- photo validation). The fence avoids evaluating photo_data for every row.
  with selected as materialized (
   select i.id from private.gama_storefront_projection i where (term='' or strpos(lower(i.name||' '||coalesce(i.reference,'')||' '||i.brand),lower(term))>0) and (cat='' or i.category=cat) and (brand_filter='' or i.brand=brand_filter)
   order by case when sortby='featured' then featured end desc nulls last,case when sortby='price_asc' then unit_price end asc nulls last,case when sortby='price_desc' then unit_price end desc nulls last,name,id limit lim offset off
  ) select coalesce(jsonb_agg(to_jsonb(z)),'[]') into rows from (
   select i.* from selected chosen join private.gama_storefront_projection i on i.id=chosen.id
   order by case when sortby='featured' then featured end desc nulls last,case when sortby='price_asc' then unit_price end asc nulls last,case when sortby='price_desc' then unit_price end desc nulls last,name,i.id
  ) z;
  return jsonb_build_object('items',rows,'total',count_items,'offset',off,'limit',lim,'currency',curr);
 elsif p_action='product' then
  select to_jsonb(i) into rows from private.gama_storefront_projection i where id=(p_data->>'id')::uuid;
  if rows is null then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;return jsonb_build_object('item',rows,'currency',curr);
 elsif p_action='photos' then
  if jsonb_typeof(p_data->'ids') is distinct from 'array' or jsonb_array_length(p_data->'ids')>24 then raise exception 'WEBSITE_INVALID_DATA';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'photo_data',p.photo_data,'photo_is_illustrative',p.photo_is_illustrative)) from public.products p join private.website_products w on w.product_id=p.id and w.public_visible where p.active and p.id in(select value::uuid from jsonb_array_elements_text(p_data->'ids')) and p.photo_data ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$'),'[]');
 elsif p_action='submit' then
  if not (cfg->>'enable_quotes')::boolean then raise exception 'WEBSITE_QUOTES_DISABLED';end if;
  select token into secret from private.website_public_connection where id;
  if coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb->>'x-coco-site-token' is distinct from secret then raise exception 'WEBSITE_SERVER_KEY_REQUIRED';end if;
  if coalesce(p_data->>'website','')<>'' then raise exception 'WEBSITE_INVALID_DATA';end if;
  visitor:=left(coalesce(p_data->>'visitor',''),200);if visitor='' then raise exception 'WEBSITE_VISITOR_REQUIRED';end if;visitor:=md5(secret||visitor);
  req:=nullif(p_data->>'request_key','')::uuid;if req is null then raise exception 'WEBSITE_REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('public-web:'||req,0));payload:=p_data-'request_key'-'visitor'-'website';select * into prior from private.website_public_inquiries where request_key=req;
  if found then if prior.payload is distinct from payload then raise exception 'WEBSITE_REQUEST_KEY_REUSED';end if;return jsonb_build_object('reference','WEB-'||lpad(prior.number::text,8,'0'));end if;
  if (p_data->>'consent') is distinct from 'true' or length(btrim(coalesce(p_data->>'contact_name',''))) not between 2 and 120 or length(coalesce(p_data->>'email',''))>254 or coalesce(p_data->>'email','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
   or length(coalesce(p_data->>'phone',''))>60 or length(coalesce(p_data->>'company',''))>160 or length(coalesce(p_data->>'notes',''))>2000 then raise exception 'WEBSITE_CONTACT_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('public-web-visitor:'||visitor,0));
  if (select count(*) from private.website_public_inquiries where visitor_hash=visitor and created_at>now()-interval '30 minutes')>=8 or (select count(*) from private.website_public_inquiries where email=lower(btrim(p_data->>'email')) and created_at>now()-interval '1 hour')>=5 or (select count(*) from private.website_public_inquiries where created_at>now()-interval '1 day')>=2000 then raise exception 'WEBSITE_RATE_LIMIT';end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 30 then raise exception 'WEBSITE_INVALID_LINES';end if;
  for line in select value from jsonb_array_elements(p_data->'lines') loop
   pid:=(line->>'product_id')::uuid;qty:=(line->>'quantity')::numeric;
   if pid=any(seen) then raise exception 'WEBSITE_DUPLICATE_PRODUCT';end if;seen:=array_append(seen,pid);
   if qty is null or qty<=0 or qty>100000 or qty<>round(qty,3) then raise exception 'WEBSITE_INVALID_QUANTITY';end if;
   select p.* into prod from public.products p join private.website_products w on w.product_id=p.id and w.public_visible where p.id=pid and p.active;
   if not found then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;
   if qty<coalesce(prod.order_minimum,0) or (coalesce(prod.order_multiple,0)>0 and mod(qty,prod.order_multiple)<>0) then raise exception 'WEBSITE_PACK_QUANTITY';end if;
   net:=round(qty*coalesce(prod.sale_price,0),2);tax:=round(net*coalesce(prod.tax_rate,0)/100,2);total:=total+net+tax;
   lines:=lines||jsonb_build_array(jsonb_build_object('product_id',prod.id,'reference',prod.reference,'name',prod.name,'quantity',qty,'unit_price',prod.sale_price,'tax_rate',prod.tax_rate,'subtotal',net,'tax',tax,'total',net+tax,'price_to_confirm',coalesce(prod.sale_price,0)<=0));
  end loop;
  insert into private.website_public_inquiries(request_key,payload,contact_name,email,phone,company,notes,lines,currency,total,visitor_hash,consent_at)
   values(req,payload,btrim(p_data->>'contact_name'),lower(btrim(p_data->>'email')),btrim(coalesce(p_data->>'phone','')),btrim(coalesce(p_data->>'company','')),btrim(coalesce(p_data->>'notes','')),lines,curr,total,visitor,now()) returning id,number into rid,seq;
  return jsonb_build_object('reference','WEB-'||lpad(seq::text,8,'0'));
 end if;
 raise exception 'WEBSITE_INVALID_ACTION';
end $function$
;
commit;


insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261019185130','audit_catalogue_projection','6e4b0afc36efb44bc6e029ec29c53097c91880b6fb0967da006f63451c9767eb','6e4b0afc36efb44bc6e029ec29c53097c91880b6fb0967da006f63451c9767eb','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261019185155_audit_security_gates.sql; SHA256 b55566c3ceacac35d811b756950f7be7ab88c877e978d4eb13d4020111053de4
begin;
set local lock_timeout='3s';
set local statement_timeout='15s';
do $$begin
if md5(pg_get_functiondef('private.coco_agent(text,jsonb)'::regprocedure)) not in ('996966a1e1b944bbc13bc13365a8abda','1d8412a2959929041617ec35616255f8') then raise exception 'AUDIT_SECURITY_DEFINITION_CHANGED';end if;
if md5(pg_get_functiondef('private.erp_mfa_ok()'::regprocedure)) <> 'b427e2c008fc5f49c1be63dc00c1a4f6' then raise exception 'AUDIT_SECURITY_DEFINITION_CHANGED';end if;
end $$;
CREATE OR REPLACE FUNCTION private.coco_agent_executor(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 uid uuid:=auth.uid();cid text:=nullif(auth.jwt()->>'client_id','');cfg private.coco_agent_access;
 cmd private.coco_agent_commands;prod public.products;quant public.stock_quants;
 lines jsonb;line jsonb;payload jsonb;snap jsonb;answer jsonb;receipts jsonb:='[]';
 key uuid;lid uuid;target numeric;qty numeric;total_delta numeric;reason text;kind text;op text;
 all_stock boolean;hash text;err text;off integer;lot_id uuid;lot_qty numeric;cfg_ids text[];cfg_write_ids text[];
begin
 if uid is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>16000 then raise exception 'INVALID_INPUT';end if;
 if p_action in ('settings','configure') then
  if cid is not null or not private.erp_module_allowed('assistant-ia',array['administrador'])
   or not private.erp_action_allowed('settings','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  if p_action='configure' then
   if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' or jsonb_typeof(p_data->'can_write') is distinct from 'boolean'
    or jsonb_typeof(p_data->'client_ids') is distinct from 'array' or jsonb_array_length(p_data->'client_ids')>10 then raise exception 'INVALID_INPUT';end if;
   select coalesce(array_agg(distinct value),'{}') into cfg_ids from jsonb_array_elements_text(p_data->'client_ids');
   if jsonb_typeof(coalesce(p_data->'write_client_ids','[]')) is distinct from 'array' then raise exception 'INVALID_INPUT';end if;
   select coalesce(array_agg(distinct value),'{}') into cfg_write_ids from jsonb_array_elements_text(coalesce(p_data->'write_client_ids','[]'));
   if not (cfg_write_ids <@ cfg_ids) or array_position(cfg_write_ids,null) is not null then raise exception 'INVALID_CLIENT_ID';end if;
   if exists(select 1 from unnest(cfg_ids) x where x is null or x!~'^[A-Za-z0-9_-]{3,200}$') then raise exception 'INVALID_CLIENT_ID';end if;
   insert into private.coco_agent_access(actor_id,enabled,can_write,client_ids,write_client_ids)
    values(uid,(p_data->>'enabled')::boolean,(p_data->>'can_write')::boolean,cfg_ids,cfg_write_ids)
    on conflict(actor_id) do update set enabled=excluded.enabled,can_write=excluded.can_write,
     client_ids=excluded.client_ids,write_client_ids=excluded.write_client_ids,revision=coco_agent_access.revision+1,updated_at=now();
   insert into private.coco_agent_events(actor_id,event,detail) values(uid,'access_changed',p_data);
  end if;
  select * into cfg from private.coco_agent_access where actor_id=uid;
  return jsonb_build_object('enabled',coalesce(cfg.enabled,false),'can_write',coalesce(cfg.can_write,false),
   'client_ids',coalesce(cfg.client_ids,'{}'),'write_client_ids',coalesce(cfg.write_client_ids,'{}'),'revision',cfg.revision,'actor_id',uid);
 end if;
 select * into cfg from private.coco_agent_access where actor_id=uid for share;
 if not found or not cfg.enabled then raise exception 'AGENT_ACCESS_DISABLED';end if;
 if cid is not null and not (cid=any(cfg.client_ids)) then raise exception 'AGENT_CLIENT_NOT_ALLOWED';end if;
 if p_action='search' then
  reason:=btrim(coalesce(p_data->>'query',''));
  if length(reason)<2 or length(reason)>200 then raise exception 'SEARCH_QUERY_REQUIRED';end if;
  select coalesce(jsonb_agg(to_jsonb(r)),'[]') into answer from (
   select p.id,p.name,p.reference,p.base_unit,p.stock,p.lot_tracking
   from public.products p where p.active and p.product_kind='goods' and
    (strpos(lower(p.name),lower(reason))>0 or lower(p.reference)=lower(reason) or p.barcode=reason)
   order by case when lower(p.reference)=lower(reason) then 0 else 1 end,p.name,p.id limit 25) r;
  return jsonb_build_object('items',answer,'limit',25,'as_of',now());
 elsif p_action='stock' then
  select * into prod from public.products where id=(p_data->>'product_id')::uuid and active;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  select coalesce(jsonb_agg(jsonb_build_object('location_id',q.location_id,'location',l.code,'warehouse',w.name,
   'quantity',q.quantity,'reserved',q.reserved_quantity,'available',q.quantity-q.reserved_quantity) order by l.code),'[]') into answer
  from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id join public.warehouses w on w.id=l.warehouse_id where q.product_id=prod.id;
  return jsonb_build_object('product_id',prod.id,'name',prod.name,'reference',prod.reference,'unit',prod.base_unit,
   'lot_tracking',prod.lot_tracking,'locations',answer,'as_of',now());
 elsif p_action='history' then
  off:=greatest(0,least(100000,coalesce((p_data->>'offset')::integer,0)));
  select coalesce(jsonb_agg(to_jsonb(r)),'[]') into answer from (
   select c.id,c.created_at,c.expires_at,c.state,c.payload,c.result,
    case when c.client_id is null then 'Coco ERP' else 'ChatGPT / OAuth' end as channel,
    p.full_name as actor_name
   from private.coco_agent_commands c join public.profiles p on p.id=c.actor_id where c.actor_id=uid
   order by c.created_at desc,c.id desc limit 25 offset off) r;
  return jsonb_build_object('items',answer,'offset',off);
 elsif p_action='status' then
  select * into cmd from private.coco_agent_commands where id=(p_data->>'command_id')::uuid and actor_id=uid and client_id is not distinct from cid;
  if not found then raise exception 'AGENT_COMMAND_NOT_FOUND';end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'reference',a.erp_reference,'status',a.status,'reason',a.reason,'movement_id',a.movement_id)),'[]') into receipts
   from public.stock_adjustment_requests a where a.id in (select (x->>'id')::uuid from jsonb_array_elements(coalesce(cmd.result->'adjustments','[]')) x);
  select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'reference',m.erp_reference,'quantity',m.quantity,'reason',m.reason,'stock_before',m.stock_before,'stock_after',m.stock_after,'user_id',m.user_id,'created_at',m.created_at)),'[]') into lines
   from public.stock_movements m where m.id in (select (x->>'movement_id')::uuid from jsonb_array_elements(receipts) x);
  return jsonb_build_object('command_id',cmd.id,'original_receipt',cmd.result,'adjustments',receipts,'movements',lines,'as_of',now(),
   'status',case when cmd.state='prepared' then case when cmd.expires_at<=now() then 'expired' else 'prepared' end
    when cmd.state='failed' then 'rejected' when exists(select 1 from jsonb_array_elements(receipts) x where x->>'status'='pending') then 'pending_approval'
    when jsonb_array_length(receipts)>0 and jsonb_array_length(lines)=jsonb_array_length(receipts) then 'executed' else 'rejected' end,
   'stock_now',(select coalesce(sum(quantity),0) from public.stock_quants where product_id=(cmd.payload->>'product_id')::uuid));
 elsif p_action not in ('prepare','execute','plan_claim') then raise exception 'INVALID_ACTION';end if;
 if not cfg.can_write or (cid is not null and not(cid=any(cfg.write_client_ids))) or not private.erp_action_allowed('warehouses','create')
  or not private.erp_action_allowed('movement','create') then raise exception 'AGENT_WRITE_NOT_ALLOWED';end if;
 if p_action='plan_claim' then
  if cid is not null then raise exception 'ROLE_NOT_ALLOWED';end if;
  key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('coco-agent-planning:'||uid::text,0));
  if (select count(*) from private.coco_agent_events where actor_id=uid and event='planning' and created_at>now()-interval '1 minute')>=10 then raise exception 'AGENT_RATE_LIMIT';end if;
  insert into private.coco_agent_events(actor_id,event,detail) values(uid,'planning',jsonb_build_object('request_key',key));
  return jsonb_build_object('allowed',true);
 end if;
 if p_action='prepare' then
  key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('coco-agent:'||uid::text||key::text,0));
  select * into cmd from private.coco_agent_commands where actor_id=uid and request_key=key;
  if found then
   if cmd.payload<>p_data or cmd.client_id is distinct from cid then raise exception 'REQUEST_KEY_REUSED';end if;
   return to_jsonb(cmd)-'actor_id'-'client_id'-'access_revision';
  end if;
  if (select count(*) from private.coco_agent_commands where actor_id=uid and created_at>now()-interval '1 minute')>=30 then raise exception 'AGENT_RATE_LIMIT';end if;
  reason:=btrim(coalesce(p_data->>'reason',''));op:=p_data->>'operation';kind:=coalesce(p_data->>'kind','inventory_difference');
  if length(reason)<3 or length(reason)>2000 or op not in ('out','in','adjust') or op is null then raise exception 'INVALID_INPUT';end if;
  if kind not in ('inventory_difference','breakage','loss','expiry','sample','donation','internal_use','opening') then raise exception 'INVALID_ADJUSTMENT_KIND';end if;
  if op<>'out' and kind not in ('inventory_difference','opening') then raise exception 'EXCEPTION_OUT_ONLY';end if;
  all_stock:=coalesce((p_data->>'all_stock')::boolean,false);lid:=nullif(p_data->>'location_id','')::uuid;lot_id:=nullif(p_data->>'lot_id','')::uuid;
  if all_stock and (op<>'out' or lid is not null or p_data ? 'quantity' or p_data ? 'target_quantity') then raise exception 'INVALID_INPUT';end if;
  select * into prod from public.products where id=(p_data->>'product_id')::uuid and active for share;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  if prod.product_kind<>'goods' then raise exception 'STOCK_GOODS_ONLY';end if;
  if prod.lot_tracking and (all_stock or lot_id is null) then raise exception 'AGENT_EXPLICIT_LOT_REQUIRED';end if;
  if not prod.lot_tracking and lot_id is not null then raise exception 'INVALID_LOT';end if;
  if not all_stock and lid is null then raise exception 'LOCATION_REQUIRED';end if;
  if all_stock then
   select coalesce(jsonb_agg(jsonb_build_object('location_id',q.location_id,'location',l.code,'expected_quantity',q.quantity,
    'reserved',q.reserved_quantity,'target_quantity',0) order by q.location_id),'[]') into lines
   from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id join public.warehouses w on w.id=l.warehouse_id
   where q.product_id=prod.id and q.quantity>0;
  else
   select * into quant from public.stock_quants where product_id=prod.id and location_id=lid;
   qty:=(p_data->>'quantity')::numeric;
   if op in ('out','in') and (qty is null or qty::text in ('NaN','Infinity','-Infinity') or qty<=0 or qty<>round(qty,3)) then raise exception 'INVALID_QUANTITY';end if;
   if (op='adjust' and p_data ? 'quantity') or (op<>'adjust' and p_data ? 'target_quantity') then raise exception 'INVALID_INPUT';end if;
   target:=case op when 'out' then coalesce(quant.quantity,0)-qty when 'in' then coalesce(quant.quantity,0)+qty else (p_data->>'target_quantity')::numeric end;
   lines:=jsonb_build_array(jsonb_build_object('location_id',lid,'expected_quantity',coalesce(quant.quantity,0),'reserved',coalesce(quant.reserved_quantity,0),'target_quantity',target));
  end if;
  if jsonb_array_length(lines)=0 then raise exception 'NO_CHANGE';end if;
  if jsonb_array_length(lines)>25 then raise exception 'AGENT_TOO_MANY_LOCATIONS';end if;
  total_delta:=0;
  for line in select value from jsonb_array_elements(lines) loop
   target:=(line->>'target_quantity')::numeric;
   if target is null or target::text in ('NaN','Infinity','-Infinity') or target<0 or target>999999999 or target<>round(target,3) then raise exception 'INVALID_QUANTITY';end if;
   if target<(line->>'reserved')::numeric then raise exception 'RESERVED_EXCEEDS_QUANTITY';end if;
   if target=(line->>'expected_quantity')::numeric then raise exception 'NO_CHANGE';end if;
   perform 1 from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id
    where l.id=(line->>'location_id')::uuid and l.active and w.active;
   if not found then raise exception 'LOCATION_NOT_FOUND';end if;
   total_delta:=total_delta+abs(target-(line->>'expected_quantity')::numeric);
  end loop;
  if jsonb_array_length(lines)>1 and exists(select 1 from public.erp_policies where id and
   ((stock_adjustment_limit is not null and total_delta>stock_adjustment_limit) or
    (stock_adjustment_value_limit is not null and (prod.purchase_price<=0 or total_delta*prod.purchase_price>stock_adjustment_value_limit)))) then
   raise exception 'AGENT_GROUP_APPROVAL_USE_ERP';
  end if;
  if lot_id is not null then
   perform 1 from public.product_lots where id=lot_id and product_id=prod.id;
   if not found then raise exception 'INVALID_LOT';end if;
   select coalesce(sum(quantity),0) into lot_qty from public.stock_lot_balances b where b.lot_id=(p_data->>'lot_id')::uuid and b.location_id=lid;
   if op='out' and lot_qty<qty then raise exception 'LOT_QUANTITY_EXCEEDED';end if;
  end if;
  snap:=jsonb_build_object('product_id',prod.id,'name',prod.name,'reference',prod.reference,'unit',prod.base_unit,'purchase_price',prod.purchase_price,
   'lot_tracking',prod.lot_tracking,'lot_quantity',lot_qty,'lines',lines,'quantity_changed',total_delta,
   'reason',reason,'kind',kind,'operation',op,'all_stock',all_stock,'policies',(select to_jsonb(r) from (select stock_adjustment_limit,stock_adjustment_value_limit,stock_adjustment_approval_kinds from public.erp_policies where id)r));
  hash:=encode(sha256(convert_to(jsonb_build_object('payload',p_data,'snapshot',snap,'actor',uid,'client',cid,'revision',cfg.revision)::text,'UTF8')),'hex');
  insert into private.coco_agent_commands(actor_id,client_id,request_key,payload,snapshot,digest,access_revision)
   values(uid,cid,key,p_data,snap,hash,cfg.revision) returning * into cmd;
  insert into private.coco_agent_events(actor_id,command_id,client_id,event) values(uid,cmd.id,cid,'prepared');
  return to_jsonb(cmd)-'actor_id'-'client_id'-'access_revision';
 end if;
 select * into cmd from private.coco_agent_commands where id=(p_data->>'command_id')::uuid and actor_id=uid for update;
 if not found or cmd.client_id is distinct from cid then raise exception 'AGENT_COMMAND_NOT_FOUND';end if;
 if p_data->'confirmed' is distinct from 'true'::jsonb or p_data->>'digest' is distinct from cmd.digest then raise exception 'AGENT_CONFIRMATION_REQUIRED';end if;
 if cmd.state='submitted' then return cmd.result;end if;
 if cmd.state<>'prepared' then raise exception 'AGENT_COMMAND_CLOSED';end if;
 begin
  if cmd.expires_at<=now() then raise exception 'AGENT_PROPOSAL_EXPIRED';end if;
  if cfg.revision<>cmd.access_revision then raise exception 'AGENT_ACCESS_CHANGED';end if;
  select * into prod from public.products where id=(cmd.payload->>'product_id')::uuid for update;
  if not found or not prod.active or prod.product_kind<>'goods' or prod.lot_tracking is distinct from (cmd.snapshot->>'lot_tracking')::boolean
   or prod.purchase_price is distinct from (cmd.snapshot->>'purchase_price')::numeric
   or prod.name is distinct from cmd.snapshot->>'name' or prod.reference is distinct from cmd.snapshot->>'reference'
   or prod.base_unit is distinct from cmd.snapshot->>'unit' then raise exception 'AGENT_PRODUCT_CHANGED';end if;
  if cmd.snapshot->'policies' is distinct from (select to_jsonb(r) from (select stock_adjustment_limit,stock_adjustment_value_limit,stock_adjustment_approval_kinds from public.erp_policies where id)r) then raise exception 'AGENT_POLICY_CHANGED';end if;
  perform 1 from public.stock_quants where product_id=prod.id order by location_id for update;
  if (cmd.snapshot->>'all_stock')::boolean and exists(select 1 from public.stock_quants q where q.product_id=prod.id and q.quantity>0 and
   not exists(select 1 from jsonb_array_elements(cmd.snapshot->'lines') x where (x->>'location_id')::uuid=q.location_id)) then raise exception 'STOCK_CHANGED_RECOUNT';end if;
  for line in select value from jsonb_array_elements(cmd.snapshot->'lines') loop
   lid:=(line->>'location_id')::uuid;
   select * into quant from public.stock_quants where product_id=prod.id and location_id=lid;
   if coalesce(quant.quantity,0) is distinct from (line->>'expected_quantity')::numeric or coalesce(quant.reserved_quantity,0) is distinct from (line->>'reserved')::numeric then raise exception 'STOCK_CHANGED_RECOUNT';end if;
  end loop;
  if nullif(cmd.payload->>'lot_id','') is not null then
   select coalesce(sum(b.quantity),0) into lot_qty from public.stock_lot_balances b where b.lot_id=(cmd.payload->>'lot_id')::uuid and b.location_id=(cmd.payload->>'location_id')::uuid;
   if lot_qty is distinct from (cmd.snapshot->>'lot_quantity')::numeric then raise exception 'STOCK_CHANGED_RECOUNT';end if;
  end if;
  for line in select value from jsonb_array_elements(cmd.snapshot->'lines') loop
   payload:=jsonb_build_object('request_key',gen_random_uuid(),'product_id',prod.id,'location_id',line->'location_id',
    'expected_quantity',line->'expected_quantity','target_quantity',line->'target_quantity',
    'reason',cmd.snapshot->>'reason','kind',cmd.snapshot->>'kind');
   if nullif(cmd.payload->>'lot_id','') is not null then payload:=payload||jsonb_build_object('lot_id',cmd.payload->>'lot_id');end if;
   answer:=public.gama_adjustment_request('submit',payload);
   receipts:=receipts||jsonb_build_array(answer);
  end loop;
  answer:=jsonb_build_object('command_id',cmd.id,'status',case when exists(select 1 from jsonb_array_elements(receipts) x where x->>'status'='pending') then 'pending_approval' else 'executed' end,
   'adjustments',receipts,'stock_after',(select coalesce(sum(quantity),0) from public.stock_quants where product_id=prod.id),
   'actor_id',uid,'agent','Agent Coco','completed_at',now());
  update private.coco_agent_commands set state='submitted',result=answer where id=cmd.id;
  insert into private.coco_agent_events(actor_id,command_id,client_id,event,detail) values(uid,cmd.id,cid,'submitted',answer);
  return answer;
 exception when others then
  get stacked diagnostics err=message_text;
  if err !~ '^[A-Z][A-Z0-9_]{2,100}$' then err:='AGENT_EXECUTION_FAILED';end if;
  answer:=jsonb_build_object('command_id',cmd.id,'status','rejected','error',err);
  update private.coco_agent_commands set state='failed',result=answer where id=cmd.id;
  insert into private.coco_agent_events(actor_id,command_id,client_id,event,detail) values(uid,cmd.id,cid,'rejected',answer);
  return answer;
 end;
end $function$
;
revoke all on function private.coco_agent_executor(text,jsonb) from public,anon,authenticated,service_role;
-- No existing administrator is locked out before enrollment and recovery setup.
create table private.mfa_enforcement (
 actor_id uuid primary key references public.profiles(id), activated_at timestamptz not null default now()
);
alter table private.mfa_enforcement enable row level security;
revoke all on private.mfa_enforcement from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.erp_mfa_ok()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select (
  auth.uid() is not null
  and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
  and exists(select 1 from auth.users u where u.id=auth.uid() and (u.banned_until is null or u.banned_until<=now()))
  and (
   nullif(auth.jwt()->>'session_id','') is null
   or exists(select 1 from auth.sessions s where s.id::text=auth.jwt()->>'session_id'
    and s.user_id=auth.uid() and (s.not_after is null or s.not_after>now()))
  )
  and (coalesce(auth.jwt()->>'aal'='aal2',false)
   or (not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.status='verified') and not exists(select 1 from private.mfa_enforcement e where e.actor_id=auth.uid())))
 ) or private.automation_delegation_ok()
$function$
;
create function private.coco_security_enrollment(p_action text default 'status') returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();adm boolean;verified boolean;
begin
 if uid is null or nullif(auth.jwt()->>'client_id','') is not null or not exists(
  select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=uid and p.active and p.deleted_at is null
   and (u.banned_until is null or u.banned_until<=now())) then raise exception 'AUTH_REQUIRED';end if;
 select role='administrador' into adm from public.profiles where id=uid;
 select exists(select 1 from auth.mfa_factors where user_id=uid and status='verified') into verified;
 if p_action='activate' then
  if auth.jwt()->>'aal' is distinct from 'aal2' or not verified or not private.erp_mfa_ok() then raise exception 'MFA_VERIFICATION_REQUIRED';end if;
  insert into private.mfa_enforcement(actor_id) values(uid) on conflict do nothing;
 elsif p_action<>'status' then raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('administrator',adm,'verified_factor',verified,'enforced',exists(select 1 from private.mfa_enforcement where actor_id=uid));
end $$;
create function public.coco_security_enrollment(p_action text default 'status') returns jsonb
language sql security invoker set search_path='' as $$select private.coco_security_enrollment(p_action)$$;
revoke all on function public.coco_security_enrollment(text),private.coco_security_enrollment(text) from public,anon,service_role;
grant execute on function public.coco_security_enrollment(text),private.coco_security_enrollment(text) to authenticated;

-- The key is only released to its current authenticated owner. It is never
-- persisted alongside the encrypted IndexedDB payload or included in telemetry.
create table private.offline_proof_keys (
 actor_id uuid primary key references public.profiles(id),
 key_material text not null default encode(sha256(convert_to(gen_random_uuid()::text||gen_random_uuid()::text,'UTF8')),'hex'),
 created_at timestamptz not null default now()
);
alter table private.offline_proof_keys enable row level security;
revoke all on private.offline_proof_keys from public,anon,authenticated,service_role;
create function private.coco_offline_key() returns jsonb language plpgsql security definer set search_path='' as $$
declare material text;
begin
 if auth.uid() is null or nullif(auth.jwt()->>'client_id','') is not null or not private.erp_mfa_ok()
  or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 insert into private.offline_proof_keys(actor_id) values(auth.uid()) on conflict do nothing;
 select key_material into material from private.offline_proof_keys where actor_id=auth.uid();
 return jsonb_build_object('actor_id',auth.uid(),'key',material);
end $$;
create function public.coco_offline_key() returns jsonb language sql security invoker set search_path='' as $$select private.coco_offline_key()$$;
revoke all on function public.coco_offline_key(),private.coco_offline_key() from public,anon,service_role;
grant execute on function public.coco_offline_key(),private.coco_offline_key() to authenticated;

create table private.coco_agent_approvals (
 command_id uuid primary key references private.coco_agent_commands(id),
 receipt uuid not null default gen_random_uuid(), actor_id uuid not null references public.profiles(id),
 digest text not null, session_id text not null, mfa_timestamp bigint not null,
 approved_at timestamptz not null default now(), expires_at timestamptz not null,
 unique(actor_id,session_id,mfa_timestamp)
);
alter table private.coco_agent_approvals enable row level security;
revoke all on private.coco_agent_approvals from public,anon,authenticated,service_role;
-- All legacy execution checks, locks and immutable receipts remain in the
-- inaccessible executor. Only this approval gate can call it.
create or replace function private.coco_agent(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();cid text:=nullif(auth.jwt()->>'client_id','');cmd private.coco_agent_commands;
 cfg private.coco_agent_access; approval private.coco_agent_approvals; stamp bigint;sid text:=nullif(auth.jwt()->>'session_id','');
begin
 if p_action not in ('approvals','approve','execute') then return private.coco_agent_executor(p_action,p_data);end if;
 if uid is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>16000 then raise exception 'INVALID_INPUT';end if;
 select * into cfg from private.coco_agent_access where actor_id=uid for share;
 if not found or not cfg.enabled then raise exception 'AGENT_ACCESS_DISABLED';end if;
 if p_action='approvals' then
  if cid is not null then raise exception 'AGENT_HUMAN_APPROVAL_REQUIRED';end if;
  return jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(
   select c.id,c.digest,c.snapshot,c.created_at,c.expires_at,c.client_id,exists(select 1 from private.coco_agent_approvals a where a.command_id=c.id) approved
   from private.coco_agent_commands c where c.actor_id=uid and c.state='prepared' and c.expires_at>now() order by c.created_at desc limit 50)x));
 end if;
 select * into cmd from private.coco_agent_commands where id=(p_data->>'command_id')::uuid and actor_id=uid for update;
 if not found then raise exception 'AGENT_COMMAND_NOT_FOUND';end if;
 if p_data->>'digest' is distinct from cmd.digest or (p_action='execute' and p_data->'confirmed' is distinct from 'true'::jsonb) then raise exception 'AGENT_CONFIRMATION_REQUIRED';end if;
 if p_action='execute' then
  -- A submitted receipt remains readable on retry, even after approval expiry.
  if cmd.state<>'submitted' and not exists(select 1 from private.coco_agent_approvals a where a.command_id=cmd.id and a.actor_id=uid and a.digest=cmd.digest and a.expires_at>now()) then raise exception 'AGENT_HUMAN_APPROVAL_REQUIRED';end if;
  return private.coco_agent_executor(p_action,p_data);
 end if;
 if cid is not null or auth.jwt()->>'aal' is distinct from 'aal2' or sid is null then raise exception 'AGENT_HUMAN_APPROVAL_REQUIRED';end if;
 if not cfg.can_write or cfg.revision<>cmd.access_revision then raise exception 'AGENT_ACCESS_CHANGED';end if;
 if cmd.state<>'prepared' or cmd.expires_at<=now() then raise exception 'AGENT_PROPOSAL_EXPIRED';end if;
 select * into approval from private.coco_agent_approvals where command_id=cmd.id;
 if found then return jsonb_build_object('receipt',approval.receipt,'expires_at',approval.expires_at);end if;
 select max((a->>'timestamp')::bigint) into stamp from jsonb_array_elements(coalesce(auth.jwt()->'amr','[]')) a
  where a->>'method'='totp' and a->>'timestamp'~'^[0-9]{1,12}$';
 -- One fresh, post-proposal TOTP verification may approve exactly one digest.
 if stamp is null or stamp<=floor(extract(epoch from cmd.created_at)) or stamp<extract(epoch from now())-300 or stamp>extract(epoch from now())+5 then raise exception 'AGENT_FRESH_MFA_REQUIRED';end if;
 insert into private.coco_agent_approvals(command_id,actor_id,digest,session_id,mfa_timestamp,expires_at)
  values(cmd.id,uid,cmd.digest,sid,stamp,cmd.expires_at) returning * into approval;
 insert into private.coco_agent_events(actor_id,command_id,event,detail) values(uid,cmd.id,'human_approved',jsonb_build_object('receipt',approval.receipt,'digest',cmd.digest));
 return jsonb_build_object('receipt',approval.receipt,'expires_at',approval.expires_at);
end $$;
notify pgrst,'reload schema';

commit;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261019185155','audit_security_gates','b55566c3ceacac35d811b756950f7be7ab88c877e978d4eb13d4020111053de4','b55566c3ceacac35d811b756950f7be7ab88c877e978d4eb13d4020111053de4','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261019185158_audit_metrics_context.sql; SHA256 69e442aaf2896165c03473f7867e300575c575747adeff4797049f07de3a59e2
begin;
set local lock_timeout='3s';
set local statement_timeout='15s';
do $$begin if md5(pg_get_functiondef('private.gama_operational_metrics(text,jsonb)'::regprocedure))<>'bdcd67ccd3f722146e0c355d3879bf34' then raise exception 'AUDIT_METRICS_DEFINITION_CHANGED';end if;end $$;
alter table private.operational_metrics
 add column build_id text not null default 'unknown',
 add column display_mode text not null default 'unknown',
 add column browser_family text not null default 'unknown',
 add column cache_state text not null default 'unknown',
 add column device_source text not null default 'viewport',
 add column visit_id uuid,
 add column metric_id text,
 add column value numeric;
alter table private.operational_metrics drop constraint operational_metrics_metric_check;
alter table private.operational_metrics add constraint operational_metrics_metric_check check(metric in ('rpc','navigation','action','vital'));
-- Web Vitals can report again on pagehide. Replace that visit's measurement.
create unique index operational_metrics_vital_once on private.operational_metrics(actor,visit_id,metric_id,operation) where metric='vital';
create or replace function private.gama_operational_metrics(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare item jsonb;n integer;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.deleted_at is null and p.role in ('administrador','comercial','almacenero')) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='record' then
  if jsonb_typeof(p_data->'samples') is distinct from 'array' or jsonb_array_length(p_data->'samples') not between 1 and 50 or octet_length(p_data::text)>64000 then raise exception 'INVALID_DATA';end if;
  perform pg_advisory_xact_lock(hashtextextended('metrics:'||auth.uid(),0));
  select count(*) into n from private.operational_metrics where actor=auth.uid() and recorded_at>=now()-interval '1 minute';if n+jsonb_array_length(p_data->'samples')>1000 then return jsonb_build_object('accepted',0,'limited',true);end if;
  for item in select value from jsonb_array_elements(p_data->'samples') loop
   if coalesce(item->>'module','')!~'^[a-zA-Z0-9_-]{1,64}$' or coalesce(item->>'operation','')!~'^[a-zA-Z0-9_-]{0,64}$'
    or coalesce(item->>'build_id','unknown')!~'^(unknown|[a-f0-9]{40})$'
    or coalesce(item->>'display_mode','unknown') not in ('unknown','browser','pwa')
    or coalesce(item->>'browser_family','unknown') not in ('unknown','chromium','safari','firefox','edge')
    or coalesce(item->>'cache_state','unknown') not in ('unknown','first_visit','return_visit')
    or coalesce(item->>'device_source','viewport')<>'viewport' then raise exception 'INVALID_DATA';end if;
   if item->>'metric'='vital' and (item->>'operation' not in ('LCP','INP','CLS') or item->>'visit_id' is null or coalesce(item->>'metric_id','')!~'^[a-zA-Z0-9_-]{1,100}$' or coalesce((item->>'value')::numeric,-1) not between 0 and 300000) then raise exception 'INVALID_DATA';end if;
   insert into private.operational_metrics(actor,metric,module,operation,duration_ms,success,device,network,build_id,display_mode,browser_family,cache_state,device_source,visit_id,metric_id,value)
    values(auth.uid(),item->>'metric',item->>'module',item->>'operation',(item->>'duration_ms')::integer,(item->>'success')::boolean,item->>'device',item->>'network',coalesce(item->>'build_id','unknown'),coalesce(item->>'display_mode','unknown'),coalesce(item->>'browser_family','unknown'),coalesce(item->>'cache_state','unknown'),'viewport',(item->>'visit_id')::uuid,item->>'metric_id',case when item->>'metric'='vital' then (item->>'value')::numeric end)
    on conflict(actor,visit_id,metric_id,operation) where metric='vital' do update set value=excluded.value,duration_ms=excluded.duration_ms,recorded_at=now();
  end loop;return jsonb_build_object('accepted',jsonb_array_length(p_data->'samples'));
 elsif p_action='report' then
  if not private.erp_module_allowed('access-settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  return jsonb_build_object('as_of',now(),'window_days',7,'rows',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(
   select metric,module,operation,device,network,build_id,display_mode,browser_family,cache_state,count(*) samples,
    case when metric<>'vital' then round((percentile_cont(.5) within group(order by duration_ms))::numeric) end median_ms,
    case when metric<>'vital' and count(*)>=100 then round((percentile_cont(.95) within group(order by duration_ms))::numeric) end p95_ms,
    case when metric='vital' and count(*)>=20 then (percentile_cont(.75) within group(order by value)) end p75_value,
    case when operation='CLS' and metric='vital' then 'score' else 'ms' end unit,
    round(avg(duration_ms)) average_ms,count(*) filter(where not success) errors
   from private.operational_metrics where recorded_at>=now()-interval '7 days'
   group by metric,module,operation,device,network,build_id,display_mode,browser_family,cache_state order by count(*) desc limit 200)z));
 end if;raise exception 'INVALID_ACTION';
end $$;
notify pgrst,'reload schema';
commit;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261019185158','audit_metrics_context','69e442aaf2896165c03473f7867e300575c575747adeff4797049f07de3a59e2','69e442aaf2896165c03473f7867e300575c575747adeff4797049f07de3a59e2','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261019190310_audit_history_product_set.sql; SHA256 09dfe33905448e0d2a762517fd9f3b7bb3f4a40cba618e0aa717a23e469a62ea
-- Keep the caller's products RLS while allowing a hashed membership subplan.
-- ARRAY membership compares against the product set for each historical row.
begin;
set local lock_timeout='3s';
set local statement_timeout='15s';
set local search_path=public;
do $$begin
 if (select pg_catalog.md5(pg_catalog.pg_get_expr(polqual,polrelid)) from pg_catalog.pg_policy where polrelid='private.coco_module_events'::regclass and polname='coco_module_events_read') is distinct from '2f085441af48da9dfcf1f2ebb60cea1d' then raise exception 'HISTORY_POLICY_CHANGED';end if;
end $$;
alter policy coco_module_events_read on private.coco_module_events using(
 module_id=any((select array_agg(m.module_id) from private.coco_history_modules m where private.coco_module_allowed(m.module_id))::text[])
 and (module_id<>'hr' or private.hr_admin() or actor_id=(select auth.uid()))
 and (proposal_id is null or exists(select 1 from private.coco_module_proposals p where p.id=proposal_id))
 and case
 when record_table='products' then (select private.coco_module_allowed('products')) and (
  record_id in (select p.id::text from public.products p)
  or (select private.current_user_role())='administrador' and not private.coco_history_record_exists('products',record_id))
 when record_table is not null then private.coco_history_record_visible(record_table,record_id,record_owner)
 when module_id='hr' then private.hr_admin() or actor_id=(select auth.uid())
 else true end
);
notify pgrst,'reload schema';
commit;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261019190310','audit_history_product_set','09dfe33905448e0d2a762517fd9f3b7bb3f4a40cba618e0aa717a23e469a62ea','09dfe33905448e0d2a762517fd9f3b7bb3f4a40cba618e0aa717a23e469a62ea','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261019225920_history_agent_author.sql; SHA256 68cb5b96a2a24506a2b4843b81f8fa7ef56c567988c56d9235a759648dff29af
-- Chat is the assistant-bridge channel, independent of the AI provider.
-- Never infer an AI author from a missing user alone or from free-form body text.
create function private.coco_history_agent_author() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if new.type='action' and new.source_type='chat' and new.actor_id is null
    and (new.actor_name='AUTHOR_NOT_RECORDED' or btrim(new.actor_name)='') then
  new.actor_name:='Agent Coco';
 end if;
 return new;
end $$;
revoke all on function private.coco_history_agent_author() from public,anon,authenticated,service_role;
create trigger coco_history_agent_author
before insert or update of actor_name,actor_id,source_type,type on private.coco_module_events
for each row execute function private.coco_history_agent_author();

-- Repair only events with an already recorded assistant origin. Keep IDs,
-- timestamps, source labels and all human attribution untouched.
update private.coco_module_events set actor_name='Agent Coco'
where type='action' and source_type='chat' and actor_id is null
 and (actor_name='AUTHOR_NOT_RECORDED' or btrim(actor_name)='');

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261019225920','history_agent_author','68cb5b96a2a24506a2b4843b81f8fa7ef56c567988c56d9235a759648dff29af','68cb5b96a2a24506a2b4843b81f8fa7ef56c567988c56d9235a759648dff29af','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261019230315_agent_write_history.sql; SHA256 eae835f4db65a564e6e6e5ac775671af293d8045eb3027fa8ec50aeea0c1007b
-- The authenticated human account remains in actor_id; the displayed executor
-- is Agent Coco for explicitly identified assistant writes, for every module.
create or replace function private.coco_history_agent_author() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if current_setting('coco.activity_source_type',true)='chat' then
  new.source_type:='chat';
  new.source_id:=coalesce(nullif(current_setting('coco.activity_source_id',true),''),new.source_id);
  new.source_label:=coalesce(nullif(current_setting('coco.activity_source_label',true),''),new.source_label,'Agent Coco');
  new.actor_name:='Agent Coco';
 elsif new.type='action' and new.source_type='chat'
    and new.action not in ('proposal_approved','proposal_rejected') then
  new.actor_name:='Agent Coco';
 end if;
 return new;
end $$;

create function private.coco_order_agent_author() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if current_setting('coco.activity_source_type',true)='chat' then
  new.actor_name:='Agent Coco';
  new.detail:=new.detail||jsonb_build_object('source_type','chat',
   'source_id',nullif(current_setting('coco.activity_source_id',true),''),
   'source_label',coalesce(nullif(current_setting('coco.activity_source_label',true),''),'Agent Coco'));
 end if;
 return new;
end $$;
revoke all on function private.coco_order_agent_author() from public,anon,authenticated,service_role;
create trigger coco_order_agent_author before insert on private.coco_order_entries
for each row execute function private.coco_order_agent_author();

-- Scope provenance to the actual execution, after the existing human approval
-- checks. Restore it even on rejection; subsequent human writes stay human.
create function private.coco_agent_execute_with_history(p_action text,p_data jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare result jsonb;
 old_type text:=coalesce(current_setting('coco.activity_source_type',true),'');
 old_id text:=coalesce(current_setting('coco.activity_source_id',true),'');
 old_label text:=coalesce(current_setting('coco.activity_source_label',true),'');
begin
 perform set_config('coco.activity_source_type','chat',true);
 perform set_config('coco.activity_source_id',coalesce(p_data->>'command_id',''),true);
 perform set_config('coco.activity_source_label','Agent Coco',true);
 result:=private.coco_agent_executor(p_action,p_data);
 perform set_config('coco.activity_source_type',old_type,true);
 perform set_config('coco.activity_source_id',old_id,true);
 perform set_config('coco.activity_source_label',old_label,true);
 return result;
exception when others then
 perform set_config('coco.activity_source_type',old_type,true);
 perform set_config('coco.activity_source_id',old_id,true);
 perform set_config('coco.activity_source_label',old_label,true);
 raise;
end $$;
revoke all on function private.coco_agent_execute_with_history(text,jsonb) from public,anon,authenticated,service_role;

do $$declare src text;needle text;begin
 src:=pg_get_functiondef('private.coco_agent(text,jsonb)'::regprocedure);
 needle:=E'  return private.coco_agent_executor(p_action,p_data);';
 if strpos(src,needle)=0 then raise exception 'AGENT_HISTORY_EXECUTION_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,'  return private.coco_agent_execute_with_history(p_action,p_data);');
 execute src;

 -- Photos are real edits too. Still omit pure version/access-time housekeeping.
 src:=pg_get_functiondef('private.coco_capture_module_event()'::regprocedure);
 needle:=$s$array['updated_at','version','photo_data','data_url','last_seen_at','last_access_at']$s$;
 if strpos(src,needle)=0 then raise exception 'AGENT_HISTORY_CAPTURE_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$s$(case when current_setting('coco.activity_source_type',true)='chat' then array['updated_at','version','last_seen_at','last_access_at'] else array['updated_at','version','photo_data','data_url','last_seen_at','last_access_at'] end)$s$);
 execute src;

 -- Existing dossier screens request annotations only; include the actual AI
 -- business events as well, retaining the same row and module access checks.
 src:=pg_get_functiondef('public.coco_module_history_events(text,jsonb)'::regprocedure);
 needle:=$s$or e.action='source_linked'$s$;
 if strpos(src,needle)=0 then raise exception 'AGENT_MODULE_HISTORY_CONTRACT_CHANGED';end if;
 execute replace(src,needle,$s$or e.source_type='chat' or e.action='source_linked'$s$);
 src:=pg_get_functiondef('public.coco_dossier(text,jsonb)'::regprocedure);
 needle:=$s$e->>'action'='source_linked'$s$;
 if strpos(src,needle)=0 then raise exception 'AGENT_DOSSIER_HISTORY_CONTRACT_CHANGED';end if;
 execute replace(src,needle,$s$e->>'source_type'='chat' or e->>'action'='source_linked'$s$);
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261019230315','agent_write_history','eae835f4db65a564e6e6e5ac775671af293d8045eb3027fa8ec50aeea0c1007b','eae835f4db65a564e6e6e5ac775671af293d8045eb3027fa8ec50aeea0c1007b','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261020174233_agent_central_history.sql; SHA256 c6ccdcfc137eacbd5d40f391cedaa0aaa8e4ba8ca5fe06db2b0ecfc6530b6e53
-- Read existing events in place: no copies, backdating or business mutations.
-- Dossier entries are RPC-only. Reuse their exact context/approval checks before
-- exposing a limited projection, never raw mail, attachments or detail JSON.
create function private.coco_agent_dossier_events() returns setof private.coco_module_events
language plpgsql stable security definer set search_path='' as $$
declare dossier record;e private.coco_order_entries;ctx jsonb;m text;link_action text;
begin
 if auth.uid() is null or not private.coco_module_allowed('assistant-ia') then raise exception 'ROLE_NOT_ALLOWED';end if;
 for dossier in select distinct kind,order_id from private.coco_order_entries
  where type in ('action','note') and (actor_name in ('Agent Coco','ChatGPT') or detail->>'source_type'='chat')
 loop
  m:=case dossier.kind when 'sales' then 'sales-orders' when 'purchase' then 'gamaPurchasesV14' when 'quote' then 'quotes' when 'tms' then 'tms' end;
  if not private.coco_module_allowed(m) then continue;end if;
  begin
   ctx:=private.coco_dossier_context(dossier.kind,dossier.order_id);
  exception when raise_exception then
   if sqlerrm in ('ROLE_NOT_ALLOWED','TMS_ACCESS_DENIED','ORDER_NOT_FOUND','AUTH_OR_MFA_REQUIRED') then continue;end if;
   raise;
  end;
  link_action:=case dossier.kind when 'sales' then 'order' when 'purchase' then 'purchase' when 'quote' then 'quote' else 'delivery' end;
  for e in select * from private.coco_order_entries x where x.kind=dossier.kind and x.order_id is not distinct from dossier.order_id
   and x.type in ('action','note') and (x.actor_name in ('Agent Coco','ChatGPT') or x.detail->>'source_type'='chat')
   and (x.detail->>'proposal_id' is null or (ctx->>'can_review')::boolean)
  loop
   return next jsonb_populate_record(null::private.coco_module_events,jsonb_build_object(
    'id',e.id,'module_id',m,'record_id',e.order_id,'type',e.type,'action',case when e.type='note' then 'note' else e.subject end,
    'subject',e.subject,'body',e.body,'actor_id',e.actor_id,'actor_name','Agent Coco','created_at',e.created_at,
    'source_type','chat','source_id',e.detail->>'source_id','source_label',coalesce(e.detail->>'source_label','Agent Coco'),
    'references_list',case when e.order_id is not null then jsonb_build_array(jsonb_build_object('kind','document','id',e.order_id,'reference',ctx->>'number')) else '[]'::jsonb end,
    'links',jsonb_build_array(jsonb_build_object('module',m,'action',case when e.order_id is null then 'module' else link_action end,'id',e.order_id,'reference',case when e.order_id is not null then ctx->>'number' end))));
  end loop;
 end loop;
end $$;
revoke all on function private.coco_agent_dossier_events() from public,anon,authenticated,service_role;
grant execute on function private.coco_agent_dossier_events() to authenticated;

-- Keep the existing invoker and row policies. Only Agent Coco broadens its
-- scope; other modules keep their current events, notes and proposal behavior.
do $$declare src text;needle text;begin
 src:=pg_get_functiondef('public.coco_module_history_events(text,jsonb)'::regprocedure);
 needle:='select * from private.coco_module_events e where module_id=m';
 if strpos(src,needle)=0 then raise exception 'AGENT_CENTRAL_HISTORY_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$s$select * from private.coco_module_events e where (module_id=m or
   m='assistant-ia' and e.type in ('action','note') and e.action not in ('proposal_approved','proposal_rejected')
   and (e.actor_name in ('Agent Coco','ChatGPT') or e.source_type='chat'))$s$);
 needle:='), grouped as (';
 if strpos(src,needle)=0 then raise exception 'AGENT_CENTRAL_HISTORY_GROUP_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$s$), combined as (
  select * from visible
  union all
  select d.* from (select 1 where m='assistant-ia') gate cross join lateral private.coco_agent_dossier_events() d
 ), grouped as ($s$);
 src:=replace(src,'from visible','from combined');
 -- Restore the first branch of the union (not the grouped source).
 src:=replace(src,E'select * from combined\n  union all',E'select * from visible\n  union all');
 src:=replace(src,'select min(id::text) id,max(created_at) at,','select module_id,min(id::text) id,max(created_at) at,');
 src:=replace(src,'group by case when type=', 'group by module_id,case when type=');
 src:=replace(src,$s$when type='action' and proposal_id is null then transaction_id::text$s$, $s$when type='action' and proposal_id is null and transaction_id is not null then transaction_id::text$s$);
 src:=replace(src,$s$'module_id',m,'at',p.at$s$, $s$'module_id',p.module_id,'at',p.at$s$);
 src:=replace(src,$s$'actor_name',p.actor_name$s$, $s$'actor_name',case when m='assistant-ia' and p.actor_name='ChatGPT' then 'Agent Coco' else p.actor_name end$s$);
 -- A module origin remains reachable even for records with no specific route.
 src:=replace(src,$s$'links',(select$s$, $s$'links',(case when m='assistant-ia' and p.module_id<>m then jsonb_build_array(jsonb_build_object('module',p.module_id,'action','module')) else '[]'::jsonb end)||(select$s$);
 execute src;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261020174233','agent_central_history','c6ccdcfc137eacbd5d40f391cedaa0aaa8e4ba8ca5fe06db2b0ecfc6530b6e53','c6ccdcfc137eacbd5d40f391cedaa0aaa8e4ba8ca5fe06db2b0ecfc6530b6e53','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261020185242_audit_daily_workflows.sql; SHA256 b1f4dfc458dbcd9b64b44efb285554abb7d1ad4ca111c117e4a10831fa80a0ed
-- Audit daily workflows: additive metadata, no business data rewrite, no SRI changes.
-- Coverage reuses the canonical min/max calculation, never the demand forecast.
create function private.coco_replenishment_coverage() returns jsonb
language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(x.data || jsonb_build_object('purchases',coalesce(p.orders,'[]'::jsonb)) order by x.data->>'name',x.product_id),'[]')
 from private.stock_minmax_replenishment_rows() x
 left join lateral (
  select jsonb_agg(jsonb_build_object('id',z.id,'number',z.order_number,'status',z.status,'remaining',z.remaining) order by z.order_number,z.id) orders
  from (select o.id,o.order_number,o.status,sum(greatest(l.quantity-l.received_quantity,0)) remaining
   from public.purchase_order_lines l join public.purchase_orders o on o.id=l.purchase_order_id
   where l.product_id=x.product_id and o.status in ('draft','sent','partial') and l.quantity>l.received_quantity
   group by o.id,o.order_number,o.status) z
 ) p on true
$$;
revoke all on function private.coco_replenishment_coverage() from public,anon,authenticated,service_role;
create or replace function private.gama_stock_insights(p_view text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare can_buy boolean;can_count boolean;rows jsonb;late jsonb:='[]';adjustments jsonb:='[]';counts jsonb:='[]';people jsonb:='[]';begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_view not in ('acciones','rotacion','reabastecimiento','conteos') then raise exception 'INVALID_VIEW';end if;
 can_buy:=private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']);
 can_count:=private.erp_module_allowed('warehouses',array['administrador','almacenero']);
 select coalesce(jsonb_agg(case when can_count then x.data else x.data-'repeated_discrepancies' end order by x.data->>'name'),'[]') into rows from private.stock_insight_rows(can_buy) x;
 if p_view='acciones' and can_buy then
  select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'number',o.order_number,'supplier',s.name,'expected_date',o.expected_date,'days_late',current_date-o.expected_date::date) order by o.expected_date),'[]') into late
   from public.purchase_orders o join public.suppliers s on s.id=o.supplier_id
   where o.status in ('sent','partial') and o.expected_date::date<current_date
    and exists(select 1 from public.purchase_order_lines l where l.purchase_order_id=o.id and l.quantity>l.received_quantity);
 end if;
 if p_view='acciones' and can_count then
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'product_id',r.product_id,'reason',r.reason,'requested_at',r.requested_at) order by r.requested_at desc,r.id desc),'[]') into adjustments from public.stock_adjustment_requests r where r.status='pending';
 end if;
 if p_view in ('acciones','conteos') and can_count then
  select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('assigned_name',p.full_name,'repeat_started',exists(select 1 from public.inventory_counts n where n.repeat_of=c.id and n.status<>'cancelled')) order by case when c.priority='high' then 0 else 1 end,coalesce(c.due_date,c.next_due),c.created_at desc),'[]') into counts
   from public.inventory_counts c left join public.profiles p on p.id=c.assigned_to
   where c.status in ('draft','in_progress') or (c.status='validated' and c.next_due is not null);
  if p_view='conteos' then select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name) order by p.full_name),'[]') into people from public.profiles p where p.active and p.role in ('administrador','almacenero');end if;
 end if;
 return jsonb_build_object('as_of',now(),'today',current_date,'minmax_coverage',case when p_view='reabastecimiento' and can_buy then private.coco_replenishment_coverage() else '[]'::jsonb end,'can_buy',can_buy,'can_count',can_count,'rows',rows,'late_orders',late,'adjustments',adjustments,'counts',counts,'people',people);
end $$;

create or replace function private.gama_automation(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
 declare admin boolean:=private.erp_module_allowed('access-settings',array['administrador']);r private.automation_rules;c private.automation_catalog;
 j private.automation_jobs;e private.automation_exceptions;off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));
 exoff integer:=greatest(0,least(coalesce((p_data->>'exception_offset')::integer,0),100000));extotal integer;rows jsonb;rules jsonb;exceptions jsonb;operation_key uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not admin and not private.erp_module_allowed('notifications',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='rule_save' then
  if not admin or not private.erp_action_allowed('access-settings','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  select * into c from private.automation_catalog where kind=p_data->>'kind';if not found then raise exception 'RULE_NOT_FOUND';end if;
  perform pg_advisory_xact_lock(hashtextextended('automation-rule:'||c.kind,0));
  select * into r from private.automation_rules where kind=c.kind order by version desc limit 1;
  if r.version is distinct from (p_data->>'expected_version')::integer then raise exception 'RULE_CHANGED';end if;
  if jsonb_typeof(p_data->'config') is distinct from 'object' then raise exception 'INVALID_CONFIG';end if;
  if coalesce((p_data->'config'->>'interval_minutes')::integer,c.interval_minutes) not between 1 and 10080 then raise exception 'INVALID_INTERVAL';end if;
  if coalesce((p_data->>'enabled')::boolean,false) and not private.automation_visible(c.module) then raise exception 'ROLE_NOT_ALLOWED';end if;
  insert into private.automation_rules(kind,version,enabled,config,executor,approved_until,approved_by)
   values(c.kind,r.version+1,coalesce((p_data->>'enabled')::boolean,false),p_data->'config',case when c.delegated then auth.uid() end,
    case when c.delegated then now()+make_interval(days=>greatest(1,least(coalesce((p_data->>'delegation_days')::integer,90),90))) end,auth.uid()) returning * into r;
  return to_jsonb(r);
 elsif p_action='run_once' then
  if not admin then raise exception 'ROLE_NOT_ALLOWED';end if;
  operation_key:=nullif(p_data->>'request_key','')::uuid;if operation_key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  operation_key:=private.automation_enqueue(p_data->>'kind','manual:'||operation_key::text,coalesce(p_data->'payload','{}'));
  if operation_key is null then raise exception 'RULE_DISABLED';end if;
  return jsonb_build_object('id',operation_key,'state','queued');
 elsif p_action in ('retry','cancel') then
  select * into j from private.automation_jobs where id=(p_data->>'id')::uuid for update;
  select * into c from private.automation_catalog where kind=j.kind;
  if not found or not admin or not private.automation_visible(c.module) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if j.state not in ('blocked','dead','retry','queued') then raise exception 'JOB_NOT_RETRYABLE';end if;
  select * into r from private.automation_rules where kind=j.kind order by version desc limit 1;
  if p_action='retry' and not r.enabled then raise exception 'RULE_DISABLED';end if;
  update private.automation_jobs set state=case when p_action='retry' then 'queued' else 'cancelled' end,rule_version=r.version,actor=r.executor,
   failures=case when p_action='retry' then 0 else failures end,available_at=now(),updated_at=now(),error_code=null where id=j.id;
  if p_action='cancel' then update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where job_id=j.id;end if;
  return jsonb_build_object('id',j.id,'state',case when p_action='retry' then 'queued' else 'cancelled' end);
 elsif p_action='assign' then
  select * into e from private.automation_exceptions where key=p_data->>'key' for update;
  if not found or not private.automation_visible(e.module) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if not e.active then raise exception 'EXCEPTION_RESOLVED';end if;
  if p_data ? 'expected_updated_at' and e.updated_at is distinct from (p_data->>'expected_updated_at')::timestamptz then raise exception 'FOLLOWUP_CHANGED';end if;
  operation_key:=coalesce(nullif(p_data->>'assigned_to','')::uuid,auth.uid());
  if not exists(select 1 from public.profiles p where p.id=operation_key and p.active and p.role in ('administrador','comercial','almacenero') and (p.id=auth.uid() or admin)) then raise exception 'ASSIGNEE_INVALID';end if;
  if length(btrim(coalesce(p_data->>'next_action','')))<3 then raise exception 'NEXT_ACTION_REQUIRED';end if;
  update private.automation_exceptions set assigned_to=operation_key,next_action=p_data->>'next_action',due_at=nullif(p_data->>'due_at','')::timestamptz,updated_at=now() where automation_exceptions.key=e.key;
  return jsonb_build_object('key',e.key);
 elsif p_action<>'snapshot' then raise exception 'INVALID_ACTION';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into rows from(select job_row.id,job_row.kind,catalog_row.title,catalog_row.module,job_row.source_type,job_row.source_id,job_row.state,job_row.attempts,job_row.created_at,job_row.updated_at,job_row.available_at,job_row.result,job_row.error_code,
  (select coalesce(jsonb_agg(to_jsonb(a) order by a.id desc),'[]') from private.automation_attempts a where a.job_id=job_row.id) attempts_log
  from private.automation_jobs job_row join private.automation_catalog catalog_row on catalog_row.kind=job_row.kind where private.automation_visible(catalog_row.module)
  and (coalesce(p_data->>'state','')='' or job_row.state=p_data->>'state') order by job_row.created_at desc,job_row.id limit 50 offset off)x;
 if admin then select coalesce(jsonb_agg(to_jsonb(x)),'[]') into rules from(select distinct on(rule_row.kind) rule_row.*,catalog_row.module,catalog_row.title,catalog_row.delegated from private.automation_rules rule_row join private.automation_catalog catalog_row using(kind) order by rule_row.kind,rule_row.version desc)x;else rules:='[]';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into exceptions from(select exception_row.*,p.full_name assigned_name from private.automation_exceptions exception_row left join public.profiles p on p.id=exception_row.assigned_to
  where exception_row.active and private.automation_visible(exception_row.module)
  and (coalesce(p_data->>'exception_scope','') not in ('mine','unassigned')
   or p_data->>'exception_scope'='mine' and exception_row.assigned_to=auth.uid()
   or p_data->>'exception_scope'='unassigned' and exception_row.assigned_to is null)
  and (coalesce(p_data->>'exception_due','')<>'overdue' or exception_row.due_at<now()) order by exception_row.due_at nulls last,exception_row.opened_at,exception_row.key limit 50 offset exoff)x;
 select count(*) into extotal from private.automation_exceptions exception_row where exception_row.active and private.automation_visible(exception_row.module)
  and (coalesce(p_data->>'exception_scope','') not in ('mine','unassigned')
   or p_data->>'exception_scope'='mine' and exception_row.assigned_to=auth.uid()
   or p_data->>'exception_scope'='unassigned' and exception_row.assigned_to is null)
  and (coalesce(p_data->>'exception_due','')<>'overdue' or exception_row.due_at<now());
 return jsonb_build_object('viewer_id',auth.uid(),'exception_offset',exoff,'exception_total',extotal,
  'assignees',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(nullif(p.full_name,''),p.role)) order by p.full_name,p.id),'[]') from public.profiles p where p.active and p.role in ('administrador','comercial','almacenero') and (admin or p.id=auth.uid())),
  'as_of',now(),'admin',admin,'rules',rules,'jobs',rows,'exceptions',exceptions,'offset',off,
  'total',(select count(*) from private.automation_jobs job_row join private.automation_catalog catalog_row on catalog_row.kind=job_row.kind where private.automation_visible(catalog_row.module) and (coalesce(p_data->>'state','')='' or job_row.state=p_data->>'state')),
  'pending',(select count(*) from private.automation_jobs job_row join private.automation_catalog catalog_row on catalog_row.kind=job_row.kind where private.automation_visible(catalog_row.module) and job_row.state in ('queued','retry','blocked','dead')));
end $$;

insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column)
 values('automation_exceptions','notifications','Seguimiento de excepción','private','key');
create trigger coco_module_history after update on private.automation_exceptions for each row
 when (old.assigned_to is distinct from new.assigned_to or old.next_action is distinct from new.next_action or old.due_at is distinct from new.due_at)
 execute function private.coco_capture_module_event();
create function private.coco_exception_visible(p_key text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok() and exists(
  select 1 from private.automation_exceptions e where e.key=p_key and private.automation_visible(e.module))
$$;
revoke all on function private.coco_exception_visible(text) from public,anon,service_role;
grant execute on function private.coco_exception_visible(text) to authenticated;
-- Preserve all later history extensions, adding only this narrowly scoped table.
do $patch$ declare body text;begin
 select pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure) into body;
 if position('if cfg.table_schema=''private'' and cfg.table_name in' in body)=0 then raise exception 'HISTORY_PATCH_TARGET_CHANGED';end if;
 body:=replace(body,'if cfg.table_schema=''private'' and cfg.table_name in',
  'if cfg.table_schema=''private'' and cfg.table_name=''automation_exceptions'' then return private.coco_exception_visible(p_id);end if;
 if cfg.table_schema=''private'' and cfg.table_name in');
 execute body;
end $patch$;
-- Read-only price review filter. A small price is a review candidate, not an error.
do $patch$ declare body text;needle text;begin
 select pg_get_functiondef('private.gama_website(text,jsonb)'::regprocedure) into body;
 needle:='and (coalesce(p_data->>''category'','''')='''' or coalesce(nullif(p.category,''''),''Otros productos'')=p_data->>''category'')';
 if (length(body)-length(replace(body,needle,'')))/length(needle)<>2 then raise exception 'WEBSITE_PATCH_TARGET_CHANGED';end if;
 body:=replace(body,needle,needle||' and (coalesce(p_data->>''price_review'','''')<>''true'' or coalesce(p.sale_price,0)<=0.05)');
 execute body;
end $patch$;

-- Administrative review only: no enrollment, role change or new lockout.
create function public.coco_admin_security_review() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.erp_mfa_ok()
  or private.current_user_role()<>'administrador'
  or not private.erp_module_allowed('users',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 return jsonb_build_object('as_of',now(),'administrators',(
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,
   'verified_factor',exists(select 1 from auth.mfa_factors f where f.user_id=p.id and f.status='verified'),
   'enforced',exists(select 1 from private.mfa_enforcement e where e.actor_id=p.id)) order by p.full_name,p.id),'[]')
  from public.profiles p where p.active and p.deleted_at is null and p.role='administrador'));
end $$;
revoke all on function public.coco_admin_security_review() from public,anon,service_role;
grant execute on function public.coco_admin_security_review() to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261020185242','audit_daily_workflows','b1f4dfc458dbcd9b64b44efb285554abb7d1ad4ca111c117e4a10831fa80a0ed','b1f4dfc458dbcd9b64b44efb285554abb7d1ad4ca111c117e4a10831fa80a0ed','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261020190329_history_action_context.sql; SHA256 a420c8330daf1a8292954612539d509ed1ffdf47f107bb26f9ce512d5e9bcd5f
-- Preserve a small, typed account of the actual change, never a row snapshot.
-- This helper is callable only by the existing capture trigger.
create function private.coco_history_change_context(p_module text,p_table text,p_op text,p_before jsonb,p_after jsonb) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb:='{}';changes jsonb:='[]';k text;v jsonb;old_value jsonb;loc text;location_key text;currency_code text;
begin
 if p_module in ('hr','users','access-settings','settings','sri') then return result;end if;
 foreach k in array array['name','title','reference','code','barcode','quantity','reserved_quantity','received_quantity','min_stock','max_stock','sale_price','purchase_price','unit_price','unit_cost','amount','total','subtotal','litres','odometer','active','status','movement_type','type','photo_data','data_url'] loop
  if not (p_after ? k) and not (p_before ? k) then continue;end if;
  v:=p_after->k;old_value:=p_before->k;
  if p_op='UPDATE' and v is not distinct from old_value then continue;end if;
  if k in ('photo_data','data_url') then
   changes:=changes||jsonb_build_array(jsonb_build_object('field','photo','changed',true));
  elsif k in ('name','title','reference','code','barcode') and jsonb_typeof(v)='string' then
   changes:=changes||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('field',k,'before',case when p_op='UPDATE' then left(old_value #>> '{}',180) end,'after',left(v #>> '{}',180))));
  elsif k in ('status','movement_type','type') then
   -- Only bounded status/type codes, never free text or arbitrary detail.
   if (v #>> '{}') !~ '^[[:alnum:]_ -]{1,60}$' then continue;end if;
   changes:=changes||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('field',k,'before',case when p_op='UPDATE' and (old_value #>> '{}') ~ '^[[:alnum:]_ -]{1,60}$' then old_value end,'after',v)));
  elsif jsonb_typeof(v) in ('number','boolean','null') then
   changes:=changes||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('field',k,'before',case when p_op='UPDATE' and jsonb_typeof(old_value) in ('number','boolean') then old_value end,'after',v)));
  end if;
 end loop;
 result:=jsonb_build_object('changes',changes);
 if exists(select 1 from jsonb_array_elements(changes) c where c->>'field' in ('sale_price','purchase_price','unit_price','unit_cost','amount','total','subtotal')) then
  select coalesce(nullif(p_after->>'currency',''),s.currency) into currency_code from public.company_settings s limit 1;
  if currency_code ~ '^[A-Z]{3}$' then result:=result||jsonb_build_object('currency',currency_code);end if;
 end if;
 if p_module='warehouses' then
  foreach location_key in array array['location_id','source_location_id','destination_location_id'] loop
   if p_after->>location_key is null then continue;end if;
   select concat_ws(' · ',w.name,l.code,l.name) into loc from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id where l.id::text=p_after->>location_key;
   if loc is not null then result:=result||jsonb_build_object(replace(location_key,'_id',''),left(loc,220));end if;
  end loop;
 end if;
 return result;
end $$;
revoke all on function private.coco_history_change_context(text,text,text,jsonb,jsonb) from public,anon,authenticated,service_role;

-- Upgrade known document routes. A generic module route remains a module route;
-- its record UUID must never be presented as a supposedly opened document.
create function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb
language sql immutable security invoker set search_path='' as $$
 select jsonb_strip_nulls(jsonb_build_object('module',p_module,'id',p_id,'reference',p_reference,'action',
  case p_table when 'sales_orders' then 'order' when 'purchase_orders' then 'purchase' when 'invoices' then 'quote'
   when 'tms_deliveries' then 'delivery' when 'external_invoices' then 'invoice' when 'supplier_invoices' then 'supplier_invoice'
   when 'business_documents' then 'document' when 'crm_opportunities' then 'opportunity' when 'return_requests' then 'return' else 'module' end))
$$;
revoke all on function private.coco_history_typed_link(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link(text,text,text,text) to authenticated;

do $$declare src text;needle text;begin
 src:=pg_get_functiondef('private.coco_capture_module_event()'::regprocedure);
 src:=replace(src,$s$'reference',p.reference,'name',p.name,$s$,$s$'reference',p.reference,'name',p.name,'unit',p.base_unit,$s$);
 needle:=' insert into private.coco_module_events(';
 if strpos(src,needle)=0 then raise exception 'HISTORY_CONTEXT_CAPTURE_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$s$
 -- One context per affected record: quantities are snapshots, not additive events.
 refs:=(select jsonb_agg(r||jsonb_build_object('record_id',rid,'record_table',tg_table_name,'quantity_mode','snapshot',
  'context',private.coco_history_change_context(cfg.module_id,tg_table_name,tg_op,coalesce(before_row,'{}'),n))) from jsonb_array_elements(refs) r);
 ln:=jsonb_build_array(private.coco_history_typed_link(cfg.module_id,tg_table_name,rid,ref))||(ln-0);
 if cfg.parent_column is not null and parent is not null then
  ln:=ln||jsonb_build_array(private.coco_history_typed_link(cfg.module_id,cfg.parent_table,n->>cfg.parent_column,ref));
 end if;
 if cfg.module_id='warehouses' and n->>'product_id' is not null then
  ln:=ln||jsonb_build_array(jsonb_build_object('module','warehouses','action','stock_product','id',n->>'product_id',
   'reference',refs->0->>'reference'));
 end if;
 if n->>'document_id' is not null then ln:=ln||jsonb_build_array(private.coco_history_typed_link('documents','business_documents',n->>'document_id',null));end if;
 if n->>'sales_order_id' is not null then ln:=ln||jsonb_build_array(private.coco_history_typed_link('sales-orders','sales_orders',n->>'sales_order_id',null));end if;
 if n->>'purchase_order_id' is not null then ln:=ln||jsonb_build_array(private.coco_history_typed_link('gamaPurchasesV14','purchase_orders',n->>'purchase_order_id',null));end if;
 if tg_op='DELETE' then ln:=jsonb_build_array(jsonb_build_object('module',cfg.module_id,'action','module'));end if;
 insert into private.coco_module_events($s$);
 execute src;

 src:=pg_get_functiondef('public.coco_module_history_events(text,jsonb)'::regprocedure);
 needle:='select module_id,min(id::text) id,max(created_at) at,actor_id,max(actor_name) actor_name,type,action,subject,body,';
 if strpos(src,needle)=0 then raise exception 'HISTORY_CONTEXT_GROUP_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$s$select module_id,record_table,min(id::text) id,max(created_at) at,actor_id,max(actor_name) actor_name,type,action,subject,string_agg(distinct nullif(body,''),E'\n') body,$s$);
 src:=replace(src,'record_table,actor_id,type,action,subject,body,','record_table,actor_id,actor_name,type,action,subject,');
 src:=replace(src,$s$'action_count',p.action_count,$s$,$s$'record_table',p.record_table,'action_count',p.action_count,$s$);
 execute src;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261020190329','history_action_context','a420c8330daf1a8292954612539d509ed1ffdf47f107bb26f9ce512d5e9bcd5f','a420c8330daf1a8292954612539d509ed1ffdf47f107bb26f9ce512d5e9bcd5f','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261020193647_business_modules_contracts_expenses_sourcing.sql; SHA256 e54974ef125283c9471dc088f5261b2a0795fe54ead9052a40e737f7279b08eb
-- Internal contracts, expense claims and multi-product supplier consultations.
-- Existing sales, purchasing and accounting gateways remain authoritative.
create table private.customer_contracts (
 id uuid primary key default gen_random_uuid(), name text not null check(length(btrim(name)) between 1 and 100),
 customer_id uuid not null references public.customers(id), delivery_address text not null check(length(btrim(delivery_address)) between 1 and 500),
 lines jsonb not null check(jsonb_typeof(lines)='array' and jsonb_array_length(lines) between 1 and 100),
 price_mode text not null check(price_mode in ('current','fixed')),
 frequency text not null check(frequency in ('weekly','monthly')), interval_count integer not null check(interval_count between 1 and 12),
 anchor_day integer not null check(anchor_day between 1 and 31), start_date date not null, next_date date not null, end_date date,
 active boolean not null default true, automatic boolean not null default true,
 notes text not null default '' check(length(notes)<=2000), last_error text, version integer not null default 1,
 created_by uuid not null references public.profiles(id), updated_at timestamptz not null default now(),
 check(end_date is null or end_date>=start_date)
);
create index customer_contracts_customer on private.customer_contracts(customer_id);
create index customer_contracts_due on private.customer_contracts(next_date) where active;
create index customer_contracts_actor on private.customer_contracts(created_by);
create table private.contract_occurrences (
 id uuid primary key default gen_random_uuid(), contract_id uuid not null references private.customer_contracts(id),
 due_date date not null, order_id uuid unique references public.sales_orders(id),
 status text not null check(status in ('draft','skipped')), created_by uuid references public.profiles(id),
 created_at timestamptz not null default now(), unique(contract_id,due_date)
);
create index contract_occurrences_creator on private.contract_occurrences(created_by);
create table private.expense_claims (
 id uuid primary key references public.expenses(id), employee_id uuid references public.hr_employees(id), vehicle_id uuid references public.fleet_vehicles(id),
 paid_by text not null check(paid_by in ('company','employee')), status text not null default 'draft' check(status in ('draft','submitted','approved','paid','rejected')),
 due_date date not null, purpose text not null default '' check(length(purpose)<=500), reason text not null default '' check(length(reason)<=1000),
 ocr_id uuid unique references private.supplier_ocr_intakes(id), liability_account_id uuid references public.accounting_accounts(id),
 payment_entry_id uuid unique references public.accounting_entries(id), paid_on date, payment_reference text,
 approved_by uuid references public.profiles(id), approved_at timestamptz, created_by uuid not null references public.profiles(id),
 request_fingerprint text, version integer not null default 1, updated_at timestamptz not null default now(),
 check(paid_by<>'employee' or employee_id is not null)
);
create index expense_claims_employee on private.expense_claims(employee_id);
create index expense_claims_vehicle on private.expense_claims(vehicle_id);
create index expense_claims_creator on private.expense_claims(created_by);
create index expense_claims_approver on private.expense_claims(approved_by);
create index expense_claims_liability on private.expense_claims(liability_account_id);
create table private.purchase_consultations (
 id uuid primary key default gen_random_uuid(), name text not null check(length(btrim(name)) between 1 and 120),
 required_on date, lines jsonb not null check(jsonb_typeof(lines)='array' and jsonb_array_length(lines) between 1 and 100),
 status text not null default 'open' check(status in ('open','awarded','cancelled')),
 version integer not null default 1, created_by uuid not null references public.profiles(id), updated_at timestamptz not null default now()
);
create index purchase_consultations_creator on private.purchase_consultations(created_by);
create table private.consultation_offers (
 id uuid primary key default gen_random_uuid(), consultation_id uuid not null references private.purchase_consultations(id),
 supplier_id uuid not null references public.suppliers(id), reference text not null default '' check(length(reference)<=100),
 currency text not null check(currency ~ '^[A-Z]{3}$'), valid_until date not null,
 payment_terms_days integer not null default 0 check(payment_terms_days between 0 and 365),
 lead_days integer not null default 0 check(lead_days between 0 and 365), freight numeric(18,2) not null default 0 check(freight>=0),
 lines jsonb not null check(jsonb_typeof(lines)='array' and jsonb_array_length(lines) between 1 and 100),
 notes text not null default '' check(length(notes)<=2000), purchase_order_id uuid unique references public.purchase_orders(id),
 award_reason text, version integer not null default 1, created_by uuid not null references public.profiles(id), updated_at timestamptz not null default now(),
 unique(consultation_id,supplier_id)
);
create index consultation_offers_supplier on private.consultation_offers(supplier_id);
create index consultation_offers_creator on private.consultation_offers(created_by);
do $$declare t text;begin
 foreach t in array array['customer_contracts','contract_occurrences','expense_claims','purchase_consultations','consultation_offers'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
 end loop;
end $$;

create function private.business_require(p_module text,p_action text default 'view') returns void
language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed(p_module,array['administrador','comercial'])
 or (p_action<>'view' and not private.erp_action_allowed(p_module,p_action)) then raise exception 'ROLE_NOT_ALLOWED';end if;
end $$;
create function private.contract_next(s private.customer_contracts,p_date date) returns date
language plpgsql immutable set search_path='' as $$
#variable_conflict use_column
declare m date;begin
 if s.frequency='weekly' then return p_date+7*s.interval_count;end if;
 m:=(date_trunc('month',p_date)+make_interval(months=>s.interval_count))::date;
 return m+least(s.anchor_day,extract(day from m+interval '1 month -1 day')::integer)-1;
end $$;
create function private.contract_generate(p_id uuid,p_date date,p_skip boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s private.customer_contracts;occ private.contract_occurrences;answer jsonb;ls jsonb;next_day date;today date:=(now() at time zone private.erp_timezone())::date;
begin
 perform private.business_require('contracts','edit');perform private.business_require('sales-orders','create');
 select * into s from private.customer_contracts where id=p_id for update;if not found then raise exception 'NOT_FOUND';end if;
 select * into occ from private.contract_occurrences where contract_id=s.id and due_date=p_date;
 if found then return jsonb_build_object('id',occ.order_id,'status',occ.status,'existing',true);end if;
 if not s.active or p_date is distinct from s.next_date or p_date>today or (s.end_date is not null and p_date>s.end_date) then raise exception 'CONTRACT_NOT_DUE';end if;
 if not exists(select 1 from public.customers where id=s.customer_id and active) then raise exception 'CUSTOMER_REQUIRED';end if;
 insert into private.contract_occurrences(contract_id,due_date,status,created_by) values(s.id,p_date,case when p_skip then 'skipped' else 'draft' end,auth.uid()) returning * into occ;
 if not p_skip then
  select jsonb_agg(x||jsonb_build_object('price_mode',case when s.price_mode='fixed' then 'manual' else 'auto' end,'price_reason','Contrato · '||s.name)) into ls from jsonb_array_elements(s.lines)x;
  answer:=private.gama_sales_action('create',jsonb_build_object('request_key',occ.id,'source','manual','customer_id',s.customer_id,'delivery_address',s.delivery_address,'notes','Contrato · '||s.name||' · '||p_date||E'\n'||s.notes,'lines',ls));
  update private.contract_occurrences set order_id=(answer->>'id')::uuid where id=occ.id;
 end if;
 next_day:=private.contract_next(s,p_date);
 while next_day<=today loop next_day:=private.contract_next(s,next_day);end loop;
 update private.customer_contracts set next_date=next_day,active=(end_date is null or next_day<=end_date),last_error=null,version=version+1,updated_at=now() where id=s.id;
 return jsonb_build_object('id',answer->>'id','status',case when p_skip then 'skipped' else 'draft' end);
end $$;
create function private.coco_contracts(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s private.customer_contracts;target uuid:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());x jsonb;ls jsonb:='[]';p public.products;today date:=(now() at time zone private.erp_timezone())::date;v integer;search text:=left(coalesce(p_data->>'search',''),100);off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>100000 then raise exception 'INVALID_REQUEST';end if;
 perform private.business_require('contracts',case when p_action in ('list','lookups') then 'view' when p_action='save' and coalesce((p_data->>'version')::integer,0)=0 then 'create' else 'edit' end);
 perform private.business_require('sales-orders');
 if p_action='lookups' then
  if p_data->>'kind'='customers' then return coalesce((select jsonb_agg(to_jsonb(r)) from(select id,name,address from public.customers where active and (name ilike '%'||search||'%' or id::text=p_data->>'selected') order by name limit 50)r),'[]');end if;
  return coalesce((select jsonb_agg(to_jsonb(r)) from(select id,name,reference,sale_price,tax_rate from public.products where active and (concat_ws(' ',name,reference,barcode) ilike '%'||search||'%' or id::text=p_data->>'selected') order by name limit 50)r),'[]');
 elsif p_action='list' then
  return jsonb_build_object('today',today,'total',(select count(*) from private.customer_contracts s join public.customers c on c.id=s.customer_id where concat_ws(' ',s.name,c.name) ilike '%'||search||'%'),
   'rows',coalesce((select jsonb_agg(to_jsonb(r)) from(select s.*,c.name customer from private.customer_contracts s join public.customers c on c.id=s.customer_id where concat_ws(' ',s.name,c.name) ilike '%'||search||'%' order by s.active desc,s.next_date,s.id offset off limit 30)r),'[]'),
   'occurrences',coalesce((select jsonb_agg(to_jsonb(r)) from(select o.*,s.name,so.number from private.contract_occurrences o join private.customer_contracts s on s.id=o.contract_id left join public.sales_orders so on so.id=o.order_id order by o.created_at desc limit 100)r),'[]'));
 elsif p_action in ('generate','skip') then return private.contract_generate(target,(p_data->>'due_date')::date,p_action='skip');
 elsif p_action='save' then
  perform pg_advisory_xact_lock(hashtextextended('contract:'||target,0));select * into s from private.customer_contracts where id=target for update;
  if coalesce(s.version,0)<>coalesce((p_data->>'version')::integer,0) then raise exception 'RECORD_CHANGED';end if;
  if not exists(select 1 from public.customers where id=(p_data->>'customer_id')::uuid and active) then raise exception 'CUSTOMER_REQUIRED';end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 100 then raise exception 'INVALID_LINES';end if;
  if exists(select 1 from jsonb_array_elements(p_data->'lines') a group by a->>'product_id' having count(*)>1) then raise exception 'INVALID_LINES';end if;
  for x in select value from jsonb_array_elements(p_data->'lines') loop
   select * into p from public.products where id=(x->>'product_id')::uuid and active;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
   if not coalesce((x->>'quantity')::numeric>0 and (x->>'quantity')::numeric<=100000 and (x->>'quantity')::numeric=round((x->>'quantity')::numeric,3) and (x->>'unit_price')::numeric>=0 and (x->>'unit_price')::numeric<1000000000,false) then raise exception 'INVALID_LINES';end if;
   ls:=ls||jsonb_build_array(jsonb_build_object('product_id',p.id,'name',p.name,'quantity',(x->>'quantity')::numeric,'unit_price',(x->>'unit_price')::numeric,'tax_rate',p.tax_rate));
  end loop;
  if (p_data->>'next_date')::date<today or (p_data->>'next_date')::date<(p_data->>'start_date')::date or (nullif(p_data->>'end_date','') is not null and (p_data->>'next_date')::date>(p_data->>'end_date')::date) then raise exception 'INVALID_DATE';end if;
  if exists(select 1 from private.contract_occurrences where contract_id=target and due_date=(p_data->>'next_date')::date) then raise exception 'CONTRACT_DATE_USED';end if;
  insert into private.customer_contracts(id,name,customer_id,delivery_address,lines,price_mode,frequency,interval_count,anchor_day,start_date,next_date,end_date,active,automatic,notes,created_by)
  values(target,p_data->>'name',(p_data->>'customer_id')::uuid,p_data->>'delivery_address',ls,p_data->>'price_mode',p_data->>'frequency',(p_data->>'interval_count')::integer,extract(day from (p_data->>'next_date')::date),(p_data->>'start_date')::date,(p_data->>'next_date')::date,nullif(p_data->>'end_date','')::date,coalesce((p_data->>'active')::boolean,true),coalesce((p_data->>'automatic')::boolean,true),coalesce(p_data->>'notes',''),auth.uid())
  on conflict(id) do update set name=excluded.name,customer_id=excluded.customer_id,delivery_address=excluded.delivery_address,lines=excluded.lines,price_mode=excluded.price_mode,frequency=excluded.frequency,interval_count=excluded.interval_count,anchor_day=case when customer_contracts.next_date=excluded.next_date then customer_contracts.anchor_day else excluded.anchor_day end,start_date=excluded.start_date,next_date=excluded.next_date,end_date=excluded.end_date,active=excluded.active,automatic=excluded.automatic,notes=excluded.notes,version=customer_contracts.version+1,updated_at=now(),last_error=null;
  return jsonb_build_object('id',target);
 elsif p_action='toggle' then
  select * into s from private.customer_contracts where id=target for update;if not found then raise exception 'NOT_FOUND';end if;
  if s.version is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
  update private.customer_contracts set active=not active,version=version+1,updated_at=now() where id=target;return jsonb_build_object('id',target);
 end if;raise exception 'INVALID_ACTION';end $$;

-- Only this non-exposed job can use the contract's saved delegation. Every run
-- rechecks its author's current rights through the same sales gateway. MFA is
-- never bypassed: when required, preparation waits for an interactive session.
create function private.contract_tick() returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s private.customer_contracts;oldsub text:=coalesce(current_setting('request.jwt.claim.sub',true),'');oldclaims text:=coalesce(current_setting('request.jwt.claims',true),'');n integer:=0;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('contract-tick',0)) then return jsonb_build_object('busy',true);end if;
 for s in select * from private.customer_contracts where active and automatic and next_date<=(now() at time zone private.erp_timezone())::date and (end_date is null or next_date<=end_date) order by next_date,id limit 100 for update skip locked loop
  begin
   perform set_config('request.jwt.claim.sub',s.created_by::text,true);
   perform set_config('request.jwt.claims',jsonb_build_object('sub',s.created_by,'role','authenticated','aal','aal1')::text,true);
   perform private.contract_generate(s.id,s.next_date);n:=n+1;
  exception when others then update private.customer_contracts set last_error=case when sqlerrm ~ '^[A-Z_]+$' then sqlerrm else 'PREPARATION_FAILED' end where id=s.id;
  end;
 end loop;
 perform set_config('request.jwt.claim.sub',oldsub,true);perform set_config('request.jwt.claims',oldclaims,true);
 return jsonb_build_object('prepared',n);
end $$;
select cron.schedule('coco-contract-drafts','25 * * * *','select private.contract_tick()');

create function private.coco_expenses(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare e public.expenses;c private.expense_claims;target uuid;result jsonb;right_name text;f public.financial_accounts;cfg public.company_settings;entry_id uuid;receipt jsonb;ocr private.supplier_ocr_intakes;search text:=left(coalesce(p_data->>'search',''),100);off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));today date:=(now() at time zone private.erp_timezone())::date;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>3600000 then raise exception 'INVALID_REQUEST';end if;
 right_name:=case when p_action in ('list','context','receipts','file') then 'view' when p_action in ('approve','reject') then 'validate' when p_action in ('pay','cancel_payment') then 'pay' when p_action='save' and nullif(p_data->>'id','') is null then 'create' else 'edit' end;
 perform private.business_require('expenses',case when right_name='pay' then 'validate' else right_name end);
 perform private.commercial_require(case when right_name='pay' then 'validate' else right_name end);
 if p_action in ('pay','cancel_payment') and not coalesce((private.gama_accounting_rights()->>'pay')::boolean,false) then raise exception 'PAYMENT_NOT_ALLOWED';end if;
 if p_action='context' then
  return jsonb_build_object('today',today,'rights',private.gama_accounting_rights(),'currency',(select currency from public.company_settings where id),
   'categories',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.expense_categories where active),'[]'),
   'employees',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',full_name) order by full_name) from public.hr_employees where active),'[]'),
   'vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',plate||' · '||brand||' '||model) order by plate) from public.fleet_vehicles where active),'[]'),
   'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.financial_accounts where active and currency=(select currency from public.company_settings where id)),'[]'));
 elsif p_action='list' then
  return jsonb_build_object('total',(select count(*) from public.expenses e where concat_ws(' ',e.reference,e.description) ilike '%'||search||'%'),
   'rows',coalesce((select jsonb_agg(to_jsonb(r)) from(select e.*,coalesce(c.status,e.status) workflow,c.paid_by,c.employee_id,c.vehicle_id,c.purpose,c.due_date,c.reason,c.paid_on,c.payment_reference,c.ocr_id,coalesce(c.version,0) version,p.full_name employee,v.plate,
    exists(select 1 from public.expense_receipts r where r.expense_id=e.id) has_receipt
    from public.expenses e left join private.expense_claims c on c.id=e.id left join public.hr_employees p on p.id=c.employee_id left join public.fleet_vehicles v on v.id=c.vehicle_id
    where concat_ws(' ',e.reference,e.description) ilike '%'||search||'%' order by e.expense_date desc,e.id offset off limit 30)r),'[]'));
 elsif p_action in ('receipts','file') then
  return private.gama_accounting_action(case when p_action='file' then 'expense_receipt_get' else 'expense_receipts' end,p_data);
 elsif p_action='save' then
  target:=nullif(p_data->>'id','')::uuid;
  perform pg_advisory_xact_lock(hashtextextended('claim:'||coalesce(target::text,p_data->>'request_key'),0));
  if target is null then select id into target from public.expenses where request_key=(p_data->>'request_key')::uuid; if found then
   if not exists(select 1 from private.expense_claims where id=target and request_fingerprint=md5(p_data::text)) then raise exception 'REQUEST_KEY_REUSED';end if;
   return jsonb_build_object('id',target,'existing',true);end if;end if;
  if target is not null then select * into e from public.expenses where id=target for update;if not found or e.status<>'draft' then raise exception 'EXPENSE_POSTED';end if;end if;
  select * into c from private.expense_claims where id=target;
  if coalesce(c.version,0)<>coalesce((p_data->>'version')::integer,0) then raise exception 'RECORD_CHANGED';end if;
  if c.status is not null and c.status not in ('draft','rejected') then raise exception 'CLAIM_LOCKED';end if;
  if (p_data->>'expense_date')::date>today or (p_data->>'amount_total')::numeric is distinct from round((p_data->>'amount_untaxed')::numeric+coalesce((p_data->>'tax_amount')::numeric,0),2) then raise exception 'INVALID_AMOUNT';end if;
  if p_data->>'paid_by'='employee' and not exists(select 1 from public.hr_employees where id=nullif(p_data->>'employee_id','')::uuid and active) then raise exception 'EMPLOYEE_REQUIRED';end if;
  if nullif(p_data->>'ocr_id','') is not null then select * into ocr from private.supplier_ocr_intakes where id=(p_data->>'ocr_id')::uuid for update;
   if not found or ocr.state<>'review' or ocr.bill_id is not null then raise exception 'SOURCE_ALREADY_USED';end if;
   if exists(select 1 from private.expense_claims where ocr_id=ocr.id and id is distinct from target) then raise exception 'SOURCE_ALREADY_USED';end if;
  end if;
  result:=private.gama_accounting_action('expense_save',p_data||jsonb_build_object('id',target,'financial_account_id',case when p_data->>'paid_by'='employee' then null else nullif(p_data->>'financial_account_id','') end));
  target:=(result->>'id')::uuid;
  insert into private.expense_claims(id,employee_id,vehicle_id,paid_by,due_date,purpose,ocr_id,created_by,request_fingerprint)
  values(target,nullif(p_data->>'employee_id','')::uuid,nullif(p_data->>'vehicle_id','')::uuid,p_data->>'paid_by',coalesce(nullif(p_data->>'due_date','')::date,today),coalesce(p_data->>'purpose',''),nullif(p_data->>'ocr_id','')::uuid,auth.uid(),md5(p_data::text))
  on conflict(id) do update set employee_id=excluded.employee_id,vehicle_id=excluded.vehicle_id,paid_by=excluded.paid_by,due_date=excluded.due_date,purpose=excluded.purpose,ocr_id=excluded.ocr_id,status='draft',reason='',version=expense_claims.version+1,updated_at=now();
  receipt:=p_data->'receipt';
  if receipt is not null and receipt<>'null'::jsonb then
   if receipt->>'mime_type' not in ('application/pdf','image/jpeg','image/png','image/webp') or receipt->>'data_url' not like 'data:'||(receipt->>'mime_type')||';base64,%' then raise exception 'OCR_FILE_INVALID';end if;
   if not exists(select 1 from public.expense_receipts where expense_id=target and data_url=receipt->>'data_url') then perform private.gama_accounting_action('expense_receipt',receipt||jsonb_build_object('expense_id',target));end if;
  end if;
  if ocr.id is not null and not exists(select 1 from public.expense_receipts where expense_id=target) then
   perform private.gama_accounting_action('expense_receipt',jsonb_build_object('expense_id',target,'filename',ocr.filename,'mime_type',ocr.mime_type,'data_url','data:'||ocr.mime_type||';base64,'||replace(encode(ocr.content,'base64'),E'\n','')));
  end if;
  return result;
 end if;
 target:=(p_data->>'id')::uuid;select * into e from public.expenses where id=target for update;select * into c from private.expense_claims where id=target for update;
 if c.id is null or e.id is null then raise exception 'NOT_FOUND';end if;
 if p_action='pay' and c.status='paid' then return jsonb_build_object('id',target,'existing',true);end if;
 if c.version is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
 if p_action='submit' then
  if c.status not in ('draft','rejected') or e.status<>'draft' then raise exception 'CLAIM_LOCKED';end if;
  if not exists(select 1 from public.expense_receipts where expense_id=target) then raise exception 'RECEIPT_REQUIRED';end if;
  update private.expense_claims set status='submitted',reason='',version=version+1,updated_at=now() where id=target;
 elsif p_action='reject' then
  if c.status<>'submitted' or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  update private.expense_claims set status='rejected',reason=p_data->>'reason',version=version+1,updated_at=now() where id=target;
 elsif p_action='approve' then
  if c.status<>'submitted' or e.status<>'draft' then raise exception 'CLAIM_LOCKED';end if;
  if c.paid_by='company' and e.financial_account_id is null then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
  select * into cfg from public.company_settings where id;
  update private.expense_claims set status='approved',liability_account_id=case when c.paid_by='employee' then cfg.payable_account_id end,approved_by=auth.uid(),approved_at=now(),version=version+1,updated_at=now() where id=target;
  update public.expenses set source_reviewed=true where id=target;
  perform private.gama_accounting_action('expense_post',jsonb_build_object('id',target));
  if c.paid_by='company' then update private.expense_claims set status='paid',paid_on=e.expense_date where id=target;end if;
 elsif p_action='cancel_payment' then
  if c.status<>'paid' or c.paid_by<>'employee' or c.payment_entry_id is null then raise exception 'CLAIM_LOCKED';end if;
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  perform private.gama_accounting_action('entry_reverse',jsonb_build_object('id',c.payment_entry_id,'reason',p_data->>'reason'));
 elsif p_action='pay' then
  if c.status<>'approved' or c.paid_by<>'employee' or e.status<>'posted' then raise exception 'CLAIM_LOCKED';end if;
  if (p_data->>'paid_on')::date>today or (p_data->>'paid_on')::date<e.expense_date or length(btrim(coalesce(p_data->>'reference','')))<3 then raise exception 'INVALID_DATE';end if;
  select * into f from public.financial_accounts where id=(p_data->>'financial_account_id')::uuid and active and currency=e.currency;if not found then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
  entry_id:=private.gama_accounting_book('OD',(p_data->>'paid_on')::date,e.reference,'manual',target,'Reembolso · '||e.description,jsonb_build_array(
   jsonb_build_object('account_id',c.liability_account_id,'label','Reembolso · '||e.reference,'debit',e.amount_total),
   jsonb_build_object('account_id',f.account_id,'financial_account_id',f.id,'label',p_data->>'reference','credit',e.amount_total)));
  update private.expense_claims set status='paid',paid_on=(p_data->>'paid_on')::date,payment_reference=left(p_data->>'reference',180),payment_entry_id=entry_id,version=version+1,updated_at=now() where id=target;
 else raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('id',target);
end $$;

create function private.expense_claim_guard() returns trigger language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare c private.expense_claims;begin
 select * into c from private.expense_claims where id=old.id;if not found then return new;end if;
 if c.status in ('submitted','approved','paid') and (new.amount_total,new.amount_untaxed,new.tax_amount,new.financial_account_id,new.expense_date,new.category_id,new.description,new.currency,new.supplier_id,new.project_id,new.tax_id) is distinct from (old.amount_total,old.amount_untaxed,old.tax_amount,old.financial_account_id,old.expense_date,old.category_id,old.description,old.currency,old.supplier_id,old.project_id,old.tax_id) then raise exception 'CLAIM_LOCKED';end if;
 if new.status='posted' and old.status<>'posted' and c.status<>'approved' then raise exception 'CLAIM_APPROVAL_REQUIRED';end if;
 if new.status='cancelled' and c.status in ('submitted','approved','paid') then raise exception 'CLAIM_LOCKED';end if;
 return new;
end $$;
create trigger expense_claim_guard before update on public.expenses for each row execute function private.expense_claim_guard();

create function private.consultation_quote(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_column
declare o private.consultation_offers;c private.purchase_consultations;ls jsonb;subtotal numeric;tax numeric;begin
 select * into o from private.consultation_offers where id=p_id;select * into c from private.purchase_consultations where id=o.consultation_id;
 with quantities as(select x,ceil(greatest((r->>'quantity')::numeric,(x->>'minimum')::numeric)/(x->>'pack')::numeric)*(x->>'pack')::numeric quantity
  from jsonb_array_elements(o.lines)x join jsonb_array_elements(c.lines)r on r->>'product_id'=x->>'product_id'),
 priced as(select x,quantity,round(quantity*(x->>'unit_cost')::numeric,2) net from quantities)
 select jsonb_agg(x||jsonb_build_object('quantity',quantity)),sum(net),sum(round(net*(x->>'tax_rate')::numeric/100,2)) into ls,subtotal,tax from priced;
 return to_jsonb(o)||jsonb_build_object('lines',ls,'subtotal',subtotal,'tax',tax,'comparison_total',subtotal+o.freight,'supplier',(select name from public.suppliers where id=o.supplier_id),'late',c.required_on is not null and (now() at time zone private.erp_timezone())::date+o.lead_days>c.required_on);
end $$;
create function private.coco_consultations(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare c private.purchase_consultations;o private.consultation_offers;target uuid:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());ls jsonb:='[]';x jsonb;p public.products;result jsonb;q jsonb;search text:=left(coalesce(p_data->>'search',''),100);off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>100000 then raise exception 'INVALID_REQUEST';end if;
 perform private.business_require('gamaPurchasesV14',case when p_action in ('list','get','lookups') then 'view' when p_action='award' then 'create' when coalesce((p_data->>'version')::integer,0)=0 then 'create' else 'edit' end);
 if p_action='lookups' then
  if p_data->>'kind'='suppliers' then return coalesce((select jsonb_agg(to_jsonb(r)) from(select id,name from public.suppliers where active and name ilike '%'||search||'%' order by name limit 50)r),'[]');end if;
  return coalesce((select jsonb_agg(to_jsonb(r)) from(select id,name,reference,purchase_price,tax_rate from public.products where active and concat_ws(' ',name,reference,barcode) ilike '%'||search||'%' order by name limit 50)r),'[]');
 elsif p_action='list' then
  return jsonb_build_object('total',(select count(*) from private.purchase_consultations where name ilike '%'||search||'%'),'rows',coalesce((select jsonb_agg(to_jsonb(r)) from(select c.*,(select count(*) from private.consultation_offers o where o.consultation_id=c.id) offers from private.purchase_consultations c where name ilike '%'||search||'%' order by updated_at desc,id offset off limit 30)r),'[]'));
 elsif p_action='get' then
  select * into c from private.purchase_consultations where id=target;if not found then raise exception 'NOT_FOUND';end if;
  return to_jsonb(c)||jsonb_build_object('currency',(select currency from public.company_settings where id),'offers',coalesce((select jsonb_agg(private.consultation_quote(id) order by updated_at) from private.consultation_offers where consultation_id=target),'[]'));
 elsif p_action='save' then
  perform pg_advisory_xact_lock(hashtextextended('consultation:'||target,0));select * into c from private.purchase_consultations where id=target for update;
  if coalesce(c.version,0)<>coalesce((p_data->>'version')::integer,0) then raise exception 'RECORD_CHANGED';end if;
  if c.status is not null and c.status<>'open' then raise exception 'RECORD_CHANGED';end if;
  if exists(select 1 from private.consultation_offers where consultation_id=target) then raise exception 'CONSULTATION_HAS_OFFERS';end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 100 then raise exception 'INVALID_LINES';end if;
  for x in select value from jsonb_array_elements(p_data->'lines') loop
   select * into p from public.products where id=(x->>'product_id')::uuid and active;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
   if not coalesce((x->>'quantity')::numeric>0 and (x->>'quantity')::numeric<=100000 and (x->>'quantity')::numeric=round((x->>'quantity')::numeric,3),false) then raise exception 'INVALID_LINES';end if;
   if exists(select 1 from jsonb_array_elements(ls)l where l->>'product_id'=p.id::text) then raise exception 'INVALID_LINES';end if;
   ls:=ls||jsonb_build_array(jsonb_build_object('product_id',p.id,'name',p.name,'quantity',(x->>'quantity')::numeric,'tax_rate',p.tax_rate));
  end loop;
  insert into private.purchase_consultations(id,name,required_on,lines,created_by) values(target,p_data->>'name',nullif(p_data->>'required_on','')::date,ls,auth.uid())
  on conflict(id) do update set name=excluded.name,required_on=excluded.required_on,lines=excluded.lines,version=purchase_consultations.version+1,updated_at=now();return jsonb_build_object('id',target);
 elsif p_action='offer_save' then
  select * into c from private.purchase_consultations where id=(p_data->>'consultation_id')::uuid for update;if not found or c.status<>'open' then raise exception 'RECORD_CHANGED';end if;
  select * into o from private.consultation_offers where id=target for update;
  if coalesce(o.version,0)<>coalesce((p_data->>'version')::integer,0) or (o.id is not null and o.consultation_id<>c.id) then raise exception 'RECORD_CHANGED';end if;
  if not exists(select 1 from public.suppliers where id=(p_data->>'supplier_id')::uuid and active) then raise exception 'SUPPLIER_REQUIRED';end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines')<>jsonb_array_length(c.lines) then raise exception 'OFFER_INCOMPLETE';end if;
  for x in select value from jsonb_array_elements(p_data->'lines') loop
   if not exists(select 1 from jsonb_array_elements(c.lines)r where r->>'product_id'=x->>'product_id') or exists(select 1 from jsonb_array_elements(ls)r where r->>'product_id'=x->>'product_id') then raise exception 'OFFER_INCOMPLETE';end if;
   if not coalesce((x->>'unit_cost')::numeric>=0 and (x->>'unit_cost')::numeric<1000000000 and (x->>'unit_cost')::numeric=round((x->>'unit_cost')::numeric,2) and (x->>'minimum')::numeric>0 and (x->>'minimum')::numeric<=100000 and (x->>'pack')::numeric>0 and (x->>'pack')::numeric<=100000 and (x->>'tax_rate')::numeric between 0 and 100,false) then raise exception 'INVALID_LINES';end if;
   ls:=ls||jsonb_build_array(jsonb_build_object('product_id',x->>'product_id','unit_cost',(x->>'unit_cost')::numeric,'minimum',(x->>'minimum')::numeric,'pack',(x->>'pack')::numeric,'tax_rate',(x->>'tax_rate')::numeric));
  end loop;
  insert into private.consultation_offers(id,consultation_id,supplier_id,reference,currency,valid_until,payment_terms_days,lead_days,freight,lines,notes,created_by)
  values(target,c.id,(p_data->>'supplier_id')::uuid,coalesce(p_data->>'reference',''),p_data->>'currency',(p_data->>'valid_until')::date,(p_data->>'payment_terms_days')::integer,(p_data->>'lead_days')::integer,(p_data->>'freight')::numeric,ls,coalesce(p_data->>'notes',''),auth.uid())
  on conflict(id) do update set supplier_id=excluded.supplier_id,reference=excluded.reference,currency=excluded.currency,valid_until=excluded.valid_until,payment_terms_days=excluded.payment_terms_days,lead_days=excluded.lead_days,freight=excluded.freight,lines=excluded.lines,notes=excluded.notes,version=consultation_offers.version+1,updated_at=now();return jsonb_build_object('id',target);
 elsif p_action='award' then
  select pc.* into c from private.purchase_consultations pc join private.consultation_offers qo on qo.consultation_id=pc.id where qo.id=target for update of pc;
  select * into o from private.consultation_offers where id=target for update;if not found then raise exception 'NOT_FOUND';end if;
  if o.purchase_order_id is not null then return jsonb_build_object('id',o.purchase_order_id,'existing',true);end if;
  if c.status<>'open' or o.version is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
  if o.currency is distinct from (select currency from public.company_settings where id) or o.valid_until<(now() at time zone private.erp_timezone())::date then raise exception 'OFFER_EXPIRED_OR_CURRENCY';end if;
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  q:=private.consultation_quote(o.id);
  result:=private.gama_purchase_save(jsonb_build_object('request_key',o.id,'supplier_id',o.supplier_id,'expected_date',(now() at time zone private.erp_timezone())::date+o.lead_days,'notes','Consulta · '||c.name||' · '||o.reference||E'\nPago: '||o.payment_terms_days||' días. Transporte adicional cotizado: '||o.freight||' '||o.currency||E' (no incluido en las líneas de mercancía).\n'||o.notes,'lines',q->'lines'));
  update private.consultation_offers set purchase_order_id=(result->>'id')::uuid,award_reason=p_data->>'reason',version=version+1,updated_at=now() where id=o.id;
  update private.purchase_consultations set status='awarded',version=version+1,updated_at=now() where id=c.id;return result;
 end if;raise exception 'INVALID_ACTION';end $$;

create function public.coco_contracts(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.coco_contracts(p_action,p_data)$$;
create function public.coco_expenses(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.coco_expenses(p_action,p_data)$$;
create function public.coco_consultations(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.coco_consultations(p_action,p_data)$$;
revoke all on function private.business_require(text,text),private.contract_next(private.customer_contracts,date),private.contract_generate(uuid,date,boolean),private.contract_tick(),private.expense_claim_guard(),private.consultation_quote(uuid),private.coco_contracts(text,jsonb),private.coco_expenses(text,jsonb),private.coco_consultations(text,jsonb),public.coco_contracts(text,jsonb),public.coco_expenses(text,jsonb),public.coco_consultations(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.coco_contracts(text,jsonb),private.coco_expenses(text,jsonb),private.coco_consultations(text,jsonb),public.coco_contracts(text,jsonb),public.coco_expenses(text,jsonb),public.coco_consultations(text,jsonb) to authenticated;

-- Attribute the two configuration records; DDL itself stays in the migration ledger.
select set_config('coco.activity_source_type','chat',true);
select set_config('coco.activity_source_id','coco-business-modules-20261020',true);
select set_config('coco.activity_source_label','Agent Coco · Modules métier',true);
alter table public.app_modules disable trigger coco_module_history;
insert into public.app_modules(id,enabled) values('contracts',true),('expenses',true) on conflict(id) do nothing;
alter table public.app_modules enable trigger coco_module_history;
insert into private.coco_history_modules(module_id,label,roles) values('contracts','Contratos',array['administrador','comercial']),('expenses','Gastos y justificantes',array['administrador','comercial']);
insert into private.coco_history_tables(table_name,module_id,label,table_schema) values
 ('customer_contracts','contracts','Contrato recurrente','private'),('contract_occurrences','contracts','Pedido del contrato','private'),
 ('expense_claims','expenses','Nota de gastos','private'),('purchase_consultations','gamaPurchasesV14','Consulta a proveedores','private'),('consultation_offers','gamaPurchasesV14','Oferta de proveedor','private');
do $$declare t text;begin foreach t in array array['customer_contracts','contract_occurrences','expense_claims','purchase_consultations','consultation_offers'] loop
 execute format('create trigger coco_module_history after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',t);
end loop;end $$;

-- Keep the function OID: existing event/proposal RLS policies must use the extension.
do $patch$ declare body text;needle text:='if cfg.table_schema=''private'' and cfg.table_name in';begin
 select pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure) into body;
 if position(needle in body)=0 then raise exception 'HISTORY_PATCH_TARGET_CHANGED';end if;
 body:=replace(body,needle,$insert$if cfg.table_schema='private' and cfg.table_name in ('customer_contracts','contract_occurrences') then return private.erp_module_allowed('sales-orders',array['administrador','comercial']);end if;
 if cfg.table_schema='private' and cfg.table_name='expense_claims' then return private.gama_accounting_rights()->>'scope'='all' and private.gama_accounting_may('view');end if;
 if cfg.table_schema='private' and cfg.table_name in ('purchase_consultations','consultation_offers') then return private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']);end if;
 $insert$||needle);execute body;
end $patch$;

-- Both consumers lock the same original before linking it to an accounting document.
do $patch$ declare body text;needle text:='elsif p_action=''draft'' then';begin
 select pg_get_functiondef('private.gama_supplier_ocr(text,jsonb)'::regprocedure) into body;
 if position(needle in body)=0 then raise exception 'OCR_PATCH_TARGET_CHANGED';end if;
 body:=replace(body,needle,needle||'
  if exists(select 1 from private.expense_claims where ocr_id=r.id) then raise exception ''SOURCE_ALREADY_USED'';end if;');execute body;
end $patch$;

-- Approved employee reimbursements remain outgoing until the balanced payment is recorded.
create or replace function private.cash_projection(p_data jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_column
declare today date:=(now() at time zone private.erp_timezone())::date;s private.cash_scenarios;balance numeric;events jsonb;weeks jsonb;begin
 perform private.commercial_require();
 if nullif(p_data->>'scenario_id','') is not null then select * into s from private.cash_scenarios where id=(p_data->>'scenario_id')::uuid;if not found then raise exception 'NOT_FOUND';end if;end if;
 select coalesce(sum(current_balance),0) into balance from private.gama_cash_position where active;
 with source as(
 select 'receivable' kind,d.document_id id,d.number label,coalesce(d.due_date,today)+coalesce(s.customer_delay,0) due,round(d.balance*coalesce(s.collection_percent,100)/100,2) amount,'in' direction,d.due_date is null missing_date from private.gama_customer_dues() d where d.balance>0
 union all select 'payable',d.document_id,d.number,coalesce(d.due_date,today)+coalesce(s.supplier_delay,0),d.balance,'out',d.due_date is null from private.gama_ec_schedule() d join public.supplier_invoices p on p.id=d.document_id and p.status='posted' where d.side='supplier' and d.balance>0
 union all select 'purchase',p.id,p.order_number,coalesce(p.expected_date::date,today)+coalesce(s.supplier_delay,0),greatest(0,p.total-coalesce((select sum(i.total) from public.supplier_invoices i where i.purchase_order_id=p.id and i.status='posted'),0)),'out',p.expected_date is null from public.purchase_orders p where p.status in ('sent','partial','received')
 union all select 'payroll',null::uuid,'Nómina · '||p.period::text,(p.period+interval '1 month -1 day')::date,sum(greatest(0,p.net-coalesce((select sum(q.amount) from public.hr_payroll_payments q where q.payroll_id=p.id and q.status='confirmed'),0))),'out',false from public.hr_payroll p where p.status='validated' group by p.period
 union all select 'expense_claim',e.id,e.reference,c.due_date,e.amount_total,'out',false from private.expense_claims c join public.expenses e on e.id=c.id where c.status='approved' and c.paid_by='employee' and e.status='posted' and e.currency=(select currency from public.company_settings where id)
 union all select c.kind,c.id,c.label,(c.due_date+make_interval(months=>n))::date,c.amount,c.direction,false from private.cash_commitments c cross join generate_series(0,120)n where c.active and (n=0 or c.repeat_monthly) and ((not c.repeat_monthly and n=0 and c.due_date<=today+90) or (c.repeat_monthly and (c.due_date+make_interval(months=>n))::date between today and today+90)) and (c.end_date is null or (c.due_date+make_interval(months=>n))::date<=c.end_date)
 ),bounded as(select *,greatest(today,due) planned_date from source where amount>0 and due<=today+90)
 select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'id',id,'label',label,'due_date',due,'planned_date',planned_date,'amount',amount,'direction',direction,'missing_date',missing_date,'basis',case when kind in ('receivable','payable','expense_claim') or (kind='payroll' and id is null) then 'recorded' else 'planned' end) order by planned_date,kind,id),'[]') into events from bounded;
 with buckets as(select n,today+n*7 starts,today+least(90,n*7+6) ends from generate_series(0,12)n),totals as(select b.*,coalesce(sum((e->>'amount')::numeric) filter(where e->>'direction'='in'),0) incoming,coalesce(sum((e->>'amount')::numeric) filter(where e->>'direction'='out'),0) outgoing from buckets b left join jsonb_array_elements(events)e on (e->>'planned_date')::date between b.starts and b.ends group by b.n,b.starts,b.ends),running as(select *,balance+sum(incoming-outgoing) over(order by n) closing from totals)
 select jsonb_agg(jsonb_build_object('from',starts,'to',ends,'incoming',incoming,'outgoing',outgoing,'closing',closing,'below_minimum',closing<coalesce(s.minimum_balance,0)) order by n) into weeks from running;
 return jsonb_build_object('today',today,'currency',(select currency from public.company_settings where id),'balance',balance,'minimum_balance',coalesce(s.minimum_balance,0),'weeks',weeks,'events',events,'scenarios',coalesce((select jsonb_agg(to_jsonb(x)-'created_by' order by name) from private.cash_scenarios x),'[]'),'commitments',coalesce((select jsonb_agg(to_jsonb(x)-'created_by' order by due_date,label) from private.cash_commitments x where active),'[]'));
end $$;


-- Reversal from either the claim or the ledger reopens the same payable.
create function private.expense_reimbursement_reversed() returns trigger language plpgsql security definer set search_path='' as $$begin
 if old.status='posted' and new.status='reversed' then
  update private.expense_claims set status='approved',paid_on=null,payment_reference=null,version=version+1,updated_at=now()
  where payment_entry_id=new.id and status='paid' and paid_by='employee';
 end if;return new;
end $$;
revoke all on function private.expense_reimbursement_reversed() from public,anon,authenticated,service_role;
create trigger expense_reimbursement_reversed after update of status on public.accounting_entries for each row execute function private.expense_reimbursement_reversed();

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261020193647','business_modules_contracts_expenses_sourcing','e54974ef125283c9471dc088f5261b2a0795fe54ead9052a40e737f7279b08eb','226152caae5d81e09823f85c7d72fea5f6efe218b7f332adc5a7e78fddbb06d1','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261020195939_agent_approval_queue.sql; SHA256 7e55293892c85c302ca3028f5ba11bfbc233bdbb3585248b1b947c3731db9c41
-- Human-reviewed queue. Ingestion and preview never perform business writes.
alter table private.coco_module_proposals drop constraint coco_module_proposals_action_check;
alter table private.coco_module_proposals add constraint coco_module_proposals_action_check check(action in
 ('contact_draft','absence_request','document_create','fuel_log','accounting_entry','record_note','bank_settlement'));
create or replace function private.coco_proposal_payload(a text,p jsonb) returns jsonb
language sql immutable set search_path='' as $$
 select coalesce(jsonb_object_agg(key,value),'{}') from jsonb_each(coalesce(p,'{}')) where key=any(case a
 when 'bank_settlement' then array['bank_id','invoice_id']
 when 'contact_draft' then array['first_name','last_name','email','phone','job_title','company','customer_id','lead_id']
 when 'absence_request' then array['employee_id','kind','start_date','end_date']
 when 'document_create' then array['title','folder','visibility','customer_id','supplier_id','employee_id','file']
 when 'fuel_log' then array['vehicle_id','logged_on','litres','amount','odometer','station','document_id']
 when 'accounting_entry' then array['journal','entry_date','reference','memo','lines','document_id']
 else array['body'] end)
$$;
revoke all on function private.coco_proposal_payload(text,jsonb) from public,anon,authenticated;


-- Keep existing typed validators; bank previews include all consequential values
-- in the review hash, and lock in the same order as the canonical settlement.
alter function private.coco_module_validate(private.coco_module_proposals,jsonb) rename to coco_module_validate_base;
create function private.coco_module_validate(p private.coco_module_proposals,raw jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d jsonb; b public.bank_transactions; i record; a public.financial_accounts; c uuid;
begin
 if p.action<>'bank_settlement' then return private.coco_module_validate_base(p,raw);end if;
 if p.module_id<>'accounting' or not private.coco_module_reviewer('accounting') or nullif(auth.jwt()->>'client_id','') is not null then raise exception 'ROLE_NOT_ALLOWED';end if;
 if not private.erp_action_allowed('accounting','validate') or not private.erp_module_allowed('payments',array['administrador','comercial'])
 or not private.erp_action_allowed('payments','create') or not private.erp_action_allowed('payments','validate') then raise exception 'NOT_ALLOWED';end if;
 d:=private.coco_proposal_payload(p.action,raw);
 select * into b from public.bank_transactions where id=(d->>'bank_id')::uuid;
 if not found then raise exception 'TRANSACTION_NOT_FOUND';end if;
 perform pg_advisory_xact_lock(hashtextextended('bank-match:'||b.financial_account_id::text,0));
 select * into b from public.bank_transactions where id=b.id for update;
 select o.customer_id into c from public.external_invoices v join public.sales_orders o on o.id=v.order_id where v.id=(d->>'invoice_id')::uuid;
 perform 1 from public.customers where id=c for update;
 perform 1 from public.external_invoices where id=(d->>'invoice_id')::uuid for update;
 if b.status<>'unmatched' or b.amount<=0 or exists(select 1 from public.bank_invoice_settlements where bank_id=b.id) then raise exception 'BANK_ALREADY_MATCHED';end if;
 select r.*,v.fiscal_status,o.status order_status into i from private.gama_receivables r join public.external_invoices v on v.id=r.id join public.sales_orders o on o.id=r.order_id where r.id=(d->>'invoice_id')::uuid;
 if not found or i.balance<b.amount or i.payment_status in ('paid','cancelled') or i.fiscal_status in ('cancelled','rejected') or i.order_status<>'confirmed' then raise exception 'AMOUNT_EXCEEDS_BALANCE';end if;
 select * into a from public.financial_accounts where id=b.financial_account_id and active and account_id is not null and kind in ('bank','card') and currency=(select currency from public.company_settings where id);
 if not found then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 if not private.gama_accounting_period_open(b.value_date) then raise exception 'PERIOD_CLOSED';end if;
 return jsonb_build_object('payload',d,'details',jsonb_build_array(i.number||' · '||i.customer_name,a.name||' · '||a.currency,b.value_date::text,coalesce(b.reference,'')||' · '||coalesce(b.description,'')),
 'settlement',jsonb_build_object('invoice',i.number,'customer',i.customer_name,'customer_id',i.customer_id,'financial_account_id',a.id,'accounting_account_id',a.account_id,'account',a.name,'currency',a.currency,'amount',b.amount,'balance_before',i.balance,'balance_after',i.balance-b.amount,'date',b.value_date,'bank_reference',b.reference,'invoice_status',i.payment_status,'fiscal_status',i.fiscal_status));
end $$;
revoke all on function private.coco_module_validate(private.coco_module_proposals,jsonb) from public,anon,authenticated;
create or replace function private.coco_module_proposal_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p private.coco_module_proposals;r jsonb;h text;author text;rid uuid;parent uuid;v_result jsonb;pl jsonb;ctx jsonb;v jsonb;
begin
 select * into p from private.coco_module_proposals where id=(p_data->>'proposal_id')::uuid and module_id=p_data->>'module_id' for update;
 if p.id is null or not private.coco_module_reviewer(p.module_id) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='approve_proposal' and p.status='approved' then return p.result;end if;
 if p.status<>'pending' then raise exception 'PROPOSAL_DECIDED';end if;
 if p_action='review_proposal' then
  r:=private.coco_module_validate(p,coalesce(p_data->'payload',p.payload));h:=md5(p.id::text||auth.uid()::text||r::text);
  update private.coco_module_proposals set review=r,review_hash=h,reviewed_by=auth.uid(),reviewed_at=now() where id=p.id;
  return jsonb_build_object('hash',h,'review',r,'action',p.action);
 end if;
 if p_action='approve_proposal' then
  if p.review_hash is null or p.review_hash is distinct from p_data->>'hash' or p.reviewed_by is distinct from auth.uid() or p.reviewed_at<now()-interval '10 minutes' then raise exception 'PROPOSAL_CHANGED';end if;
  r:=private.coco_module_validate(p,p.review->'payload');h:=md5(p.id::text||auth.uid()::text||r::text);
  if h<>p.review_hash then raise exception 'PROPOSAL_CHANGED';end if;
  pl:=r->'payload';
  perform set_config('coco.activity_source_type',p.source_type,true);perform set_config('coco.activity_source_id',p.source_id,true);perform set_config('coco.activity_source_label',p.source_label,true);
  if p.action='bank_settlement' then
   v_result:=public.gama_bank_invoice_action('settle',pl||jsonb_build_object('request_key',p.id));rid:=(pl->>'invoice_id')::uuid;
  elsif p.action='contact_draft' then
   perform pg_advisory_xact_lock(hashtextextended('coco-contact:'||(pl->>'email'),0));
   perform private.coco_module_validate(p,pl);
   parent:=nullif(pl->>'lead_id','')::uuid;
   if nullif(pl->>'customer_id','') is null and parent is null then
    insert into public.crm_leads(kind,first_name,last_name,company,email,phone,job_title,owner_id,created_by)
    values(case when nullif(pl->>'company','') is null then 'particular' else 'empresa' end,pl->>'first_name',pl->>'last_name',nullif(pl->>'company',''),pl->>'email',pl->>'phone',pl->>'job_title',auth.uid(),auth.uid()) returning id into parent;
   end if;
   v_result:=public.gama_contact_person_save(null,pl||jsonb_build_object('lead_id',parent));rid:=(v_result->>'id')::uuid;
  elsif p.action='absence_request' then
   perform pg_advisory_xact_lock(hashtextextended('coco-absence:'||(pl->>'employee_id'),0));perform private.coco_module_validate(p,pl);
   insert into public.hr_absences(employee_id,kind,start_date,end_date,status,start_fraction,end_fraction)
   values((pl->>'employee_id')::uuid,pl->>'kind',(pl->>'start_date')::date,(pl->>'end_date')::date,'pendiente',1,1) returning id into rid;
  elsif p.action='document_create' then
   v_result:=public.gama_save_business_document(pl||jsonb_build_object('id',p.id),0,pl->'file');rid:=(v_result->>'id')::uuid;
  elsif p.action='fuel_log' then
   v_result:=public.gama_fleet_action('fuel_save',pl||jsonb_build_object('request_key',p.id));rid:=(v_result->>'id')::uuid;
  elsif p.action='accounting_entry' then
   v_result:=public.gama_accounting_action('entry_manual',pl||jsonb_build_object('request_key',p.id));rid:=(v_result->>'id')::uuid;
  end if;
  v_result:=coalesce(v_result,'{}'::jsonb)||jsonb_build_object('module',p.module_id,'id',rid,'action',p.action);
 else
  if p_action<>'reject_proposal' then raise exception 'INVALID_ACTION';end if;
  v_result:=jsonb_build_object('status','rejected');
 end if;
 update private.coco_module_proposals set status=case when p_action='approve_proposal' then 'approved' else 'rejected' end,decided_at=now(),decided_by=auth.uid(),result=v_result where id=p.id;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
 insert into private.coco_module_events(module_id,type,action,subject,body,actor_id,actor_name,proposal_id,source_type,source_id,source_label,source_email,links)
 values(p.module_id,'action',p_action,case when p_action='approve_proposal' then 'proposal_approved' else 'proposal_rejected' end,
  case when p.module_id='hr' then 'Solicitud RH revisada.' when p_action='approve_proposal' and p.action='record_note' then r->'payload'->>'body' else p.summary end,
  auth.uid(),author,p.id,p.source_type,p.source_id,p.source_label,p.source_email,
  case when rid is not null then jsonb_build_array(jsonb_build_object('module',p.module_id,'action','module','id',rid)) else '[]'::jsonb end);
 return v_result;
end $$;
revoke all on function private.coco_module_proposal_action(text,jsonb) from public,anon;
grant execute on function private.coco_module_proposal_action(text,jsonb) to authenticated;


-- A narrow draft creator: the browser selects an existing invoice and bank row.
-- No arbitrary SQL, RPC name, amount, or paid status is accepted from the client.
create function private.coco_queue_prepare_bank(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p private.coco_module_proposals; r jsonb; old private.coco_module_proposals;
begin
 if auth.uid() is null or not private.coco_module_allowed('assistant-ia') or private.current_user_role()<>'administrador' then raise exception 'ROLE_NOT_ALLOWED';end if;
 p.account_id:=auth.uid();p.module_id:='accounting';p.action:='bank_settlement';p.payload:=private.coco_proposal_payload(p.action,p_data);
 r:=private.coco_module_validate(p,p.payload);
 -- Bank lock held by validator serializes duplicate preparation.
 select * into old from private.coco_module_proposals where action=p.action and payload->>'bank_id'=p.payload->>'bank_id' and status='pending' order by created_at limit 1;
 if found then
  if old.account_id<>auth.uid() or old.payload<>p.payload then raise exception 'PROPOSAL_ALREADY_PENDING';end if;
  return jsonb_build_object('id',old.id,'status',old.status,'reused',true);
 end if;
 p.id:=gen_random_uuid();p.summary:=(r->'settlement'->>'invoice')||' · '||(r->'settlement'->>'amount')||' '||(r->'settlement'->>'currency');
 insert into private.coco_module_proposals(id,account_id,module_id,action,source_type,source_id,source_label,received_at,summary,payload)
 values(p.id,p.account_id,p.module_id,p.action,'chat','bank-review:'||p.id,'Agent Coco · rapprochement bancaire',now(),p.summary,p.payload);
 insert into private.coco_module_events(module_id,type,action,subject,body,actor_id,actor_name,proposal_id,source_type,source_id,source_label)
 values('accounting','action','propose','proposal_pending',p.summary,auth.uid(),'Agent Coco',p.id,'chat','bank-review:'||p.id,'Agent Coco · rapprochement bancaire');
 return jsonb_build_object('id',p.id,'status','pending');
end $$;
revoke all on function private.coco_queue_prepare_bank(jsonb) from public,anon;
grant execute on function private.coco_queue_prepare_bank(jsonb) to authenticated;

-- Invoker listing retains proposal RLS and current source-module permissions.
create function public.coco_action_queue(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare rows jsonb; total bigint; item jsonb; p private.coco_module_proposals; result jsonb; results jsonb:='[]';
 st text:=coalesce(p_data->>'status','pending');off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));
 old_type text:=current_setting('coco.activity_source_type',true);old_id text:=current_setting('coco.activity_source_id',true);old_label text:=current_setting('coco.activity_source_label',true);
begin
 if auth.uid() is null or private.current_user_role()<>'administrador' or not private.coco_module_allowed('assistant-ia')
 or nullif(auth.jwt()->>'client_id','') is not null then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='prepare_bank' then return private.coco_queue_prepare_bank(p_data);end if;
 if p_action='list' then
  if st not in ('pending','approved','rejected') then raise exception 'INVALID_STATUS';end if;
  select count(*) into total from private.coco_module_proposals x where x.status=st and private.coco_module_reviewer(x.module_id);
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into rows from (
   select id,module_id,action,summary,source_type,source_label,created_at,status,decided_at from private.coco_module_proposals x
   where x.status=st and private.coco_module_reviewer(x.module_id) order by created_at desc,id limit 25 offset off
  ) x;
  return jsonb_build_object('rows',rows,'total',total);
 end if;
 if p_action not in ('review_batch','approve_batch','reject_batch') then raise exception 'INVALID_ACTION';end if;
 if jsonb_typeof(p_data->'items') is distinct from 'array' or jsonb_array_length(p_data->'items') not between 1 and 25 then raise exception 'INVALID_BATCH';end if;
 if (select count(distinct value->>'id') from jsonb_array_elements(p_data->'items'))<>jsonb_array_length(p_data->'items') then raise exception 'INVALID_BATCH';end if;
 if p_action in ('approve_batch','reject_batch') and p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'CONFIRMATION_REQUIRED';end if;
 -- Stable lock order avoids competing batches deadlocking on the proposal rows.
 for item in select value from jsonb_array_elements(p_data->'items') order by value->>'id' loop
  begin
   select * into p from private.coco_module_proposals where id=(item->>'id')::uuid;
   if not found or not private.coco_module_reviewer(p.module_id) then raise exception 'ROLE_NOT_ALLOWED';end if;
   result:=private.coco_module_proposal_action(case p_action when 'review_batch' then 'review_proposal' when 'approve_batch' then 'approve_proposal' else 'reject_proposal' end,
    jsonb_build_object('proposal_id',p.id,'module_id',p.module_id,'hash',item->>'hash'));
   results:=results||jsonb_build_array(jsonb_build_object('id',p.id,'ok',true,'summary',p.summary,'result',result));
  exception when others then
   -- Do not expose SQL details or private rows in batch errors.
   results:=results||jsonb_build_array(jsonb_build_object('id',item->>'id','ok',false,'error',case when sqlerrm ~ '^[A-Z][A-Z0-9_]{2,80}$' then sqlerrm else 'ACTION_FAILED' end));
  end;
  perform set_config('coco.activity_source_type',coalesce(old_type,''),true);perform set_config('coco.activity_source_id',coalesce(old_id,''),true);perform set_config('coco.activity_source_label',coalesce(old_label,''),true);
 end loop;
 return jsonb_build_object('rows',results);
end $$;
revoke all on function public.coco_action_queue(text,jsonb) from public,anon;
grant execute on function public.coco_action_queue(text,jsonb) to authenticated;

-- Trusted assistant ingestion can propose a bank settlement, never approve it.
create or replace function private.coco_assistant_bridge(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare account public.profiles;cfg private.coco_history_modules;tc private.coco_history_tables;rec jsonb;existing private.coco_module_proposals;
 m text:=p_data->>'module_id';a text:=p_data->>'action';s jsonb:=p_data->'source';pl jsonb;
 sid text:=btrim(s->>'id');typ text:=s->>'type';sender text:=lower(btrim(s->>'email'));
 label text:=left(coalesce(s->>'label',''),300);summary text:=btrim(p_data->>'summary');stamp timestamptz;
 eid uuid;employee uuid;mods jsonb;matches jsonb;lookups jsonb:='[]';term text:=left(btrim(p_data->>'search'),100);author text;
begin
 select p.* into account from public.profiles p join auth.users u on u.id=p.id
 where p.active and lower(u.email)=lower(btrim(p_data->>'account_email')) and p.role in ('administrador','comercial','rrhh');
 if account.id is null then raise exception 'BRIDGE_ACCOUNT_NOT_FOUND';end if;
 if typ='mail' and not exists(select 1 from private.coco_mail_bridge_accounts b where b.user_id=account.id and b.enabled and lower(b.email)=lower(p_data->>'account_email')) then raise exception 'BRIDGE_DISABLED';end if;
 if p_action='context' then
  select coalesce(jsonb_agg(jsonb_build_object('module_id',c.module_id,'label',c.label) order by c.module_id),'[]') into mods
  from private.coco_history_modules c left join public.role_module_access r on r.role=coalesce(account.access_profile,account.role)
  where account.role=any(c.roles) and not coalesce(c.module_id=any(r.disabled_modules),false)
  and not exists(select 1 from public.app_modules z where z.id=c.module_id and not z.enabled);
  select coalesce(jsonb_agg(c),'[]') into matches from (
   select 'customer' kind,id,name from public.customers where sender is not null and lower(btrim(email))=sender
   union all select 'supplier',id,name from public.suppliers where sender is not null and lower(btrim(email))=sender
   union all select 'person',id,concat_ws(' ',first_name,last_name) from public.crm_contacts where active and sender is not null and lower(btrim(email))=sender
  ) c;
  if length(term)>=2 and account.role='administrador' then
   if p_data->>'lookup'='vehicles' and mods @> '[{"module_id":"fleet"}]' then
    select coalesce(jsonb_agg(x),'[]') into lookups from (select id,plate reference,brand||' '||model label from public.fleet_vehicles where active and plate ilike '%'||term||'%' order by plate limit 25) x;
   elsif p_data->>'lookup' in ('accounts','journals','financial_accounts') and mods @> '[{"module_id":"accounting"}]'
    and not exists(select 1 from public.accounting_permissions where profile_id=account.id and not can_view) then
    if p_data->>'lookup'='accounts' then
     select coalesce(jsonb_agg(x),'[]') into lookups from (select id,code reference,name label from public.accounting_accounts where active and (code=term or name ilike '%'||term||'%') order by code limit 25) x;
    elsif p_data->>'lookup'='journals' then
     select coalesce(jsonb_agg(x),'[]') into lookups from (select code id,code reference,name label from public.accounting_journals where active and (code=term or name ilike '%'||term||'%') order by code limit 25) x;
    else
     select coalesce(jsonb_agg(x),'[]') into lookups from (select id,name label from public.financial_accounts where active and name ilike '%'||term||'%' order by name limit 25) x;
    end if;
   end if;
  end if;
  return jsonb_build_object('modules',mods,'contacts',matches,'lookups',lookups,'employee',case when account.role in ('administrador','rrhh') and mods @> '[{"module_id":"hr"}]' then
    (select jsonb_build_object('id',id,'name',full_name) from public.hr_employees where id=private.coco_source_employee(sender)) end,
   'existing',(select jsonb_agg(jsonb_build_object('id',id,'module_id',module_id,'action',action,'status',status)) from private.coco_module_proposals where account_id=account.id and source_type=typ and source_id=sid));
 end if;
 if p_action not in ('propose','record') then raise exception 'INVALID_ACTION';end if;
 select * into cfg from private.coco_history_modules where module_id=m;
 if cfg.module_id is null or not account.role=any(cfg.roles)
 or exists(select 1 from public.role_module_access r where r.role=coalesce(account.access_profile,account.role) and m=any(r.disabled_modules))
 or exists(select 1 from public.app_modules z where z.id=m and not z.enabled) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if typ not in ('mail','chat','file','import') or coalesce(length(sid),0) not between 1 and 500 then raise exception 'SOURCE_REQUIRED';end if;
 stamp:=(s->>'received_at')::timestamptz;
 if stamp is null or stamp>now()+interval '5 minutes' then raise exception 'INVALID_SOURCE_DATE';end if;
 if typ='mail' then
  if sender is null or sender !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then raise exception 'INVALID_SOURCE_EMAIL';end if;
  if not exists(select 1 from private.coco_mail_bridge_accounts b where b.user_id=account.id and b.enabled and lower(b.email)=lower(p_data->>'account_email')) then raise exception 'BRIDGE_DISABLED';end if;
 end if;
 if coalesce(length(summary),0) not between 1 and 3000 then raise exception 'INVALID_MESSAGE';end if;
 if m='hr' then
  if account.role not in ('administrador','rrhh') then raise exception 'ROLE_NOT_ALLOWED';end if;
  summary:='Solicitud de ausencia recibida; pendiente de revisión RH.';label:=case when typ='mail' then 'Correo RH' else 'Solicitud RH' end;
 end if;
 if p_action='record' then
  if m='hr' then summary:='Acción RH vinculada a su origen.';end if;
  select * into tc from private.coco_history_tables where table_name=p_data->>'record_table' and module_id=m;
  if not found then raise exception 'INVALID_RECORD_TABLE';end if;
  execute format('select to_jsonb(t) from %I.%I t where %I::text=$1',tc.table_schema,tc.table_name,tc.key_column) into rec using p_data->>'record_id';
  if rec is null then raise exception 'RECORD_NOT_FOUND';end if;
  insert into private.coco_module_events(module_id,record_table,record_id,type,action,subject,body,actor_id,actor_name,source_type,source_id,source_label,source_email,links)
  values(m,p_data->>'record_table',p_data->>'record_id','action','source_linked','Origen de la acción',summary,account.id,coalesce(nullif(account.full_name,''),'USER_UNAVAILABLE'),typ,sid,label,sender,
   jsonb_build_array(jsonb_build_object('module',m,'action','module','id',p_data->>'record_id')))
  on conflict do nothing returning id into eid;
  return jsonb_build_object('recorded',true,'id',eid);
 end if;
 if a not in ('contact_draft','absence_request','document_create','fuel_log','accounting_entry','record_note','bank_settlement')
 or a='contact_draft' and m<>'contacts' or a='absence_request' and m<>'hr' or a='document_create' and m<>'documents'
 or a='bank_settlement' and (m<>'accounting' or account.role<>'administrador') or a='fuel_log' and m<>'fleet' or a='accounting_entry' and m<>'accounting' then raise exception 'INVALID_PROPOSAL_ACTION';end if;
 pl:=private.coco_proposal_payload(a,p_data->'payload');
 perform pg_advisory_xact_lock(hashtextextended(account.id||':'||typ||':'||sid||':'||m||':'||a,0));
 select * into existing from private.coco_module_proposals where account_id=account.id and source_type=typ and source_id=sid and module_id=m and action=a;
 if found then return jsonb_build_object('id',existing.id,'status',existing.status,'duplicate',true);end if;
 if a='contact_draft' and typ='mail' and lower(btrim(pl->>'email')) is distinct from sender then raise exception 'SOURCE_CONTACT_MISMATCH';end if;
 if a='contact_draft' and exists(select 1 from public.customers where lower(btrim(email))=lower(btrim(pl->>'email')) union all
   select 1 from public.suppliers where lower(btrim(email))=lower(btrim(pl->>'email')) union all
   select 1 from public.crm_contacts where active and lower(btrim(email))=lower(btrim(pl->>'email')) union all
   select 1 from public.crm_leads where active and lower(btrim(email))=lower(btrim(pl->>'email'))) then return jsonb_build_object('skipped','CONTACT_EXISTS');end if;
 if a='absence_request' and typ='mail' then
  employee:=private.coco_source_employee(sender);
  if employee is null or (pl->>'employee_id')::uuid is distinct from employee then raise exception 'SOURCE_EMPLOYEE_MISMATCH';end if;
 end if;
 insert into private.coco_module_proposals(account_id,module_id,action,source_type,source_id,source_label,source_email,received_at,summary,payload)
 values(account.id,m,a,typ,sid,label,sender,stamp,summary,pl) returning * into existing;
 insert into private.coco_module_events(module_id,type,action,subject,body,actor_name,proposal_id,source_type,source_id,source_label,source_email)
 values(m,'proposal','proposal','mail_analysis',summary,'Agent Coco',existing.id,typ,sid,label,sender);
 return jsonb_build_object('id',existing.id,'status','pending','module_id',m);
end $$;
revoke all on function private.coco_assistant_bridge(text,jsonb) from public,anon,authenticated;
grant execute on function private.coco_assistant_bridge(text,jsonb) to service_role;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261020195939','agent_approval_queue','7e55293892c85c302ca3028f5ba11bfbc233bdbb3585248b1b947c3731db9c41','7e55293892c85c302ca3028f5ba11bfbc233bdbb3585248b1b947c3731db9c41','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261020200251_business_contract_current_tax.sql; SHA256 2ce7ef96ae37d0109db62402059bfb9ea77d32af1f282d1ccc5d440c5ddd6d4a
-- Contract prices may be fixed; product tax belongs to the newly prepared order.
-- Preserve the checked sales gateway and historical orders.
do $patch$ declare body text;needle text:='jsonb_build_object(''price_mode'',case when s.price_mode=';begin
 select pg_get_functiondef('private.contract_generate(uuid,date,boolean)'::regprocedure) into body;
 if position(needle in body)=0 then raise exception 'CONTRACT_PATCH_TARGET_CHANGED';end if;
 body:=replace(body,needle,'jsonb_build_object(''tax_rate'',(select p.tax_rate from public.products p where p.id=(x->>''product_id'')::uuid),''price_mode'',case when s.price_mode=');
 execute body;
end $patch$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261020200251','business_contract_current_tax','2ce7ef96ae37d0109db62402059bfb9ea77d32af1f282d1ccc5d440c5ddd6d4a','2ce7ef96ae37d0109db62402059bfb9ea77d32af1f282d1ccc5d440c5ddd6d4a','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261020201957_history_pending_approvals.sql; SHA256 a99704588350a47e37c3685ae977a29cd5ec8e603fd577b956431a2d24e6deab
-- Pending proposals are filtered before paging. Existing approval checks and
-- event history stay authoritative; changing tabs never executes a proposal.
create function private.coco_pending_mail_proposal(proposal uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p private.coco_mail_proposals;e private.coco_order_entries;c jsonb;
begin
 if auth.uid() is null then return null;end if;
 select * into p from private.coco_mail_proposals where id=proposal and status='pending';
 if not found then return null;end if;
 select * into e from private.coco_order_entries where id=p.entry_id;
 if not found then return null;end if;
 begin c:=private.coco_dossier_context(e.kind,e.order_id);
 exception when raise_exception then
  if sqlerrm in ('ROLE_NOT_ALLOWED','TMS_ACCESS_DENIED','ORDER_NOT_FOUND','AUTH_OR_MFA_REQUIRED') then return null;end if;raise;
 end;
 if not coalesce((c->>'can_review')::boolean,false) then return null;end if;
 return jsonb_build_object('id',p.id,'kind',e.kind,'target_kind',e.kind,'target_id',e.order_id,
  'status',p.status,'action',p.action,'summary',p.summary,'payload',p.payload,'result',p.result,
  'source_email',p.source_email,'source_subject',p.source_subject,'message_id',p.message_id,
  'received_at',p.received_at,'can_review',true);
end $$;
revoke all on function private.coco_pending_mail_proposal(uuid) from public,anon,authenticated;
grant execute on function private.coco_pending_mail_proposal(uuid) to authenticated;

do $$declare src text;needle text;begin
 src:=pg_get_functiondef('private.coco_dossier(text,jsonb)'::regprocedure);
 needle:=$n$and (e.type<>'mail' or (ctx->>'commercial')::boolean)$n$;
 if strpos(src,needle)=0 then raise exception 'PENDING_DOSSIER_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$n$and (not coalesce((p_data->>'pending_only')::boolean,false) or exists(
   select 1 from private.coco_mail_proposals pending where pending.id=nullif(e.detail->>'proposal_id','')::uuid and pending.status='pending'))
   and (e.type<>'mail' or (ctx->>'commercial')::boolean)$n$);
 src:=replace(src,$n$'history',coalesce(hist,'[]')$n$,$n$'history',case when coalesce((p_data->>'pending_only')::boolean,false) then '[]'::jsonb else coalesce(hist,'[]') end$n$);
 execute src;

 src:=pg_get_functiondef('private.coco_agent_dossier_events()'::regprocedure);
 needle:=$n$'created_at',e.created_at,$n$;
 if strpos(src,needle)=0 then raise exception 'PENDING_AGENT_DOSSIER_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$n$'created_at',e.created_at,'proposal_id',e.detail->>'proposal_id',$n$);
 execute src;

 src:=pg_get_functiondef('public.coco_module_history_events(text,jsonb)'::regprocedure);
 needle:=$n$e.type in ('action','note')$n$;
 src:=replace(src,needle,$n$e.type in ('action','note','proposal')$n$);
 needle:=E'from combined\n';
 if strpos(src,needle)=0 then raise exception 'PENDING_MODULE_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$n$from combined
  where not coalesce((p_data->>'pending_only')::boolean,false) or proposal_id is not null and (
   exists(select 1 from private.coco_module_proposals p where p.id=proposal_id and p.status='pending' and private.coco_module_reviewer(p.module_id))
   or private.coco_pending_mail_proposal(proposal_id) is not null)
$n$);
 execute src;

 src:=pg_get_functiondef('public.coco_module_history(text,jsonb)'::regprocedure);
 src:=replace(src,$n$'can_review',private.coco_module_reviewer(m))),'[]') from private.coco_module_proposals p where p.module_id=m and$n$,
 $n$'can_review',private.coco_module_reviewer(p.module_id))),'[]') from private.coco_module_proposals p where (p.module_id=m or m='assistant-ia') and$n$);
 needle:=$n$if p_action in ('context','list') then$n$;
 if strpos(src,needle)=0 then raise exception 'PENDING_PROPOSALS_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$n$if p_action='list' and m='assistant-ia' and coalesce((p_data->>'pending_only')::boolean,false) then
  r:=jsonb_set(r,'{proposals}',coalesce(r->'proposals','[]')||coalesce((select jsonb_agg(p) from (
   select distinct private.coco_pending_mail_proposal((e->>'proposal_id')::uuid) p
   from jsonb_array_elements(r->'history') e where e->>'proposal_id' is not null
  ) pending where p is not null),'[]'::jsonb));
 end if;
 if p_action in ('context','list') then$n$);
 execute src;

 src:=pg_get_functiondef('public.coco_dossier(text,jsonb)'::regprocedure);
 needle:=$n$'annotations_only',true,$n$;
 if strpos(src,needle)=0 then raise exception 'PENDING_DOSSIER_ANNOTATIONS_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$n$'annotations_only',true,'pending_only',coalesce((p_data->>'pending_only')::boolean,false),$n$);
 execute src;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261020201957','history_pending_approvals','a99704588350a47e37c3685ae977a29cd5ec8e603fd577b956431a2d24e6deab','a99704588350a47e37c3685ae977a29cd5ec8e603fd577b956431a2d24e6deab','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261020210157_history_human_decisions.sql; SHA256 07585a0c2bd27da3fff7ea11226cee9b83c94a882aae2c9439c12973ea0fc037
-- Preserve the human decision separately from the assistant proposal and execution.
create or replace function private.coco_history_agent_author() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 -- Decisions belong to the authenticated reviewer, even during AI execution.
 if new.action in ('approve_proposal','reject_proposal','proposal_approved','proposal_rejected')
    or new.subject in ('proposal_approved','proposal_rejected') then
  return new;
 end if;
 if current_setting('coco.activity_source_type',true)='chat' then
  new.source_type:='chat';
  new.source_id:=coalesce(nullif(current_setting('coco.activity_source_id',true),''),new.source_id);
  new.source_label:=coalesce(nullif(current_setting('coco.activity_source_label',true),''),new.source_label,'Agent Coco');
  new.actor_name:='Agent Coco';
 elsif new.type='action' and new.source_type='chat'
    and new.action not in ('proposal_approved','proposal_rejected') then
  new.actor_name:='Agent Coco';
 end if;
 return new;
end $$;

create or replace function private.coco_order_agent_author() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if new.subject in ('proposal_approved','proposal_rejected') then
  return new;
 end if;
 if current_setting('coco.activity_source_type',true)='chat' then
  new.actor_name:='Agent Coco';
  new.detail:=new.detail||jsonb_build_object('source_type','chat',
   'source_id',nullif(current_setting('coco.activity_source_id',true),''),
   'source_label',coalesce(nullif(current_setting('coco.activity_source_label',true),''),'Agent Coco'));
 end if;
 return new;
end $$;

-- Restore only decision rows whose authenticated author was retained. Do not
-- rewrite proposal authors, business execution events, dates or source links.
update private.coco_module_events e set actor_name=coalesce(nullif(p.full_name,''),'USER_UNAVAILABLE')
from public.profiles p where p.id=e.actor_id and e.actor_name in ('Agent Coco','ChatGPT')
 and (e.action in ('approve_proposal','reject_proposal','proposal_approved','proposal_rejected')
      or e.subject in ('proposal_approved','proposal_rejected'));
update private.coco_order_entries e set actor_name=coalesce(nullif(p.full_name,''),'USER_UNAVAILABLE')
from public.profiles p where p.id=e.actor_id and e.actor_name in ('Agent Coco','ChatGPT')
 and e.subject in ('proposal_approved','proposal_rejected');

-- Central history must preserve the reviewer on projected dossier decisions.
do $$declare src text;needle text;begin
 src:=pg_get_functiondef('private.coco_agent_dossier_events()'::regprocedure);
 needle:=$s$'actor_name','Agent Coco'$s$;
 if strpos(src,needle)=0 then raise exception 'DECISION_AUTHOR_PROJECTION_CHANGED';end if;
 src:=replace(src,needle,$s$'actor_name',case when e.subject in ('proposal_approved','proposal_rejected') then e.actor_name else 'Agent Coco' end$s$);
 src:=replace(src,$s$or detail->>'source_type'='chat')$s$,$s$or detail->>'source_type'='chat' or subject in ('proposal_approved','proposal_rejected'))$s$);
 src:=replace(src,$s$or x.detail->>'source_type'='chat')$s$,$s$or x.detail->>'source_type'='chat' or x.subject in ('proposal_approved','proposal_rejected'))$s$);
 execute src;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261020210157','history_human_decisions','07585a0c2bd27da3fff7ea11226cee9b83c94a882aae2c9439c12973ea0fc037','07585a0c2bd27da3fff7ea11226cee9b83c94a882aae2c9439c12973ea0fc037','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261021190510_history_actor_portraits.sql; SHA256 2ac6d498ac2a749f5a67df8c2008ea62ceea573b8e19f32989c582a82b7069fa
-- Resolve portraits only for authors on the already-authorised history page.
-- Keep the invoker and the existing HR row policies: no employee directory or
-- private HR fields are added to the history response.
do $$
declare src text; needle text;
begin
 src:=pg_get_functiondef('public.coco_module_history(text,jsonb)'::regprocedure);
 needle:=E'\n return r;\nend';
 if strpos(src,needle)=0 then raise exception 'HISTORY_PORTRAITS_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$patch$
 if p_action='list' then
  r:=jsonb_set(r,'{portraits}',coalesce(r->'portraits','{}'::jsonb)||coalesce((
   select jsonb_object_agg(h.profile_id::text,h.photo_data)
   from public.hr_employees h
   where h.active and h.photo_data is not null and length(h.photo_data)<=120000
    and h.photo_data ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/]+={0,2}$'
    and h.profile_id::text in (
     select e->>'actor_id' from jsonb_array_elements(coalesce(r->'history','[]'::jsonb)) e
     union select e->>'actor_id' from jsonb_array_elements(coalesce(r->'entries','[]'::jsonb)) e
    )
  ),'{}'::jsonb));
 end if;
 return r;
end$patch$);
 execute src;

 -- Dossier annotations are merged from module history; keep their portraits too.
 src:=pg_get_functiondef('public.coco_dossier(text,jsonb)'::regprocedure);
 needle:=E'\n return r;\nend';
 if strpos(src,needle)=0 then raise exception 'DOSSIER_PORTRAITS_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$patch$
 r:=jsonb_set(r,'{portraits}',coalesce(r->'portraits','{}'::jsonb)||coalesce(extra->'portraits','{}'::jsonb));
 return r;
end$patch$);
 execute src;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261021190510','history_actor_portraits','2ac6d498ac2a749f5a67df8c2008ea62ceea573b8e19f32989c582a82b7069fa','2ac6d498ac2a749f5a67df8c2008ea62ceea573b8e19f32989c582a82b7069fa','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
