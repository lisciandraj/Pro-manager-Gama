-- Contact addresses -> exact GPS -> matching, unstarted TMS deliveries.
-- Async networking never waits inside a contact save. Enable separately after QA.
alter table public.suppliers add column if not exists lat double precision,add column if not exists lng double precision;
alter table public.crm_leads add column if not exists lat double precision,add column if not exists lng double precision;
create table private.contact_geocode_settings(
 id boolean primary key default true check(id),enabled boolean not null default false,
 last_request_at timestamptz,request_day date,requests_today integer not null default 0,
 daily_limit integer not null default 200 check(daily_limit between 1 and 1000)
);
insert into private.contact_geocode_settings(id) values(true);
create table private.contact_geocode_cache(
 address_key text primary key,lat double precision not null,lng double precision not null,
 source text not null,conflicted boolean not null default false,updated_at timestamptz not null default now(),
 check(lat between -85 and 85 and lng between -180 and 180)
);
create table private.contact_geocode_jobs(
 kind text not null check(kind in ('customers','suppliers','crm_leads','customer_addresses')),
 entity_id uuid not null,address_key text not null,address_data jsonb not null,
 state text not null check(state in ('queued','running','located','needs_review','not_found','failed','cancelled')),
 reason text,attempts integer not null default 0,request_id bigint,requested_at timestamptz,
 available_at timestamptz not null default now(),candidates jsonb not null default '[]',
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 primary key(kind,entity_id),check(octet_length(address_data::text)<=5000 and octet_length(candidates::text)<=16000)
);
create index contact_geocode_jobs_pending on private.contact_geocode_jobs(available_at,created_at) where state='queued';
create index contact_geocode_jobs_running on private.contact_geocode_jobs(request_id) where state='running';
do $$declare t text;begin foreach t in array array['contact_geocode_settings','contact_geocode_cache','contact_geocode_jobs'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
end loop;end $$;

create function private.contact_address_norm(p_text text) returns text language sql immutable set search_path='' as $$
 select btrim(regexp_replace(regexp_replace(
  regexp_replace(translate(lower(coalesce(p_text,'')),'áàäâéèëêíìïîóòöôúùüûñç','aaaaeeeeiiiioooouuuunc'),'[^a-z0-9 -]+',' ','g'),
  '(^| )(av|avda)( |$)','\1avenida\3','g'),' +',' ','g'))
$$;
create function private.contact_country_code(p_country text) returns text language sql immutable set search_path='' as $$
 select case private.contact_address_norm(p_country)
  when '' then 'EC' when 'ecuador' then 'EC' when 'ecudor' then 'EC' when 'equateur' then 'EC'
  when 'belgique' then 'BE' when 'belgica' then 'BE' when 'belgium' then 'BE'
  when 'france' then 'FR' when 'francia' then 'FR' when 'espagne' then 'ES' when 'espana' then 'ES' when 'spain' then 'ES'
  when 'united states' then 'US' when 'estados unidos' then 'US' when 'etats unis' then 'US'
  else case when btrim(p_country)~* '^[a-z]{2}$' then upper(btrim(p_country)) end end
$$;
create function private.contact_address_key(p_data jsonb) returns text language sql immutable set search_path='' as $$
 select md5(jsonb_build_array(private.contact_address_norm(p_data->>'address'),private.contact_address_norm(p_data->>'city'),
  private.contact_address_norm(p_data->>'province'),private.contact_address_norm(p_data->>'postal_code'),
  coalesce(private.contact_country_code(p_data->>'country'),private.contact_address_norm(p_data->>'country')))::text)
$$;
create function private.contact_address_matches(p_address text,p_data jsonb) returns boolean language sql immutable set search_path='' as $$
 select private.contact_address_norm(p_address)<>'' and private.contact_address_norm(p_data->>'address')<>''
 and private.contact_address_norm(p_address)=any(array[
  private.contact_address_norm(p_data->>'address'),
  private.contact_address_norm(concat_ws(', ',nullif(p_data->>'address',''),nullif(p_data->>'city',''))),
  private.contact_address_norm(concat_ws(', ',nullif(p_data->>'address',''),nullif(p_data->>'city',''),nullif(p_data->>'country',''))),
  private.contact_address_norm(concat_ws(', ',nullif(p_data->>'address',''),nullif(p_data->>'city',''),nullif(p_data->>'province',''))),
  private.contact_address_norm(concat_ws(', ',nullif(p_data->>'address',''),nullif(p_data->>'city',''),nullif(p_data->>'province',''),nullif(p_data->>'postal_code',''),nullif(p_data->>'country','')))])
$$;
create function private.contact_geocode_snapshot(p_kind text,p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$declare row jsonb;begin
 if p_kind not in ('customers','suppliers','crm_leads','customer_addresses') or to_regclass('public.'||p_kind) is null then return null;end if;
 execute format('select to_jsonb(x) from public.%I x where id=$1',p_kind) into row using p_id;
 if row is null then return null;end if;
 -- Only address fields enter the queue or the provider request. No names,
 -- email, phone, tax identity, document, user or financial data is sent.
 return jsonb_build_object('id',row->'id','address',row->'address','city',row->'city','province',row->'province',
  'postal_code',row->'postal_code','country',row->'country','lat',row->'lat','lng',row->'lng','active',row->'active',
  'customer_id',case when p_kind='customers' then row->'id' else row->'customer_id' end,'purpose',row->'purpose');
end $$;

create function private.contact_gps_for_delivery(p_customer uuid,p_address text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare points jsonb;sites jsonb:='[]';begin
 select coalesce(jsonb_agg(jsonb_build_object('lat',c.lat,'lng',c.lng)),'[]') into points from public.customers c
 where c.id=p_customer and c.active and c.lat is not null and c.lng is not null
  and private.contact_address_matches(p_address,to_jsonb(c));
 if exists(select 1 from information_schema.columns where table_schema='public' and table_name='customer_addresses' and column_name='lat') then
  execute $query$select coalesce(jsonb_agg(jsonb_build_object('lat',a.lat,'lng',a.lng)),'[]') from public.customer_addresses a
   join public.customers c on c.id=a.customer_id and c.active
   where a.customer_id=$1 and a.active and a.purpose='delivery' and a.lat is not null and a.lng is not null
    and private.contact_address_matches($2,to_jsonb(a))$query$
   into sites using p_customer,p_address;
 end if;
 points:=points||sites;
 if jsonb_array_length(points)>0 and (select count(distinct x) from jsonb_array_elements(points)x)=1 then return points->0;end if;
 return null;
end $$;

create or replace function private.tms_customer_gps() returns trigger language plpgsql security definer set search_path='' as $$
declare point jsonb;begin
 if tg_op='UPDATE' and (new.address is distinct from old.address or new.customer_id is distinct from old.customer_id)
  and new.lat is not distinct from old.lat and new.lng is not distinct from old.lng then new.lat:=null;new.lng:=null;end if;
 if new.customer_id is not null and new.lat is null and new.lng is null then
  point:=private.contact_gps_for_delivery(new.customer_id,new.address);
  new.lat:=(point->>'lat')::double precision;new.lng:=(point->>'lng')::double precision;
 end if;return new;
end $$;

create function private.contact_gps_propagate(p_customer uuid) returns integer
language plpgsql security definer set search_path='' as $$declare changed integer;begin
 if p_customer is null then return 0;end if;
 -- Coordinates may be added to a matching open destination, never to a
 -- different site or an already departed/loaded/closed/historic delivery.
 with eligible as (select d.id from public.tms_deliveries d
 where d.customer_id=p_customer and d.lat is null and d.lng is null
  and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción')
  and not exists(select 1 from public.sales_deliveries s where s.tms_delivery_id=d.id and s.departed_at is not null)
  and not exists(select 1 from public.tms_routes r where r.id=d.route_id and r.status in ('En ruta','En tránsito','Terminada','Cancelada'))
  and private.contact_gps_for_delivery(d.customer_id,d.address) is not null for update of d skip locked)
 update public.tms_deliveries d set lat=(private.contact_gps_for_delivery(d.customer_id,d.address)->>'lat')::double precision,
  lng=(private.contact_gps_for_delivery(d.customer_id,d.address)->>'lng')::double precision
 from eligible e where d.id=e.id;
 get diagnostics changed=row_count;return changed;
end $$;

create function private.contact_geocode_apply(p_kind text,p_id uuid,p_key text,p_lat double precision,p_lng double precision) returns boolean
language plpgsql security definer set search_path='' as $$declare current_data jsonb;begin
 if p_lat is null or p_lng is null or not(p_lat between -85 and 85 and p_lng between -180 and 180) then return false;end if;
 if p_kind not in ('customers','suppliers','crm_leads','customer_addresses') then return false;end if;
 execute format('select id from public.%I where id=$1 for update',p_kind) using p_id;
 current_data:=private.contact_geocode_snapshot(p_kind,p_id);
 if current_data is null or not coalesce((current_data->>'active')::boolean,false)
  or private.contact_address_key(current_data)<>p_key or nullif(current_data->>'lat','') is not null or nullif(current_data->>'lng','') is not null then return false;end if;
 execute format('update public.%I set lat=$1,lng=$2 where id=$3',p_kind) using p_lat,p_lng,p_id;
 return true;
end $$;

create function private.contact_geocode_dispatch() returns bigint
language plpgsql security definer set search_path='' as $$
declare settings private.contact_geocode_settings;job private.contact_geocode_jobs;request bigint;code text;begin
 if not pg_try_advisory_xact_lock(hashtextextended('coco-contact-geocoding',0)) then return null;end if;
 select * into settings from private.contact_geocode_settings where id;
 if not settings.enabled or settings.last_request_at>clock_timestamp()-interval '2 seconds'
  or (settings.request_day=current_date and settings.requests_today>=settings.daily_limit)
  or exists(select 1 from private.contact_geocode_jobs where state='running') then return null;end if;
 select * into job from private.contact_geocode_jobs where state='queued' and available_at<=now()
  order by available_at,created_at,kind,entity_id limit 1 for update skip locked;
 if not found then return null;end if;
 code:=private.contact_country_code(job.address_data->>'country');
 begin
 request:=net.http_get(url:='https://photon.komoot.io/api/',
  params:=jsonb_build_object('q',concat_ws(', ',job.address_data->>'address',nullif(job.address_data->>'city',''),
   nullif(job.address_data->>'province',''),nullif(job.address_data->>'postal_code','')),'countrycode',code,'limit',5,'lang','es','dedupe',0),
  headers:=jsonb_build_object('User-Agent','CocoERP/1.0 (https://lisciandraj.github.io/Pro-manager-Gama/)','Accept','application/json'),timeout_milliseconds:=8000);
 exception when others then
  update private.contact_geocode_jobs set reason='GEOCODER_QUEUE_UNAVAILABLE',available_at=now()+interval '5 minutes',updated_at=now()
   where kind=job.kind and entity_id=job.entity_id;
  return null;
 end;
 update private.contact_geocode_jobs set state='running',attempts=attempts+1,request_id=request,requested_at=now(),updated_at=now()
  where kind=job.kind and entity_id=job.entity_id;
 update private.contact_geocode_settings set last_request_at=clock_timestamp(),request_day=current_date,
  requests_today=case when request_day=current_date then requests_today+1 else 1 end where id;
 return request;
end $$;

create function private.contact_geocode_enqueue(p_kind text,p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare data jsonb;key text;cache private.contact_geocode_cache;status text:='queued';why text;begin
 data:=private.contact_geocode_snapshot(p_kind,p_id);if data is null then return;end if;
 key:=private.contact_address_key(data);
 if not coalesce((data->>'active')::boolean,false) then status:='cancelled';why:='INACTIVE_CONTACT';
 elsif nullif(data->>'lat','') is not null and nullif(data->>'lng','') is not null then
  status:='located';why:='EXISTING_COORDINATES';
  insert into private.contact_geocode_cache(address_key,lat,lng,source)
   values(key,(data->>'lat')::double precision,(data->>'lng')::double precision,'contact_gps')
   on conflict(address_key) do update set conflicted=contact_geocode_cache.conflicted
    or abs(contact_geocode_cache.lat-excluded.lat)>.0002 or abs(contact_geocode_cache.lng-excluded.lng)>.0002,updated_at=now();
 elsif length(btrim(coalesce(data->>'address','')))<4 or (nullif(btrim(data->>'city'),'') is null and nullif(btrim(data->>'postal_code'),'') is null) then
  status:='needs_review';why:='ADDRESS_INCOMPLETE';
 elsif private.contact_country_code(data->>'country') is null then status:='needs_review';why:='COUNTRY_REQUIRED';
 end if;
 insert into private.contact_geocode_jobs(kind,entity_id,address_key,address_data,state,reason)
  values(p_kind,p_id,key,data,status,why)
  on conflict(kind,entity_id) do update set address_key=excluded.address_key,address_data=excluded.address_data,
   state=excluded.state,reason=excluded.reason,attempts=0,request_id=null,requested_at=null,available_at=now(),candidates='[]',updated_at=now()
  where contact_geocode_jobs.address_key is distinct from excluded.address_key or excluded.state in ('located','cancelled')
   or (contact_geocode_jobs.state='cancelled' and excluded.state='queued');
 if status='queued' then
  select * into cache from private.contact_geocode_cache where address_key=key and not conflicted;
  if found then perform private.contact_geocode_apply(p_kind,p_id,key,cache.lat,cache.lng);end if;
 end if;
 if nullif(data->>'lat','') is not null and nullif(data->>'lng','') is not null then
  perform private.contact_gps_propagate(nullif(data->>'customer_id','')::uuid);
 end if;
 perform private.contact_geocode_dispatch();
end $$;

create function private.contact_geocode_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='UPDATE' and private.contact_address_key(to_jsonb(new)) is distinct from private.contact_address_key(to_jsonb(old))
  and new.lat is not distinct from old.lat and new.lng is not distinct from old.lng then new.lat:=null;new.lng:=null;end if;
 if tg_table_name='customers' then new.gps_address:=case when new.lat is not null and new.lng is not null then new.address end;end if;
 return new;
end $$;
create function private.contact_geocode_changed() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform private.contact_geocode_enqueue(tg_table_name,new.id);return null;
exception when others then raise warning 'CONTACT_GEOCODING_PENDING';return null;
end $$;

-- A point is automatic only when street, house number, locality, country and
-- geometry all match. A street/city centroid or multiple precise matches is review-only.
create function private.contact_geocode_candidate(p_data jsonb,p_feature jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare properties jsonb:=p_feature->'properties';coords jsonb:=p_feature->'geometry'->'coordinates';
 street text:=private.contact_address_norm(properties->>'street');house text:=private.contact_address_norm(properties->>'housenumber');
 address text:=private.contact_address_norm(p_data->>'address');city text:=private.contact_address_norm(p_data->>'city');
 rest text;lat double precision;lng double precision;begin
 if p_feature->'geometry'->>'type' is distinct from 'Point' or jsonb_typeof(coords) is distinct from 'array' or jsonb_array_length(coords)<>2
  or jsonb_typeof(coords->0) is distinct from 'number' or jsonb_typeof(coords->1) is distinct from 'number' then return null;end if;
 lat:=(coords->>1)::double precision;lng:=(coords->>0)::double precision;
 if lat is null or lng is null or not(lat between -85 and 85 and lng between -180 and 180)
  or upper(properties->>'countrycode') is distinct from private.contact_country_code(p_data->>'country') then return null;end if;
 if private.contact_country_code(p_data->>'country')='EC' and not(lat between -6 and 2 and lng between -93 and -75) then return null;end if;
 if street='' or house='' or house !~ '[0-9]' or position(' '||street||' ' in ' '||address||' ')=0 then return null;end if;
 rest:=replace(' '||address||' ',' '||street||' ',' ');
 if position(' '||house||' ' in rest)=0 then return null;end if;
 if city<>'' and position(' '||city||' ' in ' '||private.contact_address_norm(concat_ws(' ',properties->>'city',properties->>'locality',properties->>'county'))||' ')=0 then return null;end if;
 if city='' and private.contact_address_norm(p_data->>'postal_code')<>private.contact_address_norm(properties->>'postcode') then return null;end if;
 return jsonb_build_object('lat',lat,'lng',lng,'label',left(concat_ws(', ',properties->>'name',properties->>'street',properties->>'housenumber',properties->>'city',properties->>'country'),600));
exception when others then return null;
end $$;

create function private.contact_geocode_tick() returns jsonb language plpgsql security definer set search_path='' as $$
declare job private.contact_geocode_jobs;response record;body jsonb;matches jsonb;point jsonb;data jsonb;
 handled integer:=0;request bigint;failure boolean;customer record;begin
 if not pg_try_advisory_xact_lock(hashtextextended('coco-contact-geocoding',0)) then return jsonb_build_object('busy',true);end if;
 if not (select enabled from private.contact_geocode_settings where id) then return jsonb_build_object('enabled',false);end if;
 -- Lock contacts before job rows, matching the contact edit triggers. A stale
 -- response can never cancel a replacement job created by an address edit.
 for job in select * from private.contact_geocode_jobs where state='running' order by requested_at limit 10 loop
  select status_code,content,timed_out,error_msg into response from net._http_response where id=job.request_id;
  if not found and job.requested_at>now()-interval '2 minutes' then continue;end if;
  failure:=not found or coalesce(response.timed_out,false) or response.error_msg is not null
   or response.status_code is distinct from 200 or octet_length(coalesce(response.content,''))>64000;
  data:=private.contact_geocode_snapshot(job.kind,job.entity_id);
  if data is null or not coalesce((data->>'active')::boolean,false) or private.contact_address_key(data)<>job.address_key
   or nullif(data->>'lat','') is not null or nullif(data->>'lng','') is not null then
   update private.contact_geocode_jobs set state='cancelled',reason='CONTACT_CHANGED',updated_at=now()
    where kind=job.kind and entity_id=job.entity_id and address_key=job.address_key and request_id=job.request_id and state='running';continue;
  end if;
  begin
   if not failure then
    body:=response.content::jsonb;
    failure:=body->>'type' is distinct from 'FeatureCollection' or jsonb_typeof(body->'features') is distinct from 'array';
    if not failure then failure:=jsonb_array_length(body->'features')>5;end if;
   end if;
  exception when others then failure:=true;end;
  if failure then
   update private.contact_geocode_jobs set state=case when attempts<3 then 'queued' else 'failed' end,reason='GEOCODER_UNAVAILABLE',
    request_id=null,available_at=now()+make_interval(mins=>least(60,5*attempts)),updated_at=now()
    where kind=job.kind and entity_id=job.entity_id and address_key=job.address_key and request_id=job.request_id and state='running';continue;
  end if;
  select coalesce(jsonb_agg(x),'[]') into matches from (
   select private.contact_geocode_candidate(job.address_data,f) x from jsonb_array_elements(body->'features')f
  )valid where x is not null;
  if jsonb_array_length(matches)>0 and (select count(distinct (round((x->>'lat')::numeric,5),round((x->>'lng')::numeric,5))) from jsonb_array_elements(matches)x)=1 then
   point:=matches->0;
   if private.contact_geocode_apply(job.kind,job.entity_id,job.address_key,(point->>'lat')::double precision,(point->>'lng')::double precision) then
    update private.contact_geocode_jobs set state='located',reason='GEOCODED',candidates=matches,updated_at=now() where kind=job.kind and entity_id=job.entity_id and address_key=job.address_key;
    update private.contact_geocode_cache set source='Photon / OpenStreetMap contributors' where address_key=job.address_key;
   end if;
  else
   update private.contact_geocode_jobs set state=case when jsonb_array_length(body->'features')=0 then 'not_found' else 'needs_review' end,
    reason=case when jsonb_array_length(matches)>1 then 'AMBIGUOUS_ADDRESS' else 'EXACT_ADDRESS_REQUIRED' end,candidates=matches,updated_at=now()
    where kind=job.kind and entity_id=job.entity_id and address_key=job.address_key and request_id=job.request_id and state='running';
  end if;
  handled:=handled+1;
 end loop;
 -- Retry nonblocking GPS propagation if an open delivery was being edited
 -- when its contact was saved. Planning itself remains a separate operation.
 for customer in select distinct d.customer_id from public.tms_deliveries d
  where d.lat is null and d.lng is null and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción')
   and private.contact_gps_for_delivery(d.customer_id,d.address) is not null limit 100 loop
  perform private.contact_gps_propagate(customer.customer_id);
 end loop;
 request:=private.contact_geocode_dispatch();return jsonb_build_object('handled',handled,'request_id',request);
end $$;

do $$declare kind text;begin foreach kind in array array['customers','suppliers','crm_leads','customer_addresses'] loop
 if exists(select 1 from information_schema.columns where table_schema='public' and table_name=kind and column_name='lat') then
  execute format('create trigger zz_contact_geocode_guard before insert or update of address,city,province,postal_code,country,lat,lng on public.%I for each row execute function private.contact_geocode_guard()',kind);
  execute format('create trigger contact_geocode_changed after insert or update of address,city,province,postal_code,country,lat,lng,active on public.%I for each row execute function private.contact_geocode_changed()',kind);
 end if;
end loop;end $$;
do $$declare f record;begin for f in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and (p.proname like 'contact_geocode_%' or p.proname like 'contact_address_%' or p.proname in ('contact_country_code','contact_gps_for_delivery','contact_gps_propagate')) loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f.fn);
end loop;end $$;
select cron.schedule('coco-contact-geocoding','* * * * *',$cron$select private.contact_geocode_tick();$cron$);
