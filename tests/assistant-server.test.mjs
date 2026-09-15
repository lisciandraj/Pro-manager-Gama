import test from 'node:test';
import assert from 'node:assert/strict';
import {createHandler} from '../supabase/functions/gama-assistant-ia/handler.mjs';
import {diagnostic} from '../supabase/functions/gama-assistant-ia/reports.mjs';
const uid='11111111-1111-4111-8111-111111111111',rid='22222222-2222-4222-8222-222222222222';
const overview={as_of:'2026-09-15T12:00:00Z',today:'2026-09-15',period:{from:'2026-09-01',to:'2026-09-15'},currency:'USD',coverage:[{table:'products',module:'products',rows:250}],stock:{low_products:3},sales:{registered_subtotal:150,registered_total:180,invoice_count:2,receipts:50,quotes_to_follow:1},receivables:{total:2,metrics:{balance:130,overdue:80,due_soon:50},rows:[]},purchases:{late_count:1},logistics:{late_count:2},crm:{open_opportunities:4,late_activities:1},hr:{pending_absences:1},knowledge:{articles:1}};
const reply=(body,status=200)=>new Response(body==null?null:JSON.stringify(body),{status,headers:{'Content-Type':'application/json'}});
function fixture(options={}){
 const calls=[],saved=[];let settings=[];let openaiCount=0;
 const handler=createHandler({env:k=>({SUPABASE_URL:'https://test.supabase.co',SUPABASE_ANON_KEY:'anon-test',SUPABASE_SERVICE_ROLE_KEY:'server-test-key',OPENAI_API_KEY:options.key?'sk-test-only-abcdefghijklmnopqrstuvwxyz':undefined}[k]),fetch:async(url,init={})=>{
  calls.push({url,init});const body=init.body?JSON.parse(init.body):null;
  if(url.endsWith('/auth/v1/user'))return options.invalidAuth?reply({},401):reply({id:uid});
  if(url.includes('/profiles?'))return reply([{id:uid,role:options.role||'administrador',active:options.active!==false}]);
  if(url.includes('/app_modules?'))return reply(options.disabled?[{enabled:false}]:[]);
  if(url.includes('/gama_ai_settings?')){if(init.method==='POST'){settings=[body];saved.push(body);return reply(null,201);}return reply(settings);}
  if(url.includes('/rpc/gama_ai_claim'))return options.rate?reply({message:'RATE_LIMIT'},400):reply(true);
  if(url.includes('/rpc/gama_ai_catalog'))return reply([{table:'products',columns:['id','stock','name'],pk:['id'],module:'products'}]);
  if(url.includes('/rpc/gama_ai_overview'))return reply(overview);
  if(url.includes('/rpc/gama_ai_query'))return reply({table:'products',matched_rows:250,rows:[{stock:35,name:'<img src=x onerror=alert(1)>'}],truncated:true});
  if(url.includes('/gama_ai_history?')){if(init.method==='PATCH'){saved.push(body);return reply([]);}return reply([]);}
  if(url.includes('api.openai.com/v1/models/'))return reply({id:'gpt-4.1-mini'});
  if(url.includes('api.openai.com/v1/responses')){
   openaiCount++;if(options.providerError)return reply({secret:'must not leak'},options.providerError);
   if(options.tool&&openaiCount===1)return reply({status:'completed',output:[{type:'function_call',name:options.tool,call_id:'call1',arguments:JSON.stringify({query:{table:'products',operation:'rows',limit:1}})}]});
   const report=diagnostic(overview,'fr').report;if(options.badCitation)report.findings[0].evidence_ids=['FAKE'];
   return reply({status:'completed',output:[{type:'message',role:'assistant',content:[{type:'output_text',text:JSON.stringify(report)}]}]});
  }
  throw Error('Unexpected request '+url);
 }});
 const request=(body={},token='user-token')=>handler(new Request('https://test.supabase.co/functions/v1/gama-assistant-ia',{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify({action:'ask',question:'Analyse',language:'fr',request_id:rid,...body})}));
 return {request,calls,saved,getSettings:()=>settings};
}
test('missing/invalid sessions and non-admin/disabled profiles cannot read or call provider',async()=>{
 for(const opts of [{token:null},{invalidAuth:true},{role:'comercial'},{role:'almacenero'},{role:'cliente'},{active:false},{disabled:true}]){
  const f=fixture({...opts,key:true}),r=await f.request({},Object.hasOwn(opts,'token')?opts.token:'user-token');
  assert.ok([401,403].includes(r.status));assert.ok(!f.calls.some(c=>/openai|rpc\/gama_ai_overview/.test(c.url)));
 }
});
test('no key produces explicit setup requirement and never a fake AI answer',async()=>{
 const f=fixture(),r=await f.request();assert.equal(r.status,503);assert.equal((await r.json()).error,'AI_NOT_CONFIGURED');
 const status=await (await f.request({action:'status'})).json();assert.deepEqual(status,{configured:false,model:null});
});
test('diagnostic uses current server data, confirmed totals, proposed plans and private history',async()=>{
 const f=fixture(),r=await f.request({action:'diagnostic',data:{stock:9999}});assert.equal(r.status,200);
 const a=await r.json();assert.equal(a.engine,'calculated');assert.equal(a.coverage[0].rows,250);assert.ok(!JSON.stringify(a).includes('9999'));assert.ok(a.report.actions.length>=3);
 assert.equal(f.saved.at(-1).status,'complete');assert.ok(f.calls.filter(c=>/rpc\/gama_ai_(query|overview|catalog)/.test(c.url)).every(c=>c.init.headers.Authorization==='Bearer user-token'));
});
test('provider output is structured, citations checked, store disabled, query limits disclosed',async()=>{
 const f=fixture({key:true,tool:'query_data'}),r=await f.request();assert.equal(r.status,200);const a=await r.json();assert.equal(a.engine,'openai');assert.equal(a.evidence.length,2);assert.equal(a.evidence[1].data.truncated,true);
 const modelCalls=f.calls.filter(c=>c.url.includes('/responses'));assert.equal(modelCalls.length,2);assert.ok(modelCalls.every(c=>JSON.parse(c.init.body).store===false));assert.ok(!JSON.stringify(a).includes('sk-test'));
 const bad=fixture({key:true,badCitation:true});assert.equal((await (await bad.request()).json()).error,'AI_INVALID_RESPONSE');
});
test('model cannot call business write actions or arbitrary external destinations',async()=>{
 const f=fixture({key:true,tool:'delete_products'});assert.equal((await f.request()).status,200);assert.ok(!f.calls.some(c=>c.url.includes('rpc/delete')));
 assert.ok(f.calls.every(c=>c.url.startsWith('https://test.supabase.co/')||c.url.startsWith('https://api.openai.com/v1/')));
});
test('key is encrypted at rest, never returned, and can be reused for questions',async()=>{
 const f=fixture(),key='sk-test-only-abcdefghijklmnopqrstuvwxyz';const r=await f.request({action:'configure',api_key:key,model:'gpt-4.1-mini'});
 assert.equal(r.status,200);assert.ok(!JSON.stringify(await r.json()).includes(key));const stored=f.getSettings()[0];assert.ok(stored.encrypted_key&&!stored.encrypted_key.includes(key));assert.equal((await f.request()).status,200);
});
test('rate limits, provider failures, invalid dates and invalid actions fail without secret output',async()=>{
 for(const [opts,code] of [[{key:true,rate:true},'RATE_LIMIT'],[{key:true,providerError:429},'AI_QUOTA']]){const f=fixture(opts),r=await f.request();assert.equal((await r.json()).error,code);}
 const f=fixture({key:true});assert.equal((await f.request({from:'2026-12-01',to:'2026-01-01'})).status,400);assert.equal((await f.request({action:'delete'})).status,400);
});
