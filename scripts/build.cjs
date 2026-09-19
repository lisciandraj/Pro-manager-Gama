const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{execFileSync}=require('node:child_process');
const root=path.join(__dirname,'..');
execFileSync(process.execPath,[path.join(root,'node_modules/vite/bin/vite.js'),'build'],{cwd:root,stdio:'inherit'});
fs.copyFileSync(path.join(root,'.build/client/architect-core.js'),path.join(root,'architect-core.js'));
const css=['src/ui/module-styles.css','src/ui/components.css'].map(f=>fs.readFileSync(path.join(root,f),'utf8')).join('\n');
fs.writeFileSync(path.join(root,'architect-components.css'),css);
fs.copyFileSync(path.join(root,'src/ui/base.css'),path.join(root,'architect-base.css'));
const assets=Object.fromEntries(fs.readdirSync(root).filter(f=>/\.(js|css)$/.test(f)&&f!=='architect-assets.js').map(file=>[file,file+'?v='+crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex').slice(0,12)]));
fs.writeFileSync(path.join(root,'architect-assets.js'),'/* Generated runtime asset versions. */\nwindow.ArcAssets='+JSON.stringify(assets,null,2)+';\n');
// Source-based Pages hosting remains supported. Every local loader uses its content hash.
let html=fs.readFileSync(path.join(root,'index.html'),'utf8');
if(!html.includes('src="architect-assets.js'))html=html.replace('<script src="architect-core.js','<script src="architect-assets.js"></script>\n<script src="architect-core.js');
if(!html.includes('href="architect-components.css'))html=html.replace(/<link rel="stylesheet" href="architect-ui.css/, '<link rel="stylesheet" href="architect-components.css">\n<link rel="stylesheet" href="architect-ui.css');
html=html.replace(/\b(src|href)="([^"?#]+\.(?:js|css))(?:\?[^"#]*)?"/g,(full,key,file)=>{if(/^https?:/.test(file)||!fs.existsSync(path.join(root,file)))return full;const hash=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex').slice(0,12);return `${key}="${file}?v=${hash}"`;});
fs.writeFileSync(path.join(root,'index.html'),html);
const out=path.join(root,'dist');fs.rmSync(out,{recursive:true,force:true});fs.mkdirSync(out);
for(const file of fs.readdirSync(root)){if(/\.(js|css|html|png|svg|ico|webmanifest)$/.test(file)||file==='manifest.json')fs.copyFileSync(path.join(root,file),path.join(out,file));}
for(const folder of ['assets','config','fonts'])if(fs.existsSync(path.join(root,folder)))fs.cpSync(path.join(root,folder),path.join(out,folder),{recursive:true});
fs.writeFileSync(path.join(out,'.nojekyll'),'');
console.log('Static release generated in dist/; source loaders use content hashes.');
