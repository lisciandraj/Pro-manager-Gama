/** Read-only release gate. It never repairs a ledger or executes migrations. */
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..');
function verify(remote,release){
 const baseline=require('../supabase/production-baseline-20261019.json');
 if(release.project_id!==baseline.project_id)throw Error('PROJECT_MISMATCH');
 const live=new Map(remote.map(r=>[r.version,r]));
 if(live.size!==remote.length)throw Error('DUPLICATE_REMOTE_VERSION');
 // apply_migration can assign a different ledger timestamp than the local CLI.
 // Keep both identifiers explicit; never rename an existing migration or repair a ledger.
 const appliedVersion=r=>r.applied_version||r.version;
 const approved=new Set(release.migrations.map(appliedVersion));
 if(approved.size!==release.migrations.length)throw Error('DUPLICATE_RELEASE_VERSION');
 for(const row of baseline.migrations){const actual=live.get(row.version);if(!actual||actual.name!==row.name||actual.hash!==row.hash)throw Error('BASELINE_DRIFT: '+row.version)}
 for(const row of remote)if(!baseline.migrations.some(r=>r.version===row.version)&&!approved.has(row.version))throw Error('UNREVIEWED_REMOTE_MIGRATION: '+row.version);
 for(const row of release.migrations){
  if(!/^\d{14}_[a-z0-9_]+\.sql$/.test(row.file)||row.version!==row.file.split('_')[0]||!/^\d{14}$/.test(appliedVersion(row)))throw Error('INVALID_RELEASE_MIGRATION');
  const file=path.join(root,'supabase/migrations',row.file),sql=fs.readFileSync(file);
  if(crypto.createHash('sha256').update(sql).digest('hex')!==row.sha256)throw Error('RELEASE_CONTENT_CHANGED: '+row.file);
  if(/(?:reset_product_catalog|controlled_product_catalog_reset)/.test(row.file))throw Error('HISTORICAL_RESET_FORBIDDEN');
  if(live.has(appliedVersion(row))&&live.get(appliedVersion(row)).hash!==row.applied_hash)throw Error('APPLIED_CONTENT_NOT_VERIFIED: '+row.file);
 }
 return {baseline:baseline.migrations.length,pending:release.migrations.filter(r=>!live.has(appliedVersion(r))).map(r=>r.file),mode:'individual-reviewed-migrations-only'};
}
module.exports={verify};
if(require.main===module){try{const [remote,release]=process.argv.slice(2);if(!remote||!release)throw Error('Usage: node scripts/migration-preflight.cjs remote-ledger.json release-manifest.json');console.log(JSON.stringify(verify(JSON.parse(fs.readFileSync(remote)),JSON.parse(fs.readFileSync(release))),null,2))}catch(e){console.error(e.message);process.exitCode=1}}
