-- The shared audit trigger keys rows by their `id` column. This table is keyed by
-- the profile it grants, so it gets a trigger that records that key instead.
drop trigger ac_audit_accounting_permissions on public.accounting_permissions;
create function private.gama_accounting_permissions_audit() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into public.gama_audit(table_name,row_id,action,actor_id,actor_role,old_data,new_data)
 values('accounting_permissions',coalesce(new.profile_id,old.profile_id)::text,tg_op,auth.uid(),
  private.current_user_role(),
  case when tg_op<>'INSERT' then to_jsonb(old) end,
  case when tg_op<>'DELETE' then to_jsonb(new) end);
 return coalesce(new,old);
end $$;
revoke all on function private.gama_accounting_permissions_audit() from public,anon,authenticated;
create trigger ac_audit_accounting_permissions after insert or update or delete on public.accounting_permissions
 for each row execute function private.gama_accounting_permissions_audit();
select 'permissions-audit' as status;
