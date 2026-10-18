const {test,expect}=require('@playwright/test');const {boot,delivery}=require('./order-followup-fixture.cjs');
for(const kind of ['sales','quotes'])test(`${kind} history stays on the right with small avatars after TMS styles are preloaded`,async({page})=>{
 await page.setViewportSize({width:1440,height:1000});await boot(page,{kind,proposal:true,preloadFollowup:true});
 const panel=page.locator('.cocoFollowup'),main=page.locator(kind==='sales'?'.gsOrderMain':'.cocoDossierMain');
 await expect(panel.locator('.cocoFollowupAvatar.is-agent img')).toBeVisible();
 const side=await panel.boundingBox(),content=await main.boundingBox();
 expect(side.x).toBeGreaterThanOrEqual(content.x+content.width-1);expect(side.width).toBeLessThanOrEqual(390);
 for(const img of await panel.locator('.cocoFollowupAvatar img').all()){
  const box=await img.boundingBox();expect(box.width).toBeLessThanOrEqual(30);expect(box.height).toBeLessThanOrEqual(30);
 }
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.screenshot({path:`test-results/followup-preload-${kind}-desktop.png`,fullPage:true});
});
test('a preloaded history stylesheet still opens a bounded phone drawer',async({page})=>{
 await page.setViewportSize({width:375,height:812});await boot(page,{kind:'quotes',proposal:true,preloadFollowup:true});
 const panel=page.locator('.cocoFollowup');await panel.locator(':scope>summary').click();
 await expect(panel.locator('.cocoFollowupTimeline')).toBeVisible();await expect(panel).toHaveClass(/is-mobile-open/);
 const box=await panel.boundingBox();expect(box.x).toBeGreaterThanOrEqual(0);expect(box.x+box.width).toBeLessThanOrEqual(375);expect(box.height).toBeLessThanOrEqual(812);
 for(const img of await panel.locator('.cocoFollowupAvatar img').all()){
  const avatar=await img.boundingBox();expect(avatar.width).toBeLessThanOrEqual(24);expect(avatar.height).toBeLessThanOrEqual(24);
 }
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.screenshot({path:'test-results/followup-preload-phone.png'});
});
test('sales history is a right-hand discussion with author portraits and each dossier stage',async({page})=>{
 await page.setViewportSize({width:1440,height:1000});await boot(page);await expect(page.locator('.cocoFollowupTimeline')).toContainText('Alice');await expect(page.locator('.cocoFollowupTimeline')).toContainText('Commande créée');await expect(page.locator('.cocoFollowupAvatar img')).toHaveCount(1);await expect(page.locator('[data-stage] option')).toHaveCount(7);
 const aside=await page.locator('.cocoFollowup').boundingBox(),main=await page.locator('.gsOrderMain').boundingBox();expect(aside.x).toBeGreaterThan(main.x+main.width-1);await expect(page.locator('.cocoFollowupBubble')).toHaveCount(1);await page.screenshot({path:'test-results/followup-sales-desktop.png',fullPage:true});
});
test('notes remain escaped, attributed and shared without a mailbox connection',async({page})=>{
 await boot(page,{connected:false});await page.locator('[data-compose-note]').click();await page.locator('.cocoFollowupForm textarea').fill('Appel effectué <img src=x onerror=alert(1)>');await page.locator('.cocoFollowupForm button[type=submit]').click();await expect(page.locator('.cocoFollowupTimeline')).toContainText('Appel effectué <img');expect(await page.evaluate(()=>window.__mailCalls.length)).toBe(0);await expect(page.locator('[data-connect],[data-mailbox],[data-compose-mail]')).toHaveCount(0);
});
for(const kind of ['sales','purchase','tms'])test(`${kind} history shows newest actions and notes first after filtering and refreshing`,async({page})=>{
 await boot(page,{kind});
 await page.evaluate(()=>{window.__entries=[
  {id:'middle',type:'note',actor_name:'Alice',body:'Middle note',created_at:'2026-10-18T12:00:00Z'},
  {id:'newest',type:'action',subject:'order_updated',actor_name:'Alice',body:'["status"]',created_at:'2026-10-19T12:00:00Z'},
  {id:'older',type:'note',actor_name:'Alice',body:'Older note',created_at:'2026-10-17T12:00:00Z'}
 ]});
 const panel=page.locator(kind==='purchase'?'.cocoPurchaseWorkspace .cocoFollowup':'.cocoFollowup');
 await panel.locator('[data-refresh]').click();
 const times=()=>panel.locator('.cocoFollowupTimeline time').evaluateAll(nodes=>nodes.map(n=>n.dateTime));
 await expect.poll(times).toEqual(['2026-10-19T12:00:00Z','2026-10-18T12:00:00Z','2026-10-17T12:00:00Z','2026-10-16T12:00:00Z']);
 await panel.locator('[data-filter=notes]').click();await expect.poll(times).toEqual(['2026-10-18T12:00:00Z','2026-10-17T12:00:00Z']);
 await panel.locator('[data-filter=actions]').click();await expect.poll(times).toEqual(['2026-10-19T12:00:00Z','2026-10-16T12:00:00Z']);
 await panel.locator('[data-filter=all]').click();await panel.locator('[data-refresh]').click();await expect(panel.locator('.cocoFollowupEvent')).toHaveCount(4);await expect.poll(times).toEqual(['2026-10-19T12:00:00Z','2026-10-18T12:00:00Z','2026-10-17T12:00:00Z','2026-10-16T12:00:00Z']);
});
test('purchase module history explains an automatic low-stock draft and opens the actual order',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page,{kind:'purchase'});
 await page.evaluate(()=>window.__entries.push({id:'automatic',kind:'purchase',order_id:null,type:'action',subject:'automatic_minmax_purchase',actor_id:'alice',actor_name:'Alice',body:'OC-000001 · Papelera Central',purchase_order_id:window.__DB.purchase_orders[0].id,replenishment:[{name:'Papier <A4>',reference:'PAP-01',quantity:35,on_hand:5,min_stock:10,max_stock:40}],created_at:'2026-10-17T12:00:00Z'}));
 await page.locator('[data-coco-click="purchase-close"]').click();const panel=page.locator('.cocoFollowup:visible');await panel.locator('summary').first().click();await panel.locator('[data-refresh]').click();
 const bubble=panel.locator('.cocoFollowupEvent').filter({hasText:'Brouillon d’achat automatique'});await expect(bubble).toContainText('OC-000001 · Papelera Central');await expect(bubble).toContainText('Stock inférieur au minimum');await expect(bubble).toContainText('Papier <A4> (PAP-01) · Quantité: 35 · Stock: 5 · Minimum: 10 · Maximum: 40');await expect(bubble.locator('.cocoFollowupWho strong')).toHaveText('Alice');await expect(bubble.locator('.cocoFollowupAvatar img')).toHaveCount(1);
 await panel.locator('[data-filter=actions]').click();await expect(bubble).toBeVisible();await bubble.locator('[data-open-purchase]').scrollIntoViewIfNeeded();await expect(bubble.locator('[data-open-purchase]')).toBeInViewport();expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);await page.screenshot({path:'test-results/followup-automatic-purchase-mobile.png'});
 await bubble.locator('[data-open-purchase]').click();await expect(page.locator('.cocoPurchaseWorkspace .cocoFollowupTitle')).toHaveText('Historique du dossier');await expect(page.locator('.gp14DetailHead')).toContainText('OC-000001');expect(await page.evaluate(()=>window.__DB.purchase_orders[0].status)).toBe('draft');
});
test('Agent Coco actions require a checked proposal and an explicit ERP approval',async({page})=>{
 await boot(page,{proposal:true});await page.locator('[data-review-proposal]').click();const d=page.locator('.cocoProposalDialog');await expect(d.locator('[type=submit]')).toBeDisabled();expect(await page.evaluate(()=>window.__decisions.length)).toBe(0);await d.locator('[data-check]').click();await expect(d.locator('[data-preview]')).toContainText('Costa Azul');await expect(d.locator('[type=submit]')).toBeEnabled();await d.locator('[type=submit]').click();await expect(d).toHaveCount(0);expect(await page.evaluate(()=>window.__decisions.length)).toBe(1);await expect(page.locator('[data-open-proposal]')).toBeVisible();
});
test('editing a reviewed proposal invalidates approval, and refusing never creates a draft',async({page})=>{
 await boot(page,{proposal:true});await page.locator('[data-review-proposal]').click();const d=page.locator('.cocoProposalDialog');await d.locator('[data-check]').click();await expect(d.locator('[type=submit]')).toBeEnabled();await d.locator('[type=number]').fill('5');await expect(d.locator('[type=submit]')).toBeDisabled();await d.locator('[data-close]').click();await page.locator('[data-reject-proposal]').click();await expect(page.locator('.cocoProposalState')).toHaveText('Refusé');expect(await page.evaluate(()=>window.__decisions.length)).toBe(0);
});
test('TMS has a right-hand dossier discussion and a delivery selector',async({page})=>{
 await page.setViewportSize({width:1440,height:1000});await boot(page,{kind:'tms'});await expect(page.locator('.cocoFollowupTitle')).toHaveText('Historique du module');await page.locator('.cocoTmsDossierSelect select').selectOption(delivery);await expect(page.locator('.cocoFollowupTitle')).toHaveText('Historique du dossier');await expect(page.locator('.cocoFollowupParty')).toContainText('TMS-001');const sidebar=await page.locator('.cocoFollowup').boundingBox(),main=await page.locator('.cocoDossierMain').boundingBox();expect(sidebar.x).toBeGreaterThan(main.x+main.width-1);await page.screenshot({path:'test-results/followup-tms-desktop.png',fullPage:true});
});
test('phone discussion opens as a right-hand panel without page overflow',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await expect(page.locator('.cocoFollowup')).not.toHaveAttribute('open');await page.locator('.cocoFollowup>summary').click();await expect(page.locator('.cocoFollowupTimeline')).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);const box=await page.locator('.cocoFollowup').boundingBox();expect(Math.round(box.x+box.width)).toBe(380);await page.screenshot({path:'test-results/followup-mobile.png',fullPage:true});
});
for(const language of ['fr','es','en'])test(`Agent Coco labels include existing analysis authors and module inbox in ${language}`,async({page})=>{
 await boot(page,{proposal:true,language});await expect(page.locator('.cocoFollowupTitle')).toHaveText(({fr:'Historique du dossier',es:'Historial del expediente',en:'Dossier history'})[language]);await page.evaluate(()=>window.CocoFollowup.mount(document.querySelector('.gsOrderAside'),{kind:'sales',order_id:null}));await expect(page.locator('.cocoFollowupTitle')).toHaveText(({fr:'Historique du module',es:'Historial del módulo',en:'Module history'})[language]);
 await expect(page.locator('.cocoFollowupParty')).toContainText('Agent Coco');await expect(page.locator('.cocoFollowupWho strong').filter({hasText:'Agent Coco'})).toHaveCount(1);await expect(page.locator('.cocoFollowupBridge>summary')).toContainText('Agent Coco');await expect(page.locator('.cocoFollowup')).not.toContainText(/chat\s*gpt/i);
 expect(await page.evaluate(()=>window.__entries[0].actor_name)).toBe('ChatGPT');expect(await page.evaluate(()=>window.__mailCalls.length)).toBe(0);
});
test('phone long analyses use one scroll area and keep the close control and proposal actions reachable',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page,{proposal:true,summary:'Demande Costa Azul : vérifier les produits, les quantités, le conditionnement et la livraison avant de créer le devis. '.repeat(18)});
 const panel=page.locator('.cocoFollowup'),header=panel.locator(':scope>summary'),body=panel.locator('.cocoFollowupBody');await header.click();await expect(header).toHaveAttribute('aria-label','Fermer l’historique');
 const before=await header.boundingBox(),box=await panel.boundingBox();expect(box.y).toBeGreaterThanOrEqual(0);expect(box.y+box.height).toBeLessThanOrEqual(844);expect(box.height).toBeGreaterThan(750);
 expect(await body.evaluate(e=>e.scrollHeight>e.clientHeight)).toBe(true);expect(await panel.locator('.cocoFollowupTimeline').evaluate(e=>getComputedStyle(e).overflowY)).toBe('visible');expect(await panel.locator('.cocoFollowupText').evaluate(e=>getComputedStyle(e).overflowY)).toBe('visible');
 await panel.locator('[data-review-proposal]').scrollIntoViewIfNeeded();await expect(panel.locator('[data-review-proposal]')).toBeInViewport();expect(await body.evaluate(e=>e.scrollTop)).toBeGreaterThan(0);expect((await header.boundingBox()).y).toBe(before.y);await expect(header).toBeInViewport();await page.screenshot({path:'test-results/followup-mobile-long-analysis.png'});
 await header.click();await expect(panel).not.toHaveAttribute('open');await header.click();await header.press('Escape');await expect(panel).not.toHaveAttribute('open');await expect(header).toBeFocused();
});
test('small phone review keeps its header and approval controls visible while content scrolls',async({page})=>{
 await page.setViewportSize({width:320,height:568});await boot(page,{proposal:true,summary:'Le client demande trois paquets de papier. Confirmer la référence produit et l’adresse de livraison. '.repeat(16)});
 await page.locator('.cocoFollowup>summary').click();await page.locator('[data-review-proposal]').click();const d=page.locator('.cocoProposalDialog');
 await expect(d.locator('h3')).toBeInViewport();await expect(d.locator('[data-dismiss]')).toBeInViewport();await expect(d.locator('[data-check]')).toBeInViewport();await expect(d.locator('[type=submit]')).toBeInViewport();await expect(d.locator('[data-close]')).toBeInViewport();
 const layout=await page.evaluate(()=>({width:document.documentElement.scrollWidth,overflow:[...document.body.querySelectorAll('*')].filter(e=>{const r=e.getBoundingClientRect();if(r.right<=innerWidth+1||!r.width||!r.height)return false;for(let p=e.parentElement;p&&p!==document.body;p=p.parentElement)if(/auto|hidden|clip|scroll/.test(getComputedStyle(p).overflowX))return false;return true}).map(e=>({tag:e.tagName,id:e.id,css:e.className,right:e.getBoundingClientRect().right})).slice(0,12)}));expect(layout.width,JSON.stringify(layout.overflow)).toBeLessThanOrEqual(320);
 const content=d.locator('.cocoProposalContent');expect(await content.evaluate(e=>e.scrollHeight>e.clientHeight)).toBe(true);await d.locator('[type=number]').fill('5');await d.locator('[data-check]').click();await expect(d.locator('[type=submit]')).toBeEnabled();await expect(d.locator('[data-check]')).toBeInViewport();await expect(d.locator('[type=submit]')).toBeInViewport();expect(await page.evaluate(()=>window.__decisions.length)).toBe(0);await page.screenshot({path:'test-results/followup-mobile-review.png'});
 await page.setViewportSize({width:320,height:360});await expect(d.locator('[data-dismiss]')).toBeInViewport();await expect(d.locator('[data-close]')).toBeInViewport();await d.locator('[data-dismiss]').click();await expect(d).toHaveCount(0);
});
test('phone note editor stays usable after viewport resizing without losing an unsaved note',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);const header=page.locator('.cocoFollowup>summary');await header.click();await page.locator('[data-compose-note]').click();const input=page.locator('.cocoFollowupForm textarea');await input.fill('Adresse confirmée par téléphone');
 await page.setViewportSize({width:390,height:400});await page.locator('.cocoFollowupForm [type=submit]').scrollIntoViewIfNeeded();await expect(page.locator('.cocoFollowupForm [type=submit]')).toBeInViewport();await expect(header).toBeInViewport();await header.click();await header.click();await expect(input).toHaveValue('Adresse confirmée par téléphone');await page.locator('.cocoFollowupForm [type=submit]').click();await expect(page.locator('.cocoFollowupTimeline')).toContainText('Adresse confirmée par téléphone');expect(await page.evaluate(()=>window.__notes.length)).toBe(1);
});
test('logout removes notes and pending proposal editors',async({page})=>{
 await boot(page,{proposal:true});await page.locator('[data-review-proposal]').click();await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));await expect(page.locator('.cocoFollowup')).toHaveCount(0);await expect(page.locator('.cocoProposalDialog')).toHaveCount(0);
});
