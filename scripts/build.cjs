const fs=require('node:fs'),path=require('node:path'),{execFileSync}=require('node:child_process');
const {root,manifest,hash,runtimeFiles,header,runtimeScript,validateManifest}=require('./lib/assets.cjs');
validateManifest();
execFileSync('python3',[path.join(root,'scripts/build-i18n.py'),'--catalog-only'],{cwd:root,stdio:'inherit'});
for(const {source,output} of manifest.scripts)fs.writeFileSync(path.join(root,output),runtimeScript(source));
for(const {source,output} of manifest.styles){
 fs.writeFileSync(path.join(root,output),header(source)+fs.readFileSync(path.join(root,source),'utf8'));
}
for(const bundle of manifest.startupBundles||[]){
 const code=bundle.files.map(file=>fs.readFileSync(path.join(root,file),'utf8')).join('\n;\n');
 // Parse the combined classic scope too: no duplicate lexical declarations.
 require('acorn').parse(code,{ecmaVersion:'latest',sourceType:'script'});
 fs.writeFileSync(path.join(root,bundle.output),'/* Generated startup bundle: '+bundle.files.join(', ')+'. */\n'+code+(bundle.output==='coco-modules.js'?'\nwindow.ArcRuntimeLoaded=true;window.dispatchEvent(new CustomEvent("arc:runtime-ready"));\n':''));
}
execFileSync(process.execPath,[path.join(root,'node_modules/vite/bin/vite.js'),'build'],{cwd:root,stdio:'inherit'});
fs.copyFileSync(path.join(root,'.build/client/architect-core.js'),path.join(root,'architect-core.js'));
fs.writeFileSync(path.join(root,'architect-components.css'),manifest.moduleStyles.map(f=>fs.readFileSync(path.join(root,f),'utf8')).join('')+'\n'+fs.readFileSync(path.join(root,'src/ui/components.css'),'utf8'));
fs.copyFileSync(path.join(root,'src/ui/base.css'),path.join(root,'architect-base.css'));
const assets=Object.fromEntries([...runtimeFiles(),...manifest.vendors].map(file=>[file,file+'?v='+hash(file)]));
fs.writeFileSync(path.join(root,'architect-assets.js'),'/* Generated runtime asset versions. */\nwindow.ArcAssets='+JSON.stringify(assets,null,2)+';\n');
const versionHtml=html=>html.replace(/\b(src|href)="([^"?#]+\.(?:js|css))(?:\?[^"#]*)?"/g,(full,key,file)=>{
 if(/^https?:/.test(file)||!fs.existsSync(path.join(root,file)))return full;
 // Match the dynamic SDK loader exactly so the browser reuses the preload.
 if(file==='assets/vendor/supabase-2.115.0.js')return key+'="'+file+'"';
 return key+'="'+file+'?v='+hash(file)+'"';
});
fs.writeFileSync(path.join(root,'index.html'),versionHtml(fs.readFileSync(path.join(root,'src/app/index.html'),'utf8')));
for(const file of ['gama-site.html','camera-check.html','tms-tracking.html']){
 fs.writeFileSync(path.join(root,file),versionHtml(fs.readFileSync(path.join(root,'src/app/'+file),'utf8')));
}
const b2bConfig={...JSON.parse(fs.readFileSync(path.join(root,'config/storefront-runtime.json'),'utf8')),pdf_template:'gama-pdf-template.js'};
const catalogueUrl=new URL(b2bConfig.catalogue_url);
if(catalogueUrl.protocol!=='https:'||catalogueUrl.username||catalogueUrl.password)throw Error('Public catalogue URL must be HTTPS without credentials');
fs.writeFileSync(path.join(root,'gama-b2b.html'),versionHtml(fs.readFileSync(path.join(root,'src/storefront/b2b.html'),'utf8').replace('__B2B_CSS__','gama-b2b.css').replace('__B2B_JS__','gama-b2b.js').replaceAll('__LOGO__','gama-logo.jpg').replaceAll('__CATALOGUE__',catalogueUrl.href).replace('__B2B_RUNTIME__',JSON.stringify(b2bConfig).replace(/</g,'\\u003c'))));
const shell=['./','./index.html','./manifest.json','./coco-gama-icon-180.png','./coco-gama-icon-192.png','./coco-gama-icon-512.png'];
const sw=fs.readFileSync(path.join(root,'src/app/service-worker.js'),'utf8')
 .replace('__COCO_RELEASE__',hash('architect-assets.js')+'-'+hash('index.html'))
 .replace('__COCO_APP_SHELL__',JSON.stringify(shell));
fs.writeFileSync(path.join(root,'sw.js'),sw);
const out=path.join(root,'dist');fs.rmSync(out,{recursive:true,force:true});fs.mkdirSync(out);
// Publish only web assets. Tests, build configuration, source code and notes are not copied.
const publicFiles=[...runtimeFiles(),'architect-assets.js','sw.js','index.html','gama-site.html','gama-b2b.html','camera-check.html','tms-tracking.html','manifest.json',
 ...fs.readdirSync(root).filter(f=>/\.(png|jpg|jpeg|webp|svg|ico|webmanifest)$/.test(f))];
for(const file of publicFiles)fs.copyFileSync(path.join(root,file),path.join(out,file));
for(const folder of ['assets','config/localizations','fonts'])if(fs.existsSync(path.join(root,folder)))fs.cpSync(path.join(root,folder),path.join(out,folder),{recursive:true});
fs.writeFileSync(path.join(out,'.nojekyll'),'');
console.log('Coco ERP: '+runtimeFiles().length+' versioned assets built from canonical sources.');
