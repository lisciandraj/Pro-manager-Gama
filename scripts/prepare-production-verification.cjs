/* Produce a read-only, fail-closed verification for the authorized first install.
 * No database connection, data deletion, environment assignment or activation.
 */
const fs=require('node:fs'),path=require('node:path');
const {digest}=require('./production-bootstrap-sql.cjs');
const {loadSnapshot,sourceCount,installation}=require('./production-bootstrap-snapshot.cjs');
const root=path.resolve(__dirname,'..'),target='vhutzdfatijjpahsqkne';
const literal=s=>"'"+String(s).replaceAll("'","''")+"'";
function prepare(project,{outputDirectory=path.join(root,'.build/production-verification')}={}){
 if(project!==target)throw Error('Only the authorized new production project may be verified');
 const directory=path.join(root,'supabase/migrations');
 const snapshot=loadSnapshot(directory),sources=snapshot.sources.map(({sql,...source})=>source);
 const derived=digest(sources.map(x=>x.file+':'+x.derived_sha256).join('\n'));
 const guardFile=path.join(directory,sources.at(-1).file),guard=fs.readFileSync(guardFile,'utf8');
 const list=guard.match(/defaults text\[\]:=array\[([\s\S]*?)\];/);
 if(!list||!sources.at(-1).file.endsWith('_coco_environment_isolation.sql'))throw Error('Environment guard defaults unavailable');
 const defaults=[...list[1].matchAll(/'([^']+)'/g)].map(x=>x[1]);
 if(!defaults.includes('private.coco_bootstrap_installation'))throw Error('Bootstrap metadata must be an explicit system default');
 const sql=`-- Read-only verification; do not use against the development project.
-- Canonical source fingerprint: ${installation}
-- Derived schema-only fingerprint: ${derived}
do $verify$
declare r record;has_rows boolean;actual text;defaults text[]:=array[${defaults.map(literal).join(',')}];
begin
 if (select count(*) from private.coco_bootstrap_installation)<>1
 or not exists(select 1 from private.coco_bootstrap_installation where project_ref=${literal(target)} and installation=${literal(installation)})
 then raise exception 'PRODUCTION_BOOTSTRAP_IDENTITY_MISMATCH';end if;
 if (select count(*) from private.coco_bootstrap_sources)<>${sourceCount}
 or exists(select 1 from private.coco_bootstrap_sources where project_ref<>${literal(target)} or installation<>${literal(installation)})
 then raise exception 'PRODUCTION_BOOTSTRAP_SOURCE_COUNT_MISMATCH';end if;
 select encode(sha256(convert_to(string_agg(version||'_'||name||'.sql:'||source_sha256,E'\\n' order by version),'UTF8')),'hex')
 into actual from private.coco_bootstrap_sources;
 if actual is distinct from ${literal(installation)} then raise exception 'PRODUCTION_BOOTSTRAP_SOURCE_HASH_MISMATCH';end if;
 select encode(sha256(convert_to(string_agg(version||'_'||name||'.sql:'||derived_sha256,E'\\n' order by version),'UTF8')),'hex')
 into actual from private.coco_bootstrap_sources;
 if actual is distinct from ${literal(derived)} then raise exception 'PRODUCTION_BOOTSTRAP_DERIVED_HASH_MISMATCH';end if;
 if not exists(select 1 from private.coco_environment where id and environment='unassigned' and release is null)
 then raise exception 'PRODUCTION_BOOTSTRAP_ALREADY_ASSIGNED';end if;
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 then raise exception 'EMPTY_PRODUCTION_AUTH_AND_FILES_REQUIRED';end if;
 if exists(select 1 from storage.buckets where public) then raise exception 'PRODUCTION_PUBLIC_BUCKET_FORBIDDEN';end if;
 if exists(select 1 from pg_tables t join pg_namespace n on n.nspname=t.schemaname
  join pg_class c on c.relnamespace=n.oid and c.relname=t.tablename
  where t.schemaname='public' and not c.relrowsecurity) then raise exception 'PRODUCTION_PUBLIC_TABLE_RLS_REQUIRED';end if;
 if exists(select 1 from pg_trigger t join pg_proc p on p.oid=t.tgfoid join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname in ('coco_capture_module_event','erp_audit_capture','gama_audit_row')
  and not t.tgisinternal and t.tgenabled not in ('O','A')) then raise exception 'PRODUCTION_HISTORY_TRIGGER_DISABLED';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'PRODUCTION_BUSINESS_TABLE_NOT_EMPTY: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $verify$;
select jsonb_build_object('project_ref',${literal(target)},'source_count',${sourceCount},'source_fingerprint',${literal(installation)},
 'derived_fingerprint',${literal(derived)},'business_rows',0,'auth_users',0,'storage_files',0,'environment','unassigned') as production_bootstrap_verification;
`;
 fs.mkdirSync(outputDirectory,{recursive:true});
 fs.writeFileSync(path.join(outputDirectory,'verify.sql'),sql);
 fs.writeFileSync(path.join(outputDirectory,'manifest.json'),JSON.stringify({project_ref:target,source_count:sourceCount,installation,derived_fingerprint:derived,verification_sha256:digest(sql),excluded_migrations:snapshot.excluded,follow_up:'Apply excluded migrations separately after the immutable first installation is verified.',sources},null,2)+'\n');
 return {project_ref:target,source_count:sourceCount,installation,derived_fingerprint:derived,directory:outputDirectory};
}
if(require.main===module){try{console.log(JSON.stringify(prepare(process.argv[2])));}catch(error){console.error(error.message);process.exitCode=1;}}
module.exports={prepare};
