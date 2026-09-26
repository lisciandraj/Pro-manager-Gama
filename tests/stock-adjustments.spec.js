const {test,expect}=require('@playwright/test'),fs=require('node:fs'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
async function boot(page,role='magasinier',lang='fr'){
 const db=await restore(),admin=uuid(),worker=uuid(),product=uuid(),empty=uuid();
 const as=async id=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);set role authenticated`);
 await db.exec(`insert into auth.users(id,email) values('${admin}','adjust-ui-admin@example.invalid'),('${worker}','adjust-ui-worker@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' else 'almacenero' end;insert into products(id,name,barcode) values('${product}','Café stock','CAFE-ADJ'),('${empty}','Nouveau produit','NEW-ADJ');`);
 const location=(await db.query('select id from warehouse_locations where active limit 1')).rows[0].id;
 await as(admin);await db.query("select gama_stock_adjust($1,$2,10,null,'Opening balance')",[product,location]);await db.exec('update erp_policies set stock_adjustment_limit=2 where id');await as(role==='admin'?admin:worker);
 const safe=s=>{if(!/^[a-z_][a-z0-9_]*$/i.test(s))throw Error('TEST_IDENTIFIER');return '"'+s+'"'};
 await page.exposeFunction('__erpRpc',async(fn,args={})=>{try{const entries=Object.entries(args);return {data:(await db.query('select public.'+safe(fn)+'('+entries.map(([k],i)=>safe(k)+'=> $'+(i+1)).join(',')+') r',entries.map(([,v])=>v))).rows[0].r}}catch(e){return {error:{message:e.message,code:e.code}}}});
 await page.exposeFunction('__erpList',async(table,opts={})=>{try{const params=[],where=[];for(const [k,v] of Object.entries(opts.eq||{})){params.push(v);where.push(safe(k)+'=$'+params.length)}for(const [k,v] of Object.entries(opts.in||{})){params.push(v);where.push(safe(k)+'=any($'+params.length+')')}const sql=' from public.'+safe(table)+(where.length?' where '+where.join(' and '):'');const select=opts.select&&opts.select!=='*'?opts.select.split(',').map(safe).join(','):'*';const order=typeof opts.order==='string'?' order by '+safe(opts.order)+(opts.ascending===false?' desc':' asc'):'';const start=opts.range?.[0]||0,limit=opts.range?opts.range[1]-start+1:opts.limit||200;return {data:opts.head?[]:(await db.query('select '+select+sql+order+' limit '+Number(limit)+' offset '+Number(start),params)).rows,count:(await db.query('select count(*)::int n'+sql,params)).rows[0].n,error:null}}catch(e){return {data:[],error:{message:e.message}}}});
 await page.addInitScript(({role,lang,userId})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role,userId,name:'Stock QA'}));localStorage.setItem('gama_language_v1',lang)},{role,lang,userId:role==='admin'?admin:worker});
 await page.route('https://**/*',r=>r.abort());await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(fn,args)=>window.__erpRpc(fn,args)}};GamaCloud.list=(table,opts)=>window.__erpList(table,opts);})();`}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady());await page.evaluate(()=>ArcRouter.open('warehouses'));await page.locator('[data-iv-tab="ajustes"]').click();await expect(page.locator('[data-adjust-new]')).toBeVisible();
 return {db,admin,worker,product,empty,location,as};
}
async function form(page,product,location,kind='breakage',quantity='2'){
 await page.locator('[data-adjust-new]').click();const d=page.locator('dialog').last();await d.locator('[name=kind]').selectOption(kind);await d.locator('[name=product_id]').selectOption(product);await d.locator('[name=location_id]').selectOption(location);await expect(d.locator('[data-adjust-preview]')).toContainText(/Stock actuel|Current stock|Stock actual/);await d.locator('[name=quantity]').fill(quantity);await d.locator('[name=reason]').fill('Contrôle du stock : produits endommagés');return d;
}
test('French adjustment records the actual stock and photo once after a lost response',async({page})=>{
 const x=await boot(page);try{
  const d=await form(page,x.product,x.location);await d.locator('[name=photo]').setInputFiles({name:'damage.png',mimeType:'image/png',buffer:Buffer.from(await page.evaluate(()=>{const c=document.createElement('canvas');c.width=c.height=8;c.getContext('2d').fillRect(0,0,8,8);return c.toDataURL('image/png').split(',')[1]}),'base64')});
  await page.evaluate(()=>{const old=GamaCloud.db;let lose=true;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:async(n,a)=>{const r=await c.rpc(n,a);if(n==='gama_adjustment_request'&&a.p_action==='submit'&&lose&&!r.error){lose=false;return {error:{message:'NETWORK_ERROR'}}}return r}}}});
  await d.locator('[type=submit]').click();await expect(d.locator('[role=alert]')).not.toBeEmpty();await d.locator('[type=submit]').click();await expect(page.locator('dialog')).toHaveCount(0);await expect(page.locator('[data-adjust-rows]')).toContainText('Appliqué');await expect(page.locator('[data-adjust-rows]')).toContainText('10 → 8');
  const rows=(await x.db.query('select * from stock_adjustment_requests')).rows;expect(rows).toHaveLength(1);expect(Number((await x.db.query('select quantity from stock_quants where product_id=$1',[x.product])).rows[0].quantity)).toBe(8);
  await page.locator('[data-adjust-open]').click();await page.locator('[data-adjust-photo]').click();await expect(page.locator('[data-adjust-evidence] img')).toBeVisible();await page.locator('[data-arc-dialog-close]').click();
  await page.screenshot({path:'/tmp/coco-adjust-desktop.png',fullPage:true});
 }finally{await x.db.close()}
});
test('worker submits above threshold, admin reviews through the actual database command',async({page})=>{
 const x=await boot(page);try{
  const d=await form(page,x.product,x.location,'loss','5');await expect(d.locator('[data-adjust-preview]')).toContainText('Validation nécessaire');await d.locator('[type=submit]').click();await expect(page.locator('dialog')).toHaveCount(0);await expect(page.locator('[data-adjust-rows]')).toContainText('À valider');expect(Number((await x.db.query('select stock from products where id=$1',[x.product])).rows[0].stock)).toBe(10);
  await page.locator('[data-adjust-open]').click();await expect(page.locator('[data-adjust-review]')).toHaveCount(0);await expect(page.locator('[data-adjust-cancel]')).toBeVisible();await page.locator('[data-arc-dialog-close]').click();
  await x.as(x.admin);await page.evaluate(id=>{const s=JSON.parse(localStorage.getItem('gama_session_v1'));localStorage.setItem('gama_session_v1',JSON.stringify({...s,role:'admin',userId:id}))},x.admin);
  await page.locator('[data-adjust-open]').click();await page.locator('[data-adjust-review]').click();const review=page.locator('dialog').last();await review.locator('[name=reason]').fill('Écart vérifié par le responsable');await review.locator('[type=submit]').click();await expect(page.locator('dialog')).toHaveCount(0);await expect(page.locator('[data-adjust-rows]')).toContainText('Appliqué');expect(Number((await x.db.query('select stock from products where id=$1',[x.product])).rows[0].stock)).toBe(5);
 }finally{await x.db.close()}
});
test('mobile opening stock fits, preview respects reservations, and other tabs remain translated',async({page})=>{
 await page.setViewportSize({width:390,height:844});const x=await boot(page,'admin','es');try{
  const d=await form(page,x.empty,x.location,'opening','2');await page.screenshot({path:'/tmp/coco-adjust-mobile.png',fullPage:true});expect(await d.evaluate(e=>e.scrollWidth<=e.clientWidth+1)).toBe(true);await d.locator('[type=submit]').click();await expect(page.locator('dialog')).toHaveCount(0);await expect(page.locator('[data-adjust-rows]')).toContainText('Stock inicial');
  await x.db.exec('reset role');await x.db.query('update stock_quants set reserved_quantity=9 where product_id=$1',[x.product]);await x.as(x.admin);
  const reserved=await form(page,x.product,x.location,'sample','2');await reserved.locator('[type=submit]').click();await expect(reserved.locator('[role=alert]')).toContainText('reservadas');await reserved.locator('[data-arc-dialog-close]').click();
  await page.locator('[data-iv-tab="conteos"]').click();await expect(page.locator('#ivCuerpo')).toContainText('Nuevo recuento');
 }finally{await x.db.close()}
});
