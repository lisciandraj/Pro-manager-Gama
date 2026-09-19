-- Picking confirms each line once. Weight and dimensions come from the product sheet.
-- Additive: no quantity, reservation or package of an existing document is changed.
alter table public.fulfillment_packages
 alter column weight_kg drop not null,
 alter column length_cm drop not null,
 alter column width_cm drop not null,
 alter column height_cm drop not null;
comment on column public.fulfillment_packages.weight_kg is 'Derivado de products.weight_g al crear el bulto. Nulo cuando la ficha de algún producto no lo indica.';
comment on column public.fulfillment_packages.length_cm is 'Sin origen en la ficha del producto; se conserva por historial y queda vacío.';
do $$ declare src text;old text;begin
 select pg_get_functiondef('private.gama_fulfillment_action(text,jsonb)'::regprocedure) into src;
 -- The operator no longer types weight or dimensions; the parcel reads the product sheet.
 old:=$s$  insert into public.fulfillment_packages(preparation_id,weight_kg,length_cm,width_cm,height_cm,created_by)
  values(p.id,(p_data->>'weight_kg')::numeric,(p_data->>'length_cm')::numeric,(p_data->>'width_cm')::numeric,(p_data->>'height_cm')::numeric,u) returning id into eid;$s$;
 if position(old in src)=0 then raise exception 'Unexpected package insert';end if;
 src:=replace(src,old,$s$  insert into public.fulfillment_packages(preparation_id,created_by) values(p.id,u) returning id into eid;$s$);
 -- The product was already verified when its line was picked; the parcel never re-scans it.
 old:=$s$   select barcode into photo from public.products where id=(select product_id from public.sales_order_lines where id=pl.order_line_id);
   if nullif(btrim(photo),'') is null or btrim(coalesce(x->>'product_code',''))<>btrim(photo) then raise exception 'PRODUCT_SCAN_MISMATCH';end if;
$s$;
 if position(old in src)=0 then raise exception 'Unexpected package scan';end if;
 src:=replace(src,old,'');
 -- Weight is summed from the product sheet once the content is known. Missing data stays empty.
 old:=$s$   insert into public.fulfillment_package_lines values(eid,pl.id,qty);
  end loop;$s$;
 if position(old in src)=0 then raise exception 'Unexpected package lines';end if;
 src:=replace(src,old,$s$   insert into public.fulfillment_package_lines values(eid,pl.id,qty);
  end loop;
  update public.fulfillment_packages set weight_kg=(
   select case when bool_and(coalesce(pr.weight_g,0)>0) and round(sum(t.quantity*pr.weight_g)/1000,3) between 0.001 and 99999999 then round(sum(t.quantity*pr.weight_g)/1000,3) end
   from public.fulfillment_package_lines t join public.fulfillment_pick_lines fl on fl.id=t.pick_line_id
   join public.sales_order_lines ol on ol.id=fl.order_line_id join public.products pr on pr.id=ol.product_id
   where t.package_id=eid) where id=eid;$s$);
 -- Picking is scan driven again. A code that is sent must match; products without one are not blocked.
 old:=$s$  select * into pr from public.products where id=l.product_id;$s$;
 if position(old in src)=0 then raise exception 'Unexpected picking product';end if;
 src:=replace(src,old,old||$s$
  if nullif(btrim(coalesce(p_data->>'product_code','')),'') is not null and btrim(p_data->>'product_code')<>btrim(coalesce(pr.barcode,'')) then raise exception 'PRODUCT_SCAN_MISMATCH';end if;$s$);
 execute src;
end $$;
