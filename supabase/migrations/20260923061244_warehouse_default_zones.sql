-- Otras ubicaciones, a medida. Cada almacén trae tres zonas con un papel
-- —llegada, salida y cuarentena— y el resto lo crea, renombra o quita quien
-- gestiona el almacén. Los procesos usan esas zonas por su papel, no por un
-- código escrito a mano:
--   · las recepciones y las entradas manuales llegan a la zona de llegada;
--   · la preparación de pedidos deja lo preparado en la zona de salida (antes
--     creaba una zona PR-… por preparación, que llenaba la lista);
--   · las devoluciones de clientes esperan en cuarentena (antes RET-QUARANTINE).
-- Las zonas con papel se renombran pero no se borran. Lo que había en las
-- demás ubicaciones pasa a la zona de llegada con su movimiento; las
-- ubicaciones se borran, o se archivan si el historial las nombra.

alter table public.warehouse_locations add column role text
 constraint warehouse_locations_role_check check (role in ('arrival','departure','quarantine'));
create unique index warehouse_locations_role_key on public.warehouse_locations(warehouse_id,role) where role is not null;

-- La raíz del almacén (tipo 'warehouse', sin padre): el almacén en sí, no un sitio.
create function private.gama_warehouse_root(p_warehouse uuid) returns uuid
language sql stable security definer set search_path='' as $$
 select id from public.warehouse_locations
  where warehouse_id=p_warehouse and type='warehouse' and parent_id is null
  order by (code='STOCK') desc,created_at limit 1
$$;
revoke all on function private.gama_warehouse_root(uuid) from public,anon,authenticated;

