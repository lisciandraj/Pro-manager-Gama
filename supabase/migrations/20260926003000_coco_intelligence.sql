-- Coco Intelligence V1 — deterministic inventory intelligence + recommendations.
-- The LLM explains these values; it never computes or writes stock policy.
create table if not exists public.coco_inventory_intelligence (
 product_id uuid primary key references public.products(id) on delete cascade,
 calculated_at timestamptz not null default now(),
 demand_30d numeric not null default 0,
 demand_60d numeric not null default 0,
 demand_90d numeric not null default 0,
 avg_daily_demand numeric not null default 0,
 physical_stock numeric not null default 0,
 reserved_stock numeric not null default 0,
 available_stock numeric not null default 0,
 incoming_stock numeric not null default 0,
 lead_time_days numeric not null default 7,
 safety_stock numeric not null default 0,
 recommended_min numeric not null default 0,
 recommended_max numeric not null default 0,
 recommended_order_qty numeric not null default 0,
 days_of_cover numeric,
 confidence numeric not null default 0 check(confidence between 0 and 100),
 calculation_version text not null default 'inventory-v1'
);
create table if not exists public.coco_recommendations (
 id uuid primary key default gen_random_uuid(),
 module text not null,
 entity_type text not null,
 entity_id uuid not null,
 recommendation_type text not null,
 priority text not null check(priority in ('low','medium','high','critical')),
 title text not null,
 confidence numeric not null default 0 check(confidence between 0 and 100),
 current_value jsonb not null default '{}'::jsonb,
 recommended_value jsonb not null default '{}'::jsonb,
 reasoning jsonb not null default '{}'::jsonb,
 status text not null default 'pending' check(status in ('pending','accepted','modified','rejected','expired')),
 created_at timestamptz not null default now(),
 reviewed_at timestamptz,
 reviewed_by uuid references auth.users(id) on delete set null
);
create unique index if not exists coco_recommendations_open_inventory_idx
 on public.coco_recommendations(entity_id,recommendation_type) where module='inventory' and status='pending';
alter table public.coco_inventory_intelligence enable row level security;
alter table public.coco_recommendations enable row level security;
create policy coco_inventory_read on public.coco_inventory_intelligence for select to authenticated using(private.is_staff());
create policy coco_recommendations_read on public.coco_recommendations for select to authenticated using(private.is_staff());
revoke insert,update,delete on public.coco_inventory_intelligence from authenticated;
revoke insert,update,delete on public.coco_recommendations from authenticated;

