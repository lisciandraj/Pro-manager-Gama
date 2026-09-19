-- El Asistente lee el catálogo, no tablas nuevas: bastan las cuatro de
-- Devoluciones y retirar las tres antiguas. Las columnas con adjuntos
-- (data_url) se quedan fuera, como en el resto del catálogo.
do $mig$
declare src text:=pg_get_functiondef('public.gama_ai_catalog()'::regprocedure); before int;
begin
 before:=length(src);
 src:=replace(src,'{"table":"customer_return_credits","columns":["id","return_id","invoice_id","number","amount","notes","created_by","created_at"],"pk":["id"],"module":"sales-orders"},','');
 src:=replace(src,'{"table":"customer_return_photos","columns":["id","return_id","filename","created_at"],"pk":["id"],"module":"sales-orders"},','');
 src:=replace(src,'{"table":"customer_returns","columns":["id","number","order_id","delivery_line_id","quantity","reason","status","quarantine_location_id","hold_reservation_id","replacement_order_id","inspection_notes","received_at","closed_at","created_by","created_at"],"pk":["id"],"module":"sales-orders"},','');
 if length(src)>=before then raise exception 'ANCHOR_AI_LEGACY_RETURNS';end if;
 if position('customer_return' in src)>0 then raise exception 'AI_LEGACY_LEFTOVER';end if;

 before:=length(src);
 src:=replace(src,'{"table":"sales_deliveries","columns":["id","number","order_id"',
  '{"table":"return_orders","columns":["id","number","kind","status","customer_id","order_id","delivery_id","invoice_id","supplier_id","purchase_order_id","supplier_invoice_id","reason","notes","financial_action","carrier","tracking","shipped_on","received_at","processed_at","closed_at","created_by","created_at","updated_at"],"pk":["id"],"module":"returns"},'||
  '{"table":"return_lines","columns":["id","return_id","product_id","quantity","unit_price","tax_rate","delivery_line_id","purchase_order_line_id","disposition","processed_at","notes","created_at"],"pk":["id"],"module":"returns"},'||
  '{"table":"return_credits","columns":["id","number","return_id","invoice_id","supplier_invoice_id","supplier_reference","amount","issued_on","notes","created_by","created_at"],"pk":["id"],"module":"returns"},'||
  '{"table":"return_refunds","columns":["id","return_id","amount","paid_at","method","reference","notes","created_by","created_at"],"pk":["id"],"module":"returns"},'||
  '{"table":"sales_deliveries","columns":["id","number","order_id"');
 if length(src)<=before then raise exception 'ANCHOR_AI_INSERT';end if;
 execute src;
end $mig$;
