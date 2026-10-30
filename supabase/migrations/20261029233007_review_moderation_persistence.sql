-- Withdrawal still deletes the review text. Retain only the buyer/product
-- suppression decision so withdrawal cannot serve as moderator restoration.
create table private.commerce_review_suppressions(
 product_id uuid not null references public.products(id) on delete cascade,
 buyer_key text not null,primary key(product_id,buyer_key)
);
alter table private.commerce_review_suppressions enable row level security;
revoke all on private.commerce_review_suppressions from public,anon,authenticated,service_role;
insert into private.commerce_review_suppressions(product_id,buyer_key)
 select product_id,buyer_key from private.commerce_reviews where hidden;

create function private.commerce_review_suppression_sync() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.hidden then
  insert into private.commerce_review_suppressions(product_id,buyer_key) values(new.product_id,new.buyer_key) on conflict do nothing;
 else
  delete from private.commerce_review_suppressions where product_id=new.product_id and buyer_key=new.buyer_key;
 end if;
 return new;
end $$;
revoke all on function private.commerce_review_suppression_sync() from public,anon,authenticated,service_role;
create trigger commerce_review_suppression_sync after update of hidden on private.commerce_reviews
 for each row execute function private.commerce_review_suppression_sync();

do $audit$
declare src text;before_text text;
begin
 src:=pg_get_functiondef('storefront_api.gama_commerce_before_compliance(text,jsonb)'::regprocedure);
 before_text:='if oid is null then raise exception ''COMMERCE_PURCHASE_REQUIRED'';end if;';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:review_save_lock';end if;
 src:=replace(src,before_text,before_text||' perform pg_advisory_xact_lock(hashtextextended(''commerce-review:''||pid::text||'':''||buyer,0));');
 before_text:='insert into private.commerce_reviews(product_id,buyer_key,customer_id,created_by,order_id,rating,body) values(pid,buyer,cid,auth.uid(),oid,(p_data->>''rating'')::integer,btrim(p_data->>''body''))';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:review_save_suppression';end if;
 execute replace(src,before_text,'insert into private.commerce_reviews(product_id,buyer_key,customer_id,created_by,order_id,rating,body,hidden) values(pid,buyer,cid,auth.uid(),oid,(p_data->>''rating'')::integer,btrim(p_data->>''body''),exists(select 1 from private.commerce_review_suppressions s where s.product_id=pid and s.buyer_key=buyer))');
 src:=pg_get_functiondef('storefront_api.gama_commerce(text,jsonb)'::regprocedure);
 before_text:='if p_action=''review_delete'' then delete from private.commerce_reviews';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:review_delete_lock';end if;
 execute replace(src,before_text,'if p_action=''review_delete'' then perform pg_advisory_xact_lock(hashtextextended(''commerce-review:''||pid::text||'':''||buyer,0));delete from private.commerce_reviews');
 src:=pg_get_functiondef('private.gama_compliance_admin(text,jsonb)'::regprocedure);
 before_text:='update private.commerce_reviews set hidden=';
 if position(before_text in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:review_moderation_lock';end if;
 execute replace(src,before_text,$gate$perform pg_advisory_xact_lock(hashtextextended('commerce-review:'||v.product_id::text||':'||v.buyer_key,0)) from private.commerce_reviews v where v.id=(p_data->>'id')::uuid;
  update private.commerce_reviews set hidden=$gate$);
end $audit$;
notify pgrst,'reload schema';
