import test from 'node:test';
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import {encryptAiKey,decryptAiKey,aiKeyRotationRequired} from '../supabase/functions/_shared/ai-keyring.mjs';
import {createProviderBudget} from '../supabase/functions/_shared/ai-provider-budget.mjs';
import {questionScope,minimizeCatalog,minimizeOverview,scopedQuery,minimizeHistory} from '../supabase/functions/gama-assistant-ia/minimization.mjs';
const crypto=globalThis.crypto||webcrypto;
const environment=values=>name=>values[name];
const secret='fixture-primary-key-with-at-least-32-characters';
test('new provider settings require an independent key and support versioned coordinated rotation',async()=>{
 await assert.rejects(encryptAiKey('sk-fixture',environment({SUPABASE_SERVICE_ROLE_KEY:'database-key'})),/AI_ENCRYPTION_CONFIGURATION_REQUIRED/);
 const first=environment({GAMA_AI_ENCRYPTION_KEY_ID:'november',GAMA_AI_ENCRYPTION_KEY:secret});
 const encrypted=await encryptAiKey('sk-fixture',first);assert.match(encrypted,/^v2\.november\./);assert.equal(await decryptAiKey(encrypted,first),'sk-fixture');
 const next=environment({GAMA_AI_ENCRYPTION_KEY_ID:'december',GAMA_AI_ENCRYPTION_KEY:'another-dedicated-key-at-least-32-characters',GAMA_AI_ENCRYPTION_KEYS:JSON.stringify({november:secret})});
 assert.equal(aiKeyRotationRequired(encrypted,next),true);assert.equal(await decryptAiKey(encrypted,next),'sk-fixture');
 const migrated=await encryptAiKey(await decryptAiKey(encrypted,next),next);assert.match(migrated,/^v2\.december\./);assert.equal(await decryptAiKey(migrated,next),'sk-fixture');
 await assert.rejects(decryptAiKey(migrated,first),/AI_KEY_RECONNECT/);
 await assert.rejects(decryptAiKey(encrypted.replace('november','december'),next),/AI_KEY_RECONNECT/);
});
test('legacy database-derived envelopes are decrypt-only and survive an explicit retired-key transition',async()=>{
 const legacy='fixture-old-service-role-key',iv=crypto.getRandomValues(new Uint8Array(12));
 const key=await crypto.subtle.importKey('raw',await crypto.subtle.digest('SHA-256',new TextEncoder().encode('gama-assistant-ia-v1:'+legacy)),{name:'AES-GCM'},false,['encrypt']);
 const bytes=await crypto.subtle.encrypt({name:'AES-GCM',iv},key,new TextEncoder().encode('sk-old-fixture'));
 const b64=v=>Buffer.from(v).toString('base64'),stored=b64(iv)+'.'+b64(bytes);
 const rotated=environment({GAMA_AI_ENCRYPTION_KEY:secret,SUPABASE_SERVICE_ROLE_KEY:'new-database-key',GAMA_AI_LEGACY_ENCRYPTION_KEYS:JSON.stringify([legacy])});
 assert.equal(await decryptAiKey(stored,rotated),'sk-old-fixture');assert.equal(aiKeyRotationRequired(stored,rotated),true);
 const updated=await encryptAiKey(await decryptAiKey(stored,rotated),rotated);assert.match(updated,/^v2\./);
});
test('product questions cannot send unrelated HR, contact fields or old private answers to the provider',()=>{
 const scope=questionScope('Analiza el stock del producto CUADERNO');
 const catalog=minimizeCatalog([{table:'products',module:'products',columns:['id','name','stock']},{table:'customers',module:'clients',columns:['id','name','email','phone','notes']},{table:'hr_employee_private',module:'hr',columns:['salary','email']},{table:'profiles',module:'settings',columns:['email']}],scope);
 assert.ok(!catalog.some(t=>t.module==='hr'||t.table==='profiles'));assert.ok(!catalog.some(t=>t.table==='customers'));
 const general=minimizeCatalog([{table:'customers',module:'clients',columns:['id','name','email','phone','notes']}],questionScope('Analiza el negocio'));assert.deepEqual(general[0].columns,['id','name']);
 const overview=minimizeOverview({today:'2026-11-07',stock:{low_products:2},hr:{salary:'private'},receivables:{rows:[{customer_name:'private',email:'private'}]},sales:{total:7},coverage:[{module:'hr'},{module:'products'}]},scope);
 assert.equal(overview.hr,undefined);assert.equal(overview.receivables,undefined);assert.equal(overview.sales,undefined);
 assert.deepEqual(minimizeHistory([{question:'Previous question',answer:{report:{salary:'private'}}}]),[{question:'Previous question'}]);
 assert.throws(()=>scopedQuery({table:'customers',operation:'rows',columns:['email']},general),/COLUMN_NOT_ALLOWED/);
 assert.throws(()=>scopedQuery({table:'hr_employee_private',operation:'count'},catalog),/TABLE_NOT_ALLOWED/);
 const safe=scopedQuery({table:'customers',operation:'rows'},general);assert.deepEqual(safe.columns,['id','name']);
});
test('HR scope does not silently grant salary disclosure and SQL query filters obey the narrowed catalog',()=>{
 const catalog=[{table:'hr_employee_private',module:'hr',columns:['employee_id','salary','phone','notes']},{table:'hr_absences',module:'hr',columns:['id','kind','status']}];
 const absence=minimizeCatalog(catalog,questionScope('Ausencias del personal de RRHH'));
 assert.deepEqual(absence[0].columns,['employee_id']);
 assert.throws(()=>scopedQuery({table:'hr_employee_private',operation:'count',filters:[{column:'salary',operator:'gt',value:0}]},absence),/COLUMN_NOT_ALLOWED/);
 assert.ok(minimizeCatalog(catalog,questionScope('Nómina y salarios'))[0].columns.includes('salary'));
});
test('absence questions exclude complete payroll sources from the real HR schema while payroll questions retain them',()=>{
 // Current public HR table/column names, including Ecuador payroll sources.
 const schema={
  hr_absences:['id','employee_id','kind','start_date','end_date','days','status','created_at','start_fraction','end_fraction','decision_reason','reviewed_by','reviewed_at'],
  hr_payroll:['id','employee_id','period','source_ref','gross','net','employer_cost','cost_center','status','created_at','erp_reference','ec_calculation'],
  hr_payroll_payments:['id','payroll_id','paid_on','amount','reference','status','reason','created_at','financial_account_id'],
  hr_ec_benefit_payments:['id','benefit_id','request_key','amount','paid_on','financial_account_id','reference','entry_id','created_by','created_at'],
  hr_ec_benefits:['id','employee_id','kind','from_date','to_date','amount','source_id','entry_id','created_by','created_at'],
  hr_ec_employee_terms:['id','employee_id','effective_from','decimo13_mode','decimo14_mode','reserve_mode','region','other_fulltime','sectoral_minimum','work_ratio','bank_name','bank_number','bank_kind','beneficiary_id','evidence','created_by','created_at'],
  hr_ec_parameters:['id','year','parameters','evidence','confirmed_by','confirmed_at','created_at'],
  hr_ec_payroll_signatures:['payroll_id','employee_id','signed_by','signed_at','snapshot_hash','signature_png'],
  hr_ec_utilities:['id','year','request_key','net_profit','calculation','evidence','created_by','created_at','entry_id']
 };
 const catalog=Object.entries(schema).map(([table,columns])=>({table,module:'hr',columns}));
 const absences=minimizeCatalog(catalog,questionScope('Analiza las ausencias del personal'));
 assert.deepEqual(absences.map(t=>t.table),['hr_absences']);
 for(const table of Object.keys(schema).filter(t=>t!=='hr_absences'))assert.throws(()=>scopedQuery({table,operation:'count'},absences),/TABLE_NOT_ALLOWED/);
 assert.throws(()=>scopedQuery({table:'hr_payroll_payments',operation:'rows',columns:['amount','reference']},absences),/TABLE_NOT_ALLOWED/);
 const salaries=minimizeCatalog(catalog,questionScope('Analiza la nómina, salarios y pagos'));
 assert.deepEqual(salaries.map(t=>t.table),Object.keys(schema));
 assert.deepEqual(scopedQuery({table:'hr_payroll_payments',operation:'rows',columns:['amount','reference']},salaries).columns,['amount','reference']);
 assert.ok(salaries.find(t=>t.table==='hr_payroll').columns.includes('ec_calculation'));
});
test('global budget failure is closed and every attempted provider call finalizes once without content',async()=>{
 const calls=[],root='https://db.invalid';
 const withBudget=createProviderBudget({root,service:'server-fixture',fetcher:async(url,options)=>{
  const body=JSON.parse(options.body);calls.push(body);return Response.json(body.p_action==='reserve'?{id:'11111111-1111-4111-8111-111111111111'}:{});
 }});
 const context={operation:'stock',actorId:'11111111-1111-4111-8111-111111111111',requestId:'22222222-2222-4222-8222-222222222222',body:{model:'gpt-4.1-mini',max_output_tokens:1400,input:'private text'}};
 await assert.rejects(withBudget(context,async()=>{throw Error('provider timeout')}),/provider timeout/);
 assert.equal(calls[0].p_action,'reserve');assert.equal(calls[1].p_action,'finish');assert.equal(calls[1].p_data.success,false);assert.equal(calls.length,2);assert.ok(!JSON.stringify(calls).includes('private text'));
 let invoked=false;const denied=createProviderBudget({root,service:'server-fixture',fetcher:async()=>Response.json({message:'AI_BUDGET_CONCURRENCY_LIMIT'},{status:429})});
 await assert.rejects(denied(context,async()=>{invoked=true}),/AI_BUDGET_CONCURRENCY_LIMIT/);assert.equal(invoked,false);
});
test('admission and finalization logs have distinct safe events and no provider body or context',async()=>{
 const messages=[],warning=console.warn;console.warn=value=>messages.push(JSON.parse(value));
 const context={operation:'ocr',actorId:'private-actor',requestId:'private-request',body:{model:'gpt-4.1-mini',max_output_tokens:1000,input:'private-document'}};
 try{
  const denied=createProviderBudget({root:'https://db.invalid',service:'private-service-key',fetcher:async()=>Response.json({message:'provider secret private-email@example.invalid'},{status:503})});
  await assert.rejects(denied(context,async()=>assert.fail('no paid call')),/AI_BUDGET_UNAVAILABLE/);
  assert.deepEqual(messages,[{event:'ai_provider_admission_denied',code:'AI_BUDGET_UNAVAILABLE'}]);messages.length=0;
  const deferred=createProviderBudget({root:'https://db.invalid',service:'private-service-key',fetcher:async(_url,options)=>JSON.parse(options.body).p_action==='reserve'?Response.json({id:'fixture-lease'}):Response.json({message:'AI_BUDGET_CONFIGURATION_REQUIRED',details:'private-provider-body'},{status:503})});
  assert.deepEqual(await deferred(context,async()=>({usage:{input_tokens:4,output_tokens:5}})),{usage:{input_tokens:4,output_tokens:5}});
  assert.deepEqual(messages,[{event:'ai_provider_finalization_deferred',code:'AI_BUDGET_FINALIZATION_DEFERRED'}]);
 }finally{console.warn=warning;}
});
