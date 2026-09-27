-- Remove empty storage structures without deleting their movement history.
create or replace function private.gama_shelf_spaces_in_use(p_ids uuid[]) returns text[]
language sql stable security definer set search_path='' as $$
 select coalesce(array_agg(l.code order by l.code),'{}') from public.warehouse_locations l where l.id=any(p_ids) and (
  exists(select 1 from public.stock_quants q where q.location_id=l.id and (q.quantity<>0 or q.reserved_quantity<>0))
  or exists(select 1 from public.stock_reservations r where r.location_id=l.id and r.status='active')
  or exists(select 1 from public.stock_lot_balances b where b.location_id=l.id and b.quantity<>0)
  or exists(select 1 from public.purchase_orders o where o.destination_location_id=l.id and o.status not in ('received','cancelled'))
  or exists(select 1 from public.stock_adjustment_requests a where a.location_id=l.id and a.status='pending')
  or exists(select 1 from public.fulfillment_pick_lines pl join public.fulfillment_preparations p on p.id=pl.preparation_id
    where (pl.source_location_id=l.id or pl.stage_location_id=l.id) and p.status in ('queued','picking','picked','packed'))
  or exists(select 1 from public.inventory_counts c where c.warehouse_id=l.warehouse_id and c.status in ('draft','in_progress')
    and (c.scope_location_id is null or c.scope_location_id=l.id
      or exists(select 1 from public.inventory_count_lines cl where cl.count_id=c.id and cl.location_id=l.id))))
$$;
revoke all on function private.gama_shelf_spaces_in_use(uuid[]) from public,anon,authenticated;

