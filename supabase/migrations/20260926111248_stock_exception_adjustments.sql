-- Exceptional stock operations live in Warehouses, independently of retired IN/OUT.
alter table public.stock_adjustment_requests
 add column kind text not null default 'inventory_difference'
  check(kind in ('inventory_difference','breakage','loss','expiry','sample','donation','internal_use','opening')),
 add column submission_hash text,
 add column approval_limit numeric,
 add column lot_id uuid references public.product_lots(id),
 add column erp_reference text;
create index stock_adjustments_date on public.stock_adjustment_requests(requested_at desc,id);
create index stock_adjustments_status on public.stock_adjustment_requests(status,requested_at desc);
create index stock_adjustments_product on public.stock_adjustment_requests(product_id);
create index stock_adjustments_location on public.stock_adjustment_requests(location_id);
create index stock_adjustments_lot on public.stock_adjustment_requests(lot_id);
insert into public.erp_reference_formats(kind,module_id,label_es,prefix,default_prefix,source_table)
 values('stock_adjustment','warehouses','Ajuste de stock','AJU','AJU','stock_adjustment_requests');
insert into private.erp_reference_counters(kind) values('stock_adjustment');
insert into private.erp_reference_prefixes(prefix,kind) values('AJU','stock_adjustment');
do $$declare definition text;begin
 select pg_get_constraintdef(oid) into definition from pg_constraint where conrelid='public.gama_document_references'::regclass and conname='gama_document_references_table_name_check';
 if definition is null then raise exception 'REFERENCE_TABLE_CONSTRAINT_MISSING';end if;
 alter table public.gama_document_references drop constraint gama_document_references_table_name_check;
 execute 'alter table public.gama_document_references add constraint gama_document_references_table_name_check '||replace(definition,'CHECK (','CHECK ((table_name = ''stock_adjustment_requests'') OR ');
end $$;
create trigger zz_erp_reference before insert or update on public.stock_adjustment_requests for each row execute function private.erp_stamp_reference();
update public.stock_adjustment_requests set erp_reference=erp_reference;
alter table public.stock_adjustment_requests add constraint stock_adjustment_reference check(erp_reference ~ '^[A-Z]{3}-[0-9]{8}$');
create unique index stock_adjustment_reference on public.stock_adjustment_requests(erp_reference);
drop policy adjustment_read on public.stock_adjustment_requests;
create policy adjustment_read on public.stock_adjustment_requests for select to authenticated
 using(private.erp_module_allowed('warehouses',array['administrador','almacenero']));

create table public.stock_adjustment_files(
 id uuid primary key default gen_random_uuid(),adjustment_id uuid not null unique references public.stock_adjustment_requests(id) on delete cascade,
 filename text not null check(length(filename) between 1 and 200),
 data_url text not null check(length(data_url)<=1500000 and data_url ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/]+=*$'),
 created_by uuid not null default auth.uid() references auth.users(id),created_at timestamptz not null default now()
);
alter table public.stock_adjustment_files enable row level security;
revoke all on public.stock_adjustment_files from public,anon,authenticated;
grant select on public.stock_adjustment_files to authenticated;
create index stock_adjustment_file_actor on public.stock_adjustment_files(created_by);
create policy adjustment_file_read on public.stock_adjustment_files for select to authenticated using(
 private.erp_module_allowed('warehouses',array['administrador','almacenero']) and private.document_source_visible('stock_adjustment_files',id));
-- Index evidence in Documents while retaining the owning module's permissions.
alter table public.business_documents drop constraint business_document_source_known;
alter table public.business_documents add constraint business_document_source_known check(source_table is null or source_table in
 ('hr_documents','fleet_documents','pm_files','external_invoice_files','expense_receipts','return_files','return_credits','tms_proofs','stock_adjustment_files'));
