-- Product Excel imports may enrich an existing product instead of failing on
-- name/barcode/reference identity. Only non-empty incoming fields are applied.
-- Existing populated values are preserved, except price fields: an explicitly
-- supplied price is treated as a deliberate update.
create or replace function private.erp_import_row(p_kind text,p_row jsonb,p_dry boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare
 result uuid; fields text[]; tbl text; data jsonb:=p_row; columns text; values_sql text;
 cid uuid; pid uuid; n integer; existing public.products; patch jsonb:='{}'::jsonb; f text;
begin
 if p_row ? '_errors' then raise exception '%',p_row->>'_errors';end if;
 if p_kind='customerPrices' then
  select count(*),(array_agg(id))[1] into n,cid from public.customers where active and ((nullif(p_row->>'customer_tax_id','') is not null and lower(identification)=lower(p_row->>'customer_tax_id')) or (nullif(p_row->>'customer_tax_id','') is null and lower(name)=lower(p_row->>'customer')));
  if n<>1 then raise exception 'CUSTOMER_UNKNOWN_OR_AMBIGUOUS';end if;
  select count(*),(array_agg(id))[1] into n,pid from public.products where active and ((nullif(p_row->>'reference','') is not null and lower(reference)=lower(p_row->>'reference')) or (nullif(p_row->>'reference','') is null and lower(barcode)=lower(p_row->>'barcode')));
  if n<>1 then raise exception 'PRODUCT_UNKNOWN_OR_AMBIGUOUS';end if;
  if p_row->>'unit_price' is null or (p_row->>'unit_price')::numeric<0 then raise exception 'PRICE_REQUIRED';end if;
  begin
   insert into public.customer_special_prices(customer_id,product_id,unit_price,contract_ref) values(cid,pid,(p_row->>'unit_price')::numeric,p_row->>'contract_ref') on conflict(customer_id,product_id) do update set unit_price=excluded.unit_price,contract_ref=excluded.contract_ref;
   if p_dry then raise exception using errcode='P0002',message='IMPORT_DRY_ROLLBACK';end if;
  exception when no_data_found then if sqlerrm<>'IMPORT_DRY_ROLLBACK' then raise;end if;end;
  return pid;
 end if;
 if length(btrim(coalesce(p_row->>'name','')))=0 then raise exception 'NAME_REQUIRED';end if;

 if p_kind='products' then
  fields:=array['name','description','reference','barcode','category','family','lines','brand','presentation','location','stock','min_stock','max_stock','qty_per_carton','weight_g','volume_cm3','sale_price','sale_price_b','purchase_price','tax_rate'];

  -- Resolve by barcode first, then reference, then normalized name. More than one
  -- different match is rejected rather than merging two products accidentally.
  select count(distinct id),(array_agg(distinct id))[1] into n,pid
  from public.products
  where (
    (nullif(btrim(p_row->>'barcode'),'') is not null and lower(btrim(barcode))=lower(btrim(p_row->>'barcode')))
    or (nullif(btrim(p_row->>'reference'),'') is not null and lower(btrim(reference))=lower(btrim(p_row->>'reference')))
    or lower(btrim(name))=lower(btrim(p_row->>'name'))
  );
  if n>1 then raise exception 'PRODUCT_IDENTITY_AMBIGUOUS';end if;

  if n=1 then
   select * into existing from public.products where id=pid;
   -- Re-importing an archived product restores that same record instead of trying to create a duplicate.
   if not existing.active and not p_dry then update public.products set active=true where id=pid; existing.active:=true; end if;
   foreach f in array fields loop
    if not (data ? f) or nullif(btrim(data->>f),'') is null then continue;end if;
    -- Identity fields never overwrite a different populated identity.
    if f in ('name','reference','barcode') then
      if nullif(btrim(to_jsonb(existing)->>f),'') is null then patch:=patch||jsonb_build_object(f,data->f);end if;
    -- Prices are intentional refresh fields when present in the import.
    elsif f in ('sale_price','sale_price_b','purchase_price','tax_rate') then
      patch:=patch||jsonb_build_object(f,data->f);
    -- Other fields only fill blanks / nulls / zero defaults.
    elsif nullif(btrim(to_jsonb(existing)->>f),'') is null
       or (f in ('stock','min_stock','max_stock','qty_per_carton','weight_g','volume_cm3') and coalesce((to_jsonb(existing)->>f)::numeric,0)=0)
    then patch:=patch||jsonb_build_object(f,data->f);
    end if;
   end loop;
   if p_dry then return pid;end if;
   if patch<>'{}'::jsonb then
    update public.products p set
      name=coalesce(patch->>'name',p.name),
      description=coalesce(patch->>'description',p.description),
      reference=coalesce(patch->>'reference',p.reference),
      barcode=coalesce(patch->>'barcode',p.barcode),
      category=coalesce(patch->>'category',p.category),
      family=coalesce(patch->>'family',p.family),
      lines=coalesce(patch->>'lines',p.lines),
      brand=coalesce(patch->>'brand',p.brand),
      presentation=coalesce(patch->>'presentation',p.presentation),
      location=coalesce(patch->>'location',p.location),
      stock=case when patch ? 'stock' then (patch->>'stock')::numeric else p.stock end,
      min_stock=case when patch ? 'min_stock' then (patch->>'min_stock')::numeric else p.min_stock end,
      max_stock=case when patch ? 'max_stock' then (patch->>'max_stock')::numeric else p.max_stock end,
      qty_per_carton=case when patch ? 'qty_per_carton' then (patch->>'qty_per_carton')::numeric else p.qty_per_carton end,
      weight_g=case when patch ? 'weight_g' then (patch->>'weight_g')::numeric else p.weight_g end,
      volume_cm3=case when patch ? 'volume_cm3' then (patch->>'volume_cm3')::numeric else p.volume_cm3 end,
      sale_price=case when patch ? 'sale_price' then (patch->>'sale_price')::numeric else p.sale_price end,
      sale_price_b=case when patch ? 'sale_price_b' then (patch->>'sale_price_b')::numeric else p.sale_price_b end,
      purchase_price=case when patch ? 'purchase_price' then (patch->>'purchase_price')::numeric else p.purchase_price end,
      tax_rate=case when patch ? 'tax_rate' then (patch->>'tax_rate')::numeric else p.tax_rate end
    where p.id=pid;
   end if;
   return pid;
  end if;
  tbl:='products';
 elsif p_kind='clients' then tbl:='customers';fields:=array['name','identification','category','email','phone','address','city','province','notes'];data:=(data-'tax_id')||jsonb_build_object('identification',data->>'tax_id','category',upper(coalesce(nullif(data->>'category',''),'A')));if data->>'category' not in ('A','B','C') then raise exception 'INVALID_CUSTOMER_CATEGORY';end if;
 elsif p_kind='suppliers' then tbl:='suppliers';fields:=array['name','tax_id','email','phone','address','city','contact_name','notes'];
 else raise exception 'INVALID_IMPORT_KIND';end if;

 if p_kind in ('clients','suppliers') then
  execute format('select count(*) from public.%I where lower(btrim(name))=lower(btrim($1)) and lower(btrim(coalesce(address,'''')))=lower(btrim(coalesce($2,'''')))',tbl) into n using data->>'name',data->>'address';
  if n>0 then raise exception 'DUPLICATE_CONTACT';end if;
 end if;
 select string_agg(format('%I',key),',' order by key),string_agg(format('r.%I',key),',' order by key) into columns,values_sql from jsonb_object_keys(data) key where key=any(fields);
 begin
  execute format('insert into public.%I(%s) select %s from jsonb_populate_record(null::public.%I,$1) r returning id',tbl,columns,values_sql,tbl) into result using data;
  if p_dry then raise exception using errcode='P0002',message='IMPORT_DRY_ROLLBACK';end if;
 exception when no_data_found then if sqlerrm<>'IMPORT_DRY_ROLLBACK' then raise;end if;end;
 return result;
end $$;
revoke all on function private.erp_import_row(text,jsonb,boolean) from public,anon,authenticated;
