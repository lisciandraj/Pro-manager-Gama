-- Audit daily workflows: additive metadata, no business data rewrite, no SRI changes.
-- Coverage reuses the canonical min/max calculation, never the demand forecast.
create function private.coco_replenishment_coverage() returns jsonb
language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(x.data || jsonb_build_object('purchases',coalesce(p.orders,'[]'::jsonb)) order by x.data->>'name',x.product_id),'[]')
 from private.stock_minmax_replenishment_rows() x
 left join lateral (
  select jsonb_agg(jsonb_build_object('id',z.id,'number',z.order_number,'status',z.status,'remaining',z.remaining) order by z.order_number,z.id) orders
  from (select o.id,o.order_number,o.status,sum(greatest(l.quantity-l.received_quantity,0)) remaining
   from public.purchase_order_lines l join public.purchase_orders o on o.id=l.purchase_order_id
   where l.product_id=x.product_id and o.status in ('draft','sent','partial') and l.quantity>l.received_quantity
   group by o.id,o.order_number,o.status) z
 ) p on true
$$;
revoke all on function private.coco_replenishment_coverage() from public,anon,authenticated,service_role;
create or replace function private.gama_stock_insights(p_view text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare can_buy boolean;can_count boolean;rows jsonb;late jsonb:='[]';adjustments jsonb:='[]';counts jsonb:='[]';people jsonb:='[]';begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_view not in ('acciones','rotacion','reabastecimiento','conteos') then raise exception 'INVALID_VIEW';end if;
 can_buy:=private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']);
 can_count:=private.erp_module_allowed('warehouses',array['administrador','almacenero']);
 select coalesce(jsonb_agg(case when can_count then x.data else x.data-'repeated_discrepancies' end order by x.data->>'name'),'[]') into rows from private.stock_insight_rows(can_buy) x;
 if p_view='acciones' and can_buy then
  select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'number',o.order_number,'supplier',s.name,'expected_date',o.expected_date,'days_late',current_date-o.expected_date::date) order by o.expected_date),'[]') into late
   from public.purchase_orders o join public.suppliers s on s.id=o.supplier_id
   where o.status in ('sent','partial') and o.expected_date::date<current_date
    and exists(select 1 from public.purchase_order_lines l where l.purchase_order_id=o.id and l.quantity>l.received_quantity);
 end if;
 if p_view='acciones' and can_count then
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'product_id',r.product_id,'reason',r.reason,'requested_at',r.requested_at) order by r.requested_at desc,r.id desc),'[]') into adjustments from public.stock_adjustment_requests r where r.status='pending';
 end if;
 if p_view in ('acciones','conteos') and can_count then
  select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('assigned_name',p.full_name,'repeat_started',exists(select 1 from public.inventory_counts n where n.repeat_of=c.id and n.status<>'cancelled')) order by case when c.priority='high' then 0 else 1 end,coalesce(c.due_date,c.next_due),c.created_at desc),'[]') into counts
   from public.inventory_counts c left join public.profiles p on p.id=c.assigned_to
   where c.status in ('draft','in_progress') or (c.status='validated' and c.next_due is not null);
  if p_view='conteos' then select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name) order by p.full_name),'[]') into people from public.profiles p where p.active and p.role in ('administrador','almacenero');end if;
 end if;
 return jsonb_build_object('as_of',now(),'today',current_date,'minmax_coverage',case when p_view='reabastecimiento' and can_buy then private.coco_replenishment_coverage() else '[]'::jsonb end,'can_buy',can_buy,'can_count',can_count,'rows',rows,'late_orders',late,'adjustments',adjustments,'counts',counts,'people',people);
end $$;

