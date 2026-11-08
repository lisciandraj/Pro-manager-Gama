-- GAMA public website: catalogue isolation, versioned consumer information and
-- fail-closed new commercial intake. No company values, tax rates, accepted
-- historical documents or retention approvals are fabricated or rewritten.
begin;

create function private.gama_b2b_product_visible(p_customer uuid,p_product uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.products p
  join private.website_products w on w.product_id=p.id and w.public_visible
  where p.id=p_product and p.active and p.product_kind='goods'
   and private.commerce_product_allowed(p_customer,p.id)
   and exists(select 1 from private.website_public_settings s where s.id and coalesce((s.config->>'site_enabled')::boolean,false))
 )
$$;
revoke all on function private.gama_b2b_product_visible(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function private.gama_b2b_product_favorites(p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 cid uuid:=private.gama_b2b_customer();
 pid uuid;
 off integer:=coalesce((p_data->>'offset')::integer,0);
 term text:=left(btrim(coalesce(p_data->>'search','')),100);
 wanted boolean;
 cnt integer;
 rows jsonb;
begin
 -- The resolver checks auth.uid(), MFA, verified account, current membership,
 -- active customer and the website module on EVERY read and write.
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA';end if;
 if off<0 or off>1000000 then raise exception 'INVALID_OFFSET';end if;
 if p_action='ids' then
  return coalesce((select jsonb_agg(f.product_id order by f.product_id)
   from private.b2b_product_favorites f where f.customer_id=cid and private.gama_b2b_product_visible(cid,f.product_id)),'[]'::jsonb);
 end if;
 if p_action='list' then
  with filtered as (
   select p.id,p.name,p.reference,p.category,p.tax_rate,p.order_minimum,p.order_multiple,
    (p.active and p.product_kind='goods') active,
    (p.has_photo and p.active and p.product_kind='goods') has_photo,
    p.photo_is_illustrative,f.created_at
   from private.b2b_product_favorites f join public.products p on p.id=f.product_id
   where f.customer_id=cid and private.gama_b2b_product_visible(cid,p.id) and (term='' or p.name ilike '%'||term||'%'
    or p.reference ilike '%'||term||'%' or p.barcode ilike '%'||term||'%')
  ), limited as (select * from filtered order by created_at desc,id limit 30 offset off)
  select (select count(*) from filtered),coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object(
   'unit_price',case when l.active then private.erp_price_calculate(cid,l.id,
    ceil(greatest(1,l.order_minimum)/l.order_multiple)*l.order_multiple,null)->'unit_price' else null end
   ) order by l.created_at desc,l.id),'[]'::jsonb) into cnt,rows from limited l;
  return jsonb_build_object('total',cnt,'items',rows);
 end if;
 if p_action='set' then
  pid:=nullif(p_data->>'product_id','')::uuid;
  if pid is null or jsonb_typeof(p_data->'favorite') is distinct from 'boolean' then raise exception 'INVALID_DATA';end if;
  wanted:=(p_data->>'favorite')::boolean;
  -- Serialize updates for one customer, including the bounded-list check.
  perform pg_advisory_xact_lock(hashtextextended('b2b-product-favorites:'||cid::text,0));
  if wanted then
   if not private.gama_b2b_product_visible(cid,pid) then raise exception 'PRODUCT_NOT_FOUND';end if;
   -- Revoked catalogue references are hidden from every client read. Remove
   -- those stale preferences under the same customer lock before enforcing the
   -- storage cap, so an invisible full list cannot block a new allowed favorite.
   delete from private.b2b_product_favorites f
    where f.customer_id=cid and not private.gama_b2b_product_visible(cid,f.product_id);
   if not exists(select 1 from private.b2b_product_favorites f where f.customer_id=cid and f.product_id=pid)
    and (select count(*) from private.b2b_product_favorites f where f.customer_id=cid)>=500 then raise exception 'B2B_PRODUCT_FAVORITE_LIMIT';end if;
   insert into private.b2b_product_favorites(customer_id,product_id) values(cid,pid) on conflict do nothing;
  else
   -- Unavailable products can still be removed. Retrying either state is safe.
   delete from private.b2b_product_favorites f where f.customer_id=cid and f.product_id=pid;
  end if;
  return jsonb_build_object('product_id',pid,'favorite',wanted);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
