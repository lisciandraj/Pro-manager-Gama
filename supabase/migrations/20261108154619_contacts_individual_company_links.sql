-- Distinguish individuals and companies while retaining native business roles.
-- No contact is reclassified and no business data is rewritten by this migration.
create index coco_contact_employee_parent_idx on private.coco_contact_entities(parent_id)
 where relation='employee' and parent_id is not null;

-- Small caller-scoped references: native RLS and module gates filter every role.
create function private.coco_contact_entity_summary(p_entity uuid,p_active_only boolean default false)
returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('entity_id',p_entity,'kind',r.kind,'id',r.id,'name',r.name)
 from (
  select 'clients'::text kind,c.id,c.name,c.active,1 priority from public.customers c
   where c.contact_entity_id=p_entity and private.erp_module_allowed('contacts',array['administrador','comercial'])
  union all
  select 'suppliers',s.id,s.name,s.active,2 from public.suppliers s
   where s.contact_entity_id=p_entity and private.erp_module_allowed('contacts',array['administrador','comercial'])
  union all
  select 'leads',l.id,coalesce(nullif(l.company,''),nullif(concat_ws(' ',l.first_name,l.last_name),''),'—'),l.active,3 from public.crm_leads l
   where l.contact_entity_id=p_entity and private.erp_module_allowed('crm',array['administrador','comercial'])
 ) r where not p_active_only or r.active order by r.active desc,r.priority,r.id limit 1
$$;
revoke all on function private.coco_contact_entity_summary(uuid,boolean) from public,anon,service_role;
grant execute on function private.coco_contact_entity_summary(uuid,boolean) to authenticated;

create function private.coco_contact_company(p_entity uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare e private.coco_contact_entities;k public.crm_contacts;result jsonb;begin
 select * into e from private.coco_contact_entities where id=p_entity;
 if not found then return null;end if;
 if e.relation='employee' and e.parent_id is not null then
  if exists(select 1 from private.coco_contact_entities where id=e.parent_id and nature='company') then
   return private.coco_contact_entity_summary(e.parent_id);
  end if;
  return null;
 end if;
 -- The CRM keeps its original customer/prospect parent, including legacy
 -- parents whose nature has not yet been classified by a user.
 if private.erp_module_allowed('crm',array['administrador','comercial']) then
  select * into k from public.crm_contacts where contact_entity_id=p_entity;
  if k.customer_id is not null and private.erp_module_allowed('contacts',array['administrador','comercial']) then
   select jsonb_build_object('entity_id',c.contact_entity_id,'kind','clients','id',c.id,'name',c.name)
    into result from public.customers c where c.id=k.customer_id;
  elsif k.lead_id is not null then
   select jsonb_build_object('entity_id',l.contact_entity_id,'kind','leads','id',l.id,'name',coalesce(nullif(l.company,''),nullif(concat_ws(' ',l.first_name,l.last_name),''),'—'))
    into result from public.crm_leads l where l.id=k.lead_id;
  end if;
 end if;
 return result;
end $$;
revoke all on function private.coco_contact_company(uuid) from public,anon,service_role;
grant execute on function private.coco_contact_company(uuid) to authenticated;

-- Trigger-only integrity guard covers the main editor, shared-profile editor
-- and direct permitted updates. It performs no privileged business write.
create function private.coco_contact_company_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare company_nature text;begin
 if row(new.nature,new.parent_id,new.relation) is not distinct from row(old.nature,old.parent_id,old.relation) then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended('coco-contact-parent-graph',0));
 if new.nature is distinct from old.nature and new.nature is distinct from 'person'
  and exists(select 1 from public.crm_contacts where contact_entity_id=new.id) then raise exception 'CONTACT_PERSON_REQUIRED';end if;
 if new.nature is distinct from 'company' and exists(select 1 from private.coco_contact_entities where parent_id=new.id and relation='employee') then
  raise exception 'CONTACT_COMPANY_HAS_PEOPLE';
 end if;
 if new.relation='employee' and new.parent_id is not null then
  if new.nature is distinct from 'person' then raise exception 'CONTACT_COMPANY_REQUIRED';end if;
  select nature into company_nature from private.coco_contact_entities where id=new.parent_id;
  if new.parent_id=new.id or company_nature is distinct from 'company' then raise exception 'CONTACT_INVALID_COMPANY';end if;
  -- An existing archived association can still be read and edited. A newly
  -- selected company must have at least one active operational role.
  if row(new.parent_id,new.relation) is distinct from row(old.parent_id,old.relation)
   and not (exists(select 1 from public.customers where contact_entity_id=new.parent_id and active)
    or exists(select 1 from public.suppliers where contact_entity_id=new.parent_id and active)
    or exists(select 1 from public.crm_leads where contact_entity_id=new.parent_id and active)) then raise exception 'CONTACT_INVALID_COMPANY';end if;
 end if;
 return new;
