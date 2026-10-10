import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHandler,extractionInput,extractionSchema,validateExtraction} from '../supabase/functions/coco-supplier-ocr/handler.mjs';
const file={filename:'invoice.pdf',mime_type:'application/pdf',content_base64:btoa('%PDF-1.4\ninvoice fixture')};
const extracted={...Object.fromEntries(Object.keys(extractionSchema.properties).map(k=>[k,null])),lines:[],warnings:[]};
function harness({denied=false,existing=false,invalid=false}={}){
 const calls=[];
 const handler=createHandler({env:n=>({SUPABASE_URL:'https://db.invalid',SUPABASE_ANON_KEY:'public',SUPABASE_SERVICE_ROLE_KEY:'server-only',OPENAI_API_KEY:'fixture-api-key'}[n]),fetch:async(url,opts={})=>{
  const body=opts.body?JSON.parse(opts.body):null;calls.push({url,opts,body});
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
