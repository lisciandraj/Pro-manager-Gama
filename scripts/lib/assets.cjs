const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'config/runtime-assets.json'),'utf8'));
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex').slice(0,12);
const generated=[...manifest.scripts,...manifest.styles].map(x=>x.output);
const runtimeFiles=()=>[...new Set([...generated,'architect-core.js','architect-components.css','architect-base.css','gama-i18n-catalog.js'])].sort();
const header=source=>'/* Generated from '+source+'. Edit the source and run npm run build. */\n';
function validateManifest(){
 const outputs=new Set(),sources=new Set();
 for(const item of [...manifest.scripts,...manifest.styles]){
  if(!item.source.startsWith('src/')||item.source.includes('..')||item.output.includes('/')||outputs.has(item.output)||sources.has(item.source))throw Error('Invalid/duplicate asset: '+JSON.stringify(item));
  if(!fs.existsSync(path.join(root,item.source)))throw Error('Missing source: '+item.source);
  outputs.add(item.output);sources.add(item.source);
 }
 for(const file of manifest.moduleStyles)if(!fs.existsSync(path.join(root,file)))throw Error('Missing stylesheet: '+file);
}
module.exports={root,manifest,hash,generated,runtimeFiles,header,validateManifest};
