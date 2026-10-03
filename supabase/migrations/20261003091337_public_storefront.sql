-- A separate, deliberately public catalogue. Staff ERP APIs retain their contracts.
-- Anonymous callers receive only selected sale information; submissions require a
-- server-side integration key held by Cloudflare, never by the public browser.
create schema storefront_api;
revoke all on schema storefront_api from public;
grant usage on schema storefront_api to anon,authenticated;

create function private.gama_storefront_schema() returns jsonb language sql immutable set search_path='' as $$ select '{"version":1,"groups":[{"id":"identity","label":["Identidad y diseño","Identité et apparence","Identity and design"],"fields":[{"key":"brand_name","label":["Nombre comercial","Nom commercial","Brand name"],"type":"text","max":100,"default":"Distribuidora GAMA"},{"key":"tagline","label":["Firma de marca","Signature de marque","Tagline"],"type":"text","max":120,"default":"Lo pides, lo tienes."},{"key":"logo_url","label":["Logotipo","Logo","Logo"],"type":"image","max":400000,"default":""},{"key":"primary_color","label":["Color principal","Couleur principale","Primary color"],"type":"color","default":"#176072"},{"key":"accent_color","label":["Color de acento","Couleur d’accent","Accent color"],"type":"color","default":"#e4884f"},{"key":"background_color","label":["Fondo","Fond","Background"],"type":"color","default":"#f7f6f2"},{"key":"corner_style","label":["Esquinas","Angles","Corners"],"type":"enum","options":["soft","square"],"option_labels":[["Redondeadas","Arrondis","Rounded"],["Rectas","Droits","Square"]],"default":"soft"},{"key":"navigation","label":["Menú","Menu","Navigation"],"type":"list","max":6,"default":[{"label":"Catálogo","href":"#catalogo"},{"label":"Sobre GAMA","href":"#nosotros"},{"label":"Contacto","href":"#contacto"}],"fields":[{"key":"label","label":["Texto","Texte","Text"],"type":"text","max":40},{"key":"href","label":["Destino","Destination","Destination"],"type":"link","max":500}]}]},{"id":"home","label":["Página de inicio","Page d’accueil","Homepage"],"fields":[{"key":"announcement","label":["Banda superior","Bandeau supérieur","Announcement"],"type":"text","max":180,"default":"Abastecemos el día a día de tu empresa · Quito, Ecuador"},{"key":"hero_label","label":["Etiqueta de inicio","Accroche","Hero label"],"type":"text","max":80,"default":"TU EMPRESA, BIEN ABASTECIDA"},{"key":"hero_title","label":["Título principal","Titre principal","Hero title"],"type":"text","max":120,"default":"Todo lo que necesitas."},{"key":"hero_accent","label":["Segunda línea del título","Deuxième ligne du titre","Title second line"],"type":"text","max":120,"default":"En un solo lugar."},{"key":"hero_intro","label":["Presentación","Présentation","Introduction"],"type":"textarea","max":600,"default":"Productos para tu equipo, tu oficina y cada pausa del día. Encuentra lo que buscas y recibe una atención cercana, de principio a fin."},{"key":"hero_image","label":["Imagen principal (opcional)","Image principale (facultative)","Hero image (optional)"],"type":"image","max":700000,"default":""},{"key":"hero_button","label":["Texto del botón","Texte du bouton","Button label"],"type":"text","max":45,"default":"Explorar el catálogo"},{"key":"hero_button_target","label":["Destino del botón","Destination du bouton","Button destination"],"type":"enum","options":["catalogo","contacto"],"option_labels":[["Catálogo","Catalogue","Catalogue"],["Contacto","Contact","Contact"]],"default":"catalogo"},{"key":"catalog_title","label":["Título del catálogo","Titre du catalogue","Catalogue title"],"type":"text","max":100,"default":"Encuentra tu próximo imprescindible."},{"key":"catalog_intro","label":["Texto del catálogo","Texte du catalogue","Catalogue introduction"],"type":"textarea","max":350,"default":"Una selección para acompañar el día a día de tu negocio."},{"key":"featured_title","label":["Título de destacados","Titre de la sélection","Featured title"],"type":"text","max":100,"default":"La selección GAMA"},{"key":"categories_title","label":["Título de categorías","Titre des catégories","Categories title"],"type":"text","max":100,"default":"Cada necesidad, su solución."},{"key":"show_featured","label":["Mostrar destacados","Afficher la sélection","Show featured products"],"type":"boolean","default":true},{"key":"show_categories","label":["Mostrar categorías","Afficher les catégories","Show categories"],"type":"boolean","default":true},{"key":"show_benefits","label":["Mostrar ventajas","Afficher les avantages","Show benefits"],"type":"boolean","default":true},{"key":"benefits","label":["Ventajas","Avantages","Benefits"],"type":"list","max":4,"default":[{"icon":"box","title":"Un solo proveedor","text":"Haz más sencilla la compra de los productos de tu empresa."},{"icon":"headset","title":"Atención cercana","text":"Te acompañamos para encontrar lo que necesitas."},{"icon":"truck","title":"Entrega coordinada","text":"Confirmamos contigo disponibilidad, condiciones y entrega."}],"fields":[{"key":"icon","label":["Icono","Icône","Icon"],"type":"enum","options":["box","headset","truck","shield"],"option_labels":[["Caja","Colis","Box"],["Atención","Assistance","Support"],["Entrega","Livraison","Delivery"],["Confianza","Confiance","Trust"]]},{"key":"title","label":["Título","Titre","Title"],"type":"text","max":70},{"key":"text","label":["Descripción","Description","Description"],"type":"textarea","max":200}]}]},{"id":"content","label":["Contenido y páginas","Contenu et pages","Content and pages"],"fields":[{"key":"show_about","label":["Mostrar presentación","Afficher la présentation","Show about section"],"type":"boolean","default":true},{"key":"about_title","label":["Título de presentación","Titre de présentation","About title"],"type":"text","max":120,"default":"Tu negocio avanza. Nosotros lo acompañamos."},{"key":"about_text","label":["Sobre la empresa","À propos de l’entreprise","About the business"],"type":"textarea","max":2000,"default":"En GAMA hacemos más sencilla la búsqueda de productos para tu empresa. Nuestro catálogo reúne una selección práctica y un equipo dispuesto a ayudarte. Cuéntanos qué necesitas: prepararemos una propuesta para ti."},{"key":"about_image","label":["Imagen de presentación","Image de présentation","About image"],"type":"image","max":700000,"default":""},{"key":"show_faq","label":["Mostrar preguntas frecuentes","Afficher les questions fréquentes","Show FAQ"],"type":"boolean","default":true},{"key":"faq","label":["Preguntas frecuentes","Questions fréquentes","Frequently asked questions"],"type":"list","max":10,"default":[{"question":"¿Cómo solicito una cotización?","answer":"Añade productos a tu selección y envía la solicitud con tus datos de contacto. Nuestro equipo confirmará precios, disponibilidad y condiciones."},{"question":"¿Puedo consultar por otros productos?","answer":"Sí. Contacta con nuestro equipo y cuéntanos qué necesita tu empresa."}],"fields":[{"key":"question","label":["Pregunta","Question","Question"],"type":"text","max":180},{"key":"answer","label":["Respuesta","Réponse","Answer"],"type":"textarea","max":1000}]},{"key":"brands","label":["Marcas (opcional)","Marques (facultatif)","Brands (optional)"],"type":"list","max":12,"default":[],"fields":[{"key":"name","label":["Nombre","Nom","Name"],"type":"text","max":70},{"key":"image","label":["Imagen","Image","Image"],"type":"url","max":500}]},{"key":"terms_title","label":["Título de condiciones","Titre des conditions","Terms title"],"type":"text","max":100,"default":"Condiciones de la solicitud"},{"key":"terms_text","label":["Condiciones","Conditions","Terms"],"type":"textarea","max":6000,"default":"Enviar una solicitud no confirma una compra ni reserva productos. Nuestro equipo confirmará la disponibilidad, los precios finales y las condiciones de pago y entrega antes de acordar un pedido."},{"key":"privacy_title","label":["Título de privacidad","Titre de confidentialité","Privacy title"],"type":"text","max":100,"default":"Privacidad"},{"key":"privacy_text","label":["Información de privacidad","Informations de confidentialité","Privacy information"],"type":"textarea","max":6000,"default":"Utilizamos los datos de contacto que nos envías para atender tu solicitud. Puedes contactar con nosotros para consultar el uso de tus datos. No envíes datos bancarios ni información sensible a través de este formulario."},{"key":"footer_note","label":["Texto del pie de página","Texte du pied de page","Footer text"],"type":"textarea","max":350,"default":"Productos y atención para el día a día de tu empresa."}]},{"id":"contact","label":["Contacto","Contact","Contact"],"fields":[{"key":"show_contact","label":["Mostrar contacto","Afficher les coordonnées","Show contact section"],"type":"boolean","default":true},{"key":"contact_title","label":["Título de contacto","Titre de contact","Contact title"],"type":"text","max":120,"default":"Hablemos de lo que necesitas."},{"key":"contact_intro","label":["Texto de contacto","Texte de contact","Contact introduction"],"type":"textarea","max":500,"default":"Una consulta, una lista de productos o tu próximo pedido. Estamos para ayudarte."},{"key":"phone","label":["Teléfono","Téléphone","Phone"],"type":"text","max":60,"default":"(593-2) 250-1350"},{"key":"email","label":["Correo electrónico","Adresse e-mail","Email"],"type":"email","max":254,"default":""},{"key":"address","label":["Dirección","Adresse","Address"],"type":"textarea","max":300,"default":"Puerto Rico N27-108 y Selva Alegre, Quito"},{"key":"whatsapp","label":["WhatsApp (con código de país)","WhatsApp (avec indicatif du pays)","WhatsApp (with country code)"],"type":"text","max":30,"default":""},{"key":"opening_hours","label":["Horario de atención","Horaires d’ouverture","Opening hours"],"type":"textarea","max":300,"default":""},{"key":"map_url","label":["Enlace al mapa","Lien vers la carte","Map link"],"type":"url","max":500,"default":""},{"key":"facebook_url","label":["Facebook","Facebook","Facebook"],"type":"url","max":500,"default":""},{"key":"instagram_url","label":["Instagram","Instagram","Instagram"],"type":"url","max":500,"default":""},{"key":"linkedin_url","label":["LinkedIn","LinkedIn","LinkedIn"],"type":"url","max":500,"default":""}]},{"id":"publication","label":["Publicación y catálogo","Publication et catalogue","Publication and catalogue"],"fields":[{"key":"site_enabled","label":["Publicar el sitio","Publier le site","Publish website"],"type":"boolean","default":true},{"key":"website_url","label":["Dirección del sitio Cloudflare","Adresse du site Cloudflare","Cloudflare website address"],"type":"url","max":500,"default":""},{"key":"show_prices","label":["Mostrar precios","Afficher les prix","Show prices"],"type":"boolean","default":true},{"key":"price_display","label":["Presentación de precios","Affichage des prix","Price display"],"type":"enum","options":["with_tax","without_tax"],"option_labels":[["Con impuestos","Taxes comprises","Including tax"],["Sin impuestos","Hors taxes","Excluding tax"]],"default":"with_tax"},{"key":"enable_quotes","label":["Recibir solicitudes de cotización","Recevoir des demandes de devis","Accept quote requests"],"type":"boolean","default":true},{"key":"quote_label","label":["Nombre de la selección","Nom de la sélection","Selection label"],"type":"text","max":50,"default":"Mi cotización"},{"key":"default_sort","label":["Orden del catálogo","Tri du catalogue","Catalogue sorting"],"type":"enum","options":["featured","name","price_asc","price_desc"],"option_labels":[["Destacados primero","Sélection en premier","Featured first"],["Nombre","Nom","Name"],["Precio creciente","Prix croissant","Price ascending"],["Precio decreciente","Prix décroissant","Price descending"]],"default":"featured"},{"key":"page_size","label":["Productos por página","Produits par page","Products per page"],"type":"enum","options":["12","24","36"],"option_labels":[["12","12","12"],["24","24","24"],["36","36","36"]],"default":"12"},{"key":"seo_title","label":["Título para buscadores","Titre pour les moteurs de recherche","Search engine title"],"type":"text","max":100,"default":"Distribuidora GAMA | Productos para tu empresa en Quito"},{"key":"seo_description","label":["Descripción para buscadores","Description pour les moteurs de recherche","Search engine description"],"type":"textarea","max":320,"default":"Descubre el catálogo de Distribuidora GAMA. Productos para tu empresa, atención personalizada y solicitudes de cotización en Quito, Ecuador."}]}]}'::jsonb $$;
create function private.gama_storefront_defaults() returns jsonb language sql immutable set search_path='' as $$
 select jsonb_object_agg(f->>'key',f->'default') from jsonb_array_elements(private.gama_storefront_schema()->'groups') g cross join lateral jsonb_array_elements(g->'fields') f
