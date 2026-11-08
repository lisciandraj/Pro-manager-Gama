import {test} from 'node:test';
import assert from 'node:assert/strict';
import {planAuthSecurity,configureAuth} from '../scripts/auth-security-policy.mjs';
const current=()=>({password_min_length:6,password_hibp_enabled:false,jwt_exp:3600,refresh_token_rotation_enabled:false,mfa_totp_enroll_enabled:false,mfa_totp_verify_enabled:false,uri_allow_list:'https://example.invalid/**',rate_limit_verify:30,smtp_pass:'PRIVATE_DO_NOT_PRINT'});
test('Auth plan hardens supported settings without weakening stricter policy or replacing redirects',()=>{
 const p=planAuthSecurity({...current(),password_min_length:20,jwt_exp:300});
 assert.equal(p.patch.password_min_length,undefined);assert.equal(p.patch.jwt_exp,undefined);
 assert.equal(p.patch.password_hibp_enabled,true);assert.equal(p.patch.uri_allow_list,undefined);
 assert.ok(p.warnings.includes('REDIRECT_ALLOWLIST_REQUIRES_EXACT_URL_REVIEW'));
 assert.ok(!JSON.stringify(p).includes('PRIVATE_DO_NOT_PRINT'));
});
test('Auth configuration dry run never mutates and apply verifies the partial update',async()=>{
 let state=current();const calls=[];const fetcher=async(url,o)=>{calls.push(o);assert.equal(o.redirect,'error');if(o.method==='PATCH'){state={...state,...JSON.parse(o.body)};}return Response.json(state)};
 const p=await configureAuth({token:'dummy-management-token',fetcher});assert.equal(p.applied,false);assert.deepEqual(calls.map(c=>c.method),['GET']);
 calls.length=0;const result=await configureAuth({token:'dummy-management-token',apply:true,fetcher});assert.equal(result.applied,true);assert.deepEqual(calls.map(c=>c.method),['GET','PATCH','GET']);
 assert.equal(state.password_min_length,12);assert.equal(state.jwt_exp,1800);assert.equal(state.uri_allow_list,'https://example.invalid/**');
 assert.ok(!JSON.stringify(result).includes(state.smtp_pass));
});
test('missing credentials, a foreign project and unapplied policy fail safely',async()=>{
 await assert.rejects(configureAuth({token:''}),/MANAGEMENT_TOKEN_REQUIRED/);
 await assert.rejects(configureAuth({token:'dummy-management-token',project:'foreign'}),/PROJECT_MISMATCH/);
 await assert.rejects(configureAuth({token:'dummy-management-token',apply:true,fetcher:async()=>Response.json(current())}),/NOT_APPLIED/);
 await assert.rejects(configureAuth({token:'dummy-management-token',fetcher:async()=>{throw Error('credential-sensitive details')}}),/AUTH_MANAGEMENT_UNAVAILABLE/);
});
