const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function loader(){
 const scripts=[],window={ArcAssets:{'assets/vendor/jspdf-2.5.2.umd.min.js':'assets/vendor/jspdf-2.5.2.umd.min.js?v=123456789abc'}};
 const context={window,document:{createElement:()=>({remove(){this.removed=true}}),head:{appendChild:s=>scripts.push(s)}}};
 vm.createContext(context);vm.runInContext(fs.readFileSync('src/features/documents/pdf.js','utf8'),context);
 return {scripts,window,ready:window.GamaPdf.ready};
}
test('concurrent PDF actions share a versioned engine request with integrity',async()=>{
 const x=loader(),a=x.ready(),b=x.ready();assert.equal(a,b);assert.equal(x.scripts.length,1);
 assert.match(x.scripts[0].src,/v=123456789abc/);assert.match(x.scripts[0].integrity,/^sha384-/);
 assert.equal(x.scripts[0].crossOrigin,'anonymous');
 const Constructor=function PDF(){};x.window.jspdf={jsPDF:Constructor};x.scripts[0].onload();
 assert.equal(await a,Constructor);assert.equal(await x.ready(),Constructor);assert.equal(x.scripts.length,1);
 assert.equal(x.window.GamaPdf.jsPDF(),Constructor);
});
for(const outcome of ['network failure','missing SDK'])test('PDF engine retries after '+outcome,async()=>{
 const x=loader(),first=x.ready();
 x.scripts[0][outcome==='network failure'?'onerror':'onload']();
 await assert.rejects(first,/MODULE_LOAD_FAILED/);assert.equal(x.scripts[0].removed,true);
 const next=x.ready();assert.equal(x.scripts.length,2);const Constructor=function PDF(){};
 x.window.jspdf={jsPDF:Constructor};x.scripts[1].onload();assert.equal(await next,Constructor);
});
test('an already installed PDF engine creates no script',async()=>{
 const x=loader(),Constructor=function PDF(){};x.window.jspdf={jsPDF:Constructor};
 assert.equal(await x.ready(),Constructor);assert.equal(x.scripts.length,0);
});
