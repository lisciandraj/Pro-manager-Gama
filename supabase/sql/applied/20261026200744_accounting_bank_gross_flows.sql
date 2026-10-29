-- Keep the real gross bank movements when a same-day group nets to zero.
-- No historical posting or source record is rewritten.
do $$declare s text;a text;b text;begin
 s:=pg_get_functiondef('private.gama_payment_mode_settle(uuid)'::regprocedure);
 a:='lines jsonb;eid uuid;first_entry uuid;cash numeric;bank_account uuid;begin';
 if position(a in s)=0 then raise exception 'BANK_GROSS_DECLARATION_ANCHOR';end if;
 s:=replace(s,a,'lines jsonb;eid uuid;first_entry uuid;cash numeric;bank_account uuid;bank_part record;begin');
 a:=$a$if cash<>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',bank_account,'financial_account_id',g.financial_account_id,'debit',greatest(cash,0),'credit',greatest(-cash,0),'label','Liquidación bancaria · '||item.value_date));end if;$a$;
 b:=$b$for bank_part in
   select a.bank_id,b.reference,sum(a.amount) amount
   from private.accounting_match_allocations a join public.bank_transactions b on b.id=a.bank_id
   join private.accounting_payment_treatments pm on pm.source_type=a.kind and pm.source_id=a.source_id and pm.mode in('none','outstanding')
   where a.group_id=g.id and b.value_date=item.value_date
   group by a.bank_id,b.reference having sum(a.amount)<>0 order by a.bank_id
  loop
   lines:=lines||jsonb_build_array(jsonb_build_object('account_id',bank_account,'financial_account_id',g.financial_account_id,'debit',greatest(bank_part.amount,0),'credit',greatest(-bank_part.amount,0),'label','Liquidación bancaria · '||coalesce(nullif(bank_part.reference,''),bank_part.bank_id::text)));
  end loop;$b$;
 if position(a in s)=0 then raise exception 'BANK_GROSS_POSTING_ANCHOR';end if;execute replace(s,a,b);
end $$;
