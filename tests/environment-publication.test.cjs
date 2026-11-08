const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {packageEnvironments}=require('../scripts/package-environments.cjs');
const devSha='1'.repeat(40),prodSha='2'.repeat(40);
const configuration={development:{supabaseUrl:'https://aaaaaaaaaaaaaaaaaaaa.supabase.co',publishableKey:'sb_publishable_development'},production:{supabaseUrl:'https://bbbbbbbbbbbbbbbbbbbb.supabase.co',publishableKey:'sb_publishable_production'}};
function fixture(t){
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'coco-environment-release-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 for(const name of ['dev','prod']){
  const dir=path.join(root,name);fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir,'index.html'),'<!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="default-src \'self\'; connect-src \'self\' https://mknsaibrewksgomuslev.supabase.co wss://mknsaibrewksgomuslev.supabase.co"><script defer src="coco-environment.js?v=000000000000"></script><script src="gama-supabase.js"></script></head><body>'+name+'</body></html>');
  fs.writeFileSync(path.join(dir,'coco-environment.js'),'window.CocoEnvironment={};');
  fs.writeFileSync(path.join(dir,'gama-supabase.js'),'/* '+name+' release */');
 }
 return {root,developmentDirectory:path.join(root,'dev'),productionDirectory:path.join(root,'prod'),outputDirectory:path.join(root,'pages'),developmentVersion:devSha,productionVersion:prodSha,configuration};
}
test('publication serves independent snapshots and backend bootstraps before any application code',t=>{
 const f=fixture(t);packageEnvironments(f);
 for(const [name,sha] of [['production',prodSha],['development',devSha]]){
  const dir=path.join(f.outputDirectory,name),html=fs.readFileSync(path.join(dir,'index.html'),'utf8');
  assert.ok(html.indexOf('coco-environment.js')<html.indexOf('gama-supabase.js'));
  assert.equal((html.match(/<script\b/g)||[]).length,2);
  assert.ok(!html.includes('mknsaibrewksgomuslev.supabase.co'));
  assert.ok(html.includes(configuration[name].supabaseUrl));
  assert.ok(!html.includes(configuration[name==='production'?'development':'production'].supabaseUrl));
  const bootstrap=fs.readFileSync(path.join(dir,'coco-environment-config.js'),'utf8');
  assert.ok(bootstrap.includes('"environment":"'+name+'"'));
  assert.ok(bootstrap.includes('"version":"'+sha+'"'));
  const runtime=fs.readFileSync(path.join(dir,'coco-environment.js'),'utf8');
  assert.ok(runtime.indexOf('CocoEnvironmentConfig')<runtime.indexOf('window.CocoEnvironment={}'));
  assert.equal(JSON.parse(fs.readFileSync(path.join(dir,'coco-build.json'))).commit,sha);
  const receipt=JSON.parse(fs.readFileSync(path.join(dir,'coco-release.json')));
  assert.ok(receipt.assets['coco-environment-config.js']);
 }
 assert.ok(fs.readFileSync(path.join(f.outputDirectory,'coco-entry.js'),'utf8').includes('./production/'));
});
test('a development update preserves every byte of the approved production snapshot',t=>{
 const f=fixture(t);packageEnvironments(f);
 const before=fs.readFileSync(path.join(f.outputDirectory,'production','coco-release.json'),'utf8');
 fs.writeFileSync(path.join(f.developmentDirectory,'gama-supabase.js'),'/* new development code */');
 packageEnvironments({...f,developmentVersion:'3'.repeat(40),configuration:{...configuration,production:null},productionConfiguration:configuration});
 assert.equal(fs.readFileSync(path.join(f.outputDirectory,'production','coco-release.json'),'utf8'),before);
 assert.equal(fs.readFileSync(path.join(f.outputDirectory,'development','gama-supabase.js'),'utf8'),'/* new development code */');
});
test('missing production configuration is explicit and cannot connect to development',t=>{
 const f=fixture(t);packageEnvironments({...f,configuration:{...configuration,production:null}});
 const dir=path.join(f.outputDirectory,'production');
 assert.ok(fs.readFileSync(path.join(dir,'coco-environment-config.js'),'utf8').includes('"supabaseUrl":null'));
 assert.ok(!fs.readFileSync(path.join(dir,'index.html'),'utf8').includes('.supabase.co'));
 assert.equal(JSON.parse(fs.readFileSync(path.join(dir,'coco-build.json'))).configured,false);
});
test('prepared approved production is copied verbatim and rejects altered release assets',t=>{
 const f=fixture(t);packageEnvironments(f);
 const prepared=path.join(f.root,'approved');fs.cpSync(path.join(f.outputDirectory,'production'),prepared,{recursive:true});
 const before=fs.readFileSync(path.join(prepared,'index.html'),'utf8');
 const options={...f,productionDirectory:prepared,productionPrepared:true};
 packageEnvironments(options);
 assert.equal(fs.readFileSync(path.join(f.outputDirectory,'production','index.html'),'utf8'),before);
 fs.appendFileSync(path.join(prepared,'gama-supabase.js'),'/* unapproved alteration */');
 assert.throws(()=>packageEnvironments(options),/failed integrity/);
});
test('publication rejects shared databases, privileged credentials, moving refs and unsafe output paths',t=>{
 const f=fixture(t);
 assert.throws(()=>packageEnvironments({...f,configuration:{...configuration,production:configuration.development}}),/separate databases/);
 assert.throws(()=>packageEnvironments({...f,configuration:{...configuration,production:{...configuration.production,publishableKey:'sb_secret_private'}}}),/Only publishable/);
 assert.throws(()=>packageEnvironments({...f,developmentVersion:'development'}),/Exact/);
 assert.throws(()=>packageEnvironments({...f,outputDirectory:f.developmentDirectory}),/separate from/);
 fs.unlinkSync(path.join(f.productionDirectory,'coco-environment.js'));
 assert.throws(()=>packageEnvironments(f),/environment-aware/);
});
