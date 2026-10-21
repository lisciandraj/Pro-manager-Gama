const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function harness(){
 class Element{
  constructor(){this.html='';this.dataset={};this.attributes={};this.edited=false}
  get innerHTML(){return this.html}set innerHTML(value){this.html=value;this.edited=false}
  replaceChildren(){this.innerHTML=''}
  insertAdjacentHTML(where,value){assert.equal(where,'beforeend');this.html+=value}
  setAttribute(k,v){this.attributes[k]=v}
  addEventListener(){}close(){}scrollIntoView(){}
 }
 const elements=new Map(),element=id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id)},pending=[],calls=[],signals=[];
 const context={AbortController,AbortSignal,URL,Intl,Map,Set,Promise,setTimeout,clearTimeout,sessionStorage:{getItem:()=>null,removeItem:()=>{}},document:{getElementById:element,querySelectorAll:()=>[],addEventListener:()=>{}},window:{GamaCustomer:{isActive:()=>false,ready:new Promise(()=>{})},addEventListener:()=>{}},fetch:async(_,options)=>{signals.push(options.signal);const data=JSON.parse(options.body);calls.push(data);return new Promise(resolve=>pending.push({data,resolve}))}};
 let source=fs.readFileSync(path.join(__dirname,'../src/storefront/site.js'),'utf8');
 source=source.replace(/\}\)\(\);\s*$/,"window.probe={catalogue,sessionChanged,setup(s='',o=0){boot={categories:[]};cfg={enable_quotes:true};search=s;offset=o}};})();");
 vm.runInNewContext(source,context);context.window.probe.setup();
 const answer=(items,total=205,status=200)=>{const p=pending.shift();assert.ok(p,'request pending');p.resolve({ok:status===200,json:async()=>status===200?{items,total}:({error:'WEBSITE_UNAVAILABLE'})});return p.data};
 return {api:context.window.probe,element,pending,calls,signals,answer};
}
const rows=(start,n)=>Array.from({length:n},(_,i)=>({id:'10000000-0000-4000-8000-'+String(start+i).padStart(12,'0'),name:'Product '+(start+i),reference:'R-'+(start+i),has_photo:false,category_title:'QA'}));
const count=h=>(h.element('siteProducts').innerHTML.match(/class="product-card"/g)||[]).length;
test('first 30 cards are usable before later batches; final page has 100 and does not replace edited cards',async()=>{
 const h=harness(),done=h.api.catalogue();h.answer(rows(1,30));await tick();
 assert.equal(count(h),30);assert.ok(h.element('siteProducts').innerHTML.includes('data-add='));h.element('siteProducts').edited=true;
 assert.equal(h.pending.length,1);assert.equal(h.pending[0].data.p_data.offset,30);
 h.answer(rows(31,30));await tick();h.answer(rows(61,30));await tick();h.answer(rows(91,10));await done;
 assert.equal(count(h),100);assert.equal(h.element('siteProducts').edited,true);assert.equal(h.element('siteProducts').attributes['aria-busy'],'false');
 assert.deepEqual(h.calls.map(c=>[c.p_data.offset,c.p_data.limit]),[[0,30],[30,30],[60,30],[90,10]]);
 assert.ok(h.element('sitePager').innerHTML.includes('1 / 3'));
});
test('a late batch from an older search cannot append or overwrite a newer result',async()=>{
 const h=harness(),old=h.api.catalogue();h.answer(rows(1,30));await tick();
 h.api.setup('new');const fresh=h.api.catalogue();assert.equal(count(h),0);assert.equal(h.signals[1].aborted,true);assert.equal(h.signals[2].aborted,false);
 h.answer(rows(31,30));await old;h.answer(rows(901,1),1);await fresh;
 assert.equal(count(h),1);assert.ok(h.element('siteProducts').innerHTML.includes('Product 901'));assert.ok(!h.element('siteProducts').innerHTML.includes('Product 31'));
});
test('account change discards an in-flight catalogue response and its prices',async()=>{
 const h=harness(),old=h.api.catalogue();h.answer(rows(1,30));await tick();h.api.sessionChanged();
 h.answer(rows(31,30));await old;assert.equal(count(h),0);
});
test('failed later batch preserves usable cards and exposes an error instead of a success pager',async()=>{
 const h=harness(),done=h.api.catalogue();h.answer(rows(1,30));await tick();h.answer([],205,503);await done;
 assert.equal(count(h),30);assert.equal(h.element('siteProducts').attributes['aria-busy'],'false');assert.match(h.element('siteStatus').textContent,/Vuelve a intentarlo/);assert.match(h.element('sitePager').innerHTML,/data-catalog-retry/);
});
test('pagination follows the number actually returned by a smaller server cap',async()=>{
 const h=harness(),done=h.api.catalogue();h.answer(rows(1,20),40);await tick();assert.equal(h.pending[0].data.p_data.offset,20);h.answer(rows(21,20),40);await done;assert.equal(count(h),40);
});
