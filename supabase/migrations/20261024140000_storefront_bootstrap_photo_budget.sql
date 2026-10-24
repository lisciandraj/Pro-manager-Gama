-- Preserve the public projection and its photo validation, but stop reading
-- every image at startup. No cache, permission change or business-data write.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '15s';
do $migration$
declare definition text;
before_text text := $before$
  -- Bootstrap needs the complete publication set for its category photo IDs.
  -- Evaluate the existing protected projection once, instead of four times.
  with items as materialized (select * from private.gama_storefront_items())
  select jsonb_build_object('paused',false,'settings',cfg,'currency',curr,'total',(select count(*) from items),
   'categories',coalesce((select jsonb_agg(to_jsonb(z)) from(select category,min(category_title) title,count(*) count,min(id::text) filter (where has_photo) photo_id from items group by category order by category) z),'[]'),
   'brands',coalesce((select jsonb_agg(brand order by brand) from(select distinct brand from items where brand<>'') z),'[]'),
   'featured',coalesce((select jsonb_agg(to_jsonb(z)) from(select * from items where featured order by name,id limit 8) z),'[]')) into rows;
$before$;
after_text text := $after$
  -- Only lightweight columns are needed for counts, groups and ordering.
  with items as materialized (
   select id,name,category,category_title,brand,featured from private.gama_storefront_projection
  )
  select jsonb_build_object('paused',false,'settings',cfg,'currency',curr,'total',(select count(*) from items),
   'categories',coalesce((select jsonb_agg(to_jsonb(z) order by category) from (
    select c.*, (
     -- OFFSET 0 keeps photo validation after UUID ordering. LIMIT 1 stops
     -- at the same first valid photo as the original min(id::text) filter.
     select i.id::text from (
      select id from items i where i.category=c.category order by id::text offset 0
     ) i where (select p.has_photo from private.gama_storefront_projection p where p.id=i.id) limit 1
    ) photo_id from (
     select category,min(category_title) title,count(*) count from items group by category
    ) c
   ) z),'[]'),
   'brands',coalesce((select jsonb_agg(brand order by brand) from(select distinct brand from items where brand<>'') z),'[]'),
   'featured',coalesce((select jsonb_agg(
    (select to_jsonb(p) from private.gama_storefront_projection p where p.id=z.id) order by name,id
   ) from(select id,name from items where featured order by name,id limit 8) z),'[]')) into rows;
$after$;
begin
 definition := pg_catalog.pg_get_functiondef('storefront_api.gama_storefront(text,jsonb)'::regprocedure);
 if strpos(definition,before_text)=0 then
  raise exception 'STOREFRONT_BOOTSTRAP_CHANGED: review the current function before applying';
 end if;
 execute replace(definition,before_text,after_text);
end $migration$;
commit;
