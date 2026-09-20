alter table public.service_tickets add column delivery_id uuid references public.tms_deliveries(id),add column return_id uuid references public.return_orders(id),add column replacement_order_id uuid references public.sales_orders(id),add column root_cause text not null default '',add column response_due_at timestamptz,add column first_response_at timestamptz,add column resolution_due_at timestamptz,add column portal_request_key uuid unique;
alter table public.service_messages add column visibility text not null default 'internal' check(visibility in ('internal','public'));
create table public.service_sla_rules(priority text primary key check(priority in ('normal','high','urgent')),response_hours integer not null check(response_hours between 1 and 8760),resolution_hours integer not null check(resolution_hours between 1 and 8760));
insert into public.service_sla_rules values('normal',24,72),('high',8,48),('urgent',2,24);
alter table public.service_sla_rules enable row level security;revoke all on public.service_sla_rules from public,anon,authenticated;grant select,update on public.service_sla_rules to authenticated;
create policy sla_read on public.service_sla_rules for select to authenticated using(private.service_access('sav'));
create policy sla_write on public.service_sla_rules for update to authenticated using(private.erp_module_allowed('settings',array['administrador']));
create trigger erp_audit_capture after insert or update or delete on public.service_sla_rules for each row execute function private.erp_audit_capture();
create function private.erp_service_controls() returns trigger language plpgsql security definer set search_path='' as $$declare sla public.service_sla_rules;begin
 if tg_op='INSERT' then
  select * into sla from public.service_sla_rules where priority=new.priority;
  new.response_due_at:=now()+make_interval(hours=>sla.response_hours);new.resolution_due_at:=now()+make_interval(hours=>sla.resolution_hours);new.due_date:=coalesce(new.due_date,new.resolution_due_at::date);
 else new.response_due_at:=old.response_due_at;new.resolution_due_at:=old.resolution_due_at;end if;
 if new.return_id is not null and not exists(select 1 from public.return_orders where id=new.return_id and customer_id=new.customer_id) then raise exception 'SERVICE_RETURN_CUSTOMER';end if;
 if new.replacement_order_id is not null and not exists(select 1 from public.sales_orders where id=new.replacement_order_id and customer_id=new.customer_id) then raise exception 'SERVICE_REPLACEMENT_CUSTOMER';end if;
 if new.delivery_id is not null and not exists(select 1 from public.tms_deliveries where id=new.delivery_id and customer_id=new.customer_id) then raise exception 'SERVICE_DELIVERY_CUSTOMER';end if;
 return new;
end $$;
revoke all on function private.erp_service_controls() from public,anon,authenticated;
create trigger erp_service_controls before insert or update on public.service_tickets for each row execute function private.erp_service_controls();
create function private.erp_service_response() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.visibility='public' and private.current_user_role() in ('administrador','comercial') then update public.service_tickets set first_response_at=coalesce(first_response_at,now()) where id=new.ticket_id;end if;return null;
end $$;
revoke all on function private.erp_service_response() from public,anon,authenticated;
create trigger erp_service_response after insert on public.service_messages for each row execute function private.erp_service_response();
create function private.gama_client_service(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.customers;d public.tms_deliveries;ticket public.service_tickets;oid uuid;key uuid:=nullif(p_data->>'request_key','')::uuid;receipt private.command_receipts;result jsonb;begin
 if auth.uid() is null or not private.erp_module_allowed('client-deliveries',array['cliente']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select x.* into c from public.customers x where x.active and private.gama_owns_customer(x.id) order by x.created_at,x.id limit 1;if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid and customer_id=c.id;if not found then raise exception 'DELIVERY_NOT_FOUND';end if;
 select order_id into oid from public.sales_deliveries where tms_delivery_id=d.id;
 if p_action in ('create','reply') then
  if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('service:'||key::text,0));
  select * into receipt from private.command_receipts where domain='service' and request_key=key;
  if found then if receipt.actor_id<>auth.uid() or receipt.payload<>p_data-'request_key'||jsonb_build_object('action',p_action) then raise exception 'REQUEST_KEY_REUSED';end if;return receipt.result;end if;
  if p_action='create' then
   insert into public.service_tickets(subject,description,customer_id,sales_order_id,delivery_id,category,portal_request_key) values(p_data->>'subject',p_data->>'body',c.id,oid,d.id,'delivery',key) returning * into ticket;
  else
   select * into ticket from public.service_tickets where id=(p_data->>'ticket_id')::uuid and customer_id=c.id and delivery_id=d.id and not archived for update;
   if not found or ticket.status='closed' then raise exception 'TICKET_CLOSED';end if;
   insert into public.service_messages(ticket_id,body,visibility) values(ticket.id,p_data->>'body','public');
  end if;
  result:=jsonb_build_object('id',ticket.id,'number',ticket.number);
  insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('service',key,auth.uid(),p_data-'request_key'||jsonb_build_object('action',p_action),result);return result;
 elsif p_action<>'context' then raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('tickets',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'number',s.number,'subject',s.subject,'description',s.description,'status',s.status,'created_at',s.created_at,'messages',(select coalesce(jsonb_agg(jsonb_build_object('body',m.body,'created_at',m.created_at,'author',case when m.created_by=auth.uid() then 'customer' else 'company' end) order by m.created_at),'[]') from public.service_messages m where m.ticket_id=s.id and m.visibility='public')) order by s.created_at desc),'[]') from public.service_tickets s where s.delivery_id=d.id and s.customer_id=c.id and not s.archived),
 'lines',(select coalesce(jsonb_agg(jsonb_build_object('name',l.product_name,'ordered',l.quantity,'delivered',coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl join public.sales_deliveries sd on sd.id=dl.delivery_id join public.tms_deliveries td on td.id=sd.tms_delivery_id where dl.order_line_id=l.id and td.status='Entregada'),0),'promised_date',l.promised_date)),'[]') from public.sales_order_lines l where l.order_id=oid),
 'events',jsonb_build_array(jsonb_build_object('label','Entrega prevista','date',d.delivery_date),jsonb_build_object('label','Estado','status',d.status,'date',d.delivered_at)));
