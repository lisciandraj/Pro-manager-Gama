/* Assemble independently built ERP releases. No database connection or data copy. */
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');

const SHA=/^[a-f0-9]{40}$/;
function publicBackend(value,name){
 if(value==null){if(name==='development')throw Error('Development backend is required');return {supabaseUrl:null,publishableKey:null};}
 const {supabaseUrl,publishableKey}=value;
 if(typeof supabaseUrl!=='string'||!/^https:\/\/[a-z0-9]{20}\.supabase\.co$/.test(supabaseUrl))throw Error('Invalid '+name+' Supabase URL');
 if(typeof publishableKey!=='string')throw Error('Missing '+name+' publishable key');
 if(!/^sb_publishable_[A-Za-z0-9_-]+$/.test(publishableKey)){
  let claims;try{claims=JSON.parse(Buffer.from(publishableKey.split('.')[1]||'','base64url').toString());}catch{}
  if(publishableKey.split('.').length!==3||claims?.role!=='anon')throw Error('Only publishable or legacy anon keys may be packaged');
 }
 return {supabaseUrl,publishableKey};
}
function filesIn(directory){return fs.readdirSync(directory,{withFileTypes:true}).flatMap(entry=>{
 const file=path.join(directory,entry.name);
 if(entry.isSymbolicLink())throw Error('Release assets cannot contain symbolic links');
 return entry.isDirectory()?filesIn(file):[file];
});}
function patchHtml(html,config,bootstrapHash,manifestHash){
 const host=config.supabaseUrl?new URL(config.supabaseUrl).host:null;
 // Each snapshot may connect only to its own backend, even if old sources
 // accidentally retain the historical development URL.
 html=html.replace(/(<meta\s+http-equiv=["']Content-Security-Policy["'][^>]*\bcontent=")([^"]*)(")/gi,(_,start,csp,end)=>{
  csp=csp.replace(/\bconnect-src\s+([^;]*)/i,(_directive,sources)=>{
   const filtered=sources.trim().split(/\s+/).filter(source=>!/^https?:\/\/[a-z0-9.-]*supabase\.(?:co|in)(?:\/|$)|^wss?:\/\/[a-z0-9.-]*supabase\.(?:co|in)(?:\/|$)/i.test(source));
   if(host)filtered.push('https://'+host,'wss://'+host);
   return 'connect-src '+[...new Set(filtered)].join(' ');
  });
  return start+csp+end;
 });
 html=html.replace(/<link\b[^>]*\brel=["']preconnect["'][^>]*supabase\.(?:co|in)[^>]*>/gi,'');
 html=html.replace(/<html\b[^>]*>/i,tag=>tag.replace(/\sdata-coco-build="[^"]*"/,'').replace(/>$/,' data-coco-build="'+config.version+'" data-coco-environment="'+config.environment+'">'));
 html=html.replace(/<script\b[^>]*\bsrc=["'](?:\.\/)?coco-environment\.js(?:\?[^"']*)?["'][^>]*>\s*<\/script>/gi,'');
 if(manifestHash)html=html.replace(/(\bsrc=["'](?:\.\/)?architect-assets\.js)(?:\?[^"']*)?(["'])/gi,'$1?v='+manifestHash+'$2');
 return html.replace(/<head>/i,'<head>\n<script defer src="coco-environment.js?v='+bootstrapHash+'"></script>');
}
function packageEnvironments({developmentDirectory,productionDirectory,outputDirectory,developmentVersion,productionVersion,configuration,productionConfiguration=configuration,productionPrepared=false}){
 if(!SHA.test(developmentVersion)||!SHA.test(productionVersion))throw Error('Exact development and production commit SHAs are required');
 const inputs=[developmentDirectory,productionDirectory].map(value=>path.resolve(value)),output=path.resolve(outputDirectory);
 for(const input of inputs)if(output===input||output.startsWith(input+path.sep)||input.startsWith(output+path.sep))throw Error('Publication directory must be separate from both release inputs');
 const backends={development:publicBackend(configuration.development,'development'),production:publicBackend(productionConfiguration.production,'production')};
 if(backends.production.supabaseUrl===backends.development.supabaseUrl)throw Error('Production and development must use separate databases');
 for(const input of inputs){
  if(!fs.existsSync(path.join(input,'index.html'))||!fs.existsSync(path.join(input,'coco-environment.js')))throw Error('Release must include the environment-aware ERP bootstrap');
  filesIn(input);
 }
 fs.rmSync(output,{recursive:true,force:true});fs.mkdirSync(output,{recursive:true});
 const versions={production:productionVersion,development:developmentVersion};
 for(const [environment,input] of [['production',inputs[1]],['development',inputs[0]]]){
  const target=path.join(output,environment);fs.cpSync(input,target,{recursive:true});
  if(environment==='production'&&productionPrepared){
   // Production is prepared by the packager stored in its approved source
   // snapshot. Future edits to this packager cannot rewrite production HTML.
   const receipt=JSON.parse(fs.readFileSync(path.join(target,'coco-release.json'),'utf8'));
   if(receipt.environment!=='production'||receipt.commit!==productionVersion)throw Error('Prepared production release does not match the approved commit');
   const files=filesIn(target).filter(file=>path.basename(file)!=='coco-release.json');
   if(files.length!==Object.keys(receipt.assets).length)throw Error('Prepared production asset list differs from its receipt');
   for(const file of files){
    const key=path.relative(target,file).split(path.sep).join('/');
    if(crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')!==receipt.assets[key])throw Error('Prepared production asset failed integrity: '+key);
   }
   continue;
  }
  const config={environment,version:versions[environment],...backends[environment],productionUrl:'../production/',developmentUrl:'../development/'};
  const bootstrap='/* Public release configuration; contains no privileged key. */\nwindow.CocoEnvironmentConfig=Object.freeze('+JSON.stringify(config).replace(/</g,'\\u003c')+');\n';
  // Keep the configuration receipt available to diagnostics/offline preparation,
  // but combine it with the existing bootstrap for zero extra startup requests.
  fs.writeFileSync(path.join(target,'coco-environment-config.js'),bootstrap);
  const environmentFile=path.join(target,'coco-environment.js');
  fs.writeFileSync(environmentFile,bootstrap+fs.readFileSync(environmentFile,'utf8'));
  const bootstrapHash=crypto.createHash('sha256').update(fs.readFileSync(environmentFile)).digest('hex').slice(0,12);
  const manifestFile=path.join(target,'architect-assets.js');let manifestHash=null;
  if(fs.existsSync(manifestFile)){
   fs.writeFileSync(manifestFile,fs.readFileSync(manifestFile,'utf8').replace(/coco-environment\.js\?v=[a-f0-9]+/g,'coco-environment.js?v='+bootstrapHash));
   manifestHash=crypto.createHash('sha256').update(fs.readFileSync(manifestFile)).digest('hex').slice(0,12);
  }
  for(const file of fs.readdirSync(target).filter(file=>file.endsWith('.html'))){
   const filename=path.join(target,file);fs.writeFileSync(filename,patchHtml(fs.readFileSync(filename,'utf8'),config,bootstrapHash,manifestHash));
  }
  const workerFile=path.join(target,'sw.js');
  if(fs.existsSync(workerFile)){
   const release=(manifestHash||bootstrapHash)+'-'+crypto.createHash('sha256').update(fs.readFileSync(path.join(target,'index.html'))).digest('hex').slice(0,12);
   fs.writeFileSync(workerFile,fs.readFileSync(workerFile,'utf8').replace(/const CACHE=CACHE_PREFIX\+'[^']+';/,"const CACHE=CACHE_PREFIX+'"+release+"';"));
  }
  fs.writeFileSync(path.join(target,'coco-build.json'),JSON.stringify({environment,commit:versions[environment],configured:!!config.supabaseUrl})+'\n');
  const hashes=Object.fromEntries(filesIn(target).sort().map(file=>[path.relative(target,file).split(path.sep).join('/'),crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')]));
  fs.writeFileSync(path.join(target,'coco-release.json'),JSON.stringify({environment,commit:versions[environment],assets:hashes},null,2)+'\n');
 }
 fs.writeFileSync(path.join(output,'index.html'),'<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src \'self\'; script-src \'self\'; base-uri \'self\'; object-src \'none\'"><title>Coco ERP</title><script src="coco-entry.js" defer></script></head><body><p><a href="./production/">Ouvrir Coco ERP — Production</a></p></body></html>\n');
 fs.writeFileSync(path.join(output,'coco-entry.js'),"location.replace('./production/'+location.search+location.hash);\n");
 // Existing installations may still have a root-scoped worker. Retire only
 // that worker/cache; child environments keep independent cache scopes.
 fs.writeFileSync(path.join(output,'sw.js'),"self.addEventListener('install',()=>self.skipWaiting());self.addEventListener('activate',event=>event.waitUntil((async()=>{const prefix='coco-erp:'+new URL('./',self.location.href).pathname+':';await Promise.all((await caches.keys()).filter(key=>key.startsWith(prefix)).map(key=>caches.delete(key)));await self.registration.unregister();})()));\n");
 fs.writeFileSync(path.join(output,'coco-build.json'),JSON.stringify({commit:developmentVersion,environments:versions,paths:{production:'production/',development:'development/'}})+'\n');
 fs.writeFileSync(path.join(output,'.nojekyll'),'');
 return {outputDirectory:output,environments:versions,productionConfigured:!!backends.production.supabaseUrl};
}
if(require.main===module){
 const [developmentDirectory,productionDirectory,outputDirectory,configurationFile,productionConfigurationFile,developmentVersion,productionVersion,mode]=process.argv.slice(2);
 if(!productionVersion)throw Error('Usage: node scripts/package-environments.cjs <development-dist> <production-dist> <output> <development-config.json> <production-config.json> <development-sha> <production-sha>');
 if(mode&&mode!=='--production-prepared')throw Error('Unknown publication mode');
 console.log(JSON.stringify(packageEnvironments({developmentDirectory,productionDirectory,outputDirectory,developmentVersion,productionVersion,configuration:JSON.parse(fs.readFileSync(configurationFile,'utf8')),productionConfiguration:JSON.parse(fs.readFileSync(productionConfigurationFile,'utf8')),productionPrepared:mode==='--production-prepared'})));
}
module.exports={packageEnvironments,publicBackend,patchHtml};
