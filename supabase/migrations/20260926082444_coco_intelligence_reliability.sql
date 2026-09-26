-- Coco Intelligence: guarded cache refresh, explainable stock policy and paged reads.
-- Business stock, thresholds and purchase orders are never changed by this engine.
alter table public.coco_inventory_intelligence add column if not exists draft_purchase_stock numeric not null default 0;

create or replace function private.coco_admin_allowed()
returns boolean language sql stable security invoker set search_path='' as $$
 select auth.uid() is not null
  and private.current_user_role() is not distinct from 'administrador'
  and not exists(select 1 from public.app_modules where id='assistant-ia' and not enabled)
$$;
revoke all on function private.coco_admin_allowed() from public,anon;
grant execute on function private.coco_admin_allowed() to authenticated;
revoke all on public.coco_inventory_intelligence,public.coco_recommendations from public,anon,authenticated;
grant select on public.coco_inventory_intelligence,public.coco_recommendations to authenticated;
drop policy if exists coco_inventory_read on public.coco_inventory_intelligence;
drop policy if exists coco_recommendations_read on public.coco_recommendations;
create policy coco_inventory_read on public.coco_inventory_intelligence for select to authenticated using((select private.coco_admin_allowed()));
create policy coco_recommendations_read on public.coco_recommendations for select to authenticated using((select private.coco_admin_allowed()));

create or replace function private.coco_inventory_refresh()
returns jsonb language plpgsql security definer set search_path='' as $$
declare r record; v_now timestamptz:=now(); v_count integer:=0;
 v_min numeric; v_max numeric; v_qty numeric; v_safety numeric; v_available numeric; v_kind text;
