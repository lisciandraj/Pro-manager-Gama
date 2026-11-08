do $pause$ declare selected_job bigint;begin
 if (select count(*) from private.coco_bootstrap_sources)<>306
 or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e')
 or to_regclass('private.coco_environment') is not null
 or exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 then raise exception 'NEW_PRODUCTION_BOOTSTRAP_IDENTITY_REQUIRED';end if;
 if (select count(*) from cron.job where jobname='coco-automation')<>1 then raise exception 'BOOTSTRAP_AUTOMATION_SCHEDULER_MISMATCH';end if;
 select jobid into selected_job from cron.job where jobname='coco-automation' and schedule='* * * * *' and command='select private.automation_tick();' and active;
 if selected_job is null then raise exception 'BOOTSTRAP_AUTOMATION_SCHEDULER_MISMATCH';end if;
 perform cron.alter_job(selected_job,active:=false);
end $pause$;
select jobname,schedule,command,active from cron.job where jobname='coco-automation';
