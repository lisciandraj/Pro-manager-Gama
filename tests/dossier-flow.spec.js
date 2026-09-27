const {test,expect}=require('@playwright/test'),fs=require('node:fs');
const cloud=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
async function boot(page,role='admin'){
 await page.addInitScript(role=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'QA'}));window.__DB={products:[],customers:[],suppliers:[],invoices:[],sales_orders:[],sales_order_lines:[],profiles:[]};
  const titles=['Origen de la demanda','Presupuesto','Pedido','Reserva de stock y preparación','Expedición y recepción','Facturación','Seguimiento del pago','Cierre del proceso de venta'];
  window.__processCalls=[];window.__processStates={};window.__processRows=Array.from({length:26},(_,i)=>{const id='o'+i,key='o:'+id,o={id,number:'PED-'+String(i+1).padStart(8,'0'),dossier_number:i+1,customer_name:'Cliente '+i,status:'confirmed'};
   const state={key,steps:titles.map((title,j)=>({title,state:j<3?'done':j===3?'blocked':'pending',info:''})),metrics:{ordered:10,performed:4,shipped:4,missing:6,unbilled:10,paid:0,credits:0,balance:100,open_returns:0},checks:{delivery_remainder:6},closed:false,cancelled:false,external_complete:false,external_pending:1};
   if(['magasinier','almacenero'].includes(role)){[5,6,7].forEach(j=>state.steps[j].state='restricted');state.external_complete=null;state.metrics.balance=null}
   window.__processStates[key]=state;return {key,o,party:o.customer_name,number:'PDV-'+String(i+1).padStart(8,'0'),state};});
 },role);
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaCloud&&window.GamaDossierFlow);
 await page.evaluate(async()=>{await GamaCloudReady;const db=GamaCloud.db;GamaCloud.db=async()=>{const c=await db();return {...c,rpc:async(fn,args)=>{
  if(fn==='gama_processes'){__processCalls.push(args);if(window.__processFail)return {error:{message:'offline'}};const d=args.p_data;if(args.p_action==='state')return {data:structuredClone(__processStates[d.key])};const rows=__processRows.filter(r=>(!d.key||d.key===r.key)&&(!d.search||JSON.stringify(r.o).includes(d.search)));return {data:{total:rows.length,items:structuredClone(rows.slice(d.offset,d.offset+25))}}}
  return c.rpc(fn,args);
 }}};await GamaDossierFlow.open()});
}
test('server pagination and search do not download the full process history',async({page})=>{
 await boot(page);await expect(page.locator('.gdfRecord')).toHaveCount(25);await expect(page.locator('.gdfStep')).toHaveCount(8);await expect(page.locator('.gdfRecord').first()).toContainText('PDV-00000001');
 await page.locator('[data-page-next]').click();await expect(page.locator('.gdfRecord')).toHaveCount(1);await expect(page.locator('.gdfRecord')).toContainText('Cliente 25');
 await page.locator('#gdfSearch').fill('Cliente 12');await expect(page.locator('.gdfRecord')).toHaveCount(1);await expect(page.locator('.gdfRecord')).toContainText('Cliente 12');
 expect(await page.evaluate(()=>__processCalls.filter(x=>x.p_action==='list').map(x=>x.p_data.offset))).toEqual([0,25,0]);
});
test('card and detail display the same authoritative blocked state and document links',async({page})=>{
 await boot(page);await expect(page.locator('.gdfStep').nth(3)).toHaveClass(/blocked/);await expect(page.locator('.gdfRecord').first().locator('.gdfProgress')).toHaveAttribute('data-state','blocked');await expect(page.locator('.gdfSummary .gdfBadge')).toHaveText('Proceso bloqueado');await expect(page.locator('.gdfStep').nth(4)).toContainText('4 / 10');
 await page.evaluate(()=>GamaSales.openOrder=id=>window.__opened=id);await page.locator('.gdfStep').nth(2).locator('[data-action="order"]').click();expect(await page.evaluate(()=>__opened)).toBe('o0');
});
test('credits and services can complete operations while external paperwork stays separate',async({page})=>{
 await boot(page);await page.evaluate(async()=>{const s=__processStates['o:o0'];s.steps.forEach(x=>x.state='done');Object.assign(s.metrics,{performed:10,shipped:10,unbilled:0,balance:0,credits:100,missing:0});await GamaDossierFlow.open('o:o0')});
 await expect(page.locator('.gdfSummary .gdfBadge')).toHaveText('Proceso completo');await expect(page.locator('.gdfStep').nth(6)).toContainText('Abonos');await expect(page.locator('.gdfStep').nth(6)).toContainText(/\$0[.,]00/);await expect(page.locator('#gdfDetail')).toContainText('Documentos externos por completar.');
 await page.evaluate(async()=>{__processStates['o:o0'].steps[7].state='blocked';__processStates['o:o0'].metrics.open_returns=1;await GamaDossierFlow.open('o:o0')});await expect(page.locator('.gdfSummary .gdfBadge')).toHaveText('Proceso bloqueado');await expect(page.locator('.gdfStep').nth(7)).toContainText('1');
});
test('purchase processes expose the same owner and closure controls',async({page})=>{
 await boot(page);await page.evaluate(async()=>{const titles=['Origen de la demanda','Pedido de compra','Recepción y control','Puesta en stock','Factura del proveedor','Seguimiento del pago','Cierre del proceso de compra'];const key='p:p1',o={id:'p1',supplier_id:'s1',order_number:'OCO-00000030',dossier_number:30,status:'received',total:100};const state={key,steps:titles.map((title,i)=>({title,state:i<4?'done':i===4?'blocked':'pending',info:''})),metrics:{received:2,ordered:2,goods:2,stocked:2,unbilled:2,balance:0,open_returns:0},checks:{},closed:false,cancelled:false};__processStates[key]=state;__processRows=[{key,o,party:'Supplier',state}];await GamaDossierFlow.open(key)});
 await expect(page.locator('.gdfStep')).toHaveCount(7);await expect(page.locator('#gdfDetail')).toContainText('Responsable y cierre');await expect(page.locator('.gdfStep').nth(4)).toHaveClass(/blocked/);
});
test('mobile restricted views and failed reads never show financial completion',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page,'magasinier');await expect(page.locator('.gdfStep').nth(5)).toHaveClass(/restricted/);await expect(page.locator('.gdfStep').nth(7)).toHaveClass(/restricted/);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 await page.evaluate(()=>window.__processFail=true);await page.locator('#gdfRefresh').click();await expect(page.locator('#gdfDetail [role=alert]')).toBeVisible();await expect(page.locator('.gdfStep')).toHaveCount(0);
});

