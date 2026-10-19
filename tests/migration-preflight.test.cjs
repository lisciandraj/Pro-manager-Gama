const {test}=require('node:test'),assert=require('node:assert/strict');
const {verify}=require('../scripts/migration-preflight.cjs');
const baseline=require('../supabase/production-baseline-20261019.json'),release=require('../supabase/audit-release-manifest.json');
test('release gate accepts the observed baseline and refuses missing, changed or unknown ledger entries',()=>{
 assert.equal(verify(baseline.migrations,release).pending.length,release.migrations.length);
 assert.throws(()=>verify(baseline.migrations.slice(1),release),/BASELINE_DRIFT/);
 assert.throws(()=>verify([...baseline.migrations,{version:'20990101000000',name:'surprise',hash:'x'}],release),/UNREVIEWED_REMOTE_MIGRATION/);
 assert.throws(()=>verify(baseline.migrations,{...release,project_id:'wrong'}),/PROJECT_MISMATCH/);
 assert.throws(()=>verify(baseline.migrations,{...release,migrations:release.migrations.map(r=>({...r,sha256:'bad'}))}),/RELEASE_CONTENT_CHANGED/);
});
