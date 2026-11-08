const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {execFileSync}=require('node:child_process');
const sha256=value=>crypto.createHash('sha256').update(value).digest('hex');
const webHtml=['index.html','gama-site.html','gama-b2b.html','camera-check.html','tms-tracking.html','tms-driver.html'];
function erpHttpHeaders(directory){
 const policies=webHtml.filter(file=>fs.existsSync(path.join(directory,file))).map(file=>{
  const html=fs.readFileSync(path.join(directory,file),'utf8');
  const policy=html.match(/<meta\s+http-equiv="Content-Security-Policy"\s+content="([^"]+)"/i)?.[1];
  if(!policy)throw Error('ERP_HTTP_CSP_MISSING:'+file);
  return policy;
 });
 if(!policies.length)throw Error('ERP_HTTP_HTML_MISSING');
 const directives=new Map();
 for(const policy of policies)for(const directive of policy.split(';')){
  const [name,...values]=directive.trim().split(/\s+/);if(!name)continue;
  const list=directives.get(name)||new Set();values.forEach(value=>list.add(value));directives.set(name,list);
 }
 directives.set('frame-ancestors',new Set(["'none'"]));
 const csp=[...directives].map(([name,values])=>name+(values.size?' '+[...values].join(' '):'')).join('; ');
 return `/*\n  Content-Security-Policy: ${csp}\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n  Permissions-Policy: camera=(self), microphone=(), geolocation=(self)\n  X-Frame-Options: DENY\n  Strict-Transport-Security: max-age=31536000\n`;
}
function filesUnder(directory,{include=()=>true}={}){
 if(!fs.existsSync(directory))return [];
 return fs.readdirSync(directory,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name)).flatMap(entry=>{
  if(entry.isSymbolicLink())throw Error('RELEASE_SYMLINK_FORBIDDEN');
  if(entry.name.startsWith('.'))return [];
  const file=path.join(directory,entry.name);
  return entry.isDirectory()?filesUnder(file,{include}):include(file)?[file]:[];
 });
}
const relative=(root,file)=>path.relative(root,file).split(path.sep).join('/');
function revision(root){
 const supplied=process.env.GITHUB_SHA||process.env.COCO_BUILD_ID;
 const value=supplied||execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim();
 if(!/^[a-f0-9]{40}$/.test(value))throw Error('RELEASE_SOURCE_SHA_REQUIRED');
 const dirty=execFileSync('git',['status','--porcelain','--untracked-files=normal'],{cwd:root,encoding:'utf8'}).trim()!=='';
 if(process.env.GITHUB_ACTIONS==='true'&&dirty)throw Error('RELEASE_DIRTY_SOURCE');
 return {commit:value,dirty};
}
function componentInventory(root){
 const migrations=filesUnder(path.join(root,'supabase/migrations'),{include:file=>file.endsWith('.sql')});
 const edge=path.join(root,'supabase/functions');
 const shared=filesUnder(path.join(edge,'_shared'),{include:file=>/\.(?:ts|mjs|js|json|jsonc)$/.test(file)});
 const functions=fs.existsSync(edge)?fs.readdirSync(edge,{withFileTypes:true}).filter(e=>e.isDirectory()&&!e.name.startsWith('_')&&!e.name.startsWith('.')).sort((a,b)=>a.name.localeCompare(b.name)).map(e=>{
  // Shared security helpers are part of the deployed function's provenance.
  // Conservatively include the full shared bundle rather than overlooking a
  // transitive import when a helper changes without its entrypoint changing.
  const files=[...filesUnder(path.join(edge,e.name),{include:file=>/\.(?:ts|mjs|js|json|jsonc)$/.test(file)}),...shared].sort();
  return {name:e.name,source_sha256:sha256(files.map(file=>relative(root,file)+'\0'+sha256(fs.readFileSync(file))).join('\n'))};
 }):[];
 const python=filesUnder(path.join(root,'services/sri'),{include:file=>/\.(?:py|xsd)$/.test(file)||/requirements\.(?:txt|lock)$/.test(file)});
 return {migrations:migrations.map(file=>({file:path.basename(file),sha256:sha256(fs.readFileSync(file))})),edge_functions:functions,sri_source_sha256:sha256(python.map(file=>relative(root,file)+'\0'+sha256(fs.readFileSync(file))).join('\n'))};
}
function writeReleaseManifest({root,output,kind,source=revision(root)}){
 if(!['erp','storefront'].includes(kind))throw Error('RELEASE_COMPONENT_INVALID');
 const marker={commit:source.commit,source_dirty:source.dirty,component:kind};
 fs.writeFileSync(path.join(output,'coco-build.json'),JSON.stringify(marker,null,2)+'\n');
 const files=filesUnder(output,{include:file=>path.basename(file)!=='release-manifest.json'});
 const manifest={schema_version:1,component:kind,source_commit:source.commit,source_dirty:source.dirty,
  artifacts:files.map(file=>({file:relative(output,file),sha256:sha256(fs.readFileSync(file))})),components:componentInventory(root),
  deployment_status:'build-only; hosted component revisions must be verified separately'};
 fs.writeFileSync(path.join(output,'release-manifest.json'),JSON.stringify(manifest,null,2)+'\n');
 return manifest;
}
function verifyManifest(directory,manifest){
 if(manifest.schema_version!==1||!['erp','storefront'].includes(manifest.component)||!/^[a-f0-9]{40}$/.test(manifest.source_commit)||!Array.isArray(manifest.artifacts))throw Error('RELEASE_MANIFEST_INVALID');
 const seen=new Set();
 for(const row of manifest.artifacts){
  if(typeof row.file!=='string'||row.file.startsWith('/')||row.file.split('/').some(p=>!p||p==='.'||p==='..')||seen.has(row.file)||!/^[a-f0-9]{64}$/.test(row.sha256))throw Error('RELEASE_ARTIFACT_PATH_INVALID');
  seen.add(row.file);let file=directory;const parts=row.file.split('/');
  for(let i=0;i<parts.length;i++){
   file=path.join(file,parts[i]);const stat=fs.lstatSync(file,{throwIfNoEntry:false});
   if(!stat||stat.isSymbolicLink()||(i<parts.length-1?!stat.isDirectory():!stat.isFile()))throw Error('RELEASE_ARTIFACT_PATH_INVALID');
  }
  if(sha256(fs.readFileSync(file))!==row.sha256)throw Error('RELEASE_ARTIFACT_HASH_MISMATCH:'+row.file);
 }
 return true;
}
module.exports={erpHttpHeaders,componentInventory,writeReleaseManifest,verifyManifest,sha256,revision};
