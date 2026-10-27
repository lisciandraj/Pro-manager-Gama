const {test,expect}=require('@playwright/test'),{randomUUID:uuid}=require('node:crypto');
const fs=require('node:fs'),path=require('node:path'),{restore}=require('../scripts/restore-schema.cjs');
const AxeBuilder=require('@axe-core/playwright').default;
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
test.setTimeout(120000);

async function environment(browser){
 const {createHandler}=await import('../supabase/functions/coco-workhub-documents/handler.mjs');
 const db=await restore(),a=uuid(),b=uuid(),contexts=[],errors=[];let chain=Promise.resolve(),dropResponse=false,documentId;
 const serial=fn=>{const p=chain.then(fn);chain=p.catch(()=>{});return p};
 const sql=async(actor,name,args)=>{
  await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[actor==='service'?'':actor]);await db.exec('set role '+(actor==='service'?'service_role':'authenticated'));
  const r=name==='coco_workhub_document_stage'?await db.query('select coco_workhub_document_stage($1::jsonb) value',[JSON.stringify(args.p_data)]):await db.query(`select ${name}($1,$2::jsonb) value`,[args.p_action,JSON.stringify(args.p_data)]);return r.rows[0].value;
 };
 for(const [id,name] of [[a,'Editor Quito'],[b,'Editor Andes']]){await db.query('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);await db.query("update profiles set active=true,role='administrador',full_name=$2 where id=$1",[id,name]);}
 const channel=(await serial(()=>sql(a,'coco_workhub',{p_action:'channel_create',p_data:{name:'Protocoles Quito',members:[b],request_key:uuid()}}))).id;
 const handler=createHandler({env:k=>({SUPABASE_URL:'https://unit.supabase.co',SUPABASE_ANON_KEY:'public',SUPABASE_SERVICE_ROLE_KEY:'service'})[k],fetch:async(url,o={})=>serial(async()=>{
  const token=o.headers.Authorization.replace('Bearer ',''),body=o.body?JSON.parse(o.body):null;
  if(url.endsWith('/auth/v1/user'))return new Response(JSON.stringify({id:token}),{status:200});
  try{return new Response(JSON.stringify(await sql(token,url.split('/').pop(),body)),{status:200});}catch(e){return new Response(JSON.stringify({message:e.message}),{status:400});}
 })});
 async function pageFor(id,{mobile=false}={}){
  const context=await browser.newContext({viewport:mobile?{width:390,height:844}:{width:1440,height:1000},acceptDownloads:true});contexts.push(context);const page=await context.newPage();page.setDefaultTimeout(15000);
  page.on('pageerror',e=>errors.push(e.message));
  await page.exposeFunction('__docRpc',async(name,args)=>{try{return {data:await serial(()=>sql(id,name,args))}}catch(e){return{error:{message:e.message}}}});
  await page.addInitScript(({id})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Editor'}));localStorage.setItem('gama_language_v1','fr');window.__DB={_profile:{id,role:'administrador',full_name:'Editor',active:true},_session:{profile_id:id}};},{id});
  await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
  await page.route('**/functions/v1/coco-workhub-documents',async route=>{
   const cors={'access-control-allow-origin':'*','access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST,OPTIONS','content-type':'application/json'};
   if(route.request().method()==='OPTIONS')return route.fulfill({status:204,headers:cors});
   const headers={...route.request().headers(),origin:'https://lisciandraj.github.io'};
   const response=await handler(new Request(route.request().url(),{method:'POST',headers,body:route.request().postData()}));
   const data=await response.text();
   if(dropResponse&&response.ok){dropResponse=false;return route.fulfill({status:503,headers:cors,body:JSON.stringify({error:'WORKHUB_DOCUMENT_UNAVAILABLE'})});}
   return route.fulfill({status:response.status,headers:cors,body:data});
  });
  await page.goto('/index.html');await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
  await page.evaluate(({id})=>{const old=GamaCloud.db;GamaCloud.url='https://mknsaibrewksgomuslev.supabase.co';GamaCloud.getSession=async()=>({data:{session:{access_token:id,user:{id}}}});GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(name,args)=>['coco_workhub','coco_workhub_documents','coco_module_history','coco_module_history_events'].includes(name)?window.__docRpc(name,args):c.rpc(name,args)}};},{id});
  await page.locator('#mainmenu [data-gama-module=workhub]').click();await expect(page.locator('#whNav')).toBeVisible();
  return page;
 }
 async function create(page){
  await page.locator('[data-wh-view=documents]').click();await page.getByRole('button',{name:'Nouveau document partagé',exact:true}).click();
  const d=page.locator('[data-workhub-dialog]');await d.getByLabel('Titre du document').fill('Plan partagé Quito');await d.getByLabel(/^Canal/).selectOption(channel);await d.getByRole('button',{name:'Créer',exact:true}).click();
  await expect(page.locator('#whDocText')).toBeVisible();documentId=(await serial(()=>sql(a,'coco_workhub_documents',{p_action:'list',p_data:{}}))).rows[0].id;return documentId;
 }
 return {db,a,b,channel,pageFor,create,errors,drop:()=>dropResponse=true,id:()=>documentId,read:()=>serial(()=>sql(a,'coco_workhub_documents',{p_action:'read',p_data:{id:documentId}})),revoke:()=>serial(()=>sql(a,'coco_workhub',{p_action:'member_set',p_data:{channel_id:channel,profile_id:b,remove:true,request_key:uuid()}})),close:async()=>{for(const c of contexts)await c.close();await chain;await db.close();}};
}
test('two actual editors merge, keep cursor position, export, show versions and enforce archive on desktop/mobile',async({browser})=>{
 const c=await environment(browser);try{
  const a=await c.pageFor(c.a),requests=[];a.on('request',r=>requests.push(r.url()));
  expect(requests.some(x=>x.includes('yjs-'))).toBe(false);await c.create(a);
  expect(requests.filter(x=>x.includes('yjs-13.6.33.js'))).toHaveLength(1);
  const b=await c.pageFor(c.b,{mobile:true});await b.locator('[data-wh-channel]').first().click();await b.locator('.whSource').click();await b.getByRole('button',{name:'Ouvrir dans son module',exact:true}).click();await expect(b.locator('#whDocText')).toBeVisible();
  await a.locator('#whDocText').fill('Préparer les livraisons 🚀');await a.locator('#whDocSave').click();await expect(a.locator('#whDocStatus')).toHaveText('Toutes les modifications sont enregistrées.');
  await expect(b.locator('#whDocText')).toHaveValue('Préparer les livraisons 🚀');
  await Promise.all([a.locator('#whDocText').fill('Quito — Préparer les livraisons 🚀'),b.locator('#whDocText').fill('Préparer les livraisons 🚀 — Andes')]);
  await Promise.all([a.locator('#whDocSave').click(),b.locator('#whDocSave').click()]);
  const merged='Quito — Préparer les livraisons 🚀 — Andes';await expect(a.locator('#whDocText')).toHaveValue(merged);await expect(b.locator('#whDocText')).toHaveValue(merged);
  await b.locator('#whDocText').focus();await b.locator('#whDocText').evaluate(el=>el.setSelectionRange(el.value.length,el.value.length));
  await a.locator('#whDocText').fill('Validé ✓ '+merged);await a.locator('#whDocSave').click();await expect(b.locator('#whDocText')).toHaveValue('Validé ✓ '+merged);
  expect(await b.locator('#whDocText').evaluate(el=>el.selectionStart)).toBe(('Validé ✓ '+merged).length);
  const download=a.waitForEvent('download');await a.getByRole('button',{name:'Exporter le texte',exact:true}).click();expect((await download).suggestedFilename()).toBe('Plan partagé Quito.md');
  await a.getByRole('button',{name:'Versions enregistrées',exact:true}).click();const versions=a.locator('[data-workhub-document-dialog]');await expect(versions.getByLabel('Texte de la version enregistrée')).toHaveValue('Validé ✓ '+merged);await versions.getByRole('button',{name:'Retour',exact:true}).click();
  expect(await b.locator('#workhub').evaluate(el=>el.scrollWidth<=el.clientWidth+1)).toBe(true);
  expect(await b.locator('.whDocEditor>.whActions button').evaluateAll(buttons=>buttons.every(button=>{const r=button.getBoundingClientRect();return r.width>=120&&r.height<100;}))).toBe(true);
  for(const p of [a,b])expect((await new AxeBuilder({page:p}).include('#workhub').analyze()).violations).toEqual([]);
  await b.evaluate(()=>window.scrollTo(0,0));await a.screenshot({path:'test-results/workhub-document-desktop.png',fullPage:true});await b.screenshot({path:'test-results/workhub-document-mobile.png',fullPage:true});
  await expect(a.locator('#whDocStatus')).toHaveText('Toutes les modifications sont enregistrées.');await a.getByRole('button',{name:'Archiver',exact:true}).click();await a.locator('[data-workhub-document-dialog]').getByRole('button',{name:'Confirmer',exact:true}).click();await expect(b.locator('#whDocText')).toHaveJSProperty('readOnly',true);
  await a.getByRole('button',{name:'Réactiver',exact:true}).click();await a.locator('[data-workhub-document-dialog]').getByRole('button',{name:'Confirmer',exact:true}).click();await expect(b.locator('#whDocText')).toHaveJSProperty('readOnly',false);
  await c.revoke();await expect(b.locator('#whDocText')).toHaveCount(0);await expect(b.locator('#whList')).toContainText('plus accessible');
  expect(c.errors).toEqual([]);
 }finally{await c.close();}
});
test('lost response keeps an unsaved draft through navigation and language changes; retry is idempotent',async({browser})=>{
 const c=await environment(browser);try{
  const page=await c.pageFor(c.a,{mobile:true});await c.create(page);c.drop();
  await page.locator('#whDocText').fill('Brouillon conservé <img src=x onerror=alert(1)>');await page.locator('#whDocSave').click();await expect(page.locator('#whDocStatus')).toHaveAttribute('role','alert');
  await page.locator('[data-wh-view=tasks]').click();await page.locator('[data-wh-view=documents]').click();await page.locator('#whList .whRow').filter({hasText:'Plan partagé Quito'}).click();await page.getByRole('button',{name:'Ouvrir dans son module',exact:true}).click();
  await expect(page.locator('#whDocText')).toHaveValue('Brouillon conservé <img src=x onerror=alert(1)>');await expect(page.locator('#whDocStatus')).toHaveText('Toutes les modifications sont enregistrées.');expect((await c.read()).version).toBe(1);
  await page.evaluate(()=>GamaI18n.setLanguage('en'));await expect(page.getByLabel('Document text',{exact:true})).toHaveValue('Brouillon conservé <img src=x onerror=alert(1)>');
  await page.evaluate(()=>GamaI18n.setLanguage('es'));await expect(page.getByLabel('Texto del documento',{exact:true})).toHaveValue('Brouillon conservé <img src=x onerror=alert(1)>');
  expect(await page.locator('.whDocEditor img').count()).toBe(0);
  await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));await expect(page.locator('#workhub')).toBeEmpty();expect(c.errors).toEqual([]);
 }finally{await c.close();}
});
