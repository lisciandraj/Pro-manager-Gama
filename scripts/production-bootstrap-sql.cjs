/* First-installation derivation only. Canonical historical SQL stays immutable.
 * The caller must bind every batch to the new, unassigned, empty production
 * installation. This module opens no connection and performs no database write.
 */
const crypto=require('node:crypto');
const {freshMigration}=require('./fresh-migration.cjs');
const sourceHashes=Object.freeze({
 '20260914213718_knowledge_base.sql':'5735a263c09650909f9511e75112da529c1268259f5604e0123a0badee47698a',
 '20260917194131_fleet_management_demo_data.sql':'23afd20954c8fc51921f077a8e7ed6bad566ac4cdf3cccbd2d3d14319ccf3066',
 '20260916093638_project_management.sql':'a196f396186e20fbc2a2f59bf429bbff9183ef5e204b9ae2f40f95867ca729f0',
 '20260920184630_p1_receipts_reconciliation_and_followup.sql':'776e92efd113994402418891c7177541685f0a70c7b2ba8602ef109da613ef79',
 '20260923102828_coco_erp_brand.sql':'c3e01bda8c31daea3f63a9bcaa6daae81049902036f48edd4e9139c4c5f8b664',
 '20260923211728_hr_base_role_org_chart.sql':'8a393fd6d81aa10bd3428a5712c36e00ebbc3554d967e9b5e63ca8cc94d54b32',
 '20261011211512_accounting_audit_core.sql':'9055989e75934fc874fc17c2aa70b9a0ac1a72da2077a3de2468251d4c11831d',
 '20261020193647_business_modules_contracts_expenses_sourcing.sql':'e54974ef125283c9471dc088f5261b2a0795fe54ead9052a40e737f7279b08eb'
});
const digest=s=>crypto.createHash('sha256').update(s).digest('hex');
function replaceOnce(sql,old,replacement,file){
 if(!sql.includes(old)||sql.indexOf(old)!==sql.lastIndexOf(old))throw Error('Unrecognized production bootstrap anchor: '+file);
 return sql.replace(old,replacement);
}
function productionMigration(file,original){
 if(sourceHashes[file]&&digest(original)!==sourceHashes[file])throw Error('Historical bootstrap source changed: '+file);
 let sql=freshMigration(file,original);
 if(file==='20260914213718_knowledge_base.sql'){
  const start="insert into public.knowledge_articles(slug,title,body,properties) values (";
  const index=sql.indexOf(start);
  if(index<0||index!==sql.lastIndexOf(start)||!sql.trimEnd().endsWith(');'))throw Error('Unrecognized knowledge bootstrap seed');
  sql=sql.slice(0,index)+`-- The initial guide is demo content, not part of the empty production schema.
do $$begin if exists(select 1 from public.knowledge_articles) then raise exception 'EMPTY_BOOTSTRAP_KNOWLEDGE_REQUIRED';end if;end $$;
`;
 }
 if(file==='20260917194131_fleet_management_demo_data.sql'){
  const start=sql.indexOf('do $demo$'),end=sql.indexOf('end $demo$;');
  if(start<0||end<start||sql.slice(end+'end $demo$;'.length).trim())throw Error('Unrecognized fleet bootstrap seed');
  sql=sql.slice(0,start)+`-- Keep is_demo columns; never insert the 33 demonstration business rows.
do $$begin
 if exists(select 1 from public.fleet_vehicles) or exists(select 1 from public.fleet_drivers)
 or exists(select 1 from public.fleet_assignments) or exists(select 1 from public.fleet_documents)
 or exists(select 1 from public.fleet_fuel_logs) or exists(select 1 from public.fleet_maintenance)
 then raise exception 'EMPTY_BOOTSTRAP_FLEET_REQUIRED';end if;
end $$;
`;
 }
 if(file==='20260916093638_project_management.sql'){
  const seeds=sql.split('\n').filter(line=>line.startsWith('insert into public.pm_templates(code,name,definition) values('));
  if(seeds.length!==6||seeds.some(line=>!line.endsWith(');')))throw Error('Unrecognized project configuration defaults');
  const insert=seeds.join('\n');
  sql=replaceOnce(sql,insert,'alter table public.pm_templates disable trigger pm_audit;\n'+insert+'\nalter table public.pm_templates enable trigger pm_audit;',file);
 }
 if(file==='20260920184630_p1_receipts_reconciliation_and_followup.sql'){
  const insert="insert into public.accounting_accounts(code,name,type,is_system) values('2090','Anticipos de clientes','liability',true) on conflict(code) do nothing;";
  sql=replaceOnce(sql,insert,'alter table public.accounting_accounts disable trigger ac_audit_accounting_accounts;\n'+insert+'\nalter table public.accounting_accounts enable trigger ac_audit_accounting_accounts;',file);
 }
 if(file==='20260923102828_coco_erp_brand.sql'){
  // This updates only the freshly seeded invitation template. Keep its final
  // configuration without inventing a user activity on an unused installation.
  sql='alter table public.access_invitation_template disable trigger erp_audit_capture;\n'+sql+'\nalter table public.access_invitation_template enable trigger erp_audit_capture;\n';
 }
 if(file==='20260923211728_hr_base_role_org_chart.sql'){
  const insert="insert into public.role_module_access(role,base_role,is_custom,display_name,disabled_modules)\nvalues('rrhh','rrhh',false,'Responsable RH','{}') on conflict (role) do nothing;";
  sql=replaceOnce(sql,insert,'alter table public.role_module_access disable trigger erp_audit_capture;\n'+insert+'\nalter table public.role_module_access enable trigger erp_audit_capture;',file);
 }
 if(file==='20261011211512_accounting_audit_core.sql'){
  const update="update public.accounting_accounts set cashflow_class='financing' where type='equity';";
  sql=replaceOnce(sql,update,'alter table public.accounting_accounts disable trigger ac_audit_accounting_accounts;\n'+update+'\nalter table public.accounting_accounts enable trigger ac_audit_accounting_accounts;',file);
 }
 if(file==='20261020193647_business_modules_contracts_expenses_sourcing.sql'){
  const insert="insert into public.app_modules(id,enabled) values('contracts',true),('expenses',true) on conflict(id) do nothing;";
  sql=replaceOnce(sql,insert,'alter table public.app_modules disable trigger coco_module_history;\n'+insert+'\nalter table public.app_modules enable trigger coco_module_history;',file);
 }
 return sql;
}
module.exports={productionMigration,sourceHashes,digest};
