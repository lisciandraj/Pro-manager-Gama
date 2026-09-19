-- Devoluciones: lo que vuelve del cliente y lo que se devuelve al proveedor.
--
-- Antes de crear nada se miró lo que había. GAMA ya tenía customer_returns,
-- customer_return_credits y customer_return_photos, con toda la mecánica de
-- almacén resuelta —zona de cuarentena, reserva de retención, movimientos de
-- stock— dentro de gama_fulfillment_action. Lo que no tenía: cabecera de
-- documento, varias líneas por devolución, lado proveedor, reembolsos, y una
-- pantalla propia: vivía enterrado en el dossier del pedido.
--
-- Las tres tablas estaban VACÍAS: cero devoluciones, cero abonos. Así que en
-- vez de dejar dos sistemas conviviendo —que es justo lo que el encargo
-- prohíbe— se reordenan en uno solo, conservando la lógica de almacén que sí
-- funcionaba, y se retiran las tablas viejas.

-- ------------------------------------------------------------- cabecera
create sequence public.gama_return_order_seq;
create table public.return_orders (
 id uuid primary key default gen_random_uuid(),
 number text not null unique default ('RET-'||lpad(nextval('public.gama_return_order_seq')::text,6,'0')),
 -- Un solo documento para los dos sentidos: el usuario aprende una pantalla.
 kind text not null check(kind in ('customer','supplier')),
 -- Cinco estados y no más. Los de cliente y los de proveedor comparten los
 -- extremos (por tratar → … → cerrado / anulado) y sólo difieren en el medio.
 status text not null default 'to_process' check(status in
  ('to_process','received','processed','shipped','credited','closed','cancelled')),

 customer_id uuid references public.customers(id),
 order_id uuid references public.sales_orders(id),
 delivery_id uuid references public.sales_deliveries(id),
 invoice_id uuid references public.external_invoices(id),

 supplier_id uuid references public.suppliers(id),
 purchase_order_id uuid references public.purchase_orders(id),
 supplier_invoice_id uuid references public.supplier_invoices(id),

 reason text not null check(reason in
  ('defective','damaged','wrong_product','wrong_quantity','order_error','commercial','other')),
 notes text,
 -- Nada obliga a una decisión financiera: un producto al rebut puede acabar
 -- en reembolso, y una devolución comercial puede no mover un céntimo.
 financial_action text not null default 'none'
  check(financial_action in ('none','credit','refund','store_credit')),

 -- Expedición al proveedor. Sólo la fecha es obligatoria cuando se expide.
 carrier text, tracking text, shipped_on date,

 received_at timestamptz, processed_at timestamptz, closed_at timestamptz,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),

 -- Cada sentido exige su documento de origen y prohíbe el del otro.
 check(kind<>'customer' or (customer_id is not null and supplier_id is null
   and purchase_order_id is null and supplier_invoice_id is null)),
 check(kind<>'supplier' or (supplier_id is not null and customer_id is null
   and order_id is null and delivery_id is null and invoice_id is null)),
 check(kind<>'customer' or status in ('to_process','received','processed','closed','cancelled')),
 check(kind<>'supplier' or status in ('to_process','shipped','credited','closed','cancelled'))
);
create index return_orders_kind_status on public.return_orders(kind,status);
create index return_orders_customer on public.return_orders(customer_id);
create index return_orders_supplier on public.return_orders(supplier_id);
create index return_orders_created on public.return_orders(created_at desc);

