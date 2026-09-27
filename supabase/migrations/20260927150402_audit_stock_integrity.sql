-- Audit: catalogue writes must never create unlocated stock.
create table public.stock_integrity_cases (
 id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id),
 observed_at timestamptz not null default now(), catalogue_quantity numeric not null, located_quantity numeric not null,
 resolved_at timestamptz, resolved_by uuid references auth.users(id), resolution text,
 check ((resolved_at is null and resolved_by is null) or (resolved_at is not null and resolved_by is not null and length(btrim(resolution))>=10))
);
create index stock_integrity_product on public.stock_integrity_cases(product_id);
create index stock_integrity_resolver on public.stock_integrity_cases(resolved_by);
alter table public.stock_integrity_cases enable row level security;
revoke all on public.stock_integrity_cases from public,anon,authenticated;
grant select on public.stock_integrity_cases to authenticated;
create policy stock_integrity_read on public.stock_integrity_cases for select to authenticated using(private.erp_module_allowed('warehouses',array['administrador']));
insert into public.stock_integrity_cases(product_id,catalogue_quantity,located_quantity)
 select p.id,p.stock,coalesce(q.quantity,0) from public.products p left join
 (select product_id,sum(quantity) quantity from public.stock_quants group by product_id) q on q.product_id=p.id
 where p.stock is distinct from coalesce(q.quantity,0);

create function private.erp_product_stock_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and new.stock is not distinct from old.stock then return new;end if;
 if new.stock is distinct from coalesce((select sum(quantity) from public.stock_quants where product_id=new.id),0) then
  raise exception 'STOCK_REQUIRES_MOVEMENT' using hint='Use a receipt or a located, justified stock adjustment.';
 end if;return new;
end $$;
create trigger product_stock_from_quants before insert or update of stock on public.products for each row execute function private.erp_product_stock_guard();
create function private.erp_quant_sync() returns trigger language plpgsql security definer set search_path='' as $$
declare pid uuid:=case when tg_op='DELETE' then old.product_id else new.product_id end;
begin
 if tg_op='UPDATE' and (new.product_id<>old.product_id or new.location_id<>old.location_id) then raise exception 'QUANT_IDENTITY_IMMUTABLE';end if;
 -- The product lock serializes all located quantities, including independent locations.
 perform 1 from public.products where id=pid for update;
 update public.products set stock=coalesce((select sum(quantity) from public.stock_quants where product_id=pid),0),updated_at=now() where id=pid;
 return null;
end $$;
create trigger zz_quant_sync after insert or update of quantity,product_id,location_id or delete on public.stock_quants for each row execute function private.erp_quant_sync();
revoke all on function private.erp_product_stock_guard(),private.erp_quant_sync() from public,anon,authenticated;

-- Keep catalogue enrichment, but remove its ability to update stock.
alter function private.erp_import_row(text,jsonb,boolean) rename to erp_import_catalogue_row;
revoke all on function private.erp_import_catalogue_row(text,jsonb,boolean) from public,anon,authenticated;
-- Draft catalogue imports can be completed before the optional activation gate.
-- Existing active products are never archived by a catalogue enrichment.
do $$declare s text;begin
 s:=pg_get_functiondef('private.erp_import_catalogue_row(text,jsonb,boolean)'::regprocedure);
 s:=replace(s,'fields:=array[''name'',''description''','fields:=array[''active'',''name'',''description''');
 s:=replace(s,'if not existing.active and not p_dry then','if not existing.active and not p_dry and not coalesce((p_row->>''_catalogue_draft'')::boolean,false) then');execute s;
