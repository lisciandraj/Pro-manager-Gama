-- GAMA: public policy versions, private rights/returns intake and compliance evidence.
-- No company identity, legal evidence, payment account or fiscal validation is invented.
begin;
create or replace function private.gama_storefront_schema() returns jsonb language sql immutable set search_path='' as $schema$ select '{"version":3,"groups":[{"id":"identity","label":["Identidad y diseño","Identité et apparence","Identity and design"],"fields":[{"key":"brand_name","label":["Nombre comercial","Nom commercial","Brand name"],"type":"text","max":100,"default":"Distribuidora GAMA"},{"key":"tagline","label":["Firma de marca","Signature de marque","Tagline"],"type":"text","max":120,"default":"Lo pides, lo tienes."},{"key":"logo_url","label":["Logotipo","Logo","Logo"],"type":"image","max":400000,"default":""},{"key":"primary_color","label":["Color principal","Couleur principale","Primary color"],"type":"color","default":"#176072"},{"key":"accent_color","label":["Color de acento","Couleur d’accent","Accent color"],"type":"color","default":"#e4884f"},{"key":"background_color","label":["Fondo","Fond","Background"],"type":"color","default":"#f7f6f2"},{"key":"corner_style","label":["Esquinas","Angles","Corners"],"type":"enum","options":["soft","square"],"option_labels":[["Redondeadas","Arrondis","Rounded"],["Rectas","Droits","Square"]],"default":"soft"},{"key":"navigation","label":["Menú","Menu","Navigation"],"type":"list","max":6,"default":[{"label":"Catálogo","href":"#catalogo"},{"label":"Sobre GAMA","href":"#nosotros"},{"label":"Contacto","href":"#contacto"}],"fields":[{"key":"label","label":["Texto","Texte","Text"],"type":"text","max":40},{"key":"href","label":["Destino","Destination","Destination"],"type":"link","max":500}]}]},{"id":"home","label":["Página de inicio","Page d’accueil","Homepage"],"fields":[{"key":"announcement","label":["Banda superior","Bandeau supérieur","Announcement"],"type":"text","max":180,"default":"Abastecemos el día a día de tu empresa · Quito, Ecuador"},{"key":"hero_label","label":["Etiqueta de inicio","Accroche","Hero label"],"type":"text","max":80,"default":"Tu empresa, bien abastecida"},{"key":"hero_title","label":["Título principal","Titre principal","Hero title"],"type":"text","max":120,"default":"Todo lo que necesitas."},{"key":"hero_accent","label":["Segunda línea del título","Deuxième ligne du titre","Title second line"],"type":"text","max":120,"default":"En un solo lugar."},{"key":"hero_intro","label":["Presentación","Présentation","Introduction"],"type":"textarea","max":600,"default":"Productos para tu equipo, tu oficina y cada pausa del día. Encuentra lo que buscas y recibe una atención cercana, de principio a fin."},{"key":"hero_image","label":["Imagen principal (opcional)","Image principale (facultative)","Hero image (optional)"],"type":"image","max":700000,"default":""},{"key":"hero_button","label":["Texto del botón","Texte du bouton","Button label"],"type":"text","max":45,"default":"Explorar el catálogo"},{"key":"hero_button_target","label":["Destino del botón","Destination du bouton","Button destination"],"type":"enum","options":["catalogo","contacto"],"option_labels":[["Catálogo","Catalogue","Catalogue"],["Contacto","Contact","Contact"]],"default":"catalogo"},{"key":"catalog_title","label":["Título del catálogo","Titre du catalogue","Catalogue title"],"type":"text","max":100,"default":"Encuentra tu próximo imprescindible."},{"key":"catalog_intro","label":["Texto del catálogo","Texte du catalogue","Catalogue introduction"],"type":"textarea","max":350,"default":"Una selección para acompañar el día a día de tu negocio."},{"key":"featured_title","label":["Título de destacados","Titre de la sélection","Featured title"],"type":"text","max":100,"default":"La selección GAMA"},{"key":"categories_title","label":["Título de categorías","Titre des catégories","Categories title"],"type":"text","max":100,"default":"Cada necesidad, su solución."},{"key":"show_featured","label":["Mostrar destacados","Afficher la sélection","Show featured products"],"type":"boolean","default":true},{"key":"show_categories","label":["Mostrar categorías","Afficher les catégories","Show categories"],"type":"boolean","default":true},{"key":"show_benefits","label":["Mostrar ventajas","Afficher les avantages","Show benefits"],"type":"boolean","default":true},{"key":"benefits","label":["Ventajas","Avantages","Benefits"],"type":"list","max":4,"default":[{"icon":"box","title":"Un solo proveedor","text":"Haz más sencilla la compra de los productos de tu empresa."},{"icon":"headset","title":"Atención cercana","text":"Te acompañamos para encontrar lo que necesitas."},{"icon":"truck","title":"Entrega coordinada","text":"Confirmamos contigo disponibilidad, condiciones y entrega."}],"fields":[{"key":"icon","label":["Icono","Icône","Icon"],"type":"enum","options":["box","headset","truck","shield"],"option_labels":[["Caja","Colis","Box"],["Atención","Assistance","Support"],["Entrega","Livraison","Delivery"],["Confianza","Confiance","Trust"]]},{"key":"title","label":["Título","Titre","Title"],"type":"text","max":70},{"key":"text","label":["Descripción","Description","Description"],"type":"textarea","max":200}]}]},{"id":"content","label":["Contenido y páginas","Contenu et pages","Content and pages"],"fields":[{"key":"show_about","label":["Mostrar presentación","Afficher la présentation","Show about section"],"type":"boolean","default":true},{"key":"about_title","label":["Título de presentación","Titre de présentation","About title"],"type":"text","max":120,"default":"Tu negocio avanza. Nosotros lo acompañamos."},{"key":"about_text","label":["Sobre la empresa","À propos de l’entreprise","About the business"],"type":"textarea","max":2000,"default":"En GAMA hacemos más sencilla la búsqueda de productos para tu empresa. Nuestro catálogo reúne una selección práctica y un equipo dispuesto a ayudarte. Cuéntanos qué necesitas: prepararemos una propuesta para ti."},{"key":"about_image","label":["Imagen de presentación","Image de présentation","About image"],"type":"image","max":700000,"default":""},{"key":"show_faq","label":["Mostrar preguntas frecuentes","Afficher les questions fréquentes","Show FAQ"],"type":"boolean","default":true},{"key":"faq","label":["Preguntas frecuentes","Questions fréquentes","Frequently asked questions"],"type":"list","max":10,"default":[{"question":"¿Cómo solicito una cotización?","answer":"Añade productos a tu selección y envía la solicitud con tus datos de contacto. Nuestro equipo confirmará precios, disponibilidad y condiciones."},{"question":"¿Puedo consultar por otros productos?","answer":"Sí. Contacta con nuestro equipo y cuéntanos qué necesita tu empresa."}],"fields":[{"key":"question","label":["Pregunta","Question","Question"],"type":"text","max":180},{"key":"answer","label":["Respuesta","Réponse","Answer"],"type":"textarea","max":1000}]},{"key":"brands","label":["Marcas (opcional)","Marques (facultatif)","Brands (optional)"],"type":"list","max":12,"default":[],"fields":[{"key":"name","label":["Nombre","Nom","Name"],"type":"text","max":70},{"key":"image","label":["Imagen","Image","Image"],"type":"url","max":500}]},{"key":"terms_title","label":["Título de condiciones","Titre des conditions","Terms title"],"type":"text","max":100,"default":"Condiciones de la solicitud"},{"key":"terms_text","label":["Condiciones","Conditions","Terms"],"type":"textarea","max":6000,"default":"Enviar una solicitud no confirma una compra ni reserva productos. Nuestro equipo confirmará la disponibilidad, los precios finales y las condiciones de pago y entrega antes de acordar un pedido."},{"key":"privacy_title","label":["Título de privacidad","Titre de confidentialité","Privacy title"],"type":"text","max":100,"default":"Privacidad"},{"key":"privacy_text","label":["Información de privacidad","Informations de confidentialité","Privacy information"],"type":"textarea","max":6000,"default":"Utilizamos los datos de contacto que nos envías para atender tu solicitud. Puedes contactar con nosotros para consultar el uso de tus datos. No envíes datos bancarios ni información sensible a través de este formulario."},{"key":"footer_note","label":["Texto del pie de página","Texte du pied de page","Footer text"],"type":"textarea","max":350,"default":"Productos y atención para el día a día de tu empresa."}]},{"id":"legal","label":["Información legal","Informations légales","Legal information"],"fields":[{"key":"legal_name","label":["Razón social","Raison sociale","Legal entity name"],"type":"text","max":160,"default":""},{"key":"legal_tax_id","label":["RUC (13 dígitos)","RUC (13 chiffres)","Tax ID (13 digits)"],"type":"text","max":13,"default":""},{"key":"legal_address","label":["Domicilio legal","Adresse légale","Registered address"],"type":"textarea","max":500,"default":""},{"key":"legal_representative","label":["Representante legal","Représentant légal","Legal representative"],"type":"text","max":160,"default":""},{"key":"privacy_email","label":["Contacto de privacidad","Contact confidentialité","Privacy contact"],"type":"email","max":254,"default":""},{"key":"notice_title","label":["Título de información legal","Titre des mentions légales","Legal information title"],"type":"text","max":100,"default":"Información legal"},{"key":"notice_text","label":["Información legal adicional","Mentions légales complémentaires","Additional legal information"],"type":"textarea","max":6000,"default":""},{"key":"delivery_title","label":["Título de entregas y devoluciones","Titre livraison et retours","Delivery and returns title"],"type":"text","max":100,"default":"Entregas, cambios y garantías"},{"key":"delivery_text","label":["Entregas, cambios y garantías","Livraison, retours et garanties","Delivery, returns and warranties"],"type":"textarea","max":6000,"default":"Antes de aceptar un pedido, confirmaremos por escrito la disponibilidad, la zona de entrega, el plazo, el costo del envío y las condiciones de pago. El envío no está incluido en el importe indicativo del catálogo.\n\nPara consultar por una entrega, un producto defectuoso, una garantía o una devolución, contacta con GAMA e indica la referencia del pedido y del producto. Revisaremos la solicitud según las condiciones acordadas y los derechos que reconoce la legislación ecuatoriana. Las garantías y los derechos legales del consumidor no se limitan por estas condiciones."},{"key":"storage_title","label":["Título de almacenamiento","Titre du stockage","Storage information title"],"type":"text","max":100,"default":"Cookies y almacenamiento"},{"key":"storage_text","label":["Cookies y almacenamiento","Cookies et stockage","Cookies and storage"],"type":"textarea","max":6000,"default":"El catálogo utiliza el almacenamiento de sesión del navegador para conservar los identificadores y cantidades de tu selección en esta pestaña. No guarda en ese espacio tu nombre, correo electrónico ni el contenido del formulario.\n\nEl portal Mi empresa utiliza una sesión de autenticación para mostrar los datos de la empresa autorizada. Puedes cerrarla con Cerrar sesión.\n\nEste catálogo no incorpora herramientas publicitarias, píxeles de seguimiento ni analítica de comportamiento. La infraestructura puede procesar datos técnicos de conexión para servir y proteger el sitio. Los enlaces externos se rigen por las políticas de sus respectivos sitios. Puedes borrar los datos de navegación en los ajustes de tu navegador; la selección o la sesión podrían perderse."},{"key":"returns_address","label":["Dirección de devoluciones","Adresse des retours","Returns address"],"type":"textarea","max":500,"default":""},{"key":"delivery_areas","label":["Zonas de entrega","Zones de livraison","Delivery areas"],"type":"textarea","max":1500,"default":""},{"key":"delivery_timeframes","label":["Plazos de entrega","Délais de livraison","Delivery timeframes"],"type":"textarea","max":1500,"default":""},{"key":"delivery_costs","label":["Costos y condiciones del envío","Frais et conditions de livraison","Delivery costs and conditions"],"type":"textarea","max":1500,"default":""},{"key":"refund_terms","label":["Procedimiento y medios de reembolso","Procédure et moyens de remboursement","Refund procedure and methods"],"type":"textarea","max":1500,"default":""},{"key":"warranty_terms","label":["Garantías comerciales aplicables","Garanties commerciales applicables","Applicable commercial warranties"],"type":"textarea","max":1500,"default":""},{"key":"privacy_retention","label":["Conservación por finalidad (texto público)","Conservation par finalité (texte public)","Retention by purpose (public text)"],"type":"textarea","max":3000,"default":""},{"key":"privacy_recipients","label":["Prestadores y flujos de datos (texto público)","Prestataires et flux de données (texte public)","Providers and data flows (public text)"],"type":"textarea","max":3000,"default":""},{"key":"privacy_rights_process","label":["Atención de derechos (texto público)","Exercice des droits (texte public)","Rights handling (public text)"],"type":"textarea","max":3000,"default":""}]},{"id":"contact","label":["Contacto y WhatsApp","Contact et WhatsApp","Contact and WhatsApp"],"fields":[{"key":"show_contact","label":["Mostrar contacto","Afficher les coordonnées","Show contact section"],"type":"boolean","default":true},{"key":"contact_title","label":["Título de contacto","Titre de contact","Contact title"],"type":"text","max":120,"default":"Hablemos de lo que necesitas."},{"key":"contact_intro","label":["Texto de contacto","Texte de contact","Contact introduction"],"type":"textarea","max":500,"default":"Una consulta, una lista de productos o tu próximo pedido. Estamos para ayudarte."},{"key":"phone","label":["Teléfono","Téléphone","Phone"],"type":"text","max":60,"default":"(593-2) 250-1350"},{"key":"email","label":["Correo electrónico","Adresse e-mail","Email"],"type":"email","max":254,"default":""},{"key":"address","label":["Dirección","Adresse","Address"],"type":"textarea","max":300,"default":"Puerto Rico N27-108 y Selva Alegre, Quito"},{"key":"whatsapp","label":["WhatsApp con código de país (ej. +593…)","WhatsApp avec indicatif pays (ex. +593…)","WhatsApp including country code (e.g. +593…)"],"type":"text","max":30,"default":""},{"key":"opening_hours","label":["Horario de atención","Horaires d’ouverture","Opening hours"],"type":"textarea","max":300,"default":""},{"key":"map_url","label":["Enlace al mapa","Lien vers la carte","Map link"],"type":"url","max":500,"default":""},{"key":"facebook_url","label":["Facebook","Facebook","Facebook"],"type":"url","max":500,"default":""},{"key":"instagram_url","label":["Instagram","Instagram","Instagram"],"type":"url","max":500,"default":""},{"key":"linkedin_url","label":["LinkedIn","LinkedIn","LinkedIn"],"type":"url","max":500,"default":""},{"key":"whatsapp_message","label":["Mensaje inicial de WhatsApp (sin datos personales)","Message initial WhatsApp (sans données personnelles)","Initial WhatsApp message (no personal data)"],"type":"textarea","max":250,"default":""}]},{"id":"publication","label":["Publicación y catálogo","Publication et catalogue","Publication and catalogue"],"fields":[{"key":"site_enabled","label":["Publicar el sitio","Publier le site","Publish website"],"type":"boolean","default":true},{"key":"website_url","label":["Dirección del sitio Cloudflare","Adresse du site Cloudflare","Cloudflare website address"],"type":"url","max":500,"default":""},{"key":"show_prices","label":["Mostrar precios","Afficher les prix","Show prices"],"type":"boolean","default":true},{"key":"price_display","label":["Presentación de precios","Affichage des prix","Price display"],"type":"enum","options":["with_tax","without_tax"],"option_labels":[["Con impuestos","Taxes comprises","Including tax"],["Sin impuestos","Hors taxes","Excluding tax"]],"default":"with_tax"},{"key":"enable_quotes","label":["Recibir solicitudes de cotización","Recevoir des demandes de devis","Accept quote requests"],"type":"boolean","default":true},{"key":"quote_label","label":["Nombre de la selección","Nom de la sélection","Selection label"],"type":"text","max":50,"default":"Mi cotización"},{"key":"default_sort","label":["Orden del catálogo","Tri du catalogue","Catalogue sorting"],"type":"enum","options":["featured","name","price_asc","price_desc"],"option_labels":[["Destacados primero","Sélection en premier","Featured first"],["Nombre","Nom","Name"],["Precio creciente","Prix croissant","Price ascending"],["Precio decreciente","Prix décroissant","Price descending"]],"default":"featured"},{"key":"page_size","label":["Productos por página","Produits par page","Products per page"],"type":"enum","options":["12","24","36"],"option_labels":[["12","12","12"],["24","24","24"],["36","36","36"]],"default":"12"},{"key":"seo_title","label":["Título para buscadores","Titre pour les moteurs de recherche","Search engine title"],"type":"text","max":100,"default":"Distribuidora GAMA | Productos para tu empresa en Quito"},{"key":"seo_description","label":["Descripción para buscadores","Description pour les moteurs de recherche","Search engine description"],"type":"textarea","max":320,"default":"Descubre el catálogo de Distribuidora GAMA. Productos para tu empresa, atención personalizada y solicitudes de cotización en Quito, Ecuador."}]}]}'::jsonb $schema$;
create function private.commerce_policy_templates() returns jsonb language sql immutable set search_path='' as $templates$ select '{"revision":"2026-10-29.2","templates":{"privacy":"Información de privacidad\n\nQué datos tratamos\nDatos de contacto, identificación y dirección de facturación cuando solicitas un pedido, productos, cantidades, historial comercial y decisiones de aprobación. También tratamos el contenido y el seguimiento de las solicitudes de privacidad, devoluciones, garantías y reclamaciones. La infraestructura trata datos técnicos de conexión para mantener el servicio y prevenir abusos. No introduzcas datos de tarjeta en los formularios.\n\nFinalidades y bases\nAtender tu solicitud y ejecutar las medidas precontractuales que pides; gestionar la relación contractual y cumplir las obligaciones de facturación, contabilidad y protección del consumidor. La seguridad se basa en el interés legítimo de proteger el servicio, sujeto a la evaluación correspondiente. Leer esta información no equivale a suscribirse a publicidad. No se activa marketing por comprar ni por tener una cuenta.\n\nDestinatarios\nPersonal autorizado de GAMA y proveedores necesarios de infraestructura, principalmente Cloudflare y Supabase. La base está alojada en Irlanda. El acceso de un proveedor por cuenta de GAMA debe estar cubierto por un contrato de encargo; otras comunicaciones internacionales requieren la garantía que corresponda. Un clic en WhatsApp abre un servicio externo con sus propias condiciones.\n\nConservación\nLos datos se conservan durante la atención de la solicitud y la relación contractual, y después por los plazos legales aplicables o la defensa de reclamaciones. Los comprobantes electrónicos se conservan durante siete años cuando corresponda conforme al SRI. La selección y los comprobantes sin cuenta de esta pestaña se eliminan al borrar su almacenamiento de sesión. GAMA debe aplicar un calendario de conservación a los demás registros.\n\nTus derechos\nPuedes solicitar acceso, rectificación, actualización, eliminación, oposición, portabilidad, suspensión y los demás derechos aplicables, y retirar un consentimiento opcional, mediante {{contact}}. La identidad se verifica de forma proporcional. GAMA debe responder dentro del plazo legal aplicable; la eliminación puede estar limitada por obligaciones legales de conservación. Puedes reclamar ante la Superintendencia de Protección de Datos Personales: https://www.spdp.gob.ec/.\n\nCampos obligatorios\nLos datos marcados con * son necesarios para atender la solicitud o preparar la facturación. Sin ellos no se puede completar el trámite. Las opiniones son opcionales: su texto, valoración y fecha se publican como Compra verificada. No se toman decisiones de aprobación de compras mediante perfiles automatizados: las valida una persona autorizada.","terms":"Condiciones de solicitudes y pedidos\n\nPrecios y revisión\nLos precios públicos incluyen el IVA del producto. Las cuentas de empresa ven su precio negociado sin IVA; la revisión de la selección muestra los impuestos y el total de productos. Todas las cantidades, precios y permisos se comprueban de nuevo al enviar.\n\nConfirmación\nEnviar una solicitud de cotización o un pedido sin cuenta no confirma una compra, no reserva existencias y no produce un cargo. GAMA debe confirmar por escrito disponibilidad, precio final, costo y plazo de entrega y medio de pago antes de aceptar el pedido. El envío no se presume gratuito ni incluido. Puedes corregir la selección antes de enviarla.\n\nCompras de empresa\nLos solicitantes sujetos a aprobación no pueden aceptar directamente una compra. Las modificaciones de artículos o cantidades reinician las validaciones. Copiar un pedido prepara una nueva selección a precios actuales; no repite un pago.\n\nPago y facturación\nEl pago en línea no está habilitado hasta disponer de un prestador y cuenta comercial configurados. No guardamos datos de tarjeta en este sitio. La referencia del pedido y los presupuestos son documentos comerciales; la factura fiscal debe emitirse y autorizarse mediante el proceso tributario aplicable.\n\nEstas condiciones no limitan los derechos legales del consumidor.","delivery":"Entregas, devoluciones y garantías\n\nGAMA confirma por escrito la dirección, cobertura, disponibilidad, costo, plazo de entrega y consecuencias de un retraso antes de la aceptación definitiva. Una fecha solicitada no es una promesa de entrega.\n\nEl artículo 45 de la Ley Orgánica de Defensa del Consumidor reconoce el derecho de devolución en el término de quince días posteriores a la recepción, siempre que la naturaleza del bien lo permita y conserve el estado en que fue recibido. No se aplica la antigua indicación de tres días.\n\nContacta con {{contact}} indicando la referencia y los productos para ejercer este derecho o solicitar atención por un defecto. Las garantías legales y los remedios por productos defectuosos se mantienen, sin perjuicio de la garantía comercial aplicable. No se exige una renuncia a derechos legales por tratarse de una compra desde una cuenta de empresa.\n\nLas condiciones particulares de transporte, devolución y garantía se comunicarán antes de confirmar la compra.","storage":"Cookies y almacenamiento\n\nLa selección, la sesión de empresa y los comprobantes de pedidos sin cuenta se guardan en el almacenamiento de sesión de esta pestaña. Las preferencias de cookies se conservan localmente hasta que las elimines. Los comprobantes no contienen datos de facturación en el almacenamiento del navegador. No se guardan los datos de facturación en el navegador.\n\nCloudflare Turnstile procesa señales técnicas para prevenir envíos automatizados. Es una función de seguridad y no una autorización para publicidad.\n\nNo se activan cookies publicitarias, píxeles ni analítica de comportamiento. Si se incorporan finalidades opcionales, deberán permanecer bloqueadas hasta obtener un consentimiento válido y permitir su retirada. Usa Preferencias de cookies en el pie de página. Borrar el almacenamiento o cerrar sesión puede eliminar la selección o el acceso a comprobantes de esta pestaña.","notice":"Este sitio es operado por la entidad indicada arriba. Las solicitudes de cotización y de pedido no confirman una compra ni reservan existencias. El pedido definitivo requiere acordar disponibilidad, precio, IVA, entrega y pago."}}'::jsonb $templates$;
revoke all on function private.commerce_policy_templates() from public,anon,authenticated;

