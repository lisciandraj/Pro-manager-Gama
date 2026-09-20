-- Only the managed Supabase platform is stubbed, never application tables or functions.
-- This fixture validates schema reconstruction, not Auth/Storage services or cryptography.
create role anon;
create role authenticated;
create role service_role bypassrls;
create role supabase_admin superuser;
create schema auth;
create schema storage;
create schema extensions;
create schema cron;
-- Supabase's observed postgres default privileges (subsequent migrations revoke where needed).
alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
alter default privileges in schema public grant all on sequences to anon,authenticated,service_role;
alter default privileges in schema public grant execute on functions to anon,authenticated,service_role;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),updated_at timestamptz default now());
create table auth.mfa_factors(id uuid primary key default gen_random_uuid(),user_id uuid references auth.users(id),status text);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create function auth.role() returns text language sql stable as $$ select current_user::text $$;
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,owner_id text);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$ select string_to_array(name,'/') $$;
grant usage on schema public,auth,storage,extensions to authenticated,anon,service_role;
grant all on all tables in schema storage to authenticated,service_role;
create publication supabase_realtime;
create table cron.job(jobid bigint generated always as identity primary key,jobname text,schedule text,command text);
create function cron.schedule(job_name text,schedule text,command text) returns bigint language plpgsql as $$ declare i bigint;begin insert into cron.job(jobname,schedule,command) values(job_name,schedule,command) returning jobid into i;return i;end $$;
create function cron.unschedule(job_name text) returns boolean language plpgsql as $$ begin delete from cron.job where jobname=job_name;return true;end $$;
