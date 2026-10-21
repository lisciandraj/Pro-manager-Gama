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

