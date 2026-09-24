const {test,expect}=require('@playwright/test');
const fs=require('node:fs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
async function boot(page,width=1440,height=900){
 await page.setViewportSize({width,height});
 await page.addInitScript(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({id:'view-user',role:'admin',name:'QA'}));localStorage.setItem('gama_language_v1','fr');window.__DB={products:[],customers:[],invoices:[],invoice_lines:[],profiles:[],suppliers:Array.from({length:25},(_,i)=>({id:'s'+i,name:'Supplier '+i,active:true,tax_id:'TAX'+i,contact_name:'Valeria Torres',phone:'+593 7 292 6418',email:'contact@example.invalid',city:'Machala',address:'Av. 25 de Junio 1120',notes:'Distribution de produits variés ; livraison hebdomadaire.'}))}});
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaTable&&window.ArcUI);
}
async function fixtures(page){await page.evaluate(()=>{
 const host=document.createElement('div');host.id='viewFixtures';document.querySelector('#mainmenu').append(host);
 host.innerHTML='<div id="viewLegacy"><table><tr><th>Nombre</th><th>Ciudad</th></tr><tr><td>Uno</td><td>Quito</td></tr><tr><td>Dos</td><td>Manta</td></tr></table></div><div id="viewShared"></div>';
 ArcUI.render(host.querySelector('#viewShared'),ArcUI.table({columns:[{key:'name',label:'Nombre'},{key:'city',label:'Ciudad'}],items:[{name:'Alpha',city:'Quito'},{name:'Beta',city:'Manta'},{name:'Gamma',city:'Cuenca'}]}));
});await expect(page.locator('#viewFixtures .gamaTableViews')).toHaveCount(2)}
test('legacy and shared tables switch to uniform multi-column cards and retain independent preferences',async({page})=>{
 await boot(page);await fixtures(page);
 for(const id of ['viewLegacy','viewShared']){
  const host=page.locator('#'+id);await expect(host.locator('table')).toHaveAttribute('data-gama-view','table');
  await host.getByRole('button',{name:'Tuiles',exact:true}).click();
  const result=await host.locator('table').evaluate(t=>{const rows=[...t.rows].filter(r=>!r.hasAttribute('data-gama-head'));return {colors:rows.flatMap(r=>[getComputedStyle(r).backgroundColor,...[...r.cells].map(c=>getComputedStyle(c).backgroundColor)]),y:rows.slice(0,2).map(r=>r.getBoundingClientRect().y),head:getComputedStyle(t.rows[0]).display}});
  expect(new Set(result.colors).size).toBe(1);expect(result.y[0]).toBe(result.y[1]);expect(result.head).toBe('none');
 }
 await page.locator('#viewLegacy').getByRole('button',{name:'Tableau',exact:true}).click();
 await page.evaluate(()=>{document.getElementById('viewFixtures').remove()});await fixtures(page);
 await expect(page.locator('#viewLegacy table')).toHaveAttribute('data-gama-view','table');await expect(page.locator('#viewShared table')).toHaveAttribute('data-gama-view','cards');
 await page.evaluate(()=>GamaI18n.setLanguage('en'));
 await expect(page.locator('#viewLegacy').getByRole('button',{name:'Table',exact:true})).toHaveAttribute('aria-pressed','true');
});
test('portrait and landscape support both modes without overflow and preserve supplier actions after paging',async({page})=>{
 await boot(page,390,844);await fixtures(page);
 await expect(page.locator('#viewLegacy table')).toHaveAttribute('data-gama-view','cards');
 await page.setViewportSize({width:844,height:390});await expect(page.locator('#viewLegacy table')).toHaveAttribute('data-gama-view','table');
 await page.locator('#viewShared').getByRole('button',{name:'Tuiles',exact:true}).click();
 const rows=page.locator('#viewShared tbody tr');expect((await rows.nth(0).boundingBox()).y).toBe((await rows.nth(1).boundingBox()).y);
 await page.locator('#viewShared').getByRole('button',{name:'Tableau',exact:true}).click();
 expect(await page.locator('#viewShared td').first().evaluate(c=>getComputedStyle(c).display)).toBe('table-cell');
 await page.evaluate(()=>ArcRouter.open('suppliers'));await expect(page.locator('#ctTable tbody tr')).toHaveCount(20);
 await page.locator('#ctTable [data-table-view=cards]').click();
 const supplierRows=page.locator('#ctTable tbody tr');expect((await supplierRows.nth(0).boundingBox()).y).toBe((await supplierRows.nth(1).boundingBox()).y);
 await page.locator('#ctTable .arcPager button').last().click();await expect(page.locator('#ctTable tbody tr')).toHaveCount(5);
 await expect(page.locator('#ctTable .gamaTableViews')).toHaveCount(1);await expect(page.locator('#ctTable table')).toHaveAttribute('data-gama-view','cards');
 await page.locator('#ctTable [data-ct-edit]').first().click();await expect(page.locator('#ctf-name')).not.toHaveValue('');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.screenshot({path:'test-results/table-views-landscape.png',fullPage:true});
});

