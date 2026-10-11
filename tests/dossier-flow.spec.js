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
 await expect(page.locator('.gdfNextCard .gdfActions')).toContainText('Revisar la reserva de stock');
 // A permission removed after rendering is checked again on click.
 await page.evaluate(()=>{const allowed=gamaAccessAllowed;gamaAccessAllowed=id=>id!=='tms'&&allowed(id)});
 await link(4,'Abrir la preparación').click();expect(await page.evaluate(()=>__links.length)).toBe(9);
 await page.setViewportSize({width:390,height:844});await page.evaluate(async()=>{await GamaI18n.setLanguage('fr');await GamaDossierFlow.open('o:o0')});
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

test('step history resolves authors, escapes labels, paginates and suppresses restricted stages',async({page})=>{
 await boot(page);await page.evaluate(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:async(fn,args)=>{if(fn!=='gama_process_history')return c.rpc(fn,args);return {data:{items:args.p_offset?[{id:'old',step:3,action:'created',actor_name:'AUTHOR_NOT_RECORDED',at:'2026-01-01T10:00:00Z',total:2}]:[{id:'new',step:3,action:'confirm',actor_name:'<img src=x onerror=alert(1)> Alice',at:'2026-01-02T11:00:00Z',total:2},{id:'fin',step:7,action:'payment',actor_name:'Finance',at:'2026-01-02T12:00:00Z',total:1}]}}}}}});await page.evaluate(async()=>{await GamaI18n.setLanguage('fr');await GamaDossierFlow.open('o:o0')});const h=page.locator('[data-step="3"] .gdfHistory');await expect(h).toContainText('Alice');expect(await h.locator('img').count()).toBe(0);await h.locator('summary').click();await expect(h).toContainText('Commande confirmée');await h.locator('[data-history-more]').click();await expect(h).toContainText('Auteur non enregistré');await expect(h).toContainText('2 / 2');await page.evaluate(async()=>{__processStates['o:o0'].steps[6].state='restricted';await GamaDossierFlow.open('o:o0')});await expect(page.locator('[data-step="7"] .gdfHistory')).toHaveCount(0);await expect(page.locator('[data-step="1"] .gdfHistory')).toContainText('aucune validation avec auteur');
});

async function recordedHistory(page,items){
 await page.evaluate(items=>{window.__historyItems=items;window.__historyCalls=[];const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:async(fn,args)=>{
  if(fn!=='gama_process_history')return c.rpc(fn,args);
  __historyCalls.push(args);const items=__historyItems.filter(x=>!args.p_step||x.step===args.p_step),steps=[...new Set(items.map(x=>x.step))];
  return {data:{items:steps.flatMap(step=>{const rows=items.filter(x=>x.step===step).sort((a,b)=>new Date(b.at)-new Date(a.at));return rows.slice(args.p_offset,args.p_offset+50).map(x=>({...x,total:rows.length,actor_name:'Ana'}))})}};
 }}}},items);
}

