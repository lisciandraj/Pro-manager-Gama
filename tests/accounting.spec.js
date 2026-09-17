const {test,expect}=require('@playwright/test');
const fs=require('fs');
const cloud=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');

const today=new Date().toISOString().slice(0,10);
function overview(scope='all'){
 const rights=scope==='all'
  ? {view:true,create:true,edit:true,delete:true,validate:true,export:true,close:true,scope:'all'}
  : {view:true,create:false,edit:false,delete:false,validate:false,export:true,close:false,scope:'commercial'};
 return {currency:'USD',country:'EC',scope,rights,today,
  revenue:{month:12000,previous:10000,year:90000},
  expense:{month:7000,previous:7500,year:60000,categories:scope==='all'?[{name:'Alquiler',amount:9000},{name:'Salarios',amount:4000}]:null},
  treasury:scope==='all'?{balance:25000,inflow:9000,outflow:4000,
    accounts:[{id:'fa1',name:'Banco principal',kind:'bank',bank_name:'Banco Pichincha',currency:'USD',
      opening_balance:1000,active:true,current_balance:25000,unmatched:2}]}:null,
  customers:{invoiced:50000,collected:38000,outstanding:12000,overdue:2500,overdue_count:3,avg_delay:6.5},
  suppliers:scope==='all'?{outstanding:8000,overdue:1000,overdue_count:1,due_30:3000}:null,
  taxes:scope==='all'?{collected:1800,deductible:900,from:today,to:today}:null,
  alerts:{unmatched:scope==='all'?2:null,no_receipt:scope==='all'?1:null,unbalanced:scope==='all'?0:null}};
}
const RESPONSES={
 receivables:{total:1,aging:{current:9500,d30:1500,d60:1000,d90:0,older:0,total:12000},
  metrics:{total:50000,paid:38000,balance:12000,overdue:2500},
  rows:[{id:'inv1',number:'FAC-000283',external_number:null,customer_name:'ACME SA',issue_date:'2026-09-01',
   due_date:'2026-09-30',total:2500,paid:1500,balance:1000,days_remaining:-4,payment_status:'overdue'}]},
 payables:{total:1,aging:{current:8000,d30:0,d60:0,d90:0,older:0,total:8000},
  metrics:{total:8000,paid:0,balance:8000,overdue:1000},
  rows:[{id:'sb1',number:'PRV-77',supplier_name:'Suministros SL',issue_date:'2026-09-02',due_date:'2026-10-02',
   total:8000,paid:0,balance:8000,status:'posted',payment_status:'pending'}]},
 expenses:{total:1,sum:55,categories:[{id:'c1',name:'Alquiler'}],
  rows:[{id:'e1',reference:'GA-00000001',expense_date:today,supplier_name:null,category_name:'Alquiler',
   description:'Alquiler septiembre',amount_total:55,amount_untaxed:50,tax_amount:5,status:'draft',has_receipt:false}]},
 accounts:{rows:[{id:'fa1',name:'Banco principal',kind:'bank',bank_name:'Pichincha',currency:'USD',
   opening_balance:1000,active:true,current_balance:25000,unmatched:2}],chart:[{id:'a1',code:'1000',name:'Bancos y caja'}]},
 bank_list:{rows:[{id:'bt1',value_date:today,reference:'TRF-1',description:'Transferencia ACME',amount:1250,
   status:'unmatched',account_name:'Banco principal'}],accounts:[{id:'fa1',name:'Banco principal'}]},
 entries:{rows:[{id:'en1',number:'AS-00000001',entry_date:today,journal_code:'VTA',reference:'FAC-000283',
   memo:'ACME SA',total_debit:2500,total_credit:2500,status:'posted'}],
  journals:[{id:'j1',code:'OD',name:'Operaciones diversas',kind:'misc'}],pending:2},
 taxes:{rows:[{id:'t1',name:'Exento',code:'EXENTO',rate:0,kind:'both',country:null,valid_from:null,active:true}],
  summary:{collected:1800,deductible:900,from:today,to:today}},
 report_pl:{from:today,to:today,income:90000,expense:60000,result:30000,margin:33.33,
  rows:[{type:'income',code:'4000',name:'Ventas',amount:90000},{type:'expense',code:'6050',name:'Alquiler',amount:60000}]},
 report_balance:{as_of:today,result:30000,stock:4000,
  rows:[{type:'asset',code:'1000',name:'Bancos y caja',amount:25000},{type:'liability',code:'2000',name:'Proveedores',amount:8000}]},
 report_cashflow:{from:today,to:today,balance:25000,rows:[{month:'2026-09',in:9000,out:4000,net:5000}]},
 forecast:{balance:25000,forecast:true,horizons:[{days:30,incoming:5000,outgoing:2000},
   {days:60,incoming:8000,outgoing:3000},{days:90,incoming:9000,outgoing:3500}]},
 report_revenue:{from:today,to:today,by_month:[{key:'2026-09',amount:12000}],
  by_customer:[{key:'ACME SA',amount:9000}],by_product:[{key:'Café',amount:5000}]},
 periods:{rows:[{id:'p1',period_start:'2026-09-01',period_end:'2026-09-30',status:'open',entries:12,closed_at:null}]},
 settings:{id:true,currency:'USD',country:'EC',fiscal_year_start_month:1,receivable_account_id:'a1',
  payable_account_id:'a1',sales_account_id:'a1',purchase_account_id:'a1',tax_collected_account_id:'a1',
  tax_deductible_account_id:'a1',accounts:[{id:'a1',code:'1000',name:'Bancos y caja',type:'asset'}]},
 chart:{rows:[{id:'a1',code:'1000',name:'Bancos y caja',type:'asset',active:true,is_system:true}]},
 categories:[{id:'c1',name:'Alquiler',account_id:'a1',sort_order:1,active:true}],
 permissions:[{profile_id:'u1',name:'Ana Torres',email:'ana@example.com',role:'comercial',rights:null}],
 supplier_invoices:{rows:[{id:'sb1',number:'PRV-77',supplier_name:'Suministros SL',issue_date:'2026-09-02',
   due_date:'2026-10-02',total:8000,paid:0,balance:8000,status:'posted',payment_status:'pending'}],
  suppliers:[{id:'s1',name:'Suministros SL'}]},
 entry_lines:[{id:'l1',code:'1100',account:'Clientes',label:'ACME SA',debit:2500,credit:0}],
 expense_receipts:[],sync:{posted:0}
};

