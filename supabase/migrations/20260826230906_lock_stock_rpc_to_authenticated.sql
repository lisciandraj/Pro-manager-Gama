revoke execute on function public.gama_register_stock_movement(uuid,text,numeric,text,text) from anon;
grant execute on function public.gama_register_stock_movement(uuid,text,numeric,text,text) to authenticated;