create or replace function private.gama_shelf_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sh public.warehouse_shelves;wid uuid;cc int;rc int;pid uuid;nm text;v_code text;c int;r int;
 space text;existing public.warehouse_locations;extra uuid[];busy text[];dropped jsonb:='{"deleted":0,"archived":0}';created int:=0;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 lock table public.warehouses,public.warehouse_shelves,public.warehouse_locations,
   public.stock_quants,public.stock_reservations,public.stock_lot_balances,public.purchase_orders,
   public.inventory_counts,public.inventory_count_lines,public.stock_adjustment_requests,
   public.fulfillment_preparations,public.fulfillment_pick_lines in share row exclusive mode;
 p_data:=coalesce(p_data,'{}');
 if p_action='save' then
  cc:=nullif(p_data->>'column_count','')::int;rc:=nullif(p_data->>'row_count','')::int;
  if cc is null or rc is null or cc not between 1 and 99 or rc not between 1 and 99 then raise exception 'SHELF_SIZE_INVALID';end if;
  nm:=left(btrim(coalesce(p_data->>'name','')),120);pid:=nullif(p_data->>'parent_id','')::uuid;
  if nullif(p_data->>'id','') is null then
   wid:=nullif(p_data->>'warehouse_id','')::uuid;v_code:=upper(btrim(coalesce(p_data->>'code','')));
   if v_code !~ '^[A-Z]{2}$' then raise exception 'SHELF_CODE_INVALID';end if;
   perform 1 from public.warehouses where id=wid and active;if not found then raise exception 'WAREHOUSE_NOT_FOUND';end if;
   if exists(select 1 from public.warehouse_shelves w where w.warehouse_id=wid and w.code=v_code) then raise exception 'SHELF_CODE_TAKEN';end if;
   insert into public.warehouse_shelves(warehouse_id,code,name,column_count,row_count,parent_id,created_by,updated_by)
    values(wid,v_code,nm,cc,rc,null,auth.uid(),auth.uid()) returning * into sh;
  else
   select * into sh from public.warehouse_shelves where id=(p_data->>'id')::uuid for update;
   if not found then raise exception 'SHELF_NOT_FOUND';end if;
   if nullif(p_data->>'version','')::int is distinct from sh.version then raise exception 'SHELF_STALE';end if;
   if nullif(p_data->>'code','') is not null and upper(p_data->>'code')<>sh.code then raise exception 'SHELF_CODE_IMMUTABLE';end if;
  end if;
  if pid is not null and not exists(select 1 from public.warehouse_locations where id=pid and warehouse_id=sh.warehouse_id and shelf_id is null) then raise exception 'SHELF_PARENT_INVALID';end if;
  -- Sin zona elegida, los espacios cuelgan de la raíz del almacén si la hay.
  if pid is null then select id into pid from public.warehouse_locations where warehouse_id=sh.warehouse_id and type='warehouse' and parent_id is null order by created_at limit 1;end if;
  -- Lo que queda fuera de las nuevas medidas tiene que estar vacío.
  select array_agg(id) into extra from public.warehouse_locations where shelf_id=sh.id and not (
   substr(warehouse_locations.code,3,2)::int<=cc and substr(warehouse_locations.code,6,2)::int<=rc);
  if extra is not null then
   busy:=private.gama_shelf_spaces_in_use(extra);
   if cardinality(busy)>0 then raise exception 'SHELF_SPACE_IN_USE:%',array_to_string(busy,', ');end if;
   dropped:=private.gama_shelf_drop_spaces(extra);
  end if;
  for c in 1..cc loop for r in 1..rc loop
   space:=sh.code||lpad(c::text,2,'0')||'-'||lpad(r::text,2,'0');
   select * into existing from public.warehouse_locations where warehouse_id=sh.warehouse_id and warehouse_locations.code=space;
   if found then
    if existing.shelf_id is distinct from sh.id and not (existing.shelf_id is null and not existing.active and existing.type='bin') then
     raise exception 'SHELF_SPACE_TAKEN:%',space;
    end if;
    update public.warehouse_locations set shelf_id=sh.id,active=true,type='bin',parent_id=pid,
     name=coalesce(nullif(nm,''),'Estantería '||sh.code)||' · columna '||lpad(c::text,2,'0')||' · fila '||lpad(r::text,2,'0')
     where id=existing.id;
   else
    insert into public.warehouse_locations(warehouse_id,parent_id,code,name,type,active,shelf_id)
     values(sh.warehouse_id,pid,space,coalesce(nullif(nm,''),'Estantería '||sh.code)||' · columna '||lpad(c::text,2,'0')||' · fila '||lpad(r::text,2,'0'),'bin',true,sh.id);
    created:=created+1;
   end if;
  end loop;end loop;
  update public.warehouse_shelves set name=nm,column_count=cc,row_count=rc,parent_id=nullif(p_data->>'parent_id','')::uuid,
   version=case when nullif(p_data->>'id','') is null then version else version+1 end,updated_at=now(),updated_by=auth.uid()
   where id=sh.id returning * into sh;
  return to_jsonb(sh)||jsonb_build_object('spaces',cc*rc,'created',created,'removed',dropped);
 elsif p_action='delete' then
  select * into sh from public.warehouse_shelves where id=nullif(p_data->>'id','')::uuid for update;
  if not found then raise exception 'SHELF_NOT_FOUND';end if;
  select array_agg(id) into extra from public.warehouse_locations where shelf_id=sh.id;
  busy:=private.gama_shelf_spaces_in_use(coalesce(extra,'{}'));
  if cardinality(busy)>0 then raise exception 'SHELF_NOT_EMPTY:%',array_to_string(busy,', ');end if;
  dropped:=private.gama_shelf_drop_spaces(extra);
  delete from public.warehouse_shelves where id=sh.id;
  return jsonb_build_object('id',sh.id,'code',sh.code,'removed',dropped);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
