/* Public deployment probes only: no tokens, production fixtures or stock writes. */
import assert from 'node:assert/strict';
const root='https://mknsaibrewksgomuslev.supabase.co/functions/v1';
const read=async(path,options={})=>fetch(root+path,{...options,redirect:'error',signal:AbortSignal.timeout(20000)});
const health=await read('/coco-agent-mcp/health');assert.equal(health.status,200);assert.equal((await health.json()).service,'Agent Coco');
const discovery=await read('/coco-agent-mcp/.well-known/oauth-protected-resource');assert.equal(discovery.status,200);assert.equal((await discovery.json()).resource,root+'/coco-agent-mcp');
const denied=await read('/coco-agent-mcp',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:1,method:'initialize',params:{}})});assert.equal(denied.status,401);assert.match(denied.headers.get('www-authenticate')||'',/resource_metadata/);
const assistant=await read('/gama-assistant-ia',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'status'})});assert.equal(assistant.status,401);
console.log(JSON.stringify({checked_at:new Date().toISOString(),gateway_health:'passed',oauth_metadata:'passed',unauthenticated_mcp:'rejected_401',unauthenticated_assistant:'rejected_401',stock_movement_performed:false}));
