-- Una revisión prevista por kilometraje no tiene fecha de vencimiento. Con la
-- regla estándar dos NULL son distintos, así que el "on conflict" no veía el
-- aviso anterior y la tarea programada lo repetía en cada pasada.
alter table public.fleet_alert_log drop constraint fleet_alert_log_alert_key_due_on_key;
alter table public.fleet_alert_log add constraint fleet_alert_log_alert_key_due_on_key
 unique nulls not distinct (alert_key,due_on);
