/* Immutable first-installation boundary. Later application migrations belong to
 * separate reviewed releases; they must never alter the prepared installation.
 */
const fs=require('node:fs'),path=require('node:path');
const {productionMigration,digest}=require('./production-bootstrap-sql.cjs');
const sourceCount=362,lastFile='20261107195941_coco_environment_isolation.sql';
const installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e';
// These security PRs were integrated after the baseline was approved. Their
// original versions are retained for the separate post-bootstrap release.
const separateSecurityMigrations=new Set([
 '20261029233001_security_boundary_alignment.sql',
 '20261029233002_received_sri_environment.sql',
 '20261029233003_returns_authority_and_financial_lineage.sql',
 '20261029233004_contract_schedule_authority.sql',
 '20261029233005_alert_source_authority.sql',
 '20261029233006_supplier_receipt_and_cancel_integrity.sql',
 '20261029233007_review_moderation_persistence.sql',
 '20261029233008_legacy_invoice_authority_and_capacity.sql',
 '20261029233009_storage_structure_authority.sql',
 '20261029233010_customer_collection_authority_and_capacity.sql',
 '20261029233011_native_crm_authority.sql',
 '20261107195204_audit_access_hardening.sql',
 '20261107195556_audit_workhub_quotas.sql',
 '20261107195614_audit_ai_budget.sql',
 '20261107195615_audit_identity_policy.sql',
 '20261107195905_audit_receipt_validation.sql',
]);
function loadSnapshot(directory){
 const files=fs.readdirSync(directory).filter(file=>/^\d{14}_[a-z0-9_]+\.sql$/.test(file)).sort();
 const isInitial=file=>file<=lastFile&&!separateSecurityMigrations.has(file);
 const initial=files.filter(isInitial),excluded=files.filter(file=>!isInitial(file));
 if(initial.length!==sourceCount||initial.at(-1)!==lastFile)throw Error('First-installation snapshot source count changed; review the historical snapshot');
 const originals=initial.map(file=>{const original=fs.readFileSync(path.join(directory,file),'utf8');return {file,original,sha256:digest(original)};});
 if(digest(originals.map(source=>source.file+':'+source.sha256).join('\n'))!==installation)throw Error('Historical production bootstrap snapshot changed');
 const sources=originals.map(({file,original,sha256})=>{const sql=productionMigration(file,original);return {file,sha256,derived_sha256:digest(sql),sql};});
 return {sources,excluded};
}
module.exports={loadSnapshot,sourceCount,lastFile,installation};
