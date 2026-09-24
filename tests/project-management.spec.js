const {test,expect}=require('@playwright/test');const fs=require('fs'),path=require('path'),{PGlite}=require('@electric-sql/pglite');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const uid='00000000-0000-0000-0000-000000000001',member='00000000-0000-0000-0000-000000000002';
async function boot(page,role='admin'){
 const db=new PGlite();await db.exec(fs.readFileSync(path.join(__dirname,'pm-test-bootstrap.sql'),'utf8'));await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/legacy-migrations/20260916093638_project_management.sql'),'utf8'));await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/legacy-migrations/20260916214905_project_item_deletion.sql'),'utf8'));
 await db.exec(`insert into auth.users values ('${uid}','qa@example.invalid'),('${member}','member@example.invalid');insert into public.profiles(id,full_name,role,active) values ('${uid}','Jimmy QA','${role==='client'?'cliente':'administrador'}',true),('${member}','Maria QA','comercial',true);select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated;`);
 const rpc=async(a,d={})=>(await db.query('select public.gama_projects_action($1,$2) result',[a,d])).rows[0].result;
 await page.exposeFunction('__pmServer',async(a,d)=>{try{return {data:await rpc(a,d)}}catch(e){return {error:{message:e.message,code:e.code}}}});
 await page.addInitScript(role=>{localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Jimmy QA'}));localStorage.setItem('gama_language_v1','fr')},role);
 if(process.env.PM_QA_ASSETS){for(const [pattern,file] of [['**/npm/jspdf@*/dist/jspdf.umd.min.js','jspdf/dist/jspdf.umd.min.js'],['**/npm/xlsx@*/dist/xlsx.full.min.js','xlsx/dist/xlsx.full.min.js']])await page.route(pattern,r=>r.fulfill({contentType:'text/javascript',body:fs.readFileSync(path.join(process.env.PM_QA_ASSETS,file))}));}
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html',{waitUntil:'domcontentloaded'});await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
 await page.evaluate(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(name,args)=>name==='gama_projects_action'?window.__pmServer(args.p_action,args.p_data):c.rpc(name,args)}}});
 return {db,rpc,call:(a,d={})=>rpc(a,{...d,request_key:require('crypto').randomUUID()})};
}
async function menu(page){await page.locator('#mainmenu [data-gama-module=projects]').click();await expect(page.locator('#pmFilters')).toBeVisible()}
const field=(page,name)=>page.locator('.pmDialog [name="'+name+'"]');
async function create(page){await page.locator('[data-pm-action=new]').click();await field(page,'name').fill('Installation nouvelle ligne');await field(page,'description').fill('Organiser installation et validation.');await page.locator('.pmDialog [type=submit]').click();await expect(page.locator('#pmMain h2')).toHaveText('Installation nouvelle ligne');}
async function addItem(page,kind,title){await page.locator(`[data-pm-action=new_item][data-kind=${kind}]`).first().click();await field(page,'title').fill(title);await page.locator('.pmDialog [type=submit]').click();await expect(page.locator('.pmDialog h2')).toContainText(title);await page.locator('.pmDialog [data-pm-close]').click()}
test('create, phase/task planning, Kanban drag and mobile status controls, persisted rollups',async({page})=>{test.setTimeout(90000);const {db}=await boot(page);try{await menu(page);await create(page);await page.locator('[data-pm-action=tab][data-value=plan]').click();await addItem(page,'phase','Préparation');await page.locator('[data-pm-action=tab][data-value=tasks]').click();await page.locator('[data-pm-action=new_item]').click();await field(page,'title').fill('Valider P&ID <img src=x>');await field(page,'phase_id').selectOption({label:'Préparation'});await field(page,'estimated_hours').fill('10');await page.locator('.pmDialog [type=submit]').click();await expect(page.locator('.pmDialog h2')).toContainText('Valider P&ID');await expect(page.locator('.pmDialog img')).toHaveCount(0);await page.locator('.pmDialog [data-pm-close]').click();await page.locator('[data-pm-action=sub][data-value=kanban]').click();const card=page.locator('.pmTask');await card.dragTo(page.locator('[data-drop=in_progress]'));await expect(page.locator('[data-drop=in_progress] .pmTask')).toHaveCount(1);await page.locator('[data-task-status]').selectOption('done');await expect(page.locator('[data-drop=done] .pmTask')).toHaveCount(1);await page.locator('[data-pm-action=tab][data-value=overview]').click();await expect(page.locator('.pmKpi').first()).toContainText('100 %');await page.evaluate(()=>window.scrollTo({top:0,behavior:'instant'}));await page.screenshot({path:'test-results/projects-overview-desktop.png',fullPage:true});await page.setViewportSize({width:390,height:844});await page.evaluate(()=>window.scrollTo({top:0,behavior:'instant'}));await page.screenshot({path:'test-results/projects-overview-mobile.png',fullPage:true});expect(await page.locator('#projects').evaluate(e=>e.scrollWidth<=e.clientWidth+1)).toBe(true);await page.evaluate(()=>GamaI18n.setLanguage('es'));await expect(page.locator('#projects .gamaStdText h2')).toHaveText('Proyectos');await page.evaluate(()=>GamaI18n.setLanguage('en'));await expect(page.locator('#projects .gamaStdText h2')).toHaveText('Projects');await expect(page.locator('[data-pm-action=tab][data-value=control]')).toHaveText('Control');}finally{await db.close()}});
test('advanced mode, risk alerts open their exact record, My Work and templates',async({page})=>{test.setTimeout(90000);const {db,call}=await boot(page);try{const r=await call('create_project',{name:'Project advanced',start_date:'2026-09-01',due_date:'2026-12-01'}),pid=r.project_id;await call('save_item',{project_id:pid,kind:'risk',title:'Retard fournisseur',data:{probability:5,impact:4}});await call('save_item',{project_id:pid,kind:'task',title:'Action urgente',owner_id:uid,due_date:'2026-09-01'});await menu(page);await page.locator('[data-pm-project]').first().click();await expect(page.locator('.pmHealth2').first()).toContainText('Critique');await page.locator('.pmRow .pmLink').filter({hasText:'Retard fournisseur'}).first().click();await expect(page.locator('.pmDialog h2')).toContainText('RSK-');await page.locator('.pmDialog [data-pm-close]').click();await page.locator('[data-pm-action=settings]').click();await expect(page.locator('#pmAdvancedSettings')).toBeHidden();await field(page,'mode').selectOption('advanced');await expect(page.locator('#pmAdvancedSettings')).toBeVisible();await page.locator('.pmDialog [type=submit]').click();await page.locator('[data-pm-action=tab][data-value=plan]').click();await expect(page.locator('[data-value=work_packages]')).toBeVisible();await page.locator('[data-pm-action=screen][data-value=my_work]').click();await expect(page.locator('#pmMain')).toContainText('Action urgente');await page.locator('[data-pm-action=my_filter][data-value=late]').click();await page.locator('[data-pm-item]').first().click();await expect(page.locator('.pmDialog h2')).toContainText('Action urgente');await page.locator('.pmDialog [data-pm-close]').click();await page.locator('[data-pm-action=screen][data-value=templates]').click();await expect(page.locator('[data-pm-action=use_template]')).toHaveCount(6);await page.locator('[data-pm-action=new_template]').click();await field(page,'name').fill('Maintenance');await field(page,'phases').fill('Diagnostic\nIntervention\nContrôle');await page.locator('.pmDialog [type=submit]').click();await expect(page.locator('#pmMain')).toContainText('Maintenance');}finally{await db.close()}});
test('client cannot open projects or obtain project data',async({page})=>{test.setTimeout(60000);const {db,rpc}=await boot(page,'client');try{await expect(page.locator('#mainmenu [data-gama-module=projects]')).toBeHidden();await page.evaluate(()=>GamaProjects.open());await expect(page.locator('#projects')).toHaveCount(0);await expect(rpc('lookups')).rejects.toThrow(/PM_FORBIDDEN/)}finally{await db.close()}});