$$;
revoke all on function private.gama_storefront_schema(),private.gama_storefront_defaults() from public,anon,authenticated;

create table private.website_public_settings (
 id boolean primary key default true check(id),version integer not null default 1,
 config jsonb not null check(jsonb_typeof(config)='object'),updated_at timestamptz not null default now(),updated_by uuid references auth.users(id) on delete set null
);
create index website_public_settings_actor on private.website_public_settings(updated_by);
create table private.website_public_connection (
 id boolean primary key default true check(id),token text not null,rotated_at timestamptz not null default now(),rotated_by uuid references auth.users(id) on delete set null
);
create index website_public_connection_actor on private.website_public_connection(rotated_by);
insert into private.website_public_connection(id,token) values(true,replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''));
insert into private.website_public_settings(id,config)
 select true,private.gama_storefront_defaults()||jsonb_build_object('phone',phone,'email',email,'address',address,'show_prices',show_prices) from private.website_settings where id;
alter table private.website_products add column public_visible boolean not null default false,
 add column public_featured boolean not null default false,add column public_title text not null default '' check(length(public_title)<=180),
 add column public_description text not null default '' check(length(public_description)<=3000),add column public_brand text not null default '' check(length(public_brand)<=80),
 add column public_badge text not null default '' check(length(public_badge)<=50),add column public_category_title text not null default '' check(length(public_category_title)<=100);