-- Harden the original photo implementation without adding a callable predecessor
-- or changing its OID. Every outer B2B wrapper already derives the current company.
do $photo_guard$
declare body text;before_guard text;after_guard text;before_photo text;after_photo text;
begin
 select pg_get_functiondef('private.gama_b2b_action_before_documents(text,jsonb)'::regprocedure) into body;
 before_guard:='if not exists(select 1 from public.products p where p.id=v_id and p.active and p.product_kind=''goods'') then raise exception ''PRODUCT_NOT_FOUND'';end if;';
 after_guard:='if not private.gama_b2b_product_visible(cid,v_id) then raise exception ''PRODUCT_NOT_FOUND'';end if;';
 if (length(body)-length(replace(body,before_guard,'')))/length(before_guard)<>1 then
  raise exception 'B2B_PHOTO_VISIBILITY_ANCHOR';
 end if;
 body:=replace(body,before_guard,after_guard);
 -- product_photos is no longer part of the active schema. Read the canonical
 -- photo data and preserve the response contract and illustration notice.
 before_photo:='return jsonb_build_object(''photo'',(select ph.photo from public.product_photos ph where ph.product_id=v_id));';
 after_photo:='return (select jsonb_build_object(''photo'',case when p.photo_data ~ ''^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$'' then p.photo_data end,''photo_is_illustrative'',p.photo_is_illustrative) from public.products p where p.id=v_id);';
 if (length(body)-length(replace(body,before_photo,'')))/length(before_photo)<>1 then
  raise exception 'B2B_PHOTO_DATA_ANCHOR';
 end if;
 execute replace(body,before_photo,after_photo);
end $photo_guard$;

