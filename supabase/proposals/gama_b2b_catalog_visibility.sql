-- Proposed GAMA fix. Not an applied migration: validate in an isolated database,
-- then generate a timestamped migration using the Supabase CLI before deployment.
-- Existing RPC OIDs, ACLs, company resolution and history/document reads are preserved.
begin;
create function private.gama_b2b_product_visible(p_customer uuid,p_product uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.products p
  join private.website_products w on w.product_id=p.id and w.public_visible
  where p.id=p_product and p.active and p.product_kind='goods'
   and private.commerce_product_allowed(p_customer,p.id)
 )
$$;
revoke all on function private.gama_b2b_product_visible(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function private.gama_b2b_product_favorites(p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 cid uuid:=private.gama_b2b_customer();
 pid uuid;
 off integer:=coalesce((p_data->>'offset')::integer,0);
 term text:=left(btrim(coalesce(p_data->>'search','')),100);
 wanted boolean;
 cnt integer;
 rows jsonb;
begin
 -- The resolver checks auth.uid(), MFA, verified account, current membership,
 -- active customer and the website module on EVERY read and write.
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA';end if;
 if off<0 or off>1000000 then raise exception 'INVALID_OFFSET';end if;
 if p_action='ids' then
  return coalesce((select jsonb_agg(f.product_id order by f.product_id)
   from private.b2b_product_favorites f where f.customer_id=cid and private.gama_b2b_product_visible(cid,f.product_id)),'[]'::jsonb);
 end if;
 if p_action='list' then
  with filtered as (
   select p.id,p.name,p.reference,p.category,p.tax_rate,p.order_minimum,p.order_multiple,
    (p.active and p.product_kind='goods') active,
    (p.has_photo and p.active and p.product_kind='goods') has_photo,
    p.photo_is_illustrative,f.created_at
   from private.b2b_product_favorites f join public.products p on p.id=f.product_id
   where f.customer_id=cid and private.gama_b2b_product_visible(cid,p.id) and (term='' or p.name ilike '%'||term||'%'
    or p.reference ilike '%'||term||'%' or p.barcode ilike '%'||term||'%')
  ), limited as (select * from filtered order by created_at desc,id limit 30 offset off)
  select (select count(*) from filtered),coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object(
   'unit_price',case when l.active then private.erp_price_calculate(cid,l.id,
    ceil(greatest(1,l.order_minimum)/l.order_multiple)*l.order_multiple,null)->'unit_price' else null end
   ) order by l.created_at desc,l.id),'[]'::jsonb) into cnt,rows from limited l;
  return jsonb_build_object('total',cnt,'items',rows);
 end if;
 if p_action='set' then
  pid:=nullif(p_data->>'product_id','')::uuid;
  if pid is null or jsonb_typeof(p_data->'favorite') is distinct from 'boolean' then raise exception 'INVALID_DATA';end if;
  wanted:=(p_data->>'favorite')::boolean;
  -- Serialize updates for one customer, including the bounded-list check.
  perform pg_advisory_xact_lock(hashtextextended('b2b-product-favorites:'||cid::text,0));
  if wanted then
   if not private.gama_b2b_product_visible(cid,pid) then raise exception 'PRODUCT_NOT_FOUND';end if;
   if not exists(select 1 from private.b2b_product_favorites f where f.customer_id=cid and f.product_id=pid)
    and (select count(*) from private.b2b_product_favorites f where f.customer_id=cid)>=500 then raise exception 'B2B_PRODUCT_FAVORITE_LIMIT';end if;
   insert into private.b2b_product_favorites(customer_id,product_id) values(cid,pid) on conflict do nothing;
  else
   -- Unavailable products can still be removed. Retrying either state is safe.
   delete from private.b2b_product_favorites f where f.customer_id=cid and f.product_id=pid;
  end if;
  return jsonb_build_object('product_id',pid,'favorite',wanted);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
-- Harden the original photo implementation without adding a callable predecessor
-- or changing its OID. Every outer B2B wrapper already derives the current company.
do $photo_guard$
declare body text;before_guard text;after_guard text;
begin
 select pg_get_functiondef('private.gama_b2b_action_before_documents(text,jsonb)'::regprocedure) into body;
 before_guard:='if not exists(select 1 from public.products p where p.id=v_id and p.active and p.product_kind=''goods'') then raise exception ''PRODUCT_NOT_FOUND'';end if;';
 after_guard:='if not private.gama_b2b_product_visible(cid,v_id) then raise exception ''PRODUCT_NOT_FOUND'';end if;';
 if (length(body)-length(replace(body,before_guard,'')))/length(before_guard)<>1 then
  raise exception 'B2B_PHOTO_VISIBILITY_ANCHOR';
 end if;
 execute replace(body,before_guard,after_guard);
end $photo_guard$;
notify pgrst,'reload schema';
commit;
