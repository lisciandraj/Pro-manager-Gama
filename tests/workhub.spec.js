const {test,expect}=require('@playwright/test'),{randomUUID:uuid}=require('node:crypto');
const fs=require('node:fs'),path=require('node:path');
const {restore}=require('../scripts/restore-schema.cjs');
const AxeBuilder=require('@axe-core/playwright').default;
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
test.setTimeout(90000);
async function boot(page,{mobile=false,role='admin'}={}){
 const db=await restore(),user=uuid(),colleague=uuid(),errors=[];
 page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=500)errors.push('HTTP '+r.status()+' '+r.url());});
 for(const [id,name,r]of [[user,'Coordinator QA',role==='client'?'cliente':'administrador'],[colleague,'María QA','comercial']]){
  await db.query('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);await db.query('update profiles set full_name=$2,role=$3,active=true where id=$1',[id,name,r]);
 }
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user]);await db.exec('set role authenticated');
 const sql=async(name,a,d={})=>(await db.query(`select public.${name}($1,$2::jsonb) result`,[a,JSON.stringify(d)])).rows[0].result;
 const project=role==='client'?null:(await sql('gama_projects_action','create_project',{name:'Quito deliveries',start_date:'2026-10-01',due_date:'2026-12-31',request_key:uuid()})).project_id;
 await page.exposeFunction('__workhubServer',async(name,args)=>{try{return {data:name==='coco_workhub_calendar'?(await db.query('select public.coco_workhub_calendar($1::jsonb) r',[JSON.stringify(args.p_data)])).rows[0].r:await sql(name,args.p_action,args.p_data)}}catch(e){return {error:{message:e.message,code:e.code}}}});
 await page.addInitScript(({role,user})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Coordinator QA'}));localStorage.setItem('gama_language_v1','fr');window.__workhubUid=user;},{role,user});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 if(mobile)await page.setViewportSize({width:390,height:844});else await page.setViewportSize({width:1440,height:1000});
 await page.goto('/index.html');await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
 await page.evaluate(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(name,args)=>['coco_workhub','coco_workhub_calendar','gama_projects_action','coco_module_history','coco_module_history_events'].includes(name)?window.__workhubServer(name,args):c.rpc(name,args)}};});
 return {db,user,colleague,project,errors,sql};
}
async function open(page){await page.locator('#mainmenu [data-gama-module=workhub]').click();await expect(page.locator('#whNav')).toBeVisible();await expect(page.locator('#whList')).not.toHaveText('Chargement…');}
async function createChannel(page,colleague){await page.getByRole('button',{name:'Nouveau canal',exact:true}).click();const d=page.locator('[data-workhub-dialog]');await d.getByLabel(/^Nom/).fill('Logistique Quito');await d.getByLabel('Description',{exact:true}).fill('Coordination des livraisons');await d.getByLabel('María QA').check();await d.getByRole('button',{name:'Créer',exact:true}).click();await expect(page.locator('#whControls h2')).toContainText('Logistique Quito');return page.locator('[data-wh-channel]').first().getAttribute('data-wh-channel');}
test('channel → message → native task → source/backlink → Agent Coco context, desktop and keyboard',async({page})=>{
 const c=await boot(page);try{
  await open(page);await expect(page.locator('#workhub')).toContainText('Aucun élément');const channel=await createChannel(page,c.colleague);
  await page.getByLabel('Message',{exact:true}).fill('Vérifier les livraisons <img src=x onerror=alert(1)>');await page.locator('#whMessageForm').getByRole('button',{name:'Envoyer',exact:true}).click();await expect(page.locator('.whMessage')).toHaveCount(1);await expect(page.locator('.whMessage img')).toHaveCount(0);
  await page.getByRole('button',{name:'Répondre',exact:true}).click();await page.getByLabel('Message',{exact:true}).fill('Adresse confirmée ✓');await page.locator('#whMessageForm').getByRole('button',{name:'Envoyer',exact:true}).click();await expect(page.locator('.whReply')).toHaveCount(1);
  await page.locator('.whMessage').first().getByRole('button',{name:'Créer une tâche',exact:true}).click();const d=page.locator('[data-workhub-dialog]');await d.getByLabel('Titre de la tâche').fill('Préparer la tournée');await d.getByLabel(/^Projet/).selectOption(c.project);await d.getByRole('button',{name:'Créer',exact:true}).click();await expect(page.locator('.whSource')).toHaveCount(1);
  const item=(await c.db.query("select id,title,description from pm_items where kind='task'")).rows[0];expect(item.title).toBe('Préparer la tournée');expect(item.description).toContain('<img');
  await page.locator('.whSource').click();await expect(page.locator('#whDetail')).toContainText('Discussions liées');await expect(page.locator('#whDetail .whBacklink')).toContainText('Logistique Quito');
  await page.locator('#whSearch').fill('tournée');await page.locator('#whSearch').press('Enter');await expect(page.locator('#whList .whRow')).toHaveCount(1);await page.locator('.whRow').click();await expect(page.locator('#whDetail h3')).toHaveText('Préparer la tournée');
  await page.evaluate(()=>{window.__contextDraft=null;window.GamaAssistant={openContext:c=>window.__contextDraft=c};});await page.locator('[data-wh-channel]').click();await page.locator('[data-wh-context]').click();await expect(page.locator('#whDetail')).toContainText('Adresse confirmée');await page.locator('[data-wh-context-agent]').click();expect((await page.evaluate(()=>__contextDraft)).content).toContain('Adresse confirmée');
  const a11y=await new AxeBuilder({page}).include('#workhub').analyze();expect(a11y.violations).toEqual([]);
  await page.screenshot({path:'test-results/workhub-desktop.png',fullPage:true});expect(c.errors).toEqual([]);
 }finally{await c.db.close();}
});
test('mobile, language changes, draft preserved on failed send and cleared at logout',async({page})=>{
 const c=await boot(page,{mobile:true});try{
  await page.clock.install();await open(page);const channel=await createChannel(page,c.colleague);await page.getByLabel('Message',{exact:true}).fill('Brouillon conservé');
  await c.sql('coco_workhub','message_create',{channel_id:channel,body:'Second device update',request_key:uuid()});await page.clock.fastForward(20001);await expect(page.locator('.whMessage')).toContainText('Second device update');await expect(page.getByLabel('Message',{exact:true})).toHaveValue('Brouillon conservé');
  await page.evaluate(()=>{const old=ArcData.rpc;window.ArcData={...ArcData,rpc:async(name,args)=>{if(name==='coco_workhub'&&args.p_action==='message_create'&&!window.__sendFailed){window.__sendFailed=true;throw Error('NETWORK');}return old(name,args);}};});
  await page.locator('#whMessageForm').getByRole('button',{name:'Envoyer',exact:true}).click();await expect(page.locator('#whNotice')).toHaveAttribute('role','alert');await expect(page.getByLabel('Message',{exact:true})).toHaveValue('Brouillon conservé');
  await page.locator('#whMessageForm').getByRole('button',{name:'Envoyer',exact:true}).click();await expect(page.locator('.whMessage').last()).toContainText('Brouillon conservé');
  await page.evaluate(()=>GamaI18n.setLanguage('en'));await expect(page.locator('#whMessageForm [type=submit]')).toHaveText('Send');
  await page.evaluate(()=>GamaI18n.setLanguage('es'));await expect(page.locator('#whMessageForm [type=submit]')).toHaveText('Enviar');
  expect(await page.locator('#workhub').evaluate(e=>e.scrollWidth<=e.clientWidth+1)).toBe(true);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await page.screenshot({path:'test-results/workhub-mobile.png',fullPage:true});
  const a11y=await new AxeBuilder({page}).include('#workhub').analyze();expect(a11y.violations).toEqual([]);
  await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));await expect(page.locator('#workhub')).toBeEmpty();expect(c.errors).toEqual([]);
 }finally{await c.db.close();}
});
test('client cannot open the workspace or trigger its RPC',async({page})=>{
 const c=await boot(page,{role:'client'});try{await expect(page.locator('#mainmenu [data-gama-module=workhub]')).toBeHidden();await page.evaluate(()=>ArcRouter.open('workhub'));await expect(page.locator('#workhub')).toHaveCount(0);expect(c.errors).toEqual([]);}finally{await c.db.close();}
});