create or replace function private.commerce_policy_templates() returns jsonb
language sql immutable set search_path='' as $templates$ select '{"revision":"2026-11-08.1","templates":{"privacy":"Información de privacidad\n\nQué datos tratamos\nDatos de contacto, identificación y dirección de facturación cuando solicitas un pedido, productos, cantidades, historial comercial y decisiones de aprobación. También tratamos el contenido y el seguimiento de las solicitudes de privacidad, devoluciones, garantías y reclamaciones. Las encuestas voluntarias recogen las respuestas solicitadas en cada cuestionario. La infraestructura trata datos técnicos de conexión para mantener el servicio y prevenir abusos. No introduzcas datos de tarjeta en los formularios.\n\nFinalidades y bases\nAtender tu solicitud y ejecutar las medidas precontractuales que pides; gestionar la relación contractual y cumplir las obligaciones de facturación, contabilidad y protección del consumidor. La seguridad se basa en el interés legítimo de proteger el servicio, sujeto a la evaluación correspondiente. Leer esta información no equivale a suscribirse a publicidad. No se activa marketing por comprar ni por tener una cuenta. Las respuestas a encuestas voluntarias se tratan para la finalidad indicada en cada cuestionario, con el consentimiento específico que se solicita allí. Participar en una encuesta no activa publicidad ni marketing.\n\nDestinatarios\nPersonal autorizado de GAMA y proveedores necesarios de infraestructura, principalmente Cloudflare y Supabase. La base está alojada en Irlanda. El acceso de un proveedor por cuenta de GAMA debe estar cubierto por un contrato de encargo; otras comunicaciones internacionales requieren la garantía que corresponda. Un clic en WhatsApp abre un servicio externo con sus propias condiciones.\n\nConservación\nLos datos se conservan durante la atención de la solicitud y la relación contractual, y después por los plazos legales aplicables o la defensa de reclamaciones. Los comprobantes electrónicos se conservan durante siete años cuando corresponda conforme al SRI. La selección y los comprobantes sin cuenta de esta pestaña se eliminan al borrar su almacenamiento de sesión. GAMA debe aplicar un calendario de conservación a los demás registros.\n\nTus derechos\nPuedes solicitar acceso, rectificación, actualización, eliminación, oposición, portabilidad, suspensión y los demás derechos aplicables, y retirar un consentimiento opcional, mediante {{contact}}. La identidad se verifica de forma proporcional. GAMA debe responder dentro del plazo legal aplicable; la eliminación puede estar limitada por obligaciones legales de conservación. Puedes reclamar ante la Superintendencia de Protección de Datos Personales: https://www.spdp.gob.ec/.\n\nCampos obligatorios\nLos datos marcados con * son necesarios para atender la solicitud o preparar la facturación. Sin ellos no se puede completar el trámite. Las opiniones son opcionales: su texto, valoración y fecha se publican como Compra verificada. No se toman decisiones de aprobación de compras mediante perfiles automatizados: las valida una persona autorizada.","terms":"Condiciones de solicitudes y pedidos\n\nPrecios y revisión\nLos precios públicos incluyen el IVA del producto. Las cuentas de empresa ven su precio negociado sin IVA y un equivalente con IVA incluido; la revisión de la selección muestra los impuestos y el total de productos. Todas las cantidades, precios y permisos se comprueban de nuevo al enviar.\n\nConfirmación\nEnviar una solicitud de cotización o un pedido sin cuenta no confirma una compra, no reserva existencias y no produce un cargo. GAMA debe confirmar por escrito disponibilidad, precio final, costo y plazo de entrega y medio de pago antes de aceptar el pedido. El envío no se presume gratuito ni incluido. Puedes corregir la selección antes de enviarla.\n\nCompras de empresa\nLos solicitantes sujetos a aprobación no pueden aceptar directamente una compra. Las modificaciones de artículos o cantidades reinician las validaciones. Copiar un pedido prepara una nueva selección a precios actuales; no repite un pago.\n\nPago y facturación\nEl pago en línea no está habilitado hasta disponer de un prestador y cuenta comercial configurados. No guardamos datos de tarjeta en este sitio. La referencia del pedido y los presupuestos son documentos comerciales; la factura fiscal debe emitirse y autorizarse mediante el proceso tributario aplicable.\n\nEstas condiciones no limitan los derechos legales del consumidor.","delivery":"Entregas, devoluciones, cambios y garantías\n\nGAMA confirma por escrito la dirección, cobertura, disponibilidad, costo, plazo de entrega y consecuencias de un retraso antes de la aceptación definitiva. Una fecha solicitada no es una promesa de entrega.\n\nEl artículo 45 de la Ley Orgánica de Defensa del Consumidor reconoce el derecho de devolución o cambio en el término de quince días posteriores a la recepción del bien o servicio, siempre que lo permita su naturaleza y el estado del bien sea el mismo en el que se recibió. En los servicios, la devolución se ejerce mediante la cesación inmediata del contrato de provisión del servicio. Cuando corresponda devolver el valor pagado, no se sustituirá por notas de crédito, bienes ni servicios compensatorios.\n\nContacta con {{contact}} indicando la referencia y los productos para ejercer este derecho o solicitar atención por un defecto. Las garantías legales y los remedios por productos defectuosos se mantienen, sin perjuicio de la garantía comercial aplicable. No se exige una renuncia a derechos legales por tratarse de una compra desde una cuenta de empresa.\n\nLas condiciones particulares de transporte, devolución, cambio y garantía se comunicarán antes de confirmar la compra.","storage":"Cookies y almacenamiento\n\nLa selección, la sesión de empresa y los comprobantes de pedidos sin cuenta se guardan en el almacenamiento de sesión de esta pestaña. Las preferencias de cookies se conservan localmente hasta que las elimines. Los comprobantes no contienen datos de facturación en el almacenamiento del navegador. No se guardan los datos de facturación en el navegador.\n\nCloudflare Turnstile procesa señales técnicas para prevenir envíos automatizados. Es una función de seguridad y no una autorización para publicidad.\n\nNo se activan cookies publicitarias, píxeles ni analítica de comportamiento. Si se incorporan finalidades opcionales, deberán permanecer bloqueadas hasta obtener un consentimiento válido y permitir su retirada. Usa Preferencias de cookies en el pie de página. Borrar el almacenamiento o cerrar sesión puede eliminar la selección o el acceso a comprobantes de esta pestaña.","notice":"Este sitio es operado por la entidad indicada arriba. Las solicitudes de cotización y de pedido no confirman una compra ni reservan existencias. El pedido definitivo requiere acordar disponibilidad, precio, IVA, entrega y pago."}}'::jsonb $templates$;
revoke all on function private.commerce_policy_templates() from public,anon,authenticated;

