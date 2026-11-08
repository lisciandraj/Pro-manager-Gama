const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {PGlite}=require('@electric-sql/pglite');
const {pg_trgm}=require('@electric-sql/pglite/contrib/pg_trgm');
const {unaccent}=require('@electric-sql/pglite/contrib/unaccent');
const {productionMigration}=require('../scripts/production-bootstrap-sql.cjs');
const {prepare}=require('../scripts/prepare-production-verification.cjs');
const {prepare:prepareBootstrap}=require('../scripts/bootstrap-production.cjs');
const root=path.resolve(__dirname,'..'),target='vhutzdfatijjpahsqkne';

test('first-install preparation refuses development and invalid resume positions',()=>{
 assert.throws(()=>prepare('mknsaibrewksgomuslev'),/authorized new production/);
 assert.throws(()=>prepareBootstrap('mknsaibrewksgomuslev'),/separately authorized/);
 assert.throws(()=>prepareBootstrap(target,{startIndex:-1}),/Invalid bootstrap preparation/);
 assert.throws(()=>prepareBootstrap(target,{startIndex:362}),/outside canonical history/);
 assert.throws(()=>prepareBootstrap(target,{outputSubdir:'../escape'}),/Invalid bootstrap preparation/);
 const file='20260917194131_fleet_management_demo_data.sql';
 assert.throws(()=>productionMigration(file,fs.readFileSync(path.join(root,'supabase/migrations',file),'utf8')+'\n-- changed'),/Historical bootstrap source changed/);
});

test('later releases cannot change the immutable first-installation SQL or hide historical source edits',()=>{
 const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'coco-bootstrap-snapshot-'));
 try{
  fs.mkdirSync(path.join(temporary,'scripts'));
  fs.mkdirSync(path.join(temporary,'supabase'));
  for(const file of ['bootstrap-production.cjs','prepare-production-verification.cjs','production-bootstrap-sql.cjs','production-bootstrap-snapshot.cjs','fresh-migration.cjs'])fs.copyFileSync(path.join(root,'scripts',file),path.join(temporary,'scripts',file));
  const directory=path.join(temporary,'supabase/migrations');fs.cpSync(path.join(root,'supabase/migrations'),directory,{recursive:true});
  const bootstrap=require(path.join(temporary,'scripts/bootstrap-production.cjs')).prepare;
  const verify=require(path.join(temporary,'scripts/prepare-production-verification.cjs')).prepare;
  const verificationDirectory=path.join(temporary,'.build/verification');
  const baseline=bootstrap(target,{startIndex:361}),verification=verify(target,{outputDirectory:verificationDirectory});
  const batch=fs.readFileSync(path.join(baseline.directory,'batch-001.sql'),'utf8'),verificationSql=fs.readFileSync(path.join(verificationDirectory,'verify.sql'),'utf8');
  assert.equal(baseline.migrations,362);assert.equal(verification.source_count,362);
  assert.equal(baseline.installation,'6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
  const future='20990101000000_later_application_release.sql';
  fs.writeFileSync(path.join(directory,future),"select 'FUTURE_RELEASE_MUST_BE_SEPARATE';\n");
  const resumed=bootstrap(target,{startIndex:361});verify(target,{outputDirectory:verificationDirectory});
  assert.equal(resumed.installation,baseline.installation);
  assert.equal(fs.readFileSync(path.join(resumed.directory,'batch-001.sql'),'utf8'),batch);
  assert.equal(fs.readFileSync(path.join(verificationDirectory,'verify.sql'),'utf8'),verificationSql);
  for(const manifestFile of [path.join(resumed.directory,'manifest.json'),path.join(verificationDirectory,'manifest.json')]){
   const manifest=JSON.parse(fs.readFileSync(manifestFile,'utf8'));
   assert.equal(manifest.sources.length,362);assert.equal(manifest.sources.at(-1).file,'20261107195941_coco_environment_isolation.sql');
   assert.ok(manifest.excluded_migrations.includes(future));
   assert.ok(manifest.excluded_migrations.includes('20261108154619_contacts_individual_company_links.sql'));
   assert.ok(!manifest.sources.some(source=>source.file===future));
  }
  const historical=path.join(directory,'20260825214709_create_gama_core_schema.sql');fs.appendFileSync(historical,'\n-- unauthorized historical edit\n');
  assert.throws(()=>bootstrap(target,{startIndex:361}),/Historical production bootstrap snapshot changed/);
  assert.throws(()=>verify(target,{outputDirectory:verificationDirectory}),/Historical production bootstrap snapshot changed/);
 }finally{fs.rmSync(temporary,{recursive:true,force:true});}
});

