const fs=require('node:fs'),path=require('node:path'),{execFileSync}=require('node:child_process');
const {root,generated}=require('./lib/assets.cjs');
const files=[...generated,'index.html','gama-site.html','camera-check.html','architect-core.js','architect-components.css','architect-base.css','architect-assets.js','sw.js'];
const before=new Map(files.map(file=>[file,fs.readFileSync(path.join(root,file))]));
execFileSync(process.execPath,[path.join(root,'scripts/build.cjs')],{stdio:'inherit'});
const changed=files.filter(file=>!before.get(file).equals(fs.readFileSync(path.join(root,file))));
if(changed.length)throw Error('Generated files were stale: '+changed.join(', '));
console.log('All generated files match canonical sources.');