-- La zona de un papel en un almacén; si falta, se crea con su nombre por defecto.
-- Sin código de barras propio, como los espacios de estantería: el índice de
-- códigos de barras es único en todos los almacenes.
create function private.gama_zone(p_warehouse uuid,p_role text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v uuid;c text;n text;
begin
 select id into v from public.warehouse_locations where warehouse_id=p_warehouse and role=p_role;
 if v is not null then return v;end if;
 c:=case p_role when 'arrival' then 'LLEGADA' when 'departure' then 'SALIDA' when 'quarantine' then 'CUARENTENA' end;
 n:=case p_role when 'arrival' then 'Zona de llegada' when 'departure' then 'Zona de salida' when 'quarantine' then 'Cuarentena' end;
 if c is null then raise exception 'LOCATION_ROLE_INVALID';end if;
 insert into public.warehouse_locations(warehouse_id,parent_id,code,name,type,role,active)
  values(p_warehouse,private.gama_warehouse_root(p_warehouse),c,n,'zone',p_role,true)
  on conflict(warehouse_id,code) do update set role=excluded.role,active=true
  returning id into v;
 return v;
end $$;
revoke all on function private.gama_zone(uuid,text) from public,anon,authenticated;

-- Las recepciones y las entradas sin ubicación llegan a la zona de llegada del
-- almacén principal; la raíz STOCK queda como último recurso.
create or replace function private.gama_default_location() returns uuid
language sql stable security definer set search_path to 'public','private' as $$
 select l.id from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id
  where w.code='PRINCIPAL' and l.active and (l.role='arrival' or l.code='STOCK')
  order by (l.role is not distinct from 'arrival') desc limit 1;
$$;

-- Vacía las otras ubicaciones de un almacén: todo menos la raíz, las
-- estanterías y las zonas con papel. Las existencias pasan a la zona de
-- llegada con un movimiento de transferencia interna; lo que estaba pendiente
-- de salir de ellas (preparaciones abiertas, compras por recibir) apunta a la
-- zona de llegada. El total de cada producto no cambia, así que no hay que
-- recalcularlo. Una ubicación se borra si nada la nombra y, si el historial la
-- nombra, se archiva.
create function private.gama_locations_reset(p_warehouse uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare root uuid:=private.gama_warehouse_root(p_warehouse);arr uuid;q record;x record;before_qty numeric;
 moved int:=0;deleted int:=0;archived int:=0;
begin
 -- La cuarentena de devoluciones que ya existía es la zona de cuarentena.
 update public.warehouse_locations set role='quarantine',code='CUARENTENA',name='Cuarentena',barcode=null,parent_id=root,active=true
  where warehouse_id=p_warehouse and code='RET-QUARANTINE' and role is null
    and not exists(select 1 from public.warehouse_locations c where c.warehouse_id=p_warehouse and (c.code='CUARENTENA' or c.role='quarantine'));
 arr:=private.gama_zone(p_warehouse,'arrival');
 perform private.gama_zone(p_warehouse,'departure');perform private.gama_zone(p_warehouse,'quarantine');
 create temporary table if not exists gama_reset_targets(id uuid primary key) on commit drop;
 delete from gama_reset_targets;
 insert into gama_reset_targets select id from public.warehouse_locations where warehouse_id=p_warehouse and shelf_id is null and role is null;
 if exists(select 1 from public.stock_reservations r join gama_reset_targets t on t.id=r.location_id where r.status='active')
  or exists(select 1 from public.stock_quants s join gama_reset_targets t on t.id=s.location_id where s.reserved_quantity<>0 or s.quantity<0)
 then raise exception 'LOCATION_RESET_RESERVED';end if;
 for q in select s.* from public.stock_quants s join gama_reset_targets t on t.id=s.location_id where s.quantity>0 order by s.product_id,s.location_id loop
  perform 1 from public.products where id=q.product_id for update;
  select coalesce(sum(quantity),0) into before_qty from public.stock_quants where product_id=q.product_id;
  update public.stock_quants set quantity=0,updated_at=now() where id=q.id;
  insert into public.stock_quants(product_id,location_id,quantity,reserved_quantity) values(q.product_id,arr,q.quantity,0)
   on conflict(product_id,location_id) do update set quantity=public.stock_quants.quantity+excluded.quantity,updated_at=now();
  insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,stock_before,stock_after,source_location_id,destination_location_id,movement_type)
   values(q.product_id,'adjustment',q.quantity,'Reorganización de ubicaciones','Otras ubicaciones vaciadas: pasa a la zona de llegada.',auth.uid(),before_qty,before_qty,q.location_id,arr,'internal_transfer');
  moved:=moved+1;
 end loop;
 update public.fulfillment_pick_lines pl set source_location_id=arr
  from public.fulfillment_preparations p,gama_reset_targets t
  where p.id=pl.preparation_id and t.id=pl.source_location_id and p.status in ('queued','picking') and pl.picked<pl.planned;
 update public.purchase_orders o set destination_location_id=arr from gama_reset_targets t
  where t.id=o.destination_location_id and o.status not in ('received','cancelled');
 update public.warehouse_shelves s set parent_id=null from gama_reset_targets t where t.id=s.parent_id;
 update public.warehouse_locations l set parent_id=root from gama_reset_targets t
  where t.id=l.parent_id and (l.shelf_id is not null or l.role is not null);
 -- De las hojas a la raíz: un padre se quita después que sus hijos.
 for x in with recursive tree as (
   select id,0 depth from public.warehouse_locations where warehouse_id=p_warehouse and parent_id is null
   union all select l.id,tree.depth+1 from public.warehouse_locations l join tree on l.parent_id=tree.id)
  select tree.id from tree join gama_reset_targets t on t.id=tree.id join public.warehouse_locations l on l.id=tree.id
  where tree.id is distinct from root and l.active order by tree.depth desc loop
  begin
   delete from public.stock_quants where location_id=x.id and quantity=0 and reserved_quantity=0;
   delete from public.warehouse_locations where id=x.id;deleted:=deleted+1;
  exception when foreign_key_violation then
   update public.warehouse_locations set active=false where id=x.id;archived:=archived+1;
  end;
 end loop;
 return jsonb_build_object('arrival',arr,'moved',moved,'deleted',deleted,'archived',archived);
end $$;
revoke all on function private.gama_locations_reset(uuid) from public,anon,authenticated;

-- Crear, renombrar y quitar otras ubicaciones. El código se elige al crear y
-- ya no cambia; no puede tener la forma de un espacio de estantería (AAXX-XX).
-- Sólo se quita lo vacío y lo que ningún proceso tiene pendiente.
create function private.gama_location_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare l public.warehouse_locations;w uuid;c text;nm text;v uuid;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA';end if;
 if p_action='save' then
  nm:=nullif(btrim(coalesce(p_data->>'name','')),'');
  if nm is null or length(nm)>120 then raise exception 'LOCATION_NAME_REQUIRED';end if;
  if nullif(p_data->>'id','') is not null then
   select * into l from public.warehouse_locations where id=(p_data->>'id')::uuid for update;
   if not found or l.shelf_id is not null or l.type='warehouse' or not l.active then raise exception 'LOCATION_NOT_FOUND';end if;
   if nullif(btrim(coalesce(p_data->>'code','')),'') is not null and upper(btrim(p_data->>'code'))<>l.code then raise exception 'LOCATION_CODE_IMMUTABLE';end if;
   update public.warehouse_locations set name=nm where id=l.id;
   return jsonb_build_object('id',l.id,'code',l.code,'name',nm,'role',l.role);
  end if;
  w:=nullif(p_data->>'warehouse_id','')::uuid;
  if w is null or not exists(select 1 from public.warehouses where id=w) then raise exception 'WAREHOUSE_NOT_FOUND';end if;
  c:=upper(btrim(coalesce(p_data->>'code','')));
  if c !~ '^[A-Z0-9][A-Z0-9._-]{0,23}$' then raise exception 'LOCATION_CODE_INVALID';end if;
  if c ~ '^[A-Z]{2}[0-9]{2}-[0-9]{2}$' then raise exception 'LOCATION_CODE_RESERVED';end if;
  select * into l from public.warehouse_locations where warehouse_id=w and code=c for update;
  if found then
   -- Un código archivado vuelve con su historial en vez de chocar.
   if l.active or l.shelf_id is not null or l.type='warehouse' or l.role is not null then raise exception 'LOCATION_CODE_TAKEN';end if;
   update public.warehouse_locations set active=true,name=nm,parent_id=private.gama_warehouse_root(w) where id=l.id;
   return jsonb_build_object('id',l.id,'code',c,'name',nm,'role',null,'restored',true);
  end if;
  insert into public.warehouse_locations(warehouse_id,parent_id,code,name,type)
   values(w,private.gama_warehouse_root(w),c,nm,'zone') returning id into v;
  return jsonb_build_object('id',v,'code',c,'name',nm,'role',null);
 elsif p_action='delete' then
  select * into l from public.warehouse_locations where id=nullif(p_data->>'id','')::uuid for update;
  if not found or l.shelf_id is not null or l.type='warehouse' or not l.active then raise exception 'LOCATION_NOT_FOUND';end if;
  if l.role is not null then raise exception 'LOCATION_ROLE_REQUIRED';end if;
  if cardinality(private.gama_shelf_spaces_in_use(array[l.id]))>0 then raise exception 'LOCATION_NOT_EMPTY';end if;
  if exists(select 1 from public.warehouse_locations where parent_id=l.id and active)
   or exists(select 1 from public.warehouse_shelves where parent_id=l.id) then raise exception 'LOCATION_HAS_CHILDREN';end if;
  if exists(select 1 from public.fulfillment_pick_lines pl join public.fulfillment_preparations p on p.id=pl.preparation_id
   where (pl.source_location_id=l.id or pl.stage_location_id=l.id) and p.status in ('queued','picking','picked','packed')) then raise exception 'LOCATION_IN_USE';end if;
  return private.gama_shelf_drop_spaces(array[l.id])||jsonb_build_object('id',l.id,'code',l.code);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_location_action(text,jsonb) from public,anon;
grant execute on function private.gama_location_action(text,jsonb) to authenticated;
create function public.gama_location_action(p_action text,p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.gama_location_action(p_action,p_data)$$;
revoke all on function public.gama_location_action(text,jsonb) from public,anon;
grant execute on function public.gama_location_action(text,jsonb) to authenticated;

-- Los procesos, por papel. Se cambia sólo la línea que creaba la zona; si el
-- texto no está donde se espera, la migración se detiene en vez de adivinar.
do $$
declare f regprocedure;d text;o text;
begin
 f:='private.gama_fulfillment_action(text,jsonb)'::regprocedure;d:=pg_get_functiondef(f);
 o:=E'   insert into public.warehouse_locations(warehouse_id,code,name,type,barcode)\n   values(loc.warehouse_id,p.number,''Preparación ''||p.number,''zone'',p.number) on conflict(warehouse_id,code) do update set name=excluded.name returning id into stage;';
 if position(o in d)=0 then raise exception 'PATCH_NOT_FOUND:gama_fulfillment_action';end if;
 execute replace(d,o,E'   stage:=private.gama_zone(loc.warehouse_id,''departure'');');

 f:='private.gama_returns_processing(text,jsonb,jsonb,date)'::regprocedure;d:=pg_get_functiondef(f);
 o:=E'  insert into public.warehouse_locations(warehouse_id,code,name,type,barcode)\n   values(loc.warehouse_id,''RET-QUARANTINE'',''Devoluciones — cuarentena'',''zone'',''RET-QUARANTINE'')\n   on conflict(warehouse_id,code) do update set name=excluded.name returning id into stage;';
 if position(o in d)=0 then raise exception 'PATCH_NOT_FOUND:gama_returns_processing';end if;
 execute replace(d,o,E'  stage:=private.gama_zone(loc.warehouse_id,''quarantine'');');

 -- Destinos de una devolución revisada: ni la cuarentena, ni la salida, ni la raíz.
 f:='private.gama_returns_action(text,jsonb)'::regprocedure;d:=pg_get_functiondef(f);
 o:='where active and code<>''RET-QUARANTINE'' and code not like ''PR-%''';
 if position(o in d)=0 then raise exception 'PATCH_NOT_FOUND:gama_returns_action';end if;
 execute replace(d,o,'where active and shelf_id is null and type<>''warehouse'' and coalesce(role,'''') not in (''quarantine'',''departure'') or active and shelf_id is not null');
end $$;

-- Cada almacén, con sus tres zonas y sus otras ubicaciones vacías.
do $$
declare w uuid;
begin
 for w in select id from public.warehouses order by code loop perform private.gama_locations_reset(w);end loop;
end $$;