end $$;
revoke all on function private.coco_contact_company_guard() from public,anon,authenticated,service_role;
create trigger coco_contact_company_guard before update on private.coco_contact_entities
 for each row execute function private.coco_contact_company_guard();

create or replace function private.coco_contact_odoo_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare tbl text;mod text;action_module text;linked boolean;fresh boolean;begin
 if row(new.mobile,new.title,new.street2,new.company_registry,new.ref,new.image_url,new.salesperson_id,new.nature,new.tags,new.parent_id,new.relation)
  is not distinct from row(old.mobile,old.title,old.street2,old.company_registry,old.ref,old.image_url,old.salesperson_id,old.nature,old.tags,old.parent_id,old.relation) then return new;end if;
 if not private.coco_contact_system_writer() then
  if auth.uid() is null or not private.coco_contact_access(new.id,true) then raise exception 'CONTACT_ACCESS_DENIED';end if;
  -- created_at is server-owned and has no application UPDATE grant. xmin also
  -- proves this profile was created in this transaction, so create-only users
  -- may finish a new profile without acquiring edit rights on existing ones.
  select old.created_at=transaction_timestamp() and e.xmin::text=(txid_current()%4294967296)::text into fresh
   from private.coco_contact_entities e where id=old.id;
  foreach tbl in array array['customers','suppliers','crm_leads','crm_contacts'] loop
   execute format('select exists(select 1 from public.%I where contact_entity_id=$1)',tbl) into linked using new.id;
   if not linked then continue;end if;
   mod:=case when tbl in ('customers','suppliers') then 'contacts' else 'crm' end;
   action_module:=case tbl when 'customers' then 'clients' when 'suppliers' then 'suppliers' else 'crm' end;
   if not private.erp_module_allowed(mod,array['administrador','comercial']) or not private.erp_action_allowed(action_module,case when fresh then 'create' else 'edit' end) then
    raise exception 'CONTACT_LINKED_ACCESS_REQUIRED';
   end if;
  end loop;
  if new.salesperson_id is distinct from old.salesperson_id then
   if not private.erp_module_allowed('crm',array['administrador','comercial']) then raise exception 'CONTACT_SALESPERSON_ACCESS_DENIED';end if;
   if new.salesperson_id is not null and not exists(select 1 from public.crm_team where id=new.salesperson_id) then raise exception 'CONTACT_INVALID_SALESPERSON';end if;
  end if;
 end if;
 return new;
end $$;

create or replace function private.coco_contact_odoo_history() returns trigger
language plpgsql security definer set search_path='' as $$
declare fields jsonb;tbl text;mod text;r record;author text;ref text;begin
 select jsonb_agg(jsonb_build_object('field',k,'changed',true) order by k) into fields
 from unnest(array['mobile','title','street2','company_registry','ref','image_url','salesperson_id','nature','tags','parent_id','relation']) k
 where to_jsonb(new)->k is distinct from to_jsonb(old)->k;
 if fields is null then return null;end if;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
 foreach tbl in array array['customers','suppliers','crm_leads','crm_contacts'] loop
  mod:=case when tbl in ('customers','suppliers') then 'contacts' else 'crm' end;
  for r in execute format('select id,to_jsonb(t) data from public.%I t where contact_entity_id=$1',tbl) using new.id loop
   ref:=left(coalesce(r.data->>'name',r.data->>'company',nullif(concat_ws(' ',r.data->>'first_name',r.data->>'last_name'),''),r.id::text),180);
   insert into private.coco_module_events(module_id,record_table,record_id,type,action,subject,reference,actor_id,actor_name,references_list,links,source_type,source_id,source_label)
   values(mod,tbl,r.id::text,'action','update','Perfil de contacto',ref,auth.uid(),coalesce(author,'AUTHOR_NOT_RECORDED'),
    jsonb_build_array(jsonb_build_object('kind','document','id',r.id,'reference',ref,'record_id',r.id,'record_table',tbl,'context',jsonb_build_object('changes',fields))),
    jsonb_build_array(jsonb_build_object('module',mod,'action','module','id',r.id,'reference',ref)),
    coalesce(nullif(current_setting('coco.activity_source_type',true),''),'erp'),nullif(current_setting('coco.activity_source_id',true),''),nullif(current_setting('coco.activity_source_label',true),''));
  end loop;
 end loop;
 return null;