test('completion dates use validation events beyond page one and leave unfinished steps undated',async({page})=>{
 await boot(page);
 const edits=Array.from({length:51},(_,i)=>({id:'edit'+i,step:3,action:'update',at:'2026-10-10T10:'+String(i).padStart(2,'0')+':00Z'}));
 await recordedHistory(page,[...edits,{id:'confirmed',step:3,action:'confirm',at:'2026-10-02T02:00:00Z'},{id:'request-edit',step:1,action:'request',at:'2026-10-09T12:00:00Z'},{id:'partial',step:4,action:'fulfillment_finish',at:'2026-10-08T10:00:00Z'},{id:'quote-accept',step:2,action:'quote_accept',at:'2026-09-30T12:00:00Z'}]);
 await page.evaluate(async()=>{await GamaI18n.setLanguage('fr');await GamaDossierFlow.open('o:o0')});
 for(const el of [page.locator('.gdfStepper [data-gdf-date="3"] time'),page.locator('.gdfStep[data-step="3"] .gdfStepDate time')]){
  await expect(el).toHaveAttribute('datetime','2026-10-02T02:00:00Z');await expect(el).toContainText('1 oct. 2026');
 }
 expect(await page.evaluate(()=>__historyCalls.some(c=>c.p_step===3&&c.p_offset===50))).toBe(true);
 await expect(page.locator('.gdfStep[data-step="1"] .gdfStepDate')).toHaveText('Date de clôture non enregistrée');
 await expect(page.locator('.gdfStep[data-step="4"] .gdfStepDate time')).toHaveCount(0);
 await expect(page.locator('.gdfStepper [data-gdf-date="5"]')).toHaveText('À venir');
 await expect(page.locator('.gdfNextCard')).toContainText('Réserver les quantités manquantes');
 await expect(page.locator('.gdfNextCard')).toContainText('Équipe concernée');
 for(const width of [1440,1024,390,320]){
  await page.setViewportSize({width,height:1000});
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  const card=await page.locator('.gdfNextCard').boundingBox(),first=await page.locator('.gdfFlow').boundingBox();
  if(width===1440)expect(card.x).toBeGreaterThan(first.x+first.width);else expect(card.y+card.height).toBeLessThanOrEqual(first.y+1);
  if(width===1440||width===390)await page.screenshot({path:`test-results/process-dates-${width}.png`,fullPage:width!==1440});
  if(width===1440){await page.locator('.gdfStep[data-step="7"]').scrollIntoViewIfNeeded();const panel=await page.locator('.gdfNextCard').boundingBox(),header=await page.locator('.arcTopbar').boundingBox();expect(panel.y).toBeGreaterThanOrEqual(header.y+header.height);await page.evaluate(()=>window.scrollTo(0,0))}
 }
 await page.evaluate(()=>GamaI18n.setLanguage('en'));
 await expect(page.locator('.gdfStep[data-step="3"] .gdfStepDate')).toContainText('Completed on');
 await expect(page.locator('.gdfStep[data-step="3"] .gdfStepDate time')).toHaveText('1 Oct 2026');
});

test('next action respects validated closure, reopened dossiers, assigned instructions and cancelled payments',async({page})=>{
 await boot(page);await recordedHistory(page,[{id:'new-metadata',step:6,action:'internal_external_number',at:'2026-10-10T12:00:00Z'},{id:'invoice',step:6,action:'internal_invoice',at:'2026-10-03T12:00:00Z'},{id:'payment-created:bad',step:7,action:'payment',at:'2026-10-09T12:00:00Z'},{id:'payment-created:good',step:7,action:'payment',at:'2026-10-04T12:00:00Z'},{id:'old-close',step:8,action:'closure',at:'2026-10-05T12:00:00Z'}]);
 await page.evaluate(async()=>{
  const s=__processStates['o:o0'];s.steps.forEach(x=>x.state='done');s.reopened=true;s.followup={owner_id:'person',next_action:'Contrôler <img src=x onerror=alert(1)> le dossier',due_date:'2026-10-12',closed_at:'2026-10-05T12:00:00Z'};
  __DB.profiles=[{id:'person',full_name:'Ana <strong>Test</strong>'}];__DB.external_invoices=[{id:'i1',order_id:'o0',number:'FAC-1',total:100,document_kind:'internal'}];__DB.external_invoice_payments=[{id:'good',invoice_id:'i1',amount:100,status:'confirmed'},{id:'bad',invoice_id:'i1',amount:100,status:'cancelled'}];
  await GamaI18n.setLanguage('fr');await GamaDossierFlow.open('o:o0');
 });
 await expect(page.locator('.gdfStep[data-step="6"] .gdfStepDate time')).toHaveAttribute('datetime','2026-10-03T12:00:00Z');
 await expect(page.locator('.gdfStep[data-step="7"] .gdfStepDate time')).toHaveAttribute('datetime','2026-10-04T12:00:00Z');
 await expect(page.locator('.gdfStep[data-step="8"] .gdfStepDate time')).toHaveCount(0);
 await expect(page.locator('.gdfNextCard')).toContainText('valider la clôture');await expect(page.locator('.gdfNextCard')).toContainText('Ana <strong>Test</strong>');await expect(page.locator('.gdfNextCard img')).toHaveCount(0);
 await expect(page.locator('.gdfNextCard time')).toHaveText('12 oct. 2026');
 await page.evaluate(async()=>{__processStates['o:o0'].closed=true;await GamaDossierFlow.open('o:o0')});
 await expect(page.locator('.gdfStep[data-step="8"] .gdfStepDate time')).toHaveAttribute('datetime','2026-10-05T12:00:00Z');
 await expect(page.locator('.gdfNextCard')).toContainText('Processus clôturé');await expect(page.locator('.gdfNextCard [data-gdf-next]')).toHaveCount(0);await expect(page.locator('.gdfStepper [aria-current]')).toHaveCount(0);
});

