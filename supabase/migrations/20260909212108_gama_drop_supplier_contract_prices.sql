-- Los precios pactados son cosa de la VENTA, no de la compra: se retira la
-- tabla espejo del lado del proveedor. Estaba vacía (0 filas comprobadas antes
-- de borrarla) y ninguna pantalla la lee ya.
drop table if exists public.supplier_contract_prices;
