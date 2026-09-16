const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {PGlite}=require('@electric-sql/pglite');
test('Project SQL contracts: RLS, workflow, rollup, conflicts, change application, closure and audit',async()=>{const db=new PGlite();try{await db.exec(fs.readFileSync(path.join(__dirname,'pm-test-bootstrap.sql'),'utf8'));await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations/20260916093638_project_management.sql'),'utf8'));await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations/20260916214905_project_item_deletion.sql'),'utf8'));const rows=await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/tests/project-management.sql'),'utf8'));assert.match(rows.at(-1).rows[0].result,/passed/)}finally{await db.close()}});

test('Project item deletion: every kind, permissions, references, rollups, retained records and audit',async()=>{
 const db=new PGlite();
 try{
  await db.exec(fs.readFileSync(path.join(__dirname,'pm-test-bootstrap.sql'),'utf8'));
  for(const f of ['20260916093638_project_management.sql','20260916214905_project_item_deletion.sql'])await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations',f),'utf8'));
  const manager='00000000-0000-0000-0000-000000000001',member='00000000-0000-0000-0000-000000000002',outsider='00000000-0000-0000-0000-000000000003';
  await db.exec(`insert into auth.users values('${manager}','manager@example.invalid'),('${member}','member@example.invalid'),('${outsider}','outsider@example.invalid');insert into profiles(id,full_name,role,active) values('${manager}','Manager','comercial',true),('${member}','Member','comercial',true),('${outsider}','Outsider','comercial',true);`);
  const as=async uid=>db.exec(`select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated;`);
  const rpc=async(a,d={})=>(await db.query('select public.gama_projects_action($1,$2) result',[a,d])).rows[0].result;
  const call=(a,d={})=>rpc(a,{...d,request_key:require('crypto').randomUUID()});
  await as(manager);
  const pid=(await call('create_project',{name:'Delete QA',start_date:'2026-09-01',due_date:'2026-12-01'})).project_id;
  const detail=()=>rpc('detail',{project_id:pid});
  let p=(await detail()).project;await call('update_project',{project_id:pid,version:p.version,mode:'advanced'});
  const add=async(kind,extra={})=>(await call('save_item',{project_id:pid,kind,title:'QA '+kind,...extra})).id;
  const current=async id=>(await detail()).items.find(i=>i.id===id);
  const del=async(id,extra={})=>call('delete_item',{project_id:pid,id,version:(await current(id)).version,confirmed:true,...extra});
  const root=await add('phase');
  for(const kind of ['phase','task','milestone','work_package','deliverable','risk','issue','change','decision','lesson','assumption','dependency','stakeholder','raci']){
   const id=await add(kind,kind==='work_package'?{phase_id:root}:kind==='risk'?{data:{probability:2,impact:3}}:kind==='raci'?{owner_id:manager,data:{target_id:root,raci:'R'}}:{});
   const item=await current(id);assert.equal((await del(id)).deleted,true,kind);assert.equal(await current(id),undefined,kind);
   const d=await detail();assert(d.activity.some(a=>a.row_id===id&&a.action==='DELETE'&&a.old_data.reference===item.reference),kind+' audit');
  }
  const task=await add('task',{phase_id:root,status:'done'}),remaining=await add('task',{phase_id:root});
  assert.equal((await current(root)).progress,50);
  await assert.rejects(del(root),/PM_DELETE_REFERENCED/);
  await assert.rejects(del(task,{confirmed:false}),/PM_DELETE_CONFIRM_REQUIRED/);
  await assert.rejects(del(task,{version:0}),/PM_CONFLICT/);
  const dependency=await add('task',{data:{dependencies:[task]}});await assert.rejects(del(task),/PM_DELETE_REFERENCED/);await del(dependency);
  const issue=await add('issue',{data:{task_id:task}});await assert.rejects(del(task),/PM_DELETE_REFERENCED/);await del(issue);
  const change=await add('change',{data:{impacts:[{item_id:task,version:1,due_date:'2026-12-01'}]}});await assert.rejects(del(task),/PM_DELETE_REFERENCED/);await del(change);
  const raci=await add('raci',{owner_id:manager,data:{target_id:root,raci:'R'}});await assert.rejects(del(root),/PM_DELETE_REFERENCED/);await del(raci);
  p=(await detail()).project;await call('member',{project_id:pid,version:p.version,profile_id:member,role:'member'});
  const payload={project_id:pid,id:task,version:(await current(task)).version,confirmed:true,request_key:require('crypto').randomUUID()};
  await as(member);await assert.rejects(rpc('delete_item',payload),/PM_FORBIDDEN/);
  await assert.rejects(db.query('delete from public.pm_items where id=$1',[task]),/permission denied/);
  await as(outsider);await assert.rejects(rpc('delete_item',payload),/PM_FORBIDDEN/);
  await as(manager);
  const other=(await call('create_project',{name:'Other',start_date:'2026-09-01',due_date:'2026-12-01'})).project_id;
  await assert.rejects(call('delete_item',{...payload,project_id:other}),/PM_NOT_FOUND/);
  const comment=(await call('comment',{project_id:pid,id:task,body:'Keep comment'})).id;
  const file=(await call('file',{project_id:pid,id:task,filename:'Keep file',url:'https://example.invalid/file.pdf'})).id;
  const before=(await current(task)).reference;
  assert.equal((await rpc('delete_item',payload)).deleted,true);assert.equal((await rpc('delete_item',payload)).deleted,true);
  assert.equal((await current(root)).progress,0);assert.equal((await detail()).metrics.progress,0);
  assert.equal((await detail()).comments.find(c=>c.id===comment).item_id,null);assert.equal((await detail()).files.find(f=>f.id===file).item_id,null);
  assert.equal((await detail()).activity.filter(a=>a.row_id===task&&a.action==='DELETE').length,1);
  const next=await add('task');assert.notEqual((await current(next)).reference,before);
  await db.exec(`reset role;insert into suppliers(id,name) values('00000000-0000-0000-0000-000000000091','Supplier QA');insert into products(id,name) values('00000000-0000-0000-0000-000000000092','Product QA');`);await as(manager);
  const costPhase=await add('phase');
  const purchase=await call('create_purchase',{project_id:pid,id:costPhase,supplier_id:'00000000-0000-0000-0000-000000000091',currency:'USD',exchange_rate:1,lines:[{product_id:'00000000-0000-0000-0000-000000000092',quantity:2,unit_cost:12.5}]});
  const committed=(await detail()).metrics.committed;await del(costPhase);
  assert.equal((await detail()).links.find(l=>l.target_id===purchase.purchase_id).item_id,null);assert.equal((await detail()).metrics.committed,committed);
  await db.exec(`reset role;update public.pm_items set status='completed' where id='${root}';`);await as(manager);
  await assert.rejects(del(remaining),/PM_PARENT_LOCKED/);
  await db.exec(`reset role;update public.pm_items set status='planned' where id='${root}';update public.purchase_orders set status='cancelled' where id='${purchase.purchase_id}';`);await as(manager);
  p=(await detail()).project;await call('cancel',{project_id:pid,version:p.version,reason:'QA closure'});await assert.rejects(del(remaining),/PM_PROJECT_CLOSED/);
 }finally{await db.close()}
});