create or replace function private.gama_warehouse_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare w public.warehouses;c text;nm text;dir text;ciudad text;v uuid;ids uuid[];busy text[];archived boolean:=false;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA';end if;
 if p_action='delete' then
  lock table public.warehouses,public.warehouse_shelves,public.warehouse_locations,
   public.stock_quants,public.stock_reservations,public.stock_lot_balances,public.purchase_orders,
   public.inventory_counts,public.inventory_count_lines,public.stock_adjustment_requests,
   public.fulfillment_preparations,public.fulfillment_pick_lines in share row exclusive mode;
  select * into w from public.warehouses where id=nullif(p_data->>'id','')::uuid and active for update;
  if not found then raise exception 'WAREHOUSE_NOT_FOUND';end if;
  select coalesce(array_agg(id),'{}') into ids from public.warehouse_locations where warehouse_id=w.id;
  busy:=private.gama_shelf_spaces_in_use(ids);
  if cardinality(busy)>0 then raise exception 'WAREHOUSE_NOT_EMPTY:%',array_to_string(busy,', ');end if;
  if exists(select 1 from public.inventory_counts where warehouse_id=w.id and status in ('draft','in_progress')) then
   raise exception 'WAREHOUSE_IN_USE';end if;
  -- Delete only unreferenced records; keep all historical foreign keys intact.
  begin
   delete from public.warehouse_shelves where warehouse_id=w.id;
   delete from public.stock_quants where location_id=any(ids) and quantity=0 and reserved_quantity=0;
   delete from public.warehouse_locations where warehouse_id=w.id;
   delete from public.warehouses where id=w.id;
  exception when foreign_key_violation then
   archived:=true;
   delete from public.warehouse_shelves where warehouse_id=w.id;
   update public.warehouse_locations set active=false,shelf_id=null where warehouse_id=w.id;
   update public.reorder_rules set active=false where warehouse_id=w.id;
   update public.warehouses set active=false,updated_at=now() where id=w.id;
  end;
  return jsonb_build_object('id',w.id,'code',w.code,'archived',archived);
 end if;
 if p_action is distinct from 'save' then raise exception 'INVALID_ACTION';end if;
 nm:=nullif(btrim(coalesce(p_data->>'name','')),'');
 if nm is null or length(nm)>120 then raise exception 'WAREHOUSE_NAME_REQUIRED';end if;
 dir:=nullif(btrim(coalesce(p_data->>'address','')),'');
 ciudad:=nullif(btrim(coalesce(p_data->>'city','')),'');
 if length(dir)>240 or length(ciudad)>120 then raise exception 'WAREHOUSE_TEXT_TOO_LONG';end if;
 if nullif(p_data->>'id','') is not null then
  select * into w from public.warehouses where id=(p_data->>'id')::uuid and active for update;
  if not found then raise exception 'WAREHOUSE_NOT_FOUND';end if;
  if nullif(btrim(coalesce(p_data->>'code','')),'') is not null and upper(btrim(p_data->>'code'))<>w.code then raise exception 'WAREHOUSE_CODE_IMMUTABLE';end if;
  update public.warehouses set name=nm,address=dir,city=ciudad,updated_at=now() where id=w.id;
  return jsonb_build_object('id',w.id,'code',w.code,'name',nm,'address',dir,'city',ciudad);
 end if;
 c:=upper(btrim(coalesce(p_data->>'code','')));
 if c !~ '^[A-Z0-9][A-Z0-9._-]{0,23}$' then raise exception 'WAREHOUSE_CODE_INVALID';end if;
 begin
  insert into public.warehouses(code,name,address,city) values(c,nm,dir,ciudad) returning id into v;
 exception when unique_violation then raise exception 'WAREHOUSE_CODE_TAKEN';
 end;
 insert into public.warehouse_locations(warehouse_id,parent_id,code,name,type,picking_priority)
  values(v,null,'STOCK','Existencias','warehouse',10);
 perform private.gama_zone(v,'arrival');
 perform private.gama_zone(v,'departure');
 perform private.gama_zone(v,'quarantine');
 return jsonb_build_object('id',v,'code',c,'name',nm,'address',dir,'city',ciudad,'created',true);
end $$;

-- An archived location must never receive fresh stock from a stale screen.
create function private.gama_quant_active_location() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.quantity<>0 or new.reserved_quantity<>0 then
  perform 1 from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id
   where l.id=new.location_id and l.active and w.active for share of l,w;
  if not found then raise exception 'LOCATION_NOT_FOUND';end if;
 end if;
 return new;
end $$;
revoke all on function private.gama_quant_active_location() from public,anon,authenticated;
create trigger gama_quant_active_location before insert or update of location_id,quantity,reserved_quantity
 on public.stock_quants for each row execute function private.gama_quant_active_location();

-- Prefer PRINCIPAL while it exists; otherwise use the first active warehouse.
create or replace function private.gama_default_location() returns uuid
language sql stable security definer set search_path='' as $$
 select l.id from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id
 where w.active and l.active and (l.role='arrival' or l.code='STOCK')
 order by (w.code='PRINCIPAL') desc,w.created_at,w.id,(l.role is not distinct from 'arrival') desc limit 1
$$;
revoke all on function private.gama_default_location() from public,anon,authenticated;
