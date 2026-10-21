/* AES-GCM vault: account key from the server; tab-scoped offline unlock expires
   after 48h and is removed on logout/account change. IndexedDB stores ciphertext.
   sessionStorage preserves an already unlocked driver's tab across offline reloads. */
(function(){'use strict';
let epoch=0,current=null,pending=null;
const KEY='coco.offline.unlock.';
const encode=new TextEncoder(),decode=new TextDecoder();
const bytes=hex=>Uint8Array.from(hex.match(/../g)||[],v=>parseInt(v,16));
async function key(actor){
 if(current?.actor===actor)return current.key;
 if(!navigator.onLine){let saved;try{saved=JSON.parse(sessionStorage.getItem(KEY+actor)||'null')}catch(_){}if(!saved||saved.expires<=Date.now()||!/^[0-9a-f]{64}$/.test(saved.material||''))throw Error('OFFLINE_UNLOCK_REQUIRED');const token=epoch,imported=await crypto.subtle.importKey('raw',bytes(saved.material),'AES-GCM',false,['encrypt','decrypt']);if(token!==epoch)throw Error('AUTH_CHANGED');current={actor,key:imported};return imported;}
 if(pending?.actor===actor)return pending.promise;
 const token=epoch,job={actor,promise:null};
 job.promise=(async()=>{const r=await window.ArcData.rpc('coco_offline_key');if(r.actor_id!==actor||!/^[0-9a-f]{64}$/.test(r.key))throw Error('AUTH_CHANGED');const imported=await crypto.subtle.importKey('raw',bytes(r.key),'AES-GCM',false,['encrypt','decrypt']);if(token!==epoch)throw Error('AUTH_CHANGED');current={actor,key:imported};try{sessionStorage.setItem(KEY+actor,JSON.stringify({material:r.key,expires:Date.now()+48*3600000}))}catch(_){}return imported})();pending=job;
 try{return await job.promise}finally{if(pending===job)pending=null}
}
async function pack(value){if(value instanceof Blob)return {__coco_blob:true,type:value.type,bytes:Array.from(new Uint8Array(await value.arrayBuffer()))};if(Array.isArray(value))return Promise.all(value.map(pack));if(value&&typeof value==='object'){const result={};for(const [k,v] of Object.entries(value))result[k]=await pack(v);return result}return value}
function unpack(value){if(value?.__coco_blob===true&&Array.isArray(value.bytes))return new Blob([new Uint8Array(value.bytes)],{type:value.type});if(Array.isArray(value))return value.map(unpack);if(value&&typeof value==='object')for(const k of Object.keys(value))value[k]=unpack(value[k]);return value}
async function seal(value,store){const actor=value.actor||value.actor_id;if(!actor)throw Error('AUTH_REQUIRED');const token=epoch,k=await key(actor),iv=crypto.getRandomValues(new Uint8Array(12));const id=store==='routes'?value.actor_id:value.request_key;const data=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:encode.encode(store+':'+actor+':'+id)},k,encode.encode(JSON.stringify(await pack(value))));if(token!==epoch)throw Error('AUTH_CHANGED');return {version:1,actor,actor_id:store==='routes'?actor:undefined,request_key:store==='proofs'?id:undefined,expires_at:store==='routes'?Date.parse(value.downloaded_at)+48*3600000:null,iv:Array.from(iv),ciphertext:Array.from(new Uint8Array(data))}}
async function unseal(value,store,actor){if(!value)return value;if((value.actor||value.actor_id)!==actor)throw Error('AUTH_CHANGED');if(value.version!==1)return value;const token=epoch,k=await key(actor),id=store==='routes'?value.actor_id:value.request_key;const plain=await crypto.subtle.decrypt({name:'AES-GCM',iv:new Uint8Array(value.iv),additionalData:encode.encode(store+':'+actor+':'+id)},k,new Uint8Array(value.ciphertext));if(token!==epoch)throw Error('AUTH_CHANGED');return unpack(JSON.parse(decode.decode(plain)))}
function lock(){epoch++;current=null;pending=null;try{for(const name of Object.keys(sessionStorage))if(name.startsWith(KEY))sessionStorage.removeItem(name)}catch(_){}}
window.CocoOfflineVault={key,seal,unseal,lock,unlocked:actor=>{if(current?.actor===actor)return true;try{return JSON.parse(sessionStorage.getItem(KEY+actor)||'null')?.expires>Date.now()}catch(_){return false}}};
})();