create function private.commerce_config_defaults(p_config jsonb) returns jsonb language sql immutable set search_path='' as $$
 select coalesce(jsonb_object_agg(f->>'key',f->'default'),'{}')||p_config
 from jsonb_array_elements(private.gama_storefront_schema()->'groups')g cross join lateral jsonb_array_elements(g->'fields')f
$$;
revoke all on function private.commerce_config_defaults(jsonb) from public,anon,authenticated;
create function private.commerce_policy_bundle() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cfg jsonb;docs jsonb:='{}';titles jsonb:='{}';t jsonb:=private.commerce_policy_templates();k text;body text;identity text;contact text;f record;
begin
 select private.commerce_config_defaults(config) into cfg from private.website_public_settings where id;
 identity:=concat_ws(E'\n',coalesce(nullif(cfg->>'legal_name',''),cfg->>'brand_name'),case when cfg->>'legal_tax_id' ~ '^[0-9]{13}$' then 'RUC: '||(cfg->>'legal_tax_id') end,
 nullif(cfg->>'legal_address',''),nullif(cfg->>'phone',''),nullif(cfg->>'email',''),nullif(cfg->>'privacy_email',''));
 contact:=coalesce(nullif(cfg->>'privacy_email',''),nullif(cfg->>'email',''),nullif(cfg->>'phone',''),'los canales de contacto publicados');
 for k,body in select key,value from jsonb_each_text(t->'templates') loop
  body:=case when k='storage' then '' else identity||E'\n\n' end||replace(body,'{{contact}}',contact);
  for f in select * from (values
   ('notice','legal_representative','Representante legal'),('delivery','returns_address','Dirección de devoluciones'),
   ('delivery','delivery_areas','Cobertura'),('delivery','delivery_timeframes','Plazos'),('delivery','delivery_costs','Costos del envío'),
   ('delivery','refund_terms','Reembolsos'),('delivery','warranty_terms','Garantías comerciales'),
   ('privacy','privacy_retention','Calendario de conservación'),('privacy','privacy_recipients','Prestadores y flujos de datos'),
   ('privacy','privacy_rights_process','Atención de derechos'))v(kind,field,label) where kind=k loop
   if coalesce(cfg->>f.field,'')<>'' then body:=body||E'\n\n'||f.label||E'\n'||(cfg->>f.field);end if;
  end loop;
  if coalesce(cfg->>(k||'_text'),'')<>'' then body:=body||E'\n\nInformación complementaria de GAMA\n'||(cfg->>(k||'_text'));end if;
  docs:=docs||jsonb_build_object(k,body);titles:=titles||jsonb_build_object(k,cfg->>(k||'_title'));
 end loop;
 return jsonb_build_object('version',(t->>'revision')||'-'||md5(docs::text||titles::text),'documents',docs,'titles',titles);
