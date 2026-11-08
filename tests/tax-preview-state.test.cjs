const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('src/features/finance/tax-engine.js','utf8');
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function fixture(){
 const calls=[],timers=new Map();let timerId=0,data={quantity:1};
 const window={ArcUI:{esc:String},ArcFormat:{money:String},GamaI18n:{language:'es'},ArcData:{rawRpc:(fn,args)=>{let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no});calls.push({fn,args,resolve:value=>resolve({data:value}),reject});return promise}}};
 const context=vm.createContext({window,setTimeout:fn=>{const id=++timerId;timers.set(id,fn);return id},clearTimeout:id=>timers.delete(id)});
 const anchor='window.CocoTaxEngine=Object.freeze({';assert.ok(source.includes(anchor));
 // Expose only the actual private coordinator inside this isolated VM. The
 // production module/API remains unchanged and no browser or database is mocked.
 vm.runInContext(source.replace(anchor,'window.__taxPreviewTest={schedule,ensure};'+anchor),context);
 const {schedule,ensure}=window.__taxPreviewTest,applied=[],s={host:{isConnected:true},status:{textContent:''},token:0,read:()=>({...data}),apply:r=>applied.push(r)};
 s.refresh=()=>schedule(s,s.read,s.apply);
 return {s,calls,timers,applied,ensure,change:n=>{data={quantity:n};s.refresh()},fire:()=>{assert.equal(timers.size,1);const [id,fn]=timers.entries().next().value;timers.delete(id);fn()}};
}
test('save starts the current preview when an older request is in flight and its timer has not fired',async()=>{
 const f=fixture();f.change(1);f.fire();assert.equal(f.calls.length,1);
 f.change(2);const saving=f.ensure(f.s);await tick();
 assert.equal(f.calls.length,2,'save must not cancel B then wait solely for obsolete A');assert.equal(f.calls[1].args.p_data.quantity,2);
 f.calls[0].resolve({quantity:1});await tick();assert.deepEqual(f.applied,[]);
 const expected={quantity:2};f.calls[1].resolve(expected);assert.equal(await saving,expected);assert.deepEqual(f.applied,[expected]);assert.equal(f.s.pending,null);assert.equal(f.timers.size,0);
});
test('an older direct ensure cannot overwrite a newer preview and returns the current result',async()=>{
 const f=fixture();const saving=f.ensure(f.s);assert.equal(f.calls.length,1);
 f.change(2);f.fire();assert.equal(f.calls.length,2);const current={quantity:2};f.calls[1].resolve(current);await tick();
 f.calls[0].resolve({quantity:1});assert.equal(await saving,current);assert.deepEqual(f.applied,[current]);assert.equal(f.s.result,current);assert.equal(f.s.pending,null);
});
test('current errors propagate, can be retried, and a disconnected form never applies a response',async()=>{
 const f=fixture(),first=f.ensure(f.s);f.calls[0].reject(Error('preview unavailable'));await assert.rejects(first,/preview unavailable/);
 const retried=f.ensure(f.s);assert.equal(f.calls.length,2);const current={quantity:1};f.calls[1].resolve(current);assert.equal(await retried,current);
 f.change(2);const leaving=f.ensure(f.s);f.s.host.isConnected=false;f.calls.at(-1).resolve({quantity:2});await assert.rejects(leaving,/TAX_PREVIEW_REQUIRED/);assert.deepEqual(f.applied,[current]);
});
