-- Direct CRM tables retain their shared commercial audience, but cannot
-- bypass a disabled module through the browser's generic table client.
do $audit$
declare tbl text;
begin
 foreach tbl in array array['crm_opportunities','crm_opportunity_lines','crm_activities'] loop
  execute format('create policy security_crm_module on public.%I as restrictive for all to authenticated using(private.erp_module_allowed(''crm'',array[''administrador'',''comercial''])) with check(private.erp_module_allowed(''crm'',array[''administrador'',''comercial'']))',tbl);
 end loop;
end $audit$;

-- Line creation/deletion edits an existing opportunity. Check that authority
-- before the first request; a later denied header-total update is too late.
-- The ordinary action trigger also preserves create/edit/delete restrictions.
create trigger erp_action_guard before insert or update or delete on public.crm_opportunity_lines
 for each row execute function private.erp_action_guard('crm');
create policy security_crm_line_insert on public.crm_opportunity_lines as restrictive
 for insert to authenticated with check(private.erp_action_allowed('crm','edit'));
create policy security_crm_line_update on public.crm_opportunity_lines as restrictive
 for update to authenticated using(private.erp_action_allowed('crm','edit')) with check(private.erp_action_allowed('crm','edit'));
create policy security_crm_line_delete on public.crm_opportunity_lines as restrictive
 for delete to authenticated using(private.erp_action_allowed('crm','edit'));
notify pgrst,'reload schema';
