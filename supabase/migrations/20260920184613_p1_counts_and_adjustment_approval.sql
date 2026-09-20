alter table public.inventory_counts add column blind boolean not null default true,add column cycle_days integer check(cycle_days between 1 and 366),add column next_due date,add column scope_location_id uuid references public.warehouse_locations(id),add column scope_category text,add column request_key uuid unique;
alter table public.inventory_count_lines add column counted_by uuid references auth.users(id),add column counted_at timestamptz,add column recount_quantity numeric check(recount_quantity>=0),add column recounted_by uuid references auth.users(id),add column recounted_at timestamptz;
create function private.erp_count_line_stamp() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.counted_quantity is distinct from old.counted_quantity then
  if new.counted_quantity<0 or new.counted_quantity>999999999 or new.counted_quantity<>round(new.counted_quantity,3) then raise exception 'INVALID_QUANTITY';end if;
  new.counted_by:=auth.uid();new.counted_at:=now();new.recount_quantity:=null;new.recounted_by:=null;new.recounted_at:=null;
 elsif new.recount_quantity is distinct from old.recount_quantity then
  if auth.uid()=old.counted_by then raise exception 'SECOND_COUNTER_REQUIRED';end if;
  if new.recount_quantity<>round(new.recount_quantity,3) or new.recount_quantity>999999999 then raise exception 'INVALID_QUANTITY';end if;
  new.recounted_by:=auth.uid();new.recounted_at:=now();
 else new.counted_by:=old.counted_by;new.counted_at:=old.counted_at;new.recounted_by:=old.recounted_by;new.recounted_at:=old.recounted_at;
 end if;return new;end $$;
revoke all on function private.erp_count_line_stamp() from public,anon,authenticated;
create trigger erp_count_line_stamp before update on public.inventory_count_lines for each row execute function private.erp_count_line_stamp();
create function private.gama_count_create(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.inventory_counts;key uuid:=(p_data->>'request_key')::uuid;begin
 if auth.uid() is null or not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('count:'||key::text,0));
 select * into c from public.inventory_counts where request_key=key;if found then if c.created_by<>auth.uid() then raise exception 'ROLE_NOT_ALLOWED';end if;return to_jsonb(c);end if;
 if nullif(p_data->>'location_id','') is not null and not exists(select 1 from public.warehouse_locations where id=(p_data->>'location_id')::uuid and warehouse_id=(p_data->>'warehouse_id')::uuid and active) then raise exception 'LOCATION_NOT_FOUND';end if;
 insert into public.inventory_counts(warehouse_id,reference,status,created_by,started_at,blind,cycle_days,scope_location_id,scope_category,request_key)
 values((p_data->>'warehouse_id')::uuid,p_data->>'reference','in_progress',auth.uid(),now(),coalesce((p_data->>'blind')::boolean,true),nullif(p_data->>'cycle_days','')::integer,nullif(p_data->>'location_id','')::uuid,nullif(p_data->>'category',''),key) returning * into c;
 insert into public.inventory_count_lines(count_id,product_id,location_id,expected_quantity)
 select c.id,q.product_id,q.location_id,q.quantity from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id join public.products p on p.id=q.product_id where l.warehouse_id=c.warehouse_id and (c.scope_location_id is null or q.location_id=c.scope_location_id) and (c.scope_category is null or p.category=c.scope_category);
 if not found then raise exception 'COUNT_SCOPE_EMPTY';end if;return to_jsonb(c);
