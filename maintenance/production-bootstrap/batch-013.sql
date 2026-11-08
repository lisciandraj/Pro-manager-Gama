do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>294
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;

-- Canonical source: 20261015202048_coco_contacts_hub.sql; SHA256 7a13117770a7f57932f6e4c1d3dbde342c6c3d7e062175270d218e240dcb6d79
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
   or exists(select 1 from public.suppliers a join public.suppliers b on b.contact_entity_id=target where a.contact_entity_id=eid)
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
insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261015202048','coco_contacts_hub','7a13117770a7f57932f6e4c1d3dbde342c6c3d7e062175270d218e240dcb6d79','7a13117770a7f57932f6e4c1d3dbde342c6c3d7e062175270d218e240dcb6d79','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261016160823_coco_contact_alignment.sql; SHA256 7ed58c4e6c161ab041ffe28530cf55f925d1dfea297d52f659178ffce54b2f8b
-- Align native contact records without changing business IDs, memberships or documents.
-- Only explicitly shared contact_entity_id values define the same identity.
alter table private.coco_contact_entities
 add column details jsonb not null default '{}' check(jsonb_typeof(details)='object'),
 add column alignment_conflicts jsonb not null default '{}' check(jsonb_typeof(alignment_conflicts)='object');
grant update(details,alignment_conflicts) on private.coco_contact_entities to authenticated;

-- Compatibility columns: the four native tables keep their existing business roles.
alter table public.customers add column phone2 text, add column website text, add column industry text, add column language text;
alter table public.suppliers add column phone2 text, add column website text, add column industry text, add column language text,
 add column lat double precision,add column lng double precision;
alter table public.crm_leads add column identification text,add column identification_kind text not null default 'auto',
 add column language text,add column lat double precision,add column lng double precision;
alter table public.crm_contacts add column identification text,add column identification_kind text not null default 'auto',
 add column phone2 text,add column address text,add column city text,add column province text,add column postal_code text,
 add column country text,add column lat double precision,add column lng double precision,
 add column website text,add column industry text,add column language text,
 add column address_mode text not null default 'parent' check(address_mode in ('parent','own'));

-- Private restoration point: no business records are exported into Git.
create table private.coco_contact_alignment_backup (
 source_table text not null,row_id uuid not null,row_data jsonb not null,archived_at timestamptz not null default now(),
 primary key(source_table,row_id)
);
alter table private.coco_contact_alignment_backup enable row level security;
revoke all on private.coco_contact_alignment_backup from public,anon,authenticated;
insert into private.coco_contact_alignment_backup(source_table,row_id,row_data)
 select 'customers',id,to_jsonb(c) from public.customers c union all
 select 'suppliers',id,to_jsonb(s) from public.suppliers s union all
 select 'crm_leads',id,to_jsonb(l) from public.crm_leads l union all
 select 'crm_contacts',id,to_jsonb(p) from public.crm_contacts p union all
 select 'coco_contact_entities',id,to_jsonb(e) from private.coco_contact_entities e;

create function private.coco_contact_system_writer() returns boolean language sql stable security invoker set search_path='' as $$
 select auth.uid() is null and (session_user in ('postgres','supabase_admin') or current_setting('role',true) in ('service_role','postgres','supabase_admin'))
$$;
revoke all on function private.coco_contact_system_writer() from public,anon;
grant execute on function private.coco_contact_system_writer() to authenticated,service_role;

create function private.coco_contact_field_map(p_table text) returns jsonb language sql immutable security invoker set search_path='' as $$
 select jsonb_build_object('email','email','phone','phone','phone2','phone2','address','address','city','city',
  'province','province','postal_code','postal_code','country','country','lat','lat','lng','lng',
  'website','website','industry','industry','language','language','identification_kind','identification_kind',
  'identification',case when p_table='suppliers' then 'tax_id' else 'identification' end)
 ||case p_table when 'crm_contacts' then jsonb_build_object('first_name','first_name','last_name','last_name')
  when 'crm_leads' then jsonb_build_object('display_name','company')
  when 'customers' then jsonb_build_object('display_name','name')
  when 'suppliers' then jsonb_build_object('display_name','name') else '{}'::jsonb end
$$;
revoke all on function private.coco_contact_field_map(text) from public,anon;
grant execute on function private.coco_contact_field_map(text) to authenticated,service_role;

create function private.coco_contact_values(p_table text,p_row jsonb) returns jsonb language sql immutable security invoker set search_path='' as $$
 select coalesce(jsonb_object_agg(m.key,case when jsonb_typeof(p_row->m.value)='string' then
  to_jsonb(nullif(case when m.key='website' and btrim(p_row->>m.value) ~* '^https?://' then regexp_replace(btrim(p_row->>m.value),'^https?://',lower(substring(btrim(p_row->>m.value) from '^[^:]+://')),'i') else btrim(p_row->>m.value) end,''))
  else p_row->m.value end),'{}')
 from jsonb_each_text(private.coco_contact_field_map(p_table)) m
 where p_row ? m.value and not (p_table='crm_leads' and m.key='display_name' and p_row->>'kind'<>'empresa')
$$;
revoke all on function private.coco_contact_values(text,jsonb) from public,anon;
grant execute on function private.coco_contact_values(text,jsonb) to authenticated,service_role;

create function private.coco_contact_members(p_entity uuid) returns table(source_table text,row_id uuid,row_data jsonb)
language sql stable security invoker set search_path='' as $$
 select 'customers',id,to_jsonb(c) from public.customers c where contact_entity_id=p_entity union all
 select 'suppliers',id,to_jsonb(s) from public.suppliers s where contact_entity_id=p_entity union all
 select 'crm_leads',id,to_jsonb(l) from public.crm_leads l where contact_entity_id=p_entity union all
 select 'crm_contacts',id,to_jsonb(p) from public.crm_contacts p where contact_entity_id=p_entity
$$;
revoke all on function private.coco_contact_members(uuid) from public,anon;
grant execute on function private.coco_contact_members(uuid) to authenticated,service_role;

-- Retain the existing graph/permission checks. The maintenance allowance is only
-- for actual database administrators and the server-side service role, never an app user.
create or replace function private.coco_contact_profile_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare ancestor uuid;visited uuid[]:=array[new.id];k text;sys boolean:=private.coco_contact_system_writer();begin
 if not sys and (auth.uid() is null or not private.coco_contact_access(new.id,true)) then raise exception 'ACCESS_DENIED';end if;
 if exists(select 1 from jsonb_object_keys(new.details) AS allowed_keys(key) where allowed_keys.key not in
  ('display_name','first_name','last_name','email','phone','phone2','address','city','province','postal_code','country','lat','lng','website','industry','language','identification','identification_kind')) then raise exception 'CONTACT_INVALID_DATA';end if;
 foreach k in array array['website','industry','language'] loop
  if new.details->k is distinct from old.details->k and new.details ? k then
   new:=jsonb_populate_record(new,jsonb_build_object(k,new.details->k));
  elsif to_jsonb(new)->k is distinct from to_jsonb(old)->k then
   new.details:=new.details||jsonb_build_object(k,to_jsonb(new)->k);
   new.alignment_conflicts:=new.alignment_conflicts-k;
  end if;
 end loop;
 if new.parent_id is not null then
  perform pg_advisory_xact_lock(hashtextextended('coco-contact-parent-graph',0));
  if not sys and not private.coco_contact_access(new.parent_id) then raise exception 'CONTACT_PARENT_ACCESS_DENIED';end if;
  ancestor:=new.parent_id;
  while ancestor is not null loop
   if ancestor=any(visited) then raise exception 'CONTACT_PARENT_CYCLE';end if;
   visited:=visited||ancestor;select parent_id into ancestor from private.coco_contact_entities where id=ancestor;
  end loop;
 end if;
 new.version:=old.version+1;new.updated_at:=now();new.updated_by:=auth.uid();return new;
end $$;

-- Echo only changed, allowlisted coordinates. Native RLS and action guards remain
-- effective: this function is SECURITY INVOKER, not a privileged write gateway.
create function private.coco_contact_mirror() returns trigger language plpgsql security invoker set search_path='' as $$
declare m record;patch jsonb;sets text;mod text;action_module text;sys boolean:=private.coco_contact_system_writer();begin
 if new.details=old.details then return new;end if;
 for m in select * from private.coco_contact_members(new.id) loop
  select coalesce(jsonb_object_agg(f.value,v.value),'{}') into patch
   from jsonb_each(new.details) v join jsonb_each_text(private.coco_contact_field_map(m.source_table)) f on f.key=v.key
   where v.value is distinct from old.details->v.key
    and v.value is distinct from m.row_data->f.value
    and not (m.source_table='crm_leads' and f.key='display_name' and m.row_data->>'kind'<>'empresa');
  if patch='{}' then continue;end if;
  mod:=case when m.source_table in ('customers','suppliers') then 'contacts' else 'crm' end;
  action_module:=case m.source_table when 'customers' then 'clients' when 'suppliers' then 'suppliers' else 'crm' end;
  if not sys and (not private.erp_module_allowed(mod,array['administrador','comercial']) or not private.erp_action_allowed(action_module,'edit')) then raise exception 'CONTACT_LINKED_ACCESS_REQUIRED';end if;
  select string_agg(format('%I=(jsonb_populate_record(null::public.%I,$1)).%I',key,m.source_table,key),',') into sets from jsonb_object_keys(patch) key;
  execute format('update public.%I set %s,updated_at=now() where id=$2',m.source_table,sets) using patch,m.row_id;
 end loop;
 return new;
end $$;
revoke all on function private.coco_contact_mirror() from public,anon,authenticated;
create trigger coco_contact_alignment_mirror after update of details,website,industry,language on private.coco_contact_entities
 for each row execute function private.coco_contact_mirror();

create function private.coco_contact_reconcile(p_entity uuid) returns void language plpgsql security invoker set search_path='' as $$
declare merged jsonb;conflicts jsonb;profile private.coco_contact_entities;address_conflict boolean;begin
 select * into profile from private.coco_contact_entities where id=p_entity for update;
 if not found then raise exception 'CONTACT_ACCESS_DENIED';end if;
 with vals as (
  select v.key,v.value,m.source_table,m.row_id from private.coco_contact_members(p_entity) m,
   lateral jsonb_each(private.coco_contact_values(m.source_table,m.row_data)) v where v.value<>'null'::jsonb
  union all select k,to_jsonb(profile)->k,'shared_profile',profile.id from unnest(array['website','industry','language']) k where (to_jsonb(profile)->k)<>'null'::jsonb
 ), fields as (
  select key,count(distinct value) n,jsonb_agg(distinct value)->0 value,
   jsonb_agg(jsonb_build_object('source',source_table,'id',row_id,'value',value)) alternatives from vals group by key
 ) select coalesce(jsonb_object_agg(key,value) filter(where n=1),'{}'),coalesce(jsonb_object_agg(key,jsonb_build_object('variants',n)) filter(where n>1),'{}') into merged,conflicts from fields;
 address_conflict:=conflicts ?|array['address','city','province','postal_code','country','lat','lng'];
 if address_conflict then merged:=merged-array['address','city','province','postal_code','country','lat','lng'];end if;
 -- Unresolved discrepancies keep the prior values on each role, with alternatives
 -- recorded for review. A missing value is filled only from an unambiguous identity.
 update private.coco_contact_entities set details=profile.details||merged,alignment_conflicts=conflicts where id=p_entity;
end $$;
revoke all on function private.coco_contact_reconcile(uuid) from public,anon;
grant execute on function private.coco_contact_reconcile(uuid) to authenticated,service_role;

create function private.coco_contact_capture() returns trigger language plpgsql security invoker set search_path='' as $$
declare incoming jsonb;previous jsonb;delta jsonb;current_data jsonb;conflicts jsonb;begin
 if tg_op='INSERT' or new.contact_entity_id is distinct from old.contact_entity_id then
  perform private.coco_contact_reconcile(new.contact_entity_id);return new;
 end if;
 incoming:=private.coco_contact_values(tg_table_name,to_jsonb(new));previous:=private.coco_contact_values(tg_table_name,to_jsonb(old));
 select coalesce(jsonb_object_agg(key,value),'{}') into delta from jsonb_each(incoming) where value is distinct from previous->key;
 select details,alignment_conflicts into current_data,conflicts from private.coco_contact_entities where id=new.contact_entity_id for update;
 if not found then raise exception 'CONTACT_ACCESS_DENIED';end if;
 if delta='{}' then
  -- Role-specific edits also invalidate open editors without copying these fields.
  if (to_jsonb(new)-'updated_at') is distinct from (to_jsonb(old)-'updated_at') then
   update private.coco_contact_entities set details=details where id=new.contact_entity_id;
  end if;return new;
 end if;
 if not exists(select 1 from jsonb_each(delta) where value is distinct from current_data->key) then return new;end if;
 if exists(select 1 from jsonb_each(delta) where current_data ? key and not conflicts ? key
   and current_data->key is distinct from previous->key and current_data->key is distinct from value) then raise exception 'CONTACT_VERSION_CONFLICT';end if;
 update private.coco_contact_entities set details=details||delta,
  alignment_conflicts=alignment_conflicts-array(select jsonb_object_keys(delta)) where id=new.contact_entity_id;
 return new;
end $$;
revoke all on function private.coco_contact_capture() from public,anon,authenticated;

-- Invalidate a coordinate pair when any part of its address changes. A complete
-- replacement GPS pair is required; missing positions remain null, never (0,0).
create function private.coco_contact_address_guard() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if tg_op='UPDATE' and row(new.address,new.city,new.province,new.postal_code,new.country) is distinct from row(old.address,old.city,old.province,old.postal_code,old.country)
  and row(new.lat,new.lng) is not distinct from row(old.lat,old.lng) then new.lat:=null;new.lng:=null;end if;
 if (new.lat is null)<>(new.lng is null) or not coalesce(new.lat between -85 and 85 and new.lng between -180 and 180,true) then raise exception 'CONTACT_INVALID_COORDINATES';end if;
 return new;
end $$;
revoke all on function private.coco_contact_address_guard() from public,anon,authenticated;

-- Seed before enabling capture to avoid treating backfill as an end-user change.
do $$declare e record;t text;begin
 for e in select distinct contact_entity_id id from public.customers union select contact_entity_id from public.suppliers
  union select contact_entity_id from public.crm_leads union select contact_entity_id from public.crm_contacts loop
  perform private.coco_contact_reconcile(e.id);
 end loop;
 foreach t in array array['customers','suppliers','crm_leads','crm_contacts'] loop
  execute format('create trigger coco_contact_alignment_capture after insert or update on public.%I for each row execute function private.coco_contact_capture()',t);
  execute format('create trigger coco_contact_address_coordinates before insert or update on public.%I for each row execute function private.coco_contact_address_guard()',t);
 end loop;
end $$;

create function public.coco_contact_record(p_kind text,p_id uuid) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tbl text;rec jsonb;profile jsonb;parent jsonb;parent_kind text;begin
 tbl:=case p_kind when 'clients' then 'customers' when 'suppliers' then 'suppliers' when 'leads' then 'crm_leads' when 'people' then 'crm_contacts' when 'prospects' then 'crm_contacts' end;
 if tbl is null or auth.uid() is null or not private.erp_internal_account() or not private.erp_mfa_ok() or nullif(auth.jwt()->>'client_id','') is not null
  or not private.erp_module_allowed(case when tbl in ('customers','suppliers') then 'contacts' else 'crm' end,array['administrador','comercial']) then raise exception 'CONTACT_ACCESS_DENIED';end if;
 execute format('select to_jsonb(r) from public.%I r where id=$1',tbl) into rec using p_id;
 if rec is null then raise exception 'CONTACT_NOT_FOUND';end if;
 select to_jsonb(e) into profile from private.coco_contact_entities e where id=(rec->>'contact_entity_id')::uuid;
 if profile is null then raise exception 'CONTACT_ACCESS_DENIED';end if;
 if tbl='crm_contacts' and rec->>'address_mode'='parent' then
  if rec->>'customer_id' is not null and private.erp_module_allowed('contacts',array['administrador','comercial']) then
   select to_jsonb(c) into parent from public.customers c where id=(rec->>'customer_id')::uuid;parent_kind:='clients';
  elsif rec->>'lead_id' is not null then
   select to_jsonb(l) into parent from public.crm_leads l where id=(rec->>'lead_id')::uuid;parent_kind:='leads';
  end if;
 end if;
 return jsonb_build_object('record',rec,'profile',profile,'version',(profile->>'version')::integer,
  'inherited_address',case when parent is not null then jsonb_build_object('kind',parent_kind,'id',parent->'id','name',coalesce(parent->'name',parent->'company'))||
    (select jsonb_object_agg(k,parent->k) from unnest(array['address','city','province','postal_code','country','lat','lng']) k) else null end);
end $$;
revoke all on function public.coco_contact_record(text,uuid) from public,anon;
grant execute on function public.coco_contact_record(text,uuid) to authenticated;