-- ------------------------------------------------------------- líneas
-- Una línea por producto devuelto. El precio se copia del documento de origen
-- al crearla: un abono emitido hace un año tiene que poder recalcularse aunque
-- la tarifa haya cambiado desde entonces.
create table public.return_lines (
 id uuid primary key default gen_random_uuid(),
 return_id uuid not null references public.return_orders(id) on delete cascade,
 product_id uuid not null references public.products(id),
 quantity numeric(12,3) not null check(quantity>0),
 unit_price numeric(12,4) not null default 0 check(unit_price>=0),
 tax_rate numeric(6,3) not null default 0 check(tax_rate>=0 and tax_rate<=100),

 delivery_line_id uuid references public.sales_delivery_lines(id),
 purchase_order_line_id uuid references public.purchase_order_lines(id),

 -- Qué se hace con el producto. Se decide al procesar, no al crear.
 disposition text check(disposition in ('restocked','scrapped','to_supplier')),
 quarantine_location_id uuid references public.warehouse_locations(id),
 hold_reservation_id uuid references public.stock_reservations(id),
 processed_at timestamptz,
 notes text,
 created_at timestamptz not null default now(),

 check(delivery_line_id is not null or purchase_order_line_id is not null)
);
create index return_lines_return on public.return_lines(return_id);
create index return_lines_product on public.return_lines(product_id);
create index return_lines_delivery_line on public.return_lines(delivery_line_id);
create index return_lines_purchase_line on public.return_lines(purchase_order_line_id);

-- ------------------------------------------------------------- abonos
create sequence public.gama_credit_note_seq;
create table public.return_credits (
 id uuid primary key default gen_random_uuid(),
 number text not null unique default ('AV-'||lpad(nextval('public.gama_credit_note_seq')::text,6,'0')),
 return_id uuid not null references public.return_orders(id) on delete cascade,
 -- El abono de cliente cuelga de la factura original. El de proveedor llega a
 -- menudo sin que GAMA tenga la suya registrada, así que va suelto; lo que la
 -- API exige (INVOICE_REQUIRED) es la factura en el abono de cliente.
 invoice_id uuid references public.external_invoices(id),
 supplier_invoice_id uuid references public.supplier_invoices(id),
 supplier_reference text,
 amount numeric(14,2) not null check(amount>0),
 issued_on date not null default current_date,
 notes text,
 filename text, mime_type text, data_url text,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 check(not (invoice_id is not null and supplier_invoice_id is not null))
);
create index return_credits_return on public.return_credits(return_id);
create index return_credits_invoice on public.return_credits(invoice_id);

-- ------------------------------------------------------------- reembolsos
create table public.return_refunds (
 id uuid primary key default gen_random_uuid(),
 return_id uuid not null references public.return_orders(id) on delete cascade,
 amount numeric(14,2) not null check(amount>0),
 paid_at date not null default current_date,
 method text not null,
 reference text,
 notes text,
 request_key uuid unique,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now()
);
create index return_refunds_return on public.return_refunds(return_id);

-- ------------------------------------------------------------- fotos
create table public.return_files (
 id uuid primary key default gen_random_uuid(),
 return_id uuid not null references public.return_orders(id) on delete cascade,
 filename text not null,
 mime_type text check(mime_type in ('image/png','image/jpeg','image/webp','application/pdf')),
 data_url text not null,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now()
);
create index return_files_return on public.return_files(return_id);

-- --------------------------------------------- lectura, escritura, auditoría
-- Se lee desde la pantalla; se escribe sólo por la API. Supabase concede todo
-- sobre una tabla nueva a authenticated y TRUNCATE no lo para la RLS, así que
-- se retira y se devuelve únicamente el SELECT.
alter table public.return_orders enable row level security;
alter table public.return_lines enable row level security;
alter table public.return_credits enable row level security;
alter table public.return_refunds enable row level security;
alter table public.return_files enable row level security;

do $grants$
declare t text;
begin
 foreach t in array array['return_orders','return_lines','return_credits','return_refunds','return_files'] loop
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format($p$create policy ret_read_%1$s on public.%1$I for select to authenticated
    using(coalesce(private.current_user_role(),'') in ('administrador','comercial','almacenero'))$p$,t);
  execute format('create trigger ret_audit_%1$s after insert or update or delete on public.%1$I
    for each row execute function private.gama_audit_row()',t);
 end loop;
end $grants$;

-- El expediente del pedido acoge la devolución: mismo dossier, prefijo DEV.
alter table public.gama_document_references drop constraint gama_document_references_table_name_check;
alter table public.gama_document_references add constraint gama_document_references_table_name_check
 check(table_name in ('customer_requests','invoices','sales_orders','fulfillment_preparations',
  'fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices',
  'external_invoice_payments','customer_returns','return_orders'));
create trigger gama_document_reference after insert or update on public.return_orders
 for each row execute function private.gama_document_reference_trigger();
