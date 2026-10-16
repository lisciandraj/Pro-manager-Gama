-- Additive Contacts hub. Native IDs, transaction snapshots and portal memberships remain unchanged.
create table private.coco_contact_entities (
 id uuid primary key default gen_random_uuid(),
 nature text check (nature in ('person','company')),
 language text check (language in ('fr','es','en')),
 website text check (website is null or (length(website)<=500 and website ~ '^https?://[^[:space:]]+$')),
 industry text check (length(industry)<=120),
 tags text[] not null default '{}' check (cardinality(tags)<=30 and octet_length(tags::text)<=3000),
 parent_id uuid references private.coco_contact_entities(id),
 relation text check (relation in ('branch','subsidiary','employee','other')),
 version integer not null default 1,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 updated_by uuid references public.profiles(id),
 check (parent_id is distinct from id), check ((parent_id is null)=(relation is null))
);
alter table private.coco_contact_entities enable row level security;
alter table public.customers add column contact_entity_id uuid references private.coco_contact_entities(id);
alter table public.suppliers add column contact_entity_id uuid references private.coco_contact_entities(id);
alter table public.crm_leads add column contact_entity_id uuid references private.coco_contact_entities(id);
alter table public.crm_contacts add column contact_entity_id uuid references private.coco_contact_entities(id);

-- Trigger-only capability. No user may call this function as an RPC.
create function private.coco_contact_register() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.contact_entity_id is null then
  if tg_op='UPDATE' and old.contact_entity_id is not null then raise exception 'CONTACT_IDENTITY_REQUIRED';end if;
  insert into private.coco_contact_entities(nature) values(case when tg_table_name='crm_contacts' then 'person' end) returning id into new.contact_entity_id;
 elsif tg_op='INSERT' or new.contact_entity_id is distinct from old.contact_entity_id then
  if auth.uid() is not null and coalesce(private.current_user_role(),'')<>'administrador' then
   if tg_table_name='customers' and tg_op='INSERT' and private.erp_module_allowed('crm',array['comercial']) and exists(select 1 from public.crm_leads where contact_entity_id=new.contact_entity_id and converted_customer_id is null and active) then null;
   elsif tg_table_name='crm_leads' and exists(select 1 from public.customers where id=(to_jsonb(new)->>'converted_customer_id')::uuid and contact_entity_id=new.contact_entity_id) and private.erp_module_allowed('contacts',array['comercial']) then null;
   else raise exception 'CONTACT_LINK_ADMIN_REQUIRED';end if;
  end if;
 end if;
 return new;
end $$;
revoke all on function private.coco_contact_register() from public,anon,authenticated;
do $$declare t text;begin
 foreach t in array array['customers','suppliers','crm_leads','crm_contacts'] loop
  execute format('create trigger coco_contact_register before insert or update of contact_entity_id on public.%I for each row execute function private.coco_contact_register()',t);
  execute format('update public.%I set contact_entity_id=null where contact_entity_id is null',t);
  execute format('alter table public.%I alter column contact_entity_id set not null',t);
  execute format('create index %I on public.%I(contact_entity_id)',t||'_contact_entity_idx',t);
 end loop;
end $$;
-- Only proven conversion links are reconciled, never a matching name/email/tax number.
update public.crm_leads l set contact_entity_id=c.contact_entity_id from public.customers c where l.converted_customer_id=c.id;
create unique index customers_contact_identity_unique on public.customers(contact_entity_id);
create unique index suppliers_contact_identity_unique on public.suppliers(contact_entity_id);
create unique index crm_contacts_contact_identity_unique on public.crm_contacts(contact_entity_id);

