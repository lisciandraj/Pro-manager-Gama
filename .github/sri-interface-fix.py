from pathlib import Path

def replace(path, before, after):
    p=Path(path)
    s=p.read_text()
    assert s.count(before)==1, (path,s.count(before),before[:50])
    p.write_text(s.replace(before,after))

replace('src/features/finance/accounting.js',
    'async function openSri(sourceInvoiceId){\n if(!allowed()',
    "async function openSri(sourceInvoiceId){\n if(sourceInvoiceId&&typeof sourceInvoiceId==='object')sourceInvoiceId=sourceInvoiceId.invoiceId||null;\n if(!allowed()")
replace('src/features/finance/accounting.js',
    'Emisión desactivada. Configura el servicio privado y valida las pruebas antes de enviar.',
    'Emisión SRI desactivada. Falta configurar el servicio de firma, el certificado y validar las pruebas SRI. Puedes guardar la configuración.')
replace('src/features/finance/accounting.js',
    "const permitted=action=>action==='prepare'?rights?.create:",
    "const permitted=action=>action==='prepare'?(rights?.create&&!!d.settings?.provider_ruc):")
replace('tests/mock-gama-cloud.js', 'let readMode=false;', 'let readMode=false,readRange=null,readCount=false;')
replace('tests/mock-gama-cloud.js',
    'select: () => {readMode=true;return chain},',
    "select: (_columns,options={}) => {readMode=true;readCount=!!options.count;return chain},\n          range: (from,to) => {readRange=[from,to];return chain},")
replace('tests/mock-gama-cloud.js',
    "if(readMode)return Promise.resolve({data:JSON.parse(JSON.stringify((window.__DB[table]||[]).filter(r=>filters.every(([c,v,many])=>many?v.includes(r[c]):r[c]===v)).sort((a,b)=>{for(const [col,asc] of orders){const n=String(a[col]??'').localeCompare(String(b[col]??''));if(n)return asc?n:-n}return 0}))),error:null}).then(resolve);",
    """if(readMode){
              const rows=(window.__DB[table]||[]).filter(r=>filters.every(([c,v,many])=>many?v.includes(r[c]):r[c]===v)).sort((a,b)=>{for(const [col,asc] of orders){const n=String(a[col]??'').localeCompare(String(b[col]??''));if(n)return asc?n:-n}return 0});
              const data=readRange?rows.slice(readRange[0],readRange[1]+1):rows;
              return Promise.resolve({data:JSON.parse(JSON.stringify(data)),...(readCount?{count:rows.length}:{}),error:null}).then(resolve);
            }""")
replace('tests/accounting.spec.js',
    "await expect(page.locator('[data-ga-sri=prepare]')).toBeDisabled();\n await page.locator('#gaSriSave').click();",
    "await expect(page.locator('[data-ga-sri=prepare]')).toBeDisabled();\n await page.locator('#gaMain details summary').click();\n await page.locator('#gaSriSave').click();")
p=Path('tests/sri-integration.spec.js')
p.write_text(p.read_text()+'''

test('payment details open the exact fiscal invoice without posting a payment',async({page})=>{
 await boot(page);await page.evaluate(async()=>{
  const old=GamaCloud.db;
  GamaCloud.db=async()=>{const c=await old();return {...c,rpc:async(fn,args)=>{
   if(fn==='gama_payment_action'){
    __SRI.calls.push({fn,...args});
    if(args.p_action!=='detail')throw Error('Unexpected payment mutation');
    return {data:{...__DB.external_invoices[0],customer_name:'Cliente',identification:'1712345678',customer_id:'c1',email:'',payment_status:'pending',paid:0,balance:115,lines:[],payments:[]}};
   }
   return c.rpc(fn,args);
  }}};
  await GamaPayments.open({invoiceId:__DB.external_invoices[0].id});
 });
 await expect(page.locator('#gpSri')).toBeVisible();await page.locator('#gpSri').click();
 await expect(page.locator('#sri')).toBeVisible();await expect(page.locator('#gaMain')).toContainText('FAC-00000001');
 expect(await page.evaluate(()=>__SRI.calls.some(c=>c.fn==='gama_payment_action'&&c.p_action!=='detail'))).toBe(false);
});
''')