create function private.commerce_missing_public_information() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(k order by k),'[]'::jsonb)
 from unnest(array['legal_name','legal_tax_id','legal_address','privacy_email',
  'privacy_retention','privacy_recipients','privacy_rights_process']) k
 where not exists(select 1 from private.website_public_settings s
  where s.id and length(btrim(coalesce(s.config->>k,'')))>0)
$$;
revoke all on function private.commerce_missing_public_information() from public,anon,authenticated,service_role;
alter table private.website_public_inquiries add column policy_snapshot jsonb;

-- Guest checkout already validates its policy version; retain it when it calls
-- the shared quote intake instead of stripping the information it just checked.
do $checkout_policy$
declare body text;anchor text:='array[''billing'',''price_hash'',''terms_accepted'',''policy_version'']';
begin
 select pg_get_functiondef('storefront_api.gama_commerce_before_compliance(text,jsonb)'::regprocedure) into body;
 if (length(body)-length(replace(body,anchor,'')))/length(anchor)<>1 then raise exception 'COMPLIANCE_CHECKOUT_POLICY_ANCHOR';end if;
 execute replace(body,anchor,'array[''billing'',''price_hash'',''terms_accepted'']');
end $checkout_policy$;

-- Preserve the RPC OID and its existing ACLs; no predecessor becomes callable.
create or replace function storefront_api.gama_storefront(p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;bundle jsonb;is_new boolean:=false;key_id uuid;
begin
 if p_action='submit' then
  perform private.commerce_guest_guard();
  key_id:=nullif(p_data->>'request_key','')::uuid;
  if key_id is null then raise exception 'WEBSITE_INVALID_DATA';end if;
  perform pg_advisory_xact_lock(hashtextextended('public-web:'||key_id,0));
  is_new:=not exists(select 1 from private.website_public_inquiries where request_key=key_id);
  if is_new then
   if jsonb_array_length(private.commerce_missing_public_information())>0 then raise exception 'WEBSITE_LEGAL_INFORMATION_REQUIRED';end if;
   bundle:=private.commerce_policy_bundle();
   if p_data->>'policy_version' is distinct from bundle->>'version' then raise exception 'COMMERCE_POLICY_CHANGED';end if;
   -- Email and daily counters are shared across visitors: serialize their
   -- check-and-insert path as well as the existing request/visitor locks.
   perform pg_advisory_xact_lock(hashtextextended('public-web-quota',0));
  end if;
 end if;
 r:=storefront_api.gama_storefront_before_compliance(p_action,p_data);
 if p_action='submit' and is_new then
  update private.website_public_inquiries set policy_snapshot=bundle where request_key=key_id;
 end if;
 if p_action='bootstrap' then
  r:=r||jsonb_build_object('policies',private.commerce_policy_bundle(),
   'collection_ready',jsonb_array_length(private.commerce_missing_public_information())=0);
  if r->>'paused'='false' then r:=jsonb_set(r,'{settings}',private.commerce_config_defaults(r->'settings'));end if;
 end if;
 return r;
end $$;

-- Checkout calls the canonical storefront submit in the same transaction: the
-- guard above also applies to new guest orders and rolls back on failure.
-- Support/rights intake, existing receipts and existing idempotent retries are
-- deliberately accessible while company information is being completed.

notify pgrst,'reload schema';
commit;