for(const mobile of [false,true])test('personal agenda keeps civil dates, pagination and navigation '+(mobile?'mobile':'desktop'),async({page})=>{
 const c=await boot(page,{mobile});try{
  await c.db.exec('reset role');
  await c.db.query("insert into pm_items(project_id,kind,title,owner_id,due_date,status,created_by) select $1,'task','Agenda task '||lpad(n::text,2,'0'),$2,'2026-10-02','todo',$2 from generate_series(1,43)n",[c.project,c.user]);
  await c.db.exec('set role authenticated');await open(page);await page.locator('[data-wh-view=calendar]').click();
  await page.locator('#whCalendarFrom').fill('2026-10-01');await page.locator('#whCalendarTo').fill('2026-10-31');await page.locator('[data-wh-calendar-show]').click();
  await expect(page.locator('#whList')).toContainText('1–40 / 43');await page.locator('[data-wh-next]').click();await expect(page.locator('#whList')).toContainText('41–43 / 43');
  await page.locator('[data-wh-row]').first().click();await expect(page.locator('#whDetail')).toContainText('Agenda task');
  for(const lang of ['es','en','fr']){await page.evaluate(l=>GamaI18n.setLanguage(l),lang);await expect(page.locator('#whCalendarFrom')).toHaveValue('2026-10-01');await expect(page.locator('#whList')).toContainText('43');}
  await page.locator('#whCalendarTo').fill('2027-10-31');await page.locator('[data-wh-calendar-show]').click();await expect(page.locator('#whNotice')).toContainText('93 jours');await expect(page.locator('#whList')).toContainText('43');
  const a11y=await new AxeBuilder({page}).include('#workhub').analyze();expect(a11y.violations).toEqual([]);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await page.screenshot({path:test.info().outputPath('workhub-agenda.png'),fullPage:true});expect(c.errors).toEqual([]);
 }finally{await c.db.close()}
});
