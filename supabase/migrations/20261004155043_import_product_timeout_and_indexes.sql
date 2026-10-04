-- PostgREST hoists the public RPC's statement_timeout before starting its query.
-- Keep the usual role deadlines; only import preparation/application gets 60s.
alter function public.gama_import_batch(text,jsonb) set statement_timeout = '60s';

-- Match the import's case/space-insensitive identity checks, including archived
-- products. These are deliberately non-unique: ambiguous identities still fail.
create index products_import_barcode_normalized_idx on public.products (lower(btrim(barcode)));
create index products_import_reference_normalized_idx on public.products (lower(btrim(reference)));
create index products_import_name_normalized_idx on public.products (lower(btrim(name)));
analyze public.products;

-- Refresh the RPC settings cached by the REST API.
notify pgrst, 'reload schema';
