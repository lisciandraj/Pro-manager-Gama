import {test} from 'node:test';import assert from 'node:assert/strict';import {createHandler} from '../supabase/functions/tms-proof-files/handler.mjs';
const id='12345678-1234-1234-1234-123456789abc';
const env=k=>({SUPABASE_URL:'https://database.example',SUPABASE_ANON_KEY:'public',SUPABASE_SERVICE_ROLE_KEY:'private'}[k]);
test('proof files refuse unauthenticated callers and wrong origins before elevated storage access',async()=>{
 let calls=0;const handler=createHandler({env,fetch:async()=>{calls++;return new Response('{}')}});
 assert.equal((await handler(new Request('https://edge.example',{method:'POST',body:'{}'}))).status,401);
 assert.equal((await handler(new Request('https://edge.example',{method:'POST',headers:{origin:'https://evil.example',Authorization:'Bearer test'},body:'{}'}))).status,403);assert.equal(calls,0);
});
test('caller-bound permission failure never reaches storage',async()=>{
 const calls=[];const handler=createHandler({env,fetch:async(url,options)=>{calls.push({url,options});return new Response('{}',{status:403})}});
 const response=await handler(new Request('https://edge.example',{method:'POST',headers:{Authorization:'Bearer actor'},body:JSON.stringify({proof_id:id})}));assert.equal(response.status,403);assert.equal(calls.length,1);assert.equal(calls[0].options.headers.Authorization,'Bearer actor');
});
test('stored bytes must match the accepted proof before its immutable reference is committed',async()=>{
 for(const corrupt of [false,true]){
 const calls=[],bytes=Uint8Array.of(1,2,3);const handler=createHandler({env,fetch:async(url,options)=>{calls.push(url);
 if(url.endsWith('/gama_tms_proof_file'))return Response.json({proof_id:id,content_hash:'abc',data_url:'data:image/png;base64,AQID'});
 if(url.endsWith('/gama_tms_proof_file_commit'))return Response.json({stored:true});
 if(options.method==='POST')return new Response('{}');return new Response(corrupt?Uint8Array.of(4,5,6):bytes);
 }});
 const response=await handler(new Request('https://edge.example',{method:'POST',headers:{Authorization:'Bearer actor'},body:JSON.stringify({proof_id:id})}));assert.equal(response.status,corrupt?409:200);assert.equal(calls.some(x=>x.endsWith('_commit')),!corrupt);
 }
});
