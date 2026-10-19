const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');
test('offline proofs are encrypted, bound to owner/store/id, locked on logout and recoverable by the same authenticated owner',async()=>{
 let actor='a',calls=0;
 const c={TextEncoder,TextDecoder,Blob,Uint8Array,crypto:webcrypto,navigator:{onLine:true},ArcData:{rpc:async()=>{calls++;return {actor_id:actor,key:(actor==='a'?'ab':'cd').repeat(32)}}}};c.window=c;
 vm.runInNewContext(fs.readFileSync('src/features/transport/offline-vault.js','utf8'),c);const v=c.CocoOfflineVault;
 const original={actor:'a',request_key:'proof-1',payload:{signature:'SENSITIVE SIGNATURE',photo:'PRIVATE PHOTO'},document:new Blob(['PDF example'],{type:'application/pdf'})};
 const encrypted=await v.seal(original,'proofs');assert(!JSON.stringify(encrypted).includes('PRIVATE'));assert(!JSON.stringify(encrypted).includes('SENSITIVE'));
 const restored=await v.unseal(encrypted,'proofs','a');assert.equal(restored.payload.photo,original.payload.photo);assert.equal(await restored.document.text(),'PDF example');assert.equal(calls,1);
 await assert.rejects(v.unseal(encrypted,'proofs','b'),/AUTH_CHANGED/);
 await assert.rejects(v.unseal({...encrypted,request_key:'other'},'proofs','a'));
 c.navigator.onLine=false;assert.equal((await v.unseal(encrypted,'proofs','a')).payload.signature,original.payload.signature);
 v.lock();await assert.rejects(v.unseal(encrypted,'proofs','a'),/OFFLINE_UNLOCK_REQUIRED/);
 c.navigator.onLine=true;actor='b';await assert.rejects(v.unseal(encrypted,'proofs','a'),/AUTH_CHANGED/);
 actor='a';assert.equal((await v.unseal(encrypted,'proofs','a')).payload.photo,original.payload.photo);
});
