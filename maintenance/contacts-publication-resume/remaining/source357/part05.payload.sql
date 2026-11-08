
revoke all on function public.gama_commerce_catalog_admin(text,jsonb) from public,anon;
grant execute on function public.gama_commerce_catalog_admin(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
