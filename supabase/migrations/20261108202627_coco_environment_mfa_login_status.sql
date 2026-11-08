-- MFA enrollment needs the caller's own policy status before the profile is
-- accessible at AAL2. Keep the other identity actions behind the environment gate.
create function public.coco_identity_login_status() returns jsonb
language sql security invoker set search_path='' as $$
 select private.coco_identity_policy('status','{}'::jsonb)
$$;
revoke all on function public.coco_identity_login_status() from public,anon,service_role;
grant execute on function public.coco_identity_login_status() to authenticated;

create or replace function public.coco_agent_request_guard() returns void
language plpgsql security invoker set search_path='' as $$
declare request_path text:=coalesce(current_setting('request.path',true),'');
begin
 if nullif(auth.jwt()->>'client_id','') is not null and request_path<>'/rpc/coco_agent' then
  raise exception 'AGENT_ENDPOINT_NOT_ALLOWED' using errcode='42501';
 end if;
 if current_user<>'service_role'
 and request_path not in ('/rpc/coco_environment_status','/rpc/coco_identity_login_status')
 and not environment_api.coco_environment_allowed() then
  raise exception 'DEVELOPMENT_ADMIN_REQUIRED' using errcode='42501';
 end if;
end $$;