test('each sales step opens its linked work screen, including the next action and order payments',async({page})=>{
 await boot(page);await page.evaluate(async()=>{
  __processRows[0].q={id:'q0',invoice_number:'COT-00000001',quote_state:'accepted'};
  __processRows[0].r={id:'r0',erp_reference:'SOL-00000001'};
  __DB.sales_order_lines=[{id:'l0',order_id:'o0',product_kind:'goods',quantity:10}];
  __DB.sales_deliveries=[{id:'s0',order_id:'o0',tms_delivery_id:'t0',number:'ENV-00000001'}];
  __DB.tms_deliveries=[{id:'t0',erp_reference:'ENT-00000001',status:'Planificada'}];
  __DB.external_invoices=[{id:'i0',order_id:'o0',number:'FAC-00000001',total:100,document_kind:'internal'}];
  window.__links=[];
  GamaOpenCustomerRequest=id=>__links.push(['request',id]);
  GamaQuotes.open=()=>{};GamaQuotes.view=id=>__links.push(['quote',id]);
  GamaSales.openOrder=id=>__links.push(['order',id]);GamaPreparation.open=id=>__links.push(['preparation',id]);
  gamaPrepareActionPurchase=options=>__links.push(['replenish',options]);gamaTMS.openDelivery=id=>__links.push(['delivery',id]);
  GamaPayments.open=options=>__links.push(['payments',options]);ArchitectProjectControls.dossier=key=>__links.push(['closure',key]);
  await GamaDossierFlow.open('o:o0');
 });
 for(let i=1;i<=8;i++)await expect(page.locator(`[data-step="${i}"] [data-gdf-next]`).first()).toBeVisible();
 const link=(step,label)=>page.locator(`[data-step="${step}"] .gdfActions`).getByRole('button',{name:label});
 await link(1,'Consultar el origen').click();await link(2,'Revisar el presupuesto').click();await link(3,'Abrir el pedido').click();
 await link(4,'Abrir la preparación').click();await link(4,'Preparar la reposición').click();
 await link(5,/Cargar \/ entregar/).click();await link(6,/Abrir la factura/).click();await link(7,'Abrir los cobros del pedido').click();await link(8,'Revisar responsable y cierre').click();
 expect(await page.evaluate(()=>__links)).toEqual([['request','r0'],['quote','q0'],['order','o0'],['preparation','o0'],['replenish',{order_id:'o0'}],['delivery','t0'],['payments',{invoiceId:'i0'}],['payments',{orderId:'o0',status:'all'}],['closure','o:o0']]);
 await expect(page.locator('.gdfSummary .gdfActions')).toContainText('Revisar la reserva de stock');
 // A permission removed after rendering is checked again on click.
 await page.evaluate(()=>{const allowed=gamaAccessAllowed;gamaAccessAllowed=id=>id!=='tms'&&allowed(id)});
 await link(4,'Abrir la preparación').click();expect(await page.evaluate(()=>__links.length)).toBe(9);
 await page.setViewportSize({width:390,height:844});await page.evaluate(async()=>{GamaI18n.setLanguage('fr');await GamaDossierFlow.open('o:o0')});
 await expect(page.locator('[data-step="7"] .gdfActions')).toContainText('Accéder aux encaissements de la commande');
 await expect(page.locator('[data-step="4"] .gdfActions')).not.toContainText('Accéder à la préparation');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 await page.screenshot({path:'test-results/process-actions-mobile.png',fullPage:true});
});

