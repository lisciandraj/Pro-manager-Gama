-- Future documents resolve accounts product -> category -> company settings.
-- Existing ledger entries and frozen invoice snapshots are never rewritten.
create table private.accounting_product_accounts(
 id uuid primary key default gen_random_uuid(), target text not null check(target in('product','category')),
 product_id uuid references public.products(id) on delete restrict, category text,
 sale_account_id uuid references public.accounting_accounts(id) on delete restrict,
 purchase_account_id uuid references public.accounting_accounts(id) on delete restrict,
 version integer not null default 1 check(version>0), created_by uuid not null default auth.uid() references public.profiles(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check((target='product' and product_id is not null and category is null) or (target='category' and product_id is null and length(btrim(category)) between 1 and 200)),
 check(sale_account_id is not null or purchase_account_id is not null)
);
create unique index accounting_product_accounts_product on private.accounting_product_accounts(product_id) where target='product';
create unique index accounting_product_accounts_category on private.accounting_product_accounts(category) where target='category';
create index accounting_product_accounts_sale on private.accounting_product_accounts(sale_account_id);
create index accounting_product_accounts_purchase on private.accounting_product_accounts(purchase_account_id);
alter table private.accounting_product_accounts enable row level security;
revoke all on private.accounting_product_accounts from public,anon,authenticated,service_role;

create function private.coco_product_account(p_side text,p_product uuid) returns uuid
language plpgsql stable security definer set search_path='' as $$
declare cat text;aid uuid;family text;begin
 perform pg_advisory_xact_lock_shared(hashtextextended('product-accounts-configuration',0));
 family:=case when p_side in('sale','customer') then 'income' when p_side in('purchase','supplier') then 'expense' end;
 if family is null then raise exception 'ACCOUNT_SIDE_INVALID';end if;
 if p_product is not null then
  select category into cat from public.products where id=p_product;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  select case when family='income' then sale_account_id else purchase_account_id end into aid
   from private.accounting_product_accounts where target='product' and product_id=p_product;
  if aid is null and cat is not null then
   select case when family='income' then sale_account_id else purchase_account_id end into aid
    from private.accounting_product_accounts where target='category' and category=cat;
  end if;
 end if;
 if aid is null then select case when family='income' then sales_account_id else purchase_account_id end into aid from public.company_settings where id;end if;
 if aid is null or not exists(select 1 from public.accounting_accounts a where a.id=aid and a.active and a.type=family
  and not exists(select 1 from public.financial_accounts f where f.account_id=a.id)) then raise exception 'PRODUCT_ACCOUNT_INVALID';end if;
 return aid;
end $$;
revoke all on function private.coco_product_account(text,uuid) from public,anon,authenticated,service_role;

create function private.coco_product_accounts(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare rights jsonb:=private.gama_accounting_rights();kind text:=coalesce(p_data->>'target','product');
 search text:=left(btrim(coalesce(p_data->>'search','')),200);off integer:=greatest(coalesce((p_data->>'offset')::integer,0),0);
 item uuid:=nullif(p_data->>'product_id','')::uuid;cat text:=nullif(btrim(p_data->>'category'),'');
 current_row private.accounting_product_accounts;key uuid:=nullif(p_data->>'request_key','')::uuid;receipt private.command_receipts;
 sale uuid;purchase uuid;rid uuid;result jsonb;
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial'])
  or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'NOT_ALLOWED';end if;
 rights:=rights||jsonb_build_object('edit',coalesce((rights->>'edit')::boolean,false) and private.erp_action_allowed('accounting','edit'));
 if kind not in('product','category') then raise exception 'PRODUCT_ACCOUNT_TARGET_INVALID';end if;
 if p_action='context' then
  with items as(
   select p.id,p.name,p.reference,p.category from public.products p where kind='product'
   union all select null::uuid,p.category,null::text,p.category from public.products p where kind='category' and nullif(btrim(p.category),'') is not null group by p.category
   union select null::uuid,m.category,null::text,m.category from private.accounting_product_accounts m where kind='category' and m.target='category'
  ),filtered as(
   select i.*,case when i.id is null then i.category else i.id::text end target_key,m.id preference_id,m.version,m.sale_account_id,m.purchase_account_id,
    sa.code sale_code,sa.name sale_name,pa.code purchase_code,pa.name purchase_name,
    case when i.id is null then m.sale_account_id else coalesce(m.sale_account_id,cm.sale_account_id) end effective_sale_account_id,
    case when i.id is null then m.purchase_account_id else coalesce(m.purchase_account_id,cm.purchase_account_id) end effective_purchase_account_id
   from items i left join private.accounting_product_accounts m on m.target=kind and
    ((kind='product' and m.product_id=i.id) or(kind='category' and m.category=i.category))
   left join private.accounting_product_accounts cm on cm.target='category' and cm.category=i.category
   left join public.accounting_accounts sa on sa.id=m.sale_account_id
   left join public.accounting_accounts pa on pa.id=m.purchase_account_id
   where search='' or strpos(lower(concat_ws(' ',i.name,i.reference,i.category)),lower(search))>0
  ) select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(r) order by r.name,r.id) from(select * from filtered order by name,id limit 50 offset off)r),'[]'),
   'total',(select count(*) from filtered),'rights',rights,
   'chart',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'code',a.code,'name',a.name,'type',a.type,'active',a.active) order by a.code)
    from public.accounting_accounts a where a.type in('income','expense') and not exists(select 1 from public.financial_accounts f where f.account_id=a.id)),'[]'),
   'defaults',(select jsonb_build_object('sale_account_id',sales_account_id,'purchase_account_id',purchase_account_id) from public.company_settings where id)) into result;
  return result;
 end if;
 if p_action<>'save' then raise exception 'UNKNOWN_ACTION';end if;
 if not coalesce((rights->>'edit')::boolean,false) or not private.erp_action_allowed('accounting','edit') then raise exception 'NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('product-accounts-command:'||key::text,0));
 select * into receipt from private.command_receipts where domain='product-accounts' and request_key=key;
 if found then
  if receipt.actor_id<>auth.uid() or receipt.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;
  return receipt.result;
 end if;
 perform pg_advisory_xact_lock(hashtextextended('product-accounts-configuration',0));
 if kind='product' then
  if item is null or not exists(select 1 from public.products where id=item) then raise exception 'PRODUCT_NOT_FOUND';end if;
  cat:=null;
 else
  item:=null;
  if cat is null or not(exists(select 1 from public.products where category=cat) or exists(select 1 from private.accounting_product_accounts where target='category' and category=cat)) then raise exception 'PRODUCT_CATEGORY_NOT_FOUND';end if;
 end if;
 select * into current_row from private.accounting_product_accounts where target=kind and
  ((kind='product' and product_id=item) or(kind='category' and category=cat)) for update;
 if p_data ? 'version' and coalesce((p_data->>'version')::integer,0)<>coalesce(current_row.version,0) then raise exception 'PRODUCT_ACCOUNTS_CHANGED';end if;
 sale:=case when p_data ? 'sale_account_id' then nullif(p_data->>'sale_account_id','')::uuid else current_row.sale_account_id end;
 purchase:=case when p_data ? 'purchase_account_id' then nullif(p_data->>'purchase_account_id','')::uuid else current_row.purchase_account_id end;
 if sale is not null and not exists(select 1 from public.accounting_accounts a where a.id=sale and a.active and a.type='income' and not exists(select 1 from public.financial_accounts f where f.account_id=a.id)) then raise exception 'PRODUCT_ACCOUNT_INVALID';end if;
 if purchase is not null and not exists(select 1 from public.accounting_accounts a where a.id=purchase and a.active and a.type='expense' and not exists(select 1 from public.financial_accounts f where f.account_id=a.id)) then raise exception 'PRODUCT_ACCOUNT_INVALID';end if;
 if sale is null and purchase is null then
  rid:=current_row.id;
  if rid is not null then delete from private.accounting_product_accounts where id=rid;end if;
 elsif current_row.id is null then
  insert into private.accounting_product_accounts(target,product_id,category,sale_account_id,purchase_account_id)
   values(kind,item,cat,sale,purchase) returning id into rid;
 else
  update private.accounting_product_accounts set sale_account_id=sale,purchase_account_id=purchase,version=version+1,updated_at=now()
   where id=current_row.id returning id into rid;
 end if;
 result:=jsonb_build_object('id',rid,'ok',true,'version',(select version from private.accounting_product_accounts where id=rid));
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('product-accounts',key,auth.uid(),p_data,result);
 return result;
