

-- Canonical source: 20261027185533_tms_pro_planning_tracking.sql; SHA256 a41b86452245f1a14e7a65d3f31b33f294bf1cb92c156c49edda078e092f719e
-- Native extended TMS. No dependency on OptimoRoute services or private APIs.
create table private.tms_pro_settings (
 id boolean primary key default true check(id),version integer not null default 1,
 balance text not null default 'compact' check(balance in ('compact','orders','time')),
 updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id) on delete set null
);
insert into private.tms_pro_settings(id) values(true);
create table private.tms_pro_order_rules (
 delivery_id uuid primary key references public.tms_deliveries(id) on delete cascade,
 version integer not null default 1,from_day date,to_day date,
 weekdays integer[] not null default array[0,1,2,3,4,5,6] check(cardinality(weekdays)>0 and weekdays <@ array[0,1,2,3,4,5,6]),
 windows jsonb not null default '[]' check(jsonb_typeof(windows)='array' and jsonb_array_length(windows)<=3),
 skills text[] not null default '{}',features text[] not null default '{}',
 driver_id uuid references public.fleet_drivers(id) on delete restrict,
 updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id) on delete set null,
 check((from_day is null and to_day is null) or (from_day is not null and to_day>=from_day and to_day-from_day<=365))
);
create index tms_pro_rules_driver on private.tms_pro_order_rules(driver_id);
create table private.tms_pro_driver_rules (
 driver_id uuid primary key references public.fleet_drivers(id) on delete cascade,version integer not null default 1,
 skills text[] not null default '{}',shift_start time,shift_end time,
 speed_factor numeric not null default 1 check(speed_factor between 0.5 and 1.5),
 updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id) on delete set null,
 check((shift_start is null and shift_end is null) or (shift_start is not null and shift_end>shift_start))
);
create table private.tms_pro_vehicle_rules (
 vehicle_id uuid primary key references public.fleet_vehicles(id) on delete cascade,version integer not null default 1,
 features text[] not null default '{}',updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id) on delete set null
);
create table private.tms_pro_positions (
 id uuid primary key,route_id uuid not null references public.tms_routes(id) on delete cascade,
 actor_id uuid not null references public.profiles(id) on delete restrict,
 lat double precision not null check(lat between -85 and 85),lng double precision not null check(lng between -180 and 180),
 accuracy double precision not null check(accuracy between 0 and 10000),observed_at timestamptz not null,received_at timestamptz not null default now()
);
create index tms_pro_positions_route_time on private.tms_pro_positions(route_id,observed_at desc,id);
create index tms_pro_positions_actor on private.tms_pro_positions(actor_id);
create table private.tms_pro_feedback (
 delivery_id uuid primary key references public.tms_deliveries(id) on delete cascade,
 rating integer not null check(rating between 1 and 5),comment text not null default '' check(length(comment)<=1000),
 created_at timestamptz not null default now()
);
do $$declare n text;begin
 foreach n in array array['tms_pro_settings','tms_pro_order_rules','tms_pro_driver_rules','tms_pro_vehicle_rules','tms_pro_positions','tms_pro_feedback'] loop
  execute format('alter table private.%I enable row level security',n);
  execute format('revoke all on private.%I from public,anon,authenticated,service_role',n);
 end loop;
end $$;
create index tms_pro_settings_actor on private.tms_pro_settings(updated_by);
create index tms_pro_order_actor on private.tms_pro_order_rules(updated_by);
create index tms_pro_driver_actor on private.tms_pro_driver_rules(updated_by);
create index tms_pro_vehicle_actor on private.tms_pro_vehicle_rules(updated_by);

