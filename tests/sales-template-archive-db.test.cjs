const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('template archive enforces delete permission, quote module access and ownership without changing issued documents',async()=>{
 const db=await restore(),admin=uuid(),owner=uuid(),other=uuid(),tpl=uuid(),otherTpl=uuid();
 const query=(sql,args=[])=>db.query(sql,args),value=async(sql,args=[])=>Object.values((await query(sql,args)).rows[0])[0];
 const as=async id=>{await db.exec('reset role');await query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 const api=(action,id)=>value('select public.gama_sales_workspace($1,$2::jsonb)',[action,JSON.stringify(typeof id==='object'?id:{id})]);
 try{
  for(const [id,role,name] of [[admin,'administrador','admin'],[owner,'comercial','owner'],[other,'comercial','other']]){await query('insert into auth.users(id,email) values($1,$2)',[id,name+'-template@example.invalid']);await query('update profiles set role=$1,active=true where id=$2',[role,id]);}
  await query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await query("insert into private.sales_templates(id,name,details,lines,created_by) values($1,'Office','{\"notes\":\"PRIVATE MODEL CONTENT\"}','[]',$2),($3,'Other','{}','[]',$4)",[tpl,owner,otherTpl,other]);
  await query("insert into private.sales_templates(name,details,lines,created_by,updated_at) select 'Batch '||i,'{}','[]',$1,now()+interval '1 day' from generate_series(1,101) i",[owner]);
  await db.exec("insert into erp_action_permissions(role,module,allow_delete) values('comercial','quotes',false)");
  await as(owner);assert.equal((await api('templates')).length,100);assert.ok(!(await api('templates')).some(t=>t.id===tpl));assert.equal((await api('templates',{search:'Office'}))[0].id,tpl);assert.equal((await api('templates',{search:'%'})).length,0);await assert.rejects(api('template_delete',tpl),/ROLE_NOT_ALLOWED/);
  await as(admin);await db.exec("reset role;update erp_action_permissions set allow_delete=true where role='comercial' and module='quotes';update role_module_access set disabled_modules=array['quotes'] where role='comercial'");
  await as(owner);await assert.rejects(api('template_delete',tpl),/ROLE_NOT_ALLOWED/);
  await as(admin);await db.exec("reset role;update role_module_access set disabled_modules='{}' where role='comercial'");
  await as(owner);await assert.rejects(api('template_delete',otherTpl),/NOT_FOUND/);assert.equal((await api('template_get',tpl)).active,true);
  await db.exec("begin;select set_config('coco.activity_source_type','chat',true);select set_config('coco.activity_source_id','isolated-template-archive',true);select set_config('coco.activity_source_label','Agent Coco · archive template fixture',true)");
  await api('template_delete',tpl);await db.exec('commit');assert.deepEqual(await api('template_delete',tpl),{saved:true});await assert.rejects(api('template_get',tpl),/NOT_FOUND/);
  const events=(await query("select * from private.coco_module_events where record_table='sales_templates' and record_id=$1 and action='update'",[tpl])).rows;assert.equal(events.length,1);assert.equal(events[0].actor_name,'Agent Coco');assert.equal(events[0].actor_id,owner);assert.equal(events[0].source_type,'chat');assert.equal(events[0].source_id,'isolated-template-archive');assert.ok(events[0].created_at);assert.ok(!JSON.stringify(events).includes('PRIVATE MODEL CONTENT'));
  await as(other);assert.equal(Number(await value("select count(*) from private.coco_module_events where record_table='sales_templates' and record_id=$1",[tpl])),0);await as(owner);assert.ok(!(await api('templates')).some(t=>t.id===tpl));
  await db.exec('reset role');assert.equal(await value('select active from private.sales_templates where id=$1',[tpl]),false);assert.equal(await value('select active from private.sales_templates where id=$1',[otherTpl]),true);
  assert.equal(Number(await value('select version from private.sales_templates where id=$1',[tpl])),2);
  await as(admin);await api('template_delete',otherTpl);await db.exec('reset role');assert.equal(await value('select active from private.sales_templates where id=$1',[otherTpl]),false);
  await db.exec("select set_config('request.jwt.claim.sub','',false);set role anon");await assert.rejects(api('template_delete',tpl),/permission denied|AUTH_OR_MFA_REQUIRED/);
 }finally{await db.close()}
});
