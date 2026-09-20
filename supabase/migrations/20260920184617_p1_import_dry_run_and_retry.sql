create table public.erp_import_batches(id uuid primary key default gen_random_uuid(),request_key uuid not null unique,kind text not null check(kind in ('products','clients','suppliers','customerPrices')),filename text not null,created_by uuid not null default auth.uid() references auth.users(id),created_at timestamptz not null default now(),status text not null default 'preview' check(status in ('preview','partial','completed')),source_rows jsonb not null);
create table public.erp_import_rows(id uuid primary key default gen_random_uuid(),batch_id uuid not null references public.erp_import_batches(id),row_number integer not null,data jsonb not null,status text not null check(status in ('ready','error','imported')),error text,result_id uuid,imported_at timestamptz,unique(batch_id,row_number));
do $$declare t text;begin foreach t in array array['erp_import_batches','erp_import_rows'] loop
 execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);execute format('create policy import_admin on public.%I for select to authenticated using(private.erp_module_allowed(''reports'',array[''administrador'']))',t);execute format('create trigger erp_audit_capture after insert or update or delete on public.%I for each row execute function private.erp_audit_capture()',t);end loop;end $$;
create function private.erp_import_row(p_kind text,p_row jsonb,p_dry boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;fields text[];tbl text;data jsonb:=p_row;columns text;values_sql text;cid uuid;pid uuid;n integer;begin
 if p_row ? '_errors' then raise exception '%',p_row->>'_errors';end if;
 if p_kind='customerPrices' then
  select count(*),(array_agg(id))[1] into n,cid from public.customers where active and ((nullif(p_row->>'customer_tax_id','') is not null and lower(identification)=lower(p_row->>'customer_tax_id')) or (nullif(p_row->>'customer_tax_id','') is null and lower(name)=lower(p_row->>'customer')));
  if n<>1 then raise exception 'CUSTOMER_UNKNOWN_OR_AMBIGUOUS';end if;
  select count(*),(array_agg(id))[1] into n,pid from public.products where active and ((nullif(p_row->>'reference','') is not null and lower(reference)=lower(p_row->>'reference')) or (nullif(p_row->>'reference','') is null and lower(barcode)=lower(p_row->>'barcode')));
  if n<>1 then raise exception 'PRODUCT_UNKNOWN_OR_AMBIGUOUS';end if;
  if p_row->>'unit_price' is null or (p_row->>'unit_price')::numeric<0 then raise exception 'PRICE_REQUIRED';end if;
  begin
   insert into public.customer_special_prices(customer_id,product_id,unit_price,contract_ref) values(cid,pid,(p_row->>'unit_price')::numeric,p_row->>'contract_ref') on conflict(customer_id,product_id) do update set unit_price=excluded.unit_price,contract_ref=excluded.contract_ref;
   if p_dry then raise exception using errcode='P0002',message='IMPORT_DRY_ROLLBACK';end if;
  exception when no_data_found then if sqlerrm<>'IMPORT_DRY_ROLLBACK' then raise;end if;end;
  return pid;
 end if;
 if length(btrim(coalesce(p_row->>'name','')))=0 then raise exception 'NAME_REQUIRED';end if;
 if p_kind='products' then tbl:='products';fields:=array['name','description','reference','barcode','category','family','lines','brand','presentation','location','stock','min_stock','max_stock','qty_per_carton','weight_g','volume_cm3','sale_price','sale_price_b','purchase_price','tax_rate'];
 elsif p_kind='clients' then tbl:='customers';fields:=array['name','identification','category','email','phone','address','city','province','notes'];data:=(data-'tax_id')||jsonb_build_object('identification',data->>'tax_id','category',upper(coalesce(nullif(data->>'category',''),'A')));if data->>'category' not in ('A','B','C') then raise exception 'INVALID_CUSTOMER_CATEGORY';end if;
 elsif p_kind='suppliers' then tbl:='suppliers';fields:=array['name','tax_id','email','phone','address','city','contact_name','notes'];
 else raise exception 'INVALID_IMPORT_KIND';end if;
 if p_kind in ('clients','suppliers') then
  execute format('select count(*) from public.%I where lower(btrim(name))=lower(btrim($1)) and lower(btrim(coalesce(address,'''')))=lower(btrim(coalesce($2,'''')))',tbl) into n using data->>'name',data->>'address';
  if n>0 then raise exception 'DUPLICATE_CONTACT';end if;
 end if;
 select string_agg(format('%I',key),',' order by key),string_agg(format('r.%I',key),',' order by key) into columns,values_sql from jsonb_object_keys(data) key where key=any(fields);
 begin
  execute format('insert into public.%I(%s) select %s from jsonb_populate_record(null::public.%I,$1) r returning id',tbl,columns,values_sql,tbl) into result using data;
  if p_dry then raise exception using errcode='P0002',message='IMPORT_DRY_ROLLBACK';end if;
 exception when no_data_found then if sqlerrm<>'IMPORT_DRY_ROLLBACK' then raise;end if;end;
 return result;
end $$;
revoke all on function private.erp_import_row(text,jsonb,boolean) from public,anon,authenticated;
create function private.gama_import_batch(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.erp_import_batches;r public.erp_import_rows;x jsonb;rowno integer:=1;error text;rid uuid;k text;seen text[]:='{}';begin
 if auth.uid() is null or not private.erp_module_allowed('reports',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='prepare' then
  if nullif(p_data->>'request_key','') is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('import:'||(p_data->>'request_key'),0));
  select * into b from public.erp_import_batches where request_key=(p_data->>'request_key')::uuid;
  if found then if b.created_by<>auth.uid() or b.source_rows<>p_data->'rows' or b.kind<>p_data->>'kind' then raise exception 'REQUEST_KEY_REUSED';end if;
  else
   if jsonb_typeof(p_data->'rows') is distinct from 'array' or jsonb_array_length(p_data->'rows') not between 1 and 2000 then raise exception 'IMPORT_LIMIT_2000_ROWS';end if;
   insert into public.erp_import_batches(request_key,kind,filename,source_rows) values((p_data->>'request_key')::uuid,p_data->>'kind',coalesce(p_data->>'filename','Import'),p_data->'rows') returning * into b;
   for x in select value from jsonb_array_elements(b.source_rows) loop
    rowno:=rowno+1;error:=null;
    k:=case b.kind when 'products' then lower(coalesce(nullif(x->>'barcode',''),nullif(x->>'reference',''),x->>'name')) when 'customerPrices' then lower(coalesce(nullif(x->>'customer_tax_id',''),x->>'customer'))||'|'||lower(coalesce(nullif(x->>'reference',''),x->>'barcode')) else lower(btrim(x->>'name'))||'|'||lower(btrim(coalesce(x->>'address',''))) end;
    begin
     if k=any(seen) then raise exception 'DUPLICATE_IN_FILE';end if;perform private.erp_import_row(b.kind,x,true);
    exception when others then error:=sqlerrm;end;
    seen:=array_append(seen,k);
    insert into public.erp_import_rows(batch_id,row_number,data,status,error) values(b.id,rowno,x,case when error is null then 'ready' else 'error' end,error);
   end loop;
  end if;
 elsif p_action in ('apply','detail') then
  select * into b from public.erp_import_batches where id=(p_data->>'id')::uuid for update;if not found then raise exception 'IMPORT_NOT_FOUND';end if;
  if p_action='apply' then
   for r in select ir.* from public.erp_import_rows ir where ir.batch_id=b.id and ir.status<>'imported' and ir.error is distinct from 'DUPLICATE_IN_FILE' order by row_number for update loop
    begin
     rid:=private.erp_import_row(b.kind,r.data,false);
     update public.erp_import_rows set status='imported',error=null,result_id=rid,imported_at=now() where id=r.id;
    exception when others then update public.erp_import_rows set status='error',error=sqlerrm where id=r.id;end;
   end loop;
   update public.erp_import_batches set status=case when exists(select 1 from public.erp_import_rows where batch_id=b.id and status<>'imported') then 'partial' else 'completed' end where id=b.id returning * into b;
  end if;
 else raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('batch',to_jsonb(b)-'source_rows','rows',(select jsonb_agg(to_jsonb(ir) order by ir.row_number) from public.erp_import_rows ir where ir.batch_id=b.id));
end $$;
revoke all on function private.gama_import_batch(text,jsonb) from public,anon;grant execute on function private.gama_import_batch(text,jsonb) to authenticated;
create function public.gama_import_batch(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_import_batch(p_action,p_data)$$;
revoke all on function public.gama_import_batch(text,jsonb) from public,anon;grant execute on function public.gama_import_batch(text,jsonb) to authenticated;
