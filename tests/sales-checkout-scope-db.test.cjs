const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{fixture}=require('./helpers/checkout-fixture.cjs');
test('staff checkout preserves shared quote visibility across commercial users',async()=>{
 const f=await fixture(),db=f.db,q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0],users=[uuid(),uuid()],quotes=[];
 const as=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await q("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id,role:'authenticated',aal:'aal1'})]);await db.exec('set role authenticated')};try{
  await db.exec('reset role');await q('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now()),($3,$4,now())',[users[0],'checkout-scope-a@example.invalid',users[1],'checkout-scope-b@example.invalid']);await q("update profiles set active=true,role='comercial' where id=any($1::uuid[])",[users]);
  for(const id of users){await as(id);quotes.push((await v("select public.gama_quote_action('save',$1::jsonb)",[JSON.stringify({request_key:uuid(),customer_id:f.ids.customer,issue_date:new Date().toISOString().slice(0,10),valid_until:'2099-01-01',details:{seller:'Coco',client:'Marie Client',delivery_address:'Quito'},lines:[{product_id:f.ids.product,description:'Shared quote scope',quantity:1,list_price:10,tax_rate:0,discount:0,price_mode:'auto'}]})])).id)}
  assert.equal((await q('select id from public.invoices where id=any($1::uuid[])',[quotes])).rows.length,2);
  for(const id of quotes)assert.deepEqual(await v("select public.coco_sales_checkout('context',$1::jsonb)",[JSON.stringify({quote_id:id})]),{invitations:[]});
 }finally{await db.close()}
});
