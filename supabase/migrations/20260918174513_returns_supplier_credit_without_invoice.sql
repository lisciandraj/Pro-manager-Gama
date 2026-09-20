-- Un abono de proveedor llega a menudo sin que GAMA tenga registrada su
-- factura: exigir una u otra bloqueaba el caso normal. Lo que no puede pasar
-- es que un mismo abono cuelgue de una factura de venta y de una de compra.
-- Que el abono de cliente lleve factura lo sigue exigiendo la API
-- (INVOICE_REQUIRED), donde el pliego lo pide.
alter table public.return_credits drop constraint return_credits_check;
alter table public.return_credits add constraint return_credits_check
 check (not (invoice_id is not null and supplier_invoice_id is not null));
