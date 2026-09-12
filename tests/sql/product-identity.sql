-- Execute inside BEGIN ... ROLLBACK after the migration. No fixtures persist.
do $$
declare
 a uuid; b uuid; uid uuid; legacy uuid; prefix text:='IDENTITY-TEST-'||gen_random_uuid();
 f text; denied boolean; n int;
begin
 select id into uid from public.profiles where role='administrador' and active limit 1;
 if uid is null then raise exception 'ADMIN_REQUIRED';end if;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 insert into public.products(name,barcode,reference) values(prefix||' One',prefix||'-B1',prefix||'-R1') returning id into a;
 insert into public.products(name,barcode,reference) values(prefix||' Two',prefix||'-B2',prefix||'-R2') returning id into b;
 foreach f in array array['name','barcode','reference'] loop
  denied:=false;
  begin
   execute format('insert into public.products(name,barcode,reference) select case when $1=''name'' then ''  ''||upper(name)||''  '' else $2||'' Three'' end, case when $1=''barcode'' then lower(barcode) else $2||''-B3'' end, case when $1=''reference'' then upper(reference) else $2||''-R3'' end from public.products where id=$3') using f,prefix,a;
  exception when unique_violation then denied:=true;end;
  if not denied then raise exception 'DUPLICATE_INSERT_ALLOWED: %',f;end if;
  denied:=false;
  begin
   execute format('update public.products set %I=(select %I from public.products where id=$1) where id=$2',f,f) using a,b;
  exception when unique_violation then denied:=true;end;
  if not denied then raise exception 'DUPLICATE_UPDATE_ALLOWED: %',f;end if;
 end loop;
 -- Own unchanged identity, optional blank references and ordinary photo edits remain usable.
 update public.products set name=upper(name),reference=reference,photo_data='data:image/png;base64,AA==' where id=a;
 update public.products set reference=null where id=a;
 update public.products set reference=prefix||'-R1' where id=b;
 insert into public.products(name,barcode,reference) values(prefix||' Blank',prefix||'-B4',' ');
 insert into public.products(name,barcode,reference) values(prefix||' Blank Two',prefix||'-B5',null);
 -- Archive must not free identifiers.
 update public.products set active=false where id=a;
 denied:=false;
 begin
  insert into public.products(name,barcode) values(prefix||' One',prefix||'-B6');
 exception when unique_violation then denied:=true;end;
 if not denied then raise exception 'ARCHIVED_DUPLICATE_ALLOWED';end if;
 -- Physical deletion frees just that product's keys.
 delete from public.products where id=b;
 insert into public.products(name,barcode,reference) values(prefix||' Reused',prefix||'-B2',prefix||'-R1');
 -- Historical duplicates still support price/photo edits, but no new claimant.
 select product_ids[1] into legacy from private.product_identity_claims where field='name' and cardinality(product_ids)>1 limit 1;
 if legacy is not null then
  update public.products set name=name,sale_price=sale_price where id=legacy;
  denied:=false;
  begin
   insert into public.products(name,barcode) select name,prefix||'-B7' from public.products where id=legacy;
  exception when unique_violation then denied:=true;end;
  if not denied then raise exception 'LEGACY_DUPLICATE_ALLOWED';end if;
 end if;
 -- Check role permissions and an authenticated write going through RLS+trigger.
 execute 'set local role authenticated';
 insert into public.products(name,barcode) values(prefix||' Auth',prefix||'-AUTH');
 denied:=false;
 begin
  insert into public.products(name,barcode) values(prefix||' Auth',prefix||'-AUTH2');
 exception when unique_violation then denied:=true;end;
 if not denied then raise exception 'AUTH_DUPLICATE_ALLOWED';end if;
 denied:=false;
 begin
  delete from private.product_identity_claims;
 exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'CLAIMS_WRITABLE';end if;
 execute 'reset role';
 if has_function_privilege('authenticated','private.guard_product_identity()','execute') then raise exception 'TRIGGER_DIRECT_EXECUTE';end if;
 -- Registry equals the current table, including after failed multi-field writes.
 select count(*) into n from (
  (select v.field,private.product_identity_key(v.value) k,p.id from public.products p cross join lateral (values ('name',p.name),('barcode',p.barcode),('reference',p.reference)) v(field,value) where private.product_identity_key(v.value) is not null
   except select field,identity_key,unnest(product_ids) from private.product_identity_claims)
  union all
  (select field,identity_key,unnest(product_ids) from private.product_identity_claims
   except select v.field,private.product_identity_key(v.value),p.id from public.products p cross join lateral (values ('name',p.name),('barcode',p.barcode),('reference',p.reference)) v(field,value) where private.product_identity_key(v.value) is not null)
 ) discrepancies;
 if n<>0 then raise exception 'REGISTRY_MISMATCH: %',n;end if;
end $$;
select 'product identity checks passed' as result;
