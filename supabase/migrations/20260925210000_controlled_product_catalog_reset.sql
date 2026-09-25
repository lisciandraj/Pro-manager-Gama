-- Controlled one-time Coco ERP catalogue reset.
-- Removes only rows whose FK points at the current product catalogue.
-- No TRUNCATE CASCADE is used. Unrelated customers, suppliers, users and settings remain.
do $$
declare
  v_products uuid[];
  v_count integer;
begin
  select coalesce(array_agg(id), array[]::uuid[]), count(*)::integer
    into v_products, v_count
  from public.products;

  if v_count = 0 then
    raise notice 'COCO_PRODUCT_RESET: catalogue already empty';
    return;
  end if;

  -- Product-linked operational/detail data.
  delete from public.sales_fulfillment_options where replacement_product_id = any(v_products);
  delete from public.supplier_product_offers where product_id = any(v_products);
  delete from public.stock_adjustment_requests where product_id = any(v_products);
  delete from public.stock_reservations where product_id = any(v_products);
  delete from public.stock_quants where product_id = any(v_products);
  delete from public.stock_movements where product_id = any(v_products);
  delete from public.return_lines where product_id = any(v_products);
  delete from public.reorder_rules where product_id = any(v_products);
  delete from public.purchase_order_lines where product_id = any(v_products);
  delete from public.product_units where product_id = any(v_products);
  delete from public.product_price_history where product_id = any(v_products);
  delete from public.product_lots where product_id = any(v_products);
  delete from public.invoice_lines where product_id = any(v_products);
  delete from public.inventory_count_lines where product_id = any(v_products);
  delete from public.favorite_order_lines where product_id = any(v_products);
  delete from public.erp_price_tiers where product_id = any(v_products);
  delete from public.customer_special_prices where product_id = any(v_products);
  delete from public.customer_request_lines where product_id = any(v_products);
  delete from public.crm_opportunity_lines where product_id = any(v_products);
  delete from public.commercial_matrix where product_id = any(v_products);
  delete from private.erp_stock_cost_opening where product_id = any(v_products);

  delete from public.products where id = any(v_products);

  if exists (select 1 from public.products where id = any(v_products)) then
    raise exception 'COCO_PRODUCT_RESET_FAILED';
  end if;

  raise notice 'COCO_PRODUCT_RESET: removed % products and product-linked rows', v_count;
end $$;
