const UUID=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

// GoTrue verifies the bearer. This preliminary parsing only prevents sending a
// local token or machine credential to the configured identity authority.
function authoritySubject(token,issuer){
 if(typeof token!=='string'||token.length>16384||!/^[-\w]+\.[-\w]+\.[-\w]+$/.test(token))return null;
 try{
  const payload=token.split('.')[1].replaceAll('-','+').replaceAll('_','/');
  const claims=JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(payload),byte=>byte.charCodeAt(0))));
  return claims.iss===issuer&&claims.role==='authenticated'&&claims.aud==='authenticated'&&claims.aal==='aal2'
   &&claims.is_anonymous===false&&!claims.client_id&&UUID.test(claims.session_id||'')&&UUID.test(claims.sub||'')
   &&Number.isFinite(claims.exp)&&claims.exp>Date.now()/1000?claims.sub:null;
 }catch{return null}
}

export async function getCocoAuthUser({env,fetcher,token,local}){
 const authority=env('COCO_AUTHORITY_URL'),publishable=env('COCO_AUTHORITY_PUBLISHABLE_KEY');
 if(!authority&&!publishable&&local)return local();
 let subject=null;
 if(authority||publishable){
  if(authority!=='https://mknsaibrewksgomuslev.supabase.co'||!/^sb_publishable_[a-z0-9_-]+$/i.test(publishable||''))return null;
  subject=authoritySubject(token,authority+'/auth/v1');
  if(!subject)return null;
 }
 const root=authority||env('SUPABASE_URL'),key=publishable||env('SUPABASE_ANON_KEY');
 if(!root||!key||!token)return null;
 try{
  const response=await fetcher(root+'/auth/v1/user',{headers:{apikey:key,Authorization:'Bearer '+token},redirect:'error',signal:AbortSignal.timeout(10000)});
  const user=response.ok?await response.json():null;
  return UUID.test(user?.id||'')&&(!subject||subject===user.id)?user:null;
 }catch{return null}
}