test('phone table mode scrolls full-width shipment columns and action buttons',async({page})=>{
 await boot(page,390,844);
 await page.evaluate(()=>{const host=document.createElement('div');host.id='shipmentScrollTest';host.className='gsScroll';host.style.overflowWrap='anywhere';document.querySelector('#mainmenu').append(host);host.innerHTML='<table><thead><tr><th>Expédition</th><th>Client</th><th>Transport</th><th>Date</th><th>Actions</th></tr></thead><tbody><tr><td>ENV-00001318</td><td>Almacenes Costa Azul</td><td>Entregada</td><td>2026-09-19</td><td><button type="button">Voir la commande</button></td></tr></tbody></table>';host.querySelector('button').onclick=()=>window.__shipmentOpened=true});
 await page.locator('#shipmentScrollTest [data-table-view=table]').click();
 for(const size of [{width:390,height:844},{width:844,height:390}]){
  await page.setViewportSize(size);
  const state=await page.locator('#shipmentScrollTest table').evaluate(t=>{const v=t.parentElement;return {table:t.getBoundingClientRect().width,viewport:v.clientWidth,cellWhiteSpace:getComputedStyle(t.rows[1].cells[3]).whiteSpace,buttonHeight:t.querySelector('button').getBoundingClientRect().height,pageWidth:document.documentElement.scrollWidth}});
  expect(state.cellWhiteSpace).toBe('nowrap');expect(state.buttonHeight).toBeLessThan(70);expect(state.table).toBeGreaterThanOrEqual(state.viewport);expect(state.pageWidth).toBeLessThanOrEqual(size.width);
  if(size.width===390){expect(state.table).toBeGreaterThan(state.viewport+100);await page.locator('#shipmentScrollTest .gamaTableViewport').evaluate(v=>v.scrollLeft=v.scrollWidth);expect(await page.locator('#shipmentScrollTest .gamaTableViewport').evaluate(v=>v.scrollLeft)).toBeGreaterThan(100)}
 }
 await page.locator('#shipmentScrollTest table button').click();expect(await page.evaluate(()=>window.__shipmentOpened)).toBe(true);
 await page.setViewportSize({width:390,height:844});await page.locator('#shipmentScrollTest [data-table-view=cards]').click();expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});

// En el teléfono, con la vista «Tableau» elegida, cada valor sigue bajo su
// columna: una celda vacía (sin marca, sin ubicación…) ya no se esconde ni
// corre las siguientes, y la primera celda y la de los botones llevan el
// mismo margen que las demás. En «Tuiles», la celda vacía sigue sin ocupar sitio.
test('phone table mode keeps every value under its column header, empty cells included',async({page})=>{
 await boot(page,390,844);
 await page.evaluate(()=>{const host=document.createElement('div');host.id='alignTest';document.querySelector('#mainmenu').append(host);
  ArcUI.render(host,ArcUI.table({columns:[{key:'code',label:'Código'},{key:'name',label:'Producto'},{key:'brand',label:'Marca'},{key:'stock',label:'Stock',numeric:true},{key:'place',label:'Ubicación'},{label:'Acciones',actions:true,html:()=>'<button type="button" class="arcButton">Editar</button>'}],
   items:[{code:'A1',name:'Cemento',brand:'Holcim',stock:4,place:'A01-01'},{code:'',name:'Varilla',brand:'',stock:9,place:''},{code:'C3',name:'Clavos',brand:'',stock:0,place:'B02'}]}));});
 await page.locator('#alignTest [data-table-view=table]').click();
 for(const size of [{width:390,height:844},{width:667,height:375}]){
  await page.setViewportSize(size);
  const cells=await page.locator('#alignTest table').evaluate(t=>{const head=[...t.tHead.rows[0].cells].map(c=>({x:Math.round(c.getBoundingClientRect().left),pad:getComputedStyle(c).paddingLeft}));
   return [...t.tBodies[0].rows].map(r=>[...r.cells].map((c,i)=>getComputedStyle(c).display==='table-cell'&&Math.round(c.getBoundingClientRect().left)===head[i].x&&getComputedStyle(c).paddingLeft===head[i].pad))});
  expect(cells,`${size.width}x${size.height}`).toEqual([Array(6).fill(true),Array(6).fill(true),Array(6).fill(true)]);
 }
 await page.setViewportSize({width:390,height:844});await page.locator('#alignTest [data-table-view=cards]').click();
 expect(await page.locator('#alignTest tbody tr').nth(1).locator('td').evaluateAll(c=>c.filter(x=>getComputedStyle(x).display==='none').length)).toBe(3);
});

// Los botones de vista son dibujos: cuatro cuadrados para las tarjetas y líneas
// horizontales para la tabla. El nombre, traducido, queda para el lector de
// pantalla y como ayuda al pasar el ratón.
test('les boutons d’affichage sont des logos : quatre carrés pour les tuiles, des lignes pour le tableau',async({page})=>{
 await boot(page);await fixtures(page);
 const bar=page.locator('#viewShared .gamaTableViews'),cards=bar.locator('[data-table-view=cards]'),table=bar.locator('[data-table-view=table]');
 for(const b of [cards,table]){expect(await b.evaluate(x=>x.textContent.trim())).toBe('');const box=await b.boundingBox();expect(Math.round(box.width)).toBe(44);expect(Math.round(box.height)).toBe(44)}
 await expect(cards.locator('svg rect')).toHaveCount(4);
 await expect(table.locator('svg path')).toHaveAttribute('d','M4 6h16M4 10h16M4 14h16M4 18h16');
 const names=async()=>[await cards.getAttribute('aria-label'),await cards.getAttribute('title'),await table.getAttribute('aria-label'),await table.getAttribute('title')];
 expect(await names()).toEqual(['Tuiles','Tuiles','Tableau','Tableau']);
 await page.evaluate(()=>GamaI18n.setLanguage('en'));await expect(cards).toHaveAccessibleName('Cards');expect(await names()).toEqual(['Cards','Cards','Table','Table']);
 await page.evaluate(()=>GamaI18n.setLanguage('es'));await expect(table).toHaveAccessibleName('Tabla');expect(await names()).toEqual(['Tarjetas','Tarjetas','Tabla','Tabla']);
 await cards.click();await expect(page.locator('#viewShared table')).toHaveAttribute('data-gama-view','cards');await expect(cards).toHaveAttribute('aria-pressed','true');await expect(table).toHaveAttribute('aria-pressed','false');
});