end $$;

create or replace function public.coco_contact_save(p_kind text,p_id uuid default null,p_data jsonb default '{}',p_version integer default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare extra jsonb;patch jsonb:='{}';item record;k text;result jsonb;eid uuid;sets text;begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>20000 then raise exception 'CONTACT_INVALID_DATA';end if;
 if p_data ? 'odoo' then
  extra:=p_data->'odoo';
  if jsonb_typeof(extra)<>'object' then raise exception 'CONTACT_INVALID_DATA';end if;
  for item in select * from jsonb_each(extra) loop
   k:=item.key;
   if k not in ('mobile','title','street2','company_registry','ref','image_url','salesperson_id','nature','tags','parent_id') then raise exception 'CONTACT_INVALID_DATA';end if;
   if k='parent_id' then
    if p_kind not in ('clients','suppliers') then raise exception 'CONTACT_INVALID_DATA';end if;
    if jsonb_typeof(item.value) not in ('null','string') then raise exception 'CONTACT_INVALID_DATA';end if;
    begin
     patch:=patch||jsonb_build_object('parent_id',nullif(btrim(item.value#>>'{}'),'')::uuid,
      'relation',case when nullif(btrim(item.value#>>'{}'),'') is not null then 'employee' end);
    exception when invalid_text_representation then raise exception 'CONTACT_INVALID_COMPANY';end;
   elsif k='tags' then
    if item.value='null'::jsonb then patch:=patch||'{"tags":[]}';
    else
     if jsonb_typeof(item.value)<>'array' then raise exception 'CONTACT_INVALID_DATA';end if;
     if exists(select 1 from jsonb_array_elements(item.value) x where jsonb_typeof(x)<>'string' or length(x#>>'{}')>120) then raise exception 'CONTACT_INVALID_DATA';end if;
     patch:=patch||jsonb_build_object(k,(select coalesce(jsonb_agg(v order by v),'[]') from (select distinct btrim(value) v from jsonb_array_elements_text(item.value) where btrim(value)<>'') tags));
    end if;
   else
    if jsonb_typeof(item.value) not in ('null','string') then raise exception 'CONTACT_INVALID_DATA';end if;
    patch:=patch||jsonb_build_object(k,nullif(btrim(item.value#>>'{}'),''));
   end if;
  end loop;
 end if;
 result:=private.coco_contact_save_native(p_kind,p_id,p_data-'odoo',p_version);
 if patch<>'{}' then
  if patch->>'parent_id' is not null and private.coco_contact_entity_summary((patch->>'parent_id')::uuid,true) is null then
   raise exception 'CONTACT_INVALID_COMPANY';
  end if;
  eid:=(result#>>'{profile,id}')::uuid;
  select string_agg(format('%I=(jsonb_populate_record(null::private.coco_contact_entities,$1)).%I',key,key),',') into sets from jsonb_object_keys(patch) key;
  execute format('update private.coco_contact_entities set %s where id=$2',sets) using patch,eid;
 end if;
 return public.coco_contact_record(p_kind,(result#>>'{record,id}')::uuid);
end $$;
revoke all on function public.coco_contact_save(text,uuid,jsonb,integer) from public,anon,service_role;
grant execute on function public.coco_contact_save(text,uuid,jsonb,integer) to authenticated;


-- Enrich the existing hub without replacing any actions or access checks.
alter function public.coco_contact_hub(text,uuid,text,jsonb) set schema private;
alter function private.coco_contact_hub(text,uuid,text,jsonb) rename to coco_contact_hub_native;
revoke all on function private.coco_contact_hub_native(text,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.coco_contact_hub_native(text,uuid,text,jsonb) to authenticated;
create function public.coco_contact_hub(p_kind text,p_id uuid,p_action text default 'get',p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare result jsonb;children jsonb;eid uuid;begin
 result:=private.coco_contact_hub_native(p_kind,p_id,p_action,p_data);
 eid:=(result#>>'{profile,id}')::uuid;
 if eid is null then return result;end if;
 select coalesce(jsonb_agg(r.ref||jsonb_build_object('nature',e.nature,'active',exists(select 1 from public.customers c where c.contact_entity_id=e.id and c.active) or exists(select 1 from public.suppliers s where s.contact_entity_id=e.id and s.active)) order by lower(r.ref->>'name'),e.id),'[]')
  into children from private.coco_contact_entities e
  cross join lateral (select private.coco_contact_entity_summary(e.id) ref) r
  where e.parent_id=eid and e.relation='employee' and r.ref is not null;
 return result||jsonb_build_object('nature',result#>'{profile,nature}','company',private.coco_contact_company(eid),'related_contacts',children);
end $$;
revoke all on function public.coco_contact_hub(text,uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.coco_contact_hub(text,uuid,text,jsonb) to authenticated;

create or replace function public.coco_contact_directory(p_data jsonb default '{}') returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;pg integer:=least(1000000,greatest(0,coalesce((p_data->>'page')::integer,0)));sz integer:=least(100,greatest(1,coalesce((p_data->>'pageSize')::integer,20)));begin
 if auth.uid() is null or not private.erp_internal_account() or not private.erp_mfa_ok() or nullif(auth.jwt()->>'client_id','') is not null then raise exception 'ACCESS_DENIED';end if;
 if not (private.erp_module_allowed('contacts',array['administrador','comercial']) or private.erp_module_allowed('crm',array['administrador','comercial'])) then raise exception 'ACCESS_DENIED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or length(coalesce(p_data->>'search',''))>512 or coalesce(p_data->>'nature','') not in ('','person','company') then raise exception 'INVALID_DATA';end if;
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
  select g.*,e.tags,e.nature,private.coco_contact_company(e.id) company from grouped g join private.coco_contact_entities e on e.id=g.eid
  where (coalesce(p_data->>'nature','')='' or e.nature=p_data->>'nature')
   and (coalesce(p_data->>'kind','')='' or exists(select 1 from jsonb_array_elements(g.roles) r where r->>'kind'=p_data->>'kind'))
   and (coalesce(p_data->>'quality','') not in ('email','phone') or nullif(primary_row->>(p_data->>'quality'),'') is null)
   and not exists(select 1 from regexp_split_to_table(lower(btrim(coalesce(p_data->>'search',''))),'\s+') term where term<>'' and strpos(translate(lower(g.haystack||' '||array_to_string(e.tags,' ')||' '||coalesce(private.coco_contact_company(e.id)->>'name','')),'áàâäãåéèêëíìîïóòôöõúùûüñç','aaaaaaeeeeiiiiooooouuuunc'),translate(term,'áàâäãåéèêëíìîïóòôöõúùûüñç','aaaaaaeeeeiiiiooooouuuunc'))=0)
 ), filtered as (
  select *,primary_row||jsonb_build_object('roles',roles,'entity_id',eid,'tags',tags,'nature',nature,'company',company) item from selected
  where case when coalesce(p_data->>'kind','')='' then active=not coalesce((p_data->>'archived')::boolean,false)
   else exists(select 1 from jsonb_array_elements(roles) r where r->>'kind'=p_data->>'kind' and (r->>'active')::boolean=not coalesce((p_data->>'archived')::boolean,false)) end
 ), sortable as (
  select *,case p_data->>'sort'
   when 'nature' then nature when 'company' then company->>'name'
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


notify pgrst,'reload schema';