end $$;
revoke all on function private.commerce_policy_bundle() from public,anon,authenticated;
create table private.commerce_policy_versions(
 version text primary key, documents jsonb not null,titles jsonb not null, created_at timestamptz not null default now(),created_by uuid references public.profiles
);

-- Public settings are editable in Coco; new optional fields are composed at read time.
-- Existing configuration rows are not rewritten by this schema migration.
alter function private.gama_website(text,jsonb) rename to gama_website_before_compliance;
revoke all on function private.gama_website_before_compliance(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_website(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;b jsonb;c jsonb:=p_data->'config';begin
 if p_action='public_save_settings' then
  if (coalesce(c->>'legal_tax_id','')<>'' and c->>'legal_tax_id' !~ '^[0-9]{13}$') or
   (coalesce(c->>'whatsapp','')<>'' and regexp_replace(c->>'whatsapp','[^0-9]','','g') !~ '^[1-9][0-9]{7,14}$') then raise exception 'WEBSITE_INVALID_CONFIGURATION';end if;
 end if;
 r:=private.gama_website_before_compliance(p_action,p_data);
 if p_action='public_settings' then r:=jsonb_set(r,'{config}',private.commerce_config_defaults(r->'config'));end if;
 if p_action in ('public_settings','public_save_settings') then
  b:=private.commerce_policy_bundle();r:=r||jsonb_build_object('policy_version',b->>'version');
  if p_action='public_save_settings' then insert into private.commerce_policy_versions(version,documents,titles,created_by) values(b->>'version',b->'documents',b->'titles',auth.uid()) on conflict do nothing;end if;
 end if;
 return r;
end $$;
revoke all on function private.gama_website(text,jsonb) from public,anon;
grant execute on function private.gama_website(text,jsonb) to authenticated;

alter function storefront_api.gama_storefront(text,jsonb) rename to gama_storefront_before_compliance;
revoke all on function storefront_api.gama_storefront_before_compliance(text,jsonb) from public,anon,authenticated,service_role;
create function storefront_api.gama_storefront(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;begin
 r:=storefront_api.gama_storefront_before_compliance(p_action,p_data);
 if p_action='bootstrap' then
  r:=r||jsonb_build_object('policies',private.commerce_policy_bundle());
  if r->>'paused'='false' then r:=jsonb_set(r,'{settings}',private.commerce_config_defaults(r->'settings'));end if;
 end if;
 return r;
end $$;
revoke all on function storefront_api.gama_storefront(text,jsonb) from public;
grant execute on function storefront_api.gama_storefront(text,jsonb) to anon,authenticated;

create table private.commerce_cases(
 id uuid primary key default gen_random_uuid(),reference text not null unique default ('GAMA-'||upper(replace(gen_random_uuid()::text,'-',''))),
 request_key uuid not null unique,payload_hash text not null,
 kind text not null check(kind in ('privacy','return','warranty','complaint')),right_kind text not null default '',
 contact_name text not null,email text not null,order_reference text not null default '',message text not null,
 status text not null default 'new' check(status in ('new','verifying','in_progress','answered','closed')),
 owner text not null default '',identity_verified_at timestamptz,identity_verified_by uuid references public.profiles,
 resolution text not null default 'handled' check(resolution in ('handled','refused_identity')),target_at timestamptz,target_basis text not null default '',internal_notes text not null default '',response_reference text not null default '',
 received_at timestamptz not null default now(),updated_at timestamptz not null default now(),closed_at timestamptz,
 legal_hold boolean not null default false,redacted_at timestamptz,version integer not null default 1,
 policy_snapshot jsonb not null
);
create index commerce_cases_queue on private.commerce_cases(status,target_at,received_at desc);
create table private.commerce_contact_attempts(
 id uuid primary key default gen_random_uuid(),visitor_hash text not null,email_hash text not null,created_at timestamptz not null default now()
);
create index commerce_contact_attempts_visitor on private.commerce_contact_attempts(visitor_hash,created_at);
create index commerce_contact_attempts_email on private.commerce_contact_attempts(email_hash,created_at);
create table private.commerce_compliance_records(
 id uuid primary key default gen_random_uuid(),kind text not null check(kind in ('processing','processor','retention','incident','assessment','tax_validation','operational_proof')),
 title text not null,owner text not null default '',status text not null default 'draft' check(status in ('draft','in_progress','verified','not_applicable')),
 scope text not null default '',details text not null default '',evidence text not null default '',next_review date,
 verified_by uuid references public.profiles,verified_at timestamptz,version integer not null default 1,
 created_by uuid not null references public.profiles,updated_by uuid not null references public.profiles,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index commerce_compliance_records_review on private.commerce_compliance_records(kind,next_review);
create table private.commerce_retention_rule(
 id boolean primary key default true check(id),enabled boolean not null default false,closed_case_days integer not null default 365 check(closed_case_days between 30 and 3650),
 approval_reference text not null default '',version integer not null default 1,updated_by uuid references public.profiles,updated_at timestamptz not null default now()
);
-- Lazy creation by an authorized administrator; cron does nothing until a rule is approved.
alter table private.commerce_reviews add column hidden boolean not null default false,add column moderation_reason text not null default '',add column moderated_by uuid references public.profiles,add column moderated_at timestamptz;

do $$declare t text;begin
 foreach t in array array['commerce_policy_versions','commerce_cases','commerce_contact_attempts','commerce_compliance_records','commerce_retention_rule'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated',t);
  if t<>'commerce_contact_attempts' then
   insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column)
    values(t,'website',case t when 'commerce_cases' then 'Solicitud de derechos o atención' when 'commerce_policy_versions' then 'Versión de condiciones' else 'Seguimiento de conformidad' end,'private',case when t='commerce_policy_versions' then 'version' else 'id' end);
   execute format('create trigger coco_module_history after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',t);
  end if;
 end loop;
end $$;

-- Replace the fixed policy marker with the complete current server-rendered documents.
-- A retry remains idempotent after a policy edit; a fresh checkout must accept the new version.
do $$declare body text;begin
 select pg_get_functiondef('storefront_api.gama_commerce(text,jsonb)'::regprocedure) into body;
 if strpos(body,'or p_data->>''policy_version'' is distinct from ''2026-10-29''')=0 then raise exception 'COMPLIANCE_POLICY_ANCHOR';end if;
 body:=replace(body,' or p_data->>''policy_version'' is distinct from ''2026-10-29''','');
 body:=replace(body,'cart:=private.commerce_public_cart(p_data->''lines'');',
  'if p_data->>''policy_version'' is distinct from (private.commerce_policy_bundle()->>''version'') then raise exception ''COMMERCE_POLICY_CHANGED'';end if; cart:=private.commerce_public_cart(p_data->''lines'');');
 body:=replace(body,'''2026-10-29'',','p_data->>''policy_version'',');
 body:=replace(body,'(select jsonb_object_agg(key,value) from private.website_public_settings s,jsonb_each(s.config) where s.id and key in (''legal_name'',''legal_tax_id'',''address'',''phone'',''email'',''privacy_email'',''terms_text'',''privacy_text'',''delivery_text'',''storage_text''))','private.commerce_policy_bundle()');
 body:=replace(body,'''created_at'',g.created_at,''payment_enabled'',false','''created_at'',g.created_at,''cart'',g.cart,''policies'',g.policy_snapshot,''policy_version'',g.policy_version,''accepted_at'',g.terms_accepted_at,''payment_enabled'',false');
 execute body;
end $$;
alter function storefront_api.gama_commerce(text,jsonb) rename to gama_commerce_before_compliance;
revoke all on function storefront_api.gama_commerce_before_compliance(text,jsonb) from public,anon,authenticated,service_role;
create function storefront_api.gama_commerce(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;c private.commerce_cases;secret text;visitor text;eh text;fingerprint text;key_id uuid;bundle jsonb;
 cid uuid;buyer text;pid uuid;g private.commerce_guest_orders;off integer:=coalesce((p_data->>'offset')::integer,0);
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>28000 or off<0 or off>100000 then raise exception 'WEBSITE_INVALID_DATA';end if;
 if p_action='policies' then return private.commerce_policy_bundle();end if;
 if p_action='case_submit' then
  perform private.commerce_guest_guard();
  if coalesce(p_data->>'website','')<>'' or coalesce(p_data->>'kind','') not in ('privacy','return','warranty','complaint')
   or length(btrim(coalesce(p_data->>'contact_name',''))) not between 2 and 120 or length(coalesce(p_data->>'email',''))>254
   or coalesce(p_data->>'email','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
   or length(btrim(coalesce(p_data->>'message',''))) not between 5 and 3000 or length(coalesce(p_data->>'order_reference',''))>100
   or (p_data->>'kind'='privacy' and coalesce(p_data->>'right_kind','') not in ('access','rectification','erasure','opposition','portability','restriction','withdrawal','other'))
   or length(coalesce(p_data->>'visitor','')) not between 1 and 200 then raise exception 'WEBSITE_INVALID_DATA';end if;
  key_id:=nullif(p_data->>'request_key','')::uuid;if key_id is null then raise exception 'WEBSITE_INVALID_DATA';end if;
  select token into secret from private.website_public_connection where id;
  fingerprint:=md5(secret||(p_data-array['visitor','request_key','website'])::text);
  perform pg_advisory_xact_lock(hashtextextended('commerce-case:'||key_id,0));
  select * into c from private.commerce_cases where request_key=key_id;
  if found then
   if c.payload_hash is distinct from fingerprint then raise exception 'WEBSITE_REQUEST_KEY_REUSED';end if;
   return jsonb_build_object('reference',c.reference,'received_at',c.received_at);
  end if;
  bundle:=private.commerce_policy_bundle();
  if p_data->>'policy_version' is distinct from bundle->>'version' then raise exception 'COMMERCE_POLICY_CHANGED';end if;
  visitor:=md5(secret||(p_data->>'visitor'));eh:=md5(secret||lower(btrim(p_data->>'email')));
  perform pg_advisory_xact_lock(hashtextextended('commerce-case-quota',0));
  if (select count(*) from private.commerce_contact_attempts where visitor_hash=visitor and created_at>now()-interval '30 minutes')>=8
   or (select count(*) from private.commerce_contact_attempts where commerce_contact_attempts.email_hash=eh and created_at>now()-interval '1 hour')>=5
   or (select count(*) from private.commerce_contact_attempts where created_at>now()-interval '1 day')>=2000 then raise exception 'WEBSITE_RATE_LIMIT';end if;
  insert into private.commerce_contact_attempts(visitor_hash,email_hash) values(visitor,eh);
  insert into private.commerce_cases(request_key,payload_hash,kind,right_kind,contact_name,email,order_reference,message,target_at,target_basis,policy_snapshot)
   values(key_id,fingerprint,p_data->>'kind',case when p_data->>'kind'='privacy' then p_data->>'right_kind' else '' end,btrim(p_data->>'contact_name'),lower(btrim(p_data->>'email')),
    btrim(coalesce(p_data->>'order_reference','')),btrim(p_data->>'message'),case when p_data->>'kind'='privacy' then now()+interval '15 days' end,
    case when p_data->>'kind'='privacy' then 'Objetivo operativo: 15 días desde recepción; validar el cómputo legal sin suspender por verificación de identidad.' else 'Validar plazo aplicable, recepción del producto y calendario legal.' end,bundle) returning * into c;
  return jsonb_build_object('reference',c.reference,'received_at',c.received_at);
 end if;
 if p_action='reviews' then
  pid:=(p_data->>'product_id')::uuid;
  -- Retain catalogue/publication guards, then expose only still-verified, unmoderated reviews.
  perform storefront_api.gama_commerce_before_compliance(p_action,p_data);
  return jsonb_build_object('count',(select count(*) from private.commerce_reviews v join public.sales_orders o on o.id=v.order_id where v.product_id=pid and not v.hidden and o.status='confirmed'),
   'average',(select round(avg(rating),1) from private.commerce_reviews v join public.sales_orders o on o.id=v.order_id where v.product_id=pid and not v.hidden and o.status='confirmed'),
   'items',coalesce((select jsonb_agg(to_jsonb(x)) from(select v.rating,v.body,v.created_at,'Compra verificada'::text author from private.commerce_reviews v join public.sales_orders o on o.id=v.order_id where v.product_id=pid and not v.hidden and o.status='confirmed' order by v.created_at desc,v.id limit 20 offset off)x),'[]'));
 end if;
 if p_action in ('review_delete','review_eligibility') then
  pid:=(p_data->>'product_id')::uuid;
  if auth.uid() is not null then cid:=private.gama_b2b_customer();buyer:='company:'||cid;
  else perform private.commerce_guest_guard();select * into g from private.commerce_guest_orders where id=(p_data->>'id')::uuid and access_token=(p_data->>'access_token')::uuid;
   if not found then raise exception 'NOT_FOUND';end if;buyer:='guest:'||g.id;
  end if;
  if p_action='review_delete' then delete from private.commerce_reviews where product_id=pid and buyer_key=buyer;return jsonb_build_object('deleted',true);end if;
  r:=storefront_api.gama_commerce_before_compliance(p_action,p_data);
  return r||jsonb_build_object('own_review',(select jsonb_build_object('rating',rating,'body',body,'hidden',hidden) from private.commerce_reviews where product_id=pid and buyer_key=buyer));
 end if;
 return storefront_api.gama_commerce_before_compliance(p_action,p_data);
end $$;
revoke all on function storefront_api.gama_commerce(text,jsonb) from public;
grant execute on function storefront_api.gama_commerce(text,jsonb) to anon,authenticated;

create function private.commerce_retention_cleanup() returns jsonb language plpgsql security definer set search_path='' as $$
declare r private.commerce_retention_rule;n integer:=0;begin
 delete from private.commerce_contact_attempts where created_at<now()-interval '2 days';
 select * into r from private.commerce_retention_rule where id and enabled and approval_reference<>'';
 if found then
  perform set_config('coco.activity_source_type','erp',true);
  perform set_config('coco.activity_source_id','commerce-retention',true);
  perform set_config('coco.activity_source_label','Conservación aprobada de solicitudes',true);
  update private.commerce_cases set contact_name='',email='',message='',order_reference='',internal_notes='',response_reference='',payload_hash='',
   redacted_at=now(),updated_at=now(),version=version+1 where status='closed' and closed_at<now()-make_interval(days=>r.closed_case_days) and not legal_hold and redacted_at is null;
  get diagnostics n=row_count;
 end if;
 return jsonb_build_object('redacted_cases',n);
end $$;
revoke all on function private.commerce_retention_cleanup() from public,anon,authenticated;
select cron.schedule('gama-commerce-retention','45 3 * * *','select private.commerce_retention_cleanup()');

create function private.gama_compliance_admin(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();cfg jsonb;b jsonb;r private.commerce_compliance_records;c private.commerce_cases;rule private.commerce_retention_rule;
 off integer:=coalesce((p_data->>'offset')::integer,0);record_id uuid;identity_ok boolean;
begin
 if actor is null or not private.erp_module_allowed('website',array['administrador']) or not private.erp_mfa_ok() then raise exception 'WEBSITE_ACCESS_DENIED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>28000 or off<0 or off>100000 then raise exception 'WEBSITE_INVALID_DATA';end if;
 if p_action='overview' then
  select private.commerce_config_defaults(config) into cfg from private.website_public_settings where id;
  b:=private.commerce_policy_bundle();
  return jsonb_build_object('policy_version',b->>'version','missing_fields',coalesce((select jsonb_agg(k) from unnest(array['legal_name','legal_tax_id','legal_address','privacy_email','returns_address','delivery_areas','delivery_timeframes','delivery_costs','refund_terms','warranty_terms','privacy_retention','privacy_recipients','privacy_rights_process'])k where btrim(coalesce(cfg->>k,''))=''),'[]'),
   'whatsapp_configured',coalesce(cfg->>'whatsapp','')<>'','open_cases',(select count(*) from private.commerce_cases where status not in ('closed','answered')),
   'overdue_cases',(select count(*) from private.commerce_cases where status not in ('closed','answered') and target_at<now()),
   'records_to_review',(select count(*) from private.commerce_compliance_records where status in ('draft','in_progress') or next_review<current_date),
   'payment_enabled',false,'can_edit',private.erp_action_allowed('website','edit'));
 end if;
 if p_action='cases' then return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,reference,kind,right_kind,status,owner,target_at,received_at,version,redacted_at,legal_hold from private.commerce_cases
  where coalesce(p_data->>'status','')='' or status=p_data->>'status' order by (status not in ('closed','answered')) desc,target_at nulls last,received_at desc limit 20 offset off)x),'[]'),'total',(select count(*) from private.commerce_cases where coalesce(p_data->>'status','')='' or status=p_data->>'status'));end if;
 if p_action='case_detail' then select * into c from private.commerce_cases where id=(p_data->>'id')::uuid;if not found then raise exception 'NOT_FOUND';end if;return to_jsonb(c)-'payload_hash'-'request_key';end if;
 if p_action='records' then return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from private.commerce_compliance_records where coalesce(p_data->>'kind','')='' or kind=p_data->>'kind' order by updated_at desc,id limit 20 offset off)x),'[]'),
  'total',(select count(*) from private.commerce_compliance_records where coalesce(p_data->>'kind','')='' or kind=p_data->>'kind'));end if;
 if p_action='policies' then return jsonb_build_object('current',private.commerce_policy_bundle(),'versions',coalesce((select jsonb_agg(to_jsonb(x)) from(select version,created_at from private.commerce_policy_versions order by created_at desc limit 20 offset off)x),'[]'));end if;
 if p_action='policy_detail' then select jsonb_build_object('version',version,'documents',documents,'titles',titles) into b from private.commerce_policy_versions where version=p_data->>'version';if b is null then raise exception 'NOT_FOUND';end if;return b;end if;
 if p_action='retention' then
  select * into rule from private.commerce_retention_rule where id;
  return (case when rule.id is null then jsonb_build_object('enabled',false,'closed_case_days',365,'approval_reference','','version',0) else to_jsonb(rule) end)||jsonb_build_object(
   'eligible_cases',(select count(*) from private.commerce_cases where status='closed' and closed_at<now()-make_interval(days=>coalesce(rule.closed_case_days,365)) and not legal_hold and redacted_at is null),
   'held_cases',(select count(*) from private.commerce_cases where legal_hold),'fiscal_documents_affected',0);
 end if;
 if p_action='reviews' then return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x)) from(select v.id,v.product_id,p.name product,v.rating,v.body,v.hidden,v.moderation_reason,v.updated_at from private.commerce_reviews v join public.products p on p.id=v.product_id order by v.created_at desc,v.id limit 20 offset off)x),'[]'),'total',(select count(*) from private.commerce_reviews));end if;
 if not private.erp_action_allowed('website','edit') then raise exception 'WEBSITE_ACCESS_DENIED';end if;
 if p_action='case_update' then
  select * into c from private.commerce_cases where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'NOT_FOUND';end if;
  if c.version is distinct from (p_data->>'version')::integer or c.redacted_at is not null then raise exception 'RECORD_CHANGED';end if;
  if coalesce(p_data->>'status','') not in ('new','verifying','in_progress','answered','closed') or length(coalesce(p_data->>'owner',''))>160
   or length(coalesce(p_data->>'internal_notes',''))>5000 or length(coalesce(p_data->>'response_reference',''))>1000 or length(coalesce(p_data->>'target_basis',''))>1000
   or jsonb_typeof(p_data->'identity_verified') is distinct from 'boolean' or jsonb_typeof(p_data->'legal_hold') is distinct from 'boolean' then raise exception 'WEBSITE_INVALID_DATA';end if;
  identity_ok:=(p_data->>'identity_verified')::boolean;
  if p_data->>'status' in ('answered','closed') and (btrim(coalesce(p_data->>'response_reference',''))='' or btrim(coalesce(p_data->>'owner',''))=''
   or (c.kind='privacy' and not identity_ok and p_data->>'resolution' is distinct from 'refused_identity')) then raise exception 'COMPLIANCE_RESPONSE_REQUIRED';end if;
  if coalesce(p_data->>'resolution','') not in ('handled','refused_identity') then raise exception 'WEBSITE_INVALID_DATA';end if;
  if p_data->>'resolution'='refused_identity' and length(btrim(coalesce(p_data->>'internal_notes','')))<10 then raise exception 'COMPLIANCE_RESPONSE_REQUIRED';end if;
  update private.commerce_cases set resolution=p_data->>'resolution',status=p_data->>'status',owner=btrim(p_data->>'owner'),internal_notes=coalesce(p_data->>'internal_notes',''),response_reference=coalesce(p_data->>'response_reference',''),
   target_at=nullif(p_data->>'target_at','')::timestamptz,target_basis=coalesce(p_data->>'target_basis',''),legal_hold=(p_data->>'legal_hold')::boolean,
   identity_verified_at=case when identity_ok then coalesce(identity_verified_at,now()) end,identity_verified_by=case when identity_ok then coalesce(identity_verified_by,actor) end,
   closed_at=case when p_data->>'status'='closed' then coalesce(closed_at,now()) end,updated_at=now(),version=version+1 where id=c.id returning * into c;
  return jsonb_build_object('id',c.id,'version',c.version);
 end if;
 if p_action='record_save' then
  if coalesce(p_data->>'kind','') not in ('processing','processor','retention','incident','assessment','tax_validation','operational_proof') or length(btrim(coalesce(p_data->>'title',''))) not between 3 and 180
   or coalesce(p_data->>'status','') not in ('draft','in_progress','verified','not_applicable') or length(coalesce(p_data->>'owner',''))>160 or length(coalesce(p_data->>'scope',''))>1000
   or length(coalesce(p_data->>'details',''))>10000 or length(coalesce(p_data->>'evidence',''))>3000 then raise exception 'WEBSITE_INVALID_DATA';end if;
  if p_data->>'status' in ('verified','not_applicable') and (length(btrim(coalesce(p_data->>'evidence','')))<5 or btrim(coalesce(p_data->>'owner',''))='' or btrim(coalesce(p_data->>'details',''))='') then raise exception 'COMPLIANCE_EVIDENCE_REQUIRED';end if;
  record_id:=nullif(p_data->>'id','')::uuid;
  if record_id is null then
   insert into private.commerce_compliance_records(kind,title,owner,status,scope,details,evidence,next_review,created_by,updated_by,verified_by,verified_at)
    values(p_data->>'kind',btrim(p_data->>'title'),coalesce(p_data->>'owner',''),p_data->>'status',coalesce(p_data->>'scope',''),coalesce(p_data->>'details',''),coalesce(p_data->>'evidence',''),nullif(p_data->>'next_review','')::date,actor,actor,
     case when p_data->>'status' in ('verified','not_applicable') then actor end,case when p_data->>'status' in ('verified','not_applicable') then now() end) returning * into r;
  else
   select * into r from private.commerce_compliance_records where id=record_id for update;if not found then raise exception 'NOT_FOUND';end if;
   if r.version is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
   update private.commerce_compliance_records set kind=p_data->>'kind',title=btrim(p_data->>'title'),owner=coalesce(p_data->>'owner',''),status=p_data->>'status',scope=coalesce(p_data->>'scope',''),details=coalesce(p_data->>'details',''),evidence=coalesce(p_data->>'evidence',''),next_review=nullif(p_data->>'next_review','')::date,
    verified_by=case when p_data->>'status' in ('verified','not_applicable') then actor end,verified_at=case when p_data->>'status' in ('verified','not_applicable') then now() end,
    updated_by=actor,updated_at=now(),version=version+1 where id=record_id returning * into r;
  end if;return to_jsonb(r);
 end if;
 if p_action='retention_save' then
  if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' or (p_data->>'closed_case_days')::integer not between 30 and 3650 or length(coalesce(p_data->>'approval_reference',''))>1000
   or ((p_data->>'enabled')::boolean and length(btrim(coalesce(p_data->>'approval_reference','')))<5) then raise exception 'COMPLIANCE_EVIDENCE_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('commerce-retention-rule',0));select * into rule from private.commerce_retention_rule where id;
  if coalesce(rule.version,0) is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
  insert into private.commerce_retention_rule(id,enabled,closed_case_days,approval_reference,updated_by) values(true,(p_data->>'enabled')::boolean,(p_data->>'closed_case_days')::integer,coalesce(p_data->>'approval_reference',''),actor)
   on conflict(id) do update set enabled=excluded.enabled,closed_case_days=excluded.closed_case_days,approval_reference=excluded.approval_reference,updated_by=actor,updated_at=now(),version=commerce_retention_rule.version+1 returning * into rule;
  return to_jsonb(rule);
 end if;
 if p_action='review_moderate' then
  if jsonb_typeof(p_data->'hidden') is distinct from 'boolean' or p_data->>'reason' not in ('personal_data','abuse','irrelevant','restored') then raise exception 'WEBSITE_INVALID_DATA';end if;
  update private.commerce_reviews set hidden=(p_data->>'hidden')::boolean,moderation_reason=p_data->>'reason',moderated_by=actor,moderated_at=now(),updated_at=now() where id=(p_data->>'id')::uuid and updated_at=(p_data->>'updated_at')::timestamptz;
  if not found then raise exception 'RECORD_CHANGED';end if;return jsonb_build_object('saved',true);
 end if;
 raise exception 'WEBSITE_INVALID_ACTION';