async function boot(page,scope='all',role='admin'){
 await page.addInitScript(({scope,role,overview,RESPONSES})=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Contable'}));
  localStorage.removeItem('gama_company_currency_v1');
  window.__DB={products:[],customers:[],suppliers:[],profiles:[],app_modules:[],invoices:[],
   company_settings:[{id:true,currency:'USD',country:'EC'}]};
  window.__ACC={overview,responses:RESPONSES,calls:[],error:null,scope};
 },{scope,role,overview:overview(scope),RESPONSES});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));
 await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');
 await page.waitForFunction(()=>window.GamaAccounting&&window.GamaCloud&&window.GamaCurrency);
 await page.evaluate(async()=>{
  await GamaCloudReady;const old=GamaCloud.db;
  GamaCloud.db=async()=>{const c=await old();return{...c,rpc:async(fn,args)=>{
   if(fn!=='gama_accounting_action')return c.rpc(fn,args);
   window.__ACC.calls.push(args);
   if(window.__ACC.error)return {error:{message:window.__ACC.error}};
   if(args.p_action==='overview')return {data:window.__ACC.overview};
   const r=window.__ACC.responses[args.p_action];
   return {data:r===undefined?{ok:true,id:'new'}:structuredClone(r)};
  }}};
 });
}
const open=page=>page.evaluate(()=>GamaAccounting.open());

test('the dashboard reads the whole business and formats in the company currency',async({page})=>{
 await boot(page);await open(page);
 await expect(page.locator('#accounting')).toBeVisible();
 const main=page.locator('#gaMain');
 await expect(main).toContainText('$12.000,00');        // ingresos del mes
 await expect(main).toContainText('$5.000,00');         // resultado del mes 12000-7000
 await expect(main).toContainText('$25.000,00');        // tesorería
 await expect(main).toContainText('$12.000,00');        // pendiente de cobro
 await expect(main).toContainText('+20 %');             // 12000 vs 10000
 await expect(main).toContainText('6,5');               // retraso medio
 await expect(main).toContainText('$900,00');           // saldo de impuestos 1800-900
 await expect(page.locator('#gaNav button')).toHaveCount(13);
});

test('a euro company shows euros everywhere without touching the amounts',async({page})=>{
 await boot(page);await open(page);
 await expect(page.locator('#gaMain')).toContainText('$12.000,00');
 await page.evaluate(()=>GamaCurrency.set('EUR'));
 await expect(page.locator('#gaMain')).toContainText('€12.000,00');
 await expect(page.locator('#gaMain')).not.toContainText('$12.000,00');
});

test('receivables answer who owes us money and age the balance',async({page})=>{
 await boot(page);await open(page);
 await page.locator('[data-ga-section="receivables"]').click();
 const main=page.locator('#gaMain');
 await expect(main).toContainText('ACME SA');
 await expect(main).toContainText('FAC-000283');
 await expect(main).toContainText('$2.500,00');   // total
 await expect(main).toContainText('$1.500,00');   // pagado
 await expect(main).toContainText('$1.000,00');   // restante
 await expect(main).toContainText('4 ');          // días de retraso
 await expect(main.locator('.gaBadge[data-s="overdue"]')).toBeVisible();
 await expect(main.locator('.gaAging div')).toHaveCount(5);
});

