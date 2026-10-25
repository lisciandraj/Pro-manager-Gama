-- Keep grouped trial-balance totals and exports within the selected subtree.
do $$declare s text;old_totals text;new_totals text;old_groups text;new_groups text;begin
 s:=pg_get_functiondef('private.gama_accounting_configuration(text,jsonb)'::regprocedure);
 old_totals:='''debit'',coalesce((select sum(debit) from amounts),0),''credit'',coalesce((select sum(credit) from amounts),0)';
 new_totals:='''debit'',coalesce((select sum(debit) from selected),0),''credit'',coalesce((select sum(credit) from selected),0)';
 old_groups:='from private.accounting_groups g left join tree t on t.ancestor=g.id left join amounts a on a.group_id=t.descendant group by g.id';
 new_groups:='from private.accounting_groups g left join tree t on t.ancestor=g.id left join amounts a on a.group_id=t.descendant
    where nullif(p_data->>''group_id'','''') is null or exists(select 1 from tree selected_tree where selected_tree.ancestor=(p_data->>''group_id'')::uuid and selected_tree.descendant=g.id)
    group by g.id';
 if strpos(s,old_totals)=0 or strpos(s,old_groups)=0 then raise exception 'GROUP_FILTER_ANCHOR_MISSING';end if;
 execute replace(replace(s,old_totals,new_totals),old_groups,new_groups);
end $$;