test('purchase order validation date is separate from receipt and the next action opens the pending bill',async({page})=>{
 await boot(page);await recordedHistory(page,[{id:'received',step:2,action:'purchase',status:'received',at:'2026-10-06T12:00:00Z'},{id:'sent',step:2,action:'purchase',status:'sent',at:'2026-10-02T12:00:00Z'},{id:'receipt',step:3,action:'receipt',at:'2026-10-06T12:00:00Z'},{id:'stock',step:4,action:'stock',at:'2026-10-06T12:00:00Z'}]);
 await page.evaluate(async()=>{const key='p:p1',o={id:'p1',supplier_id:'s1',order_number:'OCO-30',dossier_number:30,status:'received',total:100,created_at:'2026-10-01T12:00:00Z'},s={key,steps:['Origen de la demanda','Pedido de compra','Recepción y control','Puesta en stock','Factura del proveedor','Seguimiento del pago','Cierre del proceso de compra'].map((title,i)=>({title,state:i<4?'done':'pending'})),metrics:{received:2,ordered:2,goods:2,stocked:2,unbilled:2,balance:0,open_returns:0},closed:false};__processRows=[{key,o,party:'Supplier',state:s}];__processStates[key]=s;GamaAccounting.open=o=>window.__nextBill=o;await GamaDossierFlow.open(key)});
 await expect(page.locator('.gdfStep[data-step="2"] .gdfStepDate time')).toHaveAttribute('datetime','2026-10-02T12:00:00Z');
 await expect(page.locator('.gdfStep[data-step="3"] .gdfStepDate time')).toHaveAttribute('datetime','2026-10-06T12:00:00Z');
 await page.locator('.gdfNextCard [data-gdf-next]').click();expect(await page.evaluate(()=>__nextBill)).toEqual({section:'purchases',purchaseOrderId:'p1',newBill:true});
});

test('restricted or failed history never fabricates a completion date',async({page})=>{
 await boot(page,'magasinier');await recordedHistory(page,[{id:'private',step:7,action:'payment',at:'2026-10-02T12:00:00Z'}]);
 await page.evaluate(async()=>{__processStates['o:o0'].steps.slice(0,5).forEach(s=>s.state='done');await GamaDossierFlow.open('o:o0')});
 await expect(page.locator('.gdfStep.restricted .gdfStepDate time')).toHaveCount(0);await expect(page.locator('.gdfNextCard [data-gdf-next]')).toHaveCount(0);
 await page.evaluate(async()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(f,a)=>f==='gama_process_history'?Promise.resolve({error:{message:'offline'}}):c.rpc(f,a)}};await GamaDossierFlow.open('o:o0')});
 await expect(page.locator('.gdfStep[data-step="3"] .gdfHistory')).toContainText('No se pudo cargar');await expect(page.locator('.gdfStepDate time')).toHaveCount(0);
});
