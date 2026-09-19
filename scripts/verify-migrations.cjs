const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.join(__dirname,'..'),dir=path.join(root,'supabase/migrations');
const ledger=JSON.parse(fs.readFileSync(path.join(root,'supabase/migration-history.json'),'utf8'));
for(const row of ledger.applied){const file=path.join(dir,row.file);if(!fs.existsSync(file))throw Error('Missing applied migration: '+row.file);const hash=crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');if(hash!==row.sha256)throw Error('Applied migration was rewritten: '+row.file);}
const files=fs.readdirSync(dir).filter(f=>f.endsWith('.sql')).sort(),versions=files.map(f=>f.split('_')[0]);
if(new Set(versions).size!==versions.length)throw Error('Duplicate migration timestamp');
if(files.some(f=>!/^\d{14}_[a-z0-9_]+\.sql$/.test(f)))throw Error('Invalid migration filename');
console.log(ledger.applied.length+' applied migrations verified; '+(files.length-ledger.applied.length)+' new migrations.');
