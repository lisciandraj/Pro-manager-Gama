import {test} from 'node:test';
import assert from 'node:assert/strict';
import {APPROVED,assertReady,cloudflareClient,freezeProduction,snapshot} from './publish-initial-coco-catalogue.mjs';

const runtime = {url:'https://vhutzdfatijjpahsqkne.supabase.co',publishable_key:'sb_publishable_test'};
const marker = {environment:'production',release:APPROVED,allowed:true,admin:false};
const response = data => new Response(JSON.stringify(data),{headers:{'Content-Type':'application/json'}});
const project = () => ({id:'known-project',name:'gama-coco',subdomain:'gama-coco.pages.dev',production_branch:'main',
  deployment_configs:{production:{compatibility_date:'2026-09-01',env_vars:{COCO_SITE_TOKEN:{type:'secret_text'},TURNSTILE_SITE_KEY:{type:'plain_text',value:'public'}}},preview:{env_vars:{PREVIEW_ONLY:{type:'plain_text',value:'keep'}}}},
  source:{type:'github',config:{owner:'lisciandraj',repo_name:'Pro-manager-Gama',production_deployments_enabled:true,preview_deployment_setting:'custom',preview_branch_includes:['review/*'],pr_comments_enabled:true,path_excludes:['docs/*']}}
});

test('a backend mismatch performs no remote operation',async()=>{
  let calls=0;
  await assert.rejects(assertReady({...runtime,url:'https://mknsaibrewksgomuslev.supabase.co'},async()=>{calls++;}),/backend configuration mismatch/);
  assert.equal(calls,0);
});

test('missing or unauthorized production markers stop before catalogue reads',async()=>{
  for(const bad of [{...marker,environment:'development'},{...marker,allowed:false},{...marker,admin:true},{...marker,release:'a'.repeat(40)}]){
    let calls=0;
    await assert.rejects(assertReady(runtime,async(url,options)=>{calls++;assert.match(url,/coco_environment_status$/);assert.equal(options.redirect,'error');return response(bad);}),/marker/);
    assert.equal(calls,1);
  }
});

test('initial release requires an unpaused catalogue with no products',async()=>{
  for(const bad of [{paused:true,total:0,featured:[]},{paused:false,total:1,featured:[]},{paused:false,total:0,featured:[{id:1}]}]){
    await assert.rejects(assertReady(runtime,async(url)=>response(url.endsWith('coco_environment_status')?marker:bad)),/not ready and empty/);
  }
  const actions=[];
  await assertReady(runtime,async(url,options)=>{
    if(url.endsWith('coco_environment_status'))return response(marker);
    const action=JSON.parse(options.body).p_action;actions.push(action);
    return response(action==='bootstrap'?{paused:false,total:0,featured:[]}:{total:0,items:[]});
  });
  assert.deepEqual(actions,['bootstrap','catalog']);
});

test('production freeze changes only the Git production flag, retaining previews and bindings',async()=>{
  let current=project(),patches=0;
  const before=structuredClone(current),expected=snapshot(current);
  const client=async(method='GET',body)=>{
    if(method==='PATCH'){
      patches++;assert.deepEqual(Object.keys(body),['source']);
      assert.deepEqual(body.source,{type:before.source.type,config:{...before.source.config,production_deployments_enabled:false}});
      current={...current,source:structuredClone(body.source)};
    }
    return structuredClone(current);
  };
  const after=await freezeProduction(client,expected);
  assert.equal(patches,1);
  assert.deepEqual(after.deployment_configs,before.deployment_configs);
  assert.equal(after.source.config.production_deployments_enabled,false);
  assert.equal(after.source.config.preview_deployment_setting,'custom');
  await freezeProduction(client,expected);assert.equal(patches,1);
});

test('concurrent configuration changes abort before any production mutation',async()=>{
  const before=project(),after=project();after.deployment_configs.production.env_vars.TURNSTILE_SITE_KEY.value='changed';let writes=0;
  await assert.rejects(freezeProduction(async(method='GET')=>{if(method!=='GET')writes++;return after;},snapshot(before)),/bindings changed/);
  assert.equal(writes,0);
});

test('Cloudflare target lookup never follows a redirect or creates a project',async()=>{
  let calls=0;
  const client=cloudflareClient({CLOUDFLARE_ACCOUNT_ID:'a'.repeat(32),CLOUDFLARE_API_TOKEN:'fake-test-token'},async(url,options)=>{
    calls++;assert.equal(url,'https://api.cloudflare.com/client/v4/accounts/'+ 'a'.repeat(32)+'/pages/projects/gama-coco');
    assert.equal(options.method,'GET');assert.equal(options.redirect,'error');return response({success:true,result:{...project(),name:'other'}});
  });
  await assert.rejects(client(),/Unexpected existing/);assert.equal(calls,1);
});