-- Reuse only the user's existing preview selection, not every active ERP item.
update private.website_products set public_visible=visible,public_featured=featured;
create index website_public_selection on private.website_products(public_visible,public_featured,product_id);
create table private.website_public_inquiries (
 id uuid primary key default gen_random_uuid(),number bigint generated always as identity unique,
 request_key uuid not null unique,payload jsonb not null,contact_name text not null,email text not null,phone text not null default '',company text not null default '',notes text not null default '',
 lines jsonb not null,currency text not null,total numeric(18,2) not null,visitor_hash text not null,consent_at timestamptz not null,
 status text not null default 'new' check(status in ('new','reviewed','archived')),internal_notes text not null default '' check(length(internal_notes)<=2000),
 created_at timestamptz not null default now(),reviewed_at timestamptz,reviewed_by uuid references auth.users(id) on delete set null
);
create index website_public_inquiries_time on private.website_public_inquiries(created_at desc,id);
create index website_public_inquiries_visitor on private.website_public_inquiries(visitor_hash,created_at desc);
create index website_public_inquiries_email on private.website_public_inquiries(email,created_at desc);
create index website_public_inquiries_actor on private.website_public_inquiries(reviewed_by);
alter table private.website_public_settings enable row level security;
alter table private.website_public_connection enable row level security;
alter table private.website_public_inquiries enable row level security;
revoke all on private.website_public_settings,private.website_public_connection,private.website_public_inquiries from public,anon,authenticated;

