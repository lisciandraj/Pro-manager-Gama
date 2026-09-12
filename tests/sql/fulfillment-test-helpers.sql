-- Test fixture helper only: load inside BEGIN and always ROLLBACK the suite.
-- Existing sales/TMS tests supply desired dispatch contents. This builds the
-- required preparation and packages through the same public APIs as operators.
create function pg_temp.gama_test_prepared_ship(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;prep uuid;pl uuid;items jsonb:='[]';x jsonb;code text;location_code text;
begin
 if p_action<>'ship' then raise exception 'TEST_HELPER_SHIP_ONLY';end if;
 -- Preserve the original validation/error assertions, without retaining any
 -- changes from the preflight (its subtransaction is deliberately rolled back).
 begin
  result:=private.gama_sales_action_before_fulfillment('ship',p_data);
  raise exception sqlstate 'P4321' using message='TEST_PREFLIGHT_ROLLBACK';
 exception when sqlstate 'P4321' then null;end;
 select jsonb_build_object('id',id,'order_id',order_id) into result from public.sales_deliveries where request_key=(p_data->>'request_key')::uuid;
 if result is not null then return result;end if;
 perform public.gama_fulfillment_action('start',jsonb_build_object('order_id',p_data->>'order_id','request_key',gen_random_uuid()));
 select id into prep from public.fulfillment_preparations where order_id=(p_data->>'order_id')::uuid and status='picking';
 for x in select value from jsonb_array_elements(p_data->'lines') loop
  select id into pl from public.fulfillment_pick_lines where preparation_id=prep and order_line_id=(x->>'line_id')::uuid and source_location_id=(x->>'location_id')::uuid;
  select p.barcode into code from public.sales_order_lines l join public.products p on p.id=l.product_id where l.id=(x->>'line_id')::uuid;
  select wl.code into location_code from public.warehouse_locations wl where id=(x->>'location_id')::uuid;
  perform public.gama_fulfillment_action('pick',jsonb_build_object('order_id',p_data->>'order_id','request_key',gen_random_uuid(),'pick_line_id',pl,'product_code',code,'location_code',location_code,'quantity',x->'quantity'));
  items:=items||jsonb_build_array(jsonb_build_object('pick_line_id',pl,'product_code',code,'quantity',x->'quantity'));
 end loop;
 perform public.gama_fulfillment_action('package',jsonb_build_object('order_id',p_data->>'order_id','request_key',gen_random_uuid(),'lines',items,'weight_kg',1,'length_cm',10,'width_cm',10,'height_cm',10));
 perform public.gama_fulfillment_action('finish',jsonb_build_object('order_id',p_data->>'order_id','request_key',gen_random_uuid(),'reason','SQL regression partial shipment'));
 return public.gama_sales_action('ship',p_data||jsonb_build_object('preparation_id',prep));
end $$;
