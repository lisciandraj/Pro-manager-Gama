const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'config/runtime-assets.json'),'utf8'));
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex').slice(0,12);
const generated=[...manifest.scripts,...manifest.styles,...(manifest.startupBundles||[])].map(x=>x.output);
const runtimeFiles=()=>[...new Set([...generated,'architect-core.js','architect-components.css','architect-base.css','gama-i18n-catalog.js','gama-i18n-server.js'])].sort();
const header=source=>'/* Generated from '+source+'. Edit the source and run npm run build. */\n';
// Preserve public/global identifiers and classic-script scope while removing
// comments and whitespace. Every generated runtime script uses this contract.
const runtimeScript=source=>header(source)+require('esbuild').transformSync(fs.readFileSync(path.join(root,source),'utf8'),{
 loader:'js',target:'es2020',minifyWhitespace:true,minifySyntax:true,minifyIdentifiers:false,legalComments:'none'
}).code;
function validateManifest(){
 const outputs=new Set(),sources=new Set();
 for(const item of [...manifest.scripts,...manifest.styles]){
  if(!item.source.startsWith('src/')||item.source.includes('..')||item.output.includes('/')||outputs.has(item.output)||sources.has(item.source))throw Error('Invalid/duplicate asset: '+JSON.stringify(item));
  if(!fs.existsSync(path.join(root,item.source)))throw Error('Missing source: '+item.source);
  outputs.add(item.output);sources.add(item.source);
 }
 for(const file of manifest.vendors){
  if(!/^assets\/vendor\/[a-zA-Z0-9._-]+\.js$/.test(file)||!fs.existsSync(path.join(root,file)))throw Error('Invalid vendor asset: '+file);
 }
 const bundled=new Set();
 for(const bundle of manifest.startupBundles||[]){
  if(!/^[a-z0-9-]+\.js$/.test(bundle.output)||outputs.has(bundle.output))throw Error('Invalid bundle: '+bundle.output);
  outputs.add(bundle.output);
  for(const file of bundle.files){if(!manifest.scripts.some(s=>s.output===file)||bundled.has(file))throw Error('Invalid/duplicate bundle member: '+file);bundled.add(file)}
 }
 for(const file of manifest.moduleStyles)if(!fs.existsSync(path.join(root,file)))throw Error('Missing stylesheet: '+file);
}
module.exports={root,manifest,hash,generated,runtimeFiles,header,runtimeScript,validateManifest};