do $$declare s text;anchor text;begin
 s:=pg_get_functiondef('private.document_index(text,jsonb,boolean)'::regprocedure);anchor:='case t';
 if strpos(s,anchor)=0 then raise exception 'DOCUMENT_INDEX_ANCHOR';end if;
 s:=replace(s,anchor,anchor||$p$
 when 'stock_adjustment_files' then cat:='Ajustes de stock';mod:='warehouses';parent:=(j->>'adjustment_id')::uuid;present:=nullif(j->>'data_url','') is not null;
 $p$);execute s;
 s:=pg_get_functiondef('private.document_original_access(public.business_documents)'::regprocedure);anchor:='case d.source_table';
 if strpos(s,anchor)=0 then raise exception 'DOCUMENT_ACCESS_ANCHOR';end if;
 s:=replace(s,anchor,anchor||$p$
 when 'stock_adjustment_files' then return private.erp_module_allowed('warehouses',array['administrador','almacenero']);
 $p$);execute s;
 s:=pg_get_functiondef('private.document_download(uuid)'::regprocedure);anchor:='case d.source_table';
 if strpos(s,anchor)=0 then raise exception 'DOCUMENT_DOWNLOAD_ANCHOR';end if;
 s:=replace(s,anchor,anchor||$p$
 when 'stock_adjustment_files' then select jsonb_build_object('data_url',data_url,'filename',filename) into j from public.stock_adjustment_files where id=d.source_id;
 $p$);execute s;
end $$;
create trigger document_index after insert or update or delete on public.stock_adjustment_files for each row execute function private.document_index_trigger();
create trigger document_source_guard before insert or update or delete on public.stock_adjustment_files for each row execute function private.document_source_guard();

-- Use the selected lot for an exceptional operation; retain the existing FEFO
-- rules for deliveries and transfers. The selection comes from the locked request.
do $$declare s text;anchor text;begin
 s:=pg_get_functiondef('private.erp_lot_movement()'::regprocedure);
 anchor:='if new.source_location_id is null then';
 if strpos(s,anchor)=0 then raise exception 'LOT_ADJUSTMENT_ANCHOR';end if;
 s:=replace(s,anchor,$p$
 if new.reference_type='adjustment_request' then
  select jsonb_build_array(jsonb_build_object('lot_id',a.lot_id,'quantity',abs(new.quantity))) into plan
   from public.stock_adjustment_requests a where a.id=new.reference_id and a.product_id=new.product_id
    and a.location_id=coalesce(new.source_location_id,new.destination_location_id) and a.lot_id is not null;
  if plan is null then raise exception 'ADJUSTMENT_LOT_REQUIRED';end if;
  x:=plan->0;
  if new.source_location_id is not null then
   update public.stock_lot_balances set quantity=quantity-abs(new.quantity)
    where lot_id=(x->>'lot_id')::uuid and location_id=new.source_location_id and quantity>=abs(new.quantity);
   if not found then raise exception 'LOT_QUANTITY_EXCEEDED';end if;
  else
   insert into public.stock_lot_balances(lot_id,location_id,quantity) values((x->>'lot_id')::uuid,new.destination_location_id,abs(new.quantity))
    on conflict(lot_id,location_id) do update set quantity=public.stock_lot_balances.quantity+excluded.quantity;
  end if;
  insert into public.stock_lot_movements(movement_id,lot_id,source_location_id,destination_location_id,quantity,created_by)
   values(new.id,(x->>'lot_id')::uuid,new.source_location_id,new.destination_location_id,abs(new.quantity),auth.uid());
  return new;
 end if;
 $p$||anchor);execute s;
end $$;

