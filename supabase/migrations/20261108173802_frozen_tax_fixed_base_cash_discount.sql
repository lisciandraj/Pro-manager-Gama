-- Cash discounts reduce the net-price share of frozen taxes. Fixed levies and
-- captured currency offsets remain constant, including in compounded bases.
-- Ordered coefficients require no current master, account or product lookup.
begin;
do $$declare s text;a text;b text;begin
 s:=pg_get_functiondef('private.coco_tax_calculate_frozen(jsonb,text)'::regprocedure);
 a:='private.coco_tax_number(r->''frozen_amount'')*case when kind=''percent'' then factor else 1 end';
 b:='case when kind=''percent'' then case when direction>=0 then greatest(0,private.coco_tax_number(r->''frozen_amount'')-(1-factor)*coalesce((r->>''frozen_net_tax'')::numeric,private.coco_tax_number(r->''frozen_amount'')-coalesce((r->>''frozen_fixed_base_tax'')::numeric,0))) else least(0,private.coco_tax_number(r->''frozen_amount'')-(1-factor)*coalesce((r->>''frozen_net_tax'')::numeric,private.coco_tax_number(r->''frozen_amount'')-coalesce((r->>''frozen_fixed_base_tax'')::numeric,0))) end else private.coco_tax_number(r->''frozen_amount'') end';
 if strpos(s,a)=0 then raise exception 'FROZEN_TAX_FIXED_BASE_AMOUNT_ANCHOR';end if;s:=replace(s,a,b);
 a:='base:=private.coco_tax_number(r->''frozen_base'')*factor;';
 b:='base:=private.coco_tax_number(r->''frozen_base'')-(1-factor)*coalesce((r->>''frozen_net_base'')::numeric,private.coco_tax_number(r->''frozen_base'')-coalesce((r->>''frozen_fixed_base'')::numeric,0));base:=case when direction>=0 then greatest(0,base) else least(0,base) end;';
 if strpos(s,a)=0 then raise exception 'FROZEN_TAX_FIXED_BASE_ANCHOR';end if;s:=replace(s,a,b);execute s;
end $$;
create or replace function private.coco_tax_scale_snapshot(p_calc jsonb,p_factor numeric,p_account uuid default null) returns jsonb language plpgsql immutable security invoker set search_path='' as $$
#variable_conflict use_column
declare ls jsonb:='[]';l jsonb;r jsonb;rules jsonb;coefficient numeric;net_base numeric;net_tax numeric;begin
 if p_calc->>'schema'<>'coco.tax.v1' or p_factor is null or p_factor::text in('NaN','Infinity','-Infinity') or abs(p_factor)>1 then raise exception 'TAX_SNAPSHOT_INVALID';end if;
 for l in select value from jsonb_array_elements(p_calc->'lines') loop
  rules:='[]';coefficient:=1;
  for r in select value from jsonb_array_elements(l->'taxes') order by coalesce((value->>'sequence')::integer,10),coalesce(value->>'id',value->>'code','') loop
   net_base:=coefficient*(l->>'subtotal')::numeric;net_tax:=case when r->>'calculation_type'='percent' then net_base*(r->>'rate')::numeric/100 else 0 end;
   rules:=rules||jsonb_build_array(r-'amount'-'base'-'amount_unrounded'-'base_unrounded'-'group_key'||jsonb_build_object('frozen_amount',(r->>'amount')::numeric*p_factor,'frozen_base',(r->>'base')::numeric*p_factor,'frozen_net_base',net_base*p_factor,'frozen_net_tax',net_tax*p_factor,'price_included',false));
   if coalesce((r->>'include_base_amount')::boolean,false) and r->>'calculation_type'='percent' then coefficient:=coefficient*(1+(r->>'rate')::numeric/100);end if;
  end loop;
  ls:=ls||jsonb_build_array(l||jsonb_build_object('source_line_id',coalesce(l->'source_line_id',l->'key'),'quantity',1,'tax_quantity',1,'unit_price',(l->>'subtotal')::numeric*p_factor,'entered_unit_price',(l->>'subtotal')::numeric*p_factor,'discount',0,'tax_base_factor',1,'force_price_excluded',true,'rules',rules,'account_id',coalesce(p_account::text,l->>'account_id')));
 end loop;
 return private.coco_tax_calculate_frozen(ls,'global')||jsonb_build_object('side',p_calc->'side','date',p_calc->'date','fiscal_position_id',p_calc->'fiscal_position_id');
end $$;
create or replace function private.coco_tax_recompute_snapshot(p_calculation jsonb,p_factor numeric) returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare lines jsonb:='[]';item jsonb;r jsonb;rules jsonb;coefficient numeric;net_base numeric;net_tax numeric;begin
 if p_calculation->>'schema'<>'coco.tax.v1' or p_factor is null or p_factor::text in('NaN','Infinity','-Infinity') or p_factor not between 0 and 1 then raise exception 'TAX_SNAPSHOT_INVALID';end if;
 for item in select value from jsonb_array_elements(p_calculation->'lines') loop
  rules:='[]';coefficient:=1;
  for r in select value from jsonb_array_elements(item->'rules') order by coalesce((value->>'sequence')::integer,10),coalesce(value->>'id',value->>'code','') loop
   if r ? 'frozen_amount' then
    net_base:=coefficient*(item->>'subtotal')::numeric;net_tax:=case when coalesce(r->>'calculation_type','percent')='percent' then net_base*(r->>'rate')::numeric/100 else 0 end;
    r:=r||jsonb_build_object('frozen_net_base',net_base,'frozen_net_tax',net_tax);
   end if;
   rules:=rules||jsonb_build_array(r);
   if coalesce((r->>'include_base_amount')::boolean,false) and coalesce(r->>'calculation_type','percent')='percent' then coefficient:=coefficient*(1+(r->>'rate')::numeric/100);end if;
  end loop;
  lines:=lines||jsonb_build_array(item||jsonb_build_object('rules',rules,'tax_base_factor',p_factor));
 end loop;
 return private.coco_tax_calculate_frozen(lines,p_calculation->>'rounding')||jsonb_build_object('fiscal_position_id',p_calculation->'fiscal_position_id','side',p_calculation->'side','date',p_calculation->'date');
end $$;
revoke all on function private.coco_tax_scale_snapshot(jsonb,numeric,uuid),private.coco_tax_recompute_snapshot(jsonb,numeric) from public,anon,authenticated,service_role;
commit;
