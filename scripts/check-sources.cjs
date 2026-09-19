const fs=require('node:fs'),path=require('node:path'),acorn=require('acorn');
const root=path.join(__dirname,'..');let count=0;
for(const f of fs.readdirSync(root).filter(f=>f.endsWith('.js'))){acorn.parse(fs.readFileSync(path.join(root,f),'utf8'),{ecmaVersion:'latest',sourceType:'script'});count++;}
const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
for(const m of html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)){if(m[1].trim())acorn.parse(m[1],{ecmaVersion:'latest',sourceType:'script'});}
for(const m of html.matchAll(/(?:src|href)="([^"?#]+\.(?:js|css))(?:\?[^"#]*)?"/g))if(!m[1].startsWith('http')&&!fs.existsSync(path.join(root,m[1])))throw Error('Missing asset: '+m[1]);
console.log(count+' scripts, inline entry points and asset references checked.');
