create function private.gama_barcode_lookup(p_code text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare code text:=btrim(p_code);p public.products;u public.product_units;pk public.fulfillment_packages;begin
 if not(private.erp_module_allowed('barcode',array['administrador','comercial','almacenero']) or private.erp_module_allowed('order-preparation',array['administrador','almacenero']) or private.erp_module_allowed('movement',array['administrador','almacenero'])) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if code is null or length(code) not between 1 and 180 then raise exception 'BARCODE_REQUIRED';end if;
 select * into p from public.products where (barcode=code or reference=code) and active;
 if found then return jsonb_build_object('kind','item','product_id',p.id,'code',coalesce(nullif(p.barcode,''),p.reference),'name',p.name,'factor',1,'base_unit',p.base_unit);end if;
 select * into u from public.product_units where barcode=code and active;
 if found then select * into p from public.products where id=u.product_id and active;if found then return jsonb_build_object('kind','pack','product_id',p.id,'unit_id',u.id,'code',u.barcode,'name',p.name,'label',u.label,'factor',u.factor,'base_unit',p.base_unit);end if;end if;
 select * into pk from public.fulfillment_packages where barcode=code and status='active';
 if found then return jsonb_build_object('kind','parcel','id',pk.id,'code',pk.barcode,'name',(select o.number from public.fulfillment_preparations f join public.sales_orders o on o.id=f.order_id where f.id=pk.preparation_id),'order_id',(select order_id from public.fulfillment_preparations where id=pk.preparation_id),'factor',null,'base_unit',null);end if;
 raise exception 'BARCODE_NOT_FOUND';
end $$;
revoke all on function private.gama_barcode_lookup(text) from public,anon;grant execute on function private.gama_barcode_lookup(text) to authenticated;
create function public.gama_barcode_lookup(p_code text) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_barcode_lookup(p_code)$$;
revoke all on function public.gama_barcode_lookup(text) from public,anon;grant execute on function public.gama_barcode_lookup(text) to authenticated;
create function private.erp_barcode_namespace() returns trigger language plpgsql security definer set search_path='' as $$declare code text:=nullif(btrim(new.barcode),'');begin
 if code is null or (tg_op='UPDATE' and new.barcode is not distinct from old.barcode) then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended('barcode:'||code,0));
 if exists(select 1 from public.products where (barcode=code or reference=code) and not(tg_table_name='products' and id=new.id)) or exists(select 1 from public.product_units where barcode=code and not(tg_table_name='product_units' and id=new.id)) or exists(select 1 from public.fulfillment_packages where barcode=code and not(tg_table_name='fulfillment_packages' and id=new.id)) then raise exception 'BARCODE_ALREADY_USED';end if;
 return new;end $$;
revoke all on function private.erp_barcode_namespace() from public,anon,authenticated;
create trigger erp_barcode_namespace before insert or update on public.products for each row execute function private.erp_barcode_namespace();
create trigger erp_barcode_namespace before insert or update on public.product_units for each row execute function private.erp_barcode_namespace();
create trigger erp_barcode_namespace before insert or update on public.fulfillment_packages for each row execute function private.erp_barcode_namespace();
-- A scanned pack is verified against its product. Quantities sent by the picker
-- remain base quantities, so opening a line never silently counts a carton as one.
do $$declare src text;old text;begin
 select pg_get_functiondef('private.gama_fulfillment_action(text,jsonb)'::regprocedure) into src;
 old:=$old$btrim(p_data->>'product_code')<>btrim(coalesce(pr.barcode,'')) then raise exception 'PRODUCT_SCAN_MISMATCH'$old$;
 if position(old in src)=0 then raise exception 'PICK_SCAN_ANCHOR';end if;
 src:=replace(src,old,$new$btrim(p_data->>'product_code')<>btrim(coalesce(pr.barcode,'')) and not exists(select 1 from public.product_units pu where pu.product_id=pr.id and pu.active and pu.barcode=btrim(p_data->>'product_code')) then raise exception 'PRODUCT_SCAN_MISMATCH'$new$);execute src;
end $$;
-- Preview and save SLA rules together. Existing ticket deadlines remain fixed.
create function private.gama_sla_rules(p_rows jsonb default null,p_expected jsonb default null) returns jsonb language plpgsql security definer set search_path='' as $$declare rows jsonb;x jsonb;begin
 if not private.erp_module_allowed('settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform 1 from public.service_sla_rules order by priority for update;
 select jsonb_agg(to_jsonb(r) order by priority) into rows from public.service_sla_rules r;
 if p_rows is not null then
 if rows is distinct from p_expected then raise exception 'SLA_CHANGED';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<>3 or (select count(distinct value->>'priority') from jsonb_array_elements(p_rows))<>3 then raise exception 'INVALID_SLA';end if;
 for x in select value from jsonb_array_elements(p_rows) loop
 if x->>'priority' not in ('normal','high','urgent') or (x->>'resolution_hours')::int<(x->>'response_hours')::int then raise exception 'INVALID_SLA';end if;
 update public.service_sla_rules set response_hours=(x->>'response_hours')::int,resolution_hours=(x->>'resolution_hours')::int where priority=x->>'priority';end loop;
 select jsonb_agg(to_jsonb(r) order by priority) into rows from public.service_sla_rules r;
 end if;return rows;end $$;
revoke all on function private.gama_sla_rules(jsonb,jsonb) from public,anon;grant execute on function private.gama_sla_rules(jsonb,jsonb) to authenticated;
create function public.gama_sla_rules(p_rows jsonb default null,p_expected jsonb default null) returns jsonb language sql security invoker set search_path='' as $$select private.gama_sla_rules(p_rows,p_expected)$$;
revoke all on function public.gama_sla_rules(jsonb,jsonb) from public,anon;grant execute on function public.gama_sla_rules(jsonb,jsonb) to authenticated;
revoke update on public.service_sla_rules from authenticated;

-- Allocation pickers page through this customer's invoices, not all customers.
do $$declare src text;begin
 select pg_get_functiondef('private.gama_payment_action(text,jsonb)'::regprocedure) into src;
 src:=replace(src,$old$where (nullif(p_data->>'order_id','') is null$old$,$new$where (nullif(p_data->>'customer_id','') is null or r.customer_id=(p_data->>'customer_id')::uuid) and (nullif(p_data->>'order_id','') is null$new$);execute src;
 select pg_get_functiondef('private.gama_receipt_action_core(text,jsonb)'::regprocedure) into src;
 src:=replace(src,'order by receipt.paid_at desc limit 200','order by receipt.paid_at desc,receipt.id limit 200 offset greatest(0,coalesce((p_data->>''offset'')::int,0))');execute src;
end $$;
