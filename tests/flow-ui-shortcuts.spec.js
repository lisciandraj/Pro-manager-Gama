const {test,expect}=require('@playwright/test');
const path=require('node:path');
test.use({serviceWorkers:'block'});

async function boot(page){
 await page.route('**/*',route=>new URL(route.request().url()).hostname==='127.0.0.1'?route.continue():route.abort());
 await page.route('**/flow-ui-fixture.html',route=>route.fulfill({contentType:'text/html',body:'<!doctype html><html lang="fr"><head><style>svg{width:20px;height:20px}td{padding:10px}button,input{min-height:32px}.gamaColumnOptions[hidden]{display:none}</style></head><body><section id="flow-fixture" class="active"><div id="work"></div></section></body></html>'}));
 await page.goto('/flow-ui-fixture.html');
 await page.evaluate(async()=>{localStorage.setItem('gama_session_v1',JSON.stringify({userId:'flow-user',role:'admin'}));window.GamaI18n={language:'fr',t:s=>s};const [ui,icons,format]=await Promise.all([import('/src/ui/components.js'),import('/src/ui/icons.js'),import('/src/domain/format.js')]);window.ArcUI={...ui,...icons,esc:format.escapeHtml};});
 await page.addScriptTag({path:path.join(__dirname,'../src/ui/tables.js')});
 await page.waitForFunction(()=>!!window.GamaTable);
}

test('Ctrl+Enter validates, preserves a failed draft and prevents concurrent submissions',async({page})=>{
 await boot(page);
 await page.evaluate(()=>{
  const host=document.getElementById('work');host.innerHTML=ArcUI.form([{key:'email',id:'email',label:'Email',required:true,type:'email'}]);
  window.__saves=0;ArcUI.bindForm(host.querySelector('form'),async()=>{__saves++;await new Promise(resolve=>window.__resolve=resolve);if(__saves===1)throw Error('NETWORK_ERROR');});
 });
 const email=page.locator('#email');await email.press('Control+Enter');expect(await page.evaluate(()=>__saves)).toBe(0);
 await email.fill('qa@example.invalid');await expect(page.locator('[type=submit]')).toHaveAttribute('aria-keyshortcuts','Control+Enter Meta+Enter');
 await email.press('Control+Enter');await expect.poll(()=>page.evaluate(()=>__saves)).toBe(1);
 await email.press('Control+Enter');expect(await page.evaluate(()=>__saves)).toBe(1);
 await page.evaluate(()=>__resolve());await expect(page.locator('[role=alert]')).not.toBeEmpty();await expect(email).toHaveValue('qa@example.invalid');
 await email.press('Meta+Enter');await expect.poll(()=>page.evaluate(()=>__saves)).toBe(2);await page.evaluate(()=>__resolve());
 await expect(page.locator('form')).not.toHaveAttribute('aria-busy','true');
});

test('confirmation requires its explicit action and does not receive a submit chord',async({page})=>{
 await boot(page);await page.evaluate(()=>{window.__confirmed=false;ArcUI.confirm({title:'Confirmation',message:'Confirmer cette action ?'}).then(value=>window.__confirmed=value);});
 await expect(page.locator('dialog [type=submit]')).not.toHaveAttribute('aria-keyshortcuts',/./);
 await page.locator('dialog [data-arc-dialog-close]').press('Control+Enter');await expect(page.locator('dialog')).toBeVisible();expect(await page.evaluate(()=>__confirmed)).toBe(false);
 await page.locator('dialog [type=submit]').click();await expect.poll(()=>page.evaluate(()=>__confirmed)).toBe(true);
});