create function private.coco_contact_access(p_entity uuid,p_write boolean default false) returns boolean
language sql stable security invoker set search_path='' as $$
 select auth.uid() is not null and private.erp_internal_account() and private.erp_mfa_ok()
 and nullif(auth.jwt()->>'client_id','') is null
 and (
  (private.erp_module_allowed('contacts',array['administrador','comercial'])
   and (not p_write or private.erp_action_allowed('contacts','edit'))
   and (exists(select 1 from public.customers where contact_entity_id=p_entity) or exists(select 1 from public.suppliers where contact_entity_id=p_entity)))
  or (private.erp_module_allowed('crm',array['administrador','comercial'])
   and (not p_write or private.erp_action_allowed('crm','edit'))
   and (exists(select 1 from public.crm_leads where contact_entity_id=p_entity) or exists(select 1 from public.crm_contacts where contact_entity_id=p_entity)))
 )
$$;
revoke all on function private.coco_contact_access(uuid,boolean) from public,anon;
grant execute on function private.coco_contact_access(uuid,boolean) to authenticated;
revoke all on private.coco_contact_entities from public,anon,authenticated;
grant select on private.coco_contact_entities to authenticated;
grant update(nature,language,website,industry,tags,parent_id,relation) on private.coco_contact_entities to authenticated;
create policy coco_contact_read on private.coco_contact_entities for select to authenticated using(private.coco_contact_access(id));
create policy coco_contact_edit on private.coco_contact_entities for update to authenticated using(private.coco_contact_access(id,true)) with check(private.coco_contact_access(id,true));

create function private.coco_contact_profile_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare ancestor uuid;visited uuid[]:=array[new.id];begin
 if auth.uid() is null or not private.coco_contact_access(new.id,true) then raise exception 'ACCESS_DENIED';end if;
 if new.parent_id is not null then
  perform pg_advisory_xact_lock(hashtextextended('coco-contact-parent-graph',0));
  if not private.coco_contact_access(new.parent_id) then raise exception 'CONTACT_PARENT_ACCESS_DENIED';end if;
  ancestor:=new.parent_id;
  while ancestor is not null loop
   if ancestor=any(visited) then raise exception 'CONTACT_PARENT_CYCLE';end if;
   visited:=visited||ancestor;
   select parent_id into ancestor from private.coco_contact_entities where id=ancestor;
  end loop;
 end if;
 new.version:=old.version+1;new.updated_at:=now();new.updated_by:=auth.uid();return new;
end $$;
revoke all on function private.coco_contact_profile_guard() from public,anon,authenticated;
create trigger coco_contact_profile_guard before update on private.coco_contact_entities for each row execute function private.coco_contact_profile_guard();
create trigger coco_contact_profile_audit after update on private.coco_contact_entities for each row execute function private.erp_audit_capture();

