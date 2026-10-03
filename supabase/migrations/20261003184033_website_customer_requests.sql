-- Public inquiries enter the existing sales request workflow atomically.
alter table public.customer_requests
 add column source_website_id uuid unique references private.website_public_inquiries(id),
 add column website_reference text,
 add column requester_phone text,
 add column requester_company text;

create function private.request_contact_key(v text) returns text language sql immutable set search_path='' as $$
 select lower(regexp_replace(btrim(coalesce(v,'')),'[[:space:]]+',' ','g'))
$$;
revoke all on function private.request_contact_key(text) from public,anon;
grant execute on function private.request_contact_key(text) to authenticated;

create function private.import_website_request(p_id uuid) returns void language plpgsql security invoker set search_path='' as $$
declare w private.website_public_inquiries;r uuid;matches uuid[];l jsonb;
begin
 select * into w from private.website_public_inquiries where id=p_id;
 if not found then return;end if;
 select array_agg(c.id) into matches from public.customers c where c.active and (
  (private.request_contact_key(w.email)<>'' and private.request_contact_key(c.email)=private.request_contact_key(w.email))
  or (private.request_contact_key(c.name)<>'' and private.request_contact_key(c.name) in (private.request_contact_key(w.company),private.request_contact_key(w.contact_name))));
 insert into public.customer_requests(source_website_id,website_reference,customer_id,created_by,status,requester_name,requester_email,requester_phone,requester_company,notes,total,created_at)
 values(w.id,'WEB-'||lpad(w.number::text,8,'0'),case when cardinality(matches)=1 then matches[1] else null end,null,
 case when w.status='archived' then 'cancelled' else 'pending' end,w.contact_name,w.email,w.phone,w.company,w.notes,
 (select coalesce(sum((x->>'subtotal')::numeric),0) from jsonb_array_elements(w.lines)x),w.created_at)
 on conflict(source_website_id) do nothing returning id into r;
 if r is null then return;end if;
 for l in select value from jsonb_array_elements(w.lines) loop
  insert into public.customer_request_lines(request_id,product_id,quantity,unit_price,tax_rate,line_total)
  values(r,(l->>'product_id')::uuid,(l->>'quantity')::numeric,(l->>'unit_price')::numeric,(l->>'tax_rate')::numeric,(l->>'subtotal')::numeric);
 end loop;
end $$;
revoke all on function private.import_website_request(uuid) from public,anon,authenticated;
create function private.website_request_insert() returns trigger language plpgsql security invoker set search_path='' as $$
begin perform private.import_website_request(new.id);return new;end $$;
revoke all on function private.website_request_insert() from public,anon,authenticated;
create trigger website_request_insert after insert on private.website_public_inquiries for each row execute function private.website_request_insert();
do $$declare w record;begin for w in select id from private.website_public_inquiries order by created_at,id loop perform private.import_website_request(w.id);end loop;end $$;

-- Staff-only contact resolution; existing RLS and customer write guards still apply.
create function public.gama_request_contact(p_id uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security invoker set search_path='' as $$
declare r public.customer_requests;c public.customers;items jsonb;ident text;terms integer;nm text;em text;
begin
 if auth.uid() is null or not private.erp_module_allowed('quotes',array['administrador','comercial']) or not private.erp_module_allowed('customer-requests',array['administrador','comercial']) or not private.erp_module_allowed('contacts',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'REQUEST_CONTACT_ACCESS_DENIED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>12000 then raise exception 'REQUEST_CONTACT_INVALID';end if;
 select * into r from public.customer_requests where id=p_id for update;
 if not found or r.source_website_id is null then raise exception 'REQUEST_NOT_FOUND';end if;
 if p_action not in ('candidates','link','create') then raise exception 'REQUEST_CONTACT_INVALID';end if;
 if p_action<>'candidates' and not private.erp_action_allowed('customer-requests','edit') then raise exception 'REQUEST_CONTACT_ACCESS_DENIED';end if;
 if p_action<>'candidates' and (r.invoice_id is not null or r.status in ('cancelled','rejected')) then raise exception 'REQUEST_CONTACT_LOCKED';end if;
 if r.customer_id is not null then return jsonb_build_object('status','linked','customer_id',r.customer_id);end if;
 nm:=coalesce(nullif(btrim(r.requester_company),''),r.requester_name);em:=lower(btrim(r.requester_email));
 if p_action='create' then
  if not private.erp_action_allowed('contacts','create') then raise exception 'REQUEST_CONTACT_ACCESS_DENIED';end if;
  perform pg_advisory_xact_lock(hashtextextended('web-contact:'||private.request_contact_key(nm),0));
  perform pg_advisory_xact_lock(hashtextextended('web-contact-email:'||coalesce(em,''),0));
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'email',x.email,'identification',x.identification) order by x.name),'[]') into items
 from public.customers x where x.active and (
  (em<>'' and private.request_contact_key(x.email)=private.request_contact_key(em))
  or (private.request_contact_key(x.name)<>'' and private.request_contact_key(x.name) in (private.request_contact_key(r.requester_company),private.request_contact_key(r.requester_name)))
  or (p_action='create' and nullif(btrim(p_data->>'identification'),'') is not null and x.identification=btrim(p_data->>'identification')));
 if p_action='candidates' or (p_action='create' and jsonb_array_length(items)>0) then return jsonb_build_object('status','candidates','items',items);end if;
 if p_action='link' then
  select * into c from public.customers where id=(p_data->>'customer_id')::uuid and active;
  if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;
 else
  ident:=nullif(btrim(p_data->>'identification'),'');terms:=(p_data->>'payment_terms_days')::integer;
  if ident is null or length(ident)>100 or terms is null or terms not between 0 and 3650 then raise exception 'REQUEST_CONTACT_INVALID';end if;
  insert into public.customers(name,identification,email,phone,category,payment_terms_days,active)
  values(nm,ident,em,nullif(r.requester_phone,''),'A',terms,true) returning * into c;
 end if;
 update public.customer_requests set customer_id=c.id,updated_at=now() where id=r.id;
 return jsonb_build_object('status','linked','customer_id',c.id);
end $$;
revoke all on function public.gama_request_contact(uuid,text,jsonb) from public,anon;
grant execute on function public.gama_request_contact(uuid,text,jsonb) to authenticated;
notify pgrst,'reload schema';
