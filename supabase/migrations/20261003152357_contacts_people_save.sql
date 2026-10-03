-- Preserve existing RLS and action guards; change a primary contact atomically.
create function public.gama_contact_person_save(p_id uuid,p_data jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare old public.crm_contacts;result public.crm_contacts;cid uuid:=(p_data->>'customer_id')::uuid;lid uuid:=(p_data->>'lead_id')::uuid;
begin
 if auth.uid() is null or not private.erp_module_allowed('crm',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'CONTACT_ACCESS_DENIED';end if;
 if (cid is null)=(lid is null) or octet_length(p_data::text)>12000 then raise exception 'CONTACT_INVALID_DATA';end if;
 if not private.erp_action_allowed('crm',case when p_id is null then 'create' else 'edit' end) then raise exception 'CONTACT_ACCESS_DENIED';end if;
 if p_id is not null then select * into old from public.crm_contacts where id=p_id for update;if not found then raise exception 'CONTACT_NOT_FOUND';end if;end if;
 perform pg_advisory_xact_lock(hashtextextended('contact-parent:'||coalesce(cid,lid),0));
 if coalesce((p_data->>'is_primary')::boolean,false) then update public.crm_contacts set is_primary=false where active and is_primary and (customer_id=cid or lead_id=lid) and id is distinct from p_id;end if;
 if p_id is null then
  insert into public.crm_contacts(customer_id,lead_id,first_name,last_name,job_title,email,phone,linkedin,decision_role,notes,is_primary,created_by)
  values(cid,lid,p_data->>'first_name',p_data->>'last_name',p_data->>'job_title',p_data->>'email',p_data->>'phone',p_data->>'linkedin',p_data->>'decision_role',p_data->>'notes',coalesce((p_data->>'is_primary')::boolean,false),auth.uid()) returning * into result;
 else
  update public.crm_contacts set customer_id=cid,lead_id=lid,first_name=p_data->>'first_name',last_name=p_data->>'last_name',job_title=p_data->>'job_title',email=p_data->>'email',phone=p_data->>'phone',linkedin=p_data->>'linkedin',decision_role=p_data->>'decision_role',notes=p_data->>'notes',is_primary=coalesce((p_data->>'is_primary')::boolean,false) where id=p_id returning * into result;
 end if;
 return to_jsonb(result);
end $$;
revoke all on function public.gama_contact_person_save(uuid,jsonb) from public,anon;
grant execute on function public.gama_contact_person_save(uuid,jsonb) to authenticated;
notify pgrst,'reload schema';
