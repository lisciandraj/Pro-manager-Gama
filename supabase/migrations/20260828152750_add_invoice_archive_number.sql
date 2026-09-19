create sequence if not exists public.gama_invoice_archive_seq minvalue 1 start 1;
alter table public.invoices add column if not exists archive_number bigint;
select setval('public.gama_invoice_archive_seq', greatest(coalesce((select max(archive_number) from public.invoices),0),1), case when coalesce((select max(archive_number) from public.invoices),0) > 0 then true else false end);
update public.invoices set archive_number=nextval('public.gama_invoice_archive_seq') where archive_number is null;
select setval('public.gama_invoice_archive_seq', greatest(coalesce((select max(archive_number) from public.invoices),0),1), true) where exists (select 1 from public.invoices);
alter table public.invoices alter column archive_number set default nextval('public.gama_invoice_archive_seq');
create unique index if not exists invoices_archive_number_key on public.invoices(archive_number);
