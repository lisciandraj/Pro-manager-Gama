lock table public.products, public.stock_movements, public.invoice_lines, public.commercial_matrix, public.purchase_order_lines, public.favorite_order_lines, public.inventory_count_lines, public.customer_request_lines, public.reorder_rules, public.customer_special_prices, public.crm_opportunity_lines, public.stock_quants, public.stock_reservations, public.sales_order_lines in share row exclusive mode;
create table if not exists private.product_dedup_archive (
 batch_id uuid not null,
 removed_product_id uuid not null,
 kept_product_id uuid not null,
 removed_score integer not null,
 kept_score integer not null,
 removed_snapshot jsonb not null,
 kept_snapshot jsonb not null,
 removed_at timestamptz not null default now(),
 primary key (batch_id,removed_product_id)
);
alter table private.product_dedup_archive enable row level security;
revoke all on private.product_dedup_archive from public,anon,authenticated;
create temporary table dedup_ranked on commit drop as
with recursive edges as (
 select a.id src,b.id dst from public.products a join public.products b on a.id<>b.id and (
 private.product_identity_key(a.name)=private.product_identity_key(b.name) or
 private.product_identity_key(a.reference)=private.product_identity_key(b.reference) or
 private.product_identity_key(a.barcode)=private.product_identity_key(b.barcode))
), reach(src,dst) as (
 select src,dst from edges union select r.src,e.dst from reach r join edges e on e.src=r.dst
), members as (
 select p.id,least(p.id::text,min(r.dst::text)) grp from public.products p join reach r on r.src=p.id group by p.id
), scored as (
 select p.id,m.grp,p.name,p.reference,p.barcode,p.active,p.has_photo,p.created_at,
 (select count(*) from jsonb_each(to_jsonb(p)-array['id','created_at','updated_at','stock','active','has_photo','tax_rate']) v where v.value<>'null'::jsonb and btrim(v.value#>>'{}')<>'' and v.value<>'0'::jsonb) score
 from public.products p join members m on m.id=p.id
), ranked as (select *,row_number() over(partition by grp order by score desc,active desc,has_photo desc,created_at,id) rn from scored)
select * from ranked;
do $$
declare n integer; total_before integer; stock_before numeric; batch uuid:=gen_random_uuid(); t text;
begin
 select count(*) into n from dedup_ranked where rn>1;
 if n<>312 or (select count(*) from dedup_ranked where rn=1)<>165 then
  raise exception 'Catalogue changed: expected 312 deletions in 165 groups, got %',n;
 end if;
 if exists(select 1 from public.products p join dedup_ranked r on r.id=p.id where r.rn>1 and coalesce(p.stock,0)<>0) then raise exception 'A discarded product has stock';end if;
 foreach t in array array['stock_movements','invoice_lines','commercial_matrix','purchase_order_lines','favorite_order_lines','inventory_count_lines','customer_request_lines','reorder_rules','customer_special_prices','crm_opportunity_lines','stock_quants','stock_reservations','sales_order_lines'] loop
  execute format('select count(*) from public.%I x join dedup_ranked r on r.id=x.product_id where r.rn>1',t) into n;
  if n<>0 then raise exception 'A discarded product has related rows in %',t;end if;
 end loop;
 select count(*),coalesce(sum(stock),0) into total_before,stock_before from public.products;
 insert into private.product_dedup_archive(batch_id,removed_product_id,kept_product_id,removed_score,kept_score,removed_snapshot,kept_snapshot)
 select batch,d.id,k.id,d.score,k.score,to_jsonb(p),to_jsonb(w)
 from dedup_ranked d join dedup_ranked k on k.grp=d.grp and k.rn=1
 join public.products p on p.id=d.id join public.products w on w.id=k.id where d.rn>1;
 delete from public.products p using dedup_ranked d where p.id=d.id and d.rn>1;
 get diagnostics n=row_count;
 if n<>312 then raise exception 'Wrong number deleted: %',n;end if;
 if (select count(*) from public.products)<>total_before-312 or (select coalesce(sum(stock),0) from public.products)<>stock_before then raise exception 'Count or stock changed unexpectedly';end if;
 if exists(select 1 from public.products p cross join lateral (values('name',p.name),('reference',p.reference),('barcode',p.barcode)) v(field,value)
 where private.product_identity_key(v.value) is not null group by v.field,private.product_identity_key(v.value) having count(*)>1) then raise exception 'Duplicates remain';end if;
 if exists(select 1 from private.product_identity_claims c where cardinality(c.product_ids)>1) then raise exception 'Registry duplicates remain';end if;
 if exists(select 1 from private.product_dedup_archive a join public.products p on p.id=a.kept_product_id where a.batch_id=batch and to_jsonb(p)<>a.kept_snapshot) then raise exception 'A retained product changed';end if;
end $$;
select count(*) as products_remaining,(select count(*) from private.product_dedup_archive) as archived_duplicates from public.products;
