-- The public Photon instance supports only default/de/en/fr. Omit lang to use
-- the native address language, including Spanish streets in Ecuador.
create or replace function private.contact_geocode_dispatch() returns bigint
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
   nullif(job.address_data->>'province',''),nullif(job.address_data->>'postal_code','')),'countrycode',code,'limit',5,'dedupe',0),
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
