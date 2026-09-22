const {test,expect}=require('@playwright/test');
const fs=require('fs');
const cloud=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');

const today=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
const RIGHTS={role:'administrador',view:true,create:true,process:true,refund:true,delete:true};
const LOCATIONS=[{id:'loc1',code:'A-01',name:'Pasillo A'},{id:'loc2',code:'A-02',name:'Pasillo B'}];

const overview=(rows,rights=RIGHTS)=>({rights,today,
 kpis:{open:2,to_process:1,financial_pending:1,closed_month:3},
 rows,locations:LOCATIONS,
 customers:[{id:'c1',name:'ABC SA'}],suppliers:[{id:'s1',name:'Distribuidora Andina'}]});

const CUSTOMER_ROWS=[
 {id:'r1',number:'RET-000014',kind:'customer',status:'to_process',reason:'defective',financial_action:'none',
  created_on:today,created_at:today+'T09:00:00Z',partner:'ABC SA',amount:100,lines:1,refunded:0,credited:false},
 {id:'r2',number:'RET-000015',kind:'customer',status:'received',reason:'damaged',financial_action:'refund',
  created_on:today,created_at:today+'T08:00:00Z',partner:'ABC SA',amount:50,lines:1,refunded:0,credited:false}];
const SUPPLIER_ROWS=[
 {id:'r9',number:'RET-000020',kind:'supplier',status:'to_process',reason:'defective',financial_action:'none',
  created_on:today,created_at:today+'T07:00:00Z',partner:'Distribuidora Andina',amount:25,lines:1,refunded:0,credited:false}];

const SOURCES={rows:[{id:'d1',number:'ENV-00000087',dispatched_at:today+'T10:00:00Z',partner:'ABC SA',
 customer_id:'c1',order_id:'o1',order_number:'PED-00000128',invoice_id:'i1',invoice_number:'FAC-00000095',lines:2}]};
const SOURCE_LINES={kind:'customer',source_id:'d1',number:'ENV-00000087',partner:'ABC SA',customer_id:'c1',
 order_id:'o1',order_number:'PED-00000128',invoice_id:'i1',
 rows:[{line_id:'dl1',product_id:'p1',product:'Producto A',reference:'REF-A',moved:10,returned:0,max_return:10,unit_price:10,tax_rate:0},
       {line_id:'dl2',product_id:'p2',product:'Producto B',reference:'REF-B',moved:5,returned:1,max_return:4,unit_price:20,tax_rate:0}]};

const DETAIL={id:'r2',number:'RET-000015',kind:'customer',status:'received',reason:'damaged',
 financial_action:'refund',notes:null,amount:100,refunded:0,partner:'ABC SA',rights:RIGHTS,
 order_id:'o1',invoice_id:'i1',
 lines:[{id:'l1',product_id:'p1',product:'Producto A',reference:'REF-A',quantity:2,unit_price:50,
   tax_rate:0,disposition:null,processed_at:null,notes:null,amount:100}],
 credits:[],refunds:[],files:[],
 documents:{order:{id:'o1',number:'PED-00000128'},delivery:{id:'d1',number:'ENV-00000087'},
  invoice:{id:'i1',number:'FAC-00000095'},purchase_order:null,supplier_invoice:null}};

async function boot(page,{role='admin',rows=CUSTOMER_ROWS,rights=RIGHTS,detail=DETAIL}={}){
 const RESPONSES={overview:overview(rows,rights),sources:SOURCES,source_lines:SOURCE_LINES,detail,
  stats:{month_count:4,month_value:320,return_rate:1.25,
   reasons:[{reason:'defective',n:3}],products:[{product:'Producto A',quantity:6}],suppliers:[]}};
 await page.addInitScript(({role,RESPONSES})=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Responsable de devoluciones'}));
  localStorage.removeItem('gama_company_currency_v1');
  window.__DB={products:[],customers:[],suppliers:[],profiles:[],app_modules:[],invoices:[],
   financial_accounts:[{id:'bank1',name:'Banco real',currency:'USD',active:true}],company_settings:[{id:true,currency:'USD',country:'EC'}]};
  window.__RET={responses:RESPONSES,calls:[],error:null};
 },{role,RESPONSES});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));
 await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');
 await page.waitForFunction(()=>window.GamaReturns&&window.GamaCloud&&window.GamaCurrency);
 await page.evaluate(async()=>{
  await GamaCloudReady;const old=GamaCloud.db;
  GamaCloud.db=async()=>{const c=await old();return{...c,rpc:async(fn,args)=>{
   if(fn!=='gama_returns_action')return c.rpc(fn,args);
   window.__RET.calls.push(args);
   if(window.__RET.error)return {error:{message:window.__RET.error}};
   const r=window.__RET.responses[args.p_action];
   return {data:r===undefined?{ok:true,id:'new',number:'RET-000099'}:structuredClone(r)};
  }}};
 });
 await page.evaluate(()=>window.GamaReturns.open());
 await expect(page.locator('#returns')).toHaveClass(/active/);
}
const calls=page=>page.evaluate(()=>window.__RET.calls);
const lastCall=async(page,action)=>(await calls(page)).filter(c=>c.p_action===action).pop();

