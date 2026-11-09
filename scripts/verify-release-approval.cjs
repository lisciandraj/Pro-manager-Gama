const fs=require('node:fs');
const {authorizePromotion}=require('./lib/release-policy.cjs');
const checks=JSON.parse(process.env.COCO_RELEASE_CHECKS||'null');
const manifest=JSON.parse(fs.readFileSync(process.env.COCO_RELEASE_MANIFEST||'.build/release-provenance/release-manifest.json','utf8'));
if(manifest.schema_version!==1||manifest.component!=='erp'||manifest.source_dirty!==false)throw Error('RELEASE_PROVENANCE_REQUIRED');
authorizePromotion({event:process.env.GITHUB_EVENT_NAME,ref:process.env.GITHUB_REF,commit:process.env.GITHUB_SHA,artifactCommit:manifest.source_commit,checks});
console.log('Same-revision release checks passed; promotion is allowed.');