create function private.gama_storefront_field_valid(v jsonb,f jsonb) returns boolean language plpgsql immutable set search_path='' as $$
declare kind text:=f->>'type';s text:=v#>>'{}';item jsonb;sub jsonb;k text;
begin
 if v is null then return false;end if;
 if kind='boolean' then return jsonb_typeof(v)='boolean';end if;
 if kind='list' then
  if jsonb_typeof(v)<>'array' or jsonb_array_length(v)>(f->>'max')::integer then return false;end if;
  for item in select value from jsonb_array_elements(v) loop
   if jsonb_typeof(item)<>'object' then return false;end if;
   for k in select jsonb_object_keys(item) loop if not exists(select 1 from jsonb_array_elements(f->'fields') z where z->>'key'=k) then return false;end if;end loop;
   for sub in select value from jsonb_array_elements(f->'fields') loop if not private.gama_storefront_field_valid(item->(sub->>'key'),sub) then return false;end if;end loop;
  end loop;return true;
 end if;
 if jsonb_typeof(v)<>'string' or length(s)>coalesce((f->>'max')::integer,500) then return false;end if;
 if kind='color' then return s ~ '^#[0-9A-Fa-f]{6}$';
 elsif kind='enum' then return (f->'options') ? s;
 elsif kind='url' then return s='' or s ~ '^https://[^[:space:]<>"'']+$';
 elsif kind='link' then return s ~ '^(https://[^[:space:]<>"'']+|#[a-zA-Z][a-zA-Z0-9_-]*|\?category=[^[:space:]<>"'']+)$';
 elsif kind='image' then return s='' or s ~ '^https://[^[:space:]<>"'']+$' or s ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$';
 elsif kind='email' then return s='' or s ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$';end if;
 return true;
