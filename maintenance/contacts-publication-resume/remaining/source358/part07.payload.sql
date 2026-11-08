
revoke all on function private.gama_compliance_admin(text,jsonb) from public,anon;
grant execute on function private.gama_compliance_admin(text,jsonb) to authenticated;
create function public.gama_compliance_admin(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_compliance_admin(p_action,p_data)$$;
revoke all on function public.gama_compliance_admin(text,jsonb) from public,anon;
grant execute on function public.gama_compliance_admin(text,jsonb) to authenticated;
-- Bind a B2B acceptance to the exact public conditions alongside its quote snapshot.
do $$declare body text;target oid;n integer;begin
 select count(*),(array_agg(p.oid))[1] into n,target from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
 where ns.nspname='private' and p.proname like 'gama_b2b_action%' and strpos(p.prosrc,'insert into private.sales_portal_acceptances(quote_id,revision,accepted_by,snapshot)')>0;
 if n<>1 then raise exception 'COMPLIANCE_B2B_POLICY_ANCHOR';end if;
 select pg_get_functiondef(target) into body;
 body:=replace(body,'  insert into private.sales_portal_acceptances(quote_id,revision,accepted_by,snapshot)',
  '  if p_data->>''policy_version'' is distinct from (private.commerce_policy_bundle()->>''version'') then raise exception ''COMMERCE_POLICY_CHANGED'';end if; insert into private.sales_portal_acceptances(quote_id,revision,accepted_by,snapshot)');
 body:=replace(body,'jsonb_build_object(''reference'',q.invoice_number,''total'',q.total,''terms'',','jsonb_build_object(''policies'',private.commerce_policy_bundle(),''reference'',q.invoice_number,''total'',q.total,''terms'',');
 body:=replace(body,'result:=result||jsonb_build_object(''revision'',q.quote_revision,','result:=result||jsonb_build_object(''policies'',private.commerce_policy_bundle(),''revision'',q.quote_revision,');
 execute body;
end $$;
-- Keep the original function OID used by RLS policies. These rows have the same
-- administrator-only, module-wide read contract as the compliance RPC.
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),
 'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_compliance(');end $$;
revoke all on function private.coco_history_record_visible_before_compliance(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_compliance(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean language plpgsql stable security invoker set search_path='' as $$
begin
 if p_table in ('commerce_policy_versions','commerce_cases','commerce_compliance_records','commerce_retention_rule','commerce_reviews','commerce_guest_orders','commerce_approvers','commerce_approvals','commerce_catalog_products') then return private.coco_module_allowed('website');end if;
 return private.coco_history_record_visible_before_compliance(p_table,p_id,p_owner);
end $$;
commit;
