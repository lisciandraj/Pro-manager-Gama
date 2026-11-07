-- Add the user-facing Odoo contact fields without replacing native role data.
-- Existing RLS, entity identity, fiscal validation and document snapshots stay authoritative.
alter table private.coco_contact_entities
 add column mobile text check(length(mobile)<=80),
 add column title text check(length(title)<=80),
 add column street2 text check(length(street2)<=500),
 add column company_registry text check(length(company_registry)<=120),
 add column ref text check(length(ref)<=120),
 add column image_url text check(image_url is null or (length(image_url)<=2000 and image_url ~ '^https?://[^[:space:]/@]+(/[^[:space:]]*)?$')),
 add column salesperson_id uuid references public.profiles(id) on delete set null;
create index coco_contact_salesperson_idx on private.coco_contact_entities(salesperson_id) where salesperson_id is not null;
grant update(mobile,title,street2,company_registry,ref,image_url,salesperson_id) on private.coco_contact_entities to authenticated;

-- Trigger-only validation sees every linked role, including one hidden by the
-- caller's RLS. It never performs a privileged business write.
create function private.coco_contact_odoo_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare tbl text;mod text;action_module text;linked boolean;fresh boolean;begin
 if row(new.mobile,new.title,new.street2,new.company_registry,new.ref,new.image_url,new.salesperson_id,new.nature,new.tags)
  is not distinct from row(old.mobile,old.title,old.street2,old.company_registry,old.ref,old.image_url,old.salesperson_id,old.nature,old.tags) then return new;end if;
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
revoke all on function private.coco_contact_odoo_guard() from public,anon,authenticated,service_role;
create trigger coco_contact_odoo_guard before update on private.coco_contact_entities for each row execute function private.coco_contact_odoo_guard();

-- Preserve the existing transactional save as an invoker-only implementation.
-- It still validates every native key, action, version and parent relationship.
alter function public.coco_contact_save(text,uuid,jsonb,integer) set schema private;
alter function private.coco_contact_save(text,uuid,jsonb,integer) rename to coco_contact_save_native;
revoke all on function private.coco_contact_save_native(text,uuid,jsonb,integer) from public,anon,service_role;
grant execute on function private.coco_contact_save_native(text,uuid,jsonb,integer) to authenticated;
create function public.coco_contact_save(p_kind text,p_id uuid default null,p_data jsonb default '{}',p_version integer default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare extra jsonb;patch jsonb:='{}';item record;k text;result jsonb;eid uuid;sets text;begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>20000 then raise exception 'CONTACT_INVALID_DATA';end if;
 if p_data ? 'odoo' then
  extra:=p_data->'odoo';
  if jsonb_typeof(extra)<>'object' then raise exception 'CONTACT_INVALID_DATA';end if;
  for item in select * from jsonb_each(extra) loop
   k:=item.key;
   if k not in ('mobile','title','street2','company_registry','ref','image_url','salesperson_id','nature','tags') then raise exception 'CONTACT_INVALID_DATA';end if;
   if k='tags' then
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
  eid:=(result#>>'{profile,id}')::uuid;
  select string_agg(format('%I=(jsonb_populate_record(null::private.coco_contact_entities,$1)).%I',key,key),',') into sets from jsonb_object_keys(patch) key;
  execute format('update private.coco_contact_entities set %s where id=$2',sets) using patch,eid;
 end if;
 return public.coco_contact_record(p_kind,(result#>>'{record,id}')::uuid);
end $$;
revoke all on function public.coco_contact_save(text,uuid,jsonb,integer) from public,anon,service_role;
grant execute on function public.coco_contact_save(text,uuid,jsonb,integer) to authenticated;

-- A child inheriting an address reads the parent's complement, never its own
-- stale complement. A parent inaccessible under existing RLS is not projected.
alter function public.coco_contact_record(text,uuid) set schema private;
alter function private.coco_contact_record(text,uuid) rename to coco_contact_record_native;
revoke all on function private.coco_contact_record_native(text,uuid) from public,anon,service_role;
grant execute on function private.coco_contact_record_native(text,uuid) to authenticated;
create function public.coco_contact_record(p_kind text,p_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;parent_entity uuid;complement text;begin
 result:=private.coco_contact_record_native(p_kind,p_id);
 if result->'inherited_address'<>'null'::jsonb then
  if result#>>'{inherited_address,kind}'='clients' then
   select contact_entity_id into parent_entity from public.customers where id=(result#>>'{inherited_address,id}')::uuid;
  elsif result#>>'{inherited_address,kind}'='leads' then
   select contact_entity_id into parent_entity from public.crm_leads where id=(result#>>'{inherited_address,id}')::uuid;
  end if;
  select street2 into complement from private.coco_contact_entities where id=parent_entity;
  result:=jsonb_set(result,'{inherited_address,street2}',coalesce(to_jsonb(complement),'null'));
 end if;
 return result;
end $$;
revoke all on function public.coco_contact_record(text,uuid) from public,anon,service_role;
grant execute on function public.coco_contact_record(text,uuid) to authenticated;

-- Keep field values and image URLs out of module history. Events reference the
-- existing native rows so visibility follows their original RLS and module.
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column)
 values('coco_contact_entities','contacts','Perfil de contacto','private','id');
create function private.coco_contact_odoo_history() returns trigger
language plpgsql security definer set search_path='' as $$
declare fields jsonb;tbl text;mod text;r record;author text;ref text;begin
 select jsonb_agg(jsonb_build_object('field',k,'changed',true) order by k) into fields
 from unnest(array['mobile','title','street2','company_registry','ref','image_url','salesperson_id','nature','tags']) k
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
revoke all on function private.coco_contact_odoo_history() from public,anon,authenticated,service_role;
create trigger coco_contact_odoo_history after update on private.coco_contact_entities for each row execute function private.coco_contact_odoo_history();
notify pgrst,'reload schema';