end $$;
create function private.gama_storefront_config_valid(cfg jsonb) returns boolean language plpgsql immutable set search_path='' as $$
declare f jsonb;k text;fields jsonb;
begin
 if jsonb_typeof(cfg) is distinct from 'object' or octet_length(cfg::text)>2000000 then return false;end if;
 select jsonb_agg(f0) into fields from jsonb_array_elements(private.gama_storefront_schema()->'groups') g cross join lateral jsonb_array_elements(g->'fields') f0;
 for k in select jsonb_object_keys(cfg) loop if not exists(select 1 from jsonb_array_elements(fields) f1 where f1->>'key'=k) then return false;end if;end loop;
 for f in select value from jsonb_array_elements(fields) loop if not private.gama_storefront_field_valid(cfg->(f->>'key'),f) then return false;end if;end loop;
 return length(btrim(cfg->>'brand_name'))>0 and length(btrim(cfg->>'hero_title'))>0 and (cfg->>'whatsapp'='' or cfg->>'whatsapp' ~ '^\+?[0-9 ()-]{8,30}$');
end $$;
revoke all on function private.gama_storefront_field_valid(jsonb,jsonb),private.gama_storefront_config_valid(jsonb) from public,anon,authenticated;

-- Pure public projection. Purchase costs, exact stock, supplier IDs and staff data are excluded.
create function private.gama_storefront_items() returns table(id uuid,name text,reference text,category text,category_title text,brand text,badge text,description text,featured boolean,unit_price numeric,tax_rate numeric,order_minimum numeric,order_multiple numeric,has_photo boolean) language sql stable set search_path='' as $$
 select p.id,coalesce(nullif(w.public_title,''),p.name),p.reference,coalesce(nullif(p.category,''),'Otros productos'),coalesce(nullif(w.public_category_title,''),coalesce(nullif(p.category,''),'Otros productos')),
 w.public_brand,w.public_badge,coalesce(nullif(w.public_description,''),w.description),w.public_featured,
 case when (s.config->>'show_prices')::boolean and p.sale_price>0 then p.sale_price end,
 case when (s.config->>'show_prices')::boolean and p.sale_price>0 then p.tax_rate end,
 coalesce(p.order_minimum,0),coalesce(p.order_multiple,0),coalesce(p.photo_data ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$',false)
 from public.products p join private.website_products w on w.product_id=p.id and w.public_visible cross join private.website_public_settings s where p.active and s.id
$$;
revoke all on function private.gama_storefront_items() from public,anon,authenticated;

create function storefront_api.gama_storefront(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg jsonb;curr text;term text;cat text;brand_filter text;sortby text;off integer;lim integer;count_items integer;rows jsonb;req uuid;prior private.website_public_inquiries;payload jsonb;visitor text;secret text;
 line jsonb;prod public.products;pid uuid;qty numeric;net numeric;tax numeric;total numeric:=0;lines jsonb:='[]';seen uuid[]:='{}';rid uuid;seq bigint;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>24000 then raise exception 'WEBSITE_INVALID_DATA';end if;
 select config into cfg from private.website_public_settings where id;
 select coalesce(currency,'USD') into curr from public.company_settings limit 1;curr:=coalesce(curr,'USD');
 if not coalesce((cfg->>'site_enabled')::boolean,false) then
  if p_action='bootstrap' then return jsonb_build_object('paused',true,'settings',jsonb_build_object('brand_name',cfg->>'brand_name','phone',cfg->>'phone','email',cfg->>'email'));end if;
  raise exception 'WEBSITE_PUBLIC_PAUSED';
 end if;
 if p_action='bootstrap' then
  return jsonb_build_object('paused',false,'settings',cfg,'currency',curr,'total',(select count(*) from private.gama_storefront_items()),
   'categories',coalesce((select jsonb_agg(to_jsonb(z)) from(select category,min(category_title) title,count(*) count,min(id::text) photo_id from private.gama_storefront_items() group by category order by category) z),'[]'),
   'brands',coalesce((select jsonb_agg(brand order by brand) from(select distinct brand from private.gama_storefront_items() where brand<>'') z),'[]'),
   'featured',coalesce((select jsonb_agg(to_jsonb(z)) from(select * from private.gama_storefront_items() where featured order by name,id limit 8) z),'[]'));
 elsif p_action='catalog' then
  term:=left(coalesce(p_data->>'search',''),100);cat:=coalesce(p_data->>'category','');brand_filter:=coalesce(p_data->>'brand','');sortby:=coalesce(nullif(p_data->>'sort',''),cfg->>'default_sort');
  if sortby not in ('featured','name','price_asc','price_desc') then raise exception 'WEBSITE_INVALID_DATA';end if;
  off:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));lim:=greatest(1,least(coalesce((p_data->>'limit')::integer,(cfg->>'page_size')::integer),36));
  select count(*) into count_items from private.gama_storefront_items() i where (term='' or strpos(lower(i.name||' '||coalesce(i.reference,'')||' '||i.brand),lower(term))>0) and (cat='' or i.category=cat) and (brand_filter='' or i.brand=brand_filter);
  select coalesce(jsonb_agg(to_jsonb(z)),'[]') into rows from(select * from private.gama_storefront_items() i where (term='' or strpos(lower(i.name||' '||coalesce(i.reference,'')||' '||i.brand),lower(term))>0) and (cat='' or i.category=cat) and (brand_filter='' or i.brand=brand_filter)
   order by case when sortby='featured' then featured end desc nulls last,case when sortby='price_asc' then unit_price end asc nulls last,case when sortby='price_desc' then unit_price end desc nulls last,name,id limit lim offset off) z;
  return jsonb_build_object('items',rows,'total',count_items,'offset',off,'limit',lim,'currency',curr);
 elsif p_action='product' then
  select to_jsonb(i) into rows from private.gama_storefront_items() i where id=(p_data->>'id')::uuid;
  if rows is null then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;return jsonb_build_object('item',rows,'currency',curr);
 elsif p_action='photos' then
  if jsonb_typeof(p_data->'ids') is distinct from 'array' or jsonb_array_length(p_data->'ids')>24 then raise exception 'WEBSITE_INVALID_DATA';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'photo_data',p.photo_data)) from public.products p join private.website_products w on w.product_id=p.id and w.public_visible where p.active and p.id in(select value::uuid from jsonb_array_elements_text(p_data->'ids')) and p.photo_data ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$'),'[]');
 elsif p_action='submit' then
  if not (cfg->>'enable_quotes')::boolean then raise exception 'WEBSITE_QUOTES_DISABLED';end if;
  select token into secret from private.website_public_connection where id;
  if coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb->>'x-coco-site-token' is distinct from secret then raise exception 'WEBSITE_SERVER_KEY_REQUIRED';end if;
  if coalesce(p_data->>'website','')<>'' then raise exception 'WEBSITE_INVALID_DATA';end if;
  visitor:=left(coalesce(p_data->>'visitor',''),200);if visitor='' then raise exception 'WEBSITE_VISITOR_REQUIRED';end if;visitor:=md5(secret||visitor);
  req:=nullif(p_data->>'request_key','')::uuid;if req is null then raise exception 'WEBSITE_REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('public-web:'||req,0));payload:=p_data-'request_key'-'visitor'-'website';select * into prior from private.website_public_inquiries where request_key=req;
  if found then if prior.payload is distinct from payload then raise exception 'WEBSITE_REQUEST_KEY_REUSED';end if;return jsonb_build_object('reference','WEB-'||lpad(prior.number::text,8,'0'));end if;
  if (p_data->>'consent') is distinct from 'true' or length(btrim(coalesce(p_data->>'contact_name',''))) not between 2 and 120 or length(coalesce(p_data->>'email',''))>254 or coalesce(p_data->>'email','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
   or length(coalesce(p_data->>'phone',''))>60 or length(coalesce(p_data->>'company',''))>160 or length(coalesce(p_data->>'notes',''))>2000 then raise exception 'WEBSITE_CONTACT_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('public-web-visitor:'||visitor,0));
  if (select count(*) from private.website_public_inquiries where visitor_hash=visitor and created_at>now()-interval '30 minutes')>=8 or (select count(*) from private.website_public_inquiries where email=lower(btrim(p_data->>'email')) and created_at>now()-interval '1 hour')>=5 or (select count(*) from private.website_public_inquiries where created_at>now()-interval '1 day')>=2000 then raise exception 'WEBSITE_RATE_LIMIT';end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 30 then raise exception 'WEBSITE_INVALID_LINES';end if;
  for line in select value from jsonb_array_elements(p_data->'lines') loop
   pid:=(line->>'product_id')::uuid;qty:=(line->>'quantity')::numeric;
   if pid=any(seen) then raise exception 'WEBSITE_DUPLICATE_PRODUCT';end if;seen:=array_append(seen,pid);
   if qty is null or qty<=0 or qty>100000 or qty<>round(qty,3) then raise exception 'WEBSITE_INVALID_QUANTITY';end if;
   select p.* into prod from public.products p join private.website_products w on w.product_id=p.id and w.public_visible where p.id=pid and p.active;
   if not found then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;
   if qty<coalesce(prod.order_minimum,0) or (coalesce(prod.order_multiple,0)>0 and mod(qty,prod.order_multiple)<>0) then raise exception 'WEBSITE_PACK_QUANTITY';end if;
   net:=round(qty*coalesce(prod.sale_price,0),2);tax:=round(net*coalesce(prod.tax_rate,0)/100,2);total:=total+net+tax;
   lines:=lines||jsonb_build_array(jsonb_build_object('product_id',prod.id,'reference',prod.reference,'name',prod.name,'quantity',qty,'unit_price',prod.sale_price,'tax_rate',prod.tax_rate,'subtotal',net,'tax',tax,'total',net+tax,'price_to_confirm',coalesce(prod.sale_price,0)<=0));
  end loop;
  insert into private.website_public_inquiries(request_key,payload,contact_name,email,phone,company,notes,lines,currency,total,visitor_hash,consent_at)
   values(req,payload,btrim(p_data->>'contact_name'),lower(btrim(p_data->>'email')),btrim(coalesce(p_data->>'phone','')),btrim(coalesce(p_data->>'company','')),btrim(coalesce(p_data->>'notes','')),lines,curr,total,visitor,now()) returning id,number into rid,seq;
  return jsonb_build_object('reference','WEB-'||lpad(seq::text,8,'0'));
 end if;
 raise exception 'WEBSITE_INVALID_ACTION';
end $$;
revoke all on function storefront_api.gama_storefront(text,jsonb) from public;
grant execute on function storefront_api.gama_storefront(text,jsonb) to anon,authenticated;
create function public.gama_storefront(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$ select storefront_api.gama_storefront(p_action,p_data) $$;
revoke all on function public.gama_storefront(text,jsonb) from public;
grant execute on function public.gama_storefront(text,jsonb) to anon,authenticated;

alter function private.gama_website(text,jsonb) rename to gama_website_preview;
create function private.gama_website(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();cfg private.website_public_settings;fields jsonb;item private.website_products;pid uuid;off integer;lim integer;term text;token text;
begin
 if actor is null or not private.erp_module_allowed('website',array['administrador']) or not private.erp_mfa_ok() then raise exception 'WEBSITE_ACCESS_DENIED';end if;
 if p_action not like 'public_%' then return private.gama_website_preview(p_action,p_data);end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>2100000 then raise exception 'WEBSITE_INVALID_DATA';end if;
 select * into cfg from private.website_public_settings where id;
 if p_action='public_settings' then return jsonb_build_object('schema',private.gama_storefront_schema(),'config',cfg.config,'version',cfg.version,'selected',(select count(*) from private.website_products w join public.products p on p.id=w.product_id where w.public_visible and p.active),'unread',(select count(*) from private.website_public_inquiries where status='new'),'categories',(select coalesce(jsonb_agg(c order by c),'[]') from(select distinct coalesce(nullif(category,''),'Otros productos') c from public.products where active)z));
 elsif p_action='public_save_settings' then
  if not private.erp_action_allowed('website','edit') then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  if not private.gama_storefront_config_valid(p_data->'config') then raise exception 'WEBSITE_INVALID_CONFIGURATION';end if;
  update private.website_public_settings set config=p_data->'config',version=version+1,updated_at=now(),updated_by=actor where id and version=(p_data->>'version')::integer returning * into cfg;
  if not found then raise exception 'WEBSITE_SETTINGS_CHANGED';end if;return jsonb_build_object('config',cfg.config,'version',cfg.version);
 elsif p_action in ('public_connection','public_rotate_connection') then
  if not private.erp_action_allowed('website','edit') then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  if p_action='public_rotate_connection' then update private.website_public_connection set token=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''),rotated_at=now(),rotated_by=actor where id;end if;
  select c.token into token from private.website_public_connection c where id;return jsonb_build_object('token',token);
 elsif p_action in ('public_products','public_inquiries') then
  off:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));lim:=greatest(1,least(coalesce((p_data->>'limit')::integer,20),60));term:=left(coalesce(p_data->>'search',''),100);
  if p_action='public_inquiries' then return jsonb_build_object('total',(select count(*) from private.website_public_inquiries),'items',coalesce((select jsonb_agg(to_jsonb(z)) from(select id,'WEB-'||lpad(number::text,8,'0') reference,contact_name,email,phone,company,notes,lines,currency,total,status,internal_notes,created_at,consent_at from private.website_public_inquiries order by created_at desc,id limit lim offset off)z),'[]'));end if;
  if not private.erp_module_allowed('products',array['administrador']) then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  return jsonb_build_object('total',(select count(*) from public.products p where active and (term='' or strpos(lower(p.name||' '||coalesce(p.reference,'')),lower(term))>0) and (coalesce(p_data->>'category','')='' or coalesce(nullif(p.category,''),'Otros productos')=p_data->>'category')),
   'items',coalesce((select jsonb_agg(to_jsonb(z)) from(select p.id,p.name,p.reference,p.category,p.sale_price,p.tax_rate,coalesce(w.version,0) version,coalesce(w.public_visible,false) public_visible,coalesce(w.public_featured,false) public_featured,coalesce(w.public_title,'') public_title,coalesce(w.public_description,'') public_description,coalesce(w.public_brand,'') public_brand,coalesce(w.public_badge,'') public_badge,coalesce(w.public_category_title,'') public_category_title from public.products p left join private.website_products w on w.product_id=p.id where p.active and (term='' or strpos(lower(p.name||' '||coalesce(p.reference,'')),lower(term))>0) and (coalesce(p_data->>'category','')='' or coalesce(nullif(p.category,''),'Otros productos')=p_data->>'category') order by p.name,p.id limit lim offset off)z),'[]'));
 elsif p_action='public_save_product' then
  if not private.erp_action_allowed('website','edit') or not private.erp_module_allowed('products',array['administrador']) then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  pid:=(p_data->>'id')::uuid;perform pg_advisory_xact_lock(hashtextextended('website-product:'||pid,0));
  if not exists(select 1 from public.products where id=pid and active) then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;
  select * into item from private.website_products where product_id=pid;
  if coalesce(item.version,0) is distinct from (p_data->>'version')::integer then raise exception 'WEBSITE_PRODUCT_CHANGED';end if;
  if jsonb_typeof(p_data->'public_visible') is distinct from 'boolean' or jsonb_typeof(p_data->'public_featured') is distinct from 'boolean' then raise exception 'WEBSITE_INVALID_DATA';end if;
  insert into private.website_products(product_id,public_visible,public_featured,public_title,public_description,public_brand,public_badge,public_category_title,updated_by)
   values(pid,(p_data->>'public_visible')::boolean,(p_data->>'public_featured')::boolean,coalesce(p_data->>'public_title',''),coalesce(p_data->>'public_description',''),coalesce(p_data->>'public_brand',''),coalesce(p_data->>'public_badge',''),coalesce(p_data->>'public_category_title',''),actor)
   on conflict(product_id) do update set public_visible=excluded.public_visible,public_featured=excluded.public_featured,public_title=excluded.public_title,public_description=excluded.public_description,public_brand=excluded.public_brand,public_badge=excluded.public_badge,public_category_title=excluded.public_category_title,version=private.website_products.version+1,updated_at=now(),updated_by=actor;
  return jsonb_build_object('ok',true);
 elsif p_action='public_review' then
  if not private.erp_action_allowed('website','edit') then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  if coalesce(p_data->>'status','') not in ('reviewed','archived','new') then raise exception 'WEBSITE_INVALID_DATA';end if;
  update private.website_public_inquiries set status=p_data->>'status',internal_notes=coalesce(p_data->>'internal_notes',''),reviewed_at=now(),reviewed_by=actor where id=(p_data->>'id')::uuid;
  if not found then raise exception 'WEBSITE_INQUIRY_NOT_FOUND';end if;return jsonb_build_object('ok',true);
 end if;
 raise exception 'WEBSITE_INVALID_ACTION';
end $$;
revoke all on function private.gama_website(text,jsonb),private.gama_website_preview(text,jsonb) from public,anon;
grant execute on function private.gama_website(text,jsonb) to authenticated;
notify pgrst,'reload schema';
