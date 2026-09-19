-- El módulo de Devoluciones sustituye al retorno que vivía enterrado en el
-- dossier del pedido. Se retiran sus seis acciones y sus lecturas: dos
-- sistemas para la misma noción es justo lo que había que evitar.
-- Las tablas antiguas estaban vacías, así que no se migra nada.
do $mig$
declare
 src text:=pg_get_functiondef('private.gama_fulfillment_action(text,jsonb)'::regprocedure);
 lines text[]; ln text; out text:=''; i int; state text:='';
 seen_actions boolean:=false; seen_photo boolean:=false; seen_reads int:=0;
begin
 select array_agg(line order by n) into lines
  from regexp_split_to_table(src,E'\n') with ordinality as t(line,n);

 for i in 1..array_length(lines,1) loop
  ln:=lines[i];

  if state='' and ln=' elsif p_action=''request_return'' then' then
   state:='actions';seen_actions:=true;
  end if;
  if state='actions' then
   if ln='  end if;eid:=rt.id;' then state:='';end if;
   continue;
  end if;

  if state='' and ln=' if p_action=''photo'' then' then state:='photo';seen_photo:=true;end if;
  if state='photo' then
   if ln=' end if;' then state:='';end if;
   continue;
  end if;

  if ln like '   ''returns'',coalesce(%' or ln like '   ''photos'',coalesce(%'
   or ln like '   ''credits'',case when role_name%customer_return_credits%' then
   seen_reads:=seen_reads+1;continue;
  end if;

  ln:=replace(ln,'rt public.customer_returns;','');
  ln:=replace(ln,'p_action not in (''dossier'',''photo'')','p_action<>''dossier''');
  ln:=replace(ln,',''receive_return'',''inspect_return''','');

  out:=out||ln||E'\n';
 end loop;

 if not seen_actions then raise exception 'ANCHOR_RETURN_ACTIONS';end if;
 if not seen_photo then raise exception 'ANCHOR_RETURN_PHOTO';end if;
 if seen_reads<>3 then raise exception 'ANCHOR_RETURN_READS_%',seen_reads;end if;
 if position('customer_return' in out)>0 then raise exception 'LEGACY_RETURN_LEFTOVER';end if;
 execute out;
end $mig$;
