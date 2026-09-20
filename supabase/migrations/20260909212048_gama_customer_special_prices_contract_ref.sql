-- De qué contrato sale cada precio pactado con un cliente. Se rellena al
-- cargarlos de golpe desde Importación Excel y es lo que hay que mirar cuando
-- el contrato cambia. Aditiva y opcional: los precios que ya había siguen
-- valiendo sin referencia.
alter table public.customer_special_prices
  add column if not exists contract_ref text;
