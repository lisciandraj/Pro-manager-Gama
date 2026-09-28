const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs');
test('return summary counts all matching rows and pages beyond 200 without duplicates',async()=>{
 const db=await restore(),admin=randomUUID(),customer=randomUUID(),supplier=randomUUID();
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','summary@example.invalid');update profiles set active=true,role='administrador' where id='${admin}';
   insert into customers(id,name,identification) values('${customer}','Summary client','SUM-QA');
   insert into suppliers(id,name) values('${supplier}','Summary supplier');
   select set_config('request.jwt.claim.sub','${admin}',false);
   insert into return_orders(kind,status,customer_id,reason,financial_action,created_by,notes)
    select 'customer','to_process','${customer}','defective','none','${admin}','summary customer' from generate_series(1,201);
   insert into return_orders(kind,status,supplier_id,reason,financial_action,created_by,notes)
    select 'supplier','to_process','${supplier}','defective','none','${admin}','summary supplier' from generate_series(1,5);`);
  const call=async d=>(await db.query("select public.gama_returns_action('overview',$1::jsonb) data",[JSON.stringify({all_dates:true,...d})])).rows[0].data;
  const first=await call({limit:25}),last=await call({offset:200,limit:25});assert.equal(first.total,206);assert.equal(first.rows.length,25);assert.equal(last.rows.length,6);
  const ids=[];for(let offset=0;offset<206;offset+=25)ids.push(...(await call({offset,limit:25})).rows.map(r=>r.id));assert.equal(new Set(ids).size,206);
  assert.equal((await call({kind:'supplier'})).total,5);assert.equal((await call({customer_id:customer})).total,201);assert.equal((await call({supplier_id:supplier})).total,5);assert.equal((await call({search:'summary supplier'})).total,5);
  assert.equal((await call({search:'not present'})).total,0);assert.equal((await call({offset:999})).rows.length,0);
  assert.ok(first.rows.every(r=>r.credited_amount===0));
  await db.exec(`insert into return_credits(return_id,amount,issued_on,created_by) values('${first.rows[0].id}',12,current_date,'${admin}')`);
  assert.equal((await call({limit:1})).rows[0].credited_amount,12);
  assert.equal((await db.query("select has_function_privilege('anon','public.gama_returns_action(text,jsonb)','execute') allowed")).rows[0].allowed,false);
 }finally{await db.close()}
});
