create extension if not exists pg_cron with schema pg_catalog;

-- Comprobación diaria de vencimientos a las 07:00 de Guayaquil (12:00 UTC).
-- El aviso se entrega en el Centro de acción; fleet_alert_log evita repetirlo.
select cron.schedule('gama-fleet-deadlines','0 12 * * *',
 $$select private.gama_fleet_check_deadlines(30)$$);
