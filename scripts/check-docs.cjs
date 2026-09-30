const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const files=['README.md','AGENTS.md','supabase/README.md','services/sri/README.md','config/localizations/README.md'];
function collect(dir){for(const entry of fs.readdirSync(path.join(root,dir),{withFileTypes:true})){const file=dir+'/'+entry.name;if(entry.isDirectory())collect(file);else if(file.endsWith('.md'))files.push(file);}}
collect('docs');
const broken=[];
for(const file of files){
 const source=fs.readFileSync(path.join(root,file),'utf8');
 for(const match of source.matchAll(/\]\(([^)\s]+)\)/g)){
  const link=match[1];if(/^[a-z]+:|^#|^\/\//i.test(link))continue;
  const target=path.resolve(root,path.dirname(file),link.split('#')[0]);
  if(!fs.existsSync(target))broken.push(file+': '+link);
 }
}
if(broken.length)throw Error('Broken documentation links:\n'+broken.join('\n'));
console.log(files.length+' documentation files: local links valid.');