create function public.coco_contact_hub(p_kind text,p_id uuid,p_action text default 'get',p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare eid uuid;tbl text;profile private.coco_contact_entities;peers jsonb;v integer;target uuid;target_tags text[];begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>12000 then raise exception 'INVALID_DATA';end if;
 tbl:=case p_kind when 'clients' then 'customers' when 'suppliers' then 'suppliers' when 'leads' then 'crm_leads' when 'people' then 'crm_contacts' when 'prospects' then 'crm_contacts' end;
 if tbl is null then raise exception 'INVALID_KIND';end if;
 if not private.erp_module_allowed(case when tbl in ('customers','suppliers') then 'contacts' else 'crm' end,array['administrador','comercial']) then raise exception 'ACCESS_DENIED';end if;
 execute format('select contact_entity_id from public.%I where id=$1',tbl) into eid using p_id;
 if eid is null or not private.coco_contact_access(eid) then raise exception 'ACCESS_DENIED';end if;
 select * into profile from private.coco_contact_entities where id=eid;
 if p_action='save' then
  if not private.coco_contact_access(eid,true) then raise exception 'ACCESS_DENIED';end if;
  v:=(p_data->>'version')::integer;
  update private.coco_contact_entities set
   nature=nullif(p_data->>'nature',''), language=nullif(p_data->>'language',''), website=nullif(btrim(p_data->>'website'),''),
   industry=nullif(btrim(p_data->>'industry'),''), tags=array(select distinct btrim(value) from jsonb_array_elements_text(coalesce(p_data->'tags','[]')) where btrim(value)<>''),
   parent_id=nullif(p_data->>'parent_id','')::uuid,relation=nullif(p_data->>'relation','')
  where id=eid and version=v returning * into profile;
  if not found then raise exception 'CONTACT_VERSION_CONFLICT';end if;
 elsif p_action not in ('get','link_preview','link') then raise exception 'INVALID_ACTION';end if;
 if p_action in ('link_preview','link') then
  if private.current_user_role()<>'administrador' or tbl not in ('customers','suppliers') or not private.erp_action_allowed('contacts','edit') then raise exception 'CONTACT_LINK_ADMIN_REQUIRED';end if;
  -- Associate complementary operational roles only. Same-role duplicate merging remains its own workflow.
  execute format('select contact_entity_id from public.%I where id=$1 and active',case tbl when 'customers' then 'suppliers' else 'customers' end) into target using (p_data->>'target_id')::uuid;
  if target is null or not private.coco_contact_access(target,true) then raise exception 'ACCESS_DENIED';end if;
  if target=eid then return jsonb_build_object('linked',true,'profile',to_jsonb(profile));end if;
  perform pg_advisory_xact_lock(hashtextextended('coco-contact-role-link',0));
  perform pg_advisory_xact_lock(hashtextextended('coco-contact-parent-graph',0));
  if exists(select 1 from public.customers a join public.customers b on b.contact_entity_id=target where a.contact_entity_id=eid)
   or exists(select 1 from public.suppliers a join public.suppliers b on b.contact_entity_id=target a.contact_entity_id=eid)
   or exists(select 1 from public.crm_contacts where contact_entity_id in(eid,target)) then raise exception 'CONTACT_ROLE_COLLISION';end if;
  if p_action='link_preview' then
   return jsonb_build_object('source',to_jsonb(profile),'target',(select to_jsonb(e) from private.coco_contact_entities e where id=target),
    'source_record',(select jsonb_build_object('kind',p_kind,'id',p_id)), 'target_id',p_data->>'target_id','kept_entity',eid);
  end if;
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  perform 1 from private.coco_contact_entities where id in(eid,target) order by id for update;
  if not exists(select 1 from private.coco_contact_entities where id=eid and version=(p_data->>'version')::integer)
   or not exists(select 1 from private.coco_contact_entities where id=target and version=(p_data->>'target_version')::integer) then raise exception 'CONTACT_VERSION_CONFLICT';end if;
  -- Parent structures need a separate deliberate review, not silent reparenting.
  if exists(select 1 from private.coco_contact_entities where (id in(eid,target) and parent_id is not null) or parent_id=target) then raise exception 'CONTACT_PARENT_REVIEW_REQUIRED';end if;
  select tags into target_tags from private.coco_contact_entities where id=target;
  perform set_config('architect.change_reason','Contact role association: '||(p_data->>'reason'),true);
  update public.customers set contact_entity_id=eid where contact_entity_id=target;
  update public.suppliers set contact_entity_id=eid where contact_entity_id=target;
  update public.crm_leads set contact_entity_id=eid where contact_entity_id=target;
  update private.coco_contact_entities set tags=array(select distinct unnest(tags||target_tags)) where id=eid returning * into profile;
 end if;
 select coalesce(jsonb_agg(x order by x->>'kind'),'[]') into peers from (
  select jsonb_build_object('kind','clients','id',id,'name',name,'active',active) x from public.customers where contact_entity_id=eid and private.erp_module_allowed('contacts',array['administrador','comercial'])
  union all select jsonb_build_object('kind','suppliers','id',id,'name',name,'active',active) from public.suppliers where contact_entity_id=eid and private.erp_module_allowed('contacts',array['administrador','comercial'])
  union all select jsonb_build_object('kind','leads','id',id,'name',coalesce(company,concat_ws(' ',first_name,last_name)),'active',active,'converted',converted_customer_id is not null) from public.crm_leads where contact_entity_id=eid and private.erp_module_allowed('crm',array['administrador','comercial'])
  union all select jsonb_build_object('kind',case when customer_id is null then 'prospects' else 'people' end,'id',id,'name',concat_ws(' ',first_name,last_name),'active',active) from public.crm_contacts where contact_entity_id=eid and private.erp_module_allowed('crm',array['administrador','comercial'])
 ) links;
 return jsonb_build_object('version',1,'profile',to_jsonb(profile),'roles',peers);
end $$;
revoke all on function public.coco_contact_hub(text,uuid,text,jsonb) from public,anon;
grant execute on function public.coco_contact_hub(text,uuid,text,jsonb) to authenticated;

-- Supplemental site data live on the address actually used by quotes and the TMS.
alter table public.customer_addresses
 add column province text, add column postal_code text, add column country text,
 add column lat double precision, add column lng double precision,
 add column time_window text,add column unloading_minutes integer check(unloading_minutes between 0 and 1440),
 add column is_default boolean not null default false,
 add column version integer not null default 1,add column updated_at timestamptz not null default now(),
 add constraint coco_address_gps_pair check ((lat is null and lng is null) or (lat between -85 and 85 and lng between -180 and 180 and lat is not null and lng is not null)),
 add constraint coco_address_text_lengths check(length(coalesce(time_window,''))<=300 and length(coalesce(province,''))<=120 and length(coalesce(country,''))<=120 and length(coalesce(postal_code,''))<=30);
create unique index coco_address_one_default on public.customer_addresses(customer_id,purpose) where active and is_default;
create function private.coco_address_guard() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if tg_op='UPDATE' then
  if new.customer_id<>old.customer_id then raise exception 'ADDRESS_CUSTOMER_IMMUTABLE';end if;
  -- Editing the text cannot silently carry coordinates from the former destination.
  if row(new.address,new.city,new.province,new.postal_code,new.country) is distinct from row(old.address,old.city,old.province,old.postal_code,old.country)
   and row(new.lat,new.lng) is not distinct from row(old.lat,old.lng) then new.lat:=null;new.lng:=null;end if;
  new.version:=old.version+1;
 end if;
 if not new.active then new.is_default:=false;end if;
 new.updated_at:=now();return new;
end $$;
revoke all on function private.coco_address_guard() from public,anon,authenticated;
create trigger coco_address_guard before insert or update on public.customer_addresses for each row execute function private.coco_address_guard();
create function public.coco_contact_address_save(p_customer uuid,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare a public.customer_addresses;begin
 if auth.uid() is null or not private.erp_internal_account() or not private.erp_mfa_ok() or nullif(auth.jwt()->>'client_id','') is not null
 or not private.erp_module_allowed('contacts',array['administrador','comercial']) or not private.erp_action_allowed('clients',case when p_id is null then 'create' else 'edit' end) then raise exception 'ACCESS_DENIED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>12000 then raise exception 'INVALID_DATA';end if;
 perform 1 from public.customers where id=p_customer and active;if not found then raise exception 'ACCESS_DENIED';end if;
 perform pg_advisory_xact_lock(hashtextextended('contact-address:'||p_customer::text,0));
 if p_id is not null then
  select * into a from public.customer_addresses where id=p_id and customer_id=p_customer for update;
  if not found then raise exception 'ACCESS_DENIED';end if;
  if a.version is distinct from (p_data->>'version')::integer then raise exception 'CONTACT_VERSION_CONFLICT';end if;
 end if;
 if length(btrim(coalesce(p_data->>'label','')))=0 or length(btrim(coalesce(p_data->>'address','')))=0 then raise exception 'ADDRESS_REQUIRED';end if;
 if coalesce((p_data->>'is_default')::boolean,false) then
  update public.customer_addresses set is_default=false where customer_id=p_customer and purpose=p_data->>'purpose' and is_default and id is distinct from p_id;
 end if;
 if p_id is null then
  insert into public.customer_addresses(customer_id,label,purpose,address) values(p_customer,p_data->>'label',p_data->>'purpose',p_data->>'address') returning * into a;
 end if;
 update public.customer_addresses set label=btrim(p_data->>'label'),purpose=p_data->>'purpose',contact_name=nullif(btrim(p_data->>'contact_name'),''),
  phone=nullif(btrim(p_data->>'phone'),''),email=nullif(btrim(p_data->>'email'),''),address=btrim(p_data->>'address'),city=nullif(btrim(p_data->>'city'),''),
  province=nullif(btrim(p_data->>'province'),''),postal_code=nullif(btrim(p_data->>'postal_code'),''),country=nullif(btrim(p_data->>'country'),''),
  notes=nullif(btrim(p_data->>'notes'),''),lat=nullif(p_data->>'lat','')::double precision,lng=nullif(p_data->>'lng','')::double precision,
  time_window=nullif(btrim(p_data->>'time_window'),''),unloading_minutes=nullif(p_data->>'unloading_minutes','')::integer,is_default=coalesce((p_data->>'is_default')::boolean,false)
 where id=a.id returning * into a;
 return to_jsonb(a);
end $$;
revoke all on function public.coco_contact_address_save(uuid,uuid,jsonb) from public,anon;
grant execute on function public.coco_contact_address_save(uuid,uuid,jsonb) to authenticated;

-- Search/page only authorized projections. Business history is deliberately absent from this list.
create function public.coco_contact_directory(p_data jsonb default '{}') returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;pg integer:=least(1000000,greatest(0,coalesce((p_data->>'page')::integer,0)));sz integer:=least(100,greatest(1,coalesce((p_data->>'pageSize')::integer,20)));begin
 if auth.uid() is null or not private.erp_internal_account() or not private.erp_mfa_ok() or nullif(auth.jwt()->>'client_id','') is not null then raise exception 'ACCESS_DENIED';end if;
 if not (private.erp_module_allowed('contacts',array['administrador','comercial']) or private.erp_module_allowed('crm',array['administrador','comercial'])) then raise exception 'ACCESS_DENIED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or length(coalesce(p_data->>'search',''))>512 then raise exception 'INVALID_DATA';end if;
 with raw as materialized (
  select c.contact_entity_id eid,'clients'::text kind,c.id,c.name,coalesce(c.category,'') detail,c.identification ref,c.phone,c.email,c.city,c.active,
   to_jsonb(c)-array['credit_limit','credit_hold_reason','owner_id','source_id','crm_score','gps_address'] record,1 rank
  from public.customers c where private.erp_module_allowed('contacts',array['administrador','comercial'])
  union all
  select s.contact_entity_id,'suppliers',s.id,s.name,s.contact_name,s.tax_id,s.phone,s.email,s.city,s.active,to_jsonb(s),2
  from public.suppliers s where private.erp_module_allowed('contacts',array['administrador','comercial'])
  union all
  select k.contact_entity_id,case when k.customer_id is not null then 'people' else 'prospects' end,k.id,
   coalesce(nullif(btrim(concat_ws(' ',k.first_name,k.last_name)),''),k.email,'—'),k.job_title,
   coalesce(c.name,l.company,concat_ws(' ',l.first_name,l.last_name)),k.phone,k.email,coalesce(c.city,l.city),k.active,to_jsonb(k),3
  from public.crm_contacts k left join public.customers c on c.id=k.customer_id
   and private.erp_module_allowed('contacts',array['administrador','comercial'])
   left join public.crm_leads l on l.id=k.lead_id
  where private.erp_module_allowed('crm',array['administrador','comercial'])
 ), grouped as (
  select eid,bool_or(active) active,jsonb_agg(jsonb_build_object('id',id,'kind',kind,'name',name,'active',active) order by rank,id) roles,
   (jsonb_agg(to_jsonb(raw)-'rank' order by (kind=coalesce(nullif(p_data->>'kind',''),kind)) desc,active desc,rank,id)->0) primary_row,
   string_agg(concat_ws(' ',name,detail,ref,phone,email,city,kind,case kind when 'clients' then 'client cliente customer' when 'suppliers' then 'fournisseur proveedor supplier' when 'people' then 'contact personne person' else 'prospect prospecto' end),' ') haystack
  from raw group by eid
 ), selected as (
  select g.*,e.tags from grouped g join private.coco_contact_entities e on e.id=g.eid
  where (coalesce(p_data->>'kind','')='' or exists(select 1 from jsonb_array_elements(g.roles) r where r->>'kind'=p_data->>'kind'))
   and (coalesce(p_data->>'quality','') not in ('email','phone') or nullif(primary_row->>(p_data->>'quality'),'') is null)
   and not exists(select 1 from regexp_split_to_table(lower(btrim(coalesce(p_data->>'search',''))),'\s+') term where term<>'' and strpos(translate(lower(g.haystack||' '||array_to_string(e.tags,' ')),'áàâäãåéèêëíìîïóòôöõúùûüñç','aaaaaaeeeeiiiiooooouuuunc'),translate(term,'áàâäãåéèêëíìîïóòôöõúùûüñç','aaaaaaeeeeiiiiooooouuuunc'))=0)
 ), filtered as (
  select *,primary_row||jsonb_build_object('roles',roles,'entity_id',eid,'tags',tags) item from selected
  where case when coalesce(p_data->>'kind','')='' then active=not coalesce((p_data->>'archived')::boolean,false)
   else exists(select 1 from jsonb_array_elements(roles) r where r->>'kind'=p_data->>'kind' and (r->>'active')::boolean=not coalesce((p_data->>'archived')::boolean,false)) end
 ), sortable as (
  select *,case p_data->>'sort'
   when 'address' then primary_row#>>'{record,address}' when 'province' then primary_row#>>'{record,province}'
   when 'postalCode' then primary_row#>>'{record,postal_code}' when 'country' then primary_row#>>'{record,country}'
   when 'contactName' then primary_row#>>'{record,contact_name}' when 'category' then primary_row#>>'{record,category}'
   when 'firstName' then primary_row#>>'{record,first_name}' when 'lastName' then primary_row#>>'{record,last_name}'
   when 'jobTitle' then primary_row#>>'{record,job_title}' when 'role' then primary_row#>>'{record,decision_role}'
   when 'linkedin' then primary_row#>>'{record,linkedin}' when 'primary' then primary_row#>>'{record,is_primary}'
   when 'notes' then primary_row#>>'{record,notes}' when 'active' then primary_row->>'active'
   else primary_row->>(case when p_data->>'sort' in ('name','kind','ref','phone','email','city') then p_data->>'sort' else 'name' end) end sort_value
  from filtered
 ), ordered as (
  select * from sortable order by
   case when p_data->>'sort'='terms' and coalesce((p_data->>'ascending')::boolean,true) then (primary_row#>>'{record,payment_terms_days}')::integer end asc nulls last,
   case when p_data->>'sort'='terms' and not coalesce((p_data->>'ascending')::boolean,true) then (primary_row#>>'{record,payment_terms_days}')::integer end desc nulls last,
   case when coalesce((p_data->>'ascending')::boolean,true) then lower(sort_value) end asc nulls last,
   case when not coalesce((p_data->>'ascending')::boolean,true) then lower(sort_value) end desc nulls last,eid
  limit sz offset pg*sz
 )
 select jsonb_build_object('version',1,'items',coalesce((select jsonb_agg(item) from ordered),'[]'),'total',(select count(*) from filtered),
  'active_total',(select count(*) from grouped where active),'archived_total',(select count(*) from grouped where not active),'page',pg,'pageSize',sz) into result;
 return result;
end $$;
revoke all on function public.coco_contact_directory(jsonb) from public,anon;
grant execute on function public.coco_contact_directory(jsonb) to authenticated;

-- Reuse the CRM activity ledger for supplier follow-up as well.
alter table public.crm_activities add column supplier_id uuid references public.suppliers(id);
alter table public.crm_activities drop constraint crm_act_colgada_de_algo;
alter table public.crm_activities add constraint crm_act_colgada_de_algo check(num_nonnulls(lead_id,customer_id,contact_id,opportunity_id,invoice_id,customer_request_id,supplier_id)>0);
create index crm_activities_supplier_idx on public.crm_activities(supplier_id,due_at) where supplier_id is not null;
create function public.coco_contact_activity_save(p_kind text,p_id uuid,p_activity uuid default null,p_data jsonb default '{}') returns jsonb language plpgsql security invoker set search_path='' as $$
declare anchor text;a public.crm_activities;actor uuid:=auth.uid();begin
 perform public.coco_contact_hub(p_kind,p_id);
 if not private.erp_module_allowed('crm',array['administrador','comercial']) or not private.erp_action_allowed('crm',case when p_activity is null then 'create' else 'edit' end) then raise exception 'ACCESS_DENIED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>16000 then raise exception 'INVALID_DATA';end if;
 anchor:=case p_kind when 'clients' then 'customer_id' when 'suppliers' then 'supplier_id' when 'leads' then 'lead_id' else 'contact_id' end;
 if p_activity is not null then
  execute format('select * from public.crm_activities where id=$1 and %I=$2 for update',anchor) into a using p_activity,p_id;
  if a.id is null and p_kind='clients' then select act.* into a from public.crm_activities act join public.crm_leads l on l.id=act.lead_id and l.converted_customer_id=p_id where act.id=p_activity for update of act;end if;
  if a.id is null then raise exception 'ACCESS_DENIED';end if;
  if a.updated_at is distinct from (p_data->>'updated_at')::timestamptz then raise exception 'CONTACT_VERSION_CONFLICT';end if;
  update public.crm_activities set status='hecha',done_at=now() where id=p_activity returning * into a;
 else
  if length(btrim(coalesce(p_data->>'subject','')))=0 or length(p_data->>'subject')>300 or length(coalesce(p_data->>'body',''))>6000 then raise exception 'SUBJECT_REQUIRED';end if;
  if p_data->>'kind'<>'nota' and nullif(p_data->>'due_at','') is null then raise exception 'ACTIVITY_DUE_REQUIRED';end if;
  if nullif(p_data->>'owner_id','') is not null and not exists(select 1 from public.crm_team where id=(p_data->>'owner_id')::uuid) then raise exception 'ACTIVITY_OWNER_REQUIRED';end if;
  insert into public.crm_activities(kind,subject,body,status,owner_id,due_at,done_at,created_by,customer_id,supplier_id,lead_id,contact_id)
   values(p_data->>'kind',btrim(p_data->>'subject'),nullif(p_data->>'body',''),case when p_data->>'kind'='nota' then 'hecha' else 'pendiente' end,
    coalesce(nullif(p_data->>'owner_id','')::uuid,actor),nullif(p_data->>'due_at','')::timestamptz,case when p_data->>'kind'='nota' then now() end,actor,
    case when anchor='customer_id' then p_id end,case when anchor='supplier_id' then p_id end,case when anchor='lead_id' then p_id end,case when anchor='contact_id' then p_id end) returning * into a;
 end if;
 return to_jsonb(a);
end $$;
revoke all on function public.coco_contact_activity_save(text,uuid,uuid,jsonb) from public,anon;
grant execute on function public.coco_contact_activity_save(text,uuid,uuid,jsonb) to authenticated;

-- Atomic conversion; retries return the existing result instead of creating another customer.
create function public.coco_contact_convert_lead(p_lead uuid,p_customer uuid default null,p_data jsonb default '{}') returns jsonb language plpgsql security invoker set search_path='' as $$
declare l public.crm_leads;c public.customers;begin
 if auth.uid() is null or not private.erp_internal_account() or not private.erp_mfa_ok() or nullif(auth.jwt()->>'client_id','') is not null
 or not private.erp_module_allowed('crm',array['administrador','comercial']) or not private.erp_module_allowed('contacts',array['administrador','comercial'])
 or not private.erp_action_allowed('crm','edit') or not private.erp_action_allowed('clients',case when p_customer is null then 'create' else 'edit' end) then raise exception 'ACCESS_DENIED';end if;
 if p_data is null or octet_length(p_data::text)>12000 then raise exception 'INVALID_DATA';end if;
 select * into l from public.crm_leads where id=p_lead and active for update;
 if not found then raise exception 'ACCESS_DENIED';end if;
 if l.converted_customer_id is not null then
  if p_customer is not null and p_customer<>l.converted_customer_id then raise exception 'LEAD_ALREADY_CONVERTED';end if;
  return jsonb_build_object('customer_id',l.converted_customer_id,'already_converted',true);
 end if;
 if p_customer is null then
  if length(btrim(coalesce(p_data->>'name','')))=0 then raise exception 'CUSTOMER_NAME_REQUIRED';end if;
  insert into public.customers(name,identification,email,phone,address,city,province,postal_code,country,notes,category,owner_id,source_id,crm_score,contact_entity_id)
  values(btrim(p_data->>'name'),nullif(p_data->>'identification',''),nullif(p_data->>'email',''),nullif(p_data->>'phone',''),nullif(p_data->>'address',''),nullif(p_data->>'city',''),nullif(p_data->>'province',''),nullif(p_data->>'postal_code',''),nullif(p_data->>'country',''),nullif(p_data->>'notes',''),coalesce(nullif(p_data->>'category',''),'A'),l.owner_id,l.source_id,coalesce(l.score,0),l.contact_entity_id) returning * into c;
 else select * into c from public.customers where id=p_customer and active;if not found then raise exception 'ACCESS_DENIED';end if;
 end if;
 -- Keep the original person/opportunity IDs. Do not demote an existing customer's primary contact.
 perform 1 from public.customers where id=c.id for update;
 update public.crm_contacts set is_primary=false where lead_id=p_lead and is_primary
  and exists(select 1 from public.crm_contacts existing where existing.customer_id=c.id and existing.active and existing.is_primary);
 update public.crm_contacts set customer_id=c.id,lead_id=null where lead_id=p_lead;
 update public.crm_opportunities set customer_id=c.id,lead_id=null where lead_id=p_lead;
 -- Keep activity origin anchors on the prospect; the consolidated reader follows the proven conversion.
 update public.crm_leads set status='convertido',converted_customer_id=c.id,converted_at=now(),contact_entity_id=c.contact_entity_id where id=p_lead;
 return jsonb_build_object('customer_id',c.id,'entity_id',c.contact_entity_id,'already_converted',false);
end $$;
revoke all on function public.coco_contact_convert_lead(uuid,uuid,jsonb) from public,anon;
grant execute on function public.coco_contact_convert_lead(uuid,uuid,jsonb) to authenticated;

-- A contact dossier includes native activities plus activities whose prospect was converted to that customer.
-- SECURITY INVOKER preserves the CRM row policies; this is a projection, not a second journal.
create function public.coco_contact_activities(p_kind text,p_id uuid,p_pending boolean default false)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;begin
 perform public.coco_contact_hub(p_kind,p_id);
 if not private.erp_module_allowed('crm',array['administrador','comercial']) then raise exception 'ACCESS_DENIED';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into result from (
  select a.id,a.kind,a.subject,a.body,a.status,a.due_at,a.done_at,a.owner_id,a.updated_at,a.created_at,a.lead_id,a.customer_id,a.supplier_id,a.contact_id
  from public.crm_activities a
  where (case p_kind when 'clients' then a.customer_id=p_id or exists(select 1 from public.crm_leads l where l.id=a.lead_id and l.converted_customer_id=p_id)
   when 'suppliers' then a.supplier_id=p_id when 'leads' then a.lead_id=p_id else a.contact_id=p_id end)
  and (not p_pending or a.status in ('pendiente','en_curso'))
  order by case when p_pending then a.due_at end asc nulls last,a.created_at desc,a.id
  limit case when p_pending then 1 else 100 end
 ) x;
 return result;
end $$;
revoke all on function public.coco_contact_activities(text,uuid,boolean) from public,anon;
grant execute on function public.coco_contact_activities(text,uuid,boolean) to authenticated;