-- Reuse the public product projection, with prices derived from the verified customer.
-- No customer identifier, price or permission claim is accepted from the browser.
begin;
create function private.gama_b2b_storefront_price(cid uuid,item jsonb) returns jsonb
language sql stable set search_path='' as $$
 select item || jsonb_build_object(
  'unit_price',private.erp_price_calculate(cid,p.id,
   case when coalesce(p.order_multiple,0)>0 then ceil(greatest(1,coalesce(p.order_minimum,0))/p.order_multiple)*p.order_multiple
        else greatest(1,coalesce(p.order_minimum,0)) end,null)->'unit_price',
  'tax_rate',p.tax_rate,'orderable',p.product_kind='goods')
 from public.products p where p.id=(item->>'id')::uuid and p.active
$$;
revoke all on function private.gama_b2b_storefront_price(uuid,jsonb) from public,anon,authenticated;

create function private.gama_b2b_storefront(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid;cfg jsonb;result jsonb;rows jsonb;sortby text;term text;cat text;brand_filter text;off integer;lim integer;cnt integer;
begin
 if auth.uid() is null then raise exception 'B2B_ACCESS_REQUIRED';end if;
 cid:=private.gama_b2b_customer();
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>4000 then raise exception 'WEBSITE_INVALID_DATA';end if;
 select config into cfg from private.website_public_settings where id;
 if not coalesce((cfg->>'site_enabled')::boolean,false) then raise exception 'WEBSITE_PUBLIC_PAUSED';end if;
 if p_action='bootstrap' then
  result:=storefront_api.gama_storefront('bootstrap','{}');
  select coalesce(jsonb_agg(private.gama_b2b_storefront_price(cid,item) order by n),'[]') into rows from jsonb_array_elements(result->'featured') with ordinality f(item,n);
  return jsonb_set(result,'{featured}',rows);
 elsif p_action='product' then
  result:=storefront_api.gama_storefront('product',p_data);
  return jsonb_set(result,'{item}',private.gama_b2b_storefront_price(cid,result->'item'));
 elsif p_action='catalog' then
  term:=left(coalesce(p_data->>'search',''),100);cat:=coalesce(p_data->>'category','');brand_filter:=coalesce(p_data->>'brand','');sortby:=coalesce(nullif(p_data->>'sort',''),cfg->>'default_sort');
  if sortby not in ('featured','name','price_asc','price_desc') then raise exception 'WEBSITE_INVALID_DATA';end if;
  off:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));lim:=greatest(1,least(coalesce((p_data->>'limit')::integer,(cfg->>'page_size')::integer),36));
  with filtered as materialized (
   select * from private.gama_storefront_items() i
   where (term='' or strpos(lower(i.name||' '||coalesce(i.reference,'')||' '||i.brand),lower(term))>0)
    and (cat='' or i.category=cat) and (brand_filter='' or i.brand=brand_filter)
  ), candidates as (
   select * from filtered order by case when sortby='featured' then featured end desc nulls last,name,id
   limit case when sortby in ('price_asc','price_desc') then null else lim end
   offset case when sortby in ('price_asc','price_desc') then 0 else off end
  ), priced as materialized (
   select private.gama_b2b_storefront_price(cid,to_jsonb(i)) item from candidates i
  ), ranked as (
   select item,
    (item->>'unit_price')::numeric * case when cfg->>'price_display'='without_tax' then 1 else 1+coalesce((item->>'tax_rate')::numeric,0)/100 end amount
   from priced
  ), selected as (
   select item from ranked order by
    case when sortby='price_asc' then amount end asc nulls last,
    case when sortby='price_desc' then amount end desc nulls last,
    case when sortby='featured' then (item->>'featured')::boolean end desc nulls last,item->>'name',item->>'id'
   limit lim offset case when sortby in ('price_asc','price_desc') then off else 0 end
  ) select (select count(*) from filtered),coalesce(jsonb_agg(item),'[]') into cnt,rows from selected;
  return jsonb_build_object('items',rows,'total',cnt,'offset',off,'limit',lim,'currency',(select currency from public.company_settings where id));
 end if;
 raise exception 'WEBSITE_INVALID_ACTION';
end $$;
revoke all on function private.gama_b2b_storefront(text,jsonb) from public,anon;
grant execute on function private.gama_b2b_storefront(text,jsonb) to authenticated;
create function public.gama_b2b_storefront(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$ select private.gama_b2b_storefront(p_action,p_data) $$;
revoke all on function public.gama_b2b_storefront(text,jsonb) from public,anon;
grant execute on function public.gama_b2b_storefront(text,jsonb) to authenticated;
commit;
