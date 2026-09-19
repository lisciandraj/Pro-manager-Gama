-- Server-only settings. Browser roles have no grants or applicable policy.
create policy gama_ai_settings_server_only on public.gama_ai_settings for all to service_role using (true) with check (true);
