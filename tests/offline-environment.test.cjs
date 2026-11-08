const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{webcrypto}=require('node:crypto');

const environment=name=>({name,storageName:value=>name==='production'?'coco:production:'+value:value});

function vault(name){
 const c={TextEncoder,TextDecoder,Blob,Uint8Array,crypto:webcrypto,navigator:{onLine:true},CocoEnvironment:environment(name),ArcData:{rpc:async()=>({actor_id:'same-account',key:'ab'.repeat(32)})}};
 c.window=c;
 vm.runInNewContext(fs.readFileSync('src/features/transport/offline-vault.js','utf8'),c);
 return c.CocoOfflineVault;
}

test('production cannot decrypt copied development proofs even with the same account and key',async()=>{
 const development=vault('development'),production=vault('production');
 const value={actor:'same-account',request_key:'proof-1',payload:{photo:'DEVELOPMENT PHOTO'}};
 const original=await development.seal(value,'proofs');
 assert.equal((await development.unseal(original,'proofs','same-account')).payload.photo,'DEVELOPMENT PHOTO');
 await assert.rejects(production.unseal(original,'proofs','same-account'));
 const isolated=await production.seal({...value,payload:{photo:'PRODUCTION PHOTO'}},'proofs');
 assert.equal((await production.unseal(isolated,'proofs','same-account')).payload.photo,'PRODUCTION PHOTO');
 await assert.rejects(development.unseal(isolated,'proofs','same-account'));
});

test('production opens its own outbox while development keeps pending historical proofs',async()=>{
 for(const name of ['development','production']){
  const opened=[];
  const c={queueMicrotask,ArcUI:{esc:String},navigator:{onLine:true},CocoEnvironment:environment(name),CocoOfflineVault:{},GamaCloud:{getSession:async()=>({data:{session:{user:{id:'same-account'}}}})},addEventListener(){},indexedDB:{open(database){opened.push(database);const request={error:Error('db-unavailable')};queueMicrotask(()=>request.onerror());return request}}};
  c.window=c;
  vm.runInNewContext(fs.readFileSync('src/features/transport/offline-proofs.js','utf8'),c);
  await assert.rejects(c.ArchitectOfflineProofs.rows(),/db-unavailable/);
  assert.ok(opened.length>=2);
  assert.ok(opened.every(database=>database===(name==='production'?'coco:production:architect-proof-outbox':'architect-proof-outbox')));
 }
});