end $$;
revoke all on function private.gama_count_create(jsonb) from public,anon;
grant execute on function private.gama_count_create(jsonb) to authenticated;
create function public.gama_count_create(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_count_create(p_data)$$;
revoke all on function public.gama_count_create(jsonb) from public,anon;
grant execute on function public.gama_count_create(jsonb) to authenticated;

create or replace function public.gama_count_validate(p_count_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.inventory_counts;l public.inventory_count_lines;q public.stock_quants;limit_qty numeric;adjustments integer:=0;begin
 if auth.uid() is null or not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into c from public.inventory_counts where id=p_count_id for update;
 if not found then raise exception 'COUNT_NOT_FOUND';end if;
 if c.status='validated' then return jsonb_build_object('count_id',c.id,'adjustments',0,'already_validated',true);end if;
 if c.status not in ('draft','in_progress') then raise exception 'COUNT_CANCELLED';end if;
 if not exists(select 1 from public.inventory_count_lines where count_id=c.id) or exists(select 1 from public.inventory_count_lines where count_id=c.id and counted_quantity is null) then raise exception 'COUNT_INCOMPLETE';end if;
 select stock_adjustment_limit into limit_qty from public.erp_policies where id;
 -- Lock in product order, matching stock command lock ordering.
 perform 1 from public.products where id in(select product_id from public.inventory_count_lines where count_id=c.id) order by id for update;
 for l in select * from public.inventory_count_lines where count_id=c.id order by product_id,location_id for update loop
  q:=private.gama_lock_quant(l.product_id,l.location_id);
  if q.quantity<>l.expected_quantity then raise exception 'COUNT_STOCK_CHANGED:%',l.product_id;end if;
  if limit_qty is not null and abs(l.counted_quantity-l.expected_quantity)>limit_qty then
   if l.recount_quantity is null or l.recounted_by is null or l.recount_quantity<>l.counted_quantity then raise exception 'RECOUNT_REQUIRED:%',l.product_id;end if;
   if coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'COUNT_APPROVAL_REQUIRED';end if;
  end if;
  if l.counted_quantity<>l.expected_quantity then
   perform public.gama_stock_adjust(l.product_id,l.location_id,l.counted_quantity,null,'Inventario físico','Conteo '||c.reference,'inventory_count',c.id);adjustments:=adjustments+1;
  end if;
  update public.inventory_count_lines set validated=true where id=l.id;
 end loop;
 update public.inventory_counts set status='validated',completed_at=now(),next_due=case when cycle_days is not null then current_date+cycle_days end where id=c.id;
 return jsonb_build_object('count_id',c.id,'adjustments',adjustments);
end $$;
-- The stock command checks limits under the same product/quant locks as its write.
do $$declare src text:=pg_get_functiondef('public.gama_stock_adjust(uuid,uuid,numeric,numeric,text,text,text,uuid)'::regprocedure);begin
 src:=replace(src,'v_delta := v_new - v_quant.quantity;',$patch$v_delta := v_new - v_quant.quantity;
  if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'ADJUSTMENT_REASON_REQUIRED';end if;
  if exists(select 1 from public.erp_policies where id and stock_adjustment_limit is not null and abs(v_delta)>stock_adjustment_limit) and coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'ADJUSTMENT_APPROVAL_REQUIRED';end if;$patch$);
 execute src;
end $$;

create table public.stock_adjustment_requests(id uuid primary key default gen_random_uuid(),request_key uuid not null unique,product_id uuid not null references public.products(id),location_id uuid not null references public.warehouse_locations(id),expected_quantity numeric not null,target_quantity numeric not null check(target_quantity>=0),reason text not null check(length(btrim(reason))>=3),status text not null default 'pending' check(status in ('pending','approved','rejected')),requested_by uuid not null default auth.uid() references auth.users(id),requested_at timestamptz not null default now(),reviewed_by uuid references auth.users(id),reviewed_at timestamptz,decision_reason text,movement_id uuid references public.stock_movements(id));
alter table public.stock_adjustment_requests enable row level security;
revoke all on public.stock_adjustment_requests from public,anon,authenticated;grant select on public.stock_adjustment_requests to authenticated;
create policy adjustment_read on public.stock_adjustment_requests for select to authenticated using(private.erp_module_allowed('movement',array['administrador','almacenero']));
create trigger erp_audit_capture after insert or update or delete on public.stock_adjustment_requests for each row execute function private.erp_audit_capture();
create function private.gama_adjustment_request(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.stock_adjustment_requests;q public.stock_quants;m public.stock_movements;begin
 if auth.uid() is null or not private.erp_module_allowed('movement',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='submit' then
  if nullif(p_data->>'request_key','') is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('adjust:'||(p_data->>'request_key'),0));
  select * into a from public.stock_adjustment_requests where request_key=(p_data->>'request_key')::uuid;
  if found then if a.requested_by<>auth.uid() or a.product_id<>(p_data->>'product_id')::uuid or a.location_id<>(p_data->>'location_id')::uuid or a.target_quantity<>(p_data->>'target_quantity')::numeric or a.reason<>p_data->>'reason' then raise exception 'REQUEST_KEY_REUSED';end if;return to_jsonb(a);end if;
  perform 1 from public.products where id=(p_data->>'product_id')::uuid and active for update;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  q:=private.gama_lock_quant((p_data->>'product_id')::uuid,(p_data->>'location_id')::uuid);
  insert into public.stock_adjustment_requests(request_key,product_id,location_id,expected_quantity,target_quantity,reason) values((p_data->>'request_key')::uuid,q.product_id,q.location_id,q.quantity,(p_data->>'target_quantity')::numeric,p_data->>'reason') returning * into a;
 elsif p_action in ('approve','reject') then
  if coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'APPROVAL_ADMIN_REQUIRED';end if;
  select * into a from public.stock_adjustment_requests where id=(p_data->>'id')::uuid for update;if not found or a.status<>'pending' then raise exception 'APPROVAL_NOT_PENDING';end if;
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  if p_action='approve' then
   perform 1 from public.products where id=a.product_id for update;q:=private.gama_lock_quant(a.product_id,a.location_id);
   if q.quantity<>a.expected_quantity then raise exception 'STOCK_CHANGED_RECOUNT';end if;
   m:=public.gama_stock_adjust(a.product_id,a.location_id,a.target_quantity,null,a.reason,p_data->>'reason','adjustment_request',a.id);
  end if;
  update public.stock_adjustment_requests set status=case when p_action='approve' then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now(),decision_reason=p_data->>'reason',movement_id=m.id where id=a.id returning * into a;
 else raise exception 'INVALID_ACTION';end if;return to_jsonb(a);
end $$;
revoke all on function private.gama_adjustment_request(text,jsonb) from public,anon;
grant execute on function private.gama_adjustment_request(text,jsonb) to authenticated;
create function public.gama_adjustment_request(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_adjustment_request(p_action,p_data)$$;
revoke all on function public.gama_adjustment_request(text,jsonb) from public,anon;
grant execute on function public.gama_adjustment_request(text,jsonb) to authenticated;

create function private.gama_register_stock_movement_once(p_request_key uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare receipt private.command_receipts;result jsonb;begin
 if auth.uid() is null or not private.erp_module_allowed('movement',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_request_key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('movement:'||p_request_key::text,0));
 select * into receipt from private.command_receipts where domain='movement' and request_key=p_request_key;
 if found then if receipt.actor_id<>auth.uid() or receipt.payload<>p_data then raise exception 'REQUEST_KEY_REUSED';end if;return receipt.result;end if;
 if length(btrim(coalesce(p_data->>'p_reason','')))<3 then raise exception 'ADJUSTMENT_REASON_REQUIRED';end if;
 if exists(select 1 from public.erp_policies where id and stock_adjustment_limit is not null and abs((p_data->>'p_quantity')::numeric)>stock_adjustment_limit) and coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'ADJUSTMENT_APPROVAL_REQUIRED';end if;
 select to_jsonb(r) into result from public.gama_register_stock_movement((p_data->>'p_product_id')::uuid,p_data->>'p_type',(p_data->>'p_quantity')::numeric,p_data->>'p_reason',p_data->>'p_comment')r;
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('movement',p_request_key,auth.uid(),p_data,result);
 return result;
end $$;
revoke all on function private.gama_register_stock_movement_once(uuid,jsonb) from public,anon;
grant execute on function private.gama_register_stock_movement_once(uuid,jsonb) to authenticated;
create function public.gama_register_stock_movement_once(p_request_key uuid,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_register_stock_movement_once(p_request_key,p_data)$$;
revoke all on function public.gama_register_stock_movement_once(uuid,jsonb) from public,anon;
grant execute on function public.gama_register_stock_movement_once(uuid,jsonb) to authenticated;
-- Protect callers of the legacy command as well as the new idempotent wrapper.
do $$declare src text:=pg_get_functiondef('public.gama_register_stock_movement(uuid,text,numeric,text,text)'::regprocedure);begin
 src:=regexp_replace(src,'begin', $p$begin
 if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'ADJUSTMENT_REASON_REQUIRED';end if;
 if exists(select 1 from public.erp_policies where id and stock_adjustment_limit is not null and abs(p_quantity)>stock_adjustment_limit) and coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'ADJUSTMENT_APPROVAL_REQUIRED';end if;
 $p$,'i');execute src;end $$;
