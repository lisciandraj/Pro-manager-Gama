const {test,expect}=require('@playwright/test');const {boot}=require('./order-followup-fixture.cjs');
test('purchase discussion is on the right and preparing an external mail never marks the order sent',async({page})=>{
 await page.setViewportSize({width:1440,height:1000});await boot(page,{kind:'purchase'});const sidebar=await page.locator('.cocoPurchaseWorkspace .cocoFollowup').boundingBox(),main=await page.locator('.cocoPurchaseWorkspace>article').boundingBox();expect(sidebar.x).toBeGreaterThan(main.x+main.width-1);
 await page.locator('[data-coco-click="purchase-send"]').click();await expect(page.locator('#gamaMailTo')).toHaveValue('supplier@example.invalid');await expect(page.locator('#gamaMailNote')).toContainText('Pedido-OC-000001.pdf');expect(await page.evaluate(()=>window.__DB.purchase_orders[0].status)).toBe('draft');expect(await page.evaluate(()=>window.__mailCalls.length)).toBe(0);await page.locator('#gamaMailClose').click();await page.screenshot({path:'test-results/followup-purchase-desktop.png',fullPage:true});
});
test('close returns to order list with the module discussion',async({page})=>{
 await boot(page,{kind:'purchase',connected:false});await page.locator('[data-coco-click="purchase-close"]').click();await expect(page.locator('.gp14Grid')).toBeVisible();
});
test('a purchase placed by phone records its explanation without sending mail',async({page})=>{
 await boot(page,{kind:'purchase',connected:false});await page.locator('#gp14ManualSent').click();await page.locator('[name=reason]').fill('Commande confirmée par téléphone, référence FC-12');await page.getByRole('dialog').getByRole('button',{name:'Confirmer',exact:true}).click();await expect.poll(()=>page.evaluate(()=>window.__DB.purchase_orders[0].status)).toBe('sent');await expect(page.locator('.cocoPurchaseWorkspace .cocoFollowupTimeline')).toContainText('référence FC-12');expect(await page.evaluate(()=>window.__mailCalls.length)).toBe(0);
});
