// Produce a guarded, non-destructive server rollback from the verified private
// backup. Never commit the resulting SQL: it contains the installation's code.
const fs=require('node:fs'),path=require('node:path');
const [directory,output]=process.argv.slice(2);
if(!directory||!output)throw Error('Usage: node scripts/prepare-sales-rollback.cjs <backup-directory> <output.sql>');
const records=JSON.parse(fs.readFileSync(path.join(directory,'all-modified-functions-before.json'),'utf8'));
if(records.length!==18||records.some(r=>!r.definition?.startsWith('CREATE OR REPLACE FUNCTION ')))throw Error('Incomplete function snapshot');
const checks=`begin;
set local lock_timeout='10s';
select pg_advisory_xact_lock(741932,1);
do $$ begin
 if exists(select 1 from private.sales_down_payments) or exists(select 1 from private.sales_dossier_lines where invoice_policy='ordered')
  or exists(select 1 from public.erp_price_tiers where price_method<>'fixed' or product_category is not null)
  or exists(select 1 from private.sales_portal_acceptances)
  or exists(select 1 from private.sales_quote_extras where blocks<>'[]'::jsonb)
  or exists(select 1 from private.sales_activities) then
  raise exception 'ROLLBACK_REQUIRES_FORWARD_COMPATIBLE_REVIEW: new commercial features already used';
 end if;
end $$;
-- Retain all additive tables, lineage, terms and events. Restore existing entry
-- points only. No historical data, Storage media or migration journal is erased.
`;
let sql=checks;
for(const r of records){
 sql+=r.definition+';\n';
 // CREATE OR REPLACE preserves the current ACL. Rebuild the captured one for
 // these explicit roles, without widening private helper access.
 const signature=r.schema+'.'+r.proname+'('+r.args+')';
 sql+='revoke all on function '+signature+' from public,anon,authenticated;\n';
 const acl=r.acl||'';
 for(const role of ['anon','authenticated'])if(acl.includes(role+'=X/'))sql+='grant execute on function '+signature+' to '+role+';\n';
 if(/(^\{|,)=X\//.test(acl))sql+='grant execute on function '+signature+' to public;\n';
}
sql+="revoke all on function public.gama_sales_dossier(text,jsonb),private.gama_sales_dossier(text,jsonb) from public,anon,authenticated;\nnotify pgrst,'reload schema';\ncommit;\n";
fs.writeFileSync(output,sql,{mode:0o600});console.log('Guarded rollback prepared:',output);
