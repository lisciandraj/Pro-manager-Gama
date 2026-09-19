do $patch$
declare src text;old text;
begin
 select pg_get_functiondef('private.gama_accounting_action4(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure) into src;
 old:=$q$  update public.accounting_periods set status='closed',closed_at=now(),closed_by=u where id=r.id;
  return jsonb_build_object('id',r.id,'status','closed');$q$;
 if position(old in src)=0 then raise exception 'Unexpected period close';end if;
 src:=replace(src,old,$q$  update public.accounting_periods set status='closed',closed_at=now(),closed_by=u where id=r.id;
  insert into public.gama_audit(table_name,row_id,action,actor_id,actor_role,new_data)
  values('accounting_periods',r.id::text,'CLOSE_PERIOD',u,private.current_user_role(),
   jsonb_build_object('period_start',r.period_start,'period_end',r.period_end));
  return jsonb_build_object('id',r.id,'status','closed');$q$);
 old:=$q$  values('accounting_periods',eid::text,'REOPEN',u,private.current_user_role(),jsonb_build_object('reason',reason));$q$;
 if position(old in src)=0 then raise exception 'Unexpected period reopen';end if;
 src:=replace(src,old,$q$  values('accounting_periods',eid::text,'REOPEN_PERIOD',u,private.current_user_role(),jsonb_build_object('reason',reason));$q$);
 execute src;
end $patch$;
select 'period-audit' as status;
