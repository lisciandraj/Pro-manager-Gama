import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHandler,extractionInput,extractionSchema,validateExtraction} from '../supabase/functions/coco-supplier-ocr/handler.mjs';
const file={filename:'invoice.pdf',mime_type:'application/pdf',content_base64:btoa('%PDF-1.4\ninvoice fixture')};
const extracted={...Object.fromEntries(Object.keys(extractionSchema.properties).map(k=>[k,null])),lines:[],warnings:[]};
function harness({denied=false,existing=false,invalid=false,env={},identityId='11111111-1111-4111-8111-111111111111'}={}){
 const calls=[];
 const handler=createHandler({env:n=>({SUPABASE_URL:'https://db.invalid',SUPABASE_ANON_KEY:'public',SUPABASE_SERVICE_ROLE_KEY:'server-only',OPENAI_API_KEY:'fixture-api-key',...env}[n]),fetch:async(url,opts={})=>{
  const body=opts.body?JSON.parse(opts.body):null;calls.push({url,opts,body});
  if(url.includes('/auth/v1/user'))return Response.json({id:identityId});
  if(url.includes('/rpc/coco_ai_provider_budget'))return Response.json(body.p_action==='reserve'?{id:'22222222-2222-4222-8222-222222222222'}:{});
  if(url.includes('/rpc/')){if(denied)return Response.json({message:'ROLE_NOT_ALLOWED'},{status:403});if(body.p_action==='begin')return Response.json(existing?{id:'intake',existing:true,state:'review'}:{id:'intake',lease:'lease',state:'processing'});return Response.json({id:'intake',state:body.p_action==='complete'?'review':'failed'});}
  if(url.includes('gama_ai_settings'))return Response.json([]);
  if(url==='https://api.openai.com/v1/responses')return Response.json({status:'completed',output:[{content:[{type:'output_text',text:invalid?'bad':JSON.stringify(extracted)}]}]});
  throw Error('Unexpected destination');
 }});
 return {calls,invoke:headers=>handler(new Request('https://edge.invalid',{method:'POST',headers:{Authorization:'Bearer caller-token','Content-Type':'application/json',...headers},body:JSON.stringify(file)}))};
}
test('OCR extracts structured PDF data with no tools, no retention and caller-bound authorization',async()=>{
 const h=harness(),r=await h.invoke();assert.equal(r.status,200);assert.equal((await r.json()).state,'review');
 const ai=h.calls.find(x=>x.url.includes('openai.com'));assert.equal(ai.body.store,false);assert.equal(ai.body.tools,undefined);assert.equal(ai.body.input[1].content[1].type,'input_file');assert.match(ai.body.input[1].content[1].file_data,/^data:application\/pdf;base64,/);
 assert.equal(h.calls[0].body.p_action,'begin');assert.equal(h.calls[0].opts.headers.Authorization,'Bearer caller-token');assert.equal(h.calls.at(-1).body.p_action,'complete');assert.equal(h.calls.at(-1).opts.headers.Authorization,'Bearer caller-token');assert.equal(ai.opts.headers.Authorization,'Bearer fixture-api-key');
});
test('denied users, wrong origins and duplicates never reach AI or read server credentials',async()=>{
 const denied=harness({denied:true});assert.equal((await denied.invoke()).status,403);assert.equal(denied.calls.length,1);
 const wrong=harness();assert.equal((await wrong.invoke({Origin:'https://attacker.invalid'})).status,403);assert.equal(wrong.calls.length,0);
 const duplicate=harness({existing:true});assert.equal((await duplicate.invoke()).status,200);assert.equal(duplicate.calls.length,1);
});
test('unusable extraction is recorded as failed without creating or posting a bill',async()=>{
 const h=harness({invalid:true});assert.equal((await h.invoke()).status,502);assert.equal(h.calls.at(-1).body.p_action,'fail');assert.ok(!h.calls.some(x=>['draft','post'].includes(x.body?.p_action)));
});
test('image payloads and bounded extraction validation preserve unknown values',()=>{
 assert.equal(extractionInput({...file,mime_type:'image/png'},'fixture').input[1].content[1].type,'input_image');assert.ok(validateExtraction(extracted));assert.equal(validateExtraction({...extracted,lines:Array(201).fill({})}),false);assert.equal(validateExtraction({...extracted,currency:22}),false);
});

test('shared Auth verifies the exact subject at the authority and keeps OCR authorization and writes on Production',async()=>{
 const issuer='https://mknsaibrewksgomuslev.supabase.co',sub='11111111-1111-4111-8111-111111111111',key='sb_publishable_fixture';
 const env={COCO_AUTHORITY_URL:issuer,COCO_AUTHORITY_PUBLISHABLE_KEY:key};
 const bearer=claims=>'Bearer fixture.'+Buffer.from(JSON.stringify({iss:issuer+'/auth/v1',sub,session_id:'22222222-2222-4222-8222-222222222222',role:'authenticated',aud:'authenticated',is_anonymous:false,aal:'aal2',exp:Date.now()/1000+60,...claims})).toString('base64url')+'.fixture';
 const h=harness({env}),token=bearer({});assert.equal((await h.invoke({Authorization:token})).status,200);
 const [lookup,begin]=h.calls;
 assert.equal(begin.url,'https://db.invalid/rest/v1/rpc/gama_supplier_ocr');
 assert.equal(begin.opts.headers.Authorization,token);
 assert.equal(lookup.url,issuer+'/auth/v1/user');
 assert.equal(lookup.opts.headers.apikey,key);
 assert.equal(lookup.opts.headers.Authorization,token);
 assert.equal(lookup.opts.redirect,'error');
 assert.equal(h.calls.at(-1).url,begin.url);
 for(const claims of [{aal:'aal1'},{role:'service_role'},{iss:'https://other.invalid/auth/v1'}]){
  const blocked=harness({env});assert.equal((await blocked.invoke({Authorization:bearer(claims)})).status,401);
  assert.equal(blocked.calls.length,0);
 }
 const wrongUser=harness({env,identityId:'33333333-3333-4333-8333-333333333333'});
 assert.equal((await wrongUser.invoke({Authorization:token})).status,401);
 assert.deepEqual(wrongUser.calls.map(call=>call.url),[issuer+'/auth/v1/user']);
});
