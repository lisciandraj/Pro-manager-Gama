-- User-requested initial publication selection: every active catalogue product.
alter table private.website_products alter column public_visible set default true;
insert into private.website_products(product_id,public_visible)
 select id,true from public.products where active
 on conflict(product_id) do update set public_visible=true,version=private.website_products.version+1,updated_at=now();
-- Product write permission/RLS is checked on the source row. This narrow trigger
-- owns the private publication defaults; it never changes an explicit selection.
create function private.website_product_default() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.active then insert into private.website_products(product_id,public_visible) values(new.id,true) on conflict(product_id) do nothing;end if;
 return new;
end $$;
revoke all on function private.website_product_default() from public,anon,authenticated;
create trigger website_product_default after insert or update of active on public.products for each row execute function private.website_product_default();
