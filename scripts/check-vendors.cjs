const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..'),directory=path.join(root,'assets/vendor'),manifest=require('../assets/vendor/manifest.json');
for(const [file,entry] of Object.entries(manifest)){
 const bytes=fs.readFileSync(path.join(directory,file));
 if(crypto.createHash('sha256').update(bytes).digest('hex')!==entry.sha256||'sha384-'+crypto.createHash('sha384').update(bytes).digest('base64')!==entry.integrity)throw Error('Vendor integrity mismatch: '+file);
}
for(const file of fs.readdirSync(directory).filter(f=>f.endsWith('.js')))if(!manifest[file])throw Error('Unregistered vendor: '+file);
console.log(Object.keys(manifest).length+' audited vendor hashes verified.');