test('payment status follows the balance from unpaid to partial to paid',async({page})=>{
 await boot(page);
 await page.evaluate(()=>{window.__ACC.responses.payables.rows=[
  {id:'a',number:'F-1',supplier_name:'Uno',issue_date:'2026-09-01',due_date:'2026-10-01',total:1000,paid:0,balance:1000,status:'posted',payment_status:'pending'},
  {id:'b',number:'F-2',supplier_name:'Dos',issue_date:'2026-09-01',due_date:'2026-10-01',total:1000,paid:400,balance:600,status:'posted',payment_status:'partial'},
  {id:'c',number:'F-3',supplier_name:'Tres',issue_date:'2026-09-01',due_date:'2026-10-01',total:1000,paid:1000,balance:0,status:'posted',payment_status:'paid'}]});
 await open(page);
 await page.locator('[data-ga-section="payables"]').click();
 const rows=page.locator('#gaMain tbody tr');
 await expect(rows.nth(0)).toContainText('No pagada');
 await expect(rows.nth(1)).toContainText('Pago parcial');
 await expect(rows.nth(1)).toContainText('$600,00');
 await expect(rows.nth(2)).toContainText('Pagada');
 // only the lines that still owe something offer a payment button
 await expect(page.locator('[data-ga-pay]')).toHaveCount(2);
});

test('an expense is captured once and its total is computed for the operator',async({page})=>{
 await boot(page);await open(page);
 await page.locator('[data-ga-section="expenses"]').click();
 await expect(page.locator('#gaMain')).toContainText('GA-00000001');
 await expect(page.locator('#gaMain')).toContainText('Falta');   // sin justificante
 await page.locator('#gaNewExpense').click();
 await page.locator('#gaUntaxed').fill('200');
 await page.locator('#gaTax').fill('30');
 await expect(page.locator('#gaTotal')).toHaveValue('230.00');
 await page.locator('#gaDescription').fill('Servidor anual');
 await page.locator('#gsSave').click();
 await expect(page.locator('dialog')).toHaveCount(0);
 const call=await page.evaluate(()=>window.__ACC.calls.find(c=>c.p_action==='expense_save'));
 expect(call.p_data).toMatchObject({description:'Servidor anual',amount_untaxed:200,tax_amount:30,amount_total:230});
 expect(call.p_data.request_key).toBeTruthy();
});

test('a manual entry cannot be sent while debit and credit differ',async({page})=>{
 await boot(page);await open(page);
 await page.locator('[data-ga-section="ledger"]').click();
 await page.locator('#gaNewEntry').click();
 const dialog=page.locator('dialog');
 await dialog.locator('.gaLineDebit').first().fill('100');
 await expect(dialog.locator('#gaBalance')).toContainText('Descuadrado');
 await dialog.locator('.gaLineCredit').nth(1).fill('100');
 await expect(dialog.locator('#gaBalance')).toContainText('Cuadrado');
 await dialog.locator('.gaLineAccount').first().selectOption({index:1});
 await dialog.locator('.gaLineAccount').nth(1).selectOption({index:1});
 await page.locator('#gsSave').click();
 await expect(page.locator('dialog')).toHaveCount(0);
 const call=await page.evaluate(()=>window.__ACC.calls.find(c=>c.p_action==='entry_manual'));
 expect(call.p_data.lines).toHaveLength(2);
 expect(call.p_data.lines[0].debit).toBe(100);
 expect(call.p_data.lines[1].credit).toBe(100);
});

test('the forecast is labelled a forecast and never presented as a fact',async({page})=>{
 await boot(page);await open(page);
 await page.locator('[data-ga-section="reports"]').click();
 const main=page.locator('#gaMain');
 await expect(main).toContainText('Cuenta de resultados');
 await expect(main).toContainText('$30.000,00');
 await expect(main).toContainText('Previsión, no un hecho.');
 await expect(main).toContainText('30 días (previsión)');
 await expect(main.locator('.gaForecast')).toBeVisible();
 await expect(main).toContainText('No sustituye a las cuentas anuales');
});

test('tax and balance screens never claim to be a legal filing',async({page})=>{
 await boot(page);await open(page);
 await page.locator('[data-ga-section="taxes"]').click();
 await expect(page.locator('#gaMain')).toContainText('No constituye una declaración fiscal');
 await expect(page.locator('#gaMain')).toContainText('el sistema que exija tu país');
});

