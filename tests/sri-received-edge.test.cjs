const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),ts=require('typescript');
const {webcrypto,createHmac}=require('node:crypto');
const code=ts.transpileModule(fs.readFileSync('supabase/functions/gama-sri-received/index.ts','utf8').replace(/^import.*\n/,''),{compilerOptions:{target:ts.ScriptTarget.ES2022}}).outputText;
const ID='00000000-0000-4000-8000-000000000001',KEY='7'.repeat(49),RUC='1719304188001';
function harness(options={}){
 let handler;const calls=[],written=[],files=new Map(),env={SUPABASE_URL:'https://db.invalid',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service',SRI_WORKER_URL:'https://worker.invalid',SRI_WORKER_SECRET:'fixture',...options.env};
 const invoice={id:ID,number:'DOC-00000017',customer_identification:RUC,issuer_ruc:'1790012345001',subtotal:100,tax:15};
 const proof={invoice_id:ID,access_key:KEY,issuer_ruc:RUC,number:'001-001-000000001',issued_on:'2026-10-02',amount:13,lines:[{tax_kind:'income',code:'312',base:100,rate:10,amount:10},{tax_kind:'vat',code:'1',base:15,rate:20,amount:3}],authorized_at:'2026-10-02T12:00:00-05:00',authorized_xml:'<autorizacion/>',...options.proof};
 const db=admin=>({auth:{getUser:async()=>options.noAuth?{error:{}}:{data:{user:{id:ID}}}},rpc:async(name)=>{calls.push(name);if(name==='gama_sri_access')return {data:{validate:!options.noAccess}};return options.noMatch?{error:{message:'SRI_RECEIVED_INVOICE_NOT_FOUND'}}:{data:invoice}},
  from(){let row;const q={upsert:async data=>{assert.equal(admin,true);written.push(data);return{}},select(){return q},eq(){return q},single:async()=>({data:{id:ID,amount:13,number:proof.number,xml_sha256:written.at(-1)?.xml_sha256,withholding_id:null}})};return q},
  storage:{from:()=>({upload:async(path,raw,opts)=>{assert.equal(admin,true);assert.equal(opts.upsert,false);files.set(path,raw);return{}}})}});
 vm.runInNewContext(code,{Deno:{env:{get:k=>env[k]},serve:fn=>{handler=fn}},createClient:(url,key)=>db(key==='service'),
  fetch:async(url,init)=>{const data=JSON.parse(init.body);calls.push(data.action);assert.equal(init.redirect,'error');assert.equal(init.headers['x-sri-signature'],createHmac('sha256',env.SRI_WORKER_SECRET).update(init.body).digest('hex'));
   if(options.workerError)return Response.json({detail:'SRI_RECEIVED_NOT_AUTHORIZED'},{status:422});
   return Response.json(data.action==='received_inspect'?{issuer_ruc:RUC,access_key:KEY,sources:['001001000000001']}:{rows:[proof]})},Response,Request,URL,TextEncoder,Uint8Array,AbortSignal,crypto:webcrypto,console});
 return {calls,written,files,request:async input=>{const r=await handler(new Request('https://edge.invalid',{method:'POST',headers:{Authorization:'Bearer fixture','Content-Type':'application/json'},body:JSON.stringify(input??{xml_base64:btoa('<fake-browser-xml/>'),amount:999})}));return{status:r.status,...await r.json()}}};
}
test('received XML uses authorized data and server-matched invoice, archives privately and never writes payment',async()=>{
 const h=harness(),r=await h.request();assert.equal(r.rows[0].invoice_number,'DOC-00000017');assert.equal(h.written[0].amount,13);assert.equal(h.written[0].invoice_id,ID);assert.equal(h.files.size,1);assert.match(h.written[0].xml_path,/^received\/7{49}\/[a-f0-9]{64}\.xml$/);assert.deepEqual(h.calls,['gama_sri_access','received_inspect','gama_ec_received_match','verify_received_batch']);
});
test('authorization, action rights, authoritative match and SRI authorization fail before archive',async()=>{
 for(const options of [{noAuth:true},{noAccess:true},{noMatch:true},{workerError:true},{env:{SRI_WORKER_URL:'http://worker.invalid'}},{proof:{issuer_ruc:'1799999999001'}},{proof:{invoice_id:'unrelated'}}]){const h=harness(options),r=await h.request();assert.ok(r.error);assert.equal(h.written.length,0);assert.equal(h.files.size,0)}
});
test('large or missing XML is rejected without contacting the worker',async()=>{
 for(const input of [{xml_base64:'a'.repeat(1400001)},{amount:1}]){const h=harness(),r=await h.request(input);assert.equal(r.error,'INVALID_REQUEST');assert.equal(h.calls.includes('received_inspect'),false)}
});
