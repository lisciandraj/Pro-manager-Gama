-- GAMA — De qué contrato sale cada precio pactado con un cliente.
--
-- customer_special_prices ya guardaba el precio de UN cliente y UN producto.
-- Le falta decir de dónde sale: se rellena al cargar las tarifas de golpe
-- desde 📥 Importación Excel (tipo «Tarifas de cliente») y es lo que hay que
-- mirar en 🏷️ Tarifas especiales cuando el contrato cambia.
--
-- Aditiva y opcional: los precios que ya había siguen valiendo sin referencia.
-- La clave única (cliente, producto) que ya existía es lo que hace que volver
-- a subir la lista CORRIJA el precio en vez de duplicarlo.
--
-- Aplicada en producción el 2026-09-09 como
-- gama_customer_special_prices_contract_ref.
alter table public.customer_special_prices
  add column if not exists contract_ref text;
