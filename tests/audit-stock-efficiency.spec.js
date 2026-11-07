const {test,expect}=require('@playwright/test'),fs=require('node:fs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
const base={warehouses:[{id:'w1',code:'PRINCIPAL',name:'Principal',active:true}],warehouse_locations:[{id:'loc1',warehouse_id:'w1',code:'A01',active:true}],products:[{id:'p1',name:'Cemento',reference:'CEM',stock:100,purchase_price:2,active:true},{id:'p2',name:'Arena',reference:'ARE',stock:20,purchase_price:4,active:true},{id:'p3',name:'Grava',reference:'GRA',stock:5,purchase_price:3,active:true}],stock_quants:[{id:'q1',product_id:'p1',location_id:'loc1',quantity:100,reserved_quantity:0},{id:'q2',product_id:'p2',location_id:'loc1',quantity:20,reserved_quantity:0}],suppliers:[{id:'s1',name:'Proveedor A',active:true}],profiles:[],inventory_counts:[{id:'c1',warehouse_id:'w1',reference:'INV-CONTINUO',status:'in_progress',blind:false}],inventory_count_lines:[{id:'cl1',count_id:'c1',product_id:'p1',location_id:'loc1',expected_quantity:100,counted_quantity:null},{id:'cl2',count_id:'c1',product_id:'p2',location_id:'loc1',expected_quantity:20,counted_quantity:null},{id:'cl3',count_id:'c1',product_id:'p3',location_id:'loc1',expected_quantity:5,counted_quantity:4}],reorder_rules:[],purchase_orders:[{id:'po1',supplier_id:'s1',order_number:'OC-1',status:'sent',order_date:'2026-11-02',total:6},{id:'po2',supplier_id:'s1',order_number:'OC-2',status:'sent',order_date:'2026-11-01',total:12}],purchase_order_lines:[{id:'pol1',purchase_order_id:'po1',product_id:'p1',quantity:3,received_quantity:0,unit_cost:2},{id:'pol2',purchase_order_id:'po2',product_id:'p2',quantity:3,received_quantity:0,unit_cost:4}],stock_movements:[],warehouse_shelves:[]};
async function boot(page,seed=base){
 await page.addInitScript(db=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'}));window.__DB=db},seed);
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaOpenWarehouses&&window.gamaAccessAllowed?.('warehouses'));
}
test('Enter saves observed quantities then focuses the next uncounted line without adjusting stock',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaInventoryV2.openCount('c1'));
 await page.selectOption('#ivcView','pending');await expect(page.locator('#ivcLineas [data-ivc-linea]')).toHaveCount(2);
 await page.locator('[data-ivc-linea=cl1]').fill('97');await page.locator('[data-ivc-linea=cl1]').press('Enter');
 await expect(page.locator('[data-ivc-linea=cl2]')).toBeFocused();await expect(page.locator('#ivcLineas [data-ivc-linea]')).toHaveCount(1);
 await page.locator('[data-ivc-linea=cl2]').fill('20');await page.locator('[data-ivc-linea=cl2]').press('Enter');
 await expect(page.locator('#ivcValidar')).toBeFocused();await expect(page.locator('#ivcLineas')).toContainText('No hay líneas');
 await page.selectOption('#ivcView','differences');await expect(page.locator('#ivcLineas [data-ivc-linea]')).toHaveCount(2);
 await expect(page.locator('#ivcLineas')).toContainText('Cemento');await expect(page.locator('#ivcLineas')).toContainText('Grava');
 expect(await page.evaluate(()=>__DB.stock_quants.map(q=>q.quantity))).toEqual([100,20]);expect(await page.evaluate(()=>__DB.stock_movements)).toHaveLength(0);
});
test('a blind incomplete count hides the differences filter and keeps a failed quantity for retry',async({page})=>{
 const db=structuredClone(base);db.inventory_counts[0].blind=true;await boot(page,db);await page.evaluate(()=>GamaInventoryV2.openCount('c1'));
 await expect(page.locator('#ivcView option[value=differences]')).toHaveCount(0);
 await page.evaluate(()=>{const update=GamaCloud.update;GamaCloud.update=async(t,id,row)=>t==='inventory_count_lines'?{error:{message:'network request failed'}}:update(t,id,row)});
 await page.locator('[data-ivc-linea=cl1]').fill('96');await page.locator('[data-ivc-linea=cl1]').press('Enter');
 await expect(page.locator('[data-ivc-linea=cl1]')).toBeEnabled();await expect(page.locator('[data-ivc-linea=cl1]')).toBeFocused();await expect(page.locator('[data-ivc-linea=cl1]')).toHaveValue('96');
 expect(await page.evaluate(()=>__DB.inventory_count_lines[0].counted_quantity)).toBeNull();
 await expect(page.locator('#ivcLineas')).not.toContainText('100');
});
test('receive and next retries the same command, prevents duplicate submission and only opens the next order',async({page})=>{
 await boot(page);await page.evaluate(()=>gamaShowPurchases());await page.evaluate(()=>gamaOpenPurchaseV14('po1'));
 await page.evaluate(()=>{const db=GamaCloud.db;window.__receiptAttempts=[];GamaCloud.db=async()=>{const client=await db(),rpc=client.rpc;client.rpc=async(name,args)=>{if(name!=='gama_receive_purchase_once')return rpc(name,args);__receiptAttempts.push(args.p_data);if(__receiptAttempts.length===1)return {error:{message:'network request failed'}};await new Promise(resolve=>window.__releaseReceipt=resolve);return rpc(name,args)};return client}});
 await page.click('#gp14ReceiveNext');await expect(page.locator('#gp14DetailMsg')).toContainText('network request failed');
 await expect(page.locator('#gp14Detail h3')).toContainText('OC-1');await expect(page.locator('#gp14Recv_pol1')).toHaveValue('3');
 await page.evaluate(()=>{gamaReceivePurchaseV14('po1',true);gamaReceivePurchaseV14('po1',true)});
 await page.waitForFunction(()=>window.__releaseReceipt);await expect(page.locator('#gp14ReceiveNext')).toBeDisabled();
 expect(await page.evaluate(()=>__receiptAttempts.length)).toBe(2);expect(await page.evaluate(()=>__receiptAttempts[0].request_key===__receiptAttempts[1].request_key)).toBe(true);
 await page.evaluate(()=>__releaseReceipt());await expect(page.locator('#gp14Detail h3')).toContainText('OC-2');await expect(page.locator('#gp14Recv_pol2')).toBeFocused();
 expect(await page.evaluate(()=>__DB.purchase_orders.map(o=>o.status))).toEqual(['received','sent']);
 expect(await page.evaluate(()=>__DB.stock_quants.map(q=>q.quantity))).toEqual([103,20]);
 expect(await page.evaluate(()=>__DB.stock_movements.filter(m=>m.reference_id==='po1').length)).toBe(1);
});
