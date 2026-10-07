-- Categories use an actual published product photo, or a neutral icon when absent.
-- Keep the existing public API, authorization and private-data projection intact.
begin;
do $$
declare definition text; before_text text := 'min(id::text) photo_id';
begin
 definition := pg_get_functiondef('storefront_api.gama_storefront(text,jsonb)'::regprocedure);
 if strpos(definition,before_text)=0 then raise exception 'STOREFRONT_CATEGORY_PROJECTION_CHANGED'; end if;
 execute replace(definition,before_text,'min(id::text) filter (where has_photo) photo_id');
end $$;
commit;