end $$;
revoke all on function private.gama_compliance_admin(text,jsonb) from public,anon;
grant execute on function private.gama_compliance_admin(text,jsonb) to authenticated;
create function public.gama_compliance_admin(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_compliance_admin(p_action,p_data)$$;
revoke all on function public.gama_compliance_admin(text,jsonb) from public,anon;
grant execute on function public.gama_compliance_admin(text,jsonb) to authenticated;
-- Bind a B2B acceptance to the exact public conditions alongside its quote snapshot.
do $$declare body text;target oid;n integer;begin
 select count(*),(array_agg(p.oid))[1] into n,target from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
 where ns.nspname='private' and p.proname like 'gama_b2b_action%' and strpos(p.prosrc,'insert into private.sales_portal_acceptances(quote_id,revision,accepted_by,snapshot)')>0;
 if n<>1 then raise exception 'COMPLIANCE_B2B_POLICY_ANCHOR';end if;
 select pg_get_functiondef(target) into body;
 body:=replace(body,'  insert into private.sales_portal_acceptances(quote_id,revision,accepted_by,snapshot)',
  '  if p_data->>''policy_version'' is distinct from (private.commerce_policy_bundle()->>''version'') then raise exception ''COMMERCE_POLICY_CHANGED'';end if; insert into private.sales_portal_acceptances(quote_id,revision,accepted_by,snapshot)');
 body:=replace(body,'jsonb_build_object(''reference'',q.invoice_number,''total'',q.total,''terms'',','jsonb_build_object(''policies'',private.commerce_policy_bundle(),''reference'',q.invoice_number,''total'',q.total,''terms'',');
 body:=replace(body,'result:=result||jsonb_build_object(''revision'',q.quote_revision,','result:=result||jsonb_build_object(''policies'',private.commerce_policy_bundle(),''revision'',q.quote_revision,');
 execute body;
end $$;
-- Keep the original function OID used by RLS policies. These rows have the same
-- administrator-only, module-wide read contract as the compliance RPC.
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),
 'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_compliance(');end $$;
revoke all on function private.coco_history_record_visible_before_compliance(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_compliance(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean language plpgsql stable security invoker set search_path='' as $$
begin
 if p_table in ('commerce_policy_versions','commerce_cases','commerce_compliance_records','commerce_retention_rule','commerce_reviews','commerce_guest_orders','commerce_approvers','commerce_approvals','commerce_catalog_products') then return private.coco_module_allowed('website');end if;
 return private.coco_history_record_visible_before_compliance(p_table,p_id,p_owner);
end $$;
commit;
