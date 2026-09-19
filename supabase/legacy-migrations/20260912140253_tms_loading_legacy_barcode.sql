-- Permit pre-existing pending shipments with a missing barcode to recover when
-- the product master is completed. Existing barcode snapshots never change.
create function private.gama_fill_legacy_loading_barcode() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if length(btrim(coalesce(new.barcode,'')))=0 then return new; end if;
 perform pg_advisory_xact_lock(741932,1);
 update public.sales_delivery_lines dl set loading_barcode=new.barcode
 from public.sales_order_lines ol,public.sales_deliveries sd,public.tms_deliveries td
 where ol.id=dl.order_line_id and ol.product_id=new.id and sd.id=dl.delivery_id
 and td.id=sd.tms_delivery_id and sd.loading_required and sd.departed_at is null
 and td.status not in ('Cancelada','Entregada')
 and length(btrim(coalesce(dl.loading_barcode,'')))=0;
 return new;
end $$;
revoke all on function private.gama_fill_legacy_loading_barcode() from public,anon,authenticated;
create trigger loading_legacy_barcode after update of barcode on public.products for each row execute function private.gama_fill_legacy_loading_barcode();