create or replace function public.gama_coco_inventory_analyze()
returns jsonb language plpgsql security definer set search_path='public','private' as $$
declare r record; v_count int:=0; v_now timestamptz:=now();
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if private.current_user_role() <> 'administrador' then raise exception 'ADMIN_REQUIRED'; end if;
 for r in
  with demand as (
   select p.id product_id,
    coalesce(sum(sm.quantity) filter(where sm.created_at>=v_now-interval '30 days' and sm.type='out' and coalesce(sm.movement_type,'') not in ('internal_transfer','inventory_adjustment')),0) d30,
    coalesce(sum(sm.quantity) filter(where sm.created_at>=v_now-interval '60 days' and sm.type='out' and coalesce(sm.movement_type,'') not in ('internal_transfer','inventory_adjustment')),0) d60,
    coalesce(sum(sm.quantity) filter(where sm.created_at>=v_now-interval '90 days' and sm.type='out' and coalesce(sm.movement_type,'') not in ('internal_transfer','inventory_adjustment')),0) d90
   from products p left join stock_movements sm on sm.product_id=p.id where p.active group by p.id
  ), stock as (
   select p.id product_id,coalesce(sum(q.quantity),0) physical,coalesce(sum(q.reserved_quantity),0) reserved
   from products p left join stock_quants q on q.product_id=p.id where p.active group by p.id
  ), incoming as (
   select pol.product_id,coalesce(sum(greatest(pol.quantity-coalesce(pol.received_quantity,0),0)),0) qty
   from purchase_order_lines pol join purchase_orders po on po.id=pol.purchase_order_id
   where po.status in ('draft','sent','partial') group by pol.product_id
  ), rules as (
   select distinct on(product_id) product_id,coalesce(lead_time_days,7) lead_days,min_quantity,max_quantity
   from reorder_rules where active order by product_id,warehouse_id nulls first
  )
  select p.id,p.name,d.d30,d.d60,d.d90,s.physical,s.reserved,coalesce(i.qty,0) incoming,
   coalesce(rr.lead_days,7) lead_days,
   ((d.d30/30.0)*.5+(d.d60/60.0)*.3+(d.d90/90.0)*.2) avgd,
   coalesce(rr.min_quantity,p.min_stock,0) current_min,coalesce(rr.max_quantity,p.max_stock,0) current_max,
   least(100,greatest(20,(case when d.d90>0 then 45 else 15 end)+(case when rr.lead_days is not null then 25 else 5 end)+(case when d.d30>0 then 20 else 5 end))) confidence
  from products p join demand d on d.product_id=p.id join stock s on s.product_id=p.id
  left join incoming i on i.product_id=p.id left join rules rr on rr.product_id=p.id where p.active
 loop
  -- V1 safety stock: 50% of expected lead-time demand. Conservative and transparent until daily variance history is mature.
  insert into coco_inventory_intelligence(product_id,calculated_at,demand_30d,demand_60d,demand_90d,avg_daily_demand,
   physical_stock,reserved_stock,available_stock,incoming_stock,lead_time_days,safety_stock,recommended_min,recommended_max,
   recommended_order_qty,days_of_cover,confidence)
  values(r.id,v_now,r.d30,r.d60,r.d90,round(r.avgd,3),r.physical,r.reserved,greatest(r.physical-r.reserved,0),r.incoming,r.lead_days,
   ceil(r.avgd*r.lead_days*.5),ceil(r.avgd*r.lead_days*1.5),ceil(r.avgd*(r.lead_days+14)+r.avgd*r.lead_days*.5),
   greatest(0,ceil(r.avgd*(r.lead_days+14)+r.avgd*r.lead_days*.5)-greatest(r.physical-r.reserved,0)-r.incoming),
   case when r.avgd>0 then round(greatest(r.physical-r.reserved,0)/r.avgd,1) end,r.confidence)
  on conflict(product_id) do update set calculated_at=excluded.calculated_at,demand_30d=excluded.demand_30d,demand_60d=excluded.demand_60d,
   demand_90d=excluded.demand_90d,avg_daily_demand=excluded.avg_daily_demand,physical_stock=excluded.physical_stock,
   reserved_stock=excluded.reserved_stock,available_stock=excluded.available_stock,incoming_stock=excluded.incoming_stock,
   lead_time_days=excluded.lead_time_days,safety_stock=excluded.safety_stock,recommended_min=excluded.recommended_min,
   recommended_max=excluded.recommended_max,recommended_order_qty=excluded.recommended_order_qty,days_of_cover=excluded.days_of_cover,
   confidence=excluded.confidence,calculation_version=excluded.calculation_version;
  if r.avgd>0 and (r.physical-r.reserved+r.incoming) < ceil(r.avgd*r.lead_days*1.5) then
   insert into coco_recommendations(module,entity_type,entity_id,recommendation_type,priority,title,confidence,current_value,recommended_value,reasoning)
   values('inventory','product',r.id,'reorder',
    case when (r.physical-r.reserved) < r.avgd*r.lead_days then 'critical' else 'high' end,
    'Réapprovisionnement recommandé · '||r.name,r.confidence,
    jsonb_build_object('available_stock',greatest(r.physical-r.reserved,0),'incoming_stock',r.incoming,'min',r.current_min,'max',r.current_max),
    (select jsonb_build_object('min',recommended_min,'max',recommended_max,'order_qty',recommended_order_qty) from coco_inventory_intelligence where product_id=r.id),
    jsonb_build_object('demand_30d',r.d30,'demand_60d',r.d60,'demand_90d',r.d90,'avg_daily_demand',round(r.avgd,3),'lead_time_days',r.lead_days))
   on conflict(entity_id,recommendation_type) where module='inventory' and status='pending'
   do update set priority=excluded.priority,title=excluded.title,confidence=excluded.confidence,current_value=excluded.current_value,
    recommended_value=excluded.recommended_value,reasoning=excluded.reasoning,created_at=v_now;
  else
   update coco_recommendations set status='expired',reviewed_at=v_now
    where module='inventory' and entity_id=r.id and recommendation_type='reorder' and status='pending';
  end if;
  v_count:=v_count+1;
 end loop;
 return jsonb_build_object('products_analyzed',v_count,'calculated_at',v_now);
end $$;
revoke all on function public.gama_coco_inventory_analyze() from public,anon,authenticated;
grant execute on function public.gama_coco_inventory_analyze() to authenticated;
