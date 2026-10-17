import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mime,unb64,b64url,validateAttachments,createProvider,gmailMessage} from '../supabase/functions/coco-order-mail/provider.mjs';
import {createHandler} from '../supabase/functions/coco-order-mail/handler.mjs';
const entry={id:'87c4ad05-0e44-4ad3-b220-1c5ebee66805',from_email:'me@example.invalid',to_email:'client@example.invalid',subject:'Confirmation commande été',body:'Bonjour, confirmé.'};
test('MIME keeps UTF-8, references and attachments and refuses header injection',()=>{
 const attachment=validateAttachments([{name:'devis.pdf',type:'application/pdf',content:btoa('test')}]);const m=mime({...entry,reply:{internet_id:'<first@example.invalid>'}},attachment);
 assert.match(m.raw,/In-Reply-To: <first@example.invalid>/);assert.match(m.raw,/Content-Type: multipart\/mixed/);assert.match(m.raw,/filename="devis.pdf"/);assert(m.raw.includes(btoa('test')));
 assert.throws(()=>mime({...entry,to_email:'client@example.invalid\r\nBcc: bad@example.invalid'},[]),/INVALID_MESSAGE/);
 assert.throws(()=>validateAttachments(new Array(6).fill({})),/INVALID_ATTACHMENTS/);
 assert.throws(()=>validateAttachments([{name:'large.pdf',type:'application/pdf',content:btoa('x'.repeat(3000000))}],'microsoft'),/OUTLOOK_ATTACHMENT_TOO_LARGE/);
});
test('Gmail uses the authorized sender, returns real thread ID, preserves reply association',async()=>{
 let call;const p=createProvider(async(url,options)=>{call={url,options};return Response.json({id:'gmail-id',threadId:'thread-id'})});
 const sent=await p.send({provider:'google',access_token:'test'}, {...entry,reply:{thread_id:'existing',internet_id:'<in@example.invalid>'}},[],async()=>{});
 assert.equal(sent.status,'sent');assert.equal(sent.thread_id,'thread-id');const body=JSON.parse(call.options.body);assert.equal(body.threadId,'existing');assert.match(new TextDecoder().decode(unb64(body.raw)),/From: me@example.invalid/);
});
test('Microsoft saves an immutable draft reference before sending and reports accepted',async()=>{
 const events=[],p=createProvider(async(url,options)=>{events.push(url.endsWith('/send')?'send':url.endsWith('/attachments')?'attachment':'draft');if(url.endsWith('/messages'))assert.equal(JSON.parse(options.body).attachments,undefined);assert.match(options.headers.Prefer,/ImmutableId/);return url.endsWith('/send')?new Response(null,{status:202}):Response.json({id:'draft-id',conversationId:'conversation-id',internetMessageId:'<m@example.invalid>'})});
 const sent=await p.send({provider:'microsoft',access_token:'test'},entry,validateAttachments([{name:'a.pdf',type:'application/pdf',content:btoa('file')}]),async()=>{events.push('save')});assert.deepEqual(events,['draft','save','attachment','send']);assert.equal(sent.status,'accepted');
});
test('provider network ambiguity is never represented as a confirmed send',async()=>{
 const p=createProvider(async()=>{throw Error('timeout')});await assert.rejects(p.send({provider:'google',access_token:'test'},entry,[],async()=>{}),/PROVIDER_UNCERTAIN/);
});
test('ambiguous Gmail sends are reconciled by their exact Message-ID without sending again',async()=>{
 const internet='<'+entry.id+'@coco-erp.invalid>',calls=[];
 const p=createProvider(async(url,o)=>{calls.push({url,o});return url.includes('/messages?')?Response.json({messages:[{id:'sent-id'}]}):Response.json({id:'sent-id',threadId:'thread-id',labelIds:['SENT'],payload:{headers:[{name:'Message-ID',value:internet}]}})});
 const r=await p.recover({provider:'google',access_token:'test'},{internet_id:internet});assert.equal(r.status,'sent');assert.equal(r.thread_id,'thread-id');assert.equal(calls.length,2);assert(calls.every(c=>c.o.method==='GET'));
 assert.equal(await p.recover({provider:'google',access_token:'test'},{internet_id:'https://outside.invalid'}),null);assert.equal(calls.length,2);
});
test('untrusted mail HTML is converted to inert text and attachment metadata',()=>{
 const m=gmailMessage({id:'1',threadId:'2',internalDate:'1792184400000',payload:{headers:[{name:'From',value:'Client <client@example.invalid>'}],parts:[{mimeType:'text/html',body:{data:btoa('<script>bad()</script><p>Hello</p><img src="https://track.invalid">')}},{filename:'invoice.pdf',body:{size:123}}]}});
 assert.equal(m.from_email,'client@example.invalid');assert.equal(m.body.trim(),'Hello');assert.deepEqual(m.attachments,[{name:'invoice.pdf',size:123}]);
});
const uid='8752a6ef-1c90-4c61-9870-bd87ee450761';
function fixture({can=true,duplicate=false,sendFail=false}={}){
 const calls=[],env=k=>({SUPABASE_URL:'https://db.example.invalid',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service',COCO_GOOGLE_CLIENT_ID:'client',COCO_GOOGLE_CLIENT_SECRET:'secret',COCO_MAIL_ENCRYPTION_KEY:btoa('x'.repeat(32))}[k]);
 const context={actor_id:uid,can_mail:can,account_email:entry.from_email,mailbox:null};
 const handler=createHandler({env,fetch:async(url,o={})=>{calls.push({url,body:o.body});if(url.endsWith('/auth/v1/user'))return Response.json({id:uid});if(url.endsWith('/coco_order_followup'))return Response.json(context);throw Error('Unexpected request')}});
 return {handler,calls,context};
}
test('Edge handler requires validated authentication and order edit rights before OAuth',async()=>{
 const f=fixture({can:false});let r=await f.handler(new Request('https://db.example.invalid/functions/v1/coco-order-mail',{method:'POST',body:'{}'}));assert.equal(r.status,401);assert.equal(f.calls.length,0);
 r=await f.handler(new Request('https://db.example.invalid/functions/v1/coco-order-mail',{method:'POST',headers:{Authorization:'Bearer test','Content-Type':'application/json'},body:JSON.stringify({action:'connect',kind:'sales',order_id:entry.id,provider:'google'})}));assert.equal(r.status,403);assert.equal(f.calls.length,2);
});
test('unconfigured providers are not advertised as connected',async()=>{
 const f=fixture();const r=await f.handler(new Request('https://db.example.invalid/functions/v1/coco-order-mail',{method:'POST',headers:{Authorization:'Bearer test','Content-Type':'application/json'},body:JSON.stringify({action:'status',kind:'sales',order_id:entry.id})})),d=await r.json();assert.equal(d.google,true);assert.equal(d.microsoft,false);assert.equal(d.mailbox,null);
});
test('the Edge send claim prevents duplicate messages after an ambiguous provider failure',async()=>{
 const raw=new TextEncoder().encode('x'.repeat(32)),key=await crypto.subtle.importKey('raw',raw,{name:'AES-GCM'},false,['encrypt']);
 const iv=crypto.getRandomValues(new Uint8Array(12)),cipher=await crypto.subtle.encrypt({name:'AES-GCM',iv},key,new TextEncoder().encode(JSON.stringify({access_token:'provider-test',refresh_token:'refresh-test',expires_at:Date.now()+3600000})));
 const credentials=b64url(iv)+'.'+b64url(new Uint8Array(cipher));let claimed=false,sends=0,status='sending';
 const env=k=>({SUPABASE_URL:'https://db.example.invalid',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service',COCO_GOOGLE_CLIENT_ID:'client',COCO_GOOGLE_CLIENT_SECRET:'secret',COCO_MAIL_ENCRYPTION_KEY:btoa('x'.repeat(32))}[k]);
 const handler=createHandler({env,fetch:async(url,o={})=>{
  if(url.endsWith('/auth/v1/user'))return Response.json({id:uid});
  if(url.endsWith('/coco_order_followup')){const b=JSON.parse(o.body);if(b.p_action==='context')return Response.json({actor_id:uid,can_mail:true,account_email:entry.from_email,mailbox:{email:entry.from_email,provider:'google'}});if(b.p_action==='mail_claim'){const first=!claimed;claimed=true;return Response.json({id:entry.id,claimed:first,status})}}
  if(url.endsWith('/coco_order_mail_service')){const b=JSON.parse(o.body);if(b.p_action==='account')return Response.json({provider:'google',email:entry.from_email,credentials});if(b.p_action==='message')return Response.json({...entry,reply:null});if(b.p_action==='message_status'){status=b.p_data.status||status;return Response.json({id:entry.id,status})}}
  if(url.endsWith('/messages/send')){sends++;throw Error('connection closed after request')}
  throw Error('Unexpected request '+url);
 }});
 const request=()=>new Request('https://db.example.invalid/functions/v1/coco-order-mail',{method:'POST',headers:{Authorization:'Bearer test','Content-Type':'application/json'},body:JSON.stringify({action:'send',kind:'sales',order_id:entry.id,request_key:entry.id,to:entry.to_email,subject:entry.subject,body:entry.body})});
 let r=await handler(request());assert.equal(r.status,503);assert.equal((await r.json()).error,'MAIL_SEND_UNCERTAIN');assert.equal(status,'uncertain');
 r=await handler(request());assert.equal((await r.json()).duplicate,true);assert.equal(sends,1);
});
