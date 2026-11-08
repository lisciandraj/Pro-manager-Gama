do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>358
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only exact prior-stage receipts.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source359_part03')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source359_part')<>2
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source359_part01') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source359_part02') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;

create function public.gama_tms_routing(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_routing(p_action,p_data)$$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function public.gama_tms_routing(text, jsonb) from public,anon,authenticated;

revoke all on function public.gama_tms_routing(text,jsonb),private.gama_tms_routing(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_tms_routing(text,jsonb),private.gama_tms_routing(text,jsonb) to authenticated;

-- Only the authenticated Edge adapter may store a matrix. No client-supplied
-- matrix can become a trusted distance/time source.
create function private.tms_routing_commit(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m private.tms_routing_matrices;n integer;i integer;j integer;km jsonb;seconds jsonb;begin
 if (auth.jwt()->>'role') is distinct from 'service_role' then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into m from private.tms_routing_matrices where day=(p_data->>'day')::date and lease=(p_data->>'lease')::uuid and actor_id=(p_data->>'actor_id')::uuid for update;
 if not found or m.state<>'pending' or m.requested_at<now()-interval '2 minutes' then raise exception 'ROAD_MATRIX_STALE';end if;
 if p_data->>'error'='ROAD_PROVIDER_UNAVAILABLE' then
  update private.tms_routing_matrices set state='failed',error_code='ROAD_PROVIDER_UNAVAILABLE' where day=m.day;return jsonb_build_object('stored',false);
 end if;
 if m.points<>private.tms_routing_points(m.day) then raise exception 'ROAD_MATRIX_STALE';end if;
 n:=jsonb_array_length(m.points);
 if jsonb_typeof(p_data->'distances') is distinct from 'array' or jsonb_typeof(p_data->'durations') is distinct from 'array' or jsonb_array_length(p_data->'distances')<>n or jsonb_array_length(p_data->'durations')<>n then raise exception 'ROAD_RESPONSE_INVALID';end if;
 for i in 0..n-1 loop
  if jsonb_typeof(p_data->'distances'->i) is distinct from 'array' or jsonb_typeof(p_data->'durations'->i) is distinct from 'array' or jsonb_array_length(p_data->'distances'->i)<>n or jsonb_array_length(p_data->'durations'->i)<>n then raise exception 'ROAD_RESPONSE_INVALID';end if;
  for j in 0..n-1 loop
   km:=p_data->'distances'->i->j;seconds:=p_data->'durations'->i->j;
   if not ((km='null'::jsonb and seconds='null'::jsonb and i<>j) or (jsonb_typeof(km)='number' and jsonb_typeof(seconds)='number' and km::text::numeric between 0 and 20000 and seconds::text::numeric between 0 and 604800 and (i<>j or (km='0'::jsonb and seconds='0'::jsonb)))) then raise exception 'ROAD_RESPONSE_INVALID';end if;
   insert into private.tms_routing_pairs(day,a_lat,a_lng,b_lat,b_lng,km,seconds) values(m.day,(m.points->i->>1)::numeric,(m.points->i->>0)::numeric,(m.points->j->>1)::numeric,(m.points->j->>0)::numeric,(km#>>'{}')::double precision,(seconds#>>'{}')::double precision);
  end loop;
 end loop;
 update private.tms_routing_matrices set state='ready',measured_at=now(),expires_at=now()+interval '24 hours',error_code=null where day=m.day;
 delete from private.tms_day_plans where day=m.day;
 return jsonb_build_object('stored',true,'locations',n,'expires_at',now()+interval '24 hours');
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.tms_routing_commit(jsonb) from public,anon,authenticated;

create function public.gama_tms_routing_commit(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.tms_routing_commit(p_data)$$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function public.gama_tms_routing_commit(jsonb) from public,anon,authenticated;

revoke all on function public.gama_tms_routing_commit(jsonb),private.tms_routing_commit(jsonb) from public,anon,authenticated;
grant execute on function public.gama_tms_routing_commit(jsonb),private.tms_routing_commit(jsonb) to service_role;
-- Private cache expiry is enforced on reads even if cleanup is delayed.
select cron.schedule('coco-tms-routing-retention','17 3 * * *',$cron$delete from private.tms_routing_matrices where requested_at<now()-interval '48 hours'$cron$);
do $$declare p record;begin for p in select oid::regprocedure sig from pg_proc where pronamespace='private'::regnamespace and proname in ('tms_routing_points','tms_routing_covers','tms_routing_begin','tms_routing_evaluate','tms_routing_improve') loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',p.sig);end loop;end $$;

-- The 100-stop isolated benchmark exceeds the default API role's 8 s on WASM.
-- Bound only these authorized operations; retain all global/role timeouts.
alter function public.gama_tms_plan_day(date) set statement_timeout='30s';
alter function public.gama_tms_plan_day() set statement_timeout='30s';
alter function public.gama_tms_routing_commit(jsonb) set statement_timeout='30s';
notify pgrst, 'reload schema';

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.tms_routing_points(date) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.tms_routing_covers(jsonb, jsonb) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.tms_routing_begin(date) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.tms_routing_evaluate(integer[], jsonb, integer[], double precision[], integer, integer, integer, integer, integer) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.tms_routing_improve(uuid[], date, uuid) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_tms_routing(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function private.gama_tms_routing(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function public.gama_tms_routing(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function public.gama_tms_routing(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.tms_routing_commit(jsonb) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function public.gama_tms_routing_commit(jsonb) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.tms_routing_matrices from public,anon,authenticated;
alter table private.tms_routing_matrices enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.tms_routing_pairs from public,anon,authenticated;
alter table private.tms_routing_pairs enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.tms_routing_throttle from public,anon,authenticated;
alter table private.tms_routing_throttle enable row level security;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261030191545','tms_road_optimization','1196aaed0901133021d0ddb798f59e3653684a590e9383cb9bce2504b84404a4','1196aaed0901133021d0ddb798f59e3653684a590e9383cb9bce2504b84404a4','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
