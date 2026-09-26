const {test,expect}=require('@playwright/test');
const fs=require('node:fs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
async function boot(page,width=1440){
 await page.setViewportSize({width,height:900});
 await page.addInitScript(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({userId:'column-user',role:'admin',name:'QA'}));localStorage.setItem('gama_language_v1','fr');window.__DB={products:Array.from({length:25},(_,i)=>({id:'p'+i,barcode:'P'+i,name:'Produit '+i,brand:'Marque '+String(24-i).padStart(2,'0'),purchase_price:i+.5,sale_price:i*2,tax_rate:15,stock:i,active:true,supplier_id:'s'+i})),customers:[],invoices:[],invoice_lines:[],profiles:[],suppliers:Array.from({length:25},(_,i)=>({id:'s'+i,name:'Fournisseur '+i,active:true,phone:String(1000+i),email:`contact${i}@example.invalid`,city:'Ville '+i}))}});
 await page.route('https://**/*',r=>r.abort());await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaTable&&window.ArcUI);
}
async function fixture(page){await page.evaluate(()=>{
 const host=document.createElement('div');host.id='sortFixture';document.querySelector('#mainmenu').append(host);
 host.innerHTML='<table><thead><tr><th>Nom</th><th>Montant</th><th>Date</th><th>Quantité</th><th>Actions</th></tr></thead><tbody><tr data-id="a"><td>Alpha</td><td>1 200,50 €</td><td>31/01/2026</td><td><input type="number" value="10"></td><td><button>Ouvrir Alpha</button></td></tr><tr data-id="b"><td>Bêta</td><td>-2,50 €</td><td>02/02/2026</td><td><input type="number" value="2"></td><td><button>Ouvrir Bêta</button></td></tr><tr data-id="c"><td>Gamma</td><td>12,50 €</td><td>03/12/2025</td><td><input type="number" value="3"></td><td><button>Ouvrir Gamma</button></td></tr><tr data-id="d"><td>Vide</td><td>—</td><td>—</td><td></td><td></td></tr></tbody><tfoot><tr><td colspan="5">Total</td></tr></tfoot></table>';
 host.querySelector('tbody button').onclick=()=>window.__opened='a';GamaTable.scan(host);
 });}
