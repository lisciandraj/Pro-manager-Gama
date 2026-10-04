const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm'),ts=require('typescript');
const {webcrypto,createHmac}=require('node:crypto');
const source=fs.readFileSync('supabase/functions/gama-sri/index.ts','utf8').replace(/^import.*\n/,'');
const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
const ID='00000000-0000-4000-8000-000000000001';
const KEY='2709202601179001234500110010010000000011234567813';
function harness(options={}){
 let handler;
 const issue={id:ID,source_invoice_id:ID,status:'draft',environment:'pruebas',issuer_ruc:'1790012345001',establishment:'001',emission_point:'001',sequential:'000000001',numeric_code:'12345678',snapshot:{issue_date:'2026-09-27'},...options.issue};
 const calls=[],updates=[],files=new Map();
 const env={SUPABASE_URL:'https://db.invalid',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service',SRI_WORKER_URL:'https://worker.invalid',SRI_WORKER_SECRET:'fixture-secret',SRI_PROVIDER:'openapi',SRI_EMISSION_ENABLED:'true',...options.env};
 const access={validate:true,export:true,...options.access};
 function db(isAdmin){
  return {auth:{getUser:async()=>options.noAuth?{error:{message:'invalid'}}:{data:{user:{id:ID}}}},
   rpc:async()=>({data:options.noAccess?null:access}),
   from(table){let change=null,filters=[],many=false;const q={
    select(){return q},in(k,v){filters.push([k,v]);return q},order(){return q},limit(){many=true;return q},eq(k,v){filters.push([k,v]);return q},is(k,v){filters.push([k,v]);return q},update(patch){change=patch;return q},
    async resolve(){
     if(table==='profiles')return {data:{role:options.role||'administrador',active:options.active!==false}};
     if(table==='external_invoices'){if(change)updates.push(change);return {data:{id:ID}}}
     if(!isAdmin&&options.invisible)return{data:null};
     if(!filters.every(([k,v])=>(Array.isArray(v)?v.includes(issue[k]):(issue[k]??null)===v)))return{data:null};
     if(change)Object.assign(issue,change);
     return{data:many?[structuredClone(issue)]:structuredClone(issue)};
    },single(){return q.resolve()},maybeSingle(){return q.resolve()},then(ok,fail){return q.resolve().then(ok,fail)}
   };return q},
   storage:{from:bucket=>({
    upload:async(path,bytes)=>{if(files.has(path))return{error:{message:'already exists'}};files.set(path,new Blob([bytes]));return{}},
    download:async path=>files.has(path)?{data:files.get(path)}:{error:{message:'missing'}},
    createSignedUrl:async(path,seconds)=>({data:{signedUrl:'https://private.invalid/'+path+'?ttl='+seconds}})
   })}
  }
 }
 vm.runInNewContext(code,{
  Deno:{env:{get:k=>env[k]},serve:fn=>{handler=fn}},
  createClient:(url,key)=>db(key==='service'),
  fetch:async(url,init)=>{const body=JSON.parse(init.body);calls.push(body.action);
   assert.equal(init.redirect,'error');
   assert.equal(init.headers['x-sri-signature'],createHmac('sha256',env.SRI_WORKER_SECRET).update(init.body).digest('hex'));
   if(body.action==='status'){
    if(options.statusFailure)throw Error('unreachable');
    return Response.json(options.statusResponse===undefined?{configured:true,provider:'openapi',environment:'pruebas'}:options.statusResponse);
   }
   if(body.action==='openapi_preflight')return Response.json({ready:true});
   if(options.worker)return options.worker(body);
   return Response.json({status:'processing',access_key:KEY,provider_status:'RECIBIDA'});
  },Response,Request,Blob,URL,TextEncoder,Uint8Array,AbortController,crypto:webcrypto,atob,btoa,setTimeout,clearTimeout,console
 });
 return {issue,calls,updates,files,request:async body=>{const r=await handler(new Request('https://edge.invalid',{method:'POST',headers:{Authorization:options.serviceAuth?'Bearer service':'Bearer user','Content-Type':'application/json'},body:JSON.stringify(body)}));return {status:r.status,...await r.json()}}};
}
test('Open API emit claims once, persists provider, never authorizes from POST',async()=>{
 const h=harness();const result=await h.request({action:'submit',id:ID});
 assert.equal(result.status, 'processing');assert.equal(h.issue.receipt.provider,'openapi');
 assert.equal(h.issue.access_key,KEY);assert.equal(h.updates.length,0);
 await h.request({action:'submit',id:ID});assert.equal(h.calls.filter(x=>x==='openapi_submit').length,1);
});
test('uncertain POST remains locked even with no key; retry refused, refresh allowed',async()=>{
 const h=harness({worker:async({action})=>{if(action==='openapi_submit')throw Error('network timeout');return Response.json({status:'processing',review_required:true})}});
 const result=await h.request({action:'submit',id:ID});assert.equal(result.review_required,true);
 assert.equal(h.issue.status,'processing');assert.equal(h.issue.receipt.provider,'openapi');
 const retry=await h.request({action:'retry',id:ID});assert.equal(retry.error,'SRI_RETRY_REQUIRES_REVIEW');
 await h.request({action:'refresh',id:ID});assert.ok(h.calls.includes('openapi_refresh'));
 assert.equal(h.calls.filter(x=>x==='openapi_submit').length,1);
});
test('concurrent emission requests have exactly one claim',async()=>{
 const h=harness();await Promise.all([h.request({action:'submit',id:ID}),h.request({action:'submit',id:ID})]);
 assert.equal(h.calls.filter(x=>x==='openapi_submit').length,1);
});
test('kill switch blocks new emission but preserves read-only reconciliation',async()=>{
 const h=harness({env:{SRI_EMISSION_ENABLED:'false'},issue:{status:'processing',receipt:{provider:'openapi'}}});
 assert.equal((await h.request({action:'submit',id:ID})).error,'SRI_CERTIFICATION_PENDING');
 await h.request({action:'refresh',id:ID});assert.deepEqual(h.calls,['openapi_refresh']);
});
test('admin, active profile, action permission and RLS are all required',async()=>{
 for(const options of [{noAuth:true},{role:'comercial'},{active:false},{noAccess:true},{access:{validate:false}},{invisible:true}]){
  const h=harness(options),r=await h.request({action:'submit',id:ID});assert.ok(r.error);assert.equal(h.calls.length,0);
 }
});
test('wrong key is never persisted or used to link a commercial invoice',async()=>{
 const h=harness({worker:async()=>Response.json({status:'processing',access_key:'9'.repeat(49)})});
 const result=await h.request({action:'submit',id:ID});assert.equal(result.review_required,true);
 assert.equal(h.issue.access_key,undefined);assert.equal(h.updates.length,0);
});
test('authorization archives privately and links only the existing internal invoice',async()=>{
 const h=harness({issue:{status:'processing',receipt:{provider:'openapi'},access_key:KEY},worker:async()=>Response.json({status:'authorized',access_key:KEY,authorization:KEY,authorized_at:'2026-09-27T15:00:00-05:00',signed_xml:btoa('<factura/>'),authorized_xml:btoa('<autorizacion/>'),ride_pdf:btoa('%PDF-fixture'),provider_status:'AUTORIZADO'})});
 await h.request({action:'refresh',id:ID});assert.equal(h.issue.status,'authorized');assert.equal(h.files.size,3);
 assert.equal(h.updates.length,1);assert.equal(h.updates[0].external_number,'001-001-000000001');
 assert.equal(h.updates[0].access_key,KEY);assert.equal(h.updates[0].total,undefined);
 const result=await h.request({action:'download',id:ID,kind:'xml'});assert.match(result.url,/ttl=60$/);
});
test('unverified documents cannot be downloaded or emailed; export permission is enforced',async()=>{
 let h=harness({issue:{status:'processing'}});assert.equal((await h.request({action:'download',id:ID,kind:'xml'})).error,'SRI_NOT_AUTHORIZED');
 assert.equal((await h.request({action:'notify',id:ID})).error,'SRI_NOT_AUTHORIZED');
 h=harness({access:{export:false},issue:{status:'authorized'}});assert.equal((await h.request({action:'download',id:ID,kind:'xml'})).error,'ROLE_NOT_ALLOWED');
});
test('status reveals capabilities without credentials; invalid JSON values are rejected',async()=>{
 const h=harness();const r=await h.request({action:'status'});assert.equal(r.provider,'openapi');assert.equal(r.ready,true);
 assert.equal(JSON.stringify(r).includes('fixture-secret'),false);assert.equal((await h.request(null)).error,'INVALID_REQUEST');
});
test('technical status distinguishes incomplete, mismatched and unreachable workers',async()=>{
 for(const [options,diagnostic] of [
  [{env:{SRI_WORKER_URL:''}},'SRI_WORKER_NOT_CONFIGURED'],
  [{statusFailure:true},'SRI_WORKER_UNREACHABLE'],
  [{statusResponse:null},'SRI_WORKER_UNREACHABLE'],
  [{statusResponse:{provider:'openapi',configured:false}},'SRI_WORKER_CONFIGURATION_INCOMPLETE'],
  [{statusResponse:{provider:'private_worker',configured:true}},'SRI_WORKER_PROVIDER_MISMATCH'],
  [{env:{SRI_EMISSION_ENABLED:'false'}},'SRI_EMISSION_DISABLED'],
  [{access:{validate:false}},'SRI_VALIDATION_NOT_ALLOWED']
 ]){
  const h=harness(options),r=await h.request({action:'status'});
  assert.equal(r.ready,false);assert.equal(r.diagnostic,diagnostic);
  assert.equal(JSON.stringify(r).includes('fixture-secret'),false);
 }
 const r=await harness().request({action:'status'});
 assert.equal(r.worker_ready,true);assert.equal(r.diagnostic,'SRI_READY_FOR_SUPERVISED_TESTS');
});
test('a rejected Open API document can be consulted but never submitted or reset',async()=>{
 for(const withKey of [false,true]){
  const h=harness({issue:{status:'rejected',receipt:{provider:'openapi'},...(withKey?{access_key:KEY}:{})}});
  assert.equal((await h.request({action:'submit',id:ID})).error,'SRI_ALREADY_SUBMITTED');
  assert.equal((await h.request({action:'retry',id:ID})).error,'SRI_RETRY_REQUIRES_REVIEW');
  const r=await h.request({action:'refresh',id:ID});assert.equal(r.status,'rejected');
  assert.deepEqual(h.calls,['openapi_refresh']);assert.equal(h.updates.length,0);
 }
});
test('historical rejection lookup preserves rejection when authorization is still pending',async()=>{
 const h=harness({env:{SRI_PROVIDER:'private_worker'},issue:{status:'rejected',access_key:KEY},worker:async()=>Response.json({status:'processing'})});
 const r=await h.request({action:'refresh',id:ID});assert.equal(r.status,'rejected');
 assert.deepEqual(h.calls,['authorize']);assert.equal(h.updates.length,0);
});

function documentKey(type){const body=KEY.slice(0,8)+type+KEY.slice(10,48);const check=11-[...body].reverse().reduce((s,v,i)=>s+Number(v)*(i%6+2),0)%11;return body+(check===11?0:check===10?1:check)}
test('new document types claim once, bind the key type and never link an unrelated sales invoice',async()=>{
 for(const type of ['04','06','07']){
 const key=documentKey(type),h=harness({issue:{document_type:type},worker:async()=>Response.json({status:'processing',access_key:key})});
 await h.request({action:'submit',id:ID,document_type:type});await h.request({action:'submit',id:ID,document_type:type});
 assert.equal(h.issue.access_key,key);assert.equal(h.calls.filter(a=>a==='openapi_submit').length,1);assert.equal(h.updates.length,0);
 const wrong=harness({issue:{document_type:type},worker:async()=>Response.json({status:'processing',access_key:KEY})});
 assert.equal((await wrong.request({action:'submit',id:ID,document_type:type})).review_required,true);assert.equal(wrong.issue.access_key,undefined);
 }
});
test('assigned driver can download his authorized guide through document access but cannot emit',async()=>{
 const h=harness({role:'almacenero',issue:{document_type:'06',status:'authorized',ride_path:'private-guide.pdf'},access:{validate:false,export:true}});
 assert.match((await h.request({action:'download',id:ID,document_type:'06',kind:'ride'})).url,/ttl=60$/);
 assert.equal((await h.request({action:'submit',id:ID,document_type:'06'})).error,'ROLE_NOT_ALLOWED');assert.equal(h.calls.length,0);
});
test('service schedule only consults pending claims and cannot emit, notify or download',async()=>{
 const h=harness({serviceAuth:true,issue:{status:'processing',receipt:{provider:'openapi'},updated_at:'2026-01-01'}});
 const r=await h.request({action:'refresh_pending'});assert.equal(r.consulted,1);assert.deepEqual(h.calls,['openapi_refresh']);
 for(const action of ['submit','retry','notify','download','refresh','status'])assert.equal((await h.request({action,id:ID,kind:'ride'})).error,'ROLE_NOT_ALLOWED');
 assert.deepEqual(h.calls,['openapi_refresh']);
});
