import {test} from 'node:test';import assert from 'node:assert/strict';
import {onRequest} from '../src/storefront/server/api.mjs';import {escapeBootstrap,metadata} from '../src/storefront/server/middleware.mjs';
const token='a'.repeat(64),request=(action,data={},headers={})=>new Request('https://gama.pages.dev/api/storefront',{method:'POST',headers:{'Content-Type':'application/json',Origin:'https://gama.pages.dev','CF-Connecting-IP':'198.51.100.5',...headers},body:JSON.stringify({p_action:action,p_data:data})});
test('public proxy only allows the catalogue contract and bounds the complete body',async()=>{
 for(const a of ['public_connection','public_inquiries','delete','overview']){const r=await onRequest({request:request(a),fetcher:()=>assert.fail('must not reach database')});assert.equal(r.status,400)}
 let r=await onRequest({request:new Request('https://gama.pages.dev/api/storefront')});assert.equal(r.status,405);
 r=await onRequest({request:request('bootstrap',{value:'x'.repeat(28000)}),fetcher:()=>assert.fail()});assert.equal(r.status,413);
 let sent; r=await onRequest({request:request('catalog',{search:'Café',visitor:'untrusted'}),fetcher:async(u,o)=>{sent=JSON.parse(o.body);assert.equal(o.headers['x-coco-site-token'],undefined);return Response.json({items:[],total:0})}});assert.equal(r.status,200);assert.equal(sent.p_data.visitor,undefined);
});
test('public writes require a server secret and same origin; the visitor identity is overwritten',async()=>{
 let r=await onRequest({request:request('submit'),fetcher:()=>assert.fail()});assert.equal(r.status,503);
 r=await onRequest({request:request('submit',{}, {Origin:'https://other.invalid'}),env:{COCO_SITE_TOKEN:token},fetcher:()=>assert.fail()});assert.equal(r.status,403);
 r=await onRequest({request:request('submit',{visitor:'attacker',contact_name:'QA'}),env:{COCO_SITE_TOKEN:token},fetcher:async(u,o)=>{assert.equal(o.headers['x-coco-site-token'],token);assert.equal(JSON.parse(o.body).p_data.visitor,'198.51.100.5');assert.ok(o.headers.apikey.startsWith('sb_publishable_'));return Response.json({reference:'WEB-00000001'})}});
 assert.equal(r.status,200);assert.deepEqual(await r.json(),{reference:'WEB-00000001'});
 r=await onRequest({request:request('bootstrap'),fetcher:async()=>Response.json({message:'private table failed; secret='+token},{status:500})});assert.equal(r.status,503);assert.deepEqual(await r.json(),{error:'WEBSITE_UNAVAILABLE'});
 r=await onRequest({request:request('submit'),env:{COCO_SITE_TOKEN:token},fetcher:async()=>Response.json({message:'WEBSITE_RATE_LIMIT'},{status:400})});assert.equal(r.status,429);
});
test('bootstrap injection cannot close its inert JSON script and SEO text stays plain',()=>{const data={settings:{seo_title:'GAMA <test>',seo_description:'Catalogue',primary_color:'#176072',hero_title:'</script><script>alert(1)</script>'}};const s=escapeBootstrap(data);assert.ok(!s.includes('<'));assert.deepEqual(JSON.parse(s),data);assert.equal(metadata(data).title,'GAMA <test>');assert.equal(metadata({settings:{primary_color:'javascript:bad'}}).color,'#176072')});
