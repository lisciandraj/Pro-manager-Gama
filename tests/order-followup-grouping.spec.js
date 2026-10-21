const {test,expect}=require('@playwright/test');
const {boot,order}=require('./order-followup-fixture.cjs');

for(const kind of ['sales','purchase','tms'])for(const scope of ['module','dossier'])test(`${kind} ${scope} groups references, preserves notes and opens related modules`,async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page,{kind});
 await page.evaluate(async({kind,scope,order})=>{
  const time='2026-10-17T08:22:00.123456Z',links=[{module:'warehouses',action:'module'},{module:'tms',action:'preparation',id:order}];
  window.__history=Array.from({length:8},(_,i)=>({id:'reservation-'+i,step:4,action:'receipt_auto_reserved',actor_id:'alice',actor_name:'Alice',at:time,total:8,references:[{kind:'product',id:'p'+(i===7?0:i),reference:'REF-'+(i===7?0:i),name:i===0?'Papier <A4>':'Produit '+i,quantity:i===7?2:1,unit:'Unité'}],links}));
  window.__entries=[{id:'note1',type:'note',actor_id:'alice',actor_name:'Alice',body:'Première note',created_at:time},{id:'note2',type:'note',actor_id:'alice',actor_name:'Alice',body:'Deuxième note',created_at:time}];
  window.__relatedOpened=[];window.GamaPreparation.open=async id=>{window.__relatedOpened.push(id)};
  const old=document.querySelector(kind==='purchase'?'.cocoPurchaseWorkspace .cocoFollowup':'.cocoFollowup'),host=old.parentElement;
  await window.CocoFollowup.mount(host,{kind,order_id:scope==='module'?null:kind==='sales'?order:kind==='purchase'?window.__DB.purchase_orders[0].id:window.__DB.tms_deliveries[0].id});
 },{kind,scope,order});
 const panel=page.locator('.cocoFollowup:visible');await panel.locator(':scope>summary').click();
 await expect(panel.locator('.cocoFollowupTitle')).toHaveText(scope==='module'?'Historique du module':'Historique du dossier');
 const action=panel.locator('.cocoFollowupEvent[data-type=action]');await expect(action).toHaveCount(1);await expect(action).toContainText('8 actions');await expect(action).toContainText('Références (7)');
 await expect(action.locator('.cocoFollowupReferences>ul>li')).toHaveCount(5);await expect(action.locator('.cocoFollowupReferences>ul>li').first()).toContainText('Papier <A4>');await expect(action.locator('.cocoFollowupReferences>ul>li').first()).toContainText('Quantité: 3');await expect(action.locator('.cocoFollowupReferences img')).toHaveCount(0);
 await action.locator('.cocoFollowupReferences summary').click();await expect(action.locator('.cocoFollowupReferences details li')).toHaveCount(2);await expect(action).toContainText('REF-6');await expect(panel.locator('.cocoFollowupEvent[data-type=note]')).toHaveCount(2);
 await expect(action.locator('[data-followup-link]')).toHaveCount(2);await action.getByRole('button',{name:'Préparation',exact:true}).click();expect(await page.evaluate(()=>window.__relatedOpened)).toEqual([order]);
 await panel.locator('[data-filter=actions]').click();await expect(panel.locator('.cocoFollowupEvent')).toHaveCount(1);await panel.locator('[data-refresh]').click();await expect(action).toHaveAttribute('data-action-count','8');await expect(action).toContainText('Quantité: 3');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);await page.screenshot({path:`test-results/history-grouping-${kind}-${scope}-mobile.png`});
 await page.setViewportSize({width:1440,height:1000});await expect(action).toBeVisible();await expect(action).toContainText('Références (7)');
});

test('separate authors, dossiers, timestamps and proposal decisions retain their own bubbles',async({page})=>{
 await boot(page);await page.evaluate(()=>{
  window.__history=[];const a={type:'action',subject:'reserve',actor_id:'alice',actor_name:'Alice',created_at:'2026-10-17T08:22:00.123456Z',kind:'sales',order_id:'order-a'};
  window.__entries=[{...a,id:'a'},{...a,id:'b',actor_id:'bob',actor_name:'Bob'},{...a,id:'c',created_at:'2026-10-17T08:22:00.123457Z'},{...a,id:'d',order_id:'order-b'},{...a,id:'e',subject:'payment'},{...a,id:'f',proposal_id:'proposal-1'}];
 });await page.locator('[data-refresh]').click();await expect(page.locator('.cocoFollowupEvent')).toHaveCount(6);
});
