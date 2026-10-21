const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function api(){
 const allowed=new Set(['warehouses','documents','sales-orders','quotes','tms']);
 const calls=[],window={ArcUI:{esc:s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))},GamaI18n:{language:'fr',locale:'fr-FR',t:s=>s},gamaAccessAllowed:id=>allowed.has(id),ArcModules:{get:id=>allowed.has(id)?{label:id}:null},addEventListener(){},ArcRouter:{open:async id=>calls.push(['module',id])},GamaDocuments:{openRecord:async id=>calls.push(['document',id])},GamaInventoryV2:{focusProduct:async id=>calls.push(['product',id])}};
 const source=fs.readFileSync('src/features/processes/order-followup.js','utf8').replace('window.CocoFollowup={mount,wrap};','window.CocoFollowup={groupedActions,referenceList,actionContext,openRelated,safeLinks,changeText};');
 vm.runInNewContext(source,{window,Intl,Date,console});return {...window.CocoFollowup,window,calls};
}
const event={id:'a',type:'action',kind:'sales',order_id:'order',subject:'reserve',actor_id:'alice',actor_name:'Alice',source_type:'erp',created_at:'2026-10-20T13:00:00.123456Z'};
test('simultaneous movements sum while module snapshots and independent sources remain distinct',()=>{
 const {groupedActions:g}=api(),ref={kind:'product',id:'p',reference:'P-01',quantity:2};
 const movements=g([{...event,references:[ref]},{...event,id:'b',references:[{...ref,quantity:3}]}],{kind:'sales'});
 assert.equal(movements.length,1);assert.equal(movements[0].action_count,2);assert.equal(movements[0].references[0].quantity,5);
 const snapshots=g([{...event,kind:'module',order_id:null,module_id:'warehouses',action_count:2,references:[{...ref,record_id:'q1',quantity_mode:'snapshot'},{...ref,record_id:'q2',quantity_mode:'snapshot',quantity:3}]}],{module_id:'warehouses'});
 assert.equal(snapshots[0].references.length,2);assert.equal(snapshots[0].references[0].quantity,2);
 assert.equal(g([{...event},{...event,id:'b',source_type:'import'},{...event,id:'c',actor_name:'Agent Coco'},{...event,id:'d',created_at:'2026-10-20T13:00:00.123457Z'},{...event,id:'e',type:'note'}],{kind:'sales'}).length,5);
});
test('old UUID module links deduplicate, supported document links upgrade, and forbidden routes disappear',()=>{
 const {groupedActions:g}=api();
 const old=g([{...event,kind:'module',order_id:null,module_id:'warehouses',links:[{module:'warehouses',action:'module',id:'a'},{module:'warehouses',action:'module',id:'b'},{module:'evil',action:'module'},{module:'documents',action:'javascript',id:'c'}]}],{module_id:'warehouses'});
 assert.equal(old[0].links.length,1);
 const doc=g([{...event,kind:'module',order_id:null,module_id:'documents',record_table:'business_documents',action:'insert',links:[{module:'documents',action:'module',id:'doc-1'}]}],{module_id:'documents'});
 assert.equal(doc[0].links[0].action,'document');
 const deleted=g([{...event,kind:'module',order_id:null,module_id:'documents',record_table:'business_documents',action:'delete',links:[{module:'documents',action:'module',id:'doc-1'}]}],{module_id:'documents'});
 assert.equal(deleted[0].links[0].action,'module');
});
test('reference rendering escapes names and locations, preserves quantities before/after and the recorded currency',()=>{
 const {referenceList,changeText}=api();const html=referenceList([{reference:'DVDG005',name:'<img src=x onerror=alert(1)>',quantity:8,context:{location:'Quito <shelf>',changes:[{field:'quantity',before:5,after:8},{field:'reserved_quantity',before:0,after:2}]}}]);
 assert(html.includes('5 → 8'));assert(html.includes('0 → 2'));assert(html.includes('&lt;img'));assert(!html.includes('<img'));assert(html.includes('Quito &lt;shelf&gt;'));
 assert.equal(changeText({field:'amount',before:10,after:12.5},{currency:'USD'}),'10 → 12,5 USD');
});
test('history omits source rows while retaining missing measurement information',()=>{
 const {actionContext,window}=api();
 for(const language of ['fr','es','en']){window.GamaI18n.language=language;
  assert.equal(actionContext({type:'action',source_type:'erp',references:[{quantity:2}]},false),'');
  assert.match(actionContext({type:'action',references:[]},false),/cocoFollowupUnmeasured/);
  assert.equal(actionContext({type:'action',references:[]},true),'');
 }
});
test('exact document and product navigation uses existing APIs and checks current access',async()=>{
 const {openRelated,window,calls}=api();await openRelated({module:'documents',action:'document',id:'doc-1'});await openRelated({module:'warehouses',action:'stock_product',id:'p-1'});
 assert.deepEqual(calls,[['module','documents'],['document','doc-1'],['module','warehouses'],['product','p-1']]);
 window.gamaAccessAllowed=()=>false;await assert.rejects(openRelated({module:'documents',action:'document',id:'secret'}),/ROLE_NOT_ALLOWED/);assert.equal(calls.length,4);
});
