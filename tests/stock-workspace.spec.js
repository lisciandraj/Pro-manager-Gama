const {test,expect}=require('@playwright/test'),fs=require('node:fs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
const base={warehouses:[{id:'w1',code:'PRINCIPAL',name:'Principal',active:true}],warehouse_locations:[{id:'l1',warehouse_id:'w1',code:'STOCK',name:'Stock',active:true}],products:[{id:'p1',name:'Cemento',reference:'CEM',stock:3,min_stock:10,max_stock:40,purchase_price:2,supplier_id:'s1',active:true},{id:'p2',name:'Arena',reference:'ARE',stock:2,min_stock:5,max_stock:20,purchase_price:4,supplier_id:'s2',active:true}],stock_quants:[{id:'q1',product_id:'p1',location_id:'l1',quantity:3,reserved_quantity:0},{id:'q2',product_id:'p2',location_id:'l1',quantity:2,reserved_quantity:0}],suppliers:[{id:'s1',name:'Proveedor A',active:true},{id:'s2',name:'Proveedor B',active:true}],profiles:[{id:'u1',full_name:'Ana',role:'almacenero',active:true}],inventory_counts:[],inventory_count_lines:[],reorder_rules:[],purchase_orders:[],purchase_order_lines:[],stock_movements:[],warehouse_shelves:[]};
async function boot(page,seed=base,insights={}){
 await page.addInitScript(([db,data])=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'}));window.__DB=db;window.__stockInsights=data},[seed,insights]);
 await page.route('https://**/*',r=>r.abort());await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaOpenWarehouses&&window.gamaAccessAllowed?.('warehouses'));
}
for(const width of [390,1440])test(`Stock opens independently of secondary reads and shows three decimals at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});const db=structuredClone(base);db.stock_quants[0].quantity=.001;
 const requests=[];page.on('request',r=>requests.push(r.url()));await boot(page,db);
 expect(requests.some(u=>u.includes('gama-stock-workspace.js'))).toBe(false);expect(requests.some(u=>u.includes('gama-stock-operations.js'))).toBe(false);
 await page.evaluate(()=>{const list=GamaCloud.list;window.__stockReads=[];GamaCloud.list=async(table,o)=>{window.__stockReads.push(table);if(['inventory_counts','reorder_rules','warehouse_shelves','purchase_orders','purchase_order_lines'].includes(table))return new Promise(()=>{});return list(table,o)}});
 await page.evaluate(()=>GamaOpenWarehouses());await expect(page.locator('#ivTabla')).toContainText('0,001');
 const reads=await page.evaluate(()=>window.__stockReads);expect(reads).not.toContain('stock_quants');expect(reads).not.toContain('products');expect(await page.evaluate(()=>__stockPageCalls.length)).toBe(1);expect(reads).not.toContain('inventory_counts');expect(reads).not.toContain('reorder_rules');expect(reads).not.toContain('warehouse_shelves');
 expect(requests.filter(u=>u.includes('gama-stock-workspace.js'))).toHaveLength(1);expect(requests.some(u=>u.includes('gama-stock-operations.js'))).toBe(false);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});
test('selected proposals create supplier drafts, discount them and preserve physical quantities',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaOpenWarehouses());await page.click('[data-iv-tab=reabastecimiento]');await expect(page.locator('#ivCuerpo')).toContainText('37');
 await page.check('#ivsAll');await expect(page.locator('#ivsSelection')).toContainText('2 productos · 2 proveedores');await page.click('#ivsCreate');
 await expect(page.locator('#ivsResult')).toContainText('2 borrador(es) creado(s)');
 const data=await page.evaluate(()=>({orders:__DB.purchase_orders,quants:__DB.stock_quants,calls:__stockReplenishmentCalls}));expect(data.orders).toHaveLength(2);expect(data.orders.every(o=>o.status==='draft')).toBe(true);expect(data.quants.map(q=>q.quantity)).toEqual([3,2]);expect(data.calls).toHaveLength(1);await expect(page.locator('#ivsCreate')).toHaveCount(0);
 await page.getByRole('button',{name:/Abrir OC-STOCK/}).first().click();await expect(page.locator('#gamaPurchasesV14')).toBeVisible();
});
test('a retry keeps its command key and a stale proposal is explained without clearing the selected lines',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaOpenWarehouses());await page.click('[data-iv-tab=reabastecimiento]');await page.check('#ivsAll');
 await page.evaluate(()=>window.__stockReplenishError='network request failed');await page.click('#ivsCreate');await expect(page.locator('#ivsResult')).toContainText('network request failed');
 await page.evaluate(()=>window.__stockReplenishError='REPLENISHMENT_CHANGED');await page.click('#ivsCreate');await expect(page.locator('#ivsResult')).toContainText('Actualiza las propuestas');
 const keys=await page.evaluate(()=>__stockReplenishmentCalls.map(c=>c.request_key));expect(keys[0]).toBe(keys[1]);await expect(page.locator('#ivsSelection')).toContainText('2 productos');
 await page.evaluate(()=>window.__stockReplenishError=null);await page.click('#ivsCreate');await expect(page.locator('#ivsResult')).toContainText('2 borrador(es)');expect(await page.evaluate(()=>__DB.purchase_orders.length)).toBe(2);
});
test('dormant periods show quantities and tied-up value; actions link to affected products',async({page})=>{
 const row=(id,name,days,quantity,value)=>({id,name,on_hand:quantity,reserved:0,available:quantity,min_quantity:10,days_without_out:days,value,last_out:'2026-07-01',suggested_quantity:0,importance:'C'});
 await boot(page,base,{rotacion:{rows:[row('p1','Cemento',45,3,6),row('p2','Arena',95,2,8)]},acciones:{late_orders:[{id:'po1',number:'OC-LATE',supplier:'Proveedor A',expected_date:'2026-09-01',days_late:10}],adjustments:[]}});
 await page.evaluate(()=>GamaOpenWarehouses());await page.click('[data-iv-tab=rotacion]');await expect(page.locator('#ivCuerpo')).toContainText('Cemento');await expect(page.locator('#ivCuerpo')).toContainText('Arena');
 await page.selectOption('#ivsDormantDays','90');await expect(page.locator('#ivCuerpo')).not.toContainText('Cemento');await expect(page.locator('#ivCuerpo')).toContainText('Arena');await expect(page.locator('.ivKpi').filter({hasText:'Valor inmovilizado'})).toContainText('8');
 await page.click('[data-iv-tab=acciones]');await expect(page.locator('#ivCuerpo')).toContainText('OC-LATE');await page.locator('[data-stock-product=p1]').click();await expect(page.locator('#ivBuscar')).toHaveValue('CEM');await expect(page.locator('#ivTabla')).not.toContainText('Arena');
});
test('cycle reminders prepare a responsible, deadline, priority and scoped next count',async({page})=>{
 const db=structuredClone(base);db.inventory_counts=[{id:'c-old',warehouse_id:'w1',reference:'Recuento mensual',status:'validated',created_at:'2026-01-01',next_due:'2026-09-01',assigned_to:'u1',priority:'high',cycle_days:30,blind:true,scope_product_id:'p1'}];
 await boot(page,db);await page.evaluate(()=>GamaOpenWarehouses());await page.click('[data-iv-tab=conteos]');await expect(page.locator('#ivsCycles')).toContainText('Recuento mensual');await page.click('[data-stock-repeat=c-old]');
 await expect(page.locator('#ivcAssigned')).toHaveValue('u1');await expect(page.locator('#ivcPriority')).toHaveValue('high');await expect(page.locator('#ivcProduct')).toHaveValue('p1');await expect(page.locator('#ivcDue')).toHaveValue('2026-09-01');
 await page.click('#ivcCrear');await expect(page.locator('#ivcLineas')).toContainText('Cemento');await expect(page.locator('#ivcLineas')).not.toContainText('Arena');
 const count=await page.evaluate(()=>__DB.inventory_counts.at(-1));expect(count).toMatchObject({assigned_to:'u1',priority:'high',product_id:'p1',repeat_of:'c-old'});expect(await page.evaluate(()=>__DB.stock_quants[0].quantity)).toBe(3);
});
test('failed insight loads can be retried and late responses cannot replace the active tab',async({page})=>{
 await boot(page);await page.evaluate(()=>{window.__stockInsightsError='temporary failure'});await page.evaluate(()=>GamaOpenWarehouses());await page.click('[data-iv-tab=acciones]');await expect(page.locator('[data-iv-retry]')).toBeVisible();
 await page.evaluate(()=>window.__stockInsightsError=null);await page.click('[data-iv-retry]');await expect(page.locator('#ivCuerpo')).toContainText('Disponibilidad insuficiente');
 await page.evaluate(()=>{const db=GamaCloud.db;GamaCloud.db=async()=>{const client=await db(),rpc=client.rpc;client.rpc=(name,data)=>name==='gama_stock_insights'&&data.p_view==='rotacion'?new Promise(resolve=>window.__releaseStockTab=async()=>resolve(await rpc(name,data))):rpc(name,data);return client}});
 await page.click('[data-iv-tab=rotacion]');await page.waitForFunction(()=>window.__releaseStockTab);await page.click('[data-iv-tab=existencias]');await expect(page.locator('#ivTabla')).toBeVisible();await page.evaluate(()=>window.__releaseStockTab());await expect(page.locator('#ivTabla')).toBeVisible();await expect(page.locator('#ivsDormantDays')).toHaveCount(0);
});

test('changing accounts clears protected Stock content before the next read',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaOpenWarehouses());await page.click('[data-iv-tab=reabastecimiento]');await expect(page.locator('#ivCuerpo')).toContainText('Proveedor A');
 await page.evaluate(()=>{window.__DB._profile={...window.__DB._profile,id:'warehouse-test-user',role:'almacenero'};localStorage.setItem('gama_session_v1',JSON.stringify({userId:'warehouse-test-user',role:'magasinier',name:'Warehouse'}));window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_IN',session:{user:{id:'warehouse-test-user'}}}}))});
 await expect(page.locator('#warehouses')).not.toContainText('Proveedor A');await expect(page.locator('#ivsCreate')).toHaveCount(0);await page.waitForFunction(()=>GamaRoleAccess.isReady());
 await page.evaluate(()=>GamaOpenWarehouses());await page.click('[data-iv-tab=reabastecimiento]');await expect(page.locator('#ivCuerpo')).toContainText('Tu perfil no tiene acceso a los datos de Compras');await expect(page.locator('#ivCuerpo')).not.toContainText('Proveedor A');
});

test('product preview follows selection and mobile quantities keep their meaning',async({page})=>{
 await page.setViewportSize({width:1440,height:1000});await boot(page);await page.evaluate(()=>GamaOpenWarehouses());await expect(page.locator('#ivTabla th')).toHaveCount(6);await page.locator('[data-iv-open=p2]').click();await expect(page.locator('#ivInspector')).toContainText('Arena');await expect(page.locator('#ivInspector')).toContainText('Costo');await page.setViewportSize({width:390,height:844});await expect(page.locator('#ivTabla table')).toHaveAttribute('data-gama-view','cards');await expect(page.locator('#ivTabla td[data-col="Stock físico"]').first()).toBeVisible();await page.screenshot({path:'test-results/stock-design-mobile.png',fullPage:true});
});

for(const width of [1024,1440])test(`Stock photos stay inside their frame beside product text at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:1000});const db=structuredClone(base);
 for(const [i,p] of db.products.entries()){
  const [w,h]=i?[240,960]:[960,240];
  p.has_photo=true;p.photo_data='data:image/svg+xml;base64,'+Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><rect width="100%" height="100%" fill="#157F98"/></svg>`).toString('base64');
  p.name+=' — produit avec un nom long et une référence détaillée';
 }
 await boot(page,db);await page.evaluate(()=>GamaOpenWarehouses());
 const checkPhotos=async()=>{
  await expect.poll(()=>page.locator('#ivTabla img.ivProductPhoto').evaluateAll(imgs=>imgs.length===2&&imgs.every(img=>img.complete&&img.naturalWidth>0))).toBe(true);
  const boxes=await page.locator('#ivTabla .ivProductOpen').evaluateAll(buttons=>buttons.map(button=>{
   const photo=button.querySelector('img').getBoundingClientRect(),frame=button.firstElementChild.getBoundingClientRect(),label=button.lastElementChild.getBoundingClientRect(),control=button.getBoundingClientRect(),cell=button.parentElement.getBoundingClientRect();
   return {contained:photo.left>=frame.left-.5&&photo.top>=frame.top-.5&&photo.right<=frame.right+.5&&photo.bottom<=frame.bottom+.5,gap:label.left-photo.right,controlFits:control.left>=cell.left-.5&&control.right<=cell.right+.5};
  }));
  for(const box of boxes){expect(box.contained,'photo must not spill out of its frame').toBe(true);expect(box.gap,'product name must stay beside the photo').toBeGreaterThanOrEqual(8);expect(box.controlFits,'product control must stay inside its card').toBe(true)}
  await expect.poll(()=>page.locator('#ivInspector img').evaluate(img=>img.complete&&img.naturalWidth>0)).toBe(true);
  expect(await page.locator('#ivInspector').evaluate(host=>host.querySelector('img').getBoundingClientRect().bottom<=host.querySelector('h3').getBoundingClientRect().top)).toBe(true);
 };
 await checkPhotos();
 await page.locator('#ivTabla [data-table-view=cards]').click();await checkPhotos();
 await page.locator('#ivTabla [data-table-view=table]').click();
 await page.locator('#ivBuscar').fill('CEM');await page.locator('#ivBuscar').fill('');await checkPhotos();
 for(const mobileWidth of [390,320]){await page.setViewportSize({width:mobileWidth,height:844});await page.locator('#ivTabla [data-table-view=cards]').click();await checkPhotos()}
 const reads=await page.evaluate(()=>__DB.__calls.filter(c=>c.table==='products'));
 expect(reads.some(c=>c.select==='id,photo_data')).toBe(true);
 expect(reads.some(c=>c.select!=='id,photo_data'&&(c.select==='*'||String(c.select).includes('photo_data')))).toBe(false);
});

for(const width of [390,1440])test(`paged Stock retains catalogue totals and filters before slicing at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});const db=structuredClone(base);db.products=[];db.stock_quants=[];
 for(let i=0;i<65;i++){db.products.push({id:'p'+i,name:'Article '+String(i).padStart(3,'0'),reference:'REF-'+i,active:true,purchase_price:2,min_stock:1});db.stock_quants.push({id:'q'+i,product_id:'p'+i,location_id:'l1',quantity:i,reserved_quantity:0})}
 await boot(page,db);await page.evaluate(()=>GamaOpenWarehouses());await expect(page.locator('[data-iv-product]')).toHaveCount(20);await expect(page.locator('#ivKpis')).toContainText('65');await expect(page.locator('#ivStockTotals')).toContainText('4.160');
 await page.locator('#ivTabla [data-page-next]').click();await expect(page.locator('#ivTabla')).toContainText('Article 020');await expect(page.locator('#ivTabla .gamaPagerInfo')).toContainText('21–40');await expect(page.locator('#ivKpis')).toContainText('65');
 await page.locator('#ivBuscar').fill('REF-64');await expect(page.locator('[data-iv-product]')).toHaveCount(1);await expect(page.locator('#ivTabla')).toContainText('Article 064');await expect(page.locator('#ivStockTotals')).toContainText('128');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});