const order=page=>page.locator('#sortFixture tbody tr').evaluateAll(rows=>rows.map(r=>r.dataset.id));
test('sorts amounts, dates and inputs without losing actions; restores original order',async({page})=>{
 await boot(page);await fixture(page);const host=page.locator('#sortFixture');
 await host.getByLabel('Trier par',{exact:true}).selectOption({label:'Montant'});expect(await order(page)).toEqual(['b','c','a','d']);
 await host.getByLabel('Ordre',{exact:true}).selectOption('desc');expect(await order(page)).toEqual(['a','c','b','d']);
 await host.getByLabel('Trier par',{exact:true}).selectOption({label:'Date'});expect(await order(page)).toEqual(['b','a','c','d']);
 await host.getByLabel('Ordre',{exact:true}).selectOption('asc');expect(await order(page)).toEqual(['c','a','b','d']);
 await host.getByLabel('Trier par',{exact:true}).selectOption({label:'Quantité'});expect(await order(page)).toEqual(['b','c','a','d']);
 await host.getByRole('button',{name:'Ouvrir Alpha'}).click();expect(await page.evaluate(()=>window.__opened)).toBe('a');
 await host.getByLabel('Trier par',{exact:true}).selectOption('');expect(await order(page)).toEqual(['a','b','c','d']);
 await expect(host.locator('tfoot')).toHaveText('Total');await expect(host.locator('.gamaTableToolbar')).toHaveCount(1);
});
test('column visibility persists across render and language, is isolated by user, and works on mobile cards',async({page})=>{
 await boot(page,390);await fixture(page);const host=page.locator('#sortFixture');
 await host.locator('summary').click();await host.getByRole('checkbox',{name:'Nom',exact:true}).uncheck();await host.getByRole('checkbox',{name:'Montant',exact:true}).uncheck();
 await expect(host.locator('tbody tr').first().locator('td').nth(0)).toBeHidden();await expect(host.locator('tbody tr').first().locator('td').nth(2)).toHaveAttribute('data-gama-title','');
 await host.locator('[data-table-view=table]').click();await expect(host.locator('thead th').nth(0)).toBeHidden();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.evaluate(()=>document.getElementById('sortFixture').remove());await fixture(page);
 await expect(host.locator('tbody tr').first().locator('td').nth(0)).toBeHidden();await expect(host.locator('tfoot td')).toHaveAttribute('colspan','3');
 await page.evaluate(()=>GamaI18n.setLanguage('en'));await expect(host.getByLabel('Sort by',{exact:true})).toBeVisible();
 await host.locator('summary').click();await host.getByRole('button',{name:'Show all'}).click();await expect(host.locator('tfoot td')).toHaveAttribute('colspan','5');
 for(const name of ['Nom','Montant','Date','Quantité'])await host.getByRole('checkbox',{name,exact:true}).uncheck();
 await expect(host.getByRole('checkbox',{name:'Actions',exact:true})).toBeDisabled();
 await page.evaluate(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({userId:'another-user',role:'admin'}));window.dispatchEvent(new Event('gama:auth-change'))});
 await expect(host.locator('[data-gama-column-hidden]')).toHaveCount(0);
 await page.screenshot({path:'test-results/table-controls-mobile.png',fullPage:true});
});
test('sorts all contacts before pagination, keeps hidden columns after page changes, and persists after reload',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));const host=page.locator('#ctTable');await expect(host.locator('tbody tr')).toHaveCount(20);
 await host.getByLabel('Trier par',{exact:true}).selectOption({label:'Téléphone'});await host.getByLabel('Ordre',{exact:true}).selectOption('desc');
 await expect(host.locator('tbody tr').first()).toContainText('1024');
 await host.locator('summary').click();await host.getByRole('checkbox',{name:'Téléphone',exact:true}).uncheck();
 await host.locator('[data-arc-page="1"]').click();await expect(host.locator('tbody tr')).toHaveCount(5);await expect(host.locator('tbody tr').first()).toContainText('1004');
 await expect(host.locator('tbody tr').first().locator('td').nth(3)).toBeHidden();
 await host.locator('[data-ct-edit]').first().click();await expect(page.locator('#ctf-name')).toHaveValue('Fournisseur 4');
 await page.reload();await page.waitForFunction(()=>window.ArcRouter);await page.evaluate(()=>ArcRouter.open('contacts'));
 await expect(host.locator('tbody tr').first()).toContainText('1024');await expect(host.locator('[data-table-direction]')).toHaveValue('desc');await expect(host.locator('tbody tr').first().locator('td').nth(3)).toBeHidden();
});
test('product server sorting includes all data columns and sorts beyond the first page',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('products'));const host=page.locator('#productsTable');await expect(host.locator('tbody tr')).toHaveCount(20);
 const options=await host.locator('[data-table-sort] option').allTextContents();expect(options).toHaveLength(11);
 await host.locator('[data-table-sort]').selectOption('5');await host.locator('[data-table-direction]').selectOption('desc');await expect(host.locator('tbody tr').first()).toContainText('Produit 24');
 await host.locator('[data-arc-page="1"]').click();await expect(host.locator('tbody tr')).toHaveCount(5);await expect(host.locator('tbody tr').first()).toContainText('Produit 4');
 await host.locator('[data-table-sort]').selectOption('3');await expect(host.locator('tbody tr')).toHaveCount(20);await expect(host.locator('tbody tr').first()).toContainText('Marque 24');
 await host.locator('summary').click();await host.getByRole('checkbox',{name:'Stock',exact:true}).uncheck();await expect(host.locator('tbody tr').first().locator('td').nth(4)).toBeHidden();
 await host.locator('[data-table-sort]').selectOption('10');await expect(host.locator('tbody tr').first()).toContainText('Produit 24');
});
test('legacy paginated sort applies to the complete dataset and preserves independent table settings',async({page})=>{
 await boot(page);await page.evaluate(()=>{
 const host=document.createElement('div');host.id='pagedFixture';document.querySelector('#mainmenu').append(host);
 const rows=Array.from({length:25},(_,i)=>({name:'Row '+i,n:i}));
 const render=()=>{host.innerHTML='<table data-gama-sort-key="fixture"><thead><tr><th>Nom</th><th>Nombre</th></tr></thead><tbody>'+GamaPage.slice('fixture',rows,{0:r=>r.name,1:r=>r.n}).map(r=>`<tr><td>${r.name}</td><td>${r.n}</td></tr>`).join('')+'</tbody></table>'+GamaPage.controls('fixture',rows.length);GamaTable.scan(host)};GamaPage.register('fixture',render);render();
 });
 const host=page.locator('#pagedFixture');await host.locator('[data-table-sort]').selectOption('1');await host.locator('[data-table-direction]').selectOption('desc');await expect(host.locator('tbody tr').first()).toHaveText('Row 2424');
 await host.locator('[data-page-next]').click();await expect(host.locator('tbody tr').first()).toHaveText('Row 44');
 await host.locator('[data-table-direction]').selectOption('asc');await expect(host.locator('tbody tr')).toHaveCount(20);await expect(host.locator('tbody tr').first()).toHaveText('Row 00');
 await fixture(page);await expect(page.locator('#sortFixture [data-table-sort]')).toHaveValue('');
});
