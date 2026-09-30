const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function loader(){
 const scripts=[],window={ArcAssets:{'gama-service-documents.js':'gama-service-documents.js?v=123456789abc'}};
 const context={window,document:{createElement:()=>({dataset:{},remove(){this.removed=true}}),head:{appendChild:s=>scripts.push(s)}}};
 vm.createContext(context);
 const config=fs.readFileSync('src/app/lazy-modules.js','utf8').replace('export const','const');
 const code=fs.readFileSync('src/app/loader.js','utf8').replace(/^import .*;$/gm,'').replace(/^export \{.*;$/gm,'').replace(/export /g,'');
 vm.runInContext(config+'\n'+code+'\nthis.api={loadModule,installLazyModules};',context);
 context.api.installLazyModules();return {scripts,window,...context.api};
}
test('service and documents share one download and expose their own API',async()=>{
 const x=loader(),a=x.loadModule('sav'),b=x.loadModule('documents');
 assert.equal(x.scripts.length,1);assert.match(x.scripts[0].src,/v=123456789abc/);
 x.window.GamaService={open:()=>1};x.window.GamaDocuments={open:()=>2};x.scripts[0].onload();
 assert.equal((await a).open(),1);assert.equal((await b).open(),2);
 await x.loadModule('sav');assert.equal(x.scripts.length,1);
});
test('a failed asset can be retried and stubs forward arguments',async()=>{
 const x=loader(),first=x.loadModule('knowledge');x.scripts[0].onerror();
 await assert.rejects(first,/MODULE_LOAD_FAILED/);assert.equal(x.scripts[0].removed,true);
 const next=x.window.GamaKnowledge.openArticle('article-1');
 assert.equal(x.scripts.length,2);x.window.GamaKnowledge={openArticle:id=>'opened:'+id};x.scripts[1].onload();
 assert.equal(await next,'opened:article-1');
});
