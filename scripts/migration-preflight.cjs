/** Read-only release gate. It never repairs a ledger or executes migrations. */
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..');
function verify(remote,release){
 const baseline=require('../supabase/production-baseline-20261019.json');
 if(release.project_id!==baseline.project_id)throw Error('PROJECT_MISMATCH');
 const live=new Map(remote.map(r=>[r.version,r]));
 if(live.size!==remote.length)throw Error('DUPLICATE_REMOTE_VERSION');
 const approved=new Set(release.migrations.map(r=>r.version));
 for(const row of baseline.migrations){const actual=live.get(row.version);if(!actual||actual.name!==row.name||actual.hash!==row.hash)throw Error('BASELINE_DRIFT: '+row.version)}
 for(const row of remote)if(!baseline.migrations.some(r=>r.version===row.version)&&!approved.has(row.version))throw Error('UNREVIEWED_REMOTE_MIGRATION: '+row.version);
 for(const row of release.migrations){
  if(!/^\d{14}_[a-z0-9_]+\.sql$/.test(row.file)||row.version!==row.file.split('_')[0])throw Error('INVALID_RELEASE_MIGRATION');
  const file=path.join(root,'supabase/migrations',row.file),sql=fs.readFileSync(file);
  if(crypto.createHash('sha256').update(sql).digest('hex')!==row.sha256)throw Error('RELEASE_CONTENT_CHANGED: '+row.file);
  if(/(?:reset_product_catalog|controlled_product_catalog_reset)/.test(row.file))throw Error('HISTORICAL_RESET_FORBIDDEN');
  if(live.has(row.version)&&live.get(row.version).hash!==row.applied_hash)throw Error('APPLIED_CONTENT_NOT_VERIFIED: '+row.file);
 }
 return {baseline:baseline.migrations.length,pending:release.migrations.filter(r=>!live.has(r.version)).map(r=>r.file),mode:'individual-reviewed-migrations-only'};
}
module.exports={verify};
if(require.main===module){try{const [remote,release]=process.argv.slice(2);if(!remote||!release)throw Error('Usage: node scripts/migration-preflight.cjs remote-ledger.json release-manifest.json');console.log(JSON.stringify(verify(JSON.parse(fs.readFileSync(remote)),JSON.parse(fs.readFileSync(release))),null,2))}catch(e){console.error(e.message);process.exitCode=1}}