end $$;
revoke all on function private.gama_client_service(text,jsonb) from public,anon;grant execute on function private.gama_client_service(text,jsonb) to authenticated;
create function public.gama_client_service(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_client_service(p_action,p_data)$$;
revoke all on function public.gama_client_service(text,jsonb) from public,anon;grant execute on function public.gama_client_service(text,jsonb) to authenticated;

alter table public.business_documents add column owner_id uuid references public.profiles(id),add column next_action text not null default '';
grant insert(owner_id,next_action),update(owner_id,next_action) on public.business_documents to authenticated;
-- Extend the existing atomic save rather than adding a second, unversioned write.
do $$declare src text:=pg_get_functiondef('public.gama_save_business_document(jsonb,integer,jsonb)'::regprocedure);begin
 src:=replace(src,'ticket_id,expires_on)','ticket_id,expires_on,owner_id,next_action)');
 src:=replace(src,$a$nullif(p_document->>'expires_on','')::date) returning$a$, $a$nullif(p_document->>'expires_on','')::date,nullif(p_document->>'owner_id','')::uuid,coalesce(p_document->>'next_action','')) returning$a$);
 src:=replace(src,$a$expires_on=nullif(p_document->>'expires_on','')::date$a$, $a$expires_on=nullif(p_document->>'expires_on','')::date,owner_id=nullif(p_document->>'owner_id','')::uuid,next_action=coalesce(p_document->>'next_action','')$a$);
 execute src;
end $$;
create table public.business_document_approvals(id uuid primary key default gen_random_uuid(),document_id uuid not null references public.business_documents(id),fingerprint text not null,status text not null default 'pending' check(status in ('pending','approved','rejected')),requested_by uuid not null default auth.uid() references auth.users(id),requested_at timestamptz not null default now(),reviewed_by uuid references auth.users(id),reviewed_at timestamptz,reason text,unique(document_id,fingerprint));
alter table public.business_document_approvals enable row level security;revoke all on public.business_document_approvals from public,anon,authenticated;grant select on public.business_document_approvals to authenticated;
create policy document_approval_read on public.business_document_approvals for select to authenticated using(exists(select 1 from public.business_documents d where d.id=document_id));
create trigger erp_audit_capture after insert or update or delete on public.business_document_approvals for each row execute function private.erp_audit_capture();
create function private.gama_document_approval(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.business_documents;a public.business_document_approvals;fp text;begin
 select * into d from public.business_documents where id=(p_data->>'id')::uuid for update;
 if auth.uid() is null or not found or not private.document_read(d) then raise exception 'DOCUMENT_UNAVAILABLE';end if;
 fp:=md5((to_jsonb(d)-array['updated_at','version','owner_id','next_action'])::text||coalesce((select jsonb_agg(to_jsonb(f) order by f.revision)::text from public.business_document_files f where f.document_id=d.id),'[]'));
 if p_action='request' then
  if not private.document_write(d) then raise exception 'ROLE_NOT_ALLOWED';end if;
  insert into public.business_document_approvals(document_id,fingerprint) values(d.id,fp) on conflict(document_id,fingerprint) do nothing;
 elsif p_action='decide' then
  if coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'APPROVAL_ADMIN_REQUIRED';end if;
  if p_data->>'status' not in ('approved','rejected') or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'DECISION_REQUIRED';end if;
  update public.business_document_approvals set status=p_data->>'status',reviewed_by=auth.uid(),reviewed_at=now(),reason=p_data->>'reason' where document_id=d.id and fingerprint=fp and status='pending';if not found then raise exception 'DOCUMENT_CHANGED_OR_NOT_PENDING';end if;
 elsif p_action<>'detail' then raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('current',(select to_jsonb(x) from public.business_document_approvals x where x.document_id=d.id and x.fingerprint=fp),'history',(select coalesce(jsonb_agg(to_jsonb(x) order by requested_at desc),'[]') from public.business_document_approvals x where x.document_id=d.id));
end $$;
revoke all on function private.gama_document_approval(text,jsonb) from public,anon;grant execute on function private.gama_document_approval(text,jsonb) to authenticated;
create function public.gama_document_approval(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_document_approval(p_action,p_data)$$;
revoke all on function public.gama_document_approval(text,jsonb) from public,anon;grant execute on function public.gama_document_approval(text,jsonb) to authenticated;
