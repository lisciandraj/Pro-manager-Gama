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