create or replace function private.gama_adjustment_request(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 a public.stock_adjustment_requests;q public.stock_quants;m public.stock_movements;p public.products;
 k text:=coalesce(nullif(p_data->>'kind',''),'inventory_difference');key uuid;target numeric;delta numeric;lim numeric;
 v_reason text:=btrim(coalesce(p_data->>'reason',''));lot public.product_lots;rows jsonb;off integer;label text;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='list' then
  off:=greatest(0,coalesce((p_data->>'offset')::integer,0));
  select stock_adjustment_limit into lim from public.erp_policies where id;
  select coalesce(jsonb_agg(to_jsonb(r)),'[]') into rows from (
   select req.*,prod.name product_name,prod.reference product_reference,l.code location_code,l.name location_name,
    u.full_name requested_name,v.full_name reviewed_name,lotrow.code lot_code,
    exists(select 1 from public.stock_adjustment_files f where f.adjustment_id=req.id and private.document_source_visible('stock_adjustment_files',f.id)) has_photo
   from public.stock_adjustment_requests req join public.products prod on prod.id=req.product_id
   join public.warehouse_locations l on l.id=req.location_id left join public.profiles u on u.id=req.requested_by
   left join public.profiles v on v.id=req.reviewed_by left join public.product_lots lotrow on lotrow.id=req.lot_id
   where (nullif(p_data->>'status','') is null or req.status=p_data->>'status')
   order by req.requested_at desc,req.id desc limit 26 offset off
  )r;
  return jsonb_build_object('items',(select coalesce(jsonb_agg(value-'submission_hash'),'[]') from jsonb_array_elements(rows) with ordinality x(value,n) where n<=25),
   'has_more',jsonb_array_length(rows)>25,'approval_limit',lim);
 elsif p_action='photo' then
  select jsonb_build_object('data_url',f.data_url,'filename',f.filename) into rows from public.stock_adjustment_files f
   where f.adjustment_id=(p_data->>'id')::uuid and private.document_source_visible('stock_adjustment_files',f.id);
  if rows is null then raise exception 'DOCUMENT_UNAVAILABLE';end if;return rows;
 elsif p_action='submit' then
  key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('adjust:'||key::text,0));
  select * into a from public.stock_adjustment_requests where request_key=key;
  if found then
   if a.requested_by is distinct from auth.uid() or (a.submission_hash is not null and a.submission_hash<>md5(p_data::text))
    or (a.submission_hash is null and (a.product_id is distinct from (p_data->>'product_id')::uuid or a.location_id is distinct from (p_data->>'location_id')::uuid or a.target_quantity is distinct from (p_data->>'target_quantity')::numeric or a.reason is distinct from v_reason)) then raise exception 'REQUEST_KEY_REUSED';end if;
   return to_jsonb(a)-'submission_hash';
  end if;
  if k not in ('inventory_difference','breakage','loss','expiry','sample','donation','internal_use','opening') then raise exception 'INVALID_ADJUSTMENT_KIND';end if;
  if length(v_reason)<3 or length(v_reason)>2000 then raise exception 'ADJUSTMENT_REASON_REQUIRED';end if;
  if k='opening' and private.current_user_role()<>'administrador' then raise exception 'OPENING_ADMIN_REQUIRED';end if;
  select * into p from public.products where id=(p_data->>'product_id')::uuid and active for update;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  if p.product_kind<>'goods' then raise exception 'STOCK_GOODS_ONLY';end if;
  perform 1 from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id
   where l.id=(p_data->>'location_id')::uuid and l.active and w.active;
  if not found then raise exception 'LOCATION_NOT_FOUND';end if;
  q:=private.gama_lock_quant(p.id,(p_data->>'location_id')::uuid);
  target:=(p_data->>'target_quantity')::numeric;
  if target is null or target::text in ('NaN','Infinity','-Infinity') or target<0 or target>999999999 or target<>round(target,3) then raise exception 'INVALID_QUANTITY';end if;
  if p_data ? 'kind' and (p_data->>'expected_quantity')::numeric is distinct from q.quantity then raise exception 'STOCK_CHANGED_RECOUNT';end if;
  delta:=target-q.quantity;
  if delta=0 then raise exception 'NO_CHANGE';end if;
  if k not in ('inventory_difference','opening') and delta>=0 then raise exception 'EXCEPTION_OUT_ONLY';end if;
  if target<q.reserved_quantity then raise exception 'RESERVED_EXCEEDS_QUANTITY';end if;
  if k='opening' and (q.quantity<>0 or exists(select 1 from public.stock_movements where product_id=p.id and (source_location_id=q.location_id or destination_location_id=q.location_id))) then raise exception 'OPENING_ALREADY_USED';end if;
  if p.lot_tracking then
   if nullif(p_data->>'lot_id','') is not null then select * into lot from public.product_lots where id=(p_data->>'lot_id')::uuid and product_id=p.id;
   elsif delta>0 and length(btrim(coalesce(p_data->>'lot_code',''))) between 1 and 100 then
    select * into lot from public.product_lots where product_id=p.id and code=btrim(p_data->>'lot_code');
    if lot.id is null then insert into public.product_lots(product_id,code,expires_on,created_by)
     values(p.id,btrim(p_data->>'lot_code'),nullif(p_data->>'expires_on','')::date,auth.uid()) returning * into lot;end if;
   end if;
   if lot.id is null then raise exception 'ADJUSTMENT_LOT_REQUIRED';end if;
   if delta<0 and coalesce((select quantity from public.stock_lot_balances where lot_id=lot.id and location_id=q.location_id),0)<abs(delta) then raise exception 'LOT_QUANTITY_EXCEEDED';end if;
  end if;
  select stock_adjustment_limit into lim from public.erp_policies where id;
  insert into public.stock_adjustment_requests(request_key,product_id,location_id,expected_quantity,target_quantity,reason,kind,submission_hash,approval_limit,lot_id)
   values(key,p.id,q.location_id,q.quantity,target,v_reason,k,md5(p_data::text),lim,lot.id) returning * into a;
  if p_data->'photo' is not null and p_data->'photo'<>'null'::jsonb then
   insert into public.stock_adjustment_files(adjustment_id,filename,data_url)
    values(a.id,p_data->'photo'->>'filename',p_data->'photo'->>'data_url');
  end if;
  -- Older clients explicitly requested approval; preserve their pending behavior.
  if p_data ? 'kind' and (lim is null or abs(delta)<=lim) then
   label:=case k when 'breakage' then 'Rotura' when 'loss' then 'Pérdida' when 'expiry' then 'Caducidad' when 'sample' then 'Muestra' when 'donation' then 'Donación' when 'internal_use' then 'Consumo interno' when 'opening' then 'Stock inicial' else 'Diferencia de inventario' end;
   m:=public.gama_stock_adjust(a.product_id,a.location_id,a.target_quantity,null,label||' · '||a.reason,a.erp_reference,'adjustment_request',a.id);
   update public.stock_adjustment_requests set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),decision_reason='Aplicado según el umbral configurado',movement_id=m.id where id=a.id returning * into a;
  end if;
 elsif p_action in ('approve','reject','cancel') then
  select * into a from public.stock_adjustment_requests where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'APPROVAL_NOT_PENDING';end if;
  if p_action='cancel' then
   if a.requested_by<>auth.uid() and private.current_user_role()<>'administrador' then raise exception 'ROLE_NOT_ALLOWED';end if;
  elsif private.current_user_role()<>'administrador' then raise exception 'APPROVAL_ADMIN_REQUIRED';end if;
  if length(v_reason)<3 or length(v_reason)>2000 then raise exception 'REASON_REQUIRED';end if;
  if a.status<>'pending' then
   if a.status=(case when p_action='approve' then 'approved' else 'rejected' end) and a.reviewed_by=auth.uid() and a.decision_reason=v_reason then return to_jsonb(a)-'submission_hash';end if;
   raise exception 'APPROVAL_NOT_PENDING';
  end if;
  if p_action='approve' then
   select * into p from public.products where id=a.product_id and active for update;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
   perform 1 from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id where l.id=a.location_id and l.active and w.active;
   if not found then raise exception 'LOCATION_NOT_FOUND';end if;
   q:=private.gama_lock_quant(a.product_id,a.location_id);
   if q.quantity<>a.expected_quantity then raise exception 'STOCK_CHANGED_RECOUNT';end if;
   m:=public.gama_stock_adjust(a.product_id,a.location_id,a.target_quantity,null,a.kind||' · '||a.reason,a.erp_reference||' · '||v_reason,'adjustment_request',a.id);
  end if;
  update public.stock_adjustment_requests set status=case when p_action='approve' then 'approved' else 'rejected' end,
   reviewed_by=auth.uid(),reviewed_at=now(),decision_reason=v_reason,movement_id=m.id where id=a.id returning * into a;
 else raise exception 'INVALID_ACTION';end if;
 return to_jsonb(a)-'submission_hash';
end $$;
revoke all on function private.gama_adjustment_request(text,jsonb) from public,anon;
grant execute on function private.gama_adjustment_request(text,jsonb) to authenticated;
