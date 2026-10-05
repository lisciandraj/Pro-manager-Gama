-- Prepare a reviewed retention regardless of the order in which the invoice,
-- fiscal review and supplier policy become available. Never emit from a trigger.
create function private.gama_sri_try_purchase(p_invoice uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.sri_purchase_queue q
  join public.supplier_invoices v on v.id=q.supplier_invoice_id
  where q.supplier_invoice_id=p_invoice and q.issue_id is null and v.status='posted')
  or not exists(select 1 from public.company_settings c
   join public.accounting_ec_profile p on p.id=c.id
   where c.country='EC' and p.withholding_agent and p.confirmed_on is not null)
 then return;end if;
 begin
  perform private.gama_sri_purchase_document(p_invoice,'07','{}');
 exception when others then
  update public.sri_purchase_queue
  set last_error=case when sqlerrm ~ '^[A-Z0-9_]{1,100}$' then sqlerrm else 'SRI_PURCHASE_FISCAL_REVIEW_REQUIRED' end
  where supplier_invoice_id=p_invoice and issue_id is null;
 end;
end $$;
revoke all on function private.gama_sri_try_purchase(uuid) from public,anon,authenticated;

create or replace function private.gama_sri_purchase_queued() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.status='posted' and (tg_op='INSERT' or old.status is distinct from new.status)
  and exists(select 1 from public.company_settings c join public.accounting_ec_profile p on p.id=c.id
   where c.country='EC' and p.withholding_agent and p.confirmed_on is not null)
 then
  insert into public.sri_purchase_queue(supplier_invoice_id) values(new.id) on conflict do nothing;
  perform private.gama_sri_try_purchase(new.id);
 end if;
 return new;
end $$;
revoke all on function private.gama_sri_purchase_queued() from public,anon,authenticated;

create or replace function private.gama_sri_purchase_reviewed() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.source_type='supplier_invoice' then perform private.gama_sri_try_purchase(new.source_id);end if;
 return new;
end $$;
revoke all on function private.gama_sri_purchase_reviewed() from public,anon,authenticated;

create function private.gama_sri_supplier_policy_reviewed() returns trigger
language plpgsql security definer set search_path='' as $$
declare invoice uuid;
begin
 -- Keep a policy save bounded; the existing preparation list handles a larger
 -- historical backlog. Every subsequent invoice/fiscal review is handled alone.
 for invoice in select q.supplier_invoice_id from public.sri_purchase_queue q
  join public.supplier_invoices v on v.id=q.supplier_invoice_id
  where v.supplier_id=new.supplier_id and v.status='posted' and q.issue_id is null
  order by q.created_at,q.supplier_invoice_id limit 50
 loop perform private.gama_sri_try_purchase(invoice);end loop;
 return new;
end $$;
revoke all on function private.gama_sri_supplier_policy_reviewed() from public,anon,authenticated;
create trigger sri_supplier_policy_reviewed after insert or update on public.supplier_withholding_policies
for each row execute function private.gama_sri_supplier_policy_reviewed();
create index sri_purchase_waiting on public.sri_purchase_queue(created_at,supplier_invoice_id) where issue_id is null;
notify pgrst, 'reload schema';
