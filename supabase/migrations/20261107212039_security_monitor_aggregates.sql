-- Minimal private security audit. Actor UUID stays in the protected ledger;
-- collection returns counts only, never identities or business payloads.
set local lock_timeout='3s';
set local statement_timeout='60s';
create table private.coco_security_events(
 id bigint generated always as identity primary key,
 occurred_at timestamptz not null default clock_timestamp(),
 actor_id uuid not null default auth.uid(),
 scope text not null default 'application-business-export' check(scope='application-business-export'),
 event_type text not null check(event_type='sensitive_export')
);
create index coco_security_events_time on private.coco_security_events(occurred_at);
alter table private.coco_security_events enable row level security;
revoke all on private.coco_security_events from public,anon,authenticated,service_role;

-- Compose with the identity migration in either installation order. The event
-- rolls back if the export or its surrounding transaction fails.
alter function private.gama_recovery_export() volatile;
alter function public.gama_recovery_export() volatile;
do $$declare body text;anchor text:=$anchor$return jsonb_build_object('format','architect-application-export'$anchor$;begin
 select pg_get_functiondef('private.gama_recovery_export()'::regprocedure) into body;
 if (length(body)-length(replace(body,anchor,'')))/length(anchor)<>1
  or position('private.coco_security_events' in body)>0 then raise exception 'SECURITY_EXPORT_TRACE_ANCHOR_CHANGED';end if;
 body:=replace(body,anchor,'insert into private.coco_security_events(event_type,actor_id) values(''sensitive_export'',auth.uid()); '||anchor);
 execute body;
end $$;

create function private.coco_security_aggregate(p_start timestamptz,p_end timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare captures integer;roles bigint;exports bigint;calls bigint;failed bigint;expired bigint;
 reserved numeric;charged numeric;input_tokens numeric;output_tokens numeric;begin
 if auth.role() is distinct from 'service_role' then raise exception 'SECURITY_COLLECTOR_SERVICE_REQUIRED';end if;
 if p_start is null or p_end is null or p_start>=p_end or p_end>clock_timestamp()
  or p_start<clock_timestamp()-interval '25 hours' or p_end-p_start>interval '24 hours' then raise exception 'SECURITY_COLLECTOR_WINDOW_INVALID';end if;
 -- Never mistake RLS-filtered empty results for healthy zero counters.
 if pg_catalog.row_security_active('public.erp_audit_events'::regclass)
  or pg_catalog.row_security_active('private.ai_provider_usage'::regclass)
  or pg_catalog.row_security_active('private.coco_security_events'::regclass) then raise exception 'SECURITY_COLLECTOR_SOURCE_RLS_ACTIVE';end if;
 select count(distinct c.relname) into captures from pg_catalog.pg_trigger t
  join pg_catalog.pg_class c on c.oid=t.tgrelid join pg_catalog.pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname in('profiles','role_module_access','erp_action_permissions','accounting_permissions')
   and t.tgfoid='private.erp_audit_capture()'::regprocedure and t.tgenabled in('O','A') and not t.tgisinternal;
 if captures<>4 then raise exception 'SECURITY_COLLECTOR_AUDIT_CAPTURE_INCOMPLETE';end if;
 select count(*) into roles from public.erp_audit_events e where e.created_at>=p_start and e.created_at<p_end
  and (e.table_name in('role_module_access','erp_action_permissions','accounting_permissions')
   or (e.table_name='profiles' and (
    e.before_data->>'role' is distinct from e.after_data->>'role'
    or e.before_data->>'access_profile' is distinct from e.after_data->>'access_profile'
    or e.before_data->>'active' is distinct from e.after_data->>'active'
    or e.before_data->>'deleted_at' is distinct from e.after_data->>'deleted_at')));
 select count(*) into exports from private.coco_security_events where occurred_at>=p_start and occurred_at<p_end and event_type='sensitive_export';
 select count(*),coalesce(sum(reserved_microusd),0) into calls,reserved from private.ai_provider_usage where created_at>=p_start and created_at<p_end;
 select count(*) filter(where state='failed'),count(*) filter(where state='expired'),coalesce(sum(charged_microusd),0),
  coalesce(sum(u.input_tokens),0),coalesce(sum(u.output_tokens),0) into failed,expired,charged,input_tokens,output_tokens
  from private.ai_provider_usage u where completed_at>=p_start and completed_at<p_end;
 return jsonb_build_object('version',1,'coverage',jsonb_build_object('erp_audit',true,'export_events',true,'ai_usage',true),
  'counts',jsonb_build_object('privileged_role_change',roles,'sensitive_export',exports),
  'metrics',jsonb_build_object('ai_calls',calls,'ai_failed',failed,'ai_expired',expired,'ai_reserved_microusd',reserved,
   'ai_settled_charged_microusd',charged,'ai_input_tokens',input_tokens,'ai_output_tokens',output_tokens));
end $$;
revoke all on function private.coco_security_aggregate(timestamptz,timestamptz) from public,anon,authenticated,service_role;
grant execute on function private.coco_security_aggregate(timestamptz,timestamptz) to service_role;
create function public.coco_security_aggregate(p_start timestamptz,p_end timestamptz) returns jsonb
language sql security invoker set search_path='' as $$select private.coco_security_aggregate(p_start,p_end)$$;
revoke all on function public.coco_security_aggregate(timestamptz,timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.coco_security_aggregate(timestamptz,timestamptz) to service_role;
notify pgrst,'reload schema';