test('accepted quote links once, reports download as PDF and Excel, notifications open budget directly',async({page},testInfo)=>{
 test.setTimeout(90000);const {db,call,rpc}=await boot(page);try{
 const quote='00000000-0000-0000-0000-000000000091',customer='00000000-0000-0000-0000-000000000092';
 await db.exec(`reset role;insert into public.customers(id,name) values('${customer}','Client QA');insert into public.invoices(id,invoice_number,notes,customer_id,quote_state) values('${quote}','DEV-QA','Installation acceptée','${customer}','accepted');set role authenticated;`);
 await page.evaluate(id=>GamaProjects.fromSource('quote',id),quote);await expect(field(page,'name')).toHaveValue('DEV-QA');await expect(field(page,'customer_id')).toHaveValue(customer);await page.locator('.pmDialog [type=submit]').click();await expect(page.locator('#pmMain h2')).toHaveText('DEV-QA');
 const project=(await rpc('portfolio')).rows[0];await page.evaluate(id=>GamaProjects.fromSource('quote',id),quote);await expect(page.locator('#pmMain h2')).toHaveText('DEV-QA');expect((await rpc('portfolio')).total).toBe(1);
 await page.locator('#pmMore').selectOption('reports');
 for(const format of ['pdf','xlsx']){await page.locator('[data-pm-action=report][data-type=financial_report]').click();await field(page,'format').selectOption(format);const download=page.waitForEvent('download');await page.locator('.pmDialog [type=submit]').click();const file=await download;expect(file.suggestedFilename()).toBe(project.reference+'-financial_report.'+format);const saved=testInfo.outputPath('financial-report.'+format);await file.saveAs(saved);const bytes=fs.readFileSync(saved);expect(bytes.length).toBeGreaterThan(1000);expect(bytes.subarray(0,format==='pdf'?4:2).toString()).toBe(format==='pdf'?'%PDF':'PK');await expect(page.locator('.pmDialog')).toHaveCount(0);}
 await call('update_project',{project_id:project.id,version:project.version,estimate_remaining:100});await page.evaluate(async()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(name,args)=>name==='gama_operations_action'?Promise.resolve({data:{from:'2026-09-01',to:'2026-09-16',generated_at:new Date().toISOString(),finance:true,warehouse:true,active_count:0,total:0,counts:{},action_center:{},metrics:{},alerts:[]}}):c.rpc(name,args)}};await GamaOperations.open('notifications')});await page.locator('#notifyTab-projects').click();await expect(page.locator('[data-pm-alerts]')).toContainText('DEV-QA');await page.locator('[data-pm-alerts] [data-pm-target-tab=budget]').first().click();await expect(page.locator('#arcNotifyDialog')).toHaveCount(0);await expect(page.locator('#pmEstimate')).toBeVisible();await expect(page.locator('#pmMain h2')).toHaveText('DEV-QA');
 }finally{await db.close()}
});

