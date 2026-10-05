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
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,banned_until timestamptz,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),updated_at timestamptz default now());
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

-- Managed extensions only: isolated fixtures record intended requests and
-- explicit simulated responses. They never contact a provider or use real keys.
create schema vault;
create table vault.decrypted_secrets(id uuid primary key default gen_random_uuid(),decrypted_secret text,name text);
create function vault.create_secret(new_secret text,new_name text default null,new_description text default '') returns uuid language plpgsql as $$declare key uuid;begin insert into vault.decrypted_secrets(decrypted_secret,name) values(new_secret,new_name) returning id into key;return key;end $$;
create function vault.update_secret(secret_id uuid,new_secret text default null,new_name text default null,new_description text default null) returns void language sql as $$update vault.decrypted_secrets set decrypted_secret=coalesce(new_secret,decrypted_secret),name=coalesce(new_name,name) where id=secret_id$$;
create schema net;
create table net.fixture_requests(id bigint generated always as identity primary key,url text,body jsonb,headers jsonb);
create table net._http_response(id bigint primary key,status_code integer,content text,timed_out boolean default false,error_msg text,created timestamptz default now());
create function net.http_post(url text,body jsonb default '{}',params jsonb default '{}',headers jsonb default '{}',timeout_milliseconds integer default 2000) returns bigint language plpgsql as $$declare req bigint;begin insert into net.fixture_requests(url,body,headers) values(url,body,headers) returning id into req;return req;end $$;
create function net.http_get(url text,params jsonb default '{}',headers jsonb default '{}',timeout_milliseconds integer default 2000) returns bigint language plpgsql as $$declare req bigint;begin insert into net.fixture_requests(url,headers) values(url,headers) returning id into req;return req;end $$;