begin
 if not private.coco_admin_allowed() then raise exception 'ADMIN_REQUIRED' using errcode='42501'; end if;
 if not pg_try_advisory_xact_lock(260926,1) then raise exception 'ANALYSIS_BUSY' using errcode='55P03'; end if;
 for r in
  with demand as (
   select sm.product_id,
    sum(sm.quantity) filter(where sm.created_at>=v_now-interval '30 days') d30,
    sum(sm.quantity) filter(where sm.created_at>=v_now-interval '60 days') d60,
    sum(sm.quantity) d90, count(distinct sm.created_at::date) demand_days,
    extract(day from v_now-min(sm.created_at)) history_days
   from public.stock_movements sm
   where sm.type='out' and sm.quantity>0 and sm.created_at between v_now-interval '90 days' and v_now
    and (sm.movement_type is null or sm.movement_type in ('delivery','manual_out','production_out'))
   group by sm.product_id
  ), stock as (
   select product_id,sum(quantity) physical,sum(reserved_quantity) reserved from public.stock_quants group by product_id
  ), incoming as (
   select l.product_id,
    sum(greatest(l.quantity-coalesce(l.received_quantity,0),0)) filter(where o.status in ('sent','partial')) qty,
    sum(greatest(l.quantity-coalesce(l.received_quantity,0),0)) filter(where o.status='draft') draft_qty
   from public.purchase_order_lines l join public.purchase_orders o on o.id=l.purchase_order_id
   where o.status in ('draft','sent','partial') group by l.product_id
  ), rules as (
   -- A global rule takes precedence; otherwise combine warehouse policies.
   select product_id,coalesce(max(lead_time_days) filter(where warehouse_id is null),max(lead_time_days),7) lead_days,
    coalesce(max(min_quantity) filter(where warehouse_id is null),sum(min_quantity)) min_qty,
    coalesce(max(max_quantity) filter(where warehouse_id is null),sum(max_quantity)) max_qty
   from public.reorder_rules where active group by product_id
  )
  select p.id,p.name,coalesce(d.d30,0) d30,coalesce(d.d60,0) d60,coalesce(d.d90,0) d90,
   coalesce(d.demand_days,0) demand_days,coalesce(d.history_days,0) history_days,
   coalesce(s.physical,p.stock,0) physical,coalesce(s.reserved,0) reserved,
   coalesce(i.qty,0) incoming,coalesce(i.draft_qty,0) draft_qty,
   greatest(coalesce(rr.lead_days,7),1) lead_days,rr.product_id is not null lead_configured,
   coalesce(d.d30,0)/30.0*.5+coalesce(d.d60,0)/60.0*.3+coalesce(d.d90,0)/90.0*.2 avgd,
   greatest(coalesce(rr.min_qty,p.min_stock,0),0) current_min,
   greatest(coalesce(rr.max_qty,p.max_stock,0),coalesce(rr.min_qty,p.min_stock,0),0) current_max,
   case when coalesce(d.d90,0)=0 then 20
    else least(90,30+least(40,coalesce(d.history_days,0)*40/90)+least(10,coalesce(d.demand_days,0))+case when rr.product_id is not null then 10 else 0 end) end confidence
  from public.products p left join demand d on d.product_id=p.id left join stock s on s.product_id=p.id
  left join incoming i on i.product_id=p.id left join rules rr on rr.product_id=p.id
  where p.active and p.product_kind='goods'
 loop
  v_available:=greatest(r.physical-r.reserved,0);
  v_safety:=ceil(r.avgd*r.lead_days*.5);
  -- Without observed demand retain the configured policy, never recommend zeroing it.
  v_min:=case when r.avgd>0 then ceil(r.avgd*r.lead_days*1.5) else r.current_min end;
  v_max:=case when r.avgd>0 then ceil(r.avgd*(r.lead_days+14)+r.avgd*r.lead_days*.5) else r.current_max end;
  v_qty:=case when v_available+r.incoming+r.draft_qty<v_min
   then greatest(0,ceil(v_max-v_available-r.incoming-r.draft_qty)) else 0 end;
  insert into public.coco_inventory_intelligence(product_id,calculated_at,demand_30d,demand_60d,demand_90d,avg_daily_demand,
   physical_stock,reserved_stock,available_stock,incoming_stock,draft_purchase_stock,lead_time_days,safety_stock,
   recommended_min,recommended_max,recommended_order_qty,days_of_cover,confidence,calculation_version)
  values(r.id,v_now,r.d30,r.d60,r.d90,round(r.avgd,3),r.physical,r.reserved,v_available,r.incoming,r.draft_qty,r.lead_days,v_safety,
   v_min,v_max,v_qty,case when r.avgd>0 then round(v_available/r.avgd,1) end,round(r.confidence),'inventory-v1.1')
  on conflict(product_id) do update set calculated_at=excluded.calculated_at,demand_30d=excluded.demand_30d,
   demand_60d=excluded.demand_60d,demand_90d=excluded.demand_90d,avg_daily_demand=excluded.avg_daily_demand,
   physical_stock=excluded.physical_stock,reserved_stock=excluded.reserved_stock,available_stock=excluded.available_stock,
   incoming_stock=excluded.incoming_stock,draft_purchase_stock=excluded.draft_purchase_stock,lead_time_days=excluded.lead_time_days,
   safety_stock=excluded.safety_stock,recommended_min=excluded.recommended_min,recommended_max=excluded.recommended_max,
   recommended_order_qty=excluded.recommended_order_qty,days_of_cover=excluded.days_of_cover,confidence=excluded.confidence,
   calculation_version=excluded.calculation_version;
  v_kind:=case when v_qty>0 then 'reorder'
   when r.avgd>0 and (v_min<>r.current_min or v_max<>r.current_max) then 'stock_policy' end;
  update public.coco_recommendations set status='expired',reviewed_at=v_now
   where module='inventory' and entity_id=r.id and status='pending' and recommendation_type is distinct from v_kind;
  if v_kind is not null then
   insert into public.coco_recommendations(module,entity_type,entity_id,recommendation_type,priority,title,confidence,current_value,recommended_value,reasoning)
   values('inventory','product',r.id,v_kind,
    case when v_kind='stock_policy' then 'medium' when v_available<=0 or (r.avgd>0 and v_available<r.avgd*r.lead_days) then 'critical' else 'high' end,
    r.name,round(r.confidence),
    jsonb_build_object('available_stock',v_available,'physical_stock',r.physical,'reserved_stock',r.reserved,
     'incoming_stock',r.incoming,'draft_purchase_stock',r.draft_qty,'min',r.current_min,'max',r.current_max),
    jsonb_build_object('min',v_min,'max',v_max,'order_qty',v_qty),
    jsonb_build_object('basis',case when r.avgd>0 then 'observed_demand' else 'configured_thresholds' end,
     'demand_30d',r.d30,'demand_60d',r.d60,'demand_90d',r.d90,'avg_daily_demand',round(r.avgd,3),
     'demand_days',r.demand_days,'history_days',r.history_days,'lead_time_days',r.lead_days,'lead_time_configured',r.lead_configured,
     'safety_stock',v_safety,'days_of_cover',case when r.avgd>0 then round(v_available/r.avgd,1) end,
     'review_days',14,'calculation_version','inventory-v1.1'))
   on conflict(entity_id,recommendation_type) where module='inventory' and status='pending'
   do update set priority=excluded.priority,title=excluded.title,confidence=excluded.confidence,current_value=excluded.current_value,
    recommended_value=excluded.recommended_value,reasoning=excluded.reasoning,created_at=v_now;
  end if;
  v_count:=v_count+1;
 end loop;
 update public.coco_recommendations stale set status='expired',reviewed_at=v_now where module='inventory' and status='pending'
  and not exists(select 1 from public.products p where p.id=stale.entity_id and p.active and p.product_kind='goods');
 delete from public.coco_inventory_intelligence i where not exists(select 1 from public.products p where p.id=i.product_id and p.active and p.product_kind='goods');
 return jsonb_build_object('products_analyzed',v_count,'calculated_at',v_now);
