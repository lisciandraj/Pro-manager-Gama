-- Expose deterministic Coco Intelligence results to the existing read-only AI catalog.
-- Keep the technical module id assistant-ia for backwards-compatible authorization.
create or replace function public.gama_coco_inventory_overview()
returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador'
 or exists(select 1 from public.app_modules where id='assistant-ia' and not enabled) then
  raise exception 'ADMIN_REQUIRED' using errcode='42501';
 end if;
 return jsonb_build_object(
  'calculated_at',(select max(calculated_at) from public.coco_inventory_intelligence),
  'products_analyzed',(select count(*) from public.coco_inventory_intelligence),
  'reorder_count',(select count(*) from public.coco_recommendations where module='inventory' and recommendation_type='reorder' and status='pending'),
  'critical_count',(select count(*) from public.coco_recommendations where module='inventory' and status='pending' and priority='critical'),
  'recommended_units',(select coalesce(sum(recommended_order_qty),0) from public.coco_inventory_intelligence),
  'recommendations',(select coalesce(jsonb_agg(x order by (x->>'priority') asc),'[]'::jsonb) from (
    select jsonb_build_object('id',r.id,'product_id',r.entity_id,'title',r.title,'priority',r.priority,'confidence',r.confidence,
      'current_value',r.current_value,'recommended_value',r.recommended_value,'reasoning',r.reasoning) x
    from public.coco_recommendations r where r.module='inventory' and r.status='pending' order by r.created_at desc limit 25
  ) q)
 );
end $$;
grant execute on function public.gama_coco_inventory_overview() to authenticated;
