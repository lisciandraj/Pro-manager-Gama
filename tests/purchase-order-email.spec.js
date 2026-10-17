const {test,expect}=require('@playwright/test');
const {boot}=require('./order-followup-fixture.cjs');
test('purchase stays draft until direct mail is accepted and attaches its PDF',async({page})=>{
 await page.setViewportSize({width:1440,height:1000});await boot(page,{kind:'purchase'});
 const sidebar=await page.locator('.cocoFollowup').boundingBox(),main=await page.locator('.cocoPurchaseWorkspace>article').boundingBox();expect(sidebar.x+sidebar.width).toBeLessThan(main.x+1);
 await page.locator('[data-coco-click="purchase-send"]').click();await expect(page.locator('.cocoFollowupForm [name=to]')).toHaveValue('supplier@example.invalid');await expect(page.locator('[data-attachments]')).toContainText('Pedido-OC-000001.pdf');
 expect(await page.evaluate(()=>window.__DB.purchase_orders[0].status)).toBe('draft');expect(await page.evaluate(()=>window.__mailCalls.filter(x=>x.action==='send').length)).toBe(0);
 await page.locator('.cocoFollowupForm button[type=submit]').click();await expect.poll(()=>page.evaluate(()=>window.__DB.purchase_orders[0].status)).toBe('sent');
 const calls=await page.evaluate(()=>window.__mailCalls.filter(x=>x.action==='send'));expect(calls).toHaveLength(1);expect(calls[0].subject).toContain('OC-000001');expect(calls[0].body).toContain('Papier A4');expect(calls[0].attachments[0].type).toBe('application/pdf');await page.evaluate(()=>window.scrollTo(0,0));await page.screenshot({path:'test-results/followup-purchase-desktop.png',fullPage:true});
});
test('missing mailbox never marks purchase as sent; close returns to order list',async({page})=>{
 await boot(page,{kind:'purchase',connected:false});await page.locator('[data-coco-click="purchase-send"]').click();await expect(page.locator('.cocoFollowupConnect')).toBeVisible();expect(await page.evaluate(()=>window.__DB.purchase_orders[0].status)).toBe('draft');
 await page.locator('.cocoFollowupConnect [data-close]').click();await page.locator('[data-coco-click="purchase-close"]').click();await expect(page.locator('.gp14Grid')).toBeVisible();
});
test('a purchase placed by phone records its explanation without sending mail',async({page})=>{
 await boot(page,{kind:'purchase',connected:false});await page.locator('#gp14ManualSent').click();
 await page.locator('[name=reason]').fill('Commande confirmée par téléphone, référence FC-12');
 await page.getByRole('dialog').getByRole('button',{name:'Confirmer',exact:true}).click();
 await expect.poll(()=>page.evaluate(()=>window.__DB.purchase_orders[0].status)).toBe('sent');
 await expect(page.locator('.cocoFollowupTimeline')).toContainText('référence FC-12');
 expect(await page.evaluate(()=>window.__mailCalls.filter(x=>x.action==='send').length)).toBe(0);
});
