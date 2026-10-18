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

