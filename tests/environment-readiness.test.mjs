import {test} from 'node:test';
import assert from 'node:assert/strict';
import {checkEnvironmentReadiness} from '../scripts/check-environment-readiness.mjs';

const development={supabaseUrl:'https://aaaaaaaaaaaaaaaaaaaa.supabase.co',publishableKey:'sb_publishable_development'};
const production={supabaseUrl:'https://bbbbbbbbbbbbbbbbbbbb.supabase.co',publishableKey:'sb_publishable_frozen_production'};
function fixture(overrides={}){
 const calls=[];
 const options={configuration:{development,production:null},productionConfiguration:{production},fetchImpl:async(url,request)=>{
  calls.push({url,request});
  const name=url.startsWith(production.supabaseUrl)?'production':'development';
  return {ok:true,status:200,json:async()=>({environment:name,allowed:name==='production',admin:false})};
 },...overrides};
 return {options,calls};
}

test('publication requires both anonymous server markers using development and frozen production configurations',async()=>{
 const {options,calls}=fixture();
 options.configuration.production={supabaseUrl:'https://cccccccccccccccccccc.supabase.co',publishableKey:'sb_publishable_unapproved'};
 assert.deepEqual(await checkEnvironmentReadiness(options),{
  production:{environment:'production',allowed:true,admin:false},
  development:{environment:'development',allowed:false,admin:false}
 });
 assert.deepEqual(calls.map(call=>call.url),[production.supabaseUrl,development.supabaseUrl].map(url=>url+'/rest/v1/rpc/coco_environment_status'));
 for(const [index,{request}] of calls.entries()){
  assert.deepEqual(request.headers,{apikey:index===0?production.publishableKey:development.publishableKey,'Content-Type':'application/json',Accept:'application/json'});
  assert.equal(request.method,'POST');assert.equal(request.body,'{}');
  assert.equal(request.credentials,'omit');assert.equal(request.redirect,'error');
  assert.equal(request.cache,'no-store');assert.ok(request.signal instanceof AbortSignal);
 }
});

test('unassigned or swapped server markers block publication',async t=>{
 for(const [name,marker] of [['production','unassigned'],['production','development'],['development','production']]){
  await t.test(name+' marked '+marker,async()=>{
   const {options}=fixture({fetchImpl:async url=>({ok:true,json:async()=>{
    const environment=url.startsWith(production.supabaseUrl)?'production':'development';
    return {environment:environment===name?marker:environment,allowed:environment==='production',admin:false};
   }})});
   await assert.rejects(checkEnvironmentReadiness(options),new RegExp(name+' environment is not ready'));
  });
 }
});

test('incorrect anonymous permissions, administrator sessions and malformed status fail closed',async t=>{
 const invalid=[{environment:'production',allowed:false,admin:false},{environment:'production',allowed:'true',admin:false},
  {environment:'production',allowed:true,admin:true},{environment:'production',allowed:true},null,[],{}];
 for(const [index,status] of invalid.entries())await t.test('invalid production status '+index,async()=>{
  const {options}=fixture({fetchImpl:async()=>({ok:true,json:async()=>status})});
  await assert.rejects(checkEnvironmentReadiness(options),/production environment is not ready/);
 });
 const {options}=fixture({fetchImpl:async url=>({ok:true,json:async()=>({environment:url.startsWith(production.supabaseUrl)?'production':'development',allowed:true,admin:false})})});
 await assert.rejects(checkEnvironmentReadiness(options),/development environment is not ready/);
});

test('missing, privileged or shared backend configuration is rejected before contacting either server',async t=>{
 const cases=[
  {configuration:{}},
  {productionConfiguration:{}},
  {productionConfiguration:{production:null}},
  {productionConfiguration:{production:{supabaseUrl:production.supabaseUrl}}},
  {productionConfiguration:{production:{...production,publishableKey:'sb_secret_forbidden'}}},
  {productionConfiguration:{production:development}}
 ];
 for(const [index,overrides] of cases.entries())await t.test('invalid configuration '+index,async()=>{
  const {options,calls}=fixture(overrides);
  await assert.rejects(checkEnvironmentReadiness(options));assert.equal(calls.length,0);
 });
});

test('missing RPC, server errors, invalid JSON and transport failures block publication',async t=>{
 for(const status of [404,500])await t.test('HTTP '+status,async()=>{
  const {options}=fixture({fetchImpl:async()=>({ok:false,status})});
  await assert.rejects(checkEnvironmentReadiness(options),new RegExp('production environment readiness RPC returned HTTP '+status));
 });
 await t.test('invalid JSON',async()=>{
  const {options}=fixture({fetchImpl:async()=>({ok:true,json:async()=>{throw Error('raw response');}})});
  await assert.rejects(checkEnvironmentReadiness(options),/production environment readiness RPC returned invalid JSON/);
 });
 await t.test('transport error does not echo request or remote content',async()=>{
  const {options}=fixture({fetchImpl:async()=>{throw Error('private diagnostic');}});
  await assert.rejects(checkEnvironmentReadiness(options),{message:'production environment readiness RPC could not be reached'});
 });
});
