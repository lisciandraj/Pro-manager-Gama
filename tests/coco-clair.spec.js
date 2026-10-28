const {test,expect}=require('@playwright/test');
const fs=require('node:fs');
const {isolateLocalPage}=require('./local-browser-fixture.cjs');
const cloud=['mock-gama-cloud.js','mock-dashboard.js','mock-service-documents.js'].map(f=>fs.readFileSync(__dirname+'/'+f,'utf8')).join('\n');
test.use({serviceWorkers:'block'});
async function boot(page){
 await isolateLocalPage(page);
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Clair QA'}));
  localStorage.setItem('gama_tms_migrated_v1','1');
  window.__DB={products:[{id:'p1',name:'Papier A4',reference:'A4',barcode:'B1',stock:40,min_stock:10,sale_price:12,active:true}],customers:[{id:'c1',name:'Costa Azul',active:true,city:'Quito'}],suppliers:[],profiles:[],invoices:[],invoice_lines:[],sales_orders:[],sales_order_lines:[],purchase_orders:[],purchase_order_lines:[]};
 });
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));
 await page.goto('/index.html');await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central'&&window.gamaAccessAllowed?.('products'));
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));
}
async function products(page){await page.evaluate(()=>ArcRouter.open('products'));await expect(page.locator('#productsTable tbody tr')).toHaveCount(1);}
const visibleHeaders=page=>page.locator('#productsTable thead th:visible').count();
test('compact product list retains every column, row action and explicit personal choice',async({page})=>{
 await page.setViewportSize({width:1440,height:900});await boot(page);await products(page);
 const headers=page.locator('#productsTable thead th'),total=await headers.count();expect(total).toBeGreaterThan(25);
 expect(await visibleHeaders(page)).toBe(8); // Six business fields, photo and actions.
 await expect(page.locator('#productsTable [data-edit=p1]')).toBeVisible();
 await page.locator('#productsTable .gamaColumnHeading').click();
 await page.locator('#productsTable [data-table-column=min_stock]').check();
 await expect(page.locator('#productsTable th[data-column-key=min_stock]')).toBeVisible();
 await page.reload();await page.waitForFunction(()=>window.gamaAccessAllowed?.('products'));await products(page);
 await expect(page.locator('#productsTable th[data-column-key=min_stock]')).toBeVisible();
 await page.locator('#productsTable .gamaColumnHeading').click();
 await page.locator('#productsTable .gamaColumnOptions').getByRole('button',{name:'Tout afficher',exact:true}).click();
 expect(await visibleHeaders(page)).toBe(total);
 await page.setViewportSize({width:390,height:844});
 await expect(page.locator('#productsTable table')).toHaveAttribute('data-gama-view','cards');
 await page.locator('#productsTable [data-table-view=table]').click();
 await page.evaluate(()=>ArcDirectories.directory('products'));
 await expect(page.locator('#productsTable table')).toHaveAttribute('data-gama-view','table');
});
test('product details open only for creation or edit, and Back preserves data and focus',async({page})=>{
 await boot(page);await products(page);await expect(page.locator('#cocoProductForm')).toBeHidden();
 await page.locator('#cocoNewProduct').click();await expect(page.locator('#pName')).toBeFocused();
 await expect(page.locator('.cocoProductCatalog')).toBeHidden();
 await page.locator('#pName').fill('Brouillon conservé');await page.locator('#cocoProductClose').click();
 await expect(page.locator('.cocoProductCatalog')).toBeVisible();await expect(page.locator('#cocoNewProduct')).toBeFocused();
 await expect(page.locator('#pName')).toHaveValue('Brouillon conservé');
 await page.locator('#productsTable [data-edit=p1]').click();await expect(page.locator('#cocoProductForm')).toBeVisible();
 await expect(page.locator('#pBarcode')).toHaveValue('B1');await expect(page.locator('#pPrice')).toHaveValue('12');
 await page.locator('#cocoProductClose').click();await expect(page.locator('#productsTable [data-edit=p1]')).toBeVisible();
});
test('history opens on demand and gives its width back to the working list',async({page})=>{
 await page.setViewportSize({width:1440,height:900});await boot(page);await products(page);
 const history=page.locator('.cocoGlobalHistory>.cocoFollowup');await expect(history).toBeVisible();
 await expect(history).not.toHaveAttribute('open','');const closed=(await page.locator('#products').boundingBox()).width;
 await history.locator(':scope>summary').click();await expect(history).toHaveAttribute('open','');
 const open=(await page.locator('#products').boundingBox()).width;expect(closed-open).toBeGreaterThan(250);
 await expect(history.locator('[data-filter=actions]')).toBeVisible();
 await history.locator(':scope>summary').click();expect((await page.locator('#products').boundingBox()).width).toBeCloseTo(closed,0);
});
test('phone records keep named fields while editable business lines retain a table',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await products(page);
 await expect(page.locator('#productsTable table')).toHaveAttribute('data-gama-view','cards');
 const labels=await page.locator('#productsTable tbody td[data-col]:not([data-gama-column-hidden])').evaluateAll(cells=>cells.map(c=>c.dataset.col).filter(Boolean));
 expect(labels).toEqual(expect.arrayContaining(['Produit','Référence','Stock','Vente A','Statut']));
 await page.evaluate(()=>{const host=document.createElement('div');host.id='clair-lines';document.querySelector('#products').append(host);ArcUI.render(host,ArcUI.table({columns:[{key:'name',label:'Producto'},{label:'Cantidad',html:()=>'<input type="number" aria-label="Cantidad" value="2">'}],items:[{name:'Papier A4'}]}));});
 await expect(page.locator('#clair-lines table')).toHaveAttribute('data-gama-view','table');
 await page.locator('#clair-lines input[type=number]').fill('7');await expect(page.locator('#clair-lines input[type=number]')).toHaveValue('7');
});

test('purchases opens with the list and keeps an unfinished draft inside its disclosure',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.evaluate(()=>ArcRouter.open('gamaPurchasesV14'));
 await expect(page.locator('#gp14Orders')).toBeVisible();await expect(page.locator('#gp14Supplier')).toBeHidden();
 expect((await page.locator('#gp14Orders').boundingBox()).y).toBeLessThan(844);
 await page.locator('#gp14Editor>summary').click();await page.locator('#gp14SupplierRef').fill('Brouillon à conserver');
 await page.locator('#gp14Editor>summary').click();await expect(page.locator('#gp14Orders')).toBeVisible();
 await page.locator('#gp14Editor>summary').click();await expect(page.locator('#gp14SupplierRef')).toHaveValue('Brouillon à conserver');
});
for(const module of ['contracts','expenses'])test(module+' failed load shows a localized retry without runtime diagnostics',async({page})=>{
 await boot(page);await page.evaluate(id=>ArcRouter.open(id),module);
 const root=page.locator('#'+module);await expect(root.locator('[role=alert]')).toHaveText('Le chargement des données a échoué. Réessayez.');
 await root.locator('[data-retry]').click();await expect(root.locator('[role=alert]')).toHaveText('Le chargement des données a échoué. Réessayez.');
 await expect(root).not.toContainText('Cannot read');
});
