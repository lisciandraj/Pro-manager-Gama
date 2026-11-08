const {test}=require('node:test'),assert=require('node:assert/strict'),{createHash}=require('node:crypto');
const token='ab'.repeat(32),id='11111111-1111-4111-8111-111111111111',owner='22222222-2222-4222-8222-222222222222',pdf=Buffer.from('%PDF-1.4 frozen quote'),sha=createHash('sha256').update(pdf).digest('hex');
const cfg={SUPABASE_URL:'https://fixture.supabase.co',SUPABASE_ANON_KEY:'public-key',SUPABASE_SERVICE_ROLE_KEY:'private-machine-key',COCO_CHECKOUT_APP_ORIGIN:'https://coco.example'};
const req=(body={action:'document',token},headers={})=>new Request('https://fixture.supabase.co/functions/v1/coco-checkout',{method:'POST',headers:{origin:'https://coco.example','content-type':'application/json',...headers},body:JSON.stringify(body)});
test('quote PDF capability checks the caller before touching private storage',async()=>{
 const {createHandler}=await import('../supabase/functions/coco-checkout/handler.mjs');const calls=[];
 const handler=createHandler({env:k=>cfg[k],fetch:async(url,options)=>{calls.push({url,options});return new Response(JSON.stringify({message:'DEVELOPMENT_ADMIN_REQUIRED'}),{status:403})}});
 assert.equal((await handler(req())).status,403);assert.equal(calls.length,1);assert.equal(calls[0].options.headers.Authorization,'Bearer public-key');assert.ok(!JSON.stringify(calls).includes(cfg.SUPABASE_SERVICE_ROLE_KEY));
});
test('authorized preview uses the actual caller token and streams only the frozen PDF',async()=>{
 const {createHandler}=await import('../supabase/functions/coco-checkout/handler.mjs');const calls=[];
 const handler=createHandler({env:k=>cfg[k],fetch:async(url,options)=>{calls.push({url,options});return calls.length===1?Response.json({id,pdf_sha256:sha}):calls.length===2?Response.json({path:owner+'/'+id+'.pdf',sha256:sha}):new Response(pdf)}});
 const result=await handler(req(undefined,{authorization:'Bearer verified-admin-token'}));assert.equal(result.status,200);assert.equal(result.headers.get('content-type'),'application/pdf');assert.equal(result.headers.get('cache-control'),'no-store');assert.deepEqual(Buffer.from(await result.arrayBuffer()),pdf);
 assert.equal(calls[0].options.headers.Authorization,'Bearer verified-admin-token');assert.equal(calls[1].options.headers.Authorization,'Bearer '+cfg.SUPABASE_SERVICE_ROLE_KEY);assert.ok(!calls.some(x=>x.url.includes(token)));
});
test('altered documents, untrusted storage paths and other origins cannot be served',async()=>{
 const {createHandler}=await import('../supabase/functions/coco-checkout/handler.mjs');
 for(const path of [owner+'/'+id+'.pdf','../../unrelated']){
  let n=0;const h=createHandler({env:k=>cfg[k],fetch:async()=>++n===1?Response.json({id,pdf_sha256:sha}):n===2?Response.json({path,sha256:sha}):new Response('%PDF-1.4 substituted')});assert.equal((await h(req())).status,409);assert.equal(n,path.startsWith('..')?2:3);
 }
 let calls=0;const h=createHandler({env:k=>cfg[k],fetch:async()=>{calls++;throw Error('unexpected')}});assert.equal((await h(req(undefined,{origin:'https://unrelated.example'}))).status,403);assert.equal(calls,0);assert.equal((await h(req({action:'document',token:'bad'}))).status,400);assert.equal(calls,0);
});