end $$;
revoke all on function private.coco_inventory_refresh() from public,anon;
grant execute on function private.coco_inventory_refresh() to authenticated;
create or replace function public.gama_coco_inventory_analyze()
returns jsonb language sql security invoker set search_path='' as $$select private.coco_inventory_refresh()$$;
revoke all on function public.gama_coco_inventory_analyze() from public,anon,authenticated;
grant execute on function public.gama_coco_inventory_analyze() to authenticated;

drop function public.gama_coco_inventory_overview();
create function public.gama_coco_inventory_overview(p_limit integer default 25,p_offset integer default 0)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v_total integer;
begin
 if not private.coco_admin_allowed() then raise exception 'ADMIN_REQUIRED' using errcode='42501'; end if;
 if p_limit is null or p_limit<1 or p_limit>100 or p_offset is null or p_offset<0 or p_offset>100000 then
  raise exception 'INVALID_PAGE' using errcode='22023'; end if;
 select count(*) into v_total from public.coco_recommendations r join public.products p on p.id=r.entity_id
  where r.module='inventory' and r.status='pending' and p.active and p.product_kind='goods';
 return jsonb_build_object(
  'calculated_at',(select max(calculated_at) from public.coco_inventory_intelligence),
  'products_analyzed',(select count(*) from public.coco_inventory_intelligence i join public.products p on p.id=i.product_id where p.active and p.product_kind='goods'),
  'without_history',(select count(*) from public.coco_inventory_intelligence i join public.products p on p.id=i.product_id where p.active and p.product_kind='goods' and i.demand_90d=0),
  'recommendation_count',v_total,'offset',p_offset,'limit',p_limit,'has_more',p_offset+p_limit<v_total,
  'reorder_count',(select count(*) from public.coco_recommendations r join public.products p on p.id=r.entity_id where r.module='inventory' and r.status='pending' and p.active and p.product_kind='goods' and r.recommendation_type='reorder'),
  'critical_count',(select count(*) from public.coco_recommendations r join public.products p on p.id=r.entity_id where r.module='inventory' and r.status='pending' and p.active and p.product_kind='goods' and r.priority='critical'),
  'recommended_units',(select coalesce(sum((r.recommended_value->>'order_qty')::numeric),0) from public.coco_recommendations r join public.products p on p.id=r.entity_id where r.module='inventory' and r.status='pending' and p.active and p.product_kind='goods' and r.recommendation_type='reorder'),
  'recommendations',(select coalesce(jsonb_agg(to_jsonb(q) order by q.rank,q.product_name,q.id),'[]'::jsonb) from (
   select r.id,r.entity_id product_id,p.name product_name,p.reference,p.supplier_id,r.title,r.recommendation_type,r.priority,r.confidence,
    r.current_value,r.recommended_value,r.reasoning,
    case r.priority when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end rank
   from public.coco_recommendations r join public.products p on p.id=r.entity_id
   where r.module='inventory' and r.status='pending' and p.active and p.product_kind='goods'
   order by rank,p.name,r.id limit p_limit offset p_offset
  ) q)
 );
end $$;
revoke all on function public.gama_coco_inventory_overview(integer,integer) from public,anon,authenticated;
grant execute on function public.gama_coco_inventory_overview(integer,integer) to authenticated;
