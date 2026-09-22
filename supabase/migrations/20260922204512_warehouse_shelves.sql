-- Estanterías simuladas: cada almacén describe sus estanterías (dos letras,
-- número de columnas y de filas) y el servidor genera un espacio de
-- almacenamiento por celda con la referencia AAXX-XX —estantería, columna,
-- fila—. Los espacios son ubicaciones de verdad (warehouse_locations), así
-- que aparecen en todos los desplegables que ya listan ubicaciones.
create table public.warehouse_shelves(
 id uuid primary key default gen_random_uuid(),
 warehouse_id uuid not null references public.warehouses(id) on delete cascade,
 code text not null check(code ~ '^[A-Z]{2}$'),
 name text not null default '' check(length(name)<=120),
 column_count smallint not null check(column_count between 1 and 99),
 row_count smallint not null check(row_count between 1 and 99),
 parent_id uuid references public.warehouse_locations(id) on delete set null,
 version integer not null default 1,
 created_at timestamptz not null default now(),
 created_by uuid references auth.users(id),
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id),
 unique(warehouse_id,code)
);
create index warehouse_shelves_parent_id on public.warehouse_shelves(parent_id);
create index warehouse_shelves_created_by on public.warehouse_shelves(created_by);
create index warehouse_shelves_updated_by on public.warehouse_shelves(updated_by);
alter table public.warehouse_shelves enable row level security;
revoke all on public.warehouse_shelves from public,anon,authenticated;
grant select on public.warehouse_shelves to authenticated;
create policy warehouse_shelves_read on public.warehouse_shelves for select to authenticated using(private.is_staff());
create trigger erp_audit_capture after insert or update or delete on public.warehouse_shelves
 for each row execute function private.erp_audit_capture();

alter table public.warehouse_locations add column shelf_id uuid references public.warehouse_shelves(id) on delete set null;
create index warehouse_locations_shelf_id on public.warehouse_locations(shelf_id);

-- Un espacio está en uso si guarda existencias, reservas o lotes, o si una
-- compra abierta lo tiene como destino. Sólo los vacíos se quitan.
create function private.gama_shelf_spaces_in_use(p_ids uuid[]) returns text[]
language sql stable security definer set search_path='' as $$
 select coalesce(array_agg(l.code order by l.code),'{}') from public.warehouse_locations l where l.id=any(p_ids) and (
  exists(select 1 from public.stock_quants q where q.location_id=l.id and (q.quantity<>0 or q.reserved_quantity<>0))
  or exists(select 1 from public.stock_reservations r where r.location_id=l.id and r.status='active')
  or exists(select 1 from public.stock_lot_balances b where b.location_id=l.id and b.quantity<>0)
  or exists(select 1 from public.purchase_orders o where o.destination_location_id=l.id and o.status not in ('received','cancelled')))
$$;
revoke all on function private.gama_shelf_spaces_in_use(uuid[]) from public,anon,authenticated;

-- Quita espacios vacíos: se borran si nada los nombra y, si el historial los
-- nombra (movimientos, recuentos…), se archivan para no romperlo.
create function private.gama_shelf_drop_spaces(p_ids uuid[]) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s uuid;deleted int:=0;archived int:=0;
begin
 foreach s in array coalesce(p_ids,'{}') loop
  begin
   delete from public.stock_quants where location_id=s and quantity=0 and reserved_quantity=0;
   delete from public.warehouse_locations where id=s;deleted:=deleted+1;
  exception when foreign_key_violation then
   update public.warehouse_locations set active=false,shelf_id=null where id=s;archived:=archived+1;
  end;
 end loop;
 return jsonb_build_object('deleted',deleted,'archived',archived);
end $$;
revoke all on function private.gama_shelf_drop_spaces(uuid[]) from public,anon,authenticated;

create function private.gama_shelf_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sh public.warehouse_shelves;wid uuid;cc int;rc int;pid uuid;nm text;v_code text;c int;r int;
 space text;existing public.warehouse_locations;extra uuid[];busy text[];dropped jsonb:='{"deleted":0,"archived":0}';created int:=0;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 p_data:=coalesce(p_data,'{}');
 if p_action='save' then
  cc:=nullif(p_data->>'column_count','')::int;rc:=nullif(p_data->>'row_count','')::int;
  if cc is null or rc is null or cc not between 1 and 99 or rc not between 1 and 99 then raise exception 'SHELF_SIZE_INVALID';end if;
  nm:=left(btrim(coalesce(p_data->>'name','')),120);pid:=nullif(p_data->>'parent_id','')::uuid;
  if nullif(p_data->>'id','') is null then
   wid:=nullif(p_data->>'warehouse_id','')::uuid;v_code:=upper(btrim(coalesce(p_data->>'code','')));
   if v_code !~ '^[A-Z]{2}$' then raise exception 'SHELF_CODE_INVALID';end if;
   perform 1 from public.warehouses where id=wid;if not found then raise exception 'WAREHOUSE_NOT_FOUND';end if;
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
revoke all on function private.gama_shelf_action(text,jsonb) from public,anon;
grant execute on function private.gama_shelf_action(text,jsonb) to authenticated;
create function public.gama_shelf_action(p_action text,p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.gama_shelf_action(p_action,p_data)$$;
revoke all on function public.gama_shelf_action(text,jsonb) from public,anon;
grant execute on function public.gama_shelf_action(text,jsonb) to authenticated;
