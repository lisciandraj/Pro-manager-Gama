/* Versioned server-only encryption. Legacy envelopes are decrypt-only so the
   service-role credential is never used to encrypt a newly saved provider key. */
const encoder=new TextEncoder(),decoder=new TextDecoder();
const b64=value=>btoa(String.fromCharCode(...new Uint8Array(value)));
const unb64=value=>Uint8Array.from(atob(value),c=>c.charCodeAt(0));
const fail=code=>{const error=new Error(code);error.status=503;return error;};
function keyring(env){
 const id=env('GAMA_AI_ENCRYPTION_KEY_ID')||'primary';
 if(!/^[A-Za-z0-9_-]{1,40}$/.test(id))throw fail('AI_ENCRYPTION_CONFIGURATION_REQUIRED');
 let keys={};
 try{keys=JSON.parse(env('GAMA_AI_ENCRYPTION_KEYS')||'{}');}catch{throw fail('AI_ENCRYPTION_CONFIGURATION_REQUIRED');}
 if(!keys||typeof keys!=='object'||Array.isArray(keys))throw fail('AI_ENCRYPTION_CONFIGURATION_REQUIRED');
 if(env('GAMA_AI_ENCRYPTION_KEY'))keys[id]=env('GAMA_AI_ENCRYPTION_KEY');
 return {id,keys};
}
async function derive(secret,context){
 return crypto.subtle.importKey('raw',await crypto.subtle.digest('SHA-256',encoder.encode(context+secret)),{name:'AES-GCM'},false,['encrypt','decrypt']);
}
export function aiKeyRotationRequired(value,env){
 const {id}=keyring(env);return typeof value!=='string'||!value.startsWith('v2.'+id+'.');
}
export async function encryptAiKey(value,env){
 const {id,keys}=keyring(env),secret=keys[id];
 if(typeof secret!=='string'||secret.length<32)throw fail('AI_ENCRYPTION_CONFIGURATION_REQUIRED');
 const iv=crypto.getRandomValues(new Uint8Array(12)),key=await derive(secret,'coco-ai-settings:v2:'+id+':');
 const data=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:encoder.encode('coco-ai-settings:v2:'+id)},key,encoder.encode(value));
 return ['v2',id,b64(iv),b64(data)].join('.');
}
export async function decryptAiKey(value,env){
 try{
  if(typeof value!=='string'||value.length>2000)throw Error();
  const parts=value.split('.'),{keys}=keyring(env);
  if(parts[0]==='v2'){
   if(parts.length!==4||!/^[A-Za-z0-9_-]{1,40}$/.test(parts[1])||typeof keys[parts[1]]!=='string')throw Error();
   const key=await derive(keys[parts[1]],'coco-ai-settings:v2:'+parts[1]+':');
   return decoder.decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:unb64(parts[2]),additionalData:encoder.encode('coco-ai-settings:v2:'+parts[1])},key,unb64(parts[3])));
  }
  if(parts.length!==2)throw Error();
  // Keep old encrypted settings readable during a coordinated rotation. Retired
  // service-role values may be supplied in this explicit, temporary key list.
  const legacy=JSON.parse(env('GAMA_AI_LEGACY_ENCRYPTION_KEYS')||'[]');
  if(!Array.isArray(legacy)||legacy.length>8)throw Error();
  const candidates=[env('GAMA_AI_ENCRYPTION_KEY'),...legacy,env('SUPABASE_SERVICE_ROLE_KEY')].filter(s=>typeof s==='string'&&s);
  for(const secret of candidates)try{
   const key=await derive(secret,'gama-assistant-ia-v1:');
   return decoder.decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:unb64(parts[0])},key,unb64(parts[1])));
  }catch{/* Try only the explicitly configured legacy keys. */}
 }catch{/* Never disclose ciphertext, key material or crypto internals. */}
 throw fail('AI_KEY_RECONNECT');
}
