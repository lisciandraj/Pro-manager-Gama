-- El seguimiento de expediente lista las tablas que puede numerar. El retorno
-- es un documento más de la cadena, así que entra en la lista.
alter table public.gama_document_references drop constraint gama_document_references_table_name_check;
alter table public.gama_document_references add constraint gama_document_references_table_name_check
 check(table_name = any(array['customer_requests','invoices','sales_orders','fulfillment_preparations',
  'fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices',
  'external_invoice_payments','customer_returns','return_orders']));
