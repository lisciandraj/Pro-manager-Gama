revoke execute on function public.gama_receive_purchase(uuid,jsonb,text) from public;
revoke execute on function public.gama_receive_purchase(uuid,jsonb,text) from anon;
grant execute on function public.gama_receive_purchase(uuid,jsonb,text) to authenticated;
revoke execute on function public.gama_register_stock_movement(uuid,text,numeric,text,text) from public;
revoke execute on function public.gama_register_stock_movement(uuid,text,numeric,text,text) from anon;
grant execute on function public.gama_register_stock_movement(uuid,text,numeric,text,text) to authenticated;
