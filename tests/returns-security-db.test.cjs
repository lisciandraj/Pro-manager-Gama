const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('returns preserve module revocation, invoice lineage and consumed refund capacity',async t=>{
 const db=await restore(),ids=Object.fromEntries(['admin','seller','customer','other','order','otherOrder','product','line','delivery','tms','bank'].map(k=>[k,uuid()]));
 const q=async(sql,args=[])=>(await db.query(sql,args)).rows,one=async(sql,args=[])=>Object.values((await q(sql,args))[0])[0];
 const as=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 const rpc=(action,data={})=>one('select public.gama_returns_action($1,$2::jsonb)',[action,JSON.stringify(data)]);
 try{
  for(const id of [ids.admin,ids.seller])await q('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id,id+'@example.invalid']);
  await q("update profiles set active=true,role=case when id=$1 then 'administrador' else 'comercial' end",[ids.admin]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);
  await q("insert into customers(id,name) values($1,'Return source'),($2,'Other customer')",[ids.customer,ids.other]);
  await q("insert into products(id,name,barcode,sale_price,purchase_price) values($1,'Return item','RETURN-SEC-FIXTURE',10,4)",[ids.product]);
  for(const [order,customer]of [[ids.order,ids.customer],[ids.otherOrder,ids.other]])await q("insert into sales_orders(id,customer_id,customer_name,request_key,status,created_by) values($1,$2,'Fixture',gen_random_uuid(),'confirmed',$3)",[order,customer,ids.admin]);
  await q("insert into sales_order_lines(id,order_id,product_id,product_name,quantity,unit_price,tax_rate) values($1,$2,$3,'Return item',2,10,0)",[ids.line,ids.order,ids.product]);
  const invoices=[];
  for(const order of [ids.order,ids.otherOrder]){
   const quote=await one("insert into invoices(quote_state,quote_details) values('draft','{}') returning id");
   invoices.push(await one("insert into external_invoices(request_key,order_id,number,issuer_ruc,issue_date,subtotal,tax,fiscal_status,document_kind,source_quote_id,document_snapshot,created_by) values(gen_random_uuid(),$1,$2,'1790012345001',current_date,20,0,'unverified','internal',$3,'{}',$4) returning id",[order,'SEC-'+uuid(),quote,ids.admin]));
  }
  await db.exec('begin');
  await q("insert into tms_deliveries(id,customer_id,customer,address,created_by) values($1,$2,'Return source','Fixture address',$3)",[ids.tms,ids.customer,ids.admin]);
  await q('insert into sales_deliveries(id,order_id,request_key,tms_delivery_id,created_by) values($1,$2,gen_random_uuid(),$3,$4)',[ids.delivery,ids.order,ids.tms,ids.admin]);
  const dl=await one('insert into sales_delivery_lines(delivery_id,order_line_id,location_id,quantity) select $1,$2,id,2 from warehouse_locations where active limit 1 returning id',[ids.delivery,ids.line]);
  await db.exec('commit');
  await q("insert into financial_accounts(id,name,kind,account_id) select $1,'Refund fixture','bank',id from accounting_accounts where code='1000'",[ids.bank]);
  const create=(extra={})=>rpc('create',{kind:'customer',source_id:ids.delivery,invoice_id:invoices[0],reason:'defective',lines:[{line_id:dl,quantity:1}],...extra});
  await as(ids.seller);
  await t.test('a source from one customer cannot name another customer invoice',async()=>{
   await assert.rejects(create({invoice_id:invoices[1]}),/RETURN_INVOICE_SOURCE_MISMATCH/);
   assert.equal(await one('select count(*)::int from return_orders'),0);
  });
  const first=await create();
  await t.test('disabling Returns removes native detail and table reads',async()=>{
   assert.equal((await rpc('detail',{id:first.id})).id,first.id);
   await db.exec('reset role');await q("insert into app_modules(id,enabled) values('returns',false) on conflict(id) do update set enabled=false");await as(ids.seller);
   await assert.rejects(rpc('detail',{id:first.id}),/ROLE_NOT_ALLOWED/);assert.equal(await one('select count(*)::int from return_orders'),0);
   await db.exec('reset role');await q("update app_modules set enabled=true where id='returns'");await as(ids.admin);
  });
  await t.test('a refunded return cannot be cancelled to reuse its source quantity',async()=>{
   await rpc('refund',{id:first.id,amount:10,method:'bank',financial_account_id:ids.bank,request_key:uuid()});
   await assert.rejects(rpc('cancel',{id:first.id}),/RETURN_HAS_FINANCIAL_EFFECTS/);
   assert.equal((await rpc('detail',{id:first.id})).status,'to_process');
   const source=await rpc('source_lines',{kind:'customer',source_id:ids.delivery});assert.equal(source.rows[0].max_return,1);
   await assert.rejects(create({lines:[{line_id:dl,quantity:2}]}),/RETURN_EXCEEDS_DELIVERED/);
   assert.equal(Number(await one('select sum(amount) from return_refunds where return_id=$1',[first.id])),10);
  });
  await t.test('an untouched return can still be cancelled and recreated',async()=>{
   const clean=await create();await rpc('cancel',{id:clean.id});assert.ok((await create()).id);
  });
 }finally{await db.close()}
});
