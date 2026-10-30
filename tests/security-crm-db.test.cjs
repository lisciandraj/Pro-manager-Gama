const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');

test('security: native CRM tables and independent child writes obey current module and action restrictions',async()=>{
 const db=await restore(),admin=uuid(),seller=uuid(),customer=uuid(),product=uuid(),otherProduct=uuid(),opportunity=uuid(),line=uuid(),activity=uuid();
 const q=async(sql,args=[])=>(await db.query(sql,args)).rows,one=async(sql,args=[])=>Object.values((await q(sql,args))[0])[0];
 const owner=async()=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[admin])};
 const commercial=async()=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[seller]);await db.exec('set role authenticated')};
 try{
  for(const [id,role]of [[admin,'administrador'],[seller,'comercial']]){await q('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);await q('update profiles set role=$2,active=true where id=$1',[id,role])}
  await owner();await q("insert into customers(id,name) values($1,'CRM security fixture')",[customer]);
  for(const id of [product,otherProduct])await q('insert into products(id,name) values($1,$2)',[id,'CRM fixture '+id]);
  const stage=await one('select id from crm_pipeline_stages where active and not is_won and not is_lost limit 1');
  await q("insert into crm_opportunities(id,title,customer_id,owner_id,stage_id,amount,created_by) values($1,'Protected opportunity',$2,$3,$4,10,$3)",[opportunity,customer,seller,stage]);
  await q('insert into crm_opportunity_lines(id,opportunity_id,product_id,quantity,unit_price) values($1,$2,$3,1,10)',[line,opportunity,product]);
  await q("insert into crm_activities(id,kind,subject,status,opportunity_id,owner_id,created_by) values($1,'nota','Protected note','hecha',$2,$3,$3)",[activity,opportunity,seller]);
  const insertLine=()=>q('insert into crm_opportunity_lines(opportunity_id,product_id,quantity,unit_price) values($1,$2,1,20) returning id',[opportunity,otherProduct]);

  await q("update role_module_access set disabled_modules=array_append(disabled_modules,'crm') where role='comercial'");await commercial();
  for(const [table,id]of [['crm_opportunities',opportunity],['crm_opportunity_lines',line],['crm_activities',activity]]){
   assert.equal(await one(`select count(*)::int from ${table} where id=$1`,[id]),0);
   assert.equal((await q(`delete from ${table} where id=$1 returning id`,[id])).length,0);
  }
  assert.equal((await q('update crm_opportunities set amount=99 where id=$1 returning id',[opportunity])).length,0);
  assert.equal((await q('update crm_opportunity_lines set quantity=9 where id=$1 returning id',[line])).length,0);
  assert.equal((await q("update crm_activities set subject='Denied' where id=$1 returning id",[activity])).length,0);
  await assert.rejects(insertLine(),/row-level security/);
  await assert.rejects(q("insert into crm_opportunities(title,customer_id,stage_id) values('Denied',$1,$2)",[customer,stage]),/row-level security/);
  await assert.rejects(q("insert into crm_activities(kind,subject,opportunity_id) values('nota','Denied',$1)",[opportunity]),/row-level security/);

  await owner();await q("update role_module_access set disabled_modules=array_remove(disabled_modules,'crm') where role='comercial'");
  await q("insert into erp_action_permissions(role,module,allow_create,allow_edit,allow_delete,updated_by) values('comercial','crm',false,true,false,$1) on conflict(role,module) do update set allow_create=false,allow_edit=true,allow_delete=false",[admin]);await commercial();
  assert.equal(await one('select count(*)::int from crm_opportunities where id=$1',[opportunity]),1);
  await assert.rejects(insertLine(),/ACTION_NOT_ALLOWED:crm:create/);
  await assert.rejects(q('delete from crm_opportunity_lines where id=$1',[line]),/ACTION_NOT_ALLOWED:crm:delete/);
  assert.equal((await q('update crm_opportunity_lines set quantity=2 where id=$1 returning id',[line])).length,1);
  await q('update crm_opportunities set amount=20 where id=$1',[opportunity]);

  await owner();await q("update erp_action_permissions set allow_create=true,allow_edit=false,allow_delete=true where role='comercial' and module='crm'");await commercial();
  assert.equal(await one('select count(*)::int from crm_opportunity_lines where id=$1',[line]),1);
  await assert.rejects(insertLine(),/row-level security/);
  assert.equal((await q('delete from crm_opportunity_lines where id=$1 returning id',[line])).length,0);
  assert.equal((await q('update crm_opportunity_lines set quantity=9 where id=$1 returning id',[line])).length,0);
  await assert.rejects(q('update crm_opportunities set amount=99 where id=$1',[opportunity]),/ACTION_NOT_ALLOWED:crm:edit/);
  await owner();assert.equal(Number(await one('select quantity from crm_opportunity_lines where id=$1',[line])),2);assert.equal(Number(await one('select amount from crm_opportunities where id=$1',[opportunity])),20);

  await q("update erp_action_permissions set allow_edit=true where role='comercial' and module='crm'");await commercial();
  const added=(await insertLine())[0].id;assert.ok(added);assert.equal((await q('delete from crm_opportunity_lines where id=$1 returning id',[added])).length,1);
  assert.equal((await q("update crm_activities set subject='Authorized' where id=$1 returning id",[activity])).length,1);
  // Parent deletion has its own delete authority; its FK cascade must remain
  // valid even when the profile cannot independently edit opportunity lines.
  await owner();await q("update erp_action_permissions set allow_edit=false where role='comercial' and module='crm'");await commercial();
  assert.equal((await q('delete from crm_opportunities where id=$1 returning id',[opportunity])).length,1);
  await owner();assert.equal(await one('select count(*)::int from crm_opportunity_lines where id=$1',[line]),0);assert.equal(await one('select count(*)::int from crm_activities where id=$1',[activity]),0);
 }finally{await db.close()}
});
