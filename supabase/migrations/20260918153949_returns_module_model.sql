do $guard$
begin
 if (select count(*) from public.customer_returns)>0
  or (select count(*) from public.customer_return_credits)>0 then
  raise exception 'RETURNS_LEGACY_NOT_EMPTY';
 end if;
end $guard$;

create sequence public.gama_return_order_seq;
create table public.return_orders (
 id uuid primary key default gen_random_uuid(),
 number text not null unique default ('RET-'||lpad(nextval('public.gama_return_order_seq')::text,6,'0')),
 kind text not null check(kind in ('customer','supplier')),
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
 financial_action text not null default 'none'
  check(financial_action in ('none','credit','refund','store_credit')),
 carrier text, tracking text, shipped_on date,
 received_at timestamptz, processed_at timestamptz, closed_at timestamptz,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
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

create table public.return_lines (
 id uuid primary key default gen_random_uuid(),
 return_id uuid not null references public.return_orders(id) on delete cascade,
 product_id uuid not null references public.products(id),
 quantity numeric(12,3) not null check(quantity>0),
 unit_price numeric(12,4) not null default 0 check(unit_price>=0),
 tax_rate numeric(6,3) not null default 0 check(tax_rate>=0 and tax_rate<=100),
 delivery_line_id uuid references public.sales_delivery_lines(id),
 purchase_order_line_id uuid references public.purchase_order_lines(id),
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

create sequence public.gama_credit_note_seq;
create table public.return_credits (
 id uuid primary key default gen_random_uuid(),
 number text not null unique default ('AV-'||lpad(nextval('public.gama_credit_note_seq')::text,6,'0')),
 return_id uuid not null references public.return_orders(id) on delete cascade,
 invoice_id uuid references public.external_invoices(id),
 supplier_invoice_id uuid references public.supplier_invoices(id),
 supplier_reference text,
 amount numeric(14,2) not null check(amount>0),
 issued_on date not null default current_date,
 notes text,
 filename text, mime_type text, data_url text,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 check((invoice_id is not null) <> (supplier_invoice_id is not null))
);
create index return_credits_return on public.return_credits(return_id);
create index return_credits_invoice on public.return_credits(invoice_id);

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