test('la lista abre con los cuatro indicadores, la tabla del pliego y sus filtros',async({page})=>{
 await boot(page);
 const kpis=page.locator('.grKpis .grCard');
 await expect(kpis).toHaveCount(4);
 await expect(kpis.nth(0)).toContainText('2');
 await expect(page.locator('.grTable thead th')).toHaveCount(7);
 await expect(page.locator('.grTable tbody tr')).toHaveCount(2);
 await expect(page.locator('.grTable tbody tr').first()).toContainText('RET-000014');
 // La divisa sale del motor central, nunca de un símbolo escrito a mano.
 await expect(page.locator('.grTable tbody tr').first()).toContainText('$');
 for(const id of ['grPartner','grStatus','grFrom','grTo','grSearch'])await expect(page.locator('#'+id)).toBeVisible();
});

test('las dos pestañas piden cada una su tipo al servidor',async({page})=>{
 await boot(page);
 expect((await lastCall(page,'overview')).p_data.kind).toBe('customer');
 await page.evaluate(()=>{window.__RET.responses.overview.rows=[
  {id:'r9',number:'RET-000020',kind:'supplier',status:'to_process',reason:'defective',financial_action:'none',
   created_on:'2026-09-18',created_at:'2026-09-18T07:00:00Z',partner:'Distribuidora Andina',amount:25,lines:1,refunded:0,credited:false}]});
 await page.locator('[data-gr-tab=supplier]').click();
 await expect(page.locator('.grTable tbody tr')).toHaveCount(1);
 expect((await lastCall(page,'overview')).p_data.kind).toBe('supplier');
 await expect(page.locator('.grTable tbody tr').first()).toContainText('RET-000020');
});

test('crear un retorno son tres pantallas y GAMA pone todo lo que ya sabe',async({page})=>{
 await boot(page);
 await page.locator('#grNew').click();
 await expect(page.locator('dialog')).toContainText('1 · Tipo');
 await page.locator('[data-gr-kind=customer]').click();
 // Paso 2: el documento de origen, con su número y su cliente.
 await expect(page.locator('dialog')).toContainText('ENV-00000087');
 await expect(page.locator('dialog')).toContainText('ABC SA');
 await page.locator('[data-gr-src=d1]').click();
 // Paso 3: nada que reteclear, sólo cantidades.
 await expect(page.locator('dialog')).toContainText('PED-00000128');
 await expect(page.locator('dialog')).toContainText('Producto A');
 await expect(page.locator('[data-gr-qty=dl2]')).toHaveAttribute('max','4');
 await page.locator('[data-gr-qty=dl1]').fill('2');
 await page.locator('#grReason').selectOption('damaged');
 await page.locator('#gsSave').click();
 await expect(page.locator('dialog')).toHaveCount(0);
 const call=await lastCall(page,'create');
 expect(call.p_data).toMatchObject({kind:'customer',source_id:'d1',invoice_id:'i1',reason:'damaged'});
 expect(call.p_data.lines).toEqual([{line_id:'dl1',quantity:2}]);
});

test('el motivo «Otro» abre el comentario y ninguna cantidad no crea nada',async({page})=>{
 await boot(page);
 await page.locator('#grNew').click();
 await page.locator('[data-gr-kind=customer]').click();
 await page.locator('[data-gr-src=d1]').click();
 await expect(page.locator('#grNotesBox')).toBeHidden();
 await page.locator('#grReason').selectOption('other');
 await expect(page.locator('#grNotesBox')).toBeVisible();
 await page.locator('#gsSave').click();
 await expect(page.locator('#gsFormError')).toContainText('al menos una cantidad');
 expect((await calls(page)).filter(c=>c.p_action==='create')).toHaveLength(0);
});

test('la ficha enseña las tres decisiones y los documentos ligados',async({page})=>{
 await boot(page);
 await page.locator('[data-gr-open=r1]').click();
 await expect(page.locator('#grMain')).toContainText('RET-000015');
 // La ficha es un proceso: número PRC, seis etapas numeradas, y el origen en la primera.
 await expect(page.locator('.grSummary h3')).toHaveText('PRC-00000015');
 await expect(page.locator('.gdfStep')).toHaveCount(6);await expect(page.locator('.gdfStepper li')).toHaveCount(6);
 await expect(page.locator('.gdfStep').first()).toContainText('Origen de la devolución');
 const docs=page.locator('[data-gr-doc]');
 await expect(docs).toHaveCount(3);
 await expect(docs.nth(0)).toContainText('PED-00000128');
 await expect(docs.nth(2)).toContainText('FAC-00000095');
 await expect(page.locator('[data-gr-process=l1]')).toBeVisible();
 await expect(page.locator('#grRefund')).toBeVisible();
});