async function workList(page){
 await page.evaluate(()=>{
  window.__calls=[];
  window.__makeList=()=>{
   const work=document.getElementById('work');work.innerHTML='<input type="search" id="workSearch"><div id="workList"></div>';
   const host=document.getElementById('workList');
   window.__grid=ArcUI.dataTable(host,{contextKey:'contacts-fixture',searchInput:document.getElementById('workSearch'),columns:[{key:'name',label:'Nom'},{label:'Actions',actions:true,html:row=>ArcUI.button({label:'Ouvrir '+row.id,attrs:'data-open="'+row.id+'"'})}],source:async request=>{
    __calls.push({...request});const rows=Array.from({length:55},(_,i)=>({id:'c'+i,name:'Contact '+i})).filter(row=>row.name.includes(request.search));return {items:rows.slice(request.page*20,(request.page+1)*20),page:request.page,pageSize:20,total:rows.length};
   },actions:{'data-open':id=>{window.__record=id;__grid.dispose();work.innerHTML='<button id="back">Retour</button>';document.getElementById('back').onclick=__makeList;}}});
  };__makeList();
 });
 await expect(page.locator('#workList tbody tr')).toHaveCount(20);
}

test('return to an opted-in work list restores search, page, position and record focus without persistent business data',async({page})=>{
 await page.setViewportSize({width:1000,height:600});await boot(page);await workList(page);
 await page.locator('#workSearch').fill('Contact');await expect.poll(()=>page.evaluate(()=>__calls.at(-1).search)).toBe('Contact');
 await page.locator('[data-arc-page="1"]').click();await expect(page.locator('[data-open=c39]')).toBeVisible();
 await page.locator('[data-open=c39]').scrollIntoViewIfNeeded();const top=await page.evaluate(()=>scrollY);await page.locator('[data-open=c39]').click();
 await page.locator('#back').click();await expect(page.locator('#workSearch')).toHaveValue('Contact');await expect(page.locator('[data-open=c39]')).toBeFocused();
 expect(await page.evaluate(()=>__calls.at(-1))).toMatchObject({page:1,search:'Contact'});expect(Math.abs(await page.evaluate(()=>scrollY)-top)).toBeLessThanOrEqual(2);
 expect(await page.evaluate(()=>Object.values(localStorage).some(value=>value.includes('Contact')))).toBe(false);
 await page.evaluate(()=>{__grid.dispose();window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}}));__makeList();});
 await expect(page.locator('#workSearch')).toHaveValue('');await expect(page.locator('[data-open=c0]')).toBeVisible();
});

test('slash focuses the current table search, preserves normal typing and stays within an open dialog',async({page})=>{
 await boot(page);await workList(page);await page.locator('#workList th').first().focus();await page.keyboard.press('/');await expect(page.locator('#workSearch')).toBeFocused();
 await page.keyboard.type('/');await expect(page.locator('#workSearch')).toHaveValue('/');
 await page.evaluate(()=>ArcUI.dialog({title:'Lecture',saveLabel:'Cerrar',body:'<input id="dialog-not-search" aria-label="Note">'}));
 await page.locator('dialog [data-arc-dialog-close]').focus();await page.keyboard.press('/');await expect(page.locator('dialog [data-arc-dialog-close]')).toBeFocused();
});

test('a response from the previous account cannot render into a remembered work list',async({page})=>{
 await boot(page);await page.evaluate(()=>{
  const host=document.getElementById('work');window.__grid=ArcUI.dataTable(host,{contextKey:'account-fixture',columns:[{key:'name',label:'Nom'}],source:()=>new Promise(resolve=>window.__oldResponse=resolve)});
  window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}}));
  __oldResponse({items:[{name:'Ancien compte'}],total:1,page:0,pageSize:20});
 });
 await expect(page.locator('#work')).not.toContainText('Ancien compte');
});

test('same-account profile and sign-in events preserve a live grid, while a real account change invalidates it',async({page})=>{
 await boot(page);await workList(page);
 await page.evaluate(async()=>{window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'USER_UPDATED'}}));window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_IN'}}));await __grid.refresh({search:'Contact 1'});});
 await expect(page.locator('#workList tbody tr')).toHaveCount(11);await expect(page.locator('[data-open=c10]')).toBeVisible();
 const calls=await page.evaluate(()=>__calls.length);
 await page.evaluate(async()=>{localStorage.setItem('gama_session_v1',JSON.stringify({userId:'other-user',role:'admin'}));window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_IN'}}));await __grid.refresh({search:'Contact 2'});});
 expect(await page.evaluate(()=>__calls.length)).toBe(calls);
});
