const {test,expect}=require('@playwright/test');const {boot,delivery}=require('./order-followup-fixture.cjs');
test('sales history is a right-hand discussion with author portraits and each dossier stage',async({page})=>{
 await page.setViewportSize({width:1440,height:1000});await boot(page);await expect(page.locator('.cocoFollowupTimeline')).toContainText('Alice');await expect(page.locator('.cocoFollowupTimeline')).toContainText('Commande créée');await expect(page.locator('.cocoFollowupAvatar img')).toHaveCount(1);await expect(page.locator('[data-stage] option')).toHaveCount(7);
 const aside=await page.locator('.cocoFollowup').boundingBox(),main=await page.locator('.gsOrderMain').boundingBox();expect(aside.x).toBeGreaterThan(main.x+main.width-1);await expect(page.locator('.cocoFollowupBubble')).toHaveCount(1);await page.screenshot({path:'test-results/followup-sales-desktop.png',fullPage:true});
});
test('notes remain escaped, attributed and shared without a mailbox connection',async({page})=>{
 await boot(page,{connected:false});await page.locator('[data-compose-note]').click();await page.locator('.cocoFollowupForm textarea').fill('Appel effectué <img src=x onerror=alert(1)>');await page.locator('.cocoFollowupForm button[type=submit]').click();await expect(page.locator('.cocoFollowupTimeline')).toContainText('Appel effectué <img');expect(await page.evaluate(()=>window.__mailCalls.length)).toBe(0);await expect(page.locator('[data-connect],[data-mailbox],[data-compose-mail]')).toHaveCount(0);
});
test('ChatGPT actions require a checked proposal and an explicit ERP approval',async({page})=>{
 await boot(page,{proposal:true});await page.locator('[data-review-proposal]').click();const d=page.locator('.cocoProposalDialog');await expect(d.locator('[type=submit]')).toBeDisabled();expect(await page.evaluate(()=>window.__decisions.length)).toBe(0);await d.locator('[data-check]').click();await expect(d.locator('[data-preview]')).toContainText('Costa Azul');await expect(d.locator('[type=submit]')).toBeEnabled();await d.locator('[type=submit]').click();await expect(d).toHaveCount(0);expect(await page.evaluate(()=>window.__decisions.length)).toBe(1);await expect(page.locator('[data-open-proposal]')).toBeVisible();
});
test('editing a reviewed proposal invalidates approval, and refusing never creates a draft',async({page})=>{
 await boot(page,{proposal:true});await page.locator('[data-review-proposal]').click();const d=page.locator('.cocoProposalDialog');await d.locator('[data-check]').click();await expect(d.locator('[type=submit]')).toBeEnabled();await d.locator('[type=number]').fill('5');await expect(d.locator('[type=submit]')).toBeDisabled();await d.locator('[data-close]').click();await page.locator('[data-reject-proposal]').click();await expect(page.locator('.cocoProposalState')).toHaveText('Refusé');expect(await page.evaluate(()=>window.__decisions.length)).toBe(0);
});
test('TMS has a right-hand dossier discussion and a delivery selector',async({page})=>{
 await page.setViewportSize({width:1440,height:1000});await boot(page,{kind:'tms'});await page.locator('.cocoTmsDossierSelect select').selectOption(delivery);await expect(page.locator('.cocoFollowupParty')).toContainText('TMS-001');const sidebar=await page.locator('.cocoFollowup').boundingBox(),main=await page.locator('.cocoDossierMain').boundingBox();expect(sidebar.x).toBeGreaterThan(main.x+main.width-1);await page.screenshot({path:'test-results/followup-tms-desktop.png',fullPage:true});
});
test('phone discussion opens as a right-hand panel without page overflow',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await expect(page.locator('.cocoFollowup')).not.toHaveAttribute('open');await page.locator('.cocoFollowup>summary').click();await expect(page.locator('.cocoFollowupTimeline')).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);const box=await page.locator('.cocoFollowup').boundingBox();expect(Math.round(box.x+box.width)).toBe(380);await page.screenshot({path:'test-results/followup-mobile.png',fullPage:true});
});
test('logout removes notes and pending proposal editors',async({page})=>{
 await boot(page,{proposal:true});await page.locator('[data-review-proposal]').click();await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));await expect(page.locator('.cocoFollowup')).toHaveCount(0);await expect(page.locator('.cocoProposalDialog')).toHaveCount(0);
});
