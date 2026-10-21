const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
function harness({deny=false}={}){
 let blob,reads=0,downloads=0;
 const source=fs.readFileSync(path.join(__dirname,'../src/features/audit/audit.js'),'utf8').replace('window.ArchitectAudit={','window.exportUnderTest=exportCsv;window.ArchitectAudit={');
 const entries=['=1+1','+1+1','-1+1','@SUM(1)','\t=1+1','\r=1+1','\n=1+1','\0=1+1','  =1+1','\u00a0@SUM(1)','Texte; "cité"','Équateur'];
 const rows=entries.map(detail=>({at:'2026-10-19',kind:'stock',label:'Action',detail,reference:'=1+2',amount:-12.5,quantity:2,actor:'+1+2'}));
 const context={Blob,URL:{createObjectURL:b=>{blob=b;return 'blob:test'},revokeObjectURL:()=>{}},setTimeout:()=>{},document:{getElementById:()=>({}),createElement:()=>({click:()=>downloads++})},window:{ArcUI:{esc:String},addEventListener:()=>{},ArchitectAccessControls:{requireAction:async(m,a)=>{assert.equal(m,'audit');assert.equal(a,'export');if(deny)throw Error('FORBIDDEN')}},ArcData:{rpc:async()=>{reads++;return {items:rows,has_more:false}}}}};
 vm.runInNewContext(source,context);
 return {run:()=>context.window.exportUnderTest(),result:()=>({blob,reads,downloads}),entries};
}
test('audit CSV neutralizes spreadsheet formulas in user text while retaining typed negative amounts and CSV quoting',async()=>{
 const h=harness();await h.run();const {blob,downloads}=h.result(),text=await blob.text();assert.equal(downloads,1);
 for(const value of h.entries.slice(0,10))assert.ok(text.includes('"\''+value+'"'),JSON.stringify(value));
 assert.ok(text.includes('"Texte; ""cité"""'));assert.ok(text.includes('"Équateur"'));
 assert.ok(text.includes('"-12.5";"2"'));assert.ok(!text.includes('"\'-12.5"'));
 assert.ok(text.includes('"\'=1+2"'));assert.ok(text.includes('"\'+1+2"'));
});
test('audit export checks permission before reading records or downloading a file',async()=>{
 const h=harness({deny:true});await assert.rejects(h.run(),/FORBIDDEN/);assert.equal(h.result().reads,0);assert.equal(h.result().downloads,0);
});