end $$;
create function public.coco_product_accounts(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.coco_product_accounts(p_action,p_data)$$;
revoke all on function public.coco_product_accounts(text,jsonb),private.coco_product_accounts(text,jsonb) from public,anon,service_role;
grant execute on function public.coco_product_accounts(text,jsonb),private.coco_product_accounts(text,jsonb) to authenticated;

insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column)
 values('accounting_product_accounts','accounting','Cuentas de producto y categoría','private','id');
create trigger coco_module_history after insert or update or delete on private.accounting_product_accounts
 for each row execute function private.coco_capture_module_event();
do $$begin
 execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),
  'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_product_accounts(');
end $$;
revoke all on function private.coco_history_record_visible_before_product_accounts(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_product_accounts(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid default null) returns boolean
language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='accounting_product_accounts' then return private.coco_module_allowed('accounting') and private.gama_accounting_may('view') and private.gama_accounting_rights()->>'scope'='all';end if;
 return private.coco_history_record_visible_before_product_accounts(p_table,p_id,p_owner);
end $$;
do $$declare s text;begin
 s:=pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure);
 s:=replace(s,'select case when','select case when p_table=''accounting_product_accounts'' then jsonb_build_object(''module'',''accounting'',''id'',p_id,''reference'',p_reference,''action'',''accounting_configuration'',''tab'',''products'') when');execute s;
end $$;
