const fs=require('node:fs'),path=require('node:path'),acorn=require('acorn');
const {root,manifest,runtimeFiles,validateManifest}=require('./lib/assets.cjs');
validateManifest();
const walk=dir=>fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]);
let count=0;
for(const file of walk(path.join(root,'src')).filter(f=>f.endsWith('.js'))){
 let source=fs.readFileSync(file,'utf8');
 if(file.endsWith('service-worker.js'))source=source.replace('__COCO_APP_SHELL__','[]');
 acorn.parse(source,{ecmaVersion:'latest',sourceType:'module'});count++;
}
for(const file of [...runtimeFiles().filter(f=>f.endsWith('.js')),'architect-assets.js','sw.js']){
 acorn.parse(fs.readFileSync(path.join(root,file),'utf8'),{ecmaVersion:'latest',sourceType:'script'});
}
for(const file of ['index.html','gama-site.html','camera-check.html']){
 const html=fs.readFileSync(path.join(root,file),'utf8');
 for(const m of html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g))if(m[1].trim())acorn.parse(m[1],{ecmaVersion:'latest',sourceType:'script'});
 for(const m of html.matchAll(/(?:src|href)="([^"?#]+\.(?:js|css))(?:\?[^"#]*)?"/g)){
  if(!m[1].startsWith('http')&&!fs.existsSync(path.join(root,m[1])))throw Error('Missing asset in '+file+': '+m[1]);
 }
}
for(const file of fs.readdirSync(root).filter(f=>f.endsWith('.js')&&!f.startsWith('playwright')&&!['architect-assets.js','sw.js'].includes(f))){
 if(!runtimeFiles().includes(file))throw Error('Unregistered runtime asset: '+file);
}
console.log(count+' source scripts, generated scripts and all HTML entry assets checked.');