-- The same whitelist/transaction serves every editor. A missing key is untouched;
-- explicit null clears an optional field. Versions cover both shared and role data.
create function public.coco_contact_save(p_kind text,p_id uuid default null,p_data jsonb default '{}',p_version integer default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tbl text;rec jsonb;native jsonb;allowed text[];cols text;vals text;result_id uuid:=p_id;module text;e uuid;v integer;begin
 tbl:=case p_kind when 'clients' then 'customers' when 'suppliers' then 'suppliers' when 'leads' then 'crm_leads' when 'people' then 'crm_contacts' when 'prospects' then 'crm_contacts' end;
 module:=case tbl when 'customers' then 'clients' when 'suppliers' then 'suppliers' else 'crm' end;
 if tbl is null or auth.uid() is null or not private.erp_internal_account() or not private.erp_mfa_ok() or nullif(auth.jwt()->>'client_id','') is not null
  or not private.erp_module_allowed(case when tbl in ('customers','suppliers') then 'contacts' else 'crm' end,array['administrador','comercial'])
  or not private.erp_action_allowed(module,case when p_id is null then 'create' else 'edit' end) then raise exception 'CONTACT_ACCESS_DENIED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>20000 then raise exception 'CONTACT_INVALID_DATA';end if;
 if p_id is not null then
  execute format('select to_jsonb(r) from public.%I r where id=$1',tbl) into rec using p_id;
  if rec is null then raise exception 'CONTACT_NOT_FOUND';end if;e:=(rec->>'contact_entity_id')::uuid;
  select version into v from private.coco_contact_entities where id=e for update;
  if v is null or v is distinct from p_version then raise exception 'CONTACT_VERSION_CONFLICT';end if;
 end if;
 allowed:=array(select value from jsonb_each_text(private.coco_contact_field_map(tbl)))||array['notes'];
 if tbl='customers' then allowed:=allowed||array['category','payment_terms_days'];
 elsif tbl='suppliers' then allowed:=allowed||array['contact_name'];
 elsif tbl='crm_contacts' then allowed:=allowed||array['customer_id','lead_id','job_title','linkedin','decision_role','is_primary','address_mode'];
 else allowed:=allowed||array['kind','first_name','last_name','job_title','company_size','source_id','owner_id','priority','score','next_followup_at'];end if;
 if exists(select 1 from jsonb_object_keys(p_data) k where not k=any(allowed)) then raise exception 'CONTACT_INVALID_DATA';end if;
 native:=p_data;
 if tbl='crm_contacts' then
  -- Reuse the existing transactional primary-contact and parent validation.
  rec:=coalesce(rec,'{}')||p_data;
  select public.gama_contact_person_save(p_id,rec) into rec;result_id:=(rec->>'id')::uuid;
  native:=native-array['customer_id','lead_id','first_name','last_name','job_title','email','phone','linkedin','decision_role','notes','is_primary'];
 elsif p_id is null then
  if native='{}' then raise exception 'CONTACT_INVALID_DATA';end if;
  select string_agg(format('%I',k),','),string_agg(format('(jsonb_populate_record(null::public.%I,$1)).%I',tbl,k),',') into cols,vals from jsonb_object_keys(native) k;
  execute format('insert into public.%I (%s) select %s returning id',tbl,cols,vals) into result_id using native;native:='{}';
 end if;
 if native<>'{}' then
  select string_agg(format('%I=(jsonb_populate_record(null::public.%I,$1)).%I',k,tbl,k),',') into cols from jsonb_object_keys(native) k;
  execute format('update public.%I set %s,updated_at=now() where id=$2',tbl,cols) using native,result_id;
 end if;
 return public.coco_contact_record(p_kind,result_id);
end $$;
revoke all on function public.coco_contact_save(text,uuid,jsonb,integer) from public,anon;
grant execute on function public.coco_contact_save(text,uuid,jsonb,integer) to authenticated;

-- A discrepancy never chooses a winner automatically. Comparison requires access
-- to every linked role; the shared conflict flags themselves contain no hidden data.
create function public.coco_contact_compare(p_kind text,p_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare r jsonb;profile private.coco_contact_entities;m record;fields jsonb:='{}';keys text[];k text;options jsonb;values jsonb;begin
 r:=public.coco_contact_record(p_kind,p_id);
 select * into profile from private.coco_contact_entities where id=(r#>>'{profile,id}')::uuid;
 for m in select * from private.coco_contact_members(profile.id) loop
  if not private.erp_module_allowed(case when m.source_table in ('customers','suppliers') then 'contacts' else 'crm' end,array['administrador','comercial']) then raise exception 'CONTACT_LINKED_ACCESS_REQUIRED';end if;
 end loop;
 keys:=array(select jsonb_object_keys(profile.alignment_conflicts));
 if keys&&array['address','city','province','postal_code','country','lat','lng'] then
  keys:=array(select unnest(keys) except select unnest(array['address','city','province','postal_code','country','lat','lng']))||array['address_block'];end if;
 if keys&&array['identification','identification_kind'] then
  keys:=array(select unnest(keys) except select unnest(array['identification','identification_kind']))||array['identity_block'];end if;
 foreach k in array keys loop
  options:='[]';
  for m in select * from private.coco_contact_members(profile.id) loop
   values:=private.coco_contact_values(m.source_table,m.row_data);
   if k='address_block' then values:=(select jsonb_object_agg(f,coalesce(values->f,'null')) from unnest(array['address','city','province','postal_code','country','lat','lng']) f);
   elsif k='identity_block' then values:=jsonb_build_object('identification',values->'identification','identification_kind',values->'identification_kind');
   else values:=coalesce(values->k,'null');end if;
   options:=options||jsonb_build_array(jsonb_build_object('source',m.source_table,'id',m.row_id,'value',values));
  end loop;
  fields:=fields||jsonb_build_object(k,options);
 end loop;
 return jsonb_build_object('version',profile.version,'fields',fields);
end $$;
revoke all on function public.coco_contact_compare(text,uuid) from public,anon;
grant execute on function public.coco_contact_compare(text,uuid) to authenticated;

create function public.coco_contact_resolve(p_kind text,p_id uuid,p_version integer,p_values jsonb,p_reason text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare r jsonb;comparison jsonb;choice record;patch jsonb:='{}';eid uuid;v integer;begin
 r:=public.coco_contact_record(p_kind,p_id);eid:=(r#>>'{profile,id}')::uuid;
 select version into v from private.coco_contact_entities where id=eid for update;
 if v is distinct from p_version then raise exception 'CONTACT_VERSION_CONFLICT';end if;
 if not private.coco_contact_access(eid,true) then raise exception 'CONTACT_ACCESS_DENIED';end if;
 if p_values is null or jsonb_typeof(p_values)<>'object' or p_values='{}' or octet_length(p_values::text)>12000
   or length(btrim(coalesce(p_reason,'')))<3 or length(p_reason)>500 then raise exception 'CONTACT_INVALID_DATA';end if;
 comparison:=public.coco_contact_compare(p_kind,p_id);
 for choice in select * from jsonb_each(p_values) loop
  if not coalesce((comparison->'fields')?choice.key,false) or not exists(select 1 from jsonb_array_elements(comparison#>array['fields',choice.key]) a where a->'value'=choice.value) then raise exception 'CONTACT_INVALID_CHOICE';end if;
  patch:=patch||case when choice.key in ('address_block','identity_block') then choice.value else jsonb_build_object(choice.key,choice.value) end;
 end loop;
 perform set_config('architect.change_reason','Contact alignment: '||p_reason,true);
 -- Force an explicit selected value to reach differing legacy rows, even when the
 -- chosen value is already the canonical value. Both writes are one transaction.
 update private.coco_contact_entities set details=details-array(select jsonb_object_keys(patch)) where id=eid;
 update private.coco_contact_entities set details=details||patch,
  alignment_conflicts=alignment_conflicts-array(select jsonb_object_keys(patch)) where id=eid;
 return public.coco_contact_record(p_kind,p_id);
end $$;
revoke all on function public.coco_contact_resolve(text,uuid,integer,jsonb,text) from public,anon;
grant execute on function public.coco_contact_resolve(text,uuid,integer,jsonb,text) to authenticated;

-- Directory values and search use the effective address for a person, without copying it.
create or replace function public.coco_contact_directory(p_data jsonb default '{}') returns jsonb language plpgsql stable security invoker set search_path='' as $$
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
   coalesce(c.name,l.company,concat_ws(' ',l.first_name,l.last_name)),k.phone,k.email,case when k.address_mode='own' then k.city else coalesce(c.city,l.city) end,k.active,
   to_jsonb(k)||case when k.address_mode='own' then '{}'::jsonb else jsonb_build_object('address',coalesce(c.address,l.address),'city',coalesce(c.city,l.city),'province',coalesce(c.province,l.province),'postal_code',coalesce(c.postal_code,l.postal_code),'country',coalesce(c.country,l.country),'address_inherited',true) end,3
  from public.crm_contacts k left join public.customers c on c.id=k.customer_id
   and private.erp_module_allowed('contacts',array['administrador','comercial'])
   left join public.crm_leads l on l.id=k.lead_id
  where private.erp_module_allowed('crm',array['administrador','comercial'])
 ), grouped as (
  select eid,bool_or(active) active,jsonb_agg(jsonb_build_object('id',id,'kind',kind,'name',name,'active',active) order by rank,id) roles,
   (jsonb_agg(to_jsonb(raw)-'rank' order by (kind=coalesce(nullif(p_data->>'kind',''),kind)) desc,active desc,rank,id)->0) primary_row,
   string_agg(concat_ws(' ',name,detail,ref,phone,email,city,record->>'phone2',record->>'website',record->>'industry',record->>'country',record->>'postal_code',kind,case kind when 'clients' then 'client cliente customer' when 'suppliers' then 'fournisseur proveedor supplier' when 'people' then 'contact personne person' else 'prospect prospecto' end),' ') haystack
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
   when 'phone2' then primary_row#>>'{record,phone2}' when 'website' then primary_row#>>'{record,website}' when 'industry' then primary_row#>>'{record,industry}' when 'language' then primary_row#>>'{record,language}'
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


insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261016160823','coco_contact_alignment','7ed58c4e6c161ab041ffe28530cf55f925d1dfea297d52f659178ffce54b2f8b','7ed58c4e6c161ab041ffe28530cf55f925d1dfea297d52f659178ffce54b2f8b','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261016204331_automatic_minmax_purchase_drafts.sql; SHA256 9b5cc392043d84a428b2dbace0a73be8118ed7aca5f1008adda5fdd89658505c
-- Fixed product thresholds are a separate, explicit mode of the existing
-- delegated automation. The minute scheduler works even with every client closed.
-- Installing this migration alone does not enable or renew a delegation.
create function private.stock_minmax_replenishment_rows()
returns table(product_id uuid,data jsonb)
language sql stable security invoker set search_path='' as $$
 with pending as (
  select l.product_id,
   coalesce(sum(greatest(l.quantity-l.received_quantity,0)) filter(where o.status='draft'),0) drafts,
   coalesce(sum(greatest(l.quantity-l.received_quantity,0)) filter(where o.status in ('sent','partial')),0) incoming
  from public.purchase_order_lines l join public.purchase_orders o on o.id=l.purchase_order_id
  where o.status in ('draft','sent','partial') group by l.product_id
 )
 select p.id,jsonb_build_object(
  'id',p.id,'name',p.name,'reference',p.reference,'supplier_id',s.id,
  'on_hand',p.stock,'min_stock',p.min_stock,'max_stock',p.max_stock,
  'draft_quantity',coalesce(b.drafts,0),'incoming',coalesce(b.incoming,0),
  'quantity',round(greatest(p.max_stock-p.stock-coalesce(b.drafts,0)-coalesce(b.incoming,0),0),3),
  'thresholds_valid',p.min_stock>=0 and p.max_stock>0 and p.max_stock>=p.min_stock,
  'unit_cost',round(coalesce(p.purchase_price,0),2),'tax_rate',coalesce(p.tax_rate,0),
  'lead_time_days',r.lead
 )
 from public.products p left join pending b on b.product_id=p.id
 left join public.suppliers s on s.id=p.supplier_id and s.active
 left join lateral (
  select max(z.lead_time_days) lead from public.reorder_rules z
  where z.product_id=p.id and z.active
   and (z.warehouse_id is null or not exists(
    select 1 from public.reorder_rules g where g.product_id=p.id and g.active and g.warehouse_id is null))
 ) r on true
 where p.active and p.product_kind='goods' and not p.replenishment_excluded and p.stock<p.min_stock
$$;
revoke all on function private.stock_minmax_replenishment_rows() from public,anon,authenticated,service_role;

create function private.automation_replenish_minmax(p_job private.automation_jobs,p_config jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 row record;item jsonb;items jsonb:='[]';grouped record;orders jsonb:='[]';po jsonb;result jsonb;
 cap numeric:=coalesce((p_config->>'max_order_total')::numeric,1000);
 receipt private.command_receipts;products_count integer:=0;skipped integer:=0;reason text;
begin
 if auth.uid() is null or not private.automation_delegation_ok() then raise exception 'DELEGATION_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','comercial'])
  or not private.erp_action_allowed('gamaPurchasesV14','create') then raise exception 'ACTION_NOT_ALLOWED';end if;
 if cap::text in ('NaN','Infinity','-Infinity') or cap<=0 or cap>1000000 then
  return jsonb_build_object('blocked',true,'reason','PURCHASE_LIMIT_REQUIRED');
 end if;
 -- Shared with manual Stock replenishment, and protected by the durable job
 -- receipt as well as the canonical purchase command's own receipts.
 perform pg_advisory_xact_lock(hashtextextended('stock-replenishment',0));
 select * into receipt from private.command_receipts where domain='automatic-minmax-replenish' and request_key=p_job.id;
 if found then
  if receipt.actor_id<>auth.uid() or receipt.payload is distinct from p_config then raise exception 'REQUEST_KEY_REUSED';end if;
  return receipt.result;
 end if;
 -- Resolve old product exceptions when stock/thresholds/following purchases
 -- have changed. Still-invalid rows are reopened below with the current reason.
 update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now()
  where kind='replenishment' and key like 'minmax:%' and active;
 for row in select x.product_id,x.data from private.stock_minmax_replenishment_rows() x order by x.product_id limit 3000 loop
  item:=row.data;reason:=null;
  if not (item->>'thresholds_valid')::boolean then reason:='MIN_MAX_REQUIRED';
  elsif (item->>'quantity')::numeric<=0 then continue;
  elsif nullif(item->>'supplier_id','') is null then reason:='ACTIVE_SUPPLIER_REQUIRED';
  elsif (item->>'quantity')::numeric>999999999 then reason:='INVALID_QUANTITY';
  elsif (item->>'unit_cost')::numeric<0 or (item->>'unit_cost')::numeric>999999999 then reason:='INVALID_PRICE';
  end if;
  if reason is not null then
   perform private.automation_exception('minmax:'||row.product_id,'replenishment','gamaPurchasesV14','product',row.product_id,reason,p_job.id,item->>'reference');
   skipped:=skipped+1;
  else items:=items||jsonb_build_array(item);
  end if;
 end loop;
 for grouped in
  select x->>'supplier_id' supplier,max((x->>'lead_time_days')::integer) lead,
   sum(round((x->>'quantity')::numeric*(x->>'unit_cost')::numeric,2)
    +round(round((x->>'quantity')::numeric*(x->>'unit_cost')::numeric,2)*(x->>'tax_rate')::numeric/100,2)) total,
   jsonb_agg(jsonb_build_object('product_id',x->>'id','quantity',(x->>'quantity')::numeric,
    'unit_cost',(x->>'unit_cost')::numeric,'tax_rate',(x->>'tax_rate')::numeric) order by x->>'id') lines
  from jsonb_array_elements(items) x group by x->>'supplier_id' order by x->>'supplier_id'
 loop
  if grouped.total>cap or jsonb_array_length(grouped.lines)>500 then
   perform private.automation_exception('minmax:limit:'||grouped.supplier,'replenishment','gamaPurchasesV14','supplier',grouped.supplier::uuid,
    case when grouped.total>cap then 'PURCHASE_LIMIT_EXCEEDED' else 'SUPPLIER_LINE_LIMIT_500' end,p_job.id);
   skipped:=skipped+jsonb_array_length(grouped.lines);continue;
  end if;
  po:=private.gama_purchase_save(jsonb_build_object(
   'request_key',private.automation_key('minmax:'||p_job.id||':'||grouped.supplier),
   'supplier_id',grouped.supplier,'source_kind','low_stock',
   'destination_location_id',p_config->>'destination_location_id',
   'expected_date',case when grouped.lead is not null then current_date+grouped.lead end,
   'notes','Reposición automática mín./máx.: máximo de la ficha menos stock físico y compras pendientes (incluidos borradores). Revisar antes de enviar.',
   'lines',grouped.lines));
  orders:=orders||jsonb_build_array(jsonb_build_object('id',po->>'id','number',po->>'order_number',
   'supplier_id',grouped.supplier,'lines',jsonb_array_length(grouped.lines)));
  products_count:=products_count+jsonb_array_length(grouped.lines);
 end loop;
 result:=jsonb_build_object('orders',orders,'products',products_count,'skipped',skipped,'basis','min_max','as_of',now());
 insert into private.command_receipts(domain,request_key,actor_id,payload,result)
  values('automatic-minmax-replenish',p_job.id,auth.uid(),p_config,result);
 return result;
end $$;
revoke all on function private.automation_replenish_minmax(private.automation_jobs,jsonb) from public,anon,authenticated,service_role;

-- Preserve the demand-based mode and every existing rule's behaviour.
alter function private.automation_replenish(private.automation_jobs,jsonb) rename to automation_replenish_forecast;
create function private.automation_replenish(p_job private.automation_jobs,p_config jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$begin
 if p_config->>'basis'='min_max' then return private.automation_replenish_minmax(p_job,p_config);
 elsif coalesce(p_config->>'basis','demand')='demand' then return private.automation_replenish_forecast(p_job,p_config);
 else raise exception 'INVALID_REPLENISHMENT_BASIS';end if;
end $$;
revoke all on function private.automation_replenish(private.automation_jobs,jsonb),
 private.automation_replenish_forecast(private.automation_jobs,jsonb) from public,anon,authenticated,service_role;

-- The Purchases suggestions must also deduct drafts; otherwise the manual
-- button continues proposing the quantities the background job just created.
-- Preserve the view's existing column order, access checks and demand semantics.
do $$declare source text;columns_sql text;begin
 source:=rtrim(pg_get_viewdef('public.replenishment_needs'::regclass,true),';');
 select string_agg(case
  when attname='projected_available' then '(b.projected_available+coalesce(d.quantity,0))::numeric as projected_available'
  when attname='suggested_purchase' then $column$case when p.replenishment_excluded then 0::numeric
   when b.projected_available+coalesce(d.quantity,0)<b.min_stock or b.projected_available+coalesce(d.quantity,0)<0
   then greatest(b.max_stock,b.min_stock,0)-b.projected_available-coalesce(d.quantity,0) else 0::numeric end as suggested_purchase$column$
  else format('b.%I',attname) end,',' order by attnum) into columns_sql
 from pg_attribute where attrelid='public.replenishment_needs'::regclass and attnum>0 and not attisdropped;
 execute 'create or replace view public.replenishment_needs with(security_invoker=true) as select '||columns_sql||
  ' from ('||source||') b join public.products p on p.id=b.product_id left join ('||
  'select l.product_id,sum(greatest(l.quantity-l.received_quantity,0)) quantity from public.purchase_order_lines l '||
  'join public.purchase_orders o on o.id=l.purchase_order_id where o.status=''draft'' group by l.product_id) d on d.product_id=b.product_id';
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261016204331','automatic_minmax_purchase_drafts','9b5cc392043d84a428b2dbace0a73be8118ed7aca5f1008adda5fdd89658505c','9b5cc392043d84a428b2dbace0a73be8118ed7aca5f1008adda5fdd89658505c','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261016210906_contact_address_geocoding.sql; SHA256 a1fab893f7daf5d22fe028c73b69214fa099d0852281e0687f93967b33cb5c84
-- Contact addresses -> exact GPS -> matching, unstarted TMS deliveries.
-- Async networking never waits inside a contact save. Enable separately after QA.
alter table public.suppliers add column if not exists lat double precision,add column if not exists lng double precision;
alter table public.crm_leads add column if not exists lat double precision,add column if not exists lng double precision;
create table private.contact_geocode_settings(
 id boolean primary key default true check(id),enabled boolean not null default false,
 last_request_at timestamptz,request_day date,requests_today integer not null default 0,
 daily_limit integer not null default 200 check(daily_limit between 1 and 1000)
);
insert into private.contact_geocode_settings(id) values(true);
create table private.contact_geocode_cache(
 address_key text primary key,lat double precision not null,lng double precision not null,
 source text not null,conflicted boolean not null default false,updated_at timestamptz not null default now(),
 check(lat between -85 and 85 and lng between -180 and 180)
);
create table private.contact_geocode_jobs(
 kind text not null check(kind in ('customers','suppliers','crm_leads','customer_addresses')),
 entity_id uuid not null,address_key text not null,address_data jsonb not null,
 state text not null check(state in ('queued','running','located','needs_review','not_found','failed','cancelled')),
 reason text,attempts integer not null default 0,request_id bigint,requested_at timestamptz,
 available_at timestamptz not null default now(),candidates jsonb not null default '[]',
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 primary key(kind,entity_id),check(octet_length(address_data::text)<=5000 and octet_length(candidates::text)<=16000)
);
create index contact_geocode_jobs_pending on private.contact_geocode_jobs(available_at,created_at) where state='queued';
create index contact_geocode_jobs_running on private.contact_geocode_jobs(request_id) where state='running';
do $$declare t text;begin foreach t in array array['contact_geocode_settings','contact_geocode_cache','contact_geocode_jobs'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
end loop;end $$;

create function private.contact_address_norm(p_text text) returns text language sql immutable set search_path='' as $$
 select btrim(regexp_replace(regexp_replace(
  regexp_replace(translate(lower(coalesce(p_text,'')),'áàäâéèëêíìïîóòöôúùüûñç','aaaaeeeeiiiioooouuuunc'),'[^a-z0-9 -]+',' ','g'),
  '(^| )(av|avda)( |$)','\1avenida\3','g'),' +',' ','g'))
$$;
create function private.contact_country_code(p_country text) returns text language sql immutable set search_path='' as $$
 select case private.contact_address_norm(p_country)
  when '' then 'EC' when 'ecuador' then 'EC' when 'ecudor' then 'EC' when 'equateur' then 'EC'
  when 'belgique' then 'BE' when 'belgica' then 'BE' when 'belgium' then 'BE'
  when 'france' then 'FR' when 'francia' then 'FR' when 'espagne' then 'ES' when 'espana' then 'ES' when 'spain' then 'ES'
  when 'united states' then 'US' when 'estados unidos' then 'US' when 'etats unis' then 'US'
  else case when btrim(p_country)~* '^[a-z]{2}$' then upper(btrim(p_country)) end end
$$;
create function private.contact_address_key(p_data jsonb) returns text language sql immutable set search_path='' as $$
 select md5(jsonb_build_array(private.contact_address_norm(p_data->>'address'),private.contact_address_norm(p_data->>'city'),
  private.contact_address_norm(p_data->>'province'),private.contact_address_norm(p_data->>'postal_code'),
  coalesce(private.contact_country_code(p_data->>'country'),private.contact_address_norm(p_data->>'country')))::text)
$$;
create function private.contact_address_matches(p_address text,p_data jsonb) returns boolean language sql immutable set search_path='' as $$
 select private.contact_address_norm(p_address)<>'' and private.contact_address_norm(p_data->>'address')<>''
 and private.contact_address_norm(p_address)=any(array[
  private.contact_address_norm(p_data->>'address'),
  private.contact_address_norm(concat_ws(', ',nullif(p_data->>'address',''),nullif(p_data->>'city',''))),
  private.contact_address_norm(concat_ws(', ',nullif(p_data->>'address',''),nullif(p_data->>'city',''),nullif(p_data->>'country',''))),
  private.contact_address_norm(concat_ws(', ',nullif(p_data->>'address',''),nullif(p_data->>'city',''),nullif(p_data->>'province',''))),
  private.contact_address_norm(concat_ws(', ',nullif(p_data->>'address',''),nullif(p_data->>'city',''),nullif(p_data->>'province',''),nullif(p_data->>'postal_code',''),nullif(p_data->>'country','')))])
$$;
create function private.contact_geocode_snapshot(p_kind text,p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$declare row jsonb;begin
 if p_kind not in ('customers','suppliers','crm_leads','customer_addresses') or to_regclass('public.'||p_kind) is null then return null;end if;
 execute format('select to_jsonb(x) from public.%I x where id=$1',p_kind) into row using p_id;
 if row is null then return null;end if;
 -- Only address fields enter the queue or the provider request. No names,
 -- email, phone, tax identity, document, user or financial data is sent.
 return jsonb_build_object('id',row->'id','address',row->'address','city',row->'city','province',row->'province',
  'postal_code',row->'postal_code','country',row->'country','lat',row->'lat','lng',row->'lng','active',row->'active',
  'customer_id',case when p_kind='customers' then row->'id' else row->'customer_id' end,'purpose',row->'purpose');
end $$;

create function private.contact_gps_for_delivery(p_customer uuid,p_address text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare points jsonb;sites jsonb:='[]';begin
 select coalesce(jsonb_agg(jsonb_build_object('lat',c.lat,'lng',c.lng)),'[]') into points from public.customers c
 where c.id=p_customer and c.active and c.lat is not null and c.lng is not null
  and private.contact_address_matches(p_address,to_jsonb(c));
 if exists(select 1 from information_schema.columns where table_schema='public' and table_name='customer_addresses' and column_name='lat') then
  execute $query$select coalesce(jsonb_agg(jsonb_build_object('lat',a.lat,'lng',a.lng)),'[]') from public.customer_addresses a
   join public.customers c on c.id=a.customer_id and c.active
   where a.customer_id=$1 and a.active and a.purpose='delivery' and a.lat is not null and a.lng is not null
    and private.contact_address_matches($2,to_jsonb(a))$query$
   into sites using p_customer,p_address;
 end if;
 points:=points||sites;
 if jsonb_array_length(points)>0 and (select count(distinct x) from jsonb_array_elements(points)x)=1 then return points->0;end if;
 return null;
end $$;

create or replace function private.tms_customer_gps() returns trigger language plpgsql security definer set search_path='' as $$
declare point jsonb;begin
 if tg_op='UPDATE' and (new.address is distinct from old.address or new.customer_id is distinct from old.customer_id)
  and new.lat is not distinct from old.lat and new.lng is not distinct from old.lng then new.lat:=null;new.lng:=null;end if;
 if new.customer_id is not null and new.lat is null and new.lng is null then
  point:=private.contact_gps_for_delivery(new.customer_id,new.address);
  new.lat:=(point->>'lat')::double precision;new.lng:=(point->>'lng')::double precision;
 end if;return new;
end $$;

create function private.contact_gps_propagate(p_customer uuid) returns integer
language plpgsql security definer set search_path='' as $$declare changed integer;begin
 if p_customer is null then return 0;end if;
 -- Coordinates may be added to a matching open destination, never to a
 -- different site or an already departed/loaded/closed/historic delivery.
 with eligible as (select d.id from public.tms_deliveries d
 where d.customer_id=p_customer and d.lat is null and d.lng is null
  and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción')
  and not exists(select 1 from public.sales_deliveries s where s.tms_delivery_id=d.id and s.departed_at is not null)
  and not exists(select 1 from public.tms_routes r where r.id=d.route_id and r.status in ('En ruta','En tránsito','Terminada','Cancelada'))
  and private.contact_gps_for_delivery(d.customer_id,d.address) is not null for update of d skip locked)
 update public.tms_deliveries d set lat=(private.contact_gps_for_delivery(d.customer_id,d.address)->>'lat')::double precision,
  lng=(private.contact_gps_for_delivery(d.customer_id,d.address)->>'lng')::double precision
 from eligible e where d.id=e.id;
 get diagnostics changed=row_count;return changed;
end $$;

create function private.contact_geocode_apply(p_kind text,p_id uuid,p_key text,p_lat double precision,p_lng double precision) returns boolean
language plpgsql security definer set search_path='' as $$declare current_data jsonb;begin
 if p_lat is null or p_lng is null or not(p_lat between -85 and 85 and p_lng between -180 and 180) then return false;end if;
 if p_kind not in ('customers','suppliers','crm_leads','customer_addresses') then return false;end if;
 execute format('select id from public.%I where id=$1 for update',p_kind) using p_id;
 current_data:=private.contact_geocode_snapshot(p_kind,p_id);
 if current_data is null or not coalesce((current_data->>'active')::boolean,false)
  or private.contact_address_key(current_data)<>p_key or nullif(current_data->>'lat','') is not null or nullif(current_data->>'lng','') is not null then return false;end if;
 execute format('update public.%I set lat=$1,lng=$2 where id=$3',p_kind) using p_lat,p_lng,p_id;
 return true;
end $$;

create function private.contact_geocode_dispatch() returns bigint
language plpgsql security definer set search_path='' as $$
declare settings private.contact_geocode_settings;job private.contact_geocode_jobs;request bigint;code text;begin
 if not pg_try_advisory_xact_lock(hashtextextended('coco-contact-geocoding',0)) then return null;end if;
 select * into settings from private.contact_geocode_settings where id;
 if not settings.enabled or settings.last_request_at>clock_timestamp()-interval '2 seconds'
  or (settings.request_day=current_date and settings.requests_today>=settings.daily_limit)
  or exists(select 1 from private.contact_geocode_jobs where state='running') then return null;end if;
 select * into job from private.contact_geocode_jobs where state='queued' and available_at<=now()
  order by available_at,created_at,kind,entity_id limit 1 for update skip locked;
 if not found then return null;end if;
 code:=private.contact_country_code(job.address_data->>'country');
 begin
 request:=net.http_get(url:='https://photon.komoot.io/api/',
  params:=jsonb_build_object('q',concat_ws(', ',job.address_data->>'address',nullif(job.address_data->>'city',''),
   nullif(job.address_data->>'province',''),nullif(job.address_data->>'postal_code','')),'countrycode',code,'limit',5,'lang','es','dedupe',0),
  headers:=jsonb_build_object('User-Agent','CocoERP/1.0 (https://lisciandraj.github.io/Pro-manager-Gama/)','Accept','application/json'),timeout_milliseconds:=8000);
 exception when others then
  update private.contact_geocode_jobs set reason='GEOCODER_QUEUE_UNAVAILABLE',available_at=now()+interval '5 minutes',updated_at=now()
   where kind=job.kind and entity_id=job.entity_id;
  return null;
 end;
 update private.contact_geocode_jobs set state='running',attempts=attempts+1,request_id=request,requested_at=now(),updated_at=now()
  where kind=job.kind and entity_id=job.entity_id;
 update private.contact_geocode_settings set last_request_at=clock_timestamp(),request_day=current_date,
  requests_today=case when request_day=current_date then requests_today+1 else 1 end where id;
 return request;
end $$;

create function private.contact_geocode_enqueue(p_kind text,p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare data jsonb;key text;cache private.contact_geocode_cache;status text:='queued';why text;begin
 data:=private.contact_geocode_snapshot(p_kind,p_id);if data is null then return;end if;
 key:=private.contact_address_key(data);
 if not coalesce((data->>'active')::boolean,false) then status:='cancelled';why:='INACTIVE_CONTACT';
 elsif nullif(data->>'lat','') is not null and nullif(data->>'lng','') is not null then
  status:='located';why:='EXISTING_COORDINATES';
  insert into private.contact_geocode_cache(address_key,lat,lng,source)
   values(key,(data->>'lat')::double precision,(data->>'lng')::double precision,'contact_gps')
   on conflict(address_key) do update set conflicted=contact_geocode_cache.conflicted
    or abs(contact_geocode_cache.lat-excluded.lat)>.0002 or abs(contact_geocode_cache.lng-excluded.lng)>.0002,updated_at=now();
 elsif length(btrim(coalesce(data->>'address','')))<4 or (nullif(btrim(data->>'city'),'') is null and nullif(btrim(data->>'postal_code'),'') is null) then
  status:='needs_review';why:='ADDRESS_INCOMPLETE';
 elsif private.contact_country_code(data->>'country') is null then status:='needs_review';why:='COUNTRY_REQUIRED';
 end if;
 insert into private.contact_geocode_jobs(kind,entity_id,address_key,address_data,state,reason)
  values(p_kind,p_id,key,data,status,why)
  on conflict(kind,entity_id) do update set address_key=excluded.address_key,address_data=excluded.address_data,
   state=excluded.state,reason=excluded.reason,attempts=0,request_id=null,requested_at=null,available_at=now(),candidates='[]',updated_at=now()
  where contact_geocode_jobs.address_key is distinct from excluded.address_key or excluded.state in ('located','cancelled')
   or (contact_geocode_jobs.state='cancelled' and excluded.state='queued');
 if status='queued' then
  select * into cache from private.contact_geocode_cache where address_key=key and not conflicted;
  if found then perform private.contact_geocode_apply(p_kind,p_id,key,cache.lat,cache.lng);end if;
 end if;
 if nullif(data->>'lat','') is not null and nullif(data->>'lng','') is not null then
  perform private.contact_gps_propagate(nullif(data->>'customer_id','')::uuid);
 end if;
 perform private.contact_geocode_dispatch();
end $$;

create function private.contact_geocode_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='UPDATE' and private.contact_address_key(to_jsonb(new)) is distinct from private.contact_address_key(to_jsonb(old))
  and new.lat is not distinct from old.lat and new.lng is not distinct from old.lng then new.lat:=null;new.lng:=null;end if;
 if tg_table_name='customers' then new.gps_address:=case when new.lat is not null and new.lng is not null then new.address end;end if;
 return new;
end $$;
create function private.contact_geocode_changed() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform private.contact_geocode_enqueue(tg_table_name,new.id);return null;
exception when others then raise warning 'CONTACT_GEOCODING_PENDING';return null;
end $$;

-- A point is automatic only when street, house number, locality, country and
-- geometry all match. A street/city centroid or multiple precise matches is review-only.
create function private.contact_geocode_candidate(p_data jsonb,p_feature jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare properties jsonb:=p_feature->'properties';coords jsonb:=p_feature->'geometry'->'coordinates';
 street text:=private.contact_address_norm(properties->>'street');house text:=private.contact_address_norm(properties->>'housenumber');
 address text:=private.contact_address_norm(p_data->>'address');city text:=private.contact_address_norm(p_data->>'city');
 rest text;lat double precision;lng double precision;begin
 if p_feature->'geometry'->>'type' is distinct from 'Point' or jsonb_typeof(coords) is distinct from 'array' or jsonb_array_length(coords)<>2
  or jsonb_typeof(coords->0) is distinct from 'number' or jsonb_typeof(coords->1) is distinct from 'number' then return null;end if;
 lat:=(coords->>1)::double precision;lng:=(coords->>0)::double precision;
 if lat is null or lng is null or not(lat between -85 and 85 and lng between -180 and 180)
  or upper(properties->>'countrycode') is distinct from private.contact_country_code(p_data->>'country') then return null;end if;
 if private.contact_country_code(p_data->>'country')='EC' and not(lat between -6 and 2 and lng between -93 and -75) then return null;end if;
 if street='' or house='' or house !~ '[0-9]' or position(' '||street||' ' in ' '||address||' ')=0 then return null;end if;
 rest:=replace(' '||address||' ',' '||street||' ',' ');
 if position(' '||house||' ' in rest)=0 then return null;end if;
 if city<>'' and position(' '||city||' ' in ' '||private.contact_address_norm(concat_ws(' ',properties->>'city',properties->>'locality',properties->>'county'))||' ')=0 then return null;end if;
 if city='' and private.contact_address_norm(p_data->>'postal_code')<>private.contact_address_norm(properties->>'postcode') then return null;end if;
 return jsonb_build_object('lat',lat,'lng',lng,'label',left(concat_ws(', ',properties->>'name',properties->>'street',properties->>'housenumber',properties->>'city',properties->>'country'),600));
exception when others then return null;
end $$;

create function private.contact_geocode_tick() returns jsonb language plpgsql security definer set search_path='' as $$
declare job private.contact_geocode_jobs;response record;body jsonb;matches jsonb;point jsonb;data jsonb;
 handled integer:=0;request bigint;failure boolean;customer record;begin
 if not pg_try_advisory_xact_lock(hashtextextended('coco-contact-geocoding',0)) then return jsonb_build_object('busy',true);end if;
 if not (select enabled from private.contact_geocode_settings where id) then return jsonb_build_object('enabled',false);end if;
 -- Lock contacts before job rows, matching the contact edit triggers. A stale
 -- response can never cancel a replacement job created by an address edit.
 for job in select * from private.contact_geocode_jobs where state='running' order by requested_at limit 10 loop
  select status_code,content,timed_out,error_msg into response from net._http_response where id=job.request_id;
  if not found and job.requested_at>now()-interval '2 minutes' then continue;end if;
  failure:=not found or coalesce(response.timed_out,false) or response.error_msg is not null
   or response.status_code is distinct from 200 or octet_length(coalesce(response.content,''))>64000;
  data:=private.contact_geocode_snapshot(job.kind,job.entity_id);
  if data is null or not coalesce((data->>'active')::boolean,false) or private.contact_address_key(data)<>job.address_key
   or nullif(data->>'lat','') is not null or nullif(data->>'lng','') is not null then
   update private.contact_geocode_jobs set state='cancelled',reason='CONTACT_CHANGED',updated_at=now()
    where kind=job.kind and entity_id=job.entity_id and address_key=job.address_key and request_id=job.request_id and state='running';continue;
  end if;
  begin
   if not failure then
    body:=response.content::jsonb;
    failure:=body->>'type' is distinct from 'FeatureCollection' or jsonb_typeof(body->'features') is distinct from 'array';
    if not failure then failure:=jsonb_array_length(body->'features')>5;end if;
   end if;
  exception when others then failure:=true;end;
  if failure then
   update private.contact_geocode_jobs set state=case when attempts<3 then 'queued' else 'failed' end,reason='GEOCODER_UNAVAILABLE',
    request_id=null,available_at=now()+make_interval(mins=>least(60,5*attempts)),updated_at=now()
    where kind=job.kind and entity_id=job.entity_id and address_key=job.address_key and request_id=job.request_id and state='running';continue;
  end if;
  select coalesce(jsonb_agg(x),'[]') into matches from (
   select private.contact_geocode_candidate(job.address_data,f) x from jsonb_array_elements(body->'features')f
  )valid where x is not null;
  if jsonb_array_length(matches)>0 and (select count(distinct (round((x->>'lat')::numeric,5),round((x->>'lng')::numeric,5))) from jsonb_array_elements(matches)x)=1 then
   point:=matches->0;
   if private.contact_geocode_apply(job.kind,job.entity_id,job.address_key,(point->>'lat')::double precision,(point->>'lng')::double precision) then
    update private.contact_geocode_jobs set state='located',reason='GEOCODED',candidates=matches,updated_at=now() where kind=job.kind and entity_id=job.entity_id and address_key=job.address_key;
    update private.contact_geocode_cache set source='Photon / OpenStreetMap contributors' where address_key=job.address_key;
   end if;
  else
   update private.contact_geocode_jobs set state=case when jsonb_array_length(body->'features')=0 then 'not_found' else 'needs_review' end,
    reason=case when jsonb_array_length(matches)>1 then 'AMBIGUOUS_ADDRESS' else 'EXACT_ADDRESS_REQUIRED' end,candidates=matches,updated_at=now()
    where kind=job.kind and entity_id=job.entity_id and address_key=job.address_key and request_id=job.request_id and state='running';
  end if;
  handled:=handled+1;
 end loop;
 -- Retry nonblocking GPS propagation if an open delivery was being edited
 -- when its contact was saved. Planning itself remains a separate operation.
 for customer in select distinct d.customer_id from public.tms_deliveries d
  where d.lat is null and d.lng is null and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción')
   and private.contact_gps_for_delivery(d.customer_id,d.address) is not null limit 100 loop
  perform private.contact_gps_propagate(customer.customer_id);
 end loop;
 request:=private.contact_geocode_dispatch();return jsonb_build_object('handled',handled,'request_id',request);
end $$;

do $$declare kind text;begin foreach kind in array array['customers','suppliers','crm_leads','customer_addresses'] loop
 if exists(select 1 from information_schema.columns where table_schema='public' and table_name=kind and column_name='lat') then
  execute format('create trigger zz_contact_geocode_guard before insert or update of address,city,province,postal_code,country,lat,lng on public.%I for each row execute function private.contact_geocode_guard()',kind);
  execute format('create trigger contact_geocode_changed after insert or update of address,city,province,postal_code,country,lat,lng,active on public.%I for each row execute function private.contact_geocode_changed()',kind);
 end if;
end loop;end $$;
do $$declare f record;begin for f in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and (p.proname like 'contact_geocode_%' or p.proname like 'contact_address_%' or p.proname in ('contact_country_code','contact_gps_for_delivery','contact_gps_propagate')) loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f.fn);
end loop;end $$;
select cron.schedule('coco-contact-geocoding','* * * * *',$cron$select private.contact_geocode_tick();$cron$);

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261016210906','contact_address_geocoding','a1fab893f7daf5d22fe028c73b69214fa099d0852281e0687f93967b33cb5c84','a1fab893f7daf5d22fe028c73b69214fa099d0852281e0687f93967b33cb5c84','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261016212234_photon_default_language.sql; SHA256 e5d9a2931cfa83bade2105a1d8e4c41b0e151d5ce475b3761acaf2b372ae6367
-- The public Photon instance supports only default/de/en/fr. Omit lang to use
-- the native address language, including Spanish streets in Ecuador.
create or replace function private.contact_geocode_dispatch() returns bigint
language plpgsql security definer set search_path='' as $$
declare settings private.contact_geocode_settings;job private.contact_geocode_jobs;request bigint;code text;begin
 if not pg_try_advisory_xact_lock(hashtextextended('coco-contact-geocoding',0)) then return null;end if;
 select * into settings from private.contact_geocode_settings where id;
 if not settings.enabled or settings.last_request_at>clock_timestamp()-interval '2 seconds'
  or (settings.request_day=current_date and settings.requests_today>=settings.daily_limit)
  or exists(select 1 from private.contact_geocode_jobs where state='running') then return null;end if;
 select * into job from private.contact_geocode_jobs where state='queued' and available_at<=now()
  order by available_at,created_at,kind,entity_id limit 1 for update skip locked;
 if not found then return null;end if;
 code:=private.contact_country_code(job.address_data->>'country');
 begin
 request:=net.http_get(url:='https://photon.komoot.io/api/',
  params:=jsonb_build_object('q',concat_ws(', ',job.address_data->>'address',nullif(job.address_data->>'city',''),
   nullif(job.address_data->>'province',''),nullif(job.address_data->>'postal_code','')),'countrycode',code,'limit',5,'dedupe',0),
  headers:=jsonb_build_object('User-Agent','CocoERP/1.0 (https://lisciandraj.github.io/Pro-manager-Gama/)','Accept','application/json'),timeout_milliseconds:=8000);
 exception when others then
  update private.contact_geocode_jobs set reason='GEOCODER_QUEUE_UNAVAILABLE',available_at=now()+interval '5 minutes',updated_at=now()
   where kind=job.kind and entity_id=job.entity_id;
  return null;
 end;
 update private.contact_geocode_jobs set state='running',attempts=attempts+1,request_id=request,requested_at=now(),updated_at=now()
  where kind=job.kind and entity_id=job.entity_id;
 update private.contact_geocode_settings set last_request_at=clock_timestamp(),request_day=current_date,
  requests_today=case when request_day=current_date then requests_today+1 else 1 end where id;
 return request;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261016212234','photon_default_language','e5d9a2931cfa83bade2105a1d8e4c41b0e151d5ce475b3761acaf2b372ae6367','e5d9a2931cfa83bade2105a1d8e4c41b0e151d5ce475b3761acaf2b372ae6367','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261017093147_order_followup_mail.sql; SHA256 9e852a72023266170c0f2ac1431c41998b39cb9136198f54c4b3b6e5aa26ec0f
-- Additive order chatter. Mail credentials never enter an exposed table.
create table private.coco_mail_accounts(
 user_id uuid primary key references public.profiles(id) on delete cascade,
 provider text not null check(provider in ('google','microsoft')), email text not null,
 credentials text not null, connected_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table private.coco_mail_oauth(
 state_hash text primary key, user_id uuid not null references public.profiles(id) on delete cascade,
 provider text not null check(provider in ('google','microsoft')), verifier text not null,
 expires_at timestamptz not null default now()+interval '10 minutes'
);
create index coco_mail_oauth_expiry on private.coco_mail_oauth(expires_at);
create table private.coco_order_entries(
 id uuid primary key default gen_random_uuid(), kind text not null check(kind in ('sales','purchase')),
 order_id uuid not null, type text not null check(type in ('note','mail','action')),
 actor_id uuid references public.profiles(id) on delete set null, actor_name text not null,
 created_at timestamptz not null default now(), subject text not null default '', body text not null default '',
 direction text check(direction in ('in','out')), status text not null default 'recorded',
 from_email text, to_email text, request_key uuid,
 mail_owner uuid references public.profiles(id) on delete set null,
 provider text, provider_id text, thread_id text, internet_id text, reply_id uuid references private.coco_order_entries(id),
 attachments jsonb not null default '[]', detail jsonb not null default '{}',
 unique(actor_id,request_key), unique(mail_owner,provider,provider_id),
 check(length(subject)<=300 and length(body)<=100000 and jsonb_typeof(attachments)='array' and octet_length(attachments::text)<=20000),
 check(status in ('recorded','sending','sent','accepted','received','failed','uncertain'))
);
create index coco_order_entries_page on private.coco_order_entries(kind,order_id,created_at desc,id);
create index coco_order_entries_thread on private.coco_order_entries(mail_owner,kind,order_id,thread_id) where thread_id is not null;
create index coco_order_entries_actor on private.coco_order_entries(actor_id);
create index coco_order_entries_reply on private.coco_order_entries(reply_id);
alter table private.coco_mail_accounts enable row level security;
alter table private.coco_mail_oauth enable row level security;
alter table private.coco_order_entries enable row level security;
revoke all on private.coco_mail_accounts,private.coco_mail_oauth,private.coco_order_entries from public,anon,authenticated;

-- Reuse the existing redacted history and its financial-stage filtering. Only
-- its entry permission changes: the owning order module suffices here.
do $$declare source text;begin
 source:=pg_get_functiondef('private.gama_process_history(text,integer,integer)'::regprocedure);
 source:=replace(source,'private.gama_process_history(', 'private.coco_order_process_history(');
 if strpos(source,'model:=private.gama_processes(''state'',jsonb_build_object(''key'',p_key));')=0 then raise exception 'HISTORY_CONTRACT_CHANGED';end if;
 source:=replace(source, 'model:=private.gama_processes(''state'',jsonb_build_object(''key'',p_key));',
 'if k not in (''o'',''p'') or not private.erp_module_allowed(case when k=''o'' then ''sales-orders'' else ''gamaPurchasesV14'' end,array[''administrador'',''comercial'',''almacenero'']) then raise exception ''ROLE_NOT_ALLOWED'';end if; model:=private.gama_process_state(p_key);');
 if strpos(source,'private.gama_processes(''state''')>0 then raise exception 'HISTORY_CONTRACT_CHANGED';end if;
 execute source;
end $$;
revoke all on function private.coco_order_process_history(text,integer,integer) from public,anon,authenticated;

create function private.coco_order_context(p_kind text,p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare mod text; o jsonb; party text; recipient text; me text; comm boolean;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if p_kind not in ('sales','purchase') then raise exception 'INVALID_ORDER_KIND';end if;
 mod:=case when p_kind='sales' then 'sales-orders' else 'gamaPurchasesV14' end;
 if not private.erp_module_allowed(mod,array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 comm:=private.erp_module_allowed(mod,array['administrador','comercial']);
 if p_kind='sales' then
  select jsonb_build_object('id',s.id,'number',s.number,'status',s.status),s.customer_name,c.email into o,party,recipient from public.sales_orders s left join public.customers c on c.id=s.customer_id where s.id=p_id;
 else
  select jsonb_build_object('id',s.id,'number',s.order_number,'status',s.status),c.name,c.email into o,party,recipient from public.purchase_orders s left join public.suppliers c on c.id=s.supplier_id where s.id=p_id;
 end if;
 if o is null then raise exception 'ORDER_NOT_FOUND';end if;
 select email into me from auth.users where id=auth.uid();
 return o||jsonb_build_object('kind',p_kind,'party',party,'email',case when comm then recipient end,'actor_id',auth.uid(),'account_email',me,
 'can_mail',comm and private.erp_action_allowed(mod,'edit'),'can_note',private.erp_action_allowed(mod,'edit'),'commercial',comm,
 'mailbox',(select jsonb_build_object('provider',provider,'email',email,'connected_at',connected_at) from private.coco_mail_accounts where user_id=auth.uid() and lower(email)=lower(me)));
end $$;
revoke all on function private.coco_order_context(text,uuid) from public,anon,authenticated;

create function private.coco_order_followup(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare k text:=p_data->>'kind'; oid uuid:=(p_data->>'order_id')::uuid; ctx jsonb; items jsonb; history jsonb; off integer:=coalesce((p_data->>'offset')::integer,0); entry private.coco_order_entries; old private.coco_order_entries; key uuid; author text;
begin
 ctx:=private.coco_order_context(k,oid);
 if p_action='context' then return ctx;end if;
 if p_action='list' then
  if off<0 or off>1000000 then raise exception 'INVALID_OFFSET';end if;
  history:=private.coco_order_process_history((case when k='sales' then 'o:' else 'p:' end)||oid::text,0,off);
  select coalesce(jsonb_agg(x.data order by x.created_at desc,x.id),'[]') into items from (
   select e.created_at,e.id,(to_jsonb(e)-'mail_owner'-'provider_id'-'thread_id'-'internet_id'-'request_key'-'actor_id'-'detail')||
    jsonb_build_object('own_mailbox',e.mail_owner=auth.uid()) as data
   from private.coco_order_entries e where e.kind=k and e.order_id=oid
    and (e.type<>'mail' or (ctx->>'commercial')::boolean)
   order by e.created_at desc,e.id offset off limit 51
  ) x;
  return jsonb_build_object('context',ctx,'entries',items,'history',history->'items');
 end if;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
 if p_action='purchase_mail_sent' then
  if k<>'purchase' or not (ctx->>'can_mail')::boolean then raise exception 'ROLE_NOT_ALLOWED';end if;
  select * into entry from private.coco_order_entries where id=(p_data->>'message_id')::uuid and kind=k and order_id=oid and mail_owner=auth.uid() and direction='out' and status in ('sent','accepted');
  if entry.id is null then raise exception 'MESSAGE_NOT_SENT';end if;
  -- A concurrent receipt/cancellation must never be overwritten after a slow send.
  update public.purchase_orders set status='sent',updated_at=now() where id=oid and status='draft';
  return private.coco_order_context(k,oid);
 elsif p_action='purchase_manual_sent' then
  if k<>'purchase' or not (ctx->>'can_mail')::boolean then raise exception 'ROLE_NOT_ALLOWED';end if;
  if length(btrim(coalesce(p_data->>'body',''))) not between 3 and 1000 then raise exception 'INVALID_MESSAGE';end if;
  key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform 1 from public.purchase_orders where id=oid for update;
  select * into entry from private.coco_order_entries where actor_id=auth.uid() and request_key=key;
  if entry.id is not null then
   if entry.kind<>k or entry.order_id<>oid or entry.subject<>'purchase_manual_sent' or entry.body<>btrim(p_data->>'body') then raise exception 'REQUEST_KEY_REUSED';end if;
   return jsonb_build_object('id',entry.id);
  end if;
  update public.purchase_orders set status='sent',updated_at=now() where id=oid and status='draft';
  if not found then raise exception 'ORDER_STATE_CHANGED';end if;
  insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,subject,body,request_key)
   values(k,oid,'action',auth.uid(),author,'purchase_manual_sent',btrim(p_data->>'body'),key) returning * into entry;
  return jsonb_build_object('id',entry.id);
 elsif p_action='note' then
  if not (ctx->>'can_note')::boolean then raise exception 'ROLE_NOT_ALLOWED';end if;
  if length(btrim(coalesce(p_data->>'body',''))) not between 1 and 10000 then raise exception 'INVALID_MESSAGE';end if;
  key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,body,request_key)
   values(k,oid,'note',auth.uid(),author,btrim(p_data->>'body'),key) on conflict(actor_id,request_key) do nothing returning * into entry;
  if entry.id is null then select * into entry from private.coco_order_entries where actor_id=auth.uid() and request_key=key;end if;
  if entry.kind<>k or entry.order_id<>oid or entry.body<>btrim(p_data->>'body') or entry.type<>'note' then raise exception 'REQUEST_KEY_REUSED';end if;
  return jsonb_build_object('id',entry.id);
 elsif p_action='mail_claim' then
  if not (ctx->>'can_mail')::boolean or ctx->'mailbox'='null'::jsonb then raise exception 'MAILBOX_REQUIRED';end if;
  if length(btrim(coalesce(p_data->>'subject',''))) not between 1 and 300 or (p_data->>'subject')~E'[\r\n]' or length(btrim(coalesce(p_data->>'body',''))) not between 1 and 50000
   or coalesce(p_data->>'to','')!~'^[^\s@<>;,]+@[^\s@<>;,]+\.[^\s@<>;,]+$' or length(p_data->>'to')>254 then raise exception 'INVALID_MESSAGE';end if;
  key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  if p_data->>'reply_id' is not null then
   select * into old from private.coco_order_entries where id=(p_data->>'reply_id')::uuid and kind=k and order_id=oid and mail_owner=auth.uid() and type='mail' and thread_id is not null and provider=ctx->'mailbox'->>'provider';
   if old.id is null then raise exception 'REPLY_NOT_ALLOWED';end if;
  end if;
  insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,subject,body,direction,status,from_email,to_email,request_key,mail_owner,provider,reply_id,attachments)
   values(k,oid,'mail',auth.uid(),author,btrim(p_data->>'subject'),p_data->>'body','out','sending',ctx->>'account_email',lower(btrim(p_data->>'to')),key,auth.uid(),ctx->'mailbox'->>'provider',old.id,coalesce(p_data->'attachments','[]'))
   on conflict(actor_id,request_key) do nothing returning * into entry;
  if entry.id is null then
   select * into entry from private.coco_order_entries where actor_id=auth.uid() and request_key=key;
   if entry.kind<>k or entry.order_id<>oid or entry.subject<>btrim(p_data->>'subject') or entry.body<>p_data->>'body' or entry.to_email<>lower(btrim(p_data->>'to')) or entry.reply_id is distinct from old.id or entry.type<>'mail' then raise exception 'REQUEST_KEY_REUSED';end if;
   return jsonb_build_object('claimed',false,'id',entry.id,'status',entry.status);
  end if;
  return jsonb_build_object('claimed',true,'id',entry.id,'status',entry.status);
 elsif p_action='disconnect' then
  delete from private.coco_mail_accounts where user_id=auth.uid();
  delete from private.coco_mail_oauth where user_id=auth.uid();return jsonb_build_object('disconnected',true);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.coco_order_followup(text,jsonb) from public,anon;
grant execute on function private.coco_order_followup(text,jsonb) to authenticated;
create function public.coco_order_followup(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.coco_order_followup(p_action,p_data)$$;
revoke all on function public.coco_order_followup(text,jsonb) from public,anon;
grant execute on function public.coco_order_followup(text,jsonb) to authenticated;

-- Only the authenticated Edge handler can call this service-role facade.
create function private.coco_order_mail_service(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=(p_data->>'user_id')::uuid; me text; entry private.coco_order_entries; account private.coco_mail_accounts; state private.coco_mail_oauth; result jsonb;
begin
 if p_action='oauth_take' then
  delete from private.coco_mail_oauth where state_hash=p_data->>'state_hash' and expires_at>now() returning * into state;
  if state.user_id is null then raise exception 'OAUTH_EXPIRED';end if;uid:=state.user_id;
 end if;
 select u.email into me from auth.users u join public.profiles p on p.id=u.id where u.id=uid and p.active and p.role in ('administrador','comercial') and (u.banned_until is null or u.banned_until<now());
 if me is null then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='oauth_take' then return to_jsonb(state)||jsonb_build_object('email',me);end if;
 if p_action='oauth_store' then
  delete from private.coco_mail_oauth where user_id=uid or expires_at<now();
  insert into private.coco_mail_oauth(state_hash,user_id,provider,verifier) values(p_data->>'state_hash',uid,p_data->>'provider',p_data->>'verifier');return '{}';
 elsif p_action='account_save' then
  if lower(p_data->>'email') is distinct from lower(me) then raise exception 'MAILBOX_EMAIL_MISMATCH';end if;
  insert into private.coco_mail_accounts(user_id,provider,email,credentials) values(uid,p_data->>'provider',lower(me),p_data->>'credentials')
  on conflict(user_id) do update set provider=excluded.provider,email=excluded.email,credentials=excluded.credentials,updated_at=now();return '{}';
 elsif p_action='account' then
  select * into account from private.coco_mail_accounts where user_id=uid and lower(email)=lower(me);return to_jsonb(account);
 elsif p_action='message' then
  select * into entry from private.coco_order_entries where id=(p_data->>'id')::uuid and mail_owner=uid and type='mail';
  if entry.id is null then raise exception 'MESSAGE_NOT_FOUND';end if;
  return to_jsonb(entry)||jsonb_build_object('reply',(select to_jsonb(r) from private.coco_order_entries r where r.id=entry.reply_id and r.mail_owner=uid));
 elsif p_action='message_status' then
  select * into entry from private.coco_order_entries where id=(p_data->>'id')::uuid and mail_owner=uid and direction='out' for update;
  if entry.id is null then raise exception 'MESSAGE_NOT_FOUND';end if;
  if p_data->>'thread_id' is not null then
   perform pg_advisory_xact_lock(hashtextextended(uid::text||entry.provider||(p_data->>'thread_id'),0));
   if exists(select 1 from private.coco_order_entries e where e.mail_owner=uid and e.provider=entry.provider and e.thread_id=p_data->>'thread_id' and (e.kind<>entry.kind or e.order_id<>entry.order_id)) then raise exception 'THREAD_LINKED_ELSEWHERE';end if;
  end if;
  update private.coco_order_entries set status=coalesce(p_data->>'status',status),provider_id=coalesce(p_data->>'provider_id',provider_id),thread_id=coalesce(p_data->>'thread_id',thread_id),internet_id=coalesce(p_data->>'internet_id',internet_id)
   where id=(p_data->>'id')::uuid and mail_owner=uid and direction='out' returning * into entry;
  if entry.id is null then raise exception 'MESSAGE_NOT_FOUND';end if;
  return jsonb_build_object('id',entry.id,'status',entry.status);
 elsif p_action='pending' then
  select coalesce(jsonb_agg(t),'[]') into result from (select id,provider,internet_id from private.coco_order_entries where mail_owner=uid and kind=p_data->>'kind' and order_id=(p_data->>'order_id')::uuid and direction='out' and status in ('sending','uncertain') and thread_id is null and created_at<now()-interval '90 seconds' order by created_at limit 20) t;return result;
 elsif p_action='threads' then
  select coalesce(jsonb_agg(t),'[]') into result from (select thread_id,provider,max(created_at) at from private.coco_order_entries where mail_owner=uid and kind=p_data->>'kind' and order_id=(p_data->>'order_id')::uuid and thread_id is not null group by thread_id,provider order by max(created_at) desc limit 100) t;return result;
 elsif p_action='import' then
  -- The handler fetches only an already linked thread in this user's mailbox.
  if not exists(select 1 from private.coco_order_entries e where e.mail_owner=uid and e.kind=p_data->>'kind' and e.order_id=(p_data->>'order_id')::uuid and e.provider=p_data->>'provider' and e.thread_id=p_data->>'thread_id') then raise exception 'THREAD_NOT_LINKED';end if;
  if lower(p_data->>'from_email')=lower(me) then
   update private.coco_order_entries set status='sent',provider_id=coalesce(provider_id,p_data->>'provider_id'),internet_id=coalesce(internet_id,p_data->>'internet_id') where mail_owner=uid and provider=p_data->>'provider' and (provider_id=p_data->>'provider_id' or internet_id=p_data->>'internet_id') and direction='out';
  end if;
  insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,created_at,subject,body,direction,status,from_email,to_email,mail_owner,provider,provider_id,thread_id,internet_id,attachments)
   values(p_data->>'kind',(p_data->>'order_id')::uuid,'mail',case when lower(p_data->>'from_email')=lower(me) then uid end,
    case when lower(p_data->>'from_email')=lower(me) then (select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') from public.profiles where id=uid) else left(coalesce(p_data->>'sender',p_data->>'from_email',''),300) end,
    (p_data->>'created_at')::timestamptz,left(coalesce(p_data->>'subject',''),300),left(coalesce(p_data->>'body',''),100000),case when lower(p_data->>'from_email')=lower(me) then 'out' else 'in' end,
    case when lower(p_data->>'from_email')=lower(me) then 'sent' else 'received' end,p_data->>'from_email',p_data->>'to_email',uid,p_data->>'provider',p_data->>'provider_id',p_data->>'thread_id',p_data->>'internet_id',coalesce(p_data->'attachments','[]'))
   on conflict(mail_owner,provider,provider_id) do nothing returning to_jsonb(id) into result;
  return jsonb_build_object('imported',result is not null);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.coco_order_mail_service(text,jsonb) from public,anon,authenticated;
grant execute on function private.coco_order_mail_service(text,jsonb) to service_role;
create function public.coco_order_mail_service(p_action text,p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.coco_order_mail_service(p_action,p_data)$$;
revoke all on function public.coco_order_mail_service(text,jsonb) from public,anon,authenticated;
grant execute on function public.coco_order_mail_service(text,jsonb) to service_role;

-- Extra edits not already represented by status/receipt events are recorded at
-- the database boundary, including changes made outside the current browser.
create function private.coco_order_edit_event() returns trigger language plpgsql security definer set search_path='' as $$
declare n jsonb:=to_jsonb(new);o jsonb:=to_jsonb(old);fields jsonb;kind text:=tg_argv[0];oid uuid;author text;
begin
 select jsonb_agg(key order by key) into fields from jsonb_each(n) where key=any(array['notes','expected_date','supplier_reference','delivery_address','customer_id','supplier_id','quantity','unit_price','unit_cost','tax_rate']) and value is distinct from o->key;
 if fields is null then return new;end if;
 oid:=case when tg_table_name in ('sales_orders','purchase_orders') then new.id else coalesce(n->>'order_id',n->>'purchase_order_id')::uuid end;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
 insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,subject,body)
 values(kind,oid,'action',auth.uid(),coalesce(author,'AUTHOR_NOT_RECORDED'),'order_updated',fields::text);
 return new;
end $$;
revoke all on function private.coco_order_edit_event() from public,anon,authenticated;
create trigger coco_order_edit_event after update on public.sales_orders for each row execute function private.coco_order_edit_event('sales');
create trigger coco_order_edit_event after update on public.sales_order_lines for each row execute function private.coco_order_edit_event('sales');
create trigger coco_order_edit_event after update on public.purchase_orders for each row execute function private.coco_order_edit_event('purchase');
create trigger coco_order_edit_event after update on public.purchase_order_lines for each row execute function private.coco_order_edit_event('purchase');
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261017093147','order_followup_mail','9e852a72023266170c0f2ac1431c41998b39cb9136198f54c4b3b6e5aa26ec0f','9e852a72023266170c0f2ac1431c41998b39cb9136198f54c4b3b6e5aa26ec0f','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261017113550_dossier_chatgpt_followup.sql; SHA256 4d7e48db5f051d4a839e3c3d92147e5a393e0b169a0ba10c6aa662e886be6e9f
-- ChatGPT reads mail through its own connector. The ERP stores proposals, never
-- mailbox credentials. Existing notes, mail archives and business events survive.
alter table private.coco_order_entries drop constraint coco_order_entries_kind_check;
alter table private.coco_order_entries add constraint coco_order_entries_kind_check check(kind in ('sales','purchase','quote','tms'));
alter table private.coco_order_entries alter column order_id drop not null;
delete from private.coco_mail_oauth;
delete from private.coco_mail_accounts;
revoke all on function public.coco_order_mail_service(text,jsonb),private.coco_order_mail_service(text,jsonb) from public,anon,authenticated,service_role;

create table private.coco_mail_bridge_accounts(
 user_id uuid primary key references public.profiles(id),email text not null,
 enabled boolean not null default false,connected_at timestamptz not null default now(),last_received_at timestamptz,
 check(email=lower(btrim(email)))
);
create table private.coco_mail_proposals(
 id uuid primary key default gen_random_uuid(),mailbox_user uuid not null references public.profiles(id),
 message_id text not null,thread_id text,source_email text not null,source_subject text not null,
 received_at timestamptz not null,kind text not null check(kind in ('sales','purchase','tms')),
 target_kind text not null check(target_kind in ('sales','purchase','quote','tms')),target_id uuid,
 action text not null check(action in ('quote_draft','record_note')),summary text not null,payload jsonb not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(),decided_at timestamptz,decided_by uuid references public.profiles(id),
 result jsonb,review jsonb,reviewed_by uuid references public.profiles(id),reviewed_at timestamptz,review_hash text,
 entry_id uuid references private.coco_order_entries(id),unique(mailbox_user,message_id),
 check(length(message_id) between 1 and 300 and length(summary) between 1 and 10000 and octet_length(payload::text)<=60000)
);
create index coco_mail_proposals_pending on private.coco_mail_proposals(kind,status,created_at desc);
create index coco_mail_proposals_target on private.coco_mail_proposals(target_kind,target_id,created_at desc);
alter table private.coco_mail_bridge_accounts enable row level security;
alter table private.coco_mail_proposals enable row level security;
revoke all on private.coco_mail_bridge_accounts,private.coco_mail_proposals from public,anon,authenticated;

create function private.coco_dossier_context(p_kind text,p_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare mod text;doc jsonb;commercial boolean;can_edit boolean;me text;oid uuid;qid uuid;model jsonb;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if p_kind not in ('sales','purchase','quote','tms') or p_kind is null then raise exception 'INVALID_ORDER_KIND';end if;
 mod:=case p_kind when 'sales' then 'sales-orders' when 'quote' then 'quotes' when 'purchase' then 'gamaPurchasesV14' else 'tms' end;
 if p_kind='tms' then
  perform private.tms_require(p_id,false,'read');
  if p_id is null and private.tms_scope()='driver' then raise exception 'TMS_ACCESS_DENIED';end if;
  commercial:=private.tms_scope() in ('dispatcher','manager');
 else
  if not private.erp_module_allowed(mod,case when p_kind='quote' then array['administrador','comercial'] else array['administrador','comercial','almacenero'] end) and not
   (p_id is null and p_kind='sales' and private.erp_module_allowed('quotes',array['administrador','comercial'])) then raise exception 'ROLE_NOT_ALLOWED';end if;
  commercial:=private.erp_module_allowed(mod,array['administrador','comercial']) or p_id is null and p_kind='sales' and private.erp_module_allowed('quotes',array['administrador','comercial']);
 end if;
 can_edit:=private.erp_action_allowed(mod,'edit');
 if p_id is null then doc:=jsonb_build_object('number',case p_kind when 'sales' then 'Ventas' when 'quote' then 'Ventas' when 'purchase' then 'Compras' else 'TMS' end,'status','inbox','party','ChatGPT');
 elsif p_kind='sales' then
  select jsonb_build_object('number',number,'status',status,'party',customer_name),id,source_quote_id into doc,oid,qid from public.sales_orders where id=p_id;
 elsif p_kind='quote' then
  select jsonb_build_object('number',q.invoice_number,'status',coalesce(q.quote_state,'draft'),'party',c.name),q.id into doc,qid from public.invoices q left join public.customers c on c.id=q.customer_id where q.id=p_id;
  select id into oid from public.sales_orders where source_quote_id=qid;
 elsif p_kind='purchase' then
  select jsonb_build_object('number',o.order_number,'status',o.status,'party',s.name) into doc from public.purchase_orders o left join public.suppliers s on s.id=o.supplier_id where o.id=p_id;
 else
  select jsonb_build_object('number',coalesce(d.erp_reference,s.number),'status',d.status,'party',d.customer),s.order_id,o.source_quote_id into doc,oid,qid
   from public.tms_deliveries d left join public.sales_deliveries s on s.tms_delivery_id=d.id left join public.sales_orders o on o.id=s.order_id where d.id=p_id;
 end if;
 if doc is null then raise exception 'ORDER_NOT_FOUND';end if;
 if p_id is not null then
  if p_kind='purchase' then model:=private.gama_process_state('p:'||p_id);
  elsif oid is not null then model:=private.gama_process_state('o:'||oid);
  elsif qid is not null then model:=private.gama_process_state('q:'||qid);end if;
 end if;
 select email into me from auth.users where id=auth.uid();
 return doc||jsonb_build_object('kind',p_kind,'id',p_id,'actor_id',auth.uid(),'account_email',me,'can_note',can_edit,'commercial',commercial,
  'can_review',commercial and (can_edit or p_id is null and p_kind='sales' and private.erp_action_allowed('quotes','edit')) and (p_kind<>'tms' or private.tms_scope() in ('dispatcher','manager')),
  'sales_order_id',oid,'quote_id',qid,'stages',coalesce(model->'steps','[]'),
  'bridge',(select jsonb_build_object('enabled',a.enabled and lower(me)=a.email,'email',a.email,'last_received_at',a.last_received_at) from private.coco_mail_bridge_accounts a where a.user_id=auth.uid()));
end $$;
revoke all on function private.coco_dossier_context(text,uuid) from public,anon,authenticated;

-- Keep the established financial-stage redaction and add actor identifiers for
-- the scoped portrait projection. Quote views follow their eventual order.
do $$declare source text;begin
 source:=pg_get_functiondef('private.gama_process_history(text,integer,integer)'::regprocedure);
 source:=replace(source,'private.gama_process_history(', 'private.coco_dossier_process_history(');
 source:=replace(source,'model:=private.gama_processes(''state'',jsonb_build_object(''key'',p_key));',
  'perform private.coco_dossier_context(case k when ''o'' then ''sales'' when ''q'' then ''quote'' when ''p'' then ''purchase'' else ''invalid'' end,source); model:=private.gama_process_state(p_key);');
 source:=replace(source,'elsif k=''q'' then qid:=source;', 'elsif k=''q'' then qid:=source; select id,source_request_id into oid,rid from public.sales_orders where source_quote_id=qid; if rid is null then select id into rid from public.customer_requests where invoice_id=qid order by created_at,id limit 1;end if;');
 source:=replace(source,'''actor_name'',actor_name,', '''actor_name'',actor_name,''actor_id'',actor_id,');
 execute source;
end $$;
revoke all on function private.coco_dossier_process_history(text,integer,integer) from public,anon,authenticated;

create function private.coco_proposal_quote(p jsonb,p_key uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare c public.customers;product public.products;line jsonb;ls jsonb:='[]';price jsonb;qty numeric;stamp date:=(now() at time zone private.erp_timezone())::date;seller text;
begin
 perform private.sales_access('quote');
 if not private.erp_action_allowed('quotes','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into c from public.customers where id=nullif(p->>'customer_id','')::uuid and active;
 if c.id is null then raise exception 'CUSTOMER_REQUIRED';end if;
 if jsonb_typeof(p->'lines') is distinct from 'array' or jsonb_array_length(p->'lines') not between 1 and 200 then raise exception 'INVALID_LINES';end if;
 for line in select value from jsonb_array_elements(p->'lines') loop
  select * into product from public.products where id=nullif(line->>'product_id','')::uuid and active;
  qty:=(line->>'quantity')::numeric;
  if product.id is null then raise exception 'PRODUCT_NOT_FOUND';end if;
  if qty is null or qty::text in ('NaN','Infinity','-Infinity') or qty<=0 or qty>=100000000 or qty<>round(qty,3) then raise exception 'INVALID_LINES';end if;
  price:=private.erp_price(c.id,product.id,qty,stamp);
  if nullif(price->>'unit_price','') is null then raise exception 'INVALID_LINES';end if;
  ls:=ls||jsonb_build_array(jsonb_build_object('product_id',product.id,'description',product.name,'quantity',qty,'list_price',(price->>'unit_price')::numeric,'discount',0,'tax_rate',coalesce(product.tax_rate,0),'price_mode','automatic'));
 end loop;
 select coalesce(nullif(full_name,''),'Coco ERP') into seller from public.profiles where id=auth.uid();
 return jsonb_build_object('request_key',p_key,'customer_id',c.id,'issue_date',stamp,'valid_until',stamp+30,'lines',ls,
  'details',jsonb_build_object('client',c.name,'clientEmail',c.email,'seller',seller,'delivery_address',coalesce(nullif(btrim(coalesce(p->>'delivery_address',p->'details'->>'delivery_address')),''),nullif(btrim(c.address),''),'')));
end $$;
revoke all on function private.coco_proposal_quote(jsonb,uuid) from public,anon,authenticated;

create function private.coco_dossier(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare k text:=p_data->>'kind';oid uuid:=nullif(p_data->>'order_id','')::uuid;ctx jsonb;off integer:=coalesce((p_data->>'offset')::integer,0);
 entries jsonb;hist jsonb:='[]';portraits jsonb;proposals jsonb;author text;entry private.coco_order_entries;prop private.coco_mail_proposals;v_review jsonb;v_result jsonb;key uuid;ids uuid[];qids uuid[];tids uuid[];
begin
 ctx:=private.coco_dossier_context(k,oid);
 if p_action='context' then return ctx;end if;
 if p_action='list' then
  if off not between 0 and 1000000 then raise exception 'INVALID_OFFSET';end if;
  ids:=array[]::uuid[];qids:=array[]::uuid[];tids:=array[]::uuid[];
  if oid is not null then
   if k in ('sales','quote') then
    if private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero']) then ids:=array[nullif(ctx->>'sales_order_id','')::uuid];end if;
    if private.erp_module_allowed('quotes',array['administrador','comercial']) then qids:=array[nullif(ctx->>'quote_id','')::uuid];end if;
    if private.erp_module_allowed('tms',array['administrador','comercial','almacenero']) then select array_agg(s.tms_delivery_id) into tids from public.sales_deliveries s where s.order_id=any(ids);end if;
    hist:=private.coco_dossier_process_history((case when k='sales' then 'o:' else 'q:' end)||oid,0,off)->'items';
   elsif k='purchase' then hist:=private.coco_dossier_process_history('p:'||oid,0,off)->'items';
   elsif k='tms' then
    tids:=array[oid];ids:=array[]::uuid[];
    if private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero']) and ctx->>'sales_order_id' is not null then
     ids:=array[(ctx->>'sales_order_id')::uuid];
     if private.erp_module_allowed('quotes',array['administrador','comercial']) then qids:=array[(ctx->>'quote_id')::uuid];end if;
     hist:=private.coco_dossier_process_history('o:'||(ctx->>'sales_order_id'),0,off)->'items';
    else
     select coalesce(jsonb_agg(e),'[]') into hist from (
      select 'delivery:'||e.id id,e.at,e.user_id actor_id,coalesce(p.full_name,'AUTHOR_NOT_RECORDED') actor_name,'delivery_'||e.type action,e.note body,5 step,count(*) over() total
      from public.tms_events e left join public.profiles p on p.id=e.user_id where e.delivery_id=oid order by e.at desc,e.id offset off limit 50
     ) e;
    end if;
   end if;
  end if;
  select coalesce(jsonb_agg(to_jsonb(x)-'created_at_sort' order by x.created_at_sort desc,x.id),'[]') into entries from (
   select e.id,e.kind,e.order_id,e.type,e.actor_id,e.actor_name,e.created_at,e.created_at created_at_sort,e.subject,e.body,e.status,e.from_email,e.to_email,e.attachments,e.detail->>'proposal_id' proposal_id,e.detail->>'source_email' source_email,e.detail->>'source_subject' source_subject
   from private.coco_order_entries e where
    ((oid is null and e.order_id is null and e.kind=case when k='quote' then 'sales' else k end) or
     (oid is not null and ((e.kind=k and e.order_id=oid) or (e.kind='sales' and e.order_id=any(ids)) or (e.kind='quote' and e.order_id=any(qids)) or (e.kind='tms' and e.order_id=any(tids)))))
    and (e.type<>'mail' or (ctx->>'commercial')::boolean) and (e.detail->>'proposal_id' is null or (ctx->>'can_review')::boolean)
   order by e.created_at desc,e.id offset off limit 51
  ) x;
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'kind',p.kind,'target_kind',p.target_kind,'target_id',p.target_id,'status',p.status,'action',p.action,'summary',p.summary,'payload',p.payload,'result',p.result,'source_email',p.source_email,'source_subject',p.source_subject,'message_id',p.message_id,'received_at',p.received_at)),'[]') into proposals
   from private.coco_mail_proposals p where (ctx->>'can_review')::boolean and p.entry_id in(select (v->>'id')::uuid from jsonb_array_elements(entries) v);
  select coalesce(jsonb_object_agg(h.profile_id::text,h.photo_data),'{}') into portraits from public.hr_employees h where h.active and h.photo_data is not null and length(h.photo_data)<=120000 and h.profile_id in
   (select nullif(v->>'actor_id','')::uuid from jsonb_array_elements(entries||coalesce(hist,'[]')) v);
  return jsonb_build_object('context',ctx,'entries',entries,'history',coalesce(hist,'[]'),'portraits',portraits,'proposals',proposals);
 end if;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
 if p_action='note' then
  if not (ctx->>'can_note')::boolean then raise exception 'ROLE_NOT_ALLOWED';end if;
  if length(btrim(coalesce(p_data->>'body',''))) not between 1 and 10000 then raise exception 'INVALID_MESSAGE';end if;
  key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,body,request_key)
   values(k,oid,'note',auth.uid(),author,btrim(p_data->>'body'),key) on conflict(actor_id,request_key) do nothing returning * into entry;
  if entry.id is null then select * into entry from private.coco_order_entries where actor_id=auth.uid() and request_key=key;end if;
  if entry.kind<>k or entry.order_id is distinct from oid or entry.body<>btrim(p_data->>'body') or entry.type<>'note' then raise exception 'REQUEST_KEY_REUSED';end if;
  return jsonb_build_object('id',entry.id);
 elsif p_action in ('review_proposal','approve_proposal','reject_proposal') then
  if not (ctx->>'can_review')::boolean then raise exception 'ROLE_NOT_ALLOWED';end if;
  select * into prop from private.coco_mail_proposals where id=(p_data->>'proposal_id')::uuid for update;
  if prop.id is null or prop.kind<>(case when k='quote' then 'sales' else k end) or prop.target_id is distinct from oid or (oid is not null and prop.target_kind<>k) then raise exception 'PROPOSAL_NOT_FOUND';end if;
  if not exists(select 1 from private.coco_mail_bridge_accounts a join auth.users u on u.id=a.user_id join public.profiles p on p.id=u.id where a.user_id=prop.mailbox_user and p.active and a.email=lower(u.email)) then raise exception 'BRIDGE_DISABLED';end if;
  if prop.status<>'pending' then
   if p_action='approve_proposal' and prop.status='approved' then return prop.result;end if;
   if p_action='reject_proposal' and prop.status='rejected' then return jsonb_build_object('status','rejected');end if;
   raise exception 'PROPOSAL_DECIDED';
  end if;
  if p_action='review_proposal' then
   if prop.action='quote_draft' then v_review:=private.coco_proposal_quote(coalesce(p_data->'payload',prop.payload),prop.id);
   else v_review:=jsonb_build_object('body',prop.summary,'kind',prop.target_kind,'order_id',prop.target_id);end if;
   update private.coco_mail_proposals set review=v_review,reviewed_by=auth.uid(),reviewed_at=now(),review_hash=md5(v_review::text) where id=prop.id;
   return jsonb_build_object('review',v_review,'hash',md5(v_review::text),'action',prop.action);
  elsif p_action='approve_proposal' then
   if prop.reviewed_by is distinct from auth.uid() or prop.reviewed_at<now()-interval '10 minutes' or prop.review_hash is distinct from p_data->>'hash' then raise exception 'PROPOSAL_CHANGED';end if;
   if prop.action='quote_draft' then
    v_review:=private.coco_proposal_quote(prop.review,prop.id);
    if md5(v_review::text)<>prop.review_hash then raise exception 'PROPOSAL_CHANGED';end if;
    v_result:=private.gama_quote_action('save',v_review)||jsonb_build_object('kind','quote');
    insert into private.coco_order_entries(kind,order_id,type,actor_name,subject,body,detail)
     values('quote',(v_result->>'id')::uuid,'note','ChatGPT','mail_analysis',prop.summary,jsonb_build_object('message_id',prop.message_id,'source_email',prop.source_email,'source_subject',prop.source_subject));
    insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,subject,body)
     values('quote',(v_result->>'id')::uuid,'note',auth.uid(),author,'proposal_approved',prop.summary);
   else v_result:=jsonb_build_object('status','approved','kind',prop.target_kind,'id',prop.target_id);end if;
  else v_result:=jsonb_build_object('status','rejected');end if;
  update private.coco_mail_proposals set status=case when p_action='reject_proposal' then 'rejected' else 'approved' end,decided_at=now(),decided_by=auth.uid(),result=v_result where id=prop.id;
  insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,subject,body,detail)
   values(case when k='quote' and oid is null then 'sales' else k end,oid,'note',auth.uid(),author,case when p_action='reject_proposal' then 'proposal_rejected' else 'proposal_approved' end,prop.summary,jsonb_build_object('proposal_id',prop.id));
  return v_result;
 elsif p_action='bridge_disable' then
  update private.coco_mail_bridge_accounts set enabled=false where user_id=auth.uid();return jsonb_build_object('enabled',false);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.coco_dossier(text,jsonb) from public,anon;
grant execute on function private.coco_dossier(text,jsonb) to authenticated;
create function public.coco_dossier(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.coco_dossier(p_action,p_data)$$;
revoke all on function public.coco_dossier(text,jsonb) from public,anon;
grant execute on function public.coco_dossier(text,jsonb) to authenticated;

-- This narrow service entry accepts connector-verified mail facts and creates
-- only pending proposals. It never executes an ERP business action or sets JWTs.
create function private.coco_mail_bridge(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid;mailbox text:=lower(btrim(p_data->>'mailbox_email'));sender text:=lower(btrim(p_data->>'source_email'));prop private.coco_mail_proposals;new_entry uuid;payload jsonb;target uuid;kind text;target_kind text;matches jsonb;dossiers jsonb;target_email text;
begin
 select u.id into uid from auth.users u join public.profiles p on p.id=u.id where lower(u.email)=mailbox and p.active and p.deleted_at is null and p.role in ('administrador','comercial') and (u.banned_until is null or u.banned_until<now());
 if uid is null then raise exception 'MAILBOX_ACCOUNT_NOT_FOUND';end if;
 if p_action='enable' then
  insert into private.coco_mail_bridge_accounts(user_id,email,enabled) values(uid,mailbox,true) on conflict(user_id) do update set enabled=true,email=excluded.email;
  return jsonb_build_object('enabled',true,'email',mailbox);
 end if;
 if not exists(select 1 from private.coco_mail_bridge_accounts where user_id=uid and enabled and coco_mail_bridge_accounts.email=mailbox) then raise exception 'BRIDGE_DISABLED';end if;
 if p_action='context' then
  select coalesce(jsonb_agg(jsonb_build_object('kind','customer','id',id,'name',name,'address',address)),'[]') into matches from public.customers where active and lower(btrim(customers.email))=sender;
  select matches||coalesce(jsonb_agg(jsonb_build_object('kind','supplier','id',id,'name',name)),'[]') into matches from public.suppliers where active and lower(btrim(suppliers.email))=sender;
  select coalesce(jsonb_agg(x),'[]') into dossiers from (
   select 'sales'::text kind,o.id,o.number reference,c.name party from public.sales_orders o join public.customers c on c.id=o.customer_id where lower(btrim(c.email))=sender and p_data->>'reference' in (o.number,o.erp_reference)
   union all select 'quote',q.id,q.invoice_number,c.name from public.invoices q join public.customers c on c.id=q.customer_id where lower(btrim(c.email))=sender and p_data->>'reference' in (q.invoice_number,to_jsonb(q)->>'erp_reference')
   union all select 'purchase',o.id,o.order_number,c.name from public.purchase_orders o join public.suppliers c on c.id=o.supplier_id where lower(btrim(c.email))=sender and p_data->>'reference' in (o.order_number,o.erp_reference)
   union all select 'tms',d.id,d.erp_reference,c.name from public.tms_deliveries d left join public.sales_deliveries s on s.tms_delivery_id=d.id left join public.sales_orders o on o.id=s.order_id join public.customers c on c.id=coalesce(d.customer_id,o.customer_id) where lower(btrim(c.email))=sender and p_data->>'reference' in (d.erp_reference,s.number)
  ) x;
  return jsonb_build_object('contacts',matches,'dossiers',dossiers,'products',(select coalesce(jsonb_agg(x),'[]') from (select id,name,reference,base_unit from public.products where active and length(coalesce(p_data->>'search',''))>=2 and (name ilike '%'||(p_data->>'search')||'%' or reference ilike '%'||(p_data->>'search')||'%') order by name,id limit 25) x),'existing',(select jsonb_build_object('id',id,'status',status) from private.coco_mail_proposals where mailbox_user=uid and message_id=p_data->>'message_id'));
 elsif p_action='propose' then
  if coalesce(p_data->>'message_id','')='' or sender!~'^[^\s@<>;,]+@[^\s@<>;,]+\.[^\s@<>;,]+$' or length(coalesce(p_data->>'summary','')) not between 1 and 10000 then raise exception 'INVALID_MESSAGE';end if;
  kind:=p_data->>'kind';target_kind:=coalesce(p_data->>'target_kind',kind);target:=nullif(p_data->>'target_id','')::uuid;payload:=coalesce(p_data->'payload','{}');
  if kind not in ('sales','purchase','tms') or target_kind not in ('sales','purchase','quote','tms') then raise exception 'INVALID_ORDER_KIND';end if;
  if jsonb_typeof(payload) is distinct from 'object' or (kind='sales' and target_kind not in ('sales','quote')) or (kind in ('purchase','tms') and kind<>target_kind) then raise exception 'INVALID_PROPOSAL';end if;
  if (p_data->>'action')='quote_draft' and (kind<>'sales' or target is not null) then raise exception 'INVALID_PROPOSAL';end if;
  if target is not null and not (case target_kind when 'sales' then exists(select 1 from public.sales_orders where id=target) when 'quote' then exists(select 1 from public.invoices where id=target) when 'purchase' then exists(select 1 from public.purchase_orders where id=target) when 'tms' then exists(select 1 from public.tms_deliveries where id=target) else false end) then raise exception 'ORDER_NOT_FOUND';end if;
  if target is not null then
   if target_kind='sales' then select c.email into target_email from public.sales_orders o join public.customers c on c.id=o.customer_id where o.id=target;
   elsif target_kind='quote' then select c.email into target_email from public.invoices o join public.customers c on c.id=o.customer_id where o.id=target;
   elsif target_kind='purchase' then select c.email into target_email from public.purchase_orders o join public.suppliers c on c.id=o.supplier_id where o.id=target;
   else select c.email into target_email from public.tms_deliveries d left join public.sales_deliveries s on s.tms_delivery_id=d.id left join public.sales_orders o on o.id=s.order_id join public.customers c on c.id=coalesce(d.customer_id,o.customer_id) where d.id=target;end if;
   if lower(btrim(target_email)) is distinct from sender then raise exception 'MAIL_TARGET_MISMATCH';end if;
  end if;
  insert into private.coco_mail_proposals(mailbox_user,message_id,thread_id,source_email,source_subject,received_at,kind,target_kind,target_id,action,summary,payload)
   values(uid,p_data->>'message_id',p_data->>'thread_id',sender,left(coalesce(p_data->>'subject',''),300),(p_data->>'received_at')::timestamptz,kind,target_kind,target,p_data->>'action',p_data->>'summary',payload)
   on conflict(mailbox_user,message_id) do nothing returning * into prop;
  if prop.id is null then select * into prop from private.coco_mail_proposals where mailbox_user=uid and message_id=p_data->>'message_id';return jsonb_build_object('id',prop.id,'status',prop.status,'duplicate',true);end if;
  insert into private.coco_order_entries(kind,order_id,type,actor_name,subject,body,detail)
   values(case when target is null then kind else target_kind end,target,'note','ChatGPT','mail_analysis',prop.summary,jsonb_build_object('proposal_id',prop.id)) returning id into new_entry;
  update private.coco_mail_proposals set entry_id=new_entry where id=prop.id;
  update private.coco_mail_bridge_accounts set last_received_at=now() where user_id=uid;
  return jsonb_build_object('id',prop.id,'status','pending');
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.coco_mail_bridge(text,jsonb) from public,anon,authenticated;
grant execute on function private.coco_mail_bridge(text,jsonb) to service_role;
create function public.coco_mail_bridge(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.coco_mail_bridge(p_action,p_data)$$;
revoke all on function public.coco_mail_bridge(text,jsonb) from public,anon,authenticated;
grant execute on function public.coco_mail_bridge(text,jsonb) to service_role;

-- Capture ordinary transport edits too, including edits made outside this UI.
create function private.coco_transport_discussion_event() returns trigger language plpgsql security definer set search_path='' as $$
declare before_row jsonb:=case when tg_op='UPDATE' then to_jsonb(old) else '{}'::jsonb end;after_row jsonb:=to_jsonb(new);changed jsonb;author text;
begin
 select jsonb_agg(key order by key) into changed from jsonb_each(after_row) where key=any(array['status','delivery_date','route_id','driver_id','address','notes','promised_from','promised_until','settled_at']) and value is distinct from before_row->key;
 if tg_op='UPDATE' and changed is null then return new;end if;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
 insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,subject,body)
  values('tms',new.id,'action',auth.uid(),coalesce(author,'AUTHOR_NOT_RECORDED'),case when tg_op='INSERT' then 'delivery_created' else 'delivery_updated' end,coalesce(changed::text,''));
 return new;
end $$;
revoke all on function private.coco_transport_discussion_event() from public,anon,authenticated;
create trigger coco_transport_discussion_event after insert or update on public.tms_deliveries for each row execute function private.coco_transport_discussion_event();

alter function private.coco_order_followup(text,jsonb) rename to coco_order_followup_before_discussion;
revoke all on function private.coco_order_followup_before_discussion(text,jsonb) from public,anon,authenticated;
create function private.coco_order_followup(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$begin
 if p_action in ('context','list','note') then return private.coco_dossier(p_action,p_data);end if;
 if p_action='purchase_manual_sent' then return private.coco_order_followup_before_discussion(p_action,p_data);end if;
 raise exception 'MAIL_CONNECTOR_REMOVED';
end $$;
create or replace function public.coco_order_followup(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.coco_order_followup(p_action,p_data)$$;
revoke all on function private.coco_order_followup(text,jsonb) from public,anon;
grant execute on function private.coco_order_followup(text,jsonb) to authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261017113550','dossier_chatgpt_followup','4d7e48db5f051d4a839e3c3d92147e5a393e0b169a0ba10c6aa662e886be6e9f','4d7e48db5f051d4a839e3c3d92147e5a393e0b169a0ba10c6aa662e886be6e9f','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261017131741_minmax_purchase_module_history.sql; SHA256 0453cb166f7badc6fd1de4ffae737fc6df6c911356485e796b8f4bd9e9021e79
-- Log future automatic min/max purchase drafts in the purchase module inbox.
-- Keep the existing locks, permissions, quantity calculation and durable receipts.
-- No historical backfill: a replayed receipt returns before any new history write.
create or replace function private.automation_replenish_minmax(p_job private.automation_jobs,p_config jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 row record;item jsonb;items jsonb:='[]';grouped record;orders jsonb:='[]';po jsonb;result jsonb;
 cap numeric:=coalesce((p_config->>'max_order_total')::numeric,1000);
 receipt private.command_receipts;products_count integer:=0;skipped integer:=0;reason text;author text;supplier_name text;snapshot jsonb;
begin
 if auth.uid() is null or not private.automation_delegation_ok() then raise exception 'DELEGATION_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','comercial'])
  or not private.erp_action_allowed('gamaPurchasesV14','create') then raise exception 'ACTION_NOT_ALLOWED';end if;
 if cap::text in ('NaN','Infinity','-Infinity') or cap<=0 or cap>1000000 then
  return jsonb_build_object('blocked',true,'reason','PURCHASE_LIMIT_REQUIRED');
 end if;
 -- Shared with manual Stock replenishment, and protected by the durable job
 -- receipt as well as the canonical purchase command's own receipts.
 perform pg_advisory_xact_lock(hashtextextended('stock-replenishment',0));
 select * into receipt from private.command_receipts where domain='automatic-minmax-replenish' and request_key=p_job.id;
 if found then
  if receipt.actor_id<>auth.uid() or receipt.payload is distinct from p_config then raise exception 'REQUEST_KEY_REUSED';end if;
  return receipt.result;
 end if;
 -- Resolve old product exceptions when stock/thresholds/following purchases
 -- have changed. Still-invalid rows are reopened below with the current reason.
 update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now()
  where kind='replenishment' and key like 'minmax:%' and active;
 for row in select x.product_id,x.data from private.stock_minmax_replenishment_rows() x order by x.product_id limit 3000 loop
  item:=row.data;reason:=null;
  if not (item->>'thresholds_valid')::boolean then reason:='MIN_MAX_REQUIRED';
  elsif (item->>'quantity')::numeric<=0 then continue;
  elsif nullif(item->>'supplier_id','') is null then reason:='ACTIVE_SUPPLIER_REQUIRED';
  elsif (item->>'quantity')::numeric>999999999 then reason:='INVALID_QUANTITY';
  elsif (item->>'unit_cost')::numeric<0 or (item->>'unit_cost')::numeric>999999999 then reason:='INVALID_PRICE';
  end if;
  if reason is not null then
   perform private.automation_exception('minmax:'||row.product_id,'replenishment','gamaPurchasesV14','product',row.product_id,reason,p_job.id,item->>'reference');
   skipped:=skipped+1;
  else items:=items||jsonb_build_array(item);
  end if;
 end loop;
 for grouped in
  select x->>'supplier_id' supplier,max((x->>'lead_time_days')::integer) lead,
   sum(round((x->>'quantity')::numeric*(x->>'unit_cost')::numeric,2)
    +round(round((x->>'quantity')::numeric*(x->>'unit_cost')::numeric,2)*(x->>'tax_rate')::numeric/100,2)) total,
   jsonb_agg(jsonb_build_object('product_id',x->>'id','quantity',(x->>'quantity')::numeric,
    'unit_cost',(x->>'unit_cost')::numeric,'tax_rate',(x->>'tax_rate')::numeric) order by x->>'id') lines
  from jsonb_array_elements(items) x group by x->>'supplier_id' order by x->>'supplier_id'
 loop
  if grouped.total>cap or jsonb_array_length(grouped.lines)>500 then
   perform private.automation_exception('minmax:limit:'||grouped.supplier,'replenishment','gamaPurchasesV14','supplier',grouped.supplier::uuid,
    case when grouped.total>cap then 'PURCHASE_LIMIT_EXCEEDED' else 'SUPPLIER_LINE_LIMIT_500' end,p_job.id);
   skipped:=skipped+jsonb_array_length(grouped.lines);continue;
  end if;
  po:=private.gama_purchase_save(jsonb_build_object(
   'request_key',private.automation_key('minmax:'||p_job.id||':'||grouped.supplier),
   'supplier_id',grouped.supplier,'source_kind','low_stock',
   'destination_location_id',p_config->>'destination_location_id',
   'expected_date',case when grouped.lead is not null then current_date+grouped.lead end,
   'notes','Reposición automática mín./máx.: máximo de la ficha menos stock físico y compras pendientes (incluidos borradores). Revisar antes de enviar.',
   'lines',grouped.lines));
  -- This module event commits with the actual draft, never with a stock check.
  -- The delegated account remains the recorded actor; the title marks automation.
  select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
  select name into supplier_name from public.suppliers where id=grouped.supplier::uuid;
  select jsonb_agg(jsonb_build_object('product_id',x->>'id','name',x->>'name','reference',x->>'reference',
   'quantity',x->'quantity','on_hand',x->'on_hand','min_stock',x->'min_stock','max_stock',x->'max_stock') order by x->>'id')
   into snapshot from jsonb_array_elements(items) x where x->>'supplier_id'=grouped.supplier;
  insert into private.coco_order_entries(kind,order_id,type,actor_id,actor_name,subject,body,request_key,detail)
   values('purchase',null,'action',auth.uid(),coalesce(author,'USER_UNAVAILABLE'),'automatic_minmax_purchase',
    concat_ws(' · ',po->>'order_number',supplier_name),private.automation_key('minmax-history:'||(po->>'id')),
    jsonb_build_object('purchase_order_id',po->>'id','job_id',p_job.id,'basis','min_max','replenishment',snapshot))
   on conflict(actor_id,request_key) do nothing;
  orders:=orders||jsonb_build_array(jsonb_build_object('id',po->>'id','number',po->>'order_number',
   'supplier_id',grouped.supplier,'lines',jsonb_array_length(grouped.lines)));
  products_count:=products_count+jsonb_array_length(grouped.lines);
 end loop;
 result:=jsonb_build_object('orders',orders,'products',products_count,'skipped',skipped,'basis','min_max','as_of',now());
 insert into private.command_receipts(domain,request_key,actor_id,payload,result)
  values('automatic-minmax-replenish',p_job.id,auth.uid(),p_config,result);
 return result;
end $$;
revoke all on function private.automation_replenish_minmax(private.automation_jobs,jsonb) from public,anon,authenticated,service_role;

-- Expose only the navigation target and stock snapshot on the already-scoped
-- history projection. Keep every module, financial and proposal permission intact.
do $$declare source text;needle text:='e.detail->>''source_subject'' source_subject';begin
 source:=pg_get_functiondef('private.coco_dossier(text,jsonb)'::regprocedure);
 if (length(source)-length(replace(source,needle,'')))/length(needle)<>1 then
  raise exception 'UNEXPECTED_DOSSIER_HISTORY_PROJECTION';
 end if;
 source:=replace(source,needle,needle||',e.detail->>''purchase_order_id'' purchase_order_id,e.detail->''replenishment'' replenishment');
 execute source;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261017131741','minmax_purchase_module_history','0453cb166f7badc6fd1de4ffae737fc6df6c911356485e796b8f4bd9e9021e79','0453cb166f7badc6fd1de4ffae737fc6df6c911356485e796b8f4bd9e9021e79','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261017133055_grouped_dossier_history.sql; SHA256 55e9c9256ac85e5f88aefbd75db43652b2530597757201827853868f2b2e7257
-- Enrich only events already admitted by the dossier's existing access checks.
-- This internal projection never returns raw audit/detail payloads or prices.
create function private.coco_history_event_details(p_event text,p_key text,p_action text,p_step integer,p_reference text) returns jsonb
language plpgsql stable set search_path='' as $$
declare
 source uuid:=split_part(p_key,':',2)::uuid;prefix text:=split_part(p_event,':',1);token text:=split_part(p_event,':',2);
 eid uuid;entity uuid;pid uuid;line_id uuid;delivery_id uuid;quote_id uuid;invoice_id uuid;
 detail jsonb:='{}';before_data jsonb:='{}';after_data jsonb:='{}';tbl text;at_time timestamptz;qty numeric;
 refs jsonb:='[]';links jsonb:='[]';doc_reference text;product_name text;product_reference text;unit text;
begin
 if split_part(p_key,':',1)='q' then quote_id:=source;select o.id into source from public.sales_orders o where o.source_quote_id=quote_id;end if;
 if token ~ '^[0-9a-fA-F-]{36}$' then eid:=token::uuid;end if;
 if prefix='sale' then
  select e.detail,e.entity_id,e.created_at into detail,entity,at_time from public.sales_events e where e.id=eid and e.order_id=source;
  if detail->>'product_id' ~ '^[0-9a-fA-F-]{36}$' then pid:=(detail->>'product_id')::uuid;end if;
  if detail->>'line_id' ~ '^[0-9a-fA-F-]{36}$' then line_id:=(detail->>'line_id')::uuid;end if;
  if jsonb_typeof(detail->'quantity')='number' then qty:=(detail->>'quantity')::numeric;end if;
  if p_action='fulfillment_pick' then select l.order_line_id into line_id from public.fulfillment_pick_lines l where l.id=entity;end if;
  if line_id is not null then select l.product_id,l.product_name,l.reference into pid,product_name,product_reference from public.sales_order_lines l where l.id=line_id and l.order_id=source;end if;
  if p_action in ('confirm','reserve') then
   select coalesce(jsonb_agg(jsonb_build_object('kind','product','id',x.product_id,'reference',x.reference,'name',x.product_name,'quantity',x.quantity,'unit',x.base_unit)),'[]') into refs from (
    select l.product_id,l.reference,l.product_name,p.base_unit,sum(r.quantity) quantity from public.stock_reservations r
    join public.sales_reservation_links sl on sl.reservation_id=r.id join public.sales_order_lines l on l.id=sl.line_id join public.products p on p.id=l.product_id
    where l.order_id=source and r.created_at=at_time group by l.product_id,l.reference,l.product_name,p.base_unit
   ) x;
  elsif p_action='fulfillment_package' then
   select coalesce(jsonb_agg(jsonb_build_object('kind','product','id',l.product_id,'reference',l.reference,'name',l.product_name,'quantity',pl.quantity,'unit',p.base_unit)),'[]') into refs
    from public.fulfillment_package_lines pl join public.fulfillment_pick_lines pick on pick.id=pl.pick_line_id
    join public.sales_order_lines l on l.id=pick.order_line_id join public.products p on p.id=l.product_id where pl.package_id=entity and l.order_id=source;
  end if;
  if p_action like 'internal_%' or p_action like 'invoice_%' or p_action in ('invoice','deposit_created') then
   select i.id,i.number into invoice_id,doc_reference from public.external_invoices i where i.id=entity and i.order_id=source;
   if invoice_id is not null then
    refs:=refs||jsonb_build_array(jsonb_build_object('kind','invoice','id',invoice_id,'reference',doc_reference));
    if private.erp_module_allowed('payments',array['administrador','comercial']) then links:=links||jsonb_build_array(jsonb_build_object('module','payments','action','invoice','id',invoice_id,'reference',doc_reference));end if;
   end if;
  end if;
  select d.tms_delivery_id into delivery_id from public.sales_deliveries d where d.id=entity and d.order_id=source;
 elsif prefix='stock' then
  select m.product_id,m.quantity into pid,qty from public.stock_movements m where m.id=eid and m.reference_type='purchase_order' and m.reference_id=source;
 elsif prefix='audit' and token ~ '^[0-9]+$' then
  select a.table_name,a.before_data,a.after_data into tbl,before_data,after_data from public.erp_audit_events a where a.id=token::bigint;
  if tbl='purchase_order_lines' and after_data->>'purchase_order_id'=source::text then
   pid:=(after_data->>'product_id')::uuid;qty:=coalesce((after_data->>'received_quantity')::numeric,0)-coalesce((before_data->>'received_quantity')::numeric,0);
  elsif tbl='supplier_invoices' and private.erp_module_allowed('accounting',array['administrador','comercial']) then
   invoice_id:=(after_data->>'id')::uuid;doc_reference:=coalesce(after_data->>'number',p_reference);
   links:=links||jsonb_build_array(jsonb_build_object('module','accounting','action','supplier_invoice','id',invoice_id,'reference',doc_reference));
  elsif tbl='supplier_invoice_payments' and private.erp_module_allowed('accounting',array['administrador','comercial']) then
   links:=links||jsonb_build_array(jsonb_build_object('module','accounting','action','supplier_invoice','id',after_data->>'supplier_invoice_id','reference',p_reference));
  elsif tbl='supplier_invoice_matches' and private.erp_module_allowed('accounting',array['administrador','comercial']) then
   links:=links||jsonb_build_array(jsonb_build_object('module','accounting','action','supplier_invoice','id',after_data->>'invoice_id','reference',p_reference));
  elsif tbl in ('external_invoices','external_invoice_payments') and private.erp_module_allowed('payments',array['administrador','comercial']) then
   invoice_id:=case when tbl='external_invoices' then (after_data->>'id')::uuid else (after_data->>'invoice_id')::uuid end;
   links:=links||jsonb_build_array(jsonb_build_object('module','payments','action','invoice','id',invoice_id,'reference',p_reference));
  elsif tbl='customer_requests' and private.erp_module_allowed('customer-requests',array['administrador','comercial']) then
   links:=links||jsonb_build_array(jsonb_build_object('module','customer-requests','action','request','id',after_data->>'id','reference',p_reference));
  elsif tbl='crm_opportunities' and private.erp_module_allowed('crm',array['administrador','comercial']) then
   links:=links||jsonb_build_array(jsonb_build_object('module','crm','action','opportunity','id',after_data->>'id','reference',p_reference));
  end if;
 elsif prefix='request-created' and private.erp_module_allowed('customer-requests',array['administrador','comercial']) then
  links:=links||jsonb_build_array(jsonb_build_object('module','customer-requests','action','request','id',eid,'reference',p_reference));
 elsif prefix='opportunity-created' and private.erp_module_allowed('crm',array['administrador','comercial']) then
  links:=links||jsonb_build_array(jsonb_build_object('module','crm','action','opportunity','id',eid,'reference',p_reference));
 elsif prefix in ('credit-created','refund-created') and private.erp_module_allowed('returns',array['administrador','comercial','almacenero']) then
  if prefix='credit-created' then select c.return_id into entity from public.return_credits c where c.id=eid;else select f.return_id into entity from public.return_refunds f where f.id=eid;end if;
  if entity is not null then links:=links||jsonb_build_array(jsonb_build_object('module','returns','action','return','id',entity,'reference',p_reference));end if;
 elsif prefix in ('delivery','proof') then
  if prefix='delivery' then select e.delivery_id into delivery_id from public.tms_events e where e.id=eid;else delivery_id:=eid;end if;
 elsif prefix in ('payment-created','supplier-payment-created') then
  if prefix='payment-created' and private.erp_module_allowed('payments',array['administrador','comercial']) then
   select p.invoice_id into invoice_id from public.external_invoice_payments p where p.id=eid;
   links:=links||jsonb_build_array(jsonb_build_object('module','payments','action','invoice','id',invoice_id,'reference',p_reference));
  elsif prefix='supplier-payment-created' and private.erp_module_allowed('accounting',array['administrador','comercial']) then
   select p.supplier_invoice_id into invoice_id from public.supplier_invoice_payments p where p.id=eid;
   links:=links||jsonb_build_array(jsonb_build_object('module','accounting','action','supplier_invoice','id',invoice_id,'reference',p_reference));
  end if;
 end if;
 if pid is not null then
  select coalesce(product_name,p.name),coalesce(nullif(product_reference,''),p.reference),p.base_unit into product_name,product_reference,unit from public.products p where p.id=pid;
  refs:=refs||jsonb_build_array(jsonb_build_object('kind','product','id',pid,'reference',product_reference,'name',product_name,'quantity',qty,'unit',unit));
 end if;
 if nullif(p_reference,'') is not null then refs:=refs||jsonb_build_array(jsonb_build_object('kind','document','reference',p_reference));end if;
 if delivery_id is not null and private.erp_module_allowed('tms',array['administrador','comercial','almacenero','transportista']) then
  select coalesce(d.erp_reference,d.customer) into doc_reference from public.tms_deliveries d where d.id=delivery_id;
  links:=links||jsonb_build_array(jsonb_build_object('module','tms','action','delivery','id',delivery_id,'reference',doc_reference));
 end if;
 if split_part(p_key,':',1) in ('o','q') then
  if split_part(p_key,':',1)='o' then select o.source_quote_id into quote_id from public.sales_orders o where o.id=source;end if;
  if source is not null and private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero']) then
   select o.number into doc_reference from public.sales_orders o where o.id=source;
   links:=links||jsonb_build_array(jsonb_build_object('module','sales-orders','action','order','id',source,'reference',doc_reference));
  end if;
  if p_step<=3 and quote_id is not null and private.erp_module_allowed('quotes',array['administrador','comercial']) then
   select q.invoice_number into doc_reference from public.invoices q where q.id=quote_id;
   links:=links||jsonb_build_array(jsonb_build_object('module','quotes','action','quote','id',quote_id,'reference',doc_reference));
  end if;
  if p_step=4 and source is not null and private.erp_module_allowed('tms',array['administrador','comercial','almacenero']) then
   links:=links||jsonb_build_array(jsonb_build_object('module','tms','action','preparation','id',source));
  end if;
 elsif split_part(p_key,':',1)='p' and private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial','almacenero']) then
  select o.order_number into doc_reference from public.purchase_orders o where o.id=source;
  links:=links||jsonb_build_array(jsonb_build_object('module','gamaPurchasesV14','action','purchase','id',source,'reference',doc_reference));
 end if;
 if p_step in (3,4) and (pid is not null or jsonb_array_length(refs)>0) and private.erp_module_allowed('warehouses',array['administrador','comercial','almacenero']) then
  links:=links||jsonb_build_array(jsonb_build_object('module','warehouses','action','module'));
 end if;
 return jsonb_build_object('references',refs,'links',links);
end $$;
revoke all on function private.coco_history_event_details(text,text,text,integer,text) from public,anon,authenticated;

-- Group transaction siblings before paging. An action by another author, on
-- another dossier, at another exact server timestamp or stage stays separate.
-- The canonical process history remains unchanged for milestone consumers.
do $$declare source text;needle text;replacement text;begin
 source:=pg_get_functiondef('private.coco_dossier_process_history(text,integer,integer)'::regprocedure);
 needle:=$old$ ), numbered as (
  select *,row_number() over(partition by stage order by at desc,id desc) rn,count(*) over(partition by stage) total from permitted
 ) select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('id',id,'step',stage,'at',at,'actor_name',actor_name,'actor_id',actor_id,'action',action,'status',status,'reference',reference,'total',total) order by stage,at desc,id desc),'[]')) into result from numbered where rn>p_offset and rn<=p_offset+50;$old$;
 replacement:=$new$ ), grouped as (
  select min(id) id,stage,at,actor_id,actor_name,action,status,count(*) action_count,
   array_agg(id order by id) event_ids,array_agg(reference order by id) event_references
  from permitted group by stage,at,actor_id,actor_name,action,status
 ), numbered as (
  select *,row_number() over(partition by stage order by at desc,id desc) rn,count(*) over(partition by stage) total from grouped
 ), page as (
  select n.*,(select jsonb_agg(private.coco_history_event_details(x.id,p_key,n.action,n.stage,x.reference)) from unnest(n.event_ids,n.event_references) x(id,reference)) details
  from numbered n where rn>p_offset and rn<=p_offset+50
 ) select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('id',id,'step',stage,'at',at,'actor_name',actor_name,'actor_id',actor_id,'action',action,'status',status,'action_count',action_count,'total',total,
  'references',coalesce((select jsonb_agg(r) from jsonb_array_elements(details) d cross join lateral jsonb_array_elements(d->'references') r),'[]'),
  'links',coalesce((select jsonb_agg(distinct l) from jsonb_array_elements(details) d cross join lateral jsonb_array_elements(d->'links') l),'[]')) order by stage,at desc,id desc),'[]')) into result from page;$new$;
 if position(needle in source)=0 then raise exception 'DOSSIER_HISTORY_GROUPING_PATCH_MISMATCH';end if;
 execute replace(source,needle,replacement);
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261017133055','grouped_dossier_history','55e9c9256ac85e5f88aefbd75db43652b2530597757201827853868f2b2e7257','55e9c9256ac85e5f88aefbd75db43652b2530597757201827853868f2b2e7257','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261017141238_universal_module_history.sql; SHA256 87881f5efe93b34afe7b5991acfb9c172e7f0dc95f5bdfd49b64804f1ae22f62
-- A sanitized activity index. Business tables and their RLS remain authoritative.
create table private.coco_history_modules(
 module_id text primary key,label text not null,roles text[] not null
);
create table private.coco_history_tables(
 table_name text primary key,module_id text not null references private.coco_history_modules,
 label text not null,parent_column text,parent_table text,
 table_schema text not null default 'public' check(table_schema in ('public','private')),
 key_column text not null default 'id' check(key_column ~ '^[a-z_]+$'),
 check(table_name ~ '^[a-z_]+$' and (parent_table is null or parent_table ~ '^[a-z_]+$'))
);
create table private.coco_module_events(
 id uuid primary key default gen_random_uuid(),module_id text not null references private.coco_history_modules,
 record_table text references private.coco_history_tables,record_id text,record_owner uuid,
 type text not null check(type in ('action','note','proposal')),action text not null,
 subject text not null,body text not null default '',reference text,
 actor_id uuid references public.profiles on delete set null,actor_name text not null,
 created_at timestamptz not null default now(),transaction_id bigint not null default txid_current(),
 references_list jsonb not null default '[]',links jsonb not null default '[]',
 source_type text not null default 'erp' check(source_type in ('erp','mail','chat','file','import')),
 source_id text,source_label text,source_email text,proposal_id uuid,request_key uuid,
 unique(actor_id,request_key),check(length(body)<=10000 and length(subject)<=300)
);
create index coco_module_events_page on private.coco_module_events(module_id,created_at desc,id);
create index coco_module_events_record on private.coco_module_events(record_table,record_id);
create index coco_module_events_actor on private.coco_module_events(actor_id);
create index coco_module_events_proposal on private.coco_module_events(proposal_id);
alter table private.coco_history_modules enable row level security;
alter table private.coco_history_tables enable row level security;
alter table private.coco_module_events enable row level security;
revoke all on private.coco_history_modules,private.coco_history_tables,private.coco_module_events from public,anon,authenticated;
grant select on private.coco_history_modules,private.coco_history_tables,private.coco_module_events to authenticated;
create policy coco_history_catalog on private.coco_history_modules for select to authenticated using(true);
create policy coco_history_table_catalog on private.coco_history_tables for select to authenticated using(true);

insert into private.coco_history_modules values
('surveys','Encuestas y marketing',array['administrador','comercial']),
('sri','Facturación SRI',array['administrador']),
('website','Sitio web',array['administrador']),
('sav','Reclamaciones',array['administrador','comercial']),
('documents','Documentos',array['administrador','comercial','almacenero']),
('tms','TMS',array['administrador','almacenero']),
('accounting','Contabilidad',array['administrador','comercial']),
('fleet','Gestión de flota',array['administrador']),
('projects','Proyectos',array['administrador','comercial','almacenero']),
('assistant-ia','Agent Coco',array['administrador']),
('dashboard','Panel de control',array['administrador','comercial','almacenero']),
('notifications','Notificaciones',array['administrador','comercial','almacenero']),
('knowledge','Base de conocimientos',array['administrador','comercial','almacenero']),
('products','Productos',array['administrador','comercial','almacenero']),
('warehouses','Almacenes y existencias',array['administrador','comercial','almacenero']),
('gamaPurchasesV14','Compras',array['administrador','comercial','almacenero']),
('matrix','Matriz comercial',array['administrador','comercial']),
('barcode','Códigos de barras',array['administrador','almacenero']),
('quotes','Ventas',array['administrador','comercial']),
('contacts','Contactos',array['administrador','comercial']),
('dossier-flow','Seguimiento de procesos',array['administrador','comercial','almacenero']),
('sales-orders','Pedidos de venta',array['administrador','comercial','almacenero']),
('payments','Facturas y cobros',array['administrador','comercial']),
('returns','Devoluciones y posventa',array['administrador','comercial','almacenero']),
('crm','CRM',array['administrador','comercial']),
('price-lists','Tarifas',array['administrador','comercial']),
('reports','Importar datos',array['administrador','comercial']),
('hr','Recursos humanos',array['administrador','comercial','almacenero','rrhh']),
('audit','Auditoría',array['administrador']),
('users','Usuarios',array['administrador']),
('access-settings','Parámetros de acceso',array['administrador']),
('settings','Configuración',array['administrador','comercial','almacenero','rrhh']),
('backup','Copias de seguridad',array['administrador']),
('billing','Formulario anterior de presupuestos',array['administrador','comercial']),
('customer-requests','Solicitudes de clientes',array['administrador','comercial']);
insert into private.coco_history_tables(table_name,module_id,label,parent_column,parent_table) select v.* from (values
('products','products','Producto',null,null),
('product_units','products','Productos',null,null),
('product_lots','products','Productos',null,null),
('product_price_history','products','Productos',null,null),
('customers','contacts','Cliente',null,null),
('suppliers','contacts','Proveedor',null,null),
('customer_addresses','contacts','Contactos',null,null),
('crm_contacts','contacts','Contacto',null,null),
('crm_leads','crm','Prospecto',null,null),
('crm_opportunities','crm','CRM',null,null),
('crm_opportunity_lines','crm','CRM',null,null),
('crm_activities','crm','CRM',null,null),
('crm_targets','crm','CRM',null,null),
('crm_team','crm','CRM',null,null),
('crm_pipeline_stages','crm','CRM',null,null),
('crm_sources','crm','CRM',null,null),
('warehouses','warehouses','Almacenes y existencias',null,null),
('warehouse_locations','warehouses','Almacenes y existencias',null,null),
('warehouse_shelves','warehouses','Almacenes y existencias',null,null),
('stock_movements','warehouses','Almacenes y existencias',null,null),
('stock_quants','warehouses','Almacenes y existencias',null,null),
('stock_reservations','warehouses','Almacenes y existencias',null,null),
('stock_lot_movements','warehouses','Almacenes y existencias',null,null),
('inventory_counts','warehouses','Almacenes y existencias',null,null),
('inventory_count_lines','warehouses','Almacenes y existencias',null,null),
('reorder_rules','warehouses','Almacenes y existencias',null,null),
('stock_adjustment_requests','warehouses','Almacenes y existencias',null,null),
('stock_integrity_cases','warehouses','Almacenes y existencias',null,null),
('stock_landed_costs','warehouses','Almacenes y existencias',null,null),
('accounting_entries','accounting','Asiento contable',null,null),
('accounting_entry_lines','accounting','Líneas contables','entry_id','accounting_entries'),
('accounting_accounts','accounting','Contabilidad',null,null),
('accounting_journals','accounting','Contabilidad',null,null),
('accounting_periods','accounting','Contabilidad',null,null),
('accounting_taxes','accounting','Contabilidad',null,null),
('financial_accounts','accounting','Contabilidad',null,null),
('bank_transactions','accounting','Movimiento bancario',null,null),
('bank_match_groups','accounting','Contabilidad',null,null),
('reconciliations','accounting','Contabilidad',null,null),
('expenses','accounting','Contabilidad',null,null),
('expense_receipts','accounting','Contabilidad',null,null),
('supplier_invoices','accounting','Contabilidad',null,null),
('supplier_invoice_payments','accounting','Contabilidad',null,null),
('accounting_assets','accounting','Contabilidad',null,null),
('accounting_depreciations','accounting','Contabilidad',null,null),
('accounting_maturities','accounting','Contabilidad',null,null),
('accounting_payment_terms','accounting','Contabilidad',null,null),
('accounting_adjustments','accounting','Contabilidad',null,null),
('accounting_withholdings','accounting','Contabilidad',null,null),
('accounting_received_sri','accounting','Contabilidad',null,null),
('fleet_vehicles','fleet','Vehículo',null,null),
('fleet_drivers','fleet','Gestión de flota',null,null),
('fleet_assignments','fleet','Gestión de flota',null,null),
('fleet_documents','fleet','Gestión de flota',null,null),
('fleet_fuel_logs','fleet','Carga de combustible',null,null),
('fleet_maintenance','fleet','Gestión de flota',null,null),
('fleet_alert_log','fleet','Gestión de flota',null,null),
('hr_employees','hr','Ficha de empleado',null,null),
('hr_absences','hr','Solicitud de ausencia','employee_id','hr_employees'),
('hr_attendance','hr','Recursos humanos',null,null),
('hr_documents','hr','Documento RH',null,null),
('hr_payroll','hr','Recursos humanos',null,null),
('hr_payroll_payments','hr','Recursos humanos',null,null),
('hr_leave_accounts','hr','Recursos humanos',null,null),
('hr_employee_skills','hr','Recursos humanos',null,null),
('hr_shifts','hr','Recursos humanos',null,null),
('hr_work_patterns','hr','Recursos humanos',null,null),
('hr_lifecycle_tasks','hr','Recursos humanos',null,null),
('hr_ec_employee_terms','hr','Recursos humanos',null,null),
('hr_ec_benefits','hr','Recursos humanos',null,null),
('hr_ec_benefit_payments','hr','Recursos humanos',null,null),
('hr_ec_utilities','hr','Recursos humanos',null,null),
('business_documents','documents','Documento',null,null),
('business_document_files','documents','Archivo del documento','document_id','business_documents'),
('business_document_approvals','documents','Documentos',null,null),
('document_categories','documents','Documentos',null,null),
('pm_projects','projects','Proyectos',null,null),
('pm_items','projects','Proyectos',null,null),
('pm_comments','projects','Proyectos',null,null),
('pm_files','projects','Proyectos',null,null),
('pm_members','projects','Proyectos',null,null),
('pm_links','projects','Proyectos',null,null),
('pm_baselines','projects','Proyectos',null,null),
('pm_cost_entries','projects','Proyectos',null,null),
('pm_templates','projects','Proyectos',null,null),
('project_time_entries','projects','Proyectos',null,null),
('return_orders','returns','Devoluciones y posventa',null,null),
('return_lines','returns','Devoluciones y posventa','return_id','return_orders'),
('return_files','returns','Devoluciones y posventa',null,null),
('return_credits','returns','Devoluciones y posventa',null,null),
('return_refunds','returns','Devoluciones y posventa',null,null),
('service_tickets','sav','Reclamaciones',null,null),
('service_messages','sav','Reclamaciones',null,null),
('invoices','quotes','Ventas',null,null),
('invoice_lines','quotes','Ventas','invoice_id','invoices'),
('external_invoices','payments','Facturas y cobros',null,null),
('external_invoice_lines','payments','Facturas y cobros',null,null),
('external_invoice_payments','payments','Facturas y cobros',null,null),
('external_invoice_files','payments','Facturas y cobros',null,null),
('customer_receipts','payments','Facturas y cobros',null,null),
('receivable_followups','payments','Facturas y cobros',null,null),
('purchase_orders','gamaPurchasesV14','Compras',null,null),
('purchase_order_lines','gamaPurchasesV14','Compras','purchase_order_id','purchase_orders'),
('purchase_service_acceptances','gamaPurchasesV14','Compras',null,null),
('supplier_product_offers','gamaPurchasesV14','Compras',null,null),
('supplier_invoice_matches','gamaPurchasesV14','Compras',null,null),
('supplier_invoice_match_lines','gamaPurchasesV14','Compras',null,null),
('sales_orders','sales-orders','Pedidos de venta',null,null),
('sales_order_lines','sales-orders','Pedidos de venta','order_id','sales_orders'),
('sales_deliveries','sales-orders','Pedidos de venta',null,null),
('sales_delivery_lines','sales-orders','Pedidos de venta',null,null),
('sales_service_completions','sales-orders','Pedidos de venta',null,null),
('tms_deliveries','tms','TMS',null,null),
('tms_routes','tms','TMS',null,null),
('tms_delivery_attempts','tms','TMS',null,null),
('tms_delivery_incidents','tms','TMS',null,null),
('tms_loading_scans','tms','TMS',null,null),
('tms_route_schedules','tms','TMS',null,null),
('fulfillment_preparations','tms','TMS',null,null),
('fulfillment_pick_lines','tms','TMS',null,null),
('fulfillment_packages','tms','TMS',null,null),
('fulfillment_incidents','tms','TMS',null,null),
('knowledge_articles','knowledge','Artículo',null,null),
('storefront_settings','website','Sitio web',null,null),
('marketing_campaigns','surveys','Encuestas y marketing',null,null),
('survey_forms','surveys','Encuestas y marketing',null,null),
('sri_document_issues','sri','Facturación SRI',null,null),
('sri_electronic_documents','sri','Facturación SRI',null,null),
('profiles','users','Usuarios',null,null),
('erp_price_books','price-lists','Tarifas',null,null),
('erp_price_tiers','price-lists','Tarifas',null,null),
('customer_special_prices','price-lists','Tarifas',null,null),
('commercial_matrix','matrix','Matriz comercial',null,null),
('company_settings','settings','Configuración',null,null),
('app_modules','settings','Configuración',null,null),
('erp_policies','settings','Configuración',null,null),
('erp_import_batches','reports','Importar datos',null,null),
('erp_import_rows','reports','Importar datos',null,null)) v(table_name,module_id,label,parent_column,parent_table) where exists(select 1 from information_schema.tables t where t.table_schema='public' and t.table_name=v.table_name and t.table_type='BASE TABLE') and exists(select 1 from information_schema.columns c where c.table_schema='public' and c.table_name=v.table_name and c.column_name='id');


insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) select v.* from (values
 ('surveys','surveys','Encuesta','private','id'),('marketing_campaigns','surveys','Campaña','private','id'),
 ('website_public_settings','website','Configuración del sitio web','private','id'),
 ('website_public_inquiries','website','Solicitud del sitio web','private','id'),
 ('automation_rules','access-settings','Regla de automatización','private','kind'),
 ('hr_employee_private','hr','Ficha de empleado','public','employee_id'),
 ('hr_absence_private','hr','Solicitud de ausencia','public','absence_id'),
 ('role_module_access','access-settings','Permisos de módulo','public','role'),
 ('erp_action_permissions','access-settings','Permisos de acción','public','role'),
 ('accounting_permissions','accounting','Permisos contables','public','profile_id'),
 ('hr_permissions','hr','Permisos RH','public','profile_id'),
 ('gama_ai_history','assistant-ia','Acción de Agent Coco','public','id')) v(table_name,module_id,label,table_schema,key_column)
 where exists(select 1 from information_schema.columns c where c.table_schema=v.table_schema and c.table_name=v.table_name and c.column_name=v.key_column);

create function private.coco_module_allowed(p_module text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok()
 and exists(select 1 from private.coco_history_modules m where m.module_id=p_module
  and private.erp_module_allowed(m.module_id,m.roles))
 and case when p_module='accounting' then private.gama_accounting_may('view') and private.gama_accounting_rights()->>'scope'='all'
 when p_module='fleet' then private.gama_fleet_may() else true end
$$;
revoke all on function private.coco_module_allowed(text) from public,anon;
grant execute on function private.coco_module_allowed(text) to authenticated;

-- Invoker is essential here: a definer must never test row visibility on behalf
-- of the caller. Missing grants and unknown/deleted records fail closed.
create function private.coco_history_record_exists(p_table text,p_id text) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare cfg private.coco_history_tables;present boolean;begin
 select * into cfg from private.coco_history_tables where table_name=p_table;
 if cfg.table_name is null or not private.coco_module_allowed(cfg.module_id) or private.current_user_role()<>'administrador' then return false;end if;
 execute format('select exists(select 1 from %I.%I where %I::text=$1)',cfg.table_schema,p_table,cfg.key_column) into present using p_id;
 return coalesce(present,false);
end $$;
revoke all on function private.coco_history_record_exists(text,text) from public,anon;
grant execute on function private.coco_history_record_exists(text,text) to authenticated;
create function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$
declare cfg private.coco_history_tables;visible boolean;
begin
 select * into cfg from private.coco_history_tables where table_name=p_table;
 if cfg.table_name is null or not private.coco_module_allowed(cfg.module_id) then return false;end if;
 -- These RPC-only tables have module-wide read contracts. No row contents
 -- enter this index; other private tables never acquire a fallback grant.
 if cfg.table_schema='private' and cfg.table_name in ('surveys','marketing_campaigns','website_public_settings','website_public_inquiries','automation_rules') then return true;end if;
 if cfg.module_id='fleet' then return private.gama_fleet_may();end if;
 if cfg.module_id in ('accounting','sri') and not has_table_privilege(current_user,'public.'||p_table,'SELECT') then
  return private.gama_accounting_may('view') and private.gama_accounting_rights()->>'scope'='all';
 end if;
 if not has_table_privilege(current_user,'public.'||p_table,'SELECT') then return false;end if;
 execute format('select exists(select 1 from %I.%I where %I::text=$1)',cfg.table_schema,p_table,cfg.key_column) into visible using p_id;
 return coalesce(visible,false) or private.current_user_role()='administrador' and not private.coco_history_record_exists(p_table,p_id);
end $$;
revoke all on function private.coco_history_record_visible(text,text,uuid) from public,anon;
grant execute on function private.coco_history_record_visible(text,text,uuid) to authenticated;
create policy coco_module_events_read on private.coco_module_events for select to authenticated using(
 private.coco_module_allowed(module_id) and
 case when record_table is not null then private.coco_history_record_visible(record_table,record_id,record_owner)
 when module_id='hr' then private.hr_admin() or actor_id=auth.uid()
 else true end
);

-- Record only references, action and status. No snapshots, diagnoses, addresses,
-- salaries, bank details, credentials, attachment bodies or free-text HR reasons.
create function private.coco_capture_module_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare cfg private.coco_history_tables;n jsonb:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 before_row jsonb;ref text;author text;actor uuid:=auth.uid();ln jsonb:='[]';refs jsonb:='[]';parent jsonb;
 st text;src jsonb;act text:=lower(tg_op);rid text:=n->>'id';
begin
 select * into cfg from private.coco_history_tables where table_name=tg_table_name and table_schema=tg_table_schema;
 if cfg.table_name is null then return null;end if;
 rid:=n->>cfg.key_column;
 if tg_op='UPDATE' then
  before_row:=to_jsonb(old);
  if (before_row-array['updated_at','version','photo_data','data_url','last_seen_at','last_access_at'])
   is not distinct from (n-array['updated_at','version','photo_data','data_url','last_seen_at','last_access_at']) then return null;end if;
 end if;
 if actor is null then actor:=nullif(coalesce(n->>'updated_by',n->>'created_by',n->>'user_id'),'')::uuid;end if;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=actor;
 ref:=left(coalesce(nullif(n->>'erp_reference',''),nullif(n->>'number',''),nullif(n->>'reference',''),nullif(n->>'code',''),
  case when cfg.module_id not in ('hr','users','access-settings','settings','sri') then coalesce(n->>'title',n->>'name',n->>'plate') end,rid),180);
 if cfg.module_id='hr' then ref:=left(coalesce(n->>'erp_reference',n->>'start_date',n->>'work_date',rid),180);end if;
 st:=case when n->>'status' in ('draft','posted','reversed','pendiente','aprobada','rechazada','cancelada','active','closed','confirmed','cancelled','paid','pending','approved','rejected') then n->>'status' end;
 if tg_op='UPDATE' and st is not null and st is distinct from before_row->>'status' then act:='status';end if;
 ln:=jsonb_build_array(jsonb_build_object('module',cfg.module_id,'action','module','id',rid,'reference',ref));
 if cfg.parent_column is not null and n->>cfg.parent_column is not null then
  execute format('select to_jsonb(t) from public.%I t where id::text=$1',cfg.parent_table) into parent using n->>cfg.parent_column;
  if parent is not null then
   ref:=left(coalesce(parent->>'erp_reference',parent->>'number',parent->>'order_number',parent->>'name',parent->>'title',n->>cfg.parent_column),180);
  end if;
 end if;
 if n->>'product_id' is not null then
  select jsonb_build_array(jsonb_build_object('kind','product','id',p.id,'reference',p.reference,'name',p.name,
    'quantity',case when (n->>'quantity') ~ '^[0-9]+([.][0-9]+)?$' then (n->>'quantity')::numeric end)) into refs from public.products p where p.id::text=n->>'product_id';
 end if;
 if refs='[]'::jsonb or refs is null then refs:=jsonb_build_array(jsonb_build_object('kind','document','id',rid,'reference',ref));end if;
 -- Known business relationships only; no arbitrary routes or external URLs.
 for src in select * from jsonb_array_elements(jsonb_build_array(
  jsonb_build_object('key','customer_id','module','contacts'),jsonb_build_object('key','supplier_id','module','contacts'),
  jsonb_build_object('key','employee_id','module','hr'),jsonb_build_object('key','vehicle_id','module','fleet'),
  jsonb_build_object('key','project_id','module','projects'),jsonb_build_object('key','document_id','module','documents'),
  jsonb_build_object('key','sales_order_id','module','sales-orders'),jsonb_build_object('key','purchase_order_id','module','gamaPurchasesV14'),
  jsonb_build_object('key','entry_id','module','accounting'),jsonb_build_object('key','source_module','module',n->>'source_module')
 )) loop
  if n->>(src->>'key') is not null and exists(select 1 from private.coco_history_modules where module_id=src->>'module') then
   ln:=ln||jsonb_build_array(jsonb_build_object('module',src->>'module','action','module','id',n->>(src->>'key')));
  end if;
 end loop;
 insert into private.coco_module_events(module_id,record_table,record_id,record_owner,type,action,subject,body,reference,actor_id,actor_name,references_list,links,source_type,source_id,source_label)
 values(cfg.module_id,tg_table_name,rid,nullif(n->>'created_by','')::uuid,'action',act,cfg.label,coalesce(st,''),ref,actor,coalesce(author,'AUTHOR_NOT_RECORDED'),refs,ln,
  coalesce(nullif(current_setting('coco.activity_source_type',true),''),'erp'),nullif(current_setting('coco.activity_source_id',true),''),nullif(current_setting('coco.activity_source_label',true),''));
 return null;
end $$;
revoke all on function private.coco_capture_module_event() from public,anon,authenticated;
create function private.coco_history_actor_deleted() returns trigger
language plpgsql security definer set search_path='' as $$begin
 update private.coco_module_events set actor_id=null,actor_name='USER_UNAVAILABLE' where actor_id=old.id;
 update private.coco_module_events set record_owner=null where record_owner=old.id;
 return old;
end $$;
revoke all on function private.coco_history_actor_deleted() from public,anon,authenticated;
create trigger coco_history_actor_deleted before delete on public.profiles for each row execute function private.coco_history_actor_deleted();
do $$declare cfg private.coco_history_tables;begin
 for cfg in select * from private.coco_history_tables loop
  execute format('create trigger coco_module_history after insert or update or delete on %I.%I for each row execute function private.coco_capture_module_event()',cfg.table_schema,cfg.table_name);
 end loop;
end $$;

create function private.coco_module_note(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m text:=p_data->>'module_id';key uuid:=(p_data->>'request_key')::uuid;msg text:=btrim(p_data->>'body');r private.coco_module_events;author text;
begin
 if not private.coco_module_allowed(m) or not private.erp_action_allowed(m,'edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if m='hr' and not private.hr_admin() then raise exception 'ROLE_NOT_ALLOWED';end if;
 if key is null or coalesce(length(msg),0) not between 1 and 10000 then raise exception 'INVALID_MESSAGE';end if;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
 insert into private.coco_module_events(module_id,type,action,subject,body,actor_id,actor_name,request_key)
 values(m,'note','note','',msg,auth.uid(),author,key) on conflict(actor_id,request_key) do nothing returning * into r;
 if r.id is null then select * into r from private.coco_module_events where actor_id=auth.uid() and request_key=key;end if;
 if r.module_id<>m or r.body<>msg or r.type<>'note' then raise exception 'REQUEST_KEY_REUSED';end if;
 return jsonb_build_object('id',r.id);
end $$;
revoke all on function private.coco_module_note(jsonb) from public,anon;
grant execute on function private.coco_module_note(jsonb) to authenticated;

create function public.coco_module_history(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare m text:=p_data->>'module_id';ctx jsonb;items jsonb;off integer:=coalesce((p_data->>'offset')::integer,0);
begin
 if not private.coco_module_allowed(m) then raise exception 'ROLE_NOT_ALLOWED';end if;
 ctx:=jsonb_build_object('kind','module','module_id',m,'number',(select label from private.coco_history_modules where module_id=m),'status','recorded','party','',
 'actor_id',auth.uid(),'can_note',private.erp_action_allowed(m,'edit') and (m<>'hr' or private.hr_admin()),'can_review',false,'stages','[]'::jsonb);
 if p_action='context' then return ctx;end if;
 if p_action='note' then return private.coco_module_note(p_data);end if;
 if p_action<>'list' then raise exception 'INVALID_ACTION';end if;
 if off<0 or off>1000000 then raise exception 'INVALID_OFFSET';end if;
 with visible as materialized(
  select * from private.coco_module_events e where module_id=m
   and (not coalesce((p_data->>'annotations_only')::boolean,false) or e.action='source_linked' or e.type in ('note','proposal') or e.proposal_id is not null)
   and (nullif(p_data->>'record_id','') is null or exists(select 1 from jsonb_array_elements(e.links) l where l->>'module'=m and l->>'id'=p_data->>'record_id'))
 ), grouped as (
  select min(id::text) id,max(created_at) at,actor_id,max(actor_name) actor_name,type,action,subject,body,source_type,source_id,source_label,source_email,proposal_id,
   count(*) action_count,jsonb_agg(references_list) refs,jsonb_agg(links) all_links
  from visible
  group by case when type='action' and proposal_id is null then transaction_id::text else id::text end,record_table,actor_id,type,action,subject,body,source_type,source_id,source_label,source_email,proposal_id
 ), paged as (select *,count(*) over() total from grouped order by at desc,id offset off limit 50)
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'module_id',m,'at',p.at,'actor_id',p.actor_id,'actor_name',p.actor_name,'type',p.type,'action',p.action,'subject',p.subject,'body',p.body,
  'action_count',p.action_count,'source_type',p.source_type,'source_id',p.source_id,'source_label',p.source_label,'source_email',p.source_email,'proposal_id',p.proposal_id,'total',p.total,
  'references',(select coalesce(jsonb_agg(r),'[]') from jsonb_array_elements(p.refs) a cross join lateral jsonb_array_elements(a) r),
  'links',(select coalesce(jsonb_agg(distinct l),'[]') from jsonb_array_elements(p.all_links) a cross join lateral jsonb_array_elements(a) l where private.coco_module_allowed(l->>'module'))
 ) order by p.at desc,p.id),'[]') into items from paged p;
 return jsonb_build_object('context',ctx,'entries','[]'::jsonb,'history',items,'proposals','[]'::jsonb,'portraits','{}'::jsonb);
end $$;
revoke all on function public.coco_module_history(text,jsonb) from public,anon;
grant execute on function public.coco_module_history(text,jsonb) to authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261017141238','universal_module_history','87881f5efe93b34afe7b5991acfb9c172e7f0dc95f5bdfd49b64804f1ae22f62','87881f5efe93b34afe7b5991acfb9c172e7f0dc95f5bdfd49b64804f1ae22f62','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261017141544_module_assistant_proposals.sql; SHA256 5c99f39f97524ae4a071dbc8fb76a2886fe6f79685b5d0b456322979d9710766
-- Typed proposals from the trusted ChatGPT bridge. Ingestion never executes a
-- business action. Existing quote/purchase/TMS mail contracts remain unchanged.
create table private.coco_module_proposals(
 id uuid primary key default gen_random_uuid(),account_id uuid not null references public.profiles on delete cascade,
 module_id text not null references private.coco_history_modules,action text not null check(action in
 ('contact_draft','absence_request','document_create','fuel_log','accounting_entry','record_note')),
 source_type text not null check(source_type in ('mail','chat','file','import')),source_id text not null,
 source_label text not null,source_email text,received_at timestamptz not null,summary text not null,
 payload jsonb not null,status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(),review jsonb,reviewed_by uuid references public.profiles on delete set null,
 reviewed_at timestamptz,review_hash text,decided_at timestamptz,decided_by uuid references public.profiles on delete set null,result jsonb,
 unique(account_id,source_type,source_id,module_id,action),
 check(length(source_id) between 1 and 500 and length(source_label)<=300 and length(summary)<=3000 and octet_length(payload::text)<=60000)
);
create index coco_module_proposals_inbox on private.coco_module_proposals(module_id,status,created_at desc);
create index coco_module_proposals_reviewer on private.coco_module_proposals(reviewed_by);
create index coco_module_proposals_decider on private.coco_module_proposals(decided_by);
create unique index coco_module_source_once on private.coco_module_events(actor_id,source_type,source_id,module_id,record_table,record_id) where action='source_linked';
alter table private.coco_module_proposals enable row level security;
revoke all on private.coco_module_proposals from public,anon,authenticated;
grant select on private.coco_module_proposals to authenticated;

create function private.coco_module_reviewer(m text) returns boolean
language sql stable security definer set search_path='' as $$
 select private.coco_module_allowed(m) and (private.current_user_role()='administrador' or m='hr' and private.hr_admin())
 and private.erp_action_allowed(m,'create') and private.erp_action_allowed(m,'edit')
 and case when m='accounting' then private.gama_accounting_may('create') and private.gama_accounting_may('validate') and private.gama_accounting_rights()->>'scope'='all'
 when m='contacts' then private.erp_module_allowed('crm',array['administrador','comercial']) and private.erp_action_allowed('crm','create')
 else true end
$$;
revoke all on function private.coco_module_reviewer(text) from public,anon;
grant execute on function private.coco_module_reviewer(text) to authenticated;
create policy coco_module_proposals_read on private.coco_module_proposals for select to authenticated using(
 private.coco_module_allowed(module_id) and (account_id=auth.uid() or private.coco_module_reviewer(module_id))
);
-- Proposal summaries/decisions are private to their mailbox and module reviewer.
alter policy coco_module_events_read on private.coco_module_events using(
 private.coco_module_allowed(module_id) and (module_id<>'hr' or private.hr_admin() or actor_id=auth.uid()) and
 (proposal_id is null or exists(select 1 from private.coco_module_proposals p where p.id=proposal_id)) and
 case when record_table is not null then private.coco_history_record_visible(record_table,record_id,record_owner)
 when module_id='hr' then private.hr_admin() or actor_id=auth.uid()
 else true end
);

-- A bounded allowlist strips untrusted fields before they can enter a proposal.
create function private.coco_proposal_payload(a text,p jsonb) returns jsonb
language sql immutable set search_path='' as $$
 select coalesce(jsonb_object_agg(key,value),'{}') from jsonb_each(coalesce(p,'{}')) where key=any(case a
 when 'contact_draft' then array['first_name','last_name','email','phone','job_title','company','customer_id','lead_id']
 when 'absence_request' then array['employee_id','kind','start_date','end_date']
 when 'document_create' then array['title','folder','visibility','customer_id','supplier_id','employee_id','file']
 when 'fuel_log' then array['vehicle_id','logged_on','litres','amount','odometer','station','document_id']
 when 'accounting_entry' then array['journal','entry_date','reference','memo','lines','document_id']
 else array['body'] end)
$$;
revoke all on function private.coco_proposal_payload(text,jsonb) from public,anon,authenticated;

-- Only the bridge can ingest: no sessions, JWT impersonation, arbitrary tables
-- or direct business writes. Account identity is resolved from the verified app.
create function private.coco_source_employee(p_email text) returns uuid
language sql stable security definer set search_path='' as $$
 select case when count(distinct e.id)=1 then min(e.id::text)::uuid end from public.hr_employees e
 left join public.hr_employee_private d on d.employee_id=e.id left join auth.users u on u.id=e.profile_id
 where e.active and p_email is not null and (lower(btrim(d.email))=p_email or lower(btrim(u.email))=p_email)
$$;
revoke all on function private.coco_source_employee(text) from public,anon,authenticated;
create function private.coco_assistant_bridge(p_action text,p_data jsonb) returns jsonb
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
 if a not in ('contact_draft','absence_request','document_create','fuel_log','accounting_entry','record_note')
 or a='contact_draft' and m<>'contacts' or a='absence_request' and m<>'hr' or a='document_create' and m<>'documents'
 or a='fuel_log' and m<>'fleet' or a='accounting_entry' and m<>'accounting' then raise exception 'INVALID_PROPOSAL_ACTION';end if;
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
create function public.coco_assistant_bridge(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.coco_assistant_bridge(p_action,p_data)$$;
revoke all on function public.coco_assistant_bridge(text,jsonb) from public,anon,authenticated;
grant execute on function public.coco_assistant_bridge(text,jsonb) to service_role;

-- A real reviewer sees editable fields and a server-built readable preview.
-- Accounting and fleet keep their existing transaction and period checks.
create function private.coco_module_validate(p private.coco_module_proposals,raw jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d jsonb:=private.coco_proposal_payload(p.action,raw);details jsonb:='[]';x jsonb;debit numeric:=0;credit numeric:=0;v text;obj jsonb;
begin
 if not private.coco_module_reviewer(p.module_id) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p.action='record_note' then
  if coalesce(length(btrim(d->>'body')),0) not between 1 and 10000 then raise exception 'INVALID_MESSAGE';end if;
  return jsonb_build_object('payload',d,'details',jsonb_build_array(d->>'body'));
 elsif p.action='contact_draft' then
  d:=d||jsonb_build_object('email',lower(btrim(d->>'email')));
  if coalesce(length(concat_ws('',nullif(btrim(d->>'first_name'),''),nullif(btrim(d->>'last_name'),''))),0)=0 or d->>'email' !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then raise exception 'CONTACT_INVALID_DATA';end if;
  if exists(select 1 from public.crm_contacts where active and lower(btrim(email))=d->>'email' union all select 1 from public.crm_leads where active and lower(btrim(email))=d->>'email'
   union all select 1 from public.customers where lower(btrim(email))=d->>'email' union all select 1 from public.suppliers where lower(btrim(email))=d->>'email') then raise exception 'CONTACT_EXISTS';end if;
  if nullif(d->>'customer_id','') is not null then
   select name into v from public.customers where id=(d->>'customer_id')::uuid and active;if not found then raise exception 'CONTACT_INVALID_PARENT';end if;
  elsif nullif(d->>'lead_id','') is not null then
   select coalesce(company,concat_ws(' ',first_name,last_name)) into v from public.crm_leads where id=(d->>'lead_id')::uuid and active;if not found then raise exception 'CONTACT_INVALID_PARENT';end if;
  else v:=coalesce(nullif(d->>'company',''),concat_ws(' ',d->>'first_name',d->>'last_name'));end if;
  details:=jsonb_build_array(concat_ws(' ',d->>'first_name',d->>'last_name'),d->>'email',d->>'phone',v);
 elsif p.action='absence_request' then
  select full_name into v from public.hr_employees where id=(d->>'employee_id')::uuid and active;
  if not found or not private.hr_admin() then raise exception 'ROLE_NOT_ALLOWED';end if;
  if d->>'kind' not in ('vacaciones','enfermedad','permiso','formacion','otro') or nullif(d->>'start_date','') is null or nullif(d->>'end_date','') is null
  or (d->>'end_date')::date<(d->>'start_date')::date then raise exception 'INVALID_ABSENCE';end if;
  if exists(select 1 from public.hr_absences where employee_id=(d->>'employee_id')::uuid and status not in ('rechazada','cancelada') and start_date<=(d->>'end_date')::date and end_date>=(d->>'start_date')::date) then raise exception 'ABSENCE_OVERLAP';end if;
  details:=jsonb_build_array(v,d->>'kind',(d->>'start_date')||' → '||(d->>'end_date'),'pendiente');
 elsif p.action='document_create' then
  if coalesce(length(btrim(d->>'title')),0) not between 1 and 200 or coalesce(d->>'visibility','management') not in ('team','management','hr') then raise exception 'INVALID_DOCUMENT';end if;
  if d->>'visibility'='hr' and not private.hr_admin() then raise exception 'ROLE_NOT_ALLOWED';end if;
  if d->'file' is null or not exists(select 1 from storage.objects o where o.bucket_id='business-documents' and o.name=d->'file'->>'storage_path'
    and o.name like auth.uid()::text||'/%') then raise exception 'DOCUMENT_FILE_MISSING';end if;
  if coalesce((d->'file'->>'file_size')::bigint,0) not between 1 and 20000000 or coalesce(length(d->'file'->>'filename'),0) not between 1 and 255 then raise exception 'INVALID_DOCUMENT_FILE';end if;
  d:=d||jsonb_build_object('visibility',coalesce(d->>'visibility','management'));
  details:=jsonb_build_array(d->>'title',d->>'folder',d->>'visibility',d->'file'->>'filename');
 elsif p.action='fuel_log' then
  select plate into v from public.fleet_vehicles where id=(d->>'vehicle_id')::uuid and active;
  if not found or nullif(d->>'logged_on','') is null or coalesce((d->>'litres')::numeric,0)<=0 or coalesce((d->>'amount')::numeric,-1)<0 or coalesce((d->>'odometer')::numeric,-1)<0 then raise exception 'INVALID_FUEL_LOG';end if;
  details:=jsonb_build_array(v,d->>'logged_on',(d->>'litres')||' L',d->>'amount',d->>'station');
 elsif p.action='accounting_entry' then
  if nullif(d->>'entry_date','') is null or not exists(select 1 from public.accounting_journals where code=d->>'journal' and active) then raise exception 'INVALID_JOURNAL';end if;
  if not private.gama_accounting_period_open((d->>'entry_date')::date) then raise exception 'PERIOD_CLOSED';end if;
  if jsonb_typeof(d->'lines') is distinct from 'array' or jsonb_array_length(d->'lines') not between 2 and 200 then raise exception 'INVALID_LINES';end if;
  for x in select * from jsonb_array_elements(d->'lines') loop
   select code||' · '||name into v from public.accounting_accounts where id=(x->>'account_id')::uuid and active;
   if not found or coalesce((x->>'debit')::numeric,0)<0 or coalesce((x->>'credit')::numeric,0)<0 or ((coalesce((x->>'debit')::numeric,0)>0)=(coalesce((x->>'credit')::numeric,0)>0)) then raise exception 'INVALID_LINES';end if;
   debit:=debit+round(coalesce((x->>'debit')::numeric,0),2);credit:=credit+round(coalesce((x->>'credit')::numeric,0),2);
   details:=details||jsonb_build_array(v||' · D '||coalesce(x->>'debit','0')||' / C '||coalesce(x->>'credit','0'));
  end loop;
  if debit=0 or debit<>credit then raise exception 'ENTRY_UNBALANCED';end if;
  details:=jsonb_build_array(d->>'journal',d->>'entry_date',d->>'reference')||details;
 end if;
 return jsonb_build_object('payload',d,'details',details);
end $$;
revoke all on function private.coco_module_validate(private.coco_module_proposals,jsonb) from public,anon,authenticated;

create function private.coco_module_proposal_action(p_action text,p_data jsonb) returns jsonb
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
  if p.action='contact_draft' then
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
  v_result:=jsonb_build_object('module',p.module_id,'id',rid,'action',p.action);
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

-- Add proposal context/list/review without changing the activity read's invoker.
alter function public.coco_module_history(text,jsonb) rename to coco_module_history_events;
revoke all on function public.coco_module_history_events(text,jsonb) from public,anon;
create function public.coco_module_history(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare r jsonb;m text:=p_data->>'module_id';opts jsonb:='{}';
begin
 if not private.coco_module_allowed(m) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('review_proposal','approve_proposal','reject_proposal') then return private.coco_module_proposal_action(p_action,p_data);end if;
 if p_action='proposal_options' then
  if not private.coco_module_reviewer(m) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if m='hr' then opts:=jsonb_build_object('employees',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',full_name) order by full_name),'[]') from public.hr_employees where active));
  elsif m='fleet' then opts:=jsonb_build_object('vehicles',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',plate) order by plate),'[]') from public.fleet_vehicles where active));
  elsif m='contacts' then opts:=jsonb_build_object('customers',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',name) order by name),'[]') from public.customers where active),
   'leads',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',coalesce(company,concat_ws(' ',first_name,last_name))) order by created_at desc),'[]') from public.crm_leads where active));
  elsif m='accounting' then opts:=jsonb_build_object('journals',(select coalesce(jsonb_agg(jsonb_build_object('id',code,'label',code||' · '||name) order by code),'[]') from public.accounting_journals where active),
   'accounts',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',code||' · '||name) order by code),'[]') from public.accounting_accounts where active),
   'financial_accounts',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',name) order by name),'[]') from public.financial_accounts where active));end if;
  return opts;
 end if;
 r:=public.coco_module_history_events(p_action,p_data);
 if p_action='list' then
  -- Other successful actions from the same real source remain one click away.
  r:=jsonb_set(r,'{history}',(select coalesce(jsonb_agg(e||jsonb_build_object('links',coalesce(e->'links','[]')||coalesce((
   select jsonb_agg(jsonb_build_object('module',p.module_id,'action','module','id',p.result->>'id')) from private.coco_module_proposals p
   where e->>'source_id' is not null and p.source_id=e->>'source_id' and p.source_type=e->>'source_type' and p.status='approved' and p.result->>'id' is not null
   and p.account_id=coalesce((select o.account_id from private.coco_module_proposals o where o.id=(e->>'proposal_id')::uuid),(e->>'actor_id')::uuid)
   and p.module_id<>m and private.coco_module_allowed(p.module_id)
  ),'[]'::jsonb)) order by h.n),'[]') from jsonb_array_elements(r->'history') with ordinality h(e,n)));
  r:=jsonb_set(r,'{proposals}',(select coalesce(jsonb_agg((to_jsonb(p)-array['account_id','review','review_hash','reviewed_by','reviewed_at'])||jsonb_build_object('can_review',private.coco_module_reviewer(m))),'[]') from private.coco_module_proposals p where p.module_id=m and
   p.id in (select (x->>'proposal_id')::uuid from jsonb_array_elements(r->'history') x where x->>'proposal_id' is not null)));
 end if;
 if p_action in ('context','list') then
  if p_action='context' then return r||jsonb_build_object('can_review',private.coco_module_reviewer(m));end if;
  r:=jsonb_set(r,'{context,can_review}',to_jsonb(private.coco_module_reviewer(m)));
 end if;
 return r;
end $$;
revoke all on function public.coco_module_history(text,jsonb) from public,anon;
grant execute on function public.coco_module_history(text,jsonb) to authenticated;

-- Keep the established dossier APIs while exposing new source annotations in
-- their existing panel. Canonical sales/purchase/TMS actions are not duplicated.
create or replace function public.coco_dossier(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare r jsonb;extra jsonb;items jsonb;m text;oid text:=p_data->>'order_id';
begin
 r:=private.coco_dossier(p_action,p_data);
 if p_action<>'list' then return r;end if;
 m:=case p_data->>'kind' when 'sales' then 'sales-orders' when 'quote' then 'quotes' when 'purchase' then 'gamaPurchasesV14' when 'tms' then 'tms' end;
 if m is null or not private.coco_module_allowed(m) then return r;end if;
 extra:=public.coco_module_history('list',jsonb_build_object('module_id',m,'annotations_only',true,'record_id',oid,'offset',coalesce((p_data->>'offset')::integer,0)));
 select coalesce(jsonb_agg(e order by e->>'at' desc,e->>'id'),'[]') into items from jsonb_array_elements(extra->'history') e
 where (e->>'action'='source_linked' or e->>'type' in ('note','proposal') or e->>'proposal_id' is not null)
 and (oid is null or exists(select 1 from jsonb_array_elements(e->'links') l where l->>'module'=m and l->>'id'=oid));
 r:=jsonb_set(r,'{history}',coalesce(r->'history','[]')||items);
 r:=jsonb_set(r,'{proposals}',coalesce(r->'proposals','[]')||coalesce((select jsonb_agg(p) from jsonb_array_elements(extra->'proposals') p
  where p->>'id' in (select e->>'proposal_id' from jsonb_array_elements(items) e)),'[]'));
 return r;
end $$;
revoke all on function public.coco_dossier(text,jsonb) from public,anon;
grant execute on function public.coco_dossier(text,jsonb) to authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261017141544','module_assistant_proposals','5c99f39f97524ae4a071dbc8fb76a2886fe6f79685b5d0b456322979d9710766','5c99f39f97524ae4a071dbc8fb76a2886fe6f79685b5d0b456322979d9710766','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261017173152_optimize_module_history_policies.sql; SHA256 6768a740d28bab6495512f3ac55476b5e2f9a3dba37d3065f4f769b489362788
-- Cache the request actor once per statement; keep record visibility and module
-- permissions correlated with each row. The catalog also supports FK lookups.
create index coco_history_tables_module on private.coco_history_tables(module_id);

alter policy coco_module_proposals_read on private.coco_module_proposals using(
 private.coco_module_allowed(module_id) and (account_id=(select auth.uid()) or private.coco_module_reviewer(module_id))
);

alter policy coco_module_events_read on private.coco_module_events using(
 private.coco_module_allowed(module_id) and (module_id<>'hr' or private.hr_admin() or actor_id=(select auth.uid())) and
 (proposal_id is null or exists(select 1 from private.coco_module_proposals p where p.id=proposal_id)) and
 case when record_table is not null then private.coco_history_record_visible(record_table,record_id,record_owner)
 when module_id='hr' then private.hr_admin() or actor_id=(select auth.uid())
 else true end
);

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261017173152','optimize_module_history_policies','6768a740d28bab6495512f3ac55476b5e2f9a3dba37d3065f4f769b489362788','6768a740d28bab6495512f3ac55476b5e2f9a3dba37d3065f4f769b489362788','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
