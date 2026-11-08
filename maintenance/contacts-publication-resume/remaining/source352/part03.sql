do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>351
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only exact prior-stage receipts.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source352_part03')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source352_part')<>2
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source352_part01') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source352_part02') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;


create function private.gama_accounting_deferrals(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();b private.accounting_deferral_batches;receipt private.accounting_audit_commands;
 key uuid;x jsonb;snap jsonb;result jsonb;eid uuid;rid uuid;cid uuid;line_no integer;amount numeric;direction integer;
 d date:=nullif(p_data->>'as_of','')::date;today date:=(now() at time zone private.erp_timezone())::date;
 k text:=p_data->>'kind';j uuid:=nullif(p_data->>'journal_id','')::uuid;reason text:=btrim(p_data->>'reason');lines jsonb;
 off integer:=greatest(coalesce((p_data->>'offset')::integer,0),0);lim integer:=least(greatest(coalesce((p_data->>'limit')::integer,50),1),200);
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>500000 then raise exception 'INVALID_REQUEST';end if;
 if coalesce((p_data->>'export')::boolean,false) and not coalesce((rights->>'export')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if p_action='preview' then return private.gama_deferral_snapshot(k,j,d);
 elsif p_action='list' then return jsonb_build_object('total',(select count(*) from private.accounting_deferral_batches),
  'rows',coalesce((select jsonb_agg(to_jsonb(z)) from(select review.id,review.kind,review.journal_id,review.as_of,review.status,review.entry_id,review.reversal_entry_id,(review.snapshot->>'remaining')::numeric amount,review.reason,review.last_error from private.accounting_deferral_batches review order by review.as_of desc,review.created_at desc,review.id limit lim offset off)z),'[]'));
 elsif p_action='detail' then
  select * into b from private.accounting_deferral_batches where id=(p_data->>'id')::uuid;if not found then raise exception 'DEFER_BATCH_NOT_FOUND';end if;
  return jsonb_build_object('batch',to_jsonb(b),'entries',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'number',e.number,'entry_date',e.entry_date,'status',e.status,'source_type',e.source_type) order by e.entry_date,e.source_type) from public.accounting_entries e where e.id in(b.entry_id,b.reversal_entry_id,b.correction_id,b.reversal_correction_id)),'[]'));
 elsif p_action='plan_batches' then return jsonb_build_object('rows',coalesce((select jsonb_agg(jsonb_build_object('id',review.id,'as_of',review.as_of,'status',review.status) order by review.as_of desc,review.created_at desc) from private.accounting_deferral_batches review join private.accounting_deferral_batch_plans bp on bp.batch_id=review.id where bp.plan_id=(p_data->>'id')::uuid),'[]'));
 end if;
 if p_action not in('generate','post','post_reversal','cancel') then raise exception 'INVALID_ACTION';end if;
 if not coalesce((rights->>case when p_action='generate' then 'create' else 'validate' end)::boolean,false) or not private.erp_action_allowed('accounting',case when p_action='generate' then 'create' else 'validate' end) then raise exception 'NOT_ALLOWED';end if;
 if p_action in('post','cancel') and current_setting('coco.activity_source_type',true)='chat' then raise exception 'PLAN_HUMAN_APPROVAL_REQUIRED';end if;
 key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('deferral-command:'||key::text,0));perform pg_advisory_xact_lock(741933,1);
 select * into receipt from private.accounting_audit_commands where request_key=key;
 if found then if receipt.actor<>auth.uid() or receipt.action<>'deferral_'||p_action or receipt.payload is distinct from p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 if p_action='generate' then
  if coalesce(length(reason),0) not between 3 and 500 or d>today then raise exception 'DEFER_DATE_REASON_REQUIRED';end if;
  snap:=private.gama_deferral_snapshot(k,j,d);
  if snap->>'revision' is distinct from p_data->>'revision' then raise exception 'DEFER_STALE';end if;
  if (snap->>'remaining')::numeric<=0 then raise exception 'DEFER_NOTHING_DUE';end if;
  if not private.gama_accounting_period_open(d) or not private.gama_accounting_period_open(d+1) or (private.gama_accounting_effective_date(d,'misc')->>'effective_date')::date<>d or (private.gama_accounting_effective_date(d+1,'misc')->>'effective_date')::date<>d+1 then raise exception 'DEFER_PERIOD_LOCKED';end if;
  if exists(select 1 from private.accounting_deferral_batches where kind=k and journal_id=j and as_of=d and status<>'cancelled') then raise exception 'DEFER_PERIOD_EXISTS';end if;
  insert into private.accounting_deferral_batches(kind,journal_id,as_of,revision,snapshot,reason) values(k,j,d,snap->>'revision',snap,reason) returning * into b;
  perform set_config('coco.deferral_batch',b.id::text,true);
  for direction in 1..2 loop
   perform private.gama_accounting_period(d+direction-1);
   insert into public.accounting_entries(journal_id,entry_date,reference,source_type,source_id,memo,created_by)
    values(j,d+direction-1,'Diferidos · '||d,case when direction=1 then 'deferral_closing' else 'deferral_reversal' end,b.id,reason,auth.uid()) returning id into eid;
   if direction=1 then update private.accounting_deferral_batches set entry_id=eid where id=b.id;else update private.accounting_deferral_batches set reversal_entry_id=eid where id=b.id;end if;
   line_no:=0;
   for x in select value from jsonb_array_elements(snap->'accounts') loop
    if not exists(select 1 from public.accounting_accounts where id=(x->>'account_id')::uuid and active) then raise exception 'ACCOUNT_NOT_FOUND';end if;
    amount:=(x->>'balance')::numeric*case when direction=1 then 1 else -1 end;line_no:=line_no+1;
    insert into public.accounting_entry_lines(entry_id,account_id,label,debit,credit,position) values(eid,(x->>'account_id')::uuid,'Diferimiento agrupado',greatest(amount,0),greatest(-amount,0),line_no);
   end loop;
  end loop;
  insert into private.accounting_deferral_batch_plans(batch_id,plan_id) select b.id,(source_plan->>'id')::uuid from jsonb_array_elements(snap->'rows')source_plan;
 else
  select * into b from private.accounting_deferral_batches where id=(p_data->>'id')::uuid for update;if not found then raise exception 'DEFER_BATCH_NOT_FOUND';end if;
  perform set_config('coco.deferral_batch',b.id::text,true);
  perform 1 from public.accounting_entries where id in(b.entry_id,b.reversal_entry_id) order by id for update;
  if p_action in('post','post_reversal') and exists(select 1 from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id where l.entry_id in(b.entry_id,b.reversal_entry_id) and not a.active) then raise exception 'ACCOUNT_INACTIVE';end if;
  if p_action='post' then
   if b.status<>'draft' then raise exception 'DEFER_STATE_INVALID';end if;
   snap:=private.gama_deferral_snapshot(b.kind,b.journal_id,b.as_of);if snap->>'revision'<>b.revision then raise exception 'DEFER_STALE';end if;
   if not private.gama_accounting_period_open(b.as_of) or not private.gama_accounting_period_open(b.as_of+1) or (private.gama_accounting_effective_date(b.as_of,'misc')->>'effective_date')::date<>b.as_of or (private.gama_accounting_effective_date(b.as_of+1,'misc')->>'effective_date')::date<>b.as_of+1 then raise exception 'DEFER_PERIOD_LOCKED';end if;
   if b.as_of>today or exists(select 1 from public.accounting_entries where id in(b.entry_id,b.reversal_entry_id) and status<>'draft') then raise exception 'DEFER_STATE_INVALID';end if;
   update public.accounting_entries set status='posted',posted_at=now(),posted_by=auth.uid() where id in(b.entry_id,b.reversal_entry_id) and entry_date<=today;
   update private.accounting_deferral_batches set status='posted',approved_by=auth.uid(),approved_at=now() where id=b.id;
  elsif p_action='post_reversal' then
   if b.status<>'posted' or b.approved_by is null or b.as_of+1>today then raise exception 'DEFER_STATE_INVALID';end if;
   if not private.gama_accounting_period_open(b.as_of+1) or (private.gama_accounting_effective_date(b.as_of+1,'misc')->>'effective_date')::date<>b.as_of+1 then raise exception 'DEFER_PERIOD_LOCKED';end if;
   update public.accounting_entries set status='posted',posted_at=now(),posted_by=auth.uid() where id=b.reversal_entry_id and status='draft';
   update private.accounting_deferral_batches set last_error=null where id=b.id;
  else
   if b.status='cancelled' or coalesce(length(reason),0) not between 3 and 500 then raise exception 'DEFER_STATE_INVALID';end if;
   if b.status='draft' then
    if exists(select 1 from public.accounting_entries where id in(b.entry_id,b.reversal_entry_id) and status<>'draft') then raise exception 'DEFER_STATE_INVALID';end if;
    update private.accounting_deferral_batches set entry_id=null,reversal_entry_id=null where id=b.id;
    delete from public.accounting_entry_lines where entry_id in(b.entry_id,b.reversal_entry_id);
    delete from public.accounting_entries where id in(b.entry_id,b.reversal_entry_id);
   else
    -- Corrections preserve posted originals and the original period boundaries.
    if not private.gama_accounting_period_open(b.as_of) or not private.gama_accounting_period_open(b.as_of+1) or (private.gama_accounting_effective_date(b.as_of,'misc')->>'effective_date')::date<>b.as_of or (private.gama_accounting_effective_date(b.as_of+1,'misc')->>'effective_date')::date<>b.as_of+1 then raise exception 'DEFER_PERIOD_LOCKED';end if;
    for eid in select id from public.accounting_entries where id in(b.entry_id,b.reversal_entry_id) order by entry_date loop
     if (select status from public.accounting_entries where id=eid)='draft' then
      update private.accounting_deferral_batches set reversal_entry_id=null where id=b.id;
      delete from public.accounting_entry_lines where entry_id=eid;delete from public.accounting_entries where id=eid;continue;
     end if;
     if exists(select 1 from public.accounting_entries where reversal_of=eid) then raise exception 'DEFER_STATE_INVALID';end if;
     select jsonb_agg(jsonb_build_object('account_id',account_id,'debit',credit,'credit',debit,'label',label) order by position) into lines from public.accounting_entry_lines where entry_id=eid;
     cid:=private.gama_accounting_book((select code from public.accounting_journals where id=b.journal_id),(select entry_date from public.accounting_entries where id=eid),'Corrección de diferidos · '||b.as_of,'deferral_correction',gen_random_uuid(),reason,lines);
     update public.accounting_entries set reversal_of=eid where id=cid;
     if eid=b.entry_id then update private.accounting_deferral_batches set correction_id=cid where id=b.id;else update private.accounting_deferral_batches set reversal_correction_id=cid where id=b.id;end if;
    end loop;
   end if;
   update private.accounting_deferral_batches set status='cancelled',reason=btrim(p_data->>'reason') where id=b.id;
  end if;
 end if;
 result:=jsonb_build_object('id',b.id);insert into private.accounting_audit_commands values(key,auth.uid(),'deferral_'||p_action,p_data,result);perform set_config('coco.deferral_batch','',true);return result;
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_accounting_deferrals(text, jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_plan_compute_before_grouped(jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_deferral_snapshot(text, uuid, date) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_accounting_plans_before_grouped(text, jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_accounting_deferrals(text, jsonb) from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.accounting_deferral_batches enable row level security;
revoke all on table private.accounting_deferral_batches from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.accounting_deferral_batch_plans enable row level security;
revoke all on table private.accounting_deferral_batch_plans from public,anon,authenticated;
