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

for(const width of [390,768,1440])test(`every enabled module shares the responsive GAMA workspace at ${width}px`,async({page},info)=>{
 test.setTimeout(120000);await page.setViewportSize({width,height:900});await boot(page);
 const modules=await page.evaluate(()=>GamaMenu.items.filter(x=>gamaMenuVisible(x[1])).map(x=>x[1]));
 expect(modules.length).toBeGreaterThan(20);
 const report=[];
 for(const id of modules){
  await page.evaluate(()=>{document.querySelectorAll('dialog[open]').forEach(d=>d.close());GamaUI.backToMenu()});
  await page.evaluate(id=>ArcRouter.open(id),id);
  // The app bar synchronizes after a rendered frame; wait for the visible
  // result instead of assuming every browser paints within 350 milliseconds.
  await expect.poll(()=>page.evaluate(()=>[...(document.querySelector('section.active')?.querySelectorAll('.gamaStdText h2,.gamaStdBack')||[])].filter(el=>!el.closest('dialog')&&el.getClientRects().length).length),{message:id+' duplicate module headings and home arrows'}).toBe(0);
  const screen=await page.evaluate(()=>{
   const section=document.querySelector('section.active'),dialog=document.querySelector('dialog[open]');
   const nav=section?.querySelector('.cocoModuleNav'),r=nav?.getBoundingClientRect();
   return {id:section?.id,dialog:!!dialog,overflow:document.documentElement.scrollWidth-innerWidth,contentLeft:document.querySelector('.arcMain').getBoundingClientRect().left,pinned:document.body.classList.contains('cocoNavPinned'),nav:r?{top:r.top,left:r.left,right:r.right}:null,title:document.querySelector('#cocoModuleContext')?.textContent,duplicateHeaders:[...(section?.querySelectorAll('.gamaStdText h2,.gamaStdBack')||[])].filter(el=>!el.closest('dialog')&&el.getClientRects().length).length};
  });
  report.push({module:id,...screen});
  expect(screen.dialog||screen.id!=='mainmenu',id+' opened').toBe(true);
  expect(screen.overflow,id+' horizontal overflow').toBeLessThanOrEqual(2);
  expect(screen.contentLeft,id+' desktop sidebar allowance').toBe(width>=1180?276:0);
  expect(screen.pinned,id+' native tabs stay in the content').toBe(false);
  await expect(page.locator('.arcTopbar')).toBeVisible();
  if(!screen.dialog){
   expect(screen.title,id+' module title').toBeTruthy();
   expect(screen.duplicateHeaders,id+' duplicate module headings and home arrows').toBe(0);
   const back=page.locator('.arcTopbar #cocoModuleBack'),title=page.locator('.arcTopbar h1#cocoModuleContext');
   await expect(back).toBeVisible();await expect(title).toBeVisible();
   const b=await back.boundingBox(),h=await title.boundingBox();
   expect(Math.abs(b.y+b.height/2-h.y-h.height/2),id+' title and return share one row').toBeLessThanOrEqual(1);
   expect(b.x+b.width,id+' return precedes title').toBeLessThanOrEqual(h.x);
   await back.click();await expect(page.locator('#mainmenu')).toBeVisible();await expect(back).toBeHidden();
   await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="'+id+'"] .cocoModuleOpen')).toBeFocused();
  }
 }
 fs.writeFileSync(info.outputPath('module-layout-coverage.json'),JSON.stringify(report,null,2));
 await info.attach('module-layout-coverage',{body:JSON.stringify(report,null,2),contentType:'application/json'});
});

test('tablet and phone drawer traps focus, restores it, and keeps module favorites accessible',async({page})=>{
 await boot(page);
 for(const width of [1024,768,390]){
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
 // The GAMA reference theme allows a roomier toolbar while keeping rows above the fold.
 // The compact history utility row remains in normal flow above the list.
 expect((await page.locator('#gqList').boundingBox()).y).toBeLessThan(560);
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
  await expect(page.locator('#cocoModuleBack')).toHaveAccessibleName(({fr:'Retour au menu',es:'Volver al menú',en:'Back to menu'})[lang]);
  await page.locator('#arcSearchInput').focus();await expect(page.locator('#gamaSpotlight')).toBeVisible();
  await page.keyboard.press('Escape');await expect(page.locator('#gamaSpotlight')).toBeHidden();
 }
});


test('desktop navigation remains usable across the drawer breakpoint without trapping the app',async({page})=>{
 await page.setViewportSize({width:1024,height:900});await boot(page);
 await page.locator('.arcBurger').click();
 await expect(page.locator('.arcSidebar')).toHaveAttribute('aria-modal','true');
 await page.setViewportSize({width:1440,height:900});
 await expect(page.locator('.arcSidebar')).toBeVisible();
 await expect(page.locator('.arcBurger')).toBeHidden();
 await expect(page.locator('.arcSidebar')).not.toHaveAttribute('aria-modal','true');
 expect(await page.locator('.arcSidebar').evaluate(el=>el.inert)).toBe(false);
 expect(await page.locator('.arcMain').evaluate(el=>el.inert)).toBe(false);
 await page.evaluate(()=>document.fonts.ready);
 expect(await page.evaluate(()=>[400,500,600].every(weight=>document.fonts.check(weight+' 14px Poppins')))).toBe(true);
 // A real long translated label must fit without breaking its final word.
 // This also covers the narrowest persistent-sidebar breakpoint.
 for(const width of [1180,1280,1440]){
  await page.setViewportSize({width,height:900});
  const label=await page.locator('#mainmenu [data-gama-module=knowledge] .gamaF2Title').evaluate(el=>({height:el.getBoundingClientRect().height,line:parseFloat(getComputedStyle(el).lineHeight)}));
  expect(label.height,'knowledge label at '+width).toBeLessThanOrEqual(label.line*2.1);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(2);
 }
 await page.locator('.arcNavLink[data-gama-module=products]').last().click();
 await expect(page.locator('#products')).toBeVisible();
 await page.setViewportSize({width:390,height:844});
 await expect(page.locator('.arcBurger')).toBeVisible();
 expect(await page.locator('.arcSidebar').evaluate(el=>el.inert)).toBe(true);
 await page.locator('.arcBurger').click();await page.keyboard.press('Escape');
 await expect(page.locator('.arcBurger')).toBeFocused();
});
