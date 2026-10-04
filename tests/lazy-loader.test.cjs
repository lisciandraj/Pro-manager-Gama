const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function loader(){
 const scripts=[],window={ArcAssets:{'gama-service-documents.js':'gama-service-documents.js?v=123456789abc'}};
 const context={window,document:{createElement:()=>({dataset:{},remove(){this.removed=true}}),head:{appendChild:s=>scripts.push(s)}}};
 vm.createContext(context);
 const config=fs.readFileSync('src/app/lazy-modules.js','utf8').replace('export const','const');
 const code=fs.readFileSync('src/app/loader.js','utf8').replace(/^import .*;$/gm,'').replace(/^export \{.*;$/gm,'').replace(/export /g,'');
 vm.runInContext(config+'\n'+code+'\nthis.api={loadScript,loadModule,installLazyModules};',context);
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

test('project dependencies load once, before their workspace, even for simultaneous callers',async()=>{
 const x=loader(),a=x.loadModule('projects'),b=x.loadModule('projects');
 assert.equal(x.scripts.length,1);assert.equal(x.scripts[0].src,'gama-projects-core.js');
 x.scripts[0].onload();await Promise.resolve();await Promise.resolve();
 assert.equal(x.scripts.length,2);assert.equal(x.scripts[1].src,'gama-projects.js');
 x.window.GamaProjects={open:()=>true};x.scripts[1].onload();
 assert.equal(await a,await b);
});
test('dynamic vendor scripts keep their integrity and use the same download',async()=>{
 const x=loader(),options={integrity:'sha384-test',crossOrigin:'anonymous',referrerPolicy:'no-referrer'};
 const a=x.loadScript('vendor.js',options),b=x.loadScript('vendor.js',options);
 assert.equal(a,b);for(const [key,value] of Object.entries(options))assert.equal(x.scripts[0][key],value);
 x.scripts[0].onload();await a;
});

test('Stock mutations do not download an unopened workspace; opening still forwards through the shared loader',async()=>{
 const x=loader();vm.runInNewContext(fs.readFileSync('src/features/inventory/integration.js','utf8'),{window:x.window});
 await x.window.GamaInventoryV2.cargar();assert.equal(x.scripts.length,0);
 const opened=x.window.GamaOpenWarehouses('stock-entry');assert.equal(x.scripts.length,1);assert.equal(x.scripts[0].src,'gama-stock-workspace.js');
 x.window.GamaInventoryV2={abrir:entry=>'opened:'+entry};x.scripts[0].onload();assert.equal(await opened,'opened:stock-entry');
});
