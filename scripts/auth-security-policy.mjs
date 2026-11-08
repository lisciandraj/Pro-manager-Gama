#!/usr/bin/env node
/** Partial Management API updates only. Never print the complete Auth config. */
import {pathToFileURL} from 'node:url';
export const PROJECT='mknsaibrewksgomuslev';
const keys=['password_min_length','password_hibp_enabled','jwt_exp','refresh_token_rotation_enabled','mfa_totp_enroll_enabled','mfa_totp_verify_enabled'];
export function planAuthSecurity(current){
 const desired={password_min_length:Math.max(12,Number(current.password_min_length)||0),password_hibp_enabled:true,
  jwt_exp:Math.min(1800,Number(current.jwt_exp)>0?Number(current.jwt_exp):1800),
  refresh_token_rotation_enabled:true,mfa_totp_enroll_enabled:true,mfa_totp_verify_enabled:true};
 const patch=Object.fromEntries(keys.filter(k=>current[k]!==desired[k]).map(k=>[k,desired[k]]));
 const redirects=String(current.uri_allow_list||'').split(',').map(x=>x.trim()).filter(Boolean);
 const warnings=[];
 if(redirects.some(x=>/[*!]/.test(x)))warnings.push('REDIRECT_ALLOWLIST_REQUIRES_EXACT_URL_REVIEW');
 if(!Number.isInteger(current.rate_limit_verify)||current.rate_limit_verify<1)warnings.push('AUTH_VERIFICATION_RATE_LIMIT_NOT_OBSERVED');
 return {project:PROJECT,patch,observed:Object.fromEntries(keys.map(k=>[k,current[k]??null])),warnings,
  redirects_changed:false,scope:'Auth configuration only; personal MFA enrollment and ERP mandatory-policy activation remain separate.'};
}
export async function configureAuth({token,project=PROJECT,apply=false,fetcher=fetch}){
 if(project!==PROJECT)throw Error('AUTH_PROJECT_MISMATCH');
 if(typeof token!=='string'||token.length<10)throw Error('SUPABASE_MANAGEMENT_TOKEN_REQUIRED');
 const url='https://api.supabase.com/v1/projects/'+project+'/config/auth';
 const request=async(method,body)=>{
  let response;
  try{response=await fetcher(url,{method,redirect:'error',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},
   body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)})}catch{throw Error('AUTH_MANAGEMENT_UNAVAILABLE')}
  if(!response.ok)throw Error('AUTH_MANAGEMENT_HTTP_'+response.status);
  try{return await response.json()}catch{throw Error('AUTH_MANAGEMENT_INVALID_RESPONSE')}
 };
 const before=await request('GET'),plan=planAuthSecurity(before);
 if(!apply)return {...plan,applied:false};
 if(Object.keys(plan.patch).length)await request('PATCH',plan.patch);
 const after=await request('GET');
 for(const [key,value] of Object.entries(plan.patch))if(after[key]!==value)throw Error('AUTH_SETTING_NOT_APPLIED:'+key);
 return {...plan,observed:planAuthSecurity(after).observed,applied:true};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 if(process.argv.includes('--help'))console.log('Usage: SUPABASE_ACCESS_TOKEN=<managed secret> node scripts/auth-security-policy.mjs [--apply]. Default: read-only plan. Exact redirect URLs and verification rate limits are preserved and reported for review.');
 else configureAuth({token:process.env.SUPABASE_ACCESS_TOKEN,apply:process.argv.includes('--apply')}).then(r=>console.log(JSON.stringify(r,null,2))).catch(e=>{console.error(/^[A-Z_0-9:]+$/.test(e.message)?e.message:'AUTH_POLICY_FAILED');process.exitCode=1});
}
