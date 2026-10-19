const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
test('notification badges share in-flight work, pause while hidden and back off errors without reusing another session',async()=>{
 let now=0,allowed=true,calls=0;const queue=[],events={},badge={textContent:'',dataset:{},setAttribute(){}};
 class Clock extends Date{static now(){return now}}
 const c={Date:Clock,Promise,setTimeout(){},clearTimeout(){},setInterval(){},document:{hidden:false,querySelectorAll:()=>[badge],getElementById:()=>null,addEventListener(){}},ArcUI:{esc:x=>x},GamaCloudReady:Promise.resolve(),GamaCloud:{db:async()=>({})},ArcData:{rawRpc:async()=>{calls++;return new Promise(resolve=>queue.push(resolve))}},gamaAccessAllowed:()=>allowed,addEventListener:(n,fn)=>events[n]=fn,GamaCurrency:{format:x=>x}};c.window=c;
 vm.runInNewContext(fs.readFileSync('src/features/notifications/workspace.js','utf8'),c);const refresh=()=>c.GamaOperations.refreshBadge();
 const first=refresh(),duplicate=refresh();await new Promise(setImmediate);assert.equal(calls,1);queue.shift()({data:{active_count:4}});await Promise.all([first,duplicate]);assert.equal(badge.textContent,'4');
 await refresh();assert.equal(calls,1);now=61000;c.document.hidden=true;await refresh();assert.equal(calls,1);c.document.hidden=false;
 const failed=refresh();await new Promise(setImmediate);queue.shift()({error:Error('NETWORK_ERROR')});await failed;assert.equal(badge.textContent,'?');now+=60000;await refresh();assert.equal(calls,2);
 now+=61000;const stale=refresh();await new Promise(setImmediate);events['gama:auth-change']({detail:{event:'SIGNED_OUT'}});allowed=false;queue.shift()({data:{active_count:99}});await stale;assert.notEqual(badge.textContent,'99');
});
