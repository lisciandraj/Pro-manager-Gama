const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const bridge=`
(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();const prev=c.rpc;return {...c,rpc:async(fn,args)=>{
 if(fn==='gama_receipt_action'&&args.p_action==='context')return {data:{accounts:[{id:'bank-1',name:'Bank QA',currency:'USD'}],receipts:[],followups:[]}};
 if(fn!=='gama_payment_action')return prev(fn,args);
 __paymentCalls.push(args);if(window.__payError)return {error:{message:'NETWORK'}};
 const r=__receivable;
 if(args.p_action==='list')return {data:{total:1,metrics:{total:r.total,paid:r.paid,balance:r.balance,due_soon:r.payment_status==='due_soon'?r.balance:0,overdue:r.payment_status==='overdue'?r.balance:0},rows:[r]}};
 if(args.p_action==='reminder'&& !['due_soon','overdue'].includes(r.payment_status))return {error:{message:'REMINDER_NOT_DUE'}};
 if(args.p_action==='payment'){r.payments.push({id:'pay1',...args.p_data,status:'confirmed'});r.paid=Number(args.p_data.amount);r.balance=r.total-r.paid;r.payment_status=r.balance?'due_soon':'paid';return {data:{id:'pay1'}}}
 if(args.p_action==='cancel_payment'){r.payments[0].status='cancelled';r.payments[0].cancellation_reason=args.p_data.reason;r.paid=0;r.balance=r.total;r.payment_status='overdue';return {data:{id:'pay1'}}}
 return {data:r};}}};})();`;
