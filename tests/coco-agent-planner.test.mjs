import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {prepareStockMessage} from '../supabase/functions/gama-assistant-ia/stock-planner.mjs';
const pid=randomUUID(),lid=randomUUID();
const intent={product_query:'MED001',location_query:'',operation:'out',quantity:null,target_quantity:null,all_stock:true,kind:'internal_use',reason:'consommation interne',needs_clarification:false,clarification:''};
function fixture(change={},data={}){
 const calls=[],requestKey=randomUUID();
 return {calls,run:()=>prepareStockMessage({question:'Retire tout le MED001 pour consommation interne',language:'fr',requestKey,config:{key:'isolated',model:'test'},openai:async()=>({output:[{content:[{type:'output_text',text:JSON.stringify({...intent,...change})}]}]}),rpc:async(action,payload)=>{calls.push({action,payload});assert.notEqual(action,'execute');if(action==='search')return {items:data.items||[{id:pid,reference:'MED001',name:'Test'}]};if(action==='stock')return {lot_tracking:!!data.lot_tracking,locations:data.locations||[{location_id:lid,location:'A1',quantity:65,available:65}]};return {id:randomUUID(),snapshot:payload,state:'prepared'}}})};
}
test('natural language prepares the exact internal-consumption proposal without executing',async()=>{const f=fixture(),r=await f.run();assert.equal(r.status,'prepared');assert.deepEqual(f.calls.map(c=>c.action),['search','stock','prepare']);assert.equal(f.calls[2].payload.reason,'consommation interne');assert.equal(f.calls[2].payload.all_stock,true)});
test('ambiguous product names are never auto-selected',async()=>{const f=fixture({product_query:'MED'},{items:[{id:pid,name:'MED A'},{id:randomUUID(),name:'MED B'}]});assert.equal((await f.run()).status,'needs_clarification');assert.equal(f.calls.length,1)});
test('invented or translated reasons cannot reach preparation',async()=>{const f=fixture({reason:'consumo interno'});assert.equal((await f.run()).status,'needs_clarification');assert.equal(f.calls.length,0)});
test('explicit clarification never reads stock',async()=>{const f=fixture({needs_clarification:true,clarification:'Quel produit ?'});assert.equal((await f.run()).message,'Quel produit ?');assert.equal(f.calls.length,0)});
test('lot tracked stock is directed to the existing lot workflow',async()=>{const f=fixture({}, {lot_tracking:true});assert.equal((await f.run()).status,'needs_clarification');assert.ok(!f.calls.some(c=>c.action==='prepare'))});
test('finite manual quantities need an unambiguous location',async()=>{const f=fixture({all_stock:false,quantity:2},{locations:[{location_id:lid,location:'A1'},{location_id:randomUUID(),location:'A2'}]});assert.equal((await f.run()).status,'needs_clarification')});
test('unexpected model fields are rejected before any database call',async()=>{const f=fixture({execute:true});await assert.rejects(f.run(),/AI_INVALID_RESPONSE/);assert.equal(f.calls.length,0)});
