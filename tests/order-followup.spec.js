const {test,expect}=require('@playwright/test');
const {boot}=require('./order-followup-fixture.cjs');
test('sales document shows status and named activity stream on the left',async({page})=>{
 await page.setViewportSize({width:1440,height:1000});await boot(page);
 await expect(page.locator('.cocoFollowupTimeline')).toContainText('Alice');await expect(page.locator('.cocoFollowupTimeline')).toContainText('Commande créée');
 const aside=await page.locator('.cocoFollowup').boundingBox(),main=await page.locator('.gsOrderMain').boundingBox();expect(aside.x+aside.width).toBeLessThan(main.x+1);
 await page.screenshot({path:'test-results/followup-sales-desktop.png',fullPage:true});
});
test('notes are escaped and attributed; replies can be refreshed and answered',async({page})=>{
 await boot(page);await page.locator('[data-compose-note]').click();await page.locator('.cocoFollowupForm textarea').fill('Pedido confirmado\nAppel effectué <img src=x onerror=alert(1)>');await page.locator('.cocoFollowupForm button[type=submit]').click();
 await expect(page.locator('.cocoFollowupTimeline')).toContainText('Appel effectué <img');await expect(page.locator('.cocoFollowupTimeline img')).toHaveCount(0);await expect(page.locator('.cocoFollowupText p').last()).toContainText('Pedido confirmado');
 await page.evaluate(()=>window.__incoming=true);await page.locator('[data-refresh]').click();await expect(page.locator('.cocoFollowupTimeline')).toContainText('Livraison confirmée');
 await page.locator('[data-reply="in-1"]').click();await expect(page.locator('.cocoFollowupForm [name=to]')).toHaveValue('client@example.invalid');await page.locator('.cocoFollowupForm textarea').fill('Merci pour votre réponse.');await page.locator('.cocoFollowupForm button[type=submit]').click();
 await expect(page.locator('.cocoFollowupTimeline')).toContainText('Merci pour votre réponse.');const sends=await page.evaluate(()=>window.__mailCalls.filter(c=>c.action==='send'));expect(sends).toHaveLength(1);expect(sends[0].reply_id).toBe('in-1');
});
test('ambiguous send cannot be retried accidentally',async({page})=>{
 await boot(page);await page.evaluate(()=>window.__sendFailure=true);await page.locator('[data-compose-mail]').click();await page.locator('.cocoFollowupForm textarea').fill('Bonjour');await page.locator('.cocoFollowupForm button[type=submit]').click();
 await expect(page.locator('.cocoFollowupFormError')).toContainText('Envoi non confirmé');await expect(page.locator('.cocoFollowupForm button[type=submit]')).toBeDisabled();expect(await page.evaluate(()=>window.__mailCalls.filter(c=>c.action==='send').length)).toBe(1);
});
test('mail setup never fakes a connected account',async({page})=>{
 await boot(page,{connected:false});await page.locator('[data-compose-mail]').click();await expect(page.locator('.cocoFollowupConnect')).toContainText('configurée par l’administrateur');await expect(page.locator('[data-connect=google]')).toBeDisabled();await expect(page.locator('.cocoFollowupForm')).toHaveCount(0);
});
test('phone follow-up collapses with readable status and no page overflow',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await expect(page.locator('.cocoFollowup')).not.toHaveAttribute('open');await page.locator('.cocoFollowup>summary').click();await expect(page.locator('.cocoFollowupTimeline')).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);await page.screenshot({path:'test-results/followup-mobile.png',fullPage:true});
});
test('logout removes shared mail content and drafts',async({page})=>{
 await boot(page);await page.locator('[data-compose-note]').click();await page.locator('.cocoFollowupForm textarea').fill('draft');await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));await expect(page.locator('.cocoFollowup')).toHaveCount(0);
});