test('purchase receipt, bill creation and existing bill links retain purchase and invoice context',async({page})=>{
 await boot(page);await page.evaluate(async()=>{
  const key='p:p1',o={id:'p1',supplier_id:'s1',order_number:'OCO-00000030',dossier_number:30,status:'received',total:100};
  const state={key,steps:['Origen de la demanda','Pedido de compra','Recepción y control','Puesta en stock','Factura del proveedor','Seguimiento del pago','Cierre del proceso de compra'].map((title,i)=>({title,state:i<4?'done':'pending',info:''})),metrics:{received:2,ordered:2,goods:2,stocked:2,unbilled:2,balance:0,open_returns:0},closed:false,cancelled:false};
  __processStates[key]=state;__processRows=[{key,o,party:'Supplier',state}];window.__links=[];
  gamaOpenPurchaseDossier=id=>__links.push(['purchase',id]);GamaAccounting.open=options=>__links.push(['accounting',options]);
  await GamaDossierFlow.open(key);
 });
 await page.locator('[data-step="3"] .gdfActions button').click();await page.locator('[data-step="5"] .gdfActions button').click();
 expect(await page.evaluate(()=>__links)).toEqual([['purchase','p1'],['accounting',{section:'purchases',purchaseOrderId:'p1',newBill:true}]]);
 await expect(page.locator('[data-step="5"]')).toContainText('no genera una factura automáticamente');
 await page.evaluate(async()=>{__DB.supplier_invoices=[{id:'bill1',purchase_order_id:'p1',number:'External-123',erp_reference:'FPR-00000030',total:100,status:'posted'}];await GamaDossierFlow.open('p:p1')});
 await page.locator('[data-step="6"] .gdfActions button').click();
 expect(await page.evaluate(()=>__links.at(-1))).toEqual(['accounting',{section:'purchases',invoiceId:'bill1'}]);
});

test('a process without an order links back to its quote and never opens an empty preparation',async({page})=>{
 await boot(page);await page.evaluate(async()=>{const key='q:q1',state=structuredClone(__processStates['o:o0']);state.key=key;state.steps.forEach((s,i)=>s.state=i===0?'skip':i===1?'active':'pending');__processStates[key]=state;__processRows=[{key,q:{id:'q1',invoice_number:'COT-00000077',quote_state:'sent'},party:'Quote customer',state}];window.__quote=null;GamaQuotes.open=()=>{};GamaQuotes.view=id=>__quote=id;await GamaDossierFlow.open(key)});
 await page.locator('[data-step="3"] .gdfActions button').click();expect(await page.evaluate(()=>__quote)).toBe('q1');
 await expect(page.locator('[data-step="4"] .gdfActions')).not.toContainText('Abrir la preparación');
});
