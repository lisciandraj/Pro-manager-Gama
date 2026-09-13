-- External number is optional traceability metadata, not a fiscal-validation workflow.
alter table public.external_invoices drop constraint invoice_kind_integrity;
alter table public.external_invoices add constraint invoice_kind_integrity check(
 (document_kind='external' and issuer_ruc is not null and source_quote_id is null and external_number is null)
 or (document_kind='internal' and source_quote_id is not null and document_snapshot is not null and fiscal_status in ('unverified','cancelled'))
);
do $$ declare src text;a integer;b integer;begin
 select pg_get_functiondef('private.gama_internal_invoice_action(text,jsonb)'::regprocedure) into src;
 a:=position('elsif p_action=''link_external'' then' in src);
 b:=position('else raise exception ''INVALID_ACTION'';end if;' in src);
 if a=0 or b<a then raise exception 'Unexpected internal invoice function';end if;
 src:=left(src,a-1)||$branch$elsif p_action='link_external' then
  select order_id into oid from public.external_invoices where id=(p_data->>'invoice_id')::uuid;
  select * into o from public.sales_orders where id=oid for update;
  select * into i from public.external_invoices where id=(p_data->>'invoice_id')::uuid and document_kind='internal' for update;
  if not found then raise exception 'INVOICE_NOT_FOUND';end if;
  if i.fiscal_status='cancelled' then raise exception 'INVOICE_CLOSED';end if;
  if length(btrim(coalesce(p_data->>'number','')))>80 then raise exception 'INVALID_EXTERNAL_NUMBER';end if;
  insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(i.order_id,'internal_external_number',i.id,u,jsonb_build_object('previous_number',i.external_number,'number',nullif(btrim(p_data->>'number'),'')));
  update public.external_invoices set external_number=nullif(btrim(p_data->>'number'),''),updated_at=now() where id=i.id returning * into i;
 $branch$||substring(src from b);
 execute src;
end $$;
-- Keep historical external records; all new invoices must use accepted quotes.
create function private.gama_invoice_from_quote_only() returns trigger language plpgsql set search_path='' as $$
begin if new.document_kind<>'internal' then raise exception 'CREATE_INVOICE_FROM_QUOTE';end if;return new;end $$;
revoke all on function private.gama_invoice_from_quote_only() from public,anon,authenticated;
create trigger invoice_from_quote_only before insert on public.external_invoices for each row execute function private.gama_invoice_from_quote_only();
