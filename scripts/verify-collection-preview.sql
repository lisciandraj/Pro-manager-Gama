-- Production smoke: metadata only; no customer/document rows or business RPC calls.
begin transaction read only;
with expected(signature,security_definer,authenticated_execute,returns_set,return_type) as (
 values
 ('private.coco_collection_preview_rows(uuid)',false,false,true,'record'),
 ('private.gama_collections_preview(uuid,jsonb)',true,true,false,'jsonb'),
 ('public.gama_collections_preview(uuid,jsonb)',false,true,false,'jsonb')
), checked as (
 select e.signature,p.oid is not null present,
  p.prosecdef=e.security_definer security_mode_ok,
  p.provolatile='s' stable_ok,
  p.proconfig @> array['search_path=""']::text[] search_path_ok,
  pg_get_userbyid(p.proowner)='postgres' owner_ok,
  p.proretset=e.returns_set and p.prorettype=e.return_type::regtype return_type_ok,
  has_function_privilege('authenticated',p.oid,'EXECUTE')=e.authenticated_execute authenticated_acl_ok,
  not has_function_privilege('anon',p.oid,'EXECUTE') anon_acl_ok,
  not has_function_privilege('service_role',p.oid,'EXECUTE') service_acl_ok,
  not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
   where a.grantee=0 and a.privilege_type='EXECUTE') public_acl_ok,
  case when e.signature='private.gama_collections_preview(uuid,jsonb)' then
   strpos(p.prosrc,'auth.uid() is null')>0 and strpos(p.prosrc,'private.erp_mfa_ok()')>0
   and strpos(p.prosrc,'private.erp_module_allowed(''payments'',array[''administrador'',''comercial''])')>0
   and strpos(p.prosrc,'private.erp_action_allowed(''payments'',''create'')')>0
   else true end authorization_guard_ok,
  pg_get_function_result(p.oid) actual_result,
  md5(p.prosrc) source_md5
 from expected e left join pg_proc p on p.oid=to_regprocedure(e.signature)
), report as (
 select *,coalesce(present and security_mode_ok and stable_ok and search_path_ok and owner_ok
  and return_type_ok and authenticated_acl_ok and anon_acl_ok and service_acl_ok
  and public_acl_ok and authorization_guard_ok,false) passed from checked
)
select jsonb_build_object('all_passed',bool_and(passed),'functions',jsonb_agg(to_jsonb(report) order by signature)) from report;
rollback;