test('derived first installation preserves configuration and access controls while starting with no business rows or fictitious history',async()=>{
 const db=new PGlite({extensions:{pg_trgm,unaccent}}),outputDirectory=path.join(root,'.build/production-verification-test');
 const prepared=prepare(target,{outputDirectory}),manifest=JSON.parse(fs.readFileSync(path.join(outputDirectory,'manifest.json'),'utf8'));
 const verification=fs.readFileSync(path.join(outputDirectory,'verify.sql'),'utf8');
 const q=async(sql,params=[])=>(await db.query(sql,params)).rows;
 try{
  await db.exec("set time zone 'UTC'");
  await db.exec(fs.readFileSync(path.join(root,'tests/platform-bootstrap.sql'),'utf8'));
  await db.exec('create schema private;create table private.coco_bootstrap_installation(project_ref text primary key,installation text not null);alter table private.coco_bootstrap_installation enable row level security;create table private.coco_bootstrap_sources(version text primary key,name text not null,source_sha256 text not null,derived_sha256 text not null,project_ref text not null,installation text not null);alter table private.coco_bootstrap_sources enable row level security;revoke all on private.coco_bootstrap_installation,private.coco_bootstrap_sources from public,anon,authenticated,service_role');
  await q('insert into private.coco_bootstrap_installation values($1,$2)',[target,prepared.installation]);
  for(const source of manifest.sources){
   const sql=productionMigration(source.file,fs.readFileSync(path.join(root,'supabase/migrations',source.file),'utf8'))
    .replace(/create extension if not exists (pgcrypto|pg_cron|pg_net)(?: with schema \w+)?;/gi,'');
   await db.exec(sql);
   await q('insert into private.coco_bootstrap_sources values($1,$2,$3,$4,$5,$6)',[source.file.slice(0,14),source.file.slice(15,-4),source.sha256,source.derived_sha256,target,prepared.installation]);
  }
  await db.exec(verification);
  const counts=await q("select (select count(*) from public.fleet_vehicles)::int vehicles,(select count(*) from public.fleet_drivers)::int drivers,(select count(*) from public.knowledge_articles)::int articles,(select count(*) from public.gama_audit)::int audit,(select count(*) from public.erp_audit_events)::int audit_events,(select count(*) from private.coco_module_events)::int history,(select count(*) from public.gama_document_references)::int document_references,(select count(*) from private.erp_issued_references)::int issued_references");
  assert.deepEqual(counts[0],{vehicles:0,drivers:0,articles:0,audit:0,audit_events:0,history:0,document_references:0,issued_references:0});
  assert.deepEqual((await q("select id from public.app_modules where id in ('contracts','expenses') and enabled order by id")).map(r=>r.id),['contracts','expenses']);
  assert.equal((await q("select count(*)::int n from public.role_module_access where role='rrhh' and base_role='rrhh'"))[0].n,1);
  assert.match((await q('select message from public.access_invitation_template'))[0].message,/Coco ERP/);

  async function rejectsChange(change,pattern){
   await db.exec('begin');
   try{await db.exec(change);await assert.rejects(db.exec(verification),pattern);}finally{await db.exec('rollback');}
  }
  await rejectsChange("update private.coco_bootstrap_installation set project_ref='mknsaibrewksgomuslev'",/IDENTITY_MISMATCH/);
  await rejectsChange("update private.coco_bootstrap_sources set derived_sha256=repeat('0',64) where version='20260914213718'",/DERIVED_HASH_MISMATCH/);
  await rejectsChange("insert into public.products(name,reference) values('Unexpected business data','BOOTSTRAP-REJECT')",/BUSINESS_TABLE_NOT_EMPTY/);
  await rejectsChange("insert into auth.users(id,email) values('a0000000-0000-4000-8000-000000000001','bootstrap@example.invalid')",/AUTH_AND_FILES_REQUIRED/);
  await rejectsChange('alter table public.app_modules disable trigger coco_module_history',/HISTORY_TRIGGER_DISABLED/);
  const resume=prepareBootstrap(target,{startIndex:77,maxBytes:100000,outputSubdir:'production-bootstrap-guard-test'});
  const firstBatch=fs.readFileSync(path.join(resume.directory,'batch-001.sql'),'utf8');
  await assert.rejects(db.exec(firstBatch),/BOOTSTRAP_IDENTITY_MISMATCH/);
  await db.exec('begin');
  try{
   await q('delete from private.coco_bootstrap_sources where version >= $1',[manifest.sources[77].file.slice(0,14)]);
   await db.exec("insert into public.products(name,reference) values('Unexpected concurrent data','BOOTSTRAP-CONCURRENT-REJECT')");
   await assert.rejects(db.exec(firstBatch),/EMPTY_PRODUCTION_BUSINESS_REQUIRED/);
  }finally{await db.exec('rollback');}
  await db.exec(verification);
  const release='0123456789abcdef0123456789abcdef01234567';
  const activated=(await q('select private.coco_assign_environment($1,$2,$3,$4) result',['production',release,362,0]))[0].result;
  assert.equal(activated.environment,'production');
  await assert.rejects(db.exec(verification),/ALREADY_ASSIGNED/);
 }finally{await db.close()}
});