create or replace function private.gama_automation(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
 declare admin boolean:=private.erp_module_allowed('access-settings',array['administrador']);r private.automation_rules;c private.automation_catalog;
 j private.automation_jobs;e private.automation_exceptions;off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));
 exoff integer:=greatest(0,least(coalesce((p_data->>'exception_offset')::integer,0),100000));extotal integer;rows jsonb;rules jsonb;exceptions jsonb;operation_key uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not admin and not private.erp_module_allowed('notifications',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='rule_save' then
  if not admin or not private.erp_action_allowed('access-settings','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  select * into c from private.automation_catalog where kind=p_data->>'kind';if not found then raise exception 'RULE_NOT_FOUND';end if;
  perform pg_advisory_xact_lock(hashtextextended('automation-rule:'||c.kind,0));
  select * into r from private.automation_rules where kind=c.kind order by version desc limit 1;
  if r.version is distinct from (p_data->>'expected_version')::integer then raise exception 'RULE_CHANGED';end if;
  if jsonb_typeof(p_data->'config') is distinct from 'object' then raise exception 'INVALID_CONFIG';end if;
  if coalesce((p_data->'config'->>'interval_minutes')::integer,c.interval_minutes) not between 1 and 10080 then raise exception 'INVALID_INTERVAL';end if;
  if coalesce((p_data->>'enabled')::boolean,false) and not private.automation_visible(c.module) then raise exception 'ROLE_NOT_ALLOWED';end if;
  insert into private.automation_rules(kind,version,enabled,config,executor,approved_until,approved_by)
   values(c.kind,r.version+1,coalesce((p_data->>'enabled')::boolean,false),p_data->'config',case when c.delegated then auth.uid() end,
    case when c.delegated then now()+make_interval(days=>greatest(1,least(coalesce((p_data->>'delegation_days')::integer,90),90))) end,auth.uid()) returning * into r;
  return to_jsonb(r);
 elsif p_action='run_once' then
  if not admin then raise exception 'ROLE_NOT_ALLOWED';end if;
  operation_key:=nullif(p_data->>'request_key','')::uuid;if operation_key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  operation_key:=private.automation_enqueue(p_data->>'kind','manual:'||operation_key::text,coalesce(p_data->'payload','{}'));
  if operation_key is null then raise exception 'RULE_DISABLED';end if;
  return jsonb_build_object('id',operation_key,'state','queued');
 elsif p_action in ('retry','cancel') then
  select * into j from private.automation_jobs where id=(p_data->>'id')::uuid for update;
  select * into c from private.automation_catalog where kind=j.kind;
  if not found or not admin or not private.automation_visible(c.module) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if j.state not in ('blocked','dead','retry','queued') then raise exception 'JOB_NOT_RETRYABLE';end if;
  select * into r from private.automation_rules where kind=j.kind order by version desc limit 1;
  if p_action='retry' and not r.enabled then raise exception 'RULE_DISABLED';end if;
  update private.automation_jobs set state=case when p_action='retry' then 'queued' else 'cancelled' end,rule_version=r.version,actor=r.executor,
   failures=case when p_action='retry' then 0 else failures end,available_at=now(),updated_at=now(),error_code=null where id=j.id;
  if p_action='cancel' then update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where job_id=j.id;end if;
  return jsonb_build_object('id',j.id,'state',case when p_action='retry' then 'queued' else 'cancelled' end);
 elsif p_action='assign' then
  select * into e from private.automation_exceptions where key=p_data->>'key' for update;
  if not found or not private.automation_visible(e.module) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if not e.active then raise exception 'EXCEPTION_RESOLVED';end if;
  if p_data ? 'expected_updated_at' and e.updated_at is distinct from (p_data->>'expected_updated_at')::timestamptz then raise exception 'FOLLOWUP_CHANGED';end if;
  operation_key:=coalesce(nullif(p_data->>'assigned_to','')::uuid,auth.uid());
  if not exists(select 1 from public.profiles p where p.id=operation_key and p.active and p.role in ('administrador','comercial','almacenero') and (p.id=auth.uid() or admin)) then raise exception 'ASSIGNEE_INVALID';end if;
  if length(btrim(coalesce(p_data->>'next_action','')))<3 then raise exception 'NEXT_ACTION_REQUIRED';end if;
  update private.automation_exceptions set assigned_to=operation_key,next_action=p_data->>'next_action',due_at=nullif(p_data->>'due_at','')::timestamptz,updated_at=now() where automation_exceptions.key=e.key;
  return jsonb_build_object('key',e.key);
 elsif p_action<>'snapshot' then raise exception 'INVALID_ACTION';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into rows from(select job_row.id,job_row.kind,catalog_row.title,catalog_row.module,job_row.source_type,job_row.source_id,job_row.state,job_row.attempts,job_row.created_at,job_row.updated_at,job_row.available_at,job_row.result,job_row.error_code,
  (select coalesce(jsonb_agg(to_jsonb(a) order by a.id desc),'[]') from private.automation_attempts a where a.job_id=job_row.id) attempts_log
  from private.automation_jobs job_row join private.automation_catalog catalog_row on catalog_row.kind=job_row.kind where private.automation_visible(catalog_row.module)
  and (coalesce(p_data->>'state','')='' or job_row.state=p_data->>'state') order by job_row.created_at desc,job_row.id limit 50 offset off)x;
 if admin then select coalesce(jsonb_agg(to_jsonb(x)),'[]') into rules from(select distinct on(rule_row.kind) rule_row.*,catalog_row.module,catalog_row.title,catalog_row.delegated from private.automation_rules rule_row join private.automation_catalog catalog_row using(kind) order by rule_row.kind,rule_row.version desc)x;else rules:='[]';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into exceptions from(select exception_row.*,p.full_name assigned_name from private.automation_exceptions exception_row left join public.profiles p on p.id=exception_row.assigned_to
  where exception_row.active and private.automation_visible(exception_row.module)
  and (coalesce(p_data->>'exception_scope','') not in ('mine','unassigned')
   or p_data->>'exception_scope'='mine' and exception_row.assigned_to=auth.uid()
   or p_data->>'exception_scope'='unassigned' and exception_row.assigned_to is null)
  and (coalesce(p_data->>'exception_due','')<>'overdue' or exception_row.due_at<now()) order by exception_row.due_at nulls last,exception_row.opened_at,exception_row.key limit 50 offset exoff)x;
 select count(*) into extotal from private.automation_exceptions exception_row where exception_row.active and private.automation_visible(exception_row.module)
  and (coalesce(p_data->>'exception_scope','') not in ('mine','unassigned')
   or p_data->>'exception_scope'='mine' and exception_row.assigned_to=auth.uid()
   or p_data->>'exception_scope'='unassigned' and exception_row.assigned_to is null)
  and (coalesce(p_data->>'exception_due','')<>'overdue' or exception_row.due_at<now());
 return jsonb_build_object('viewer_id',auth.uid(),'exception_offset',exoff,'exception_total',extotal,
  'assignees',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',coalesce(nullif(p.full_name,''),p.role)) order by p.full_name,p.id),'[]') from public.profiles p where p.active and p.role in ('administrador','comercial','almacenero') and (admin or p.id=auth.uid())),
  'as_of',now(),'admin',admin,'rules',rules,'jobs',rows,'exceptions',exceptions,'offset',off,
  'total',(select count(*) from private.automation_jobs job_row join private.automation_catalog catalog_row on catalog_row.kind=job_row.kind where private.automation_visible(catalog_row.module) and (coalesce(p_data->>'state','')='' or job_row.state=p_data->>'state')),
  'pending',(select count(*) from private.automation_jobs job_row join private.automation_catalog catalog_row on catalog_row.kind=job_row.kind where private.automation_visible(catalog_row.module) and job_row.state in ('queued','retry','blocked','dead')));
end $$;

insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column)
 values('automation_exceptions','notifications','Seguimiento de excepción','private','key');
create trigger coco_module_history after update on private.automation_exceptions for each row
 when (old.assigned_to is distinct from new.assigned_to or old.next_action is distinct from new.next_action or old.due_at is distinct from new.due_at)
 execute function private.coco_capture_module_event();
create function private.coco_exception_visible(p_key text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok() and exists(
  select 1 from private.automation_exceptions e where e.key=p_key and private.automation_visible(e.module))
$$;
revoke all on function private.coco_exception_visible(text) from public,anon,service_role;
grant execute on function private.coco_exception_visible(text) to authenticated;
-- Preserve all later history extensions, adding only this narrowly scoped table.
do $patch$ declare body text;begin
 select pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure) into body;
 if position('if cfg.table_schema=''private'' and cfg.table_name in' in body)=0 then raise exception 'HISTORY_PATCH_TARGET_CHANGED';end if;
 body:=replace(body,'if cfg.table_schema=''private'' and cfg.table_name in',
  'if cfg.table_schema=''private'' and cfg.table_name=''automation_exceptions'' then return private.coco_exception_visible(p_id);end if;
 if cfg.table_schema=''private'' and cfg.table_name in');
 execute body;
end $patch$;
-- Read-only price review filter. A small price is a review candidate, not an error.
do $patch$ declare body text;needle text;begin
 select pg_get_functiondef('private.gama_website(text,jsonb)'::regprocedure) into body;
 needle:='and (coalesce(p_data->>''category'','''')='''' or coalesce(nullif(p.category,''''),''Otros productos'')=p_data->>''category'')';
 if (length(body)-length(replace(body,needle,'')))/length(needle)<>2 then raise exception 'WEBSITE_PATCH_TARGET_CHANGED';end if;
 body:=replace(body,needle,needle||' and (coalesce(p_data->>''price_review'','''')<>''true'' or coalesce(p.sale_price,0)<=0.05)');
 execute body;
end $patch$;

-- Administrative review only: no enrollment, role change or new lockout.
create function public.coco_admin_security_review() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.erp_mfa_ok()
  or private.current_user_role()<>'administrador'
  or not private.erp_module_allowed('users',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 return jsonb_build_object('as_of',now(),'administrators',(
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,
   'verified_factor',exists(select 1 from auth.mfa_factors f where f.user_id=p.id and f.status='verified'),
   'enforced',exists(select 1 from private.mfa_enforcement e where e.actor_id=p.id)) order by p.full_name,p.id),'[]')
  from public.profiles p where p.active and p.deleted_at is null and p.role='administrador'));
end $$;
revoke all on function public.coco_admin_security_review() from public,anon,service_role;
grant execute on function public.coco_admin_security_review() to authenticated;