-- Sanitized history registration before any user configuration can be written.
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column,parent_column,parent_table) values
 ('tms_pro_settings','tms','Planificación TMS','private','id',null,null),
 ('tms_pro_order_rules','tms','Restricciones de entrega','private','delivery_id','delivery_id','tms_deliveries'),
 ('tms_pro_driver_rules','tms','Disponibilidad y competencias','private','driver_id','driver_id','fleet_drivers'),
 ('tms_pro_vehicle_rules','tms','Equipamiento de vehículo','private','vehicle_id','vehicle_id','fleet_vehicles'),
 ('tms_pro_feedback','tms','Opinión de entrega','private','delivery_id','delivery_id','tms_deliveries');
do $$declare n text;begin
 foreach n in array array['tms_pro_settings','tms_pro_order_rules','tms_pro_driver_rules','tms_pro_vehicle_rules','tms_pro_feedback'] loop
  execute format('create trigger coco_module_history after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',n);
 end loop;
end $$;
alter function private.coco_history_record_visible(text,text,uuid) rename to coco_history_record_visible_before_tms_pro;
create function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean language plpgsql stable security invoker set search_path='' as $$
begin
 if p_table in ('tms_pro_settings','tms_pro_order_rules','tms_pro_driver_rules','tms_pro_vehicle_rules','tms_pro_feedback') then return private.tms_scope() in ('dispatcher','manager');end if;
 return private.coco_history_record_visible_before_tms_pro(p_table,p_id,p_owner);
end $$;
revoke all on function private.coco_history_record_visible(text,text,uuid),private.coco_history_record_visible_before_tms_pro(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible(text,text,uuid),private.coco_history_record_visible_before_tms_pro(text,text,uuid) to authenticated;

create function private.tms_pro_compatible(p_delivery uuid,p_driver uuid,p_vehicle uuid,p_day date) returns boolean
language sql stable security definer set search_path='' as $$
 select not exists(select 1 from private.tms_pro_order_rules o
 left join private.tms_pro_driver_rules d on d.driver_id=p_driver
 left join private.tms_pro_vehicle_rules v on v.vehicle_id=p_vehicle
 where o.delivery_id=p_delivery and (
  (o.from_day is not null and p_day not between o.from_day and o.to_day)
  or not(extract(dow from p_day)::integer=any(o.weekdays))
  or (o.driver_id is not null and o.driver_id<>p_driver)
  or not(o.skills <@ coalesce(d.skills,'{}')) or not(o.features <@ coalesce(v.features,'{}'))))
$$;
create function private.tms_pro_service_at(p_delivery uuid,p_day date,p_arrival timestamptz) returns timestamptz
language plpgsql stable security definer set search_path='' as $$
declare rules private.tms_pro_order_rules;delivery public.tms_deliveries;stamp timestamptz;begin
 select * into rules from private.tms_pro_order_rules where delivery_id=p_delivery;
 if jsonb_array_length(coalesce(rules.windows,'[]'))>0 then
  select min(greatest(p_arrival,(p_day+(x->>'from')::time) at time zone private.erp_timezone())) into stamp
  from jsonb_array_elements(rules.windows) x where p_arrival<=(p_day+(x->>'to')::time) at time zone private.erp_timezone();
  return stamp;
 end if;
 select * into delivery from public.tms_deliveries where id=p_delivery;
 if delivery.promised_until is null then return p_arrival;end if;
 -- A weekly date choice retains the original promise for OTIF, while moving its daily clock.
 stamp:=greatest(p_arrival,(p_day+(delivery.promised_from at time zone private.erp_timezone())::time) at time zone private.erp_timezone());
 if stamp>(p_day+(delivery.promised_until at time zone private.erp_timezone())::time) at time zone private.erp_timezone() then return null;end if;
 return stamp;
end $$;
create function private.tms_pro_travel(a double precision,b double precision,c double precision,d double precision,p_driver uuid) returns integer
language sql stable security definer set search_path='' as $$
 select ceil(private.tms_travel_minutes(a,b,c,d)/coalesce((select speed_factor from private.tms_pro_driver_rules where driver_id=p_driver),1))::integer
$$;