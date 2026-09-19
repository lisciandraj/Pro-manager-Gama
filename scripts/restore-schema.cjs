const fs=require('node:fs'),path=require('node:path');
const {PGlite}=require('@electric-sql/pglite');
const {pg_trgm}=require('@electric-sql/pglite/contrib/pg_trgm');
const {unaccent}=require('@electric-sql/pglite/contrib/unaccent');
const {freshMigration}=require('./fresh-migration.cjs');
async function restore({before}={}){
 const db=new PGlite({extensions:{pg_trgm,unaccent}});
 await db.exec(fs.readFileSync(path.join(__dirname,'../tests/platform-bootstrap.sql'),'utf8'));
 const directory=path.join(__dirname,'../supabase/migrations');
 for(const file of fs.readdirSync(directory).filter(f=>f.endsWith('.sql')).sort()){
  if(before && file>=before)break;
  // PGlite supplies gen_random_uuid in core; managed Cron is represented above.
  let sql=fs.readFileSync(path.join(directory,file),'utf8').replace(/create extension if not exists (pgcrypto|pg_cron)(?: with schema \w+)?;/gi,'');
  // This audited repair was intentionally bound to 312 existing production rows.
  // Reconstruct its archive schema, but do not replay a data repair on an empty database.
  sql=freshMigration(file,sql);
  try {await db.exec(sql);}catch(e){await db.close();throw Error(file+': '+e.message,{cause:e});}
 }
 return db;
}
module.exports={restore};
if(require.main===module)restore().then(async db=>{const r=await db.query("select count(*)::int tables,count(*) filter(where relrowsecurity)::int rls from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'");console.log(r.rows);await db.close();}).catch(e=>{console.error(e.message);process.exitCode=1;});
