// A production-only data repair cannot be replayed on an empty catalog.
// Keep the immutable applied SQL in migrations/ and adapt only derived fixtures.
const repair='20260912081917_deduplicate_products_keep_most_complete.sql';
function freshMigration(file,sql){
 if(file!==repair)return sql;
 const marker='create temporary table dedup_ranked';
 if(!sql.includes(marker))throw Error('Unrecognized historical repair: '+file);
 return `-- Fresh-database reconstruction only; original repair remains in canonical history.
do $$ begin
 if exists(select 1 from public.products) then
  raise exception 'Fresh reconstruction requires an empty product catalog';
 end if;
end $$;
`+sql.slice(0,sql.indexOf(marker));
}
// Only disposable fixtures replace managed networking and scheduling with the
// platform-bootstrap stubs. Production always applies the original migration.
function fixtureMigration(file,sql){return freshMigration(file,sql.replace(/create extension if not exists (pg_cron|pg_net)(?: with schema \w+)?;/gi,''));}
module.exports={freshMigration,fixtureMigration};