test('la decisión sobre el producto pide ubicación sólo al reponer',async({page})=>{
 await boot(page);
 await page.locator('[data-gr-open=r1]').click();
 await page.locator('[data-gr-process=l1]').click();
 await page.locator('[data-gr-disp=restocked]').click();
 await expect(page.locator('#grLocBox')).toBeVisible();
 await page.locator('[data-gr-disp=scrapped]').click();
 await expect(page.locator('#grLocBox')).toBeHidden();
 await page.locator('#gsSave').click();
 await expect(page.locator('dialog')).toHaveCount(0);
 const call=await lastCall(page,'process_line');
 expect(call.p_data).toMatchObject({id:'r2',line_id:'l1',disposition:'scrapped',location_id:null});
});

test('el reembolso propone el importe pendiente y no deja pasarse',async({page})=>{
 await boot(page);
 await page.locator('[data-gr-open=r1]').click();
 await page.locator('#grRefund').click();
 await expect(page.locator('#grRefundAmount')).toHaveValue('100');
 await expect(page.locator('#grRefundAmount')).toHaveAttribute('max','100');
 await page.locator('#grRefundAccount').selectOption('bank1');await page.locator('#grRefundMethod').fill('Transferencia');
 await page.locator('#gsSave').click();
 await expect(page.locator('dialog')).toHaveCount(0);
 const call=await lastCall(page,'refund');
 expect(call.p_data.amount).toBe(100);
 expect(call.p_data.method).toBe('Transferencia');expect(call.p_data.financial_account_id).toBe('bank1');
 expect(call.p_data.request_key).toMatch(/^[0-9a-f-]{36}$/);
});

test('el servidor manda: su negativa se explica en la pantalla',async({page})=>{
 await boot(page);
 await page.locator('[data-gr-open=r1]').click();
 await page.evaluate(()=>{window.__RET.error='REFUND_EXCEEDS_RETURN'});
 await page.locator('#grRefund').click();
 await page.locator('#grRefundAccount').selectOption('bank1');await page.locator('#grRefundMethod').fill('Transferencia');
 await page.locator('#gsSave').click();
 await expect(page.locator('#gsFormError')).toContainText('superaría el importe de la devolución');
 await expect(page.locator('dialog')).toHaveCount(1);
});

test('cada perfil ve sólo sus botones',async({page})=>{
 // Comercial: ve y crea, no trata ni reembolsa.
 await boot(page,{role:'commercial',rights:{role:'comercial',view:true,create:true,process:false,refund:false,delete:false}});
 await expect(page.locator('#grNew')).toBeVisible();
 await page.locator('[data-gr-open=r1]').click();
 await expect(page.locator('[data-gr-process=l1]')).toHaveCount(0);
 await expect(page.locator('#grRefund')).toHaveCount(0);
 await expect(page.locator('#grCredit')).toHaveCount(0);
});

test('logística trata la mercancía pero no toca el dinero',async({page})=>{
 await boot(page,{role:'magasinier',rights:{role:'almacenero',view:true,create:true,process:true,refund:false,delete:false}});
 await page.locator('[data-gr-open=r1]').click();
 await expect(page.locator('[data-gr-process=l1]')).toBeVisible();
 await expect(page.locator('#grRefund')).toHaveCount(0);
 await expect(page.locator('#grFinancial')).toHaveCount(0);
});

test('las cifras del periodo se piden sólo cuando se abren',async({page})=>{
 await boot(page);
 expect((await calls(page)).filter(c=>c.p_action==='stats')).toHaveLength(0);
 await page.locator('#grStatsLoad').click();
 await expect(page.locator('#grStats')).toContainText('1,25');
 await expect(page.locator('#grStats')).toContainText('Producto A');
});

test('PC, tableta y móvil enseñan la misma pantalla sin desbordarla',async({page})=>{
 await boot(page);
 for(const size of [{width:1280,height:900},{width:1024,height:768},{width:768,height:1024},{width:390,height:844}]){
  await page.setViewportSize(size);
  await expect(page.locator('#returns')).toBeVisible();
  await expect(page.locator('.grKpis .grCard')).toHaveCount(4);
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(1);
 }
});

test('el módulo habla las tres lenguas sin tocar los números ni las referencias',async({page})=>{
 await boot(page);
 await expect(page.locator('#grNew')).toContainText('+ Nueva devolución');
 for(const [lang,label,tab] of [['fr','+ Nouveau retour','PRC · Retour client'],['en','+ New return','PRC · Customer return']]){
  await page.evaluate(l=>window.GamaI18n.setLanguage(l),lang);
  await expect(page.locator('#grNew')).toContainText(label);
  await expect(page.locator('[data-gr-tab=customer]')).toContainText(tab);
  await expect(page.locator('.grTable tbody tr').first()).toContainText('RET-000014');
  await expect(page.locator('.grKpis .grCard').first()).toContainText('2');
 }
});
