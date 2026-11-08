
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
