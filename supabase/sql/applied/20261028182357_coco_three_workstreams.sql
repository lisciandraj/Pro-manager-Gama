-- Three additive continuations. Existing business rows and schedules are not replayed.
alter table public.accounting_assets
 add column depreciation_method text not null default 'linear' check(depreciation_method in('linear','declining','declining_linear')),
 add column declining_factor numeric check(declining_factor>0 and declining_factor<1),
 add column depreciation_prorata boolean;

-- Internal only: called from the existing audited/authorized policy command.
create function private.coco_asset_policy(p_id uuid,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.accounting_assets;m text;factor numeric;prorata boolean;first_factor numeric:=1;
 impaired numeric;remaining numeric;base numeric;weight numeric;weight_left numeric;amount numeric;n int;i int;period date;
begin
 select * into a from public.accounting_assets where id=p_id and status='active' for update;
 if not found then raise exception 'ASSET_REQUIRED';end if;
 if exists(select 1 from public.accounting_depreciations where asset_id=p_id) then raise exception 'ASSET_SCHEDULE_LOCKED';end if;
 if current_setting('coco.activity_source_type',true)='chat' then raise exception 'PLAN_HUMAN_APPROVAL_REQUIRED';end if;
 if p_data ? 'expected_policy' and p_data->'expected_policy' is distinct from jsonb_build_object('method',a.depreciation_method,'factor',a.declining_factor,'prorata',a.depreciation_prorata) then raise exception 'DOCUMENT_CHANGED';end if;
 m:=coalesce(p_data->>'method',a.depreciation_method);
 if m not in('linear','declining','declining_linear') then raise exception 'ASSET_METHOD_INVALID';end if;
 factor:=case when m='linear' then null else coalesce(nullif(p_data->>'declining_factor','')::numeric,a.declining_factor) end;
 if m<>'linear' and (factor is null or factor<=0 or factor>=1 or scale(factor)>6) then raise exception 'ASSET_FACTOR_INVALID';end if;
 prorata:=coalesce((p_data->>'prorata')::boolean,a.depreciation_prorata,false);
 if prorata and date_trunc('month',a.acquired_on)=date_trunc('month',a.first_depreciation) then
  first_factor:=((date_trunc('month',a.acquired_on)+interval '1 month')::date-a.acquired_on)::numeric/extract(day from (date_trunc('month',a.acquired_on)+interval '1 month - 1 day'));
 end if;
 select coalesce(sum(ev.amount),0) into impaired from private.accounting_asset_events ev where ev.asset_id=p_id and ev.kind='impairment';
 base:=greatest(a.cost-a.residual-impaired,0);remaining:=base;
 n:=a.months+case when first_factor<1 then 1 else 0 end;weight_left:=a.months;
 delete from private.accounting_asset_schedules where asset_id=p_id;
 for i in 0..n-1 loop
  period:=(date_trunc('month',a.first_depreciation)+make_interval(months=>i+1)-interval '1 day')::date;
  weight:=case when i=0 then first_factor when i=n-1 and first_factor<1 then 1-first_factor else 1 end;
  amount:=case when i=n-1 then remaining
   when m='linear' then round(base/a.months*weight,2)
   when m='declining' then round(remaining*factor*weight,2)
   else round(greatest(remaining*factor,remaining/weight_left)*weight,2) end;
  amount:=least(remaining,greatest(amount,0));remaining:=remaining-amount;weight_left:=weight_left-weight;
  insert into private.accounting_asset_schedules values(p_id,period,amount);
 end loop;
 update public.accounting_assets set depreciation_method=m,declining_factor=factor,depreciation_prorata=prorata where id=p_id;
 return jsonb_build_object('id',p_id,'periods',n,'method',m,'declining_factor',factor);
end $$;
revoke all on function private.coco_asset_policy(uuid,jsonb) from public,anon,authenticated,service_role;
do $$declare s text;first_anchor text:='prorata:=coalesce((p_data->>''prorata'')::boolean,false);first_factor:=1;';last_anchor text:='end loop;return jsonb_build_object(''id'',a.id,''periods'',n);';start_at int;end_at int;begin
 s:=pg_get_functiondef('private.gama_accounting_audit_write_before_payment_modes(text,jsonb)'::regprocedure);
 start_at:=strpos(s,first_anchor);end_at:=strpos(s,last_anchor);
 if start_at=0 or end_at<start_at then raise exception 'ASSET_POLICY_CONTRACT_CHANGED';end if;
 execute overlay(s placing 'return private.coco_asset_policy(a.id,p_data);' from start_at for end_at+length(last_anchor)-start_at);
end $$;

-- Observed GPS chords only. Never bridge outages, poor accuracy or implausible
-- jumps, and never describe the sum as road mileage or full-trip coverage.
create function private.coco_tms_trace(p_route uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 with points as (
  select p.*,lag(lat) over w prev_lat,lag(lng) over w prev_lng,lag(accuracy) over w prev_accuracy,lag(observed_at) over w prev_at
  from private.tms_pro_positions p where route_id=p_route window w as(order by observed_at,id)
 ), segments as (
  select *,extract(epoch from(observed_at-prev_at)) seconds,private.tms_distance(prev_lat,prev_lng,lat,lng) km from points
 ), checked as (
  select *,seconds>0 and seconds<=300 and accuracy<=50 and prev_accuracy<=50 and km<=seconds*130/3600 as usable from segments where prev_at is not null
 ) select jsonb_build_object(
  'observed_km',round((sum(km) filter(where usable))::numeric,3),
  'observed_minutes',round((coalesce(sum(seconds) filter(where usable),0)/60)::numeric,1),
  'accepted_segments',count(*) filter(where usable),'excluded_segments',count(*) filter(where not usable),
  'max_gap_seconds',max(seconds),'basis','gps_chords_partial') from checked
$$;
revoke all on function private.coco_tms_trace(uuid) from public,anon,authenticated,service_role;
do $$declare s text;anchor text:='s.duration_minutes planned_minutes,';begin
 s:=pg_get_functiondef('private.gama_tms_pro(text,jsonb)'::regprocedure);
 if strpos(s,anchor)=0 then raise exception 'TMS_ANALYTICS_CONTRACT_CHANGED';end if;
 execute replace(s,anchor,anchor||'private.coco_tms_trace(r.id) trace,');
end $$;

-- Read-only, personally assigned agenda, evaluated under original source RLS.
-- No new events, calendar tokens or external synchronization are introduced.
create function public.coco_workhub_calendar(p_data jsonb default '{}') returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare d1 date;d2 date;lim int;offst int;r jsonb;begin
 if not private.coco_workhub_allowed() then raise exception 'WORKHUB_FORBIDDEN';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>2000 then raise exception 'INVALID_REQUEST';end if;
 d1:=(p_data->>'from')::date;d2:=(p_data->>'to')::date;
 if d1 is null or d2 is null or d2<d1 or d2-d1>92 then raise exception 'WORKHUB_CALENDAR_PERIOD';end if;
 lim:=least(100,greatest(1,coalesce((p_data->>'limit')::int,40)));offst:=least(10000,greatest(0,coalesce((p_data->>'offset')::int,0)));
 with items as (
  select 'task'::text kind,i.id,i.title,left(i.description,600) body,'projects'::text module,i.project_id,i.status,
   i.due_date::text due_at,i.due_date calendar_day,i.updated_at
  from public.pm_items i where private.coco_module_allowed('projects') and i.kind='task' and i.owner_id=auth.uid()
   and i.status not in('done','cancelled') and i.due_date between d1 and d2
  union all
  select 'activity',a.id,a.subject,left(a.body,600),'crm',null,case when a.status='pendiente' then 'pending' else 'in_progress' end,a.due_at::text,
   (a.due_at at time zone private.erp_timezone())::date,a.updated_at
  from public.crm_activities a where private.coco_module_allowed('crm') and a.owner_id=auth.uid() and a.status in('pendiente','en_curso')
   and a.due_at >= (d1::timestamp at time zone private.erp_timezone()) and a.due_at < ((d2+1)::timestamp at time zone private.erp_timezone())
 ), page as(select * from items order by calendar_day,due_at,kind,id limit lim offset offst)
 select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(p) order by calendar_day,due_at,kind,id) from page p),'[]'),
  'total',(select count(*) from items),'timezone',private.erp_timezone(),'from',d1,'to',d2) into r;return r;
end $$;
revoke all on function public.coco_workhub_calendar(jsonb) from public,anon,service_role;
grant execute on function public.coco_workhub_calendar(jsonb) to authenticated;

notify pgrst, 'reload schema';
