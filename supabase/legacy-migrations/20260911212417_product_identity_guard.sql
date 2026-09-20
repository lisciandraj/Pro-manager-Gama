-- Existing duplicates are grandfathered, never renamed/deleted or merged.
-- A unique private key claim prevents ALL new collisions, including concurrent writes.
lock table public.products in share row exclusive mode;
create table private.product_identity_claims (
 field text not null check (field in ('name','reference','barcode')),
 identity_key text not null,
 product_ids uuid[] not null,
 primary key (field,identity_key)
);
alter table private.product_identity_claims enable row level security;
revoke all on private.product_identity_claims from public, anon, authenticated;
create function private.product_identity_key(value text) returns text
language sql immutable strict set search_path='' as $$
 select nullif(lower(btrim(regexp_replace(value,'\s+',' ','g'))),'');
$$;
revoke all on function private.product_identity_key(text) from public,anon,authenticated;
insert into private.product_identity_claims(field,identity_key,product_ids)
select v.field,private.product_identity_key(v.value),array_agg(p.id order by p.id)
from public.products p cross join lateral
 (values ('name',p.name),('reference',p.reference),('barcode',p.barcode)) v(field,value)
where private.product_identity_key(v.value) is not null
group by v.field,private.product_identity_key(v.value);
create function private.guard_product_identity() returns trigger
language plpgsql security definer set search_path='' as $$
declare
 f text; old_key text; new_key text; claimed uuid[]; label text;
begin
 -- Only trigger execution is allowed. RLS on products still authorizes the write.
 if auth.uid() is null and current_setting('role',true) in ('anon','authenticated') then
  raise exception 'Se requiere una sesión activa' using errcode='42501';
 end if;
 if TG_OP='UPDATE' and new.id is distinct from old.id then
  raise exception 'No se puede cambiar el identificador del producto';
 end if;
 foreach f in array array['barcode','name','reference'] loop
  old_key:=null;new_key:=null;
  if TG_OP<>'INSERT' then old_key:=private.product_identity_key(to_jsonb(old)->>f);end if;
  if TG_OP<>'DELETE' then new_key:=private.product_identity_key(to_jsonb(new)->>f);end if;
  if old_key is not distinct from new_key then continue;end if;
  if new_key is not null then
   claimed:=null;
   insert into private.product_identity_claims as c(field,identity_key,product_ids)
    values(f,new_key,array[new.id])
    on conflict (field,identity_key) do update set product_ids=c.product_ids
    where new.id=any(c.product_ids)
    returning product_ids into claimed;
   if claimed is null then
    label:=case f when 'name' then 'nombre' when 'barcode' then 'código de barras' else 'referencia' end;
    raise exception 'Ya existe un producto con este %. Revisa también los productos archivados.',label
     using errcode='23505',constraint='products_'||f||'_identity_unique';
   end if;
  end if;
  if old_key is not null then
   update private.product_identity_claims set product_ids=array_remove(product_ids,old.id)
    where field=f and identity_key=old_key;
   delete from private.product_identity_claims where field=f and identity_key=old_key and cardinality(product_ids)=0;
  end if;
 end loop;
 if TG_OP='DELETE' then return old;end if;
 return new;
end;
$$;
revoke all on function private.guard_product_identity() from public,anon,authenticated;
create trigger products_identity_guard
 after insert or update of name,reference,barcode,id or delete on public.products
 for each row execute function private.guard_product_identity();
comment on table private.product_identity_claims is 'Unique normalized product identifiers. Arrays preserve legacy duplicates until individually corrected. No API access; maintained atomically by trigger.';
