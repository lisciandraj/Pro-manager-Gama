const {test,expect}=require('@playwright/test');
const fs=require('node:fs');
const {isolateLocalPage}=require('./local-browser-fixture.cjs');
const mock=['mock-gama-cloud.js','mock-dashboard.js','mock-service-documents.js'].map(f=>fs.readFileSync(__dirname+'/'+f,'utf8')).join('\n');
test.use({serviceWorkers:'block'});
async function boot(page){
 await isolateLocalPage(page);
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Coco Layout QA'}));
  localStorage.setItem('gama_tms_migrated_v1','1');
  window.__DB={products:[{id:'p1',name:'Papier A4',reference:'A4',barcode:'B1',stock:40,sale_price:12,active:true}],customers:[{id:'c1',name:'Costa Azul',active:true}],suppliers:[],profiles:[],invoice_lines:[],sales_orders:[],sales_order_lines:[],purchase_orders:[],purchase_order_lines:[],invoices:Array.from({length:24},(_,i)=>({id:'q'+i,invoice_number:'COT-'+(3118+i),quote_state:'draft',quote_revision:1,issue_date:'2026-10-16',quote_valid_until:'2026-11-16',quote_details:{seller:'Coco',client:'Costa Azul',delivery_address:'Quito'},total:100+i}))};
 });
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');
 await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central'&&window.gamaAccessAllowed?.('quotes'));
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));
}

for(const width of [390,768,1440])test(`every enabled module shares the full-width workspace at ${width}px`,async({page},info)=>{
 test.setTimeout(120000);await page.setViewportSize({width,height:900});await boot(page);
 const modules=await page.evaluate(()=>GamaMenu.items.filter(x=>gamaMenuVisible(x[1])).map(x=>x[1]));
 expect(modules.length).toBeGreaterThan(20);
 const report=[];
 for(const id of modules){
  await page.evaluate(()=>{document.querySelectorAll('dialog[open]').forEach(d=>d.close());GamaUI.backToMenu()});
  await page.evaluate(id=>ArcRouter.open(id),id);
  await page.waitForTimeout(350);
  const screen=await page.evaluate(()=>{
   const section=document.querySelector('section.active'),dialog=document.querySelector('dialog[open]');
   const nav=section?.querySelector('.cocoModuleNav'),r=nav?.getBoundingClientRect();
   return {id:section?.id,dialog:!!dialog,overflow:document.documentElement.scrollWidth-innerWidth,contentLeft:document.querySelector('.arcMain').getBoundingClientRect().left,pinned:document.body.classList.contains('cocoNavPinned'),nav:r?{top:r.top,left:r.left,right:r.right}:null,title:document.querySelector('#cocoModuleContext')?.textContent};
  });
  report.push({module:id,...screen});
  expect(screen.dialog||screen.id!=='mainmenu',id+' opened').toBe(true);
  expect(screen.overflow,id+' horizontal overflow').toBeLessThanOrEqual(2);
  expect(screen.contentLeft,id+' full-width workspace').toBe(0);
  await expect(page.locator('.arcTopbar')).toBeVisible();
  if(screen.pinned&&!screen.dialog){
   expect(screen.nav.top,id+' navigation in app bar').toBe(0);
   expect(screen.nav.left,id+' navigation after brand').toBeGreaterThan(200);
   expect(screen.nav.right,id+' navigation before utilities').toBeLessThan(width-120);
  }
 }
 fs.writeFileSync(info.outputPath('module-layout-coverage.json'),JSON.stringify(report,null,2));
 await info.attach('module-layout-coverage',{body:JSON.stringify(report,null,2),contentType:'application/json'});
});

