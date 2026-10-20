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
test('a different applied timestamp requires the explicit verified hash and cannot hide a second migration',()=>{
 const one=release.migrations[0],version='20990101000000',hash='verified-ledger-content';
 const mapped={...release,migrations:[{...one,applied_version:version,applied_hash:hash}]};
 const remote=[...baseline.migrations,{version,name:'reviewed',hash}];
 assert.deepEqual(verify(remote,mapped).pending,[]);
 assert.throws(()=>verify(remote,{...mapped,migrations:[{...mapped.migrations[0],applied_hash:'changed'}]}),/APPLIED_CONTENT_NOT_VERIFIED/);
 assert.throws(()=>verify(remote,{...mapped,migrations:[mapped.migrations[0],mapped.migrations[0]]}),/DUPLICATE_RELEASE_VERSION/);
});
