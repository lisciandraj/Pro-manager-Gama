-- Enlaza la entrega con la ficha del cliente: de ahí salen la empresa y la
-- dirección al crearla, y el correo al que se manda el comprobante. Queda
-- nulo cuando la entrega se escribe a mano, que sigue siendo posible.
alter table public.tms_deliveries
  add column if not exists customer_id uuid references public.customers(id) on delete set null;

create index if not exists tms_deliveries_customer_id_idx
  on public.tms_deliveries(customer_id);
