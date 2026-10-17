import {test} from 'node:test';import assert from 'node:assert/strict';
import {createHandler} from '../supabase/functions/coco-order-mail/handler.mjs';
test('retired mailbox endpoint never contacts a provider or reads credentials',async()=>{
 let calls=0;const handler=createHandler({env(){calls++;throw Error('No secrets')},fetch(){calls++;throw Error('No network')}});
 for(const path of ['','/callback?code=private&state=old']){const r=await handler(new Request('https://example.invalid'+path));assert.equal(r.status,410);assert.equal((await r.json()).error,'MAIL_CONNECTOR_REMOVED')}
 assert.equal(calls,0);const preflight=await handler(new Request('https://example.invalid',{method:'OPTIONS',headers:{Origin:'https://lisciandraj.github.io'}}));assert.equal(preflight.status,204);assert.equal(preflight.headers.get('Access-Control-Allow-Origin'),'https://lisciandraj.github.io');
 const other=await handler(new Request('https://example.invalid',{headers:{Origin:'https://other.invalid'}}));assert.equal(other.headers.get('Access-Control-Allow-Origin'),null);
});