end $$;
create function private.erp_import_row(p_kind text,p_row jsonb,p_dry boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare pid uuid;qty numeric;result jsonb;
begin
 if p_kind<>'products' then return private.erp_import_catalogue_row(p_kind,p_row,p_dry);end if;
 qty:=coalesce(nullif(p_row->>'stock','')::numeric,0);
 if qty::text in ('NaN','Infinity','-Infinity') or qty<0 or qty<>round(qty,3) then raise exception 'INVALID_QUANTITY';end if;
 if coalesce((p_row->>'_catalogue_draft')::boolean,false) then
  if qty>0 then raise exception 'DRAFT_CANNOT_OPEN_STOCK';end if;
  p_row:=p_row||jsonb_build_object('active',false);
 end if;
 if qty>0 and (nullif(p_row->>'opening_location_id','') is null or length(btrim(coalesce(p_row->>'opening_reason','')))<10) then raise exception 'OPENING_LOCATION_AND_REASON_REQUIRED';end if;
 begin
  pid:=private.erp_import_catalogue_row(p_kind,p_row-'stock',false);
  if qty>0 then
   -- Opening is explicit, located, one-time and uses the same approval/lot controls as the stock screen.
   result:=private.gama_adjustment_request('submit',jsonb_build_object('request_key',gen_random_uuid(),'kind','opening','product_id',pid,
    'location_id',p_row->>'opening_location_id','expected_quantity',0,'target_quantity',qty,'reason',p_row->>'opening_reason',
    'lot_code',p_row->>'lot_code','expires_on',p_row->>'expires_on'));
  end if;
  if p_dry then raise exception using errcode='P0002',message='IMPORT_DRY_ROLLBACK';end if;
 exception when no_data_found then if sqlerrm<>'IMPORT_DRY_ROLLBACK' then raise;end if;end;
 return pid;
end $$;
revoke all on function private.erp_import_row(text,jsonb,boolean) from public,anon,authenticated;

alter table public.erp_policies
 add column stock_adjustment_value_limit numeric check(stock_adjustment_value_limit>=0 and stock_adjustment_value_limit::text not in ('NaN','Infinity','-Infinity')),
 add column stock_adjustment_approval_kinds text[] not null default '{}',
 add column allow_self_approval_exception boolean not null default false,
 add column picking_scan_mode text not null default 'confirm' check(picking_scan_mode in ('unit','pack','confirm')),
 add column picking_location_required boolean not null default false,
 add column product_readiness_required boolean not null default false;
alter table public.products
 add column replenishment_excluded boolean not null default false,
 add column replenishment_exclusion_reason text,
 add constraint replenishment_exclusion_explained check(not replenishment_excluded or length(btrim(coalesce(replenishment_exclusion_reason,'')))>=3);
alter table public.stock_adjustment_requests add column approval_value numeric,add column approval_value_limit numeric;

create function private.erp_independent_approval(requester uuid,data jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 if requester=auth.uid() and not (coalesce((select allow_self_approval_exception from public.erp_policies where id),false)
  and coalesce((data->>'self_approval_exception')::boolean,false) and length(btrim(coalesce(data->>'reason','')))>=20) then
 raise exception 'INDEPENDENT_APPROVER_REQUIRED';end if;
end $$;
revoke all on function private.erp_independent_approval(uuid,jsonb) from public,anon,authenticated;
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_approval_action(text,jsonb)'::regprocedure);
 s:=replace(s,'if a.fingerprint<>','perform private.erp_independent_approval(a.requested_by,p_data); if a.fingerprint<>');execute s;
 s:=pg_get_functiondef('private.gama_adjustment_request(text,jsonb)'::regprocedure);
 s:=replace(s,'if p_data ? ''kind'' and (lim is null or abs(delta)<=lim) then',
 $p$update public.stock_adjustment_requests set approval_value=abs(delta)*coalesce(p.purchase_price,0),approval_value_limit=(select stock_adjustment_value_limit from public.erp_policies where id) where id=a.id returning * into a;
  if p_data ? 'kind' and (lim is null or abs(delta)<=lim)
   and (a.approval_value_limit is null or (coalesce(p.purchase_price,0)>0 and a.approval_value<=a.approval_value_limit))
   and not (k=any((select stock_adjustment_approval_kinds from public.erp_policies where id)::text[])) then$p$);
 s:=replace(s,'if p_action=''approve'' then','if p_action=''approve'' then perform private.erp_independent_approval(a.requested_by,p_data);');execute s;
end $$;

create function private.erp_product_readiness(pid uuid) returns text[] language sql stable security definer set search_path='' as $$
 select array_remove(array[
 case when nullif(btrim(p.reference),'') is null then 'reference' end,
 case when nullif(btrim(p.base_unit),'') is null then 'unit' end,
 case when coalesce(p.sale_price,0)<=0 then 'sale_price' end,
 case when p.product_kind='goods' and coalesce(p.purchase_price,0)<=0 then 'purchase_price' end,
 case when p.product_kind='goods' and not p.replenishment_excluded and p.supplier_id is null
  and not exists(select 1 from public.supplier_product_offers s where s.product_id=p.id and s.active)
  and not exists(select 1 from public.commercial_matrix s where s.product_id=p.id and s.active and s.supplier_id is not null) then 'supplier' end,
 case when p.product_kind='goods' and not p.replenishment_excluded and not(p.min_stock>0 and p.max_stock>=p.min_stock)
  and not exists(select 1 from public.reorder_rules r where r.product_id=p.id and r.active) then 'replenishment' end
 ],null) from public.products p where p.id=pid;
$$;
create function private.erp_product_activation() returns trigger language plpgsql security definer set search_path='' as $$
declare missing text[];
begin
 if new.active and (tg_op='INSERT' or not old.active) and coalesce((select product_readiness_required from public.erp_policies where id),false) then
 missing:=private.erp_product_readiness(new.id);if cardinality(missing)>0 then raise exception 'PRODUCT_NOT_READY: %',array_to_string(missing,', ');end if;
 end if;return null;
end $$;
create trigger product_activation_check after insert or update of active on public.products for each row execute function private.erp_product_activation();
create function private.gama_integrity(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;c public.stock_integrity_cases;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('products',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='resolve' then
  select * into c from public.stock_integrity_cases where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'CASE_NOT_FOUND';end if;
  if length(btrim(coalesce(p_data->>'reason','')))<10 then raise exception 'REASON_REQUIRED';end if;
  perform 1 from public.products where id=c.product_id for update;
  if (select stock from public.products where id=c.product_id) is distinct from coalesce((select sum(quantity) from public.stock_quants where product_id=c.product_id),0) then raise exception 'STOCK_STILL_INCONSISTENT';end if;
  update public.stock_integrity_cases set resolved_at=now(),resolved_by=auth.uid(),resolution=p_data->>'reason' where id=c.id and resolved_at is null;
  return jsonb_build_object('resolved',true);
 elsif p_action='products' then
  with items as (
   select p.id,p.name,p.reference,p.base_unit,p.active,p.replenishment_excluded,p.replenishment_exclusion_reason,p.lot_tracking,
    p.stock catalogue_quantity,coalesce(q.quantity,0) located_quantity,private.erp_product_readiness(p.id) missing,
    (select jsonb_agg(ic) from public.stock_integrity_cases ic where ic.product_id=p.id and ic.resolved_at is null) cases
   from public.products p left join (select product_id,sum(quantity) quantity from public.stock_quants group by product_id) q on q.product_id=p.id
   where p.active and (nullif(p_data->>'search','') is null or concat_ws(' ',p.name,p.reference,p.barcode) ilike '%'||(p_data->>'search')||'%')
  ), filtered as(select * from items where not coalesce((p_data->>'issues_only')::boolean,true) or cardinality(missing)>0 or cases is not null or catalogue_quantity<>located_quantity)
  select jsonb_build_object('total',(select count(*) from filtered),'items',coalesce((select jsonb_agg(r) from
   (select * from filtered order by cases is not null desc,name,id limit 25 offset greatest(0,coalesce((p_data->>'offset')::integer,0)))r),'[]')) into result;
  return result;
 end if;raise exception 'INVALID_ACTION';
end $$;
create function public.gama_integrity(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_integrity(p_action,p_data)$$;
revoke all on function private.erp_product_readiness(uuid),private.erp_product_activation() from public,anon,authenticated;
revoke all on function private.gama_integrity(text,jsonb),public.gama_integrity(text,jsonb) from public,anon;
grant execute on function private.gama_integrity(text,jsonb),public.gama_integrity(text,jsonb) to authenticated;

-- A product identity scan is no longer an implicit whole-line quantity confirmation.
do $$declare s text;anchor text;begin
 s:=pg_get_functiondef('private.gama_fulfillment_action(text,jsonb)'::regprocedure);
 s:=replace(s,'''preparations'',coalesce', '''scan_policy'',(select jsonb_build_object(''mode'',picking_scan_mode,''location_required'',picking_location_required) from public.erp_policies where id),''preparations'',coalesce');
 anchor:='if qty is null or pl.picked+qty>pl.planned then';
 if strpos(s,anchor)=0 then raise exception 'PICK_CONTROL_ANCHOR_MISSING';end if;
 s:=replace(s,'and btrim(p_data->>''product_code'')<>btrim(coalesce(pr.barcode,''''))','and btrim(p_data->>''product_code'')<>btrim(coalesce(pr.barcode,'''')) and btrim(p_data->>''product_code'')<>btrim(coalesce(pr.reference,''''))');
 s:=replace(s,anchor,$p$
  if coalesce((select picking_location_required from public.erp_policies where id),false) and btrim(coalesce(p_data->>'scanned_location',''))<>loc.code then raise exception 'LOCATION_SCAN_REQUIRED';end if;
  if p_data->>'scan_mode'='confirm' then
   if not coalesce((p_data->>'quantity_confirmed')::boolean,false) then raise exception 'QUANTITY_CONFIRMATION_REQUIRED';end if;
  elsif p_data->>'scan_mode'='unit' then
   if nullif(btrim(p_data->>'product_code'),'') is null or qty<>1
    or exists(select 1 from public.product_units where product_id=pr.id and active and barcode=p_data->>'product_code' and factor<>1) then raise exception 'UNIT_SCAN_QUANTITY_REQUIRED';end if;
  elsif p_data->>'scan_mode'='pack' then
   if not exists(select 1 from public.product_units where product_id=pr.id and active and barcode=p_data->>'product_code' and factor=qty) then raise exception 'PACK_SCAN_QUANTITY_REQUIRED';end if;
  else raise exception 'SCAN_MODE_REQUIRED';end if;
 $p$||anchor);
 execute s;
end $$;
