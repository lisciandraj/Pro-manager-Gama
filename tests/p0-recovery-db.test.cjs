const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs'),{drill,verify,hash}=require('../scripts/restore-application-export.cjs');
test('Scoped business export restores declared data and relations without credentials or capability tokens',async()=>{const db=await restore(),a=uuid(),survey=uuid(),oldToken=uuid();let data,response;try{
 await db.exec(`insert into auth.users(id,email) values('${a}','restore-admin@example.invalid');update profiles set role='administrador',active=true where id='${a}';insert into suppliers(name) values('Restore Supplier');select set_config('request.jwt.claim.sub','${a}',false);`);
 await db.query("insert into private.surveys(id,title,token,state,questions,created_by) values($1,'Recovery fixture survey',$2,'open',$3::jsonb,$4)",[survey,oldToken,JSON.stringify([{id:'rating',type:'rating',title:'Service',required:true}]),a]);
 const secret=(await db.query('select token from private.website_public_connection where id')).rows[0].token;
 await db.query("select set_config('request.jwt.claim.sub','',false),set_config('request.headers',$1,false)",[JSON.stringify({'x-coco-site-token':secret})]);await db.exec('set role anon');
 response=(await db.query("select public.gama_survey('submit',$1::jsonb) r",[JSON.stringify({token:oldToken,request_key:uuid(),visitor:'198.51.100.74',consent:true,answers:{rating:5}})])).rows[0].r;
 await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[a]);
 await db.query("insert into private.offline_proof_keys(actor_id,key_material) values($1,$2)",[a,'2'.repeat(64)]);
 await db.exec('set role authenticated');data=(await db.query('select gama_recovery_export() result')).rows[0].result;data.files=[];
 }finally{await db.close()}
 assert.equal(data.scope,'business_data_and_files');assert.equal(data.coverage.full_backup,false);
 assert.ok(data.tables['private.erp_reference_counters']);assert.ok(data.tables['private.gama_alert_handling']);assert.ok(!Object.hasOwn(data.tables,'private.offline_proof_keys'));
 assert.ok(data.coverage.excluded_tables.includes('private.offline_proof_keys'));assert.equal(data.tables['private.surveys'].find(s=>s.id===survey).token,undefined);assert.ok(!JSON.stringify(data).includes(oldToken));
 const payload=JSON.stringify(data),envelope={format:'architect-verified-export',payload,sha256:hash(payload)},result=await drill(envelope,{onRestored:async restored=>{
  const fresh=(await restored.query('select token from private.surveys where id=$1',[survey])).rows[0].token;assert.notEqual(fresh,oldToken);
  const saved=(await restored.query('select payload,answers from private.survey_responses where id=$1',[response.id])).rows[0];assert.equal(saved.payload.token,undefined);assert.equal(saved.answers.rating,5);
  await restored.query("select set_config('request.jwt.claim.sub','',false),set_config('request.jwt.claims','{}',false)");await restored.exec('set role anon');
  await restored.exec('savepoint invalid_survey_token');
  await assert.rejects(restored.query("select public.gama_survey('get',$1::jsonb)",[JSON.stringify({token:oldToken})]),/SURVEY_UNAVAILABLE/);
  await restored.exec('rollback to savepoint invalid_survey_token');
  const readable=(await restored.query("select public.gama_survey('get',$1::jsonb) r",[JSON.stringify({token:fresh})])).rows[0].r;assert.equal(readable.title,'Recovery fixture survey');await restored.exec('reset role');
 }});
 assert.ok(result.success);assert.equal(result.tables,Object.keys(data.tables).length);assert.ok(result.relations>100);assert.match(result.scope,/scoped business data/);assert.throws(()=>verify({...envelope,payload:payload+' '}),/CHECKSUM/);
 const legacy={...data,scope:'application_data_and_files'};delete legacy.coverage;const oldPayload=JSON.stringify(legacy),oldEnvelope={format:'architect-verified-export',payload:oldPayload,sha256:hash(oldPayload)};
 assert.equal(verify(oldEnvelope).scope,'application_data_and_files');await assert.rejects(drill(oldEnvelope),/LEGACY_EXPORT_READ_ONLY/);
});
