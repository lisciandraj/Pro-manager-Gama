/* Audited first installation on the separately created empty production project.
 * This prepares SQL; it never opens a connection, exports existing data or runs
 * a migration. Apply the bounded files through the authenticated migration API.
 */
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {freshMigration}=require('./fresh-migration.cjs');
const root=path.join(__dirname,'..');
const target='vhutzdfatijjpahsqkne',forbidden='mknsaibrewksgomuslev';
const digest=s=>crypto.createHash('sha256').update(s).digest('hex');
const sqlString=s=>"'"+s.replaceAll("'","''")+"'";
function prepare(project){
 if(project===forbidden||project!==target)throw Error('Only the separately authorized empty production project is accepted');
 const directory=path.join(root,'supabase/migrations'),out=path.join(root,'.build/production-bootstrap');
 fs.mkdirSync(out,{recursive:true});
 const sources=fs.readdirSync(directory).filter(f=>/^\d{14}_[a-z0-9_]+\.sql$/.test(f)).sort().map(file=>{const original=fs.readFileSync(path.join(directory,file),'utf8');const sql=freshMigration(file,original);return {file,sha256:digest(original),derived_sha256:digest(sql),sql};});
 if(!sources.at(-1)?.file.endsWith('_coco_environment_isolation.sql'))throw Error('Environment guard must be the final reviewed migration');
 const installation=digest(sources.map(x=>x.file+':'+x.sha256).join('\n'));
 const preflight=`do $$begin
 if exists(select 1 from information_schema.tables where table_schema in ('public','private','storefront_api') and table_type='BASE TABLE')
 or exists(select 1 from auth.users) or exists(select 1 from storage.objects) or exists(select 1 from storage.buckets) then
  raise exception 'EMPTY_PRODUCTION_REQUIRED';
 end if;
end $$;
create schema if not exists private;
create table private.coco_bootstrap_installation(project_ref text primary key,installation text not null);
insert into private.coco_bootstrap_installation values(${sqlString(project)},${sqlString(installation)});
alter table private.coco_bootstrap_installation enable row level security;
revoke all on private.coco_bootstrap_installation from public,anon,authenticated,service_role;
create table private.coco_bootstrap_sources(version text primary key,name text not null,source_sha256 text not null,derived_sha256 text not null,project_ref text not null,installation text not null,installed_at timestamptz not null default now());
alter table private.coco_bootstrap_sources enable row level security;
revoke all on private.coco_bootstrap_sources from public,anon,authenticated,service_role;
`;
 const guard=`do $$begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or not exists(select 1 from private.coco_bootstrap_installation where project_ref=${sqlString(project)} and installation=${sqlString(installation)}) then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
end $$;\n`;
 let batches=[],parts=[],size=0;
 for(const source of sources){
  const piece='\n-- Canonical source: '+source.file+'; SHA256 '+source.sha256+'\n'+source.sql+'\n'+`insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values(${[source.file.slice(0,14),source.file.slice(15,-4),source.sha256,source.derived_sha256,project,installation].map(sqlString).join(',')});\n`;
  if(parts.length&&size+Buffer.byteLength(piece)>15000){batches.push(parts.join('\n'));parts=[];size=0;}
  parts.push(piece);size+=Buffer.byteLength(piece);
 }
 if(parts.length)batches.push(parts.join('\n'));
 fs.writeFileSync(path.join(out,'preflight.sql'),preflight);
 const files=batches.map((sql,i)=>{const file='batch-'+String(i+1).padStart(3,'0')+'.sql';const query=guard+sql;fs.writeFileSync(path.join(out,file),query);return {file,sha256:digest(query),bytes:Buffer.byteLength(query)};});
 const manifest={project_ref:project,source_project_forbidden:forbidden,installation,adaptation:'Only the historical 20260912081917 existing-product data repair is omitted after asserting its target catalog is empty. All schema statements and all original files remain unchanged.',sources:sources.map(({sql,...source})=>source),batches:files};
 fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
 return {project_ref:project,installation,migrations:sources.length,batches:files.length,directory:out};
}
if(require.main===module){try{console.log(JSON.stringify(prepare(process.argv[2])));}catch(error){console.error(error.message);process.exitCode=1;}}
module.exports={prepare};
