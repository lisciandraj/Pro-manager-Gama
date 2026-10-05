-- File preview and user confirmation remain explicit. Only confirmed batches
-- are queued; a periodic tick never discovers and applies unconfirmed previews.
insert into private.automation_catalog(kind,module,title,interval_minutes,delegated) values('import_apply','reports','Importaciones confirmadas en segundo plano',1440,true);
insert into private.automation_rules(kind,version,enabled) values('import_apply',1,false);
create function private.gama_import_background(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare batch public.erp_import_batches;rule private.automation_rules;job uuid;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('reports',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into batch from public.erp_import_batches where id=(p_data->>'id')::uuid;if not found then raise exception 'IMPORT_NOT_FOUND';end if;
 if p_action='queue' then
  select * into rule from private.automation_rules where kind='import_apply' order by version desc limit 1;
  if not rule.enabled or rule.executor is distinct from auth.uid() or rule.approved_until<=now() then raise exception 'IMPORT_DELEGATION_REQUIRED';end if;
  job:=private.automation_enqueue('import_apply','import-confirmed:'||batch.id||':'||rule.version,jsonb_build_object('source_hash',md5(batch.source_rows::text)),'import_batch',batch.id);
  return jsonb_build_object('id',job,'state','queued','batch_id',batch.id);
 elsif p_action='status' then return jsonb_build_object('batch',to_jsonb(batch),'jobs',(select coalesce(jsonb_agg(jsonb_build_object('id',j.id,'state',j.state,'attempts',j.attempts,'result',j.result,'error_code',j.error_code) order by created_at desc),'[]') from private.automation_jobs j where j.kind='import_apply' and source_id=batch.id));
 end if;raise exception 'INVALID_ACTION';end $$;
create function public.gama_import_background(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_import_background(p_action,p_data)$$;
revoke all on function public.gama_import_background(text,jsonb),private.gama_import_background(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_import_background(text,jsonb),private.gama_import_background(text,jsonb) to authenticated;
create function private.automation_import_apply(p_job private.automation_jobs) returns jsonb language plpgsql security definer set search_path='' as $$
declare batch public.erp_import_batches;result jsonb;done integer;failed integer;begin
 if p_job.source_id is null then return jsonb_build_object('scanned',0);end if;
 select * into batch from public.erp_import_batches where id=p_job.source_id for update;if not found or md5(batch.source_rows::text) is distinct from p_job.payload->>'source_hash' then return jsonb_build_object('blocked',true,'reason','IMPORT_SOURCE_CHANGED');end if;
 result:=private.gama_import_batch('apply',jsonb_build_object('id',batch.id));
 select count(*) filter(where status='imported'),count(*) filter(where status='error') into done,failed from public.erp_import_rows where batch_id=batch.id;
 return jsonb_build_object('batch_id',batch.id,'imported',done,'errors',failed,'blocked',failed>0,'reason',case when failed>0 then 'IMPORT_ROWS_REQUIRE_REVIEW' end);end $$;
alter function private.automation_dispatch(private.automation_jobs,jsonb) rename to automation_dispatch_before_imports;
revoke all on function private.automation_dispatch_before_imports(private.automation_jobs,jsonb) from public,anon,authenticated,service_role;
create function private.automation_dispatch(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if p_job.kind='import_apply' then return private.automation_import_apply(p_job);end if;return private.automation_dispatch_before_imports(p_job,p_config);end $$;
revoke all on function private.automation_import_apply(private.automation_jobs),private.automation_dispatch(private.automation_jobs,jsonb) from public,anon,authenticated,service_role;
