const fs=require('node:fs'),path=require('node:path');
const {freshMigration}=require('./fresh-migration.cjs');
require('./verify-migrations.cjs');
const root=path.join(__dirname,'..'),source=path.join(root,'supabase/migrations');
const target=path.join(root,'.build/fresh-database/supabase/migrations');
fs.mkdirSync(target,{recursive:true});
for(const file of fs.readdirSync(target))if(file.endsWith('.sql'))fs.unlinkSync(path.join(target,file));
for(const file of fs.readdirSync(source).filter(f=>f.endsWith('.sql'))){
 fs.writeFileSync(path.join(target,file),freshMigration(file,fs.readFileSync(path.join(source,file),'utf8')));
}
console.log('Derived empty-database migrations: .build/fresh-database/supabase/migrations');
console.log('No database connection or production change was made. See supabase/README.md.');
