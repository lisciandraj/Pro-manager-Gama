const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('Agent Coco central history combines existing module and dossier events with paging and original access controls',async()=>{
 const db=await restore(),admin=uuid(),sales=uuid();
 const q=async(s,p=[])=>(await db.query(s,p)).rows;
 const actor=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 const history=async(module='assistant-ia',offset=0)=>(await q("select public.coco_module_history('list',$1::jsonb) result",[JSON.stringify({module_id:module,offset})]))[0].result.history;
 try{
  for(const [id,role] of [[admin,'administrador'],[sales,'comercial']]){
   await q('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);await q('update profiles set active=true,role=$2,full_name=$2 where id=$1',[id,role]);
  }
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await q("insert into private.coco_module_events(module_id,type,action,subject,actor_name,source_type,source_id,created_at,transaction_id) select case when n%2=0 then 'products' else 'contacts' end,'action','update','Central fixture','Agent Coco','chat','central-'||n,now()-n*interval '1 minute',100000+n from generate_series(1,61) n");
  await q("insert into private.coco_module_events(module_id,type,action,subject,actor_name) values ('products','action','update','Human excluded','Alice'),('products','action','update','Unknown excluded','AUTHOR_NOT_RECORDED'),('assistant-ia','note','note','Local note preserved','Alice')");
  await q("insert into private.coco_module_events(module_id,type,action,subject,actor_name,source_type) values('products','action','proposal_approved','Human approval excluded','Alice','chat')");
  await q("insert into private.coco_order_entries(kind,type,actor_name,subject,body) values('sales','note','ChatGPT','Dossier note','Legacy agent note'),('sales','action','Agent Coco','created','Dossier agent action'),('sales','note','Alice','Human dossier','Human excluded')");
  const before=await q('select id,created_at from private.coco_module_events order by id');
  await actor(admin);
  const first=await history(),second=await history('assistant-ia',50),all=[...first,...second];
  assert.equal(first.length,50);assert.equal(new Set(all.map(x=>x.id)).size,64);assert.equal(first[0].total,64);
  assert(all.some(x=>x.body==='Legacy agent note'&&x.actor_name==='Agent Coco'&&x.module_id==='sales-orders'));
  assert(all.some(x=>x.body==='Dossier agent action'));assert(all.some(x=>x.subject==='Local note preserved'));
  assert(!all.some(x=>/excluded/.test(x.subject)));assert(all.filter(x=>x.source_id?.startsWith('central-')).every(x=>x.links.some(l=>l.module===x.module_id)));
  assert(all.every((x,i)=>!i||new Date(all[i-1].at)>=new Date(x.at)));
  const products=await history('products');assert(products.some(x=>x.subject==='Human excluded'));assert(products.every(x=>x.module_id==='products'));assert(!products.some(x=>x.body==='Legacy agent note'));
  await db.exec('reset role');assert.deepEqual(await q('select id,created_at from private.coco_module_events order by id'),before);
  // A source row hidden by its current policy must stay hidden centrally.
  await db.exec("begin;select set_config('coco.activity_source_type','chat',true),set_config('coco.activity_source_id','row-restricted',true)");
  await q("insert into products(name,reference,barcode) values('Hidden agent product','CENTRAL-HIDDEN','CENTRAL-HIDDEN')");await db.exec('commit');
  await db.exec("create policy central_fixture_restriction on public.products as restrictive for select to authenticated using (name<>'Hidden agent product')");
  await actor(admin);assert(!(await history()).some(x=>x.source_id==='row-restricted'&&x.subject==='Producto'));assert(!(await history('products')).some(x=>x.source_id==='row-restricted'&&x.subject==='Producto'));
  await db.exec('reset role');
  // Permission to enter Agent Coco does not grant permission to source modules.
  await q("select gama_save_role_module_access('administrador',array['contacts','sales-orders'],0)");await actor(admin);
  const restricted=await history();assert(!restricted.some(x=>['contacts','sales-orders'].includes(x.module_id)));
  await actor(sales);await assert.rejects(history(),/ROLE_NOT_ALLOWED/);assert((await history('products')).length>0);
  await db.exec('reset role;set role anon');await assert.rejects(history(),/permission denied/);
 }finally{await db.close()}
});