test('application drawer traps focus, restores it, and keeps module favorites accessible on every device',async({page})=>{
 await boot(page);
 for(const width of [1440,1024,390]){
  await page.setViewportSize({width,height:900});
  await expect(page.locator('.arcBurger')).toBeVisible();
  expect(await page.locator('.arcSidebar').evaluate(el=>el.inert)).toBe(true);
  await page.locator('.arcBurger').click();
  await expect(page.locator('.arcSidebar')).toHaveAttribute('aria-modal','true');
  await expect(page.locator('.arcNavFavorites')).toBeVisible();
  expect(await page.locator('.arcMain').evaluate(el=>el.inert)).toBe(true);
  await page.locator('#arcLangSelect').focus();await page.keyboard.press('Tab');
  await expect(page.locator('.arcDrawerClose')).toBeFocused();
  await page.keyboard.press('Escape');await expect(page.locator('.arcBurger')).toBeFocused();
  expect(await page.locator('.arcMain').evaluate(el=>el.inert)).toBe(false);
  await page.locator('.arcBurger').click();await page.locator('.arcNavLink[data-gama-module=products]').last().click();
  await expect(page.locator('#products')).toBeVisible();
  await expect(page.locator('.arcBurger')).toHaveAttribute('aria-expanded','false');
 }
});

test('native sales tabs stay in their module, switch with keyboard, and the command bar keeps real filters and paging',async({page},info)=>{
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.setViewportSize({width:1440,height:1000});await boot(page);
 await page.evaluate(()=>ArcRouter.open('quotes'));await expect(page.locator('#gqList tbody tr')).toHaveCount(20);
 await expect(page.locator('section.active .cocoSalesNavigation')).toHaveClass(/cocoModuleNav/);
 expect(await page.locator('section.active .cocoSalesNavigation').evaluate(el=>el.closest('section').id)).toBe('quotes');
 expect((await page.locator('#gqList').boundingBox()).y).toBeLessThan(330);
 const first=page.locator('[data-coco-sales-section=documents]');await first.focus();await page.keyboard.press('ArrowRight');
 await expect(page.locator('[data-coco-sales-section=orders]')).toBeFocused();await page.keyboard.press('Enter');
 await expect(page.locator('#sales-orders')).toBeVisible();
 await page.locator('section.active [data-coco-sales-section=documents]').click();await expect(page.locator('#gqList')).toBeVisible();
 await page.locator('#gqNext').click();await expect(page.locator('#gqList tbody tr')).toHaveCount(4);
 await page.locator('#gqSearch').fill('COT-3118');await page.locator('#gqSearch').press('Enter');await expect(page.locator('#gqList tbody tr')).toHaveCount(1);
 await page.locator('[data-gq-open=q0]').click();await expect(page.locator('#gqBack')).toBeVisible();
 await page.locator('#gqBack').click();await expect(page.locator('#gqSearch')).toHaveValue('COT-3118');
 await expect(page.locator('[data-gq-open=q0]')).toBeFocused();
 await page.screenshot({path:info.outputPath('workbench-sales-desktop.png')});
 await page.setViewportSize({width:390,height:900});
 await expect(page.locator('#gqList')).toHaveAttribute('data-gama-view','cards');
 expect(await page.locator('section.active .cocoSalesNavigation').evaluate(el=>getComputedStyle(el).flexWrap)).toBe('nowrap');
 await page.locator('#gqOptions>summary').click();await page.locator('section.active [data-table-view=table]').click();await page.locator('#gqRefresh').click();
 await expect(page.locator('#gqList')).toHaveAttribute('data-gama-view','table');
 await page.locator('#gqOptions>summary').click();await page.locator('section.active [data-table-view=cards]').click();
 await page.screenshot({path:info.outputPath('workbench-sales-mobile.png'),fullPage:true});
 expect(errors).toEqual([]);
});

test('global search and module titles follow the selected language without duplicated controls',async({page})=>{
 await page.setViewportSize({width:1440,height:900});await boot(page);
 for(const lang of ['fr','es','en']){
  await page.evaluate(async lang=>{await GamaI18n.setLanguage(lang);await ArcRouter.open('quotes')},lang);
  await expect(page.locator('[data-coco-sales-section]')).toHaveCount(5);
  await expect(page.locator('#gqSearch')).toHaveCount(1);
  await expect(page.locator('#cocoModuleContext')).toHaveText(await page.locator('#quotes .gamaStdText h2').innerText());
  await page.locator('#arcSearchInput').focus();await expect(page.locator('#gamaSpotlight')).toBeVisible();
  await page.keyboard.press('Escape');await expect(page.locator('#gamaSpotlight')).toBeHidden();
 }
});
