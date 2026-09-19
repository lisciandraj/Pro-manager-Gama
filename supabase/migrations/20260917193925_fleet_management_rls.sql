do $$ declare t text;
begin
 foreach t in array array['fleet_vehicles','fleet_drivers','fleet_assignments','fleet_documents',
  'fleet_fuel_logs','fleet_maintenance']
 loop
  execute format('create trigger %I after insert or update or delete on public.%I for each row execute function private.gama_audit_row()','fl_audit_'||t,t);
 end loop;
 foreach t in array array['fleet_vehicles','fleet_drivers','fleet_assignments','fleet_documents',
  'fleet_fuel_logs','fleet_maintenance','fleet_alert_log']
 loop
  execute format('alter table public.%I enable row level security',t);
  execute format('create policy %I on public.%I for select to authenticated using (private.gama_fleet_may())','fl_read_'||t,t);
  execute format('revoke all on public.%I from anon',t);
  execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;
