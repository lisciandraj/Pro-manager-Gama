// Rebuild only when upgrading the pinned CRDT dependency or its owned entry.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..'),version=require('../node_modules/yjs/package.json').version;
if(version!==require('../package.json').devDependencies.yjs)throw Error('Unpinned Yjs build');
const file='yjs-'+version+'.js',dir=path.join(root,'assets/vendor');
const result=require('esbuild').buildSync({entryPoints:[path.join(root,'src/features/workhub/crdt-vendor.js')],bundle:true,write:false,format:'iife',target:'es2020',minify:true,legalComments:'inline'});
const bytes=Buffer.from('/* Yjs '+version+' / lib0. Licenses: '+file+'.LICENSE.txt. Owned wrapper: src/features/workhub/crdt-vendor.js. */\n'+result.outputFiles[0].text);
fs.writeFileSync(path.join(dir,file),bytes);
fs.writeFileSync(path.join(dir,file+'.LICENSE.txt'),'Yjs '+version+'\n'+fs.readFileSync(path.join(root,'node_modules/yjs/LICENSE'),'utf8')+'\nlib0\n'+fs.readFileSync(path.join(root,'node_modules/lib0/LICENSE'),'utf8'));
const manifestPath=path.join(dir,'manifest.json'),manifest=JSON.parse(fs.readFileSync(manifestPath,'utf8'));
manifest[file]={source:'npm:yjs@'+version+'; npm:lib0@'+require('../node_modules/lib0/package.json').version,sha256:crypto.createHash('sha256').update(bytes).digest('hex'),integrity:'sha384-'+crypto.createHash('sha384').update(bytes).digest('base64')};
fs.writeFileSync(manifestPath,JSON.stringify(manifest,null,2)+'\n');
console.log(file+': '+bytes.length+' bytes; package licenses and integrity recorded.');
