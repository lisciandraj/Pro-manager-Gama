-- Complete account metadata and isolate off-balance bookkeeping.
-- No account, document, amount or historical entry is rewritten.
create or replace function private.gama_account_family(p_type text) returns text
language sql immutable security invoker set search_path='' as $$
 select case
 when p_type in ('asset_receivable','asset_cash','asset_current','asset_non_current','asset_prepayments','asset_fixed') then 'asset'
 when p_type in ('liability_payable','liability_credit_card','liability_current','liability_non_current') then 'liability'
 when p_type in ('equity','equity_unaffected') then 'equity'
 when p_type in ('income','income_other') then 'income'
 when p_type in ('expense','expense_other','expense_depreciation','expense_direct_cost') then 'expense'
 when p_type='off_balance' then 'off_balance' end
$$;
revoke all on function private.gama_account_family(text) from public,anon,authenticated,service_role;

create function private.gama_off_balance_entry(p_entry uuid) returns void
language plpgsql security definer set search_path='' as $$
declare has_off boolean;has_regular boolean;has_tax boolean;has_cash boolean;begin
 select bool_or(a.type='off_balance'),bool_or(a.type<>'off_balance'),bool_or(l.tax_id is not null),bool_or(l.financial_account_id is not null)
 into has_off,has_regular,has_tax,has_cash
 from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id where l.entry_id=p_entry;
 if coalesce(has_off,false) then
  if has_regular then raise exception 'OFF_BALANCE_MIXED';end if;
  if has_tax then raise exception 'OFF_BALANCE_TAXES';end if;
  if has_cash or exists(select 1 from private.accounting_bank_bindings b join public.accounting_entry_lines l on l.id=b.line_id where l.entry_id=p_entry) then raise exception 'OFF_BALANCE_RECONCILIATION';end if;
 end if;
end $$;
revoke all on function private.gama_off_balance_entry(uuid) from public,anon,authenticated,service_role;

create function private.gama_off_balance_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare eid uuid;begin
 if tg_table_name='accounting_entries' then
  perform private.gama_off_balance_entry(new.id);
 elsif tg_table_name='accounting_entry_lines' then
  if tg_op<>'DELETE' then perform private.gama_off_balance_entry(new.entry_id);end if;
  if tg_op='DELETE' or (tg_op='UPDATE' and old.entry_id is distinct from new.entry_id) then perform private.gama_off_balance_entry(old.entry_id);end if;
 elsif tg_table_name='accounting_accounts' then
  for eid in select distinct entry_id from public.accounting_entry_lines where account_id=new.id loop perform private.gama_off_balance_entry(eid);end loop;
 else
  if tg_table_name='accounting_bank_bindings' then
   if exists(select 1 from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id where l.id=new.line_id and a.type='off_balance') then raise exception 'OFF_BALANCE_RECONCILIATION';end if;
  elsif tg_table_name='bank_match_sources' then
   if new.kind='ledger_entry' then eid:=new.source_id;end if;
  elsif tg_table_name='reconciliations' then
   if new.match_type in ('manual','ledger_entry') then eid:=new.match_id;end if;
  end if;
  if eid is not null and exists(select 1 from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id where l.entry_id=eid and a.type='off_balance') then raise exception 'OFF_BALANCE_RECONCILIATION';end if;
  return new;
 end if;
 return null;
end $$;
revoke all on function private.gama_off_balance_guard() from public,anon,authenticated,service_role;

-- Defer entry checks so a complete multi-line save remains atomic.
create constraint trigger accounting_off_balance_entry after insert or update on public.accounting_entries
 deferrable initially deferred for each row execute function private.gama_off_balance_guard();
create constraint trigger accounting_off_balance_lines after insert or update or delete on public.accounting_entry_lines
 deferrable initially deferred for each row execute function private.gama_off_balance_guard();
create constraint trigger accounting_off_balance_account after update on public.accounting_accounts
 deferrable initially deferred for each row when(old.type is distinct from new.type) execute function private.gama_off_balance_guard();
create trigger accounting_off_balance_binding before insert or update on private.accounting_bank_bindings
 for each row execute function private.gama_off_balance_guard();
create trigger accounting_off_balance_match before insert or update on public.bank_match_sources
 for each row execute function private.gama_off_balance_guard();
create trigger accounting_off_balance_reconciliation before insert or update on public.reconciliations
 for each row execute function private.gama_off_balance_guard();