test('delete item confirmation, dependency guidance, translations and refreshed lists',async({page})=>{
 test.setTimeout(90000);const {db,call,rpc}=await boot(page);try{
 const pid=(await call('create_project',{name:'Deletion QA',start_date:'2026-09-01',due_date:'2026-12-01'})).project_id;
 const phase=(await call('save_item',{project_id:pid,kind:'phase',title:'Parent QA'})).id;
 const task=(await call('save_item',{project_id:pid,kind:'task',title:'Task to delete',phase_id:phase})).id;
 await page.setViewportSize({width:390,height:844});await menu(page);await page.locator('[data-pm-project]').first().click();
 await page.evaluate(id=>GamaProjects.open({projectId:id,tab:'plan'}),pid);
 await page.locator(`[data-pm-action=item][data-id="${phase}"]`).first().click();
 await page.locator('[data-pm-action=delete_item]').click();
 await expect(page.locator('.pmDialog')).toContainText('Supprimez ou réaffectez');
 await expect(page.locator('.pmDialog [type=submit]')).toHaveCount(0);
 await page.locator(`.pmDialog [data-pm-action=item][data-id="${task}"]`).click();
 await page.locator('[data-pm-action=delete_item]').click();
 await expect(page.locator('.pmDialog')).toContainText('Task to delete');
 await page.locator('.pmDialog [data-pm-close]').click();
 expect((await rpc('detail',{project_id:pid})).items.some(i=>i.id===task)).toBe(true);
 for(const [lang,label] of [['es','Eliminar elemento'],['en','Delete item'],['fr','Supprimer l’élément']]){
  await page.evaluate(lang=>GamaI18n.setLanguage(lang),lang);
  await page.evaluate(({pid,task})=>GamaProjects.open({projectId:pid,itemId:task}),{pid,task});
  await expect(page.locator('[data-pm-action=delete_item]')).toHaveText(label);
  await page.locator('.pmDialog [data-pm-close]').click();
 }
 await page.evaluate(({pid,task})=>GamaProjects.open({projectId:pid,itemId:task}),{pid,task});
 await page.locator('[data-pm-action=delete_item]').click();
 await page.locator('.pmDialog [type=submit]').click();
 expect((await rpc('detail',{project_id:pid})).items.some(i=>i.id===task)).toBe(true);
 await page.locator('.pmDialog [name=confirmed]').check();
 await page.locator('.pmDialog [type=submit]').click();
 await expect(page.locator('.pmDialog')).toHaveCount(0);
 await expect(page.locator('#pmMessage')).toHaveText('Élément supprimé.');
 expect((await rpc('detail',{project_id:pid})).items.some(i=>i.id===task)).toBe(false);
 }finally{await db.close()}
});
