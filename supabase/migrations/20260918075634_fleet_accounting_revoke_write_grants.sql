-- Supabase concede por defecto todos los privilegios sobre una tabla nueva de
-- public a anon y authenticated. La RLS cierra INSERT, UPDATE y DELETE porque
-- sólo hay política de SELECT, pero TRUNCATE no pasa por las políticas: se
-- rige sólo por el privilegio. Quedaba concedido, así que la promesa de que
-- Flota es únicamente de administración tenía una rendija.
--
-- Toda escritura de estos dos módulos pasa por su RPC SECURITY DEFINER, así
-- que authenticated no necesita más que leer; y aun ese SELECT lo filtra la
-- RLS. Se dejan en paz las tablas de otros módulos que sí se escriben en
-- directo desde el cliente (hr_employees, products, tms_*, stock_*).
do $$ declare t text;
begin
 foreach t in array array[
  'fleet_vehicles','fleet_drivers','fleet_assignments','fleet_documents',
  'fleet_fuel_logs','fleet_maintenance','fleet_alert_log',
  'accounting_accounts','accounting_journals','accounting_entries','accounting_entry_lines',
  'accounting_periods','accounting_permissions','accounting_taxes',
  'financial_accounts','bank_transactions','reconciliations',
  'expenses','expense_categories','expense_receipts',
  'supplier_invoices','supplier_invoice_payments']
 loop
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;
