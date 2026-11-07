const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {authorizePromotion,REQUIRED_RELEASE_JOBS}=require('../scripts/lib/release-policy.cjs');
const {erpHttpHeaders,writeReleaseManifest,verifyManifest}=require('../scripts/lib/release.cjs');
const {secureHtml}=require('../scripts/lib/csp.cjs');
const root=path.resolve(__dirname,'..'),commit='a'.repeat(40);
const complete=()=>Object.fromEntries(REQUIRED_RELEASE_JOBS.map(job=>[job,{result:'success'}]));
test('release promotion refuses pending, failed, skipped and missing security gates, foreign revisions and PRs',()=>{
 const input={event:'push',ref:'refs/heads/main',commit,artifactCommit:commit,checks:complete()};
 assert.equal(authorizePromotion(input),true);
 for(const job of REQUIRED_RELEASE_JOBS)for(const result of ['failure','cancelled','skipped','pending',undefined]){
  const checks=complete();if(result===undefined)delete checks[job];else checks[job]={result};
  assert.throws(()=>authorizePromotion({...input,checks}),new RegExp('RELEASE_CHECK_REQUIRED:'+job));
 }
 assert.throws(()=>authorizePromotion({...input,artifactCommit:'b'.repeat(40)}),/REVISION_MISMATCH/);
 assert.throws(()=>authorizePromotion({...input,event:'pull_request'}),/MAIN_ONLY/);
 assert.throws(()=>authorizePromotion({...input,ref:'refs/heads/security'}),/MAIN_ONLY/);
});
test('the actual Pages deploy waits for every security gate and does not probe production from PR builds',()=>{
 const workflow=fs.readFileSync(path.join(root,'.github/workflows/deploy-coco-pages.yml'),'utf8');
 const deploy=workflow.slice(workflow.indexOf('\n  deploy:'));
 const needs=deploy.match(/\n    needs: \[([^\]]+)\]/)?.[1].split(',').map(s=>s.trim());
 assert.deepEqual(needs,REQUIRED_RELEASE_JOBS);
 assert.match(workflow,/release-validation:\n    uses: \.\/\.github\/workflows\/validate-release\.yml/);
 assert.match(workflow,/secret-scan:\n    uses: \.\/\.github\/workflows\/secret-scan\.yml/);
 assert.match(deploy,/node scripts\/verify-release-approval\.cjs/);
 assert.ok(!workflow.slice(0,workflow.indexOf('\n  deploy:')).includes('check-agent-live.mjs'));
 assert.ok(deploy.includes('check-agent-live.mjs'));
 const scanner=fs.readFileSync(path.join(root,'.github/workflows/secret-scan.yml'),'utf8');assert.match(scanner,/fetch-depth: 0/);assert.match(scanner,/--redact.*--log-opts=--all/);assert.match(scanner,/sha256sum --check --status/);assert.ok(!scanner.includes('pull_request_target'));
});
test('ERP HTTP CSP retains trusted script hashes and forbids framing while preserving camera/GPS and the existing frame restrictions',()=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'coco-http-'));
 try{
  fs.writeFileSync(path.join(directory,'index.html'),secureHtml('<html><head></head><body><script>window.fixture=1</script></body></html>',{roadRoutes:true}));
  fs.writeFileSync(path.join(directory,'camera-check.html'),secureHtml('<html><head></head><body></body></html>'));
  const h=erpHttpHeaders(directory);
  assert.match(h,/frame-ancestors 'none'/);assert.match(h,/X-Frame-Options: DENY/);assert.match(h,/script-src-attr 'none'/);
  assert.match(h,/'sha256-[A-Za-z0-9+/=]+'/);assert.match(h,/frame-src 'self';/);assert.ok(!h.includes("frame-src 'self' blob:"));
  assert.match(h,/camera=\(self\).*geolocation=\(self\)/);assert.ok(!h.includes("script-src 'unsafe-inline'"));
  assert.match(h,/X-Content-Type-Options: nosniff/);
 }finally{fs.rmSync(directory,{recursive:true,force:true})}
});
test('release provenance hashes exact public artifacts and private source definitions without including their content',()=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'coco-release-'));
 try{
  const output=path.join(directory,'dist');fs.mkdirSync(output);fs.mkdirSync(path.join(directory,'supabase/migrations'),{recursive:true});fs.mkdirSync(path.join(directory,'supabase/functions/example'),{recursive:true});
  fs.writeFileSync(path.join(output,'index.html'),'<html>fixture</html>');fs.writeFileSync(path.join(directory,'supabase/migrations/20260101000000_fixture.sql'),'select 1;');fs.writeFileSync(path.join(directory,'supabase/functions/example/index.ts'),'// non-public fixture source');
  fs.writeFileSync(path.join(directory,'supabase/functions/example/.env'),'NEVER_INCLUDE_THIS');
  const manifest=writeReleaseManifest({root:directory,output,kind:'erp',source:{commit,dirty:false}});
  assert.equal(verifyManifest(output,manifest),true);assert.equal(manifest.source_commit,commit);assert.equal(manifest.components.migrations.length,1);assert.equal(manifest.components.edge_functions[0].name,'example');
  assert.ok(!JSON.stringify(manifest).includes('NEVER_INCLUDE_THIS'));assert.ok(!JSON.stringify(manifest).includes('non-public fixture source'));
  fs.writeFileSync(path.join(output,'index.html'),'changed');assert.throws(()=>verifyManifest(output,manifest),/HASH_MISMATCH/);
  const invalid={...manifest,artifacts:[{file:'../outside',sha256:'a'.repeat(64)}]};assert.throws(()=>verifyManifest(output,invalid),/PATH_INVALID/);
  fs.writeFileSync(path.join(directory,'outside'),'fixture');fs.symlinkSync(path.join(directory,'outside'),path.join(output,'link'));
  const linked={...manifest,artifacts:[{file:'link',sha256:require('../scripts/lib/release.cjs').sha256('fixture')}]};assert.throws(()=>verifyManifest(output,linked),/PATH_INVALID/);
 }finally{fs.rmSync(directory,{recursive:true,force:true})}
});
test('all external workflow actions are pinned by commit and the fiscal lock uses distribution hashes',()=>{
 for(const filename of fs.readdirSync(path.join(root,'.github/workflows'))){
  const content=fs.readFileSync(path.join(root,'.github/workflows',filename),'utf8');
  for(const match of content.matchAll(/uses:\s+(?!\.\/)([^\s#]+)/g))assert.match(match[1],/^[\w.-]+\/[\w./-]+@[a-f0-9]{40}$/,'Unpinned '+match[1]);
 }
 const lock=fs.readFileSync(path.join(root,'services/sri/requirements.lock'),'utf8');
 const entries=lock.split(/\n(?=[A-Za-z0-9])/).filter(part=>/^[\w.-]+==/.test(part));
 assert.ok(entries.length>8);for(const entry of entries){assert.match(entry,/^[\w.-]+==[^\s]+/);assert.match(entry,/--hash=sha256:[a-f0-9]{64}/)}
 for(const dep of fs.readFileSync(path.join(root,'services/sri/requirements.txt'),'utf8').split(/\r?\n/).filter(line=>line&&!line.startsWith('#')))assert.ok(lock.includes(dep+' '),'Runtime requirement absent from hashed lock: '+dep);
 const docker=fs.readFileSync(path.join(root,'services/sri/deploy/Dockerfile.gateway'),'utf8');assert.match(docker,/^FROM python:[^\s]+@sha256:[a-f0-9]{64}/);assert.match(docker,/pip install --no-cache-dir --require-hashes -r requirements\.lock/);
});
test('deployment alignment refuses missing observations and detects any stale component without claiming deployment from a build',()=>{
 const {compareReleaseComponents}=require('../scripts/check-release-alignment.cjs');
 const manifest={schema_version:1,component:'erp',source_commit:commit,source_dirty:false,components:{edge_functions:[{name:'dummy',source_sha256:'b'.repeat(64)}],migrations:[{file:'fixture.sql',sha256:'c'.repeat(64)}],sri_source_sha256:'d'.repeat(64)}};
 assert.equal(compareReleaseComponents([manifest],{}).length,4);
 const observed={web:{erp:{observed:true,source_commit:commit}},edge_functions:[{name:'dummy',observed:true,version:2,source_sha256:'b'.repeat(64)}],migrations:[{file:'fixture.sql',observed:true,sha256:'c'.repeat(64)}],sri:{observed:true,source_sha256:'d'.repeat(64)}};
 assert.deepEqual(compareReleaseComponents([manifest],observed),[]);
 observed.edge_functions[0].source_sha256='e'.repeat(64);assert.deepEqual(compareReleaseComponents([manifest],observed),['edge/dummy: deployed source/version not observed or differs']);
 assert.deepEqual(compareReleaseComponents([{...manifest,source_dirty:true}],{...observed,edge_functions:[{...observed.edge_functions[0],source_sha256:'b'.repeat(64)}]}),['erp: source checkout was dirty at build time']);
});
