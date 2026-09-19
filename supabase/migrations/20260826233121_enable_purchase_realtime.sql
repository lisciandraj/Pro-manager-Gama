alter table public.purchase_orders replica identity full;
alter table public.purchase_order_lines replica identity full;
do $$ begin
 if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='purchase_orders') then alter publication supabase_realtime add table public.purchase_orders; end if;
 if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='purchase_order_lines') then alter publication supabase_realtime add table public.purchase_order_lines; end if;
end $$;