async function boot(page,role='admin'){
 await page.addInitScript(role=>{localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'QA'}));window.__DB={products:[],customers:[{id:'c1',name:'Cliente Andes',identification:'123456',email:'cliente@example.invalid',payment_terms_days:30}],suppliers:[],invoices:[],invoice_lines:[],purchase_orders:[],purchase_order_lines:[]};window.__paymentCalls=[];window.__receivable={id:'i1',order_id:'o1',number:'FAC-123',external_number:'SRI-456',order_number:'CMD-123',document_kind:'internal',customer_id:'c1',customer_name:'Cliente Andes',identification:'123456',email:'cliente@example.invalid',issue_date:'2026-09-01',payment_delivery_date:'2026-08-20',payment_terms_days:30,due_date:'2026-09-19',subtotal:100,tax:15,total:115,paid:0,balance:115,payment_status:'due_soon',lines:[{name:'Producto A',reference:'REF-A',quantity:10,unit_price:10,tax_rate:15}],payments:[]};},role);
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+bridge}));await page.route('**/@supabase/**',r=>r.abort());await page.goto('/index.html');await page.waitForTimeout(1500);
}
test('payment module shows invoice content, records partial payment and retains cancelled payment',async({page})=>{
 // Las facturas son la pestaña Facturas de Presupuestos y facturas.
 await boot(page);await page.locator('#mainmenu [data-gama-module="quotes"]').click();await page.locator('#gqInvoicesTab').click();await expect(page.locator('#gpMain')).toContainText('FAC-123');await expect(page.locator('.gpBadge')).toHaveAttribute('data-state','due_soon');
 await page.locator('[data-gp-detail]').click();await expect(page.locator('#gpMain')).toContainText('Producto A');await expect(page.locator('#gpMain')).toContainText('2026-08-20');await page.locator('#gpPay').click();await page.locator('#gpAmount').fill('40');await page.locator('#gpReference').fill('BANK-123');await page.locator('#gpAccount').selectOption('bank-1');await page.locator('dialog #gsSave').click();await expect(page.locator('#gpMain')).toContainText('BANK-123');expect(await page.evaluate(()=>__paymentCalls.find(c=>c.p_action==='payment').p_data.amount)).toBe(40);
 await page.locator('[data-gp-cancel]').click();await page.locator('#gpReason').fill('Transferencia devuelta');await page.locator('dialog #gsSave').click();await expect(page.locator('#gpMain')).toContainText('Transferencia devuelta');await expect(page.locator('.gpBadge')).toHaveAttribute('data-state','overdue');
});
test('both reminder templates use the current customer, dates and balance and never claim to have sent',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaPayments.open());await page.locator('[data-gp-remind]').click();await expect(page.locator('#gamaMailTo')).toHaveValue('cliente@example.invalid');await expect(page.locator('#gamaMailSubject')).toHaveValue(/próximo vencimiento/);await expect(page.locator('#gamaMailBody')).toHaveValue(/2026-09-19/);await page.locator('#gamaMailClose').click();
 await page.evaluate(()=>{__receivable.payment_status='overdue';__receivable.paid=40;__receivable.balance=75});await page.locator('[data-gp-remind]').click();await expect(page.locator('#gamaMailSubject')).toHaveValue(/pago vencido/);await expect(page.locator('#gamaMailBody')).toHaveValue(/75/);await page.locator('#gamaMailClose').click();
 await page.evaluate(()=>{__receivable.payment_status='paid';__receivable.balance=0});await page.locator('[data-gp-remind]').click();await expect(page.locator('#gamaMailTo')).toHaveCount(0);await expect(page.locator('#gamaToasts')).toContainText('ya no requiere');
});
test('client terms are loaded and saved centrally, including zero days',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaPayments.open({invoiceId:'i1'}));await page.locator('#gpCustomer').click();await expect(page.locator('#ctf-terms')).toHaveValue('30');await page.locator('#ctf-terms').fill('0');await page.locator('#ctSave').click();await expect.poll(()=>page.evaluate(()=>__DB.customers[0].payment_terms_days)).toBe(0);await page.evaluate(()=>editClient('123456'));await expect(page.locator('#ctf-terms')).toHaveValue('0');
});
test('notifications open the exact payment and expose an orange or red reminder',async({page})=>{
 await boot(page);await page.evaluate(async()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:async(fn,args)=>fn==='gama_operations_action'?{data:{finance:true,warehouse:true,from:'2026-09-01',to:'2026-09-13',generated_at:new Date().toISOString(),active_count:1,total:1,counts:{due_soon_invoice:1},alerts:[{target:'invoice',target_id:'i1',kind:'due_soon_invoice',priority:2,title:'Pago próximo a vencer',reference:'FAC-123',customer:'Cliente Andes',detail:'Vencimiento: 2026-09-19',handling:'open'}]}}:c.rpc(fn,args)}};await GamaOperations.open('notifications')});
 await expect(page.locator('#goAlerts article')).toHaveAttribute('data-priority','2');await page.locator('[data-go-action]').click();await expect(page.locator('#gamaMailSubject')).toHaveValue(/próximo vencimiento/);await page.locator('#gamaMailClose').click();await page.locator('[data-go-open]').click();await expect(page.locator('#payments.active')).toBeVisible();await expect(page.locator('#gpMain h2')).toHaveText('FAC-123');
});
test('mobile layout, French labels, missing email and failed reads are explicit',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.evaluate(()=>GamaPayments.open({invoiceId:'i1'}));expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);await page.evaluate(()=>GamaI18n.setLanguage('fr'));await expect(page.locator('#payments')).toContainText('Devis et facture');await expect(page.locator('#payments #gqInvoicesTab')).toHaveAttribute('aria-selected','true');await page.screenshot({path:'test-results/payments-mobile.png',fullPage:true});
 await page.evaluate(()=>__receivable.email='');await page.locator('[data-gp-remind]').click();await expect(page.locator('#gamaMailTo')).toHaveCount(0);
 await page.evaluate(()=>__payError=true);await page.locator('#gpDetailRefresh').click();await expect(page.locator('#gpMain [role=alert]')).toBeVisible();
});
test('clients and warehouse users cannot open or fetch payments; disabled module is respected',async({page})=>{
 await boot(page,'client');await page.evaluate(()=>GamaPayments.open());expect(await page.evaluate(()=>__paymentCalls.length)).toBe(0);await expect(page.locator('#payments')).toHaveCount(0);
 await page.evaluate(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'magasinier'}));GamaPayments.open()});expect(await page.evaluate(()=>__paymentCalls.length)).toBe(0);
 await page.evaluate(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin'}));GamaModules.enabled=id=>id!=='payments';GamaPayments.open()});expect(await page.evaluate(()=>__paymentCalls.length)).toBe(0);
});