test('a commercial profile sees its own side and never the ledger or the cash',async({page})=>{
 await boot(page,'commercial','commercial');await open(page);
 const nav=page.locator('#gaNav button');
 await expect(nav).toHaveCount(4);
 await expect(nav).toHaveText(['Vista general','Ventas','Cuentas por cobrar','Informes']);
 await expect(page.locator('[data-ga-section="ledger"]')).toHaveCount(0);
 await expect(page.locator('[data-ga-section="cash"]')).toHaveCount(0);
 await expect(page.locator('#gaMain')).not.toContainText('Tesorería');
 await expect(page.locator('#gaMain')).not.toContainText('Impuesto recaudado');
 // and the module never asks the server for what it may not see
 await page.locator('[data-ga-section="reports"]').click();
 const asked=await page.evaluate(()=>window.__ACC.calls.map(c=>c.p_action));
 expect(asked).not.toContain('report_balance');
 expect(asked).not.toContain('forecast');
});

test('a server refusal is explained, not dumped as a database error',async({page})=>{
 await boot(page);await open(page);
 await page.evaluate(()=>window.__ACC.error='PERIOD_CLOSED');
 await page.locator('[data-ga-section="expenses"]').click();
 await expect(page.locator('#gaMain')).toContainText('El periodo contable está cerrado');
 await expect(page.locator('#gaMain')).not.toContainText('PERIOD_CLOSED');
 await page.evaluate(()=>window.__ACC.error=null);
 await page.locator('#gaRetry').click();
 await expect(page.locator('#gaMain')).toContainText('GA-00000001');
});

test('the bank import reads a CSV before sending anything',async({page})=>{
 await boot(page);await open(page);
 await page.locator('[data-ga-section="cash"]').click();
 await expect(page.locator('#gaMain')).toContainText('Transferencia ACME');
 await page.locator('#gaImport').click();
 await page.locator('#gaCsv').setInputFiles({name:'extracto.csv',mimeType:'text/csv',
  buffer:Buffer.from('fecha;referencia;descripcion;importe\n01/09/2026;TRF-9;Pago ACME;1.250,00\n02/09/2026;TRF-10;Alquiler;-800,00\n')});
 await expect(page.locator('#gaPreview')).toContainText('2');
 await expect(page.locator('#gaPreview')).toContainText('$1.250,00');
 await expect(page.locator('#gaPreview')).toContainText('$-800,00');
 await page.locator('#gsSave').click();
 const call=await page.evaluate(()=>window.__ACC.calls.find(c=>c.p_action==='bank_import'));
 expect(call.p_data.rows).toEqual([
  {value_date:'2026-09-01',reference:'TRF-9',description:'Pago ACME',amount:1250},
  {value_date:'2026-09-02',reference:'TRF-10',description:'Alquiler',amount:-800}]);
});

test('the module reads in French and in English',async({page})=>{
 await boot(page);await open(page);
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));
 await expect(page.locator('#gaNav')).toContainText('Vue d’ensemble');
 await expect(page.locator('#gaMain')).toContainText('Trésorerie');
 await expect(page.locator('#gaMain')).toContainText('Retard moyen de paiement');
 await page.evaluate(()=>GamaI18n.setLanguage('en'));
 await expect(page.locator('#gaNav')).toContainText('Overview');
 await expect(page.locator('#gaMain')).toContainText('Average payment delay');
 await page.evaluate(()=>GamaI18n.setLanguage('es'));
 await expect(page.locator('#gaNav')).toContainText('Vista general');
});

for(const [label,width,height] of [['mobile',390,844],['tablet-portrait',768,1024],['tablet-landscape',1024,768],['desktop',1440,900]]){
 test(`the module fits ${label} without a horizontal scroll`,async({page})=>{
  await page.setViewportSize({width,height});
  await boot(page);await open(page);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await page.locator('[data-ga-section="receivables"]').click();
  await expect(page.locator('#gaMain .gaTable')).toBeVisible();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await page.screenshot({path:`test-results/accounting-${label}.png`,fullPage:false});
 });
}

test('accounting is in Administration and closed to clients',async({page})=>{
 await boot(page);
 await page.evaluate(()=>showTab('mainmenu'));
 await expect(page.locator('.gamaF2Card[data-gama-module="accounting"]')).toBeVisible();
 await page.locator('.gamaF2Card[data-gama-module="accounting"]').click();
 await expect(page.locator('#accounting')).toBeVisible();
 await page.evaluate(()=>{showTab('mainmenu');localStorage.setItem('gama_session_v1',JSON.stringify({role:'client'}));
  GamaAccounting.open()});
 await expect(page.locator('#accounting.active')).toHaveCount(0);
});
