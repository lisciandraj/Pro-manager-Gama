-- Add missing structured address fields; retain existing data, policies and grants.
alter table public.customers add column if not exists postal_code text, add column if not exists country text;
alter table public.crm_leads add column if not exists province text, add column if not exists postal_code text;
notify pgrst, 'reload schema';
