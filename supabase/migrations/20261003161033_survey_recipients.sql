-- Recipient selection prepares personal invitations; opening a mail composer is not delivery.
create function private.gama_survey_recipients(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_items jsonb;v_total bigint;v_row jsonb;v_inv jsonb;v_out jsonb:='[]';v_seen text[]:='{}';v_email text;v_label text;v_sid uuid;
 v_off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),1000000));v_term text:=left(coalesce(p_data->>'search',''),100);v_kind text:=coalesce(p_data->>'kind','');
begin
 if auth.uid() is null or not private.erp_module_allowed('surveys',array['administrador','comercial']) or not private.erp_module_allowed('contacts',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'SURVEY_ACCESS_DENIED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>18000 then raise exception 'SURVEY_INVALID_DATA';end if;
 if p_action='search' then
  with recipients as (
   select c.id,'customer' kind,c.name label,coalesce(c.email,'') email from public.customers c where c.active
   union all select s.id,'supplier',s.name,coalesce(s.email,'') from public.suppliers s where s.active
   union all select c.id,'contact',coalesce(nullif(btrim(coalesce(c.first_name,'')||' '||coalesce(c.last_name,'')),''),c.email,'—'),coalesce(c.email,'') from public.crm_contacts c where c.active and private.erp_module_allowed('crm',array['administrador','comercial'])
  ), filtered as (select * from recipients where (v_kind='' or kind=v_kind) and (label ilike '%'||v_term||'%' or email ilike '%'||v_term||'%'))
  select (select count(*) from filtered),(select coalesce(jsonb_agg(x),'[]') from (select *,email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' and length(email)<=254 selectable from filtered order by label,id,kind limit 30 offset v_off) x) into v_total,v_items;
  return jsonb_build_object('items',v_items,'total',v_total);
 elsif p_action<>'prepare' then raise exception 'SURVEY_INVALID_ACTION';end if;
 if not private.erp_action_allowed('surveys','edit') then raise exception 'SURVEY_ACCESS_DENIED';end if;
 v_sid:=(p_data->>'id')::uuid;
 perform 1 from private.surveys where id=v_sid and state='open' and (closes_at is null or closes_at>now()) for update;
 if not found then raise exception 'SURVEY_UNAVAILABLE';end if;
 if jsonb_typeof(p_data->'recipients') is distinct from 'array' or jsonb_array_length(p_data->'recipients') not between 1 and 50 then raise exception 'SURVEY_INVALID_DATA';end if;
 for v_row in select value from jsonb_array_elements(p_data->'recipients') loop
  v_email:=null;v_label:=null;
  if v_row->>'kind'='customer' then select name,lower(btrim(email)) into v_label,v_email from public.customers where id=(v_row->>'id')::uuid and active;
  elsif v_row->>'kind'='supplier' then select name,lower(btrim(email)) into v_label,v_email from public.suppliers where id=(v_row->>'id')::uuid and active;
  elsif v_row->>'kind'='contact' and private.erp_module_allowed('crm',array['administrador','comercial']) then select btrim(coalesce(first_name,'')||' '||coalesce(last_name,'')),lower(btrim(email)) into v_label,v_email from public.crm_contacts where id=(v_row->>'id')::uuid and active;
  else raise exception 'SURVEY_ACCESS_DENIED';end if;
  if v_label is null then raise exception 'SURVEY_INVALID_CONTACT';end if;
  if coalesce(v_email,'') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(v_email)>254 then
   v_out:=v_out||jsonb_build_array(jsonb_build_object('label',v_label,'status','missing_email'));continue;
  elsif v_email=any(v_seen) then v_out:=v_out||jsonb_build_array(jsonb_build_object('label',v_label,'status','duplicate_email'));continue;end if;
  v_seen:=array_append(v_seen,v_email);
  v_inv:=private.gama_surveys('invite',jsonb_build_object('id',v_sid,'kind',v_row->>'kind','contact_id',v_row->>'id'));
  if exists(select 1 from private.survey_responses where invitation_id=(v_inv->>'id')::uuid) then
   v_out:=v_out||jsonb_build_array(jsonb_build_object('label',v_label,'status','answered'));continue;
  end if;
  v_out:=v_out||jsonb_build_array(jsonb_build_object('id',v_inv->>'id','label',v_label,'email',v_email,'token',v_inv->>'token','status','prepared'));
 end loop;
 return jsonb_build_object('items',v_out);
end $$;
revoke all on function private.gama_survey_recipients(text,jsonb) from public,anon;
grant execute on function private.gama_survey_recipients(text,jsonb) to authenticated;
create function public.gama_survey_recipients(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_survey_recipients(p_action,p_data)$$;
revoke all on function public.gama_survey_recipients(text,jsonb) from public,anon;
grant execute on function public.gama_survey_recipients(text,jsonb) to authenticated;
notify pgrst,'reload schema';
