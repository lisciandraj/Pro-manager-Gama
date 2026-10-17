const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('order follow-up scopes notes, audit and mailbox messages; service secrets are inaccessible',async()=>{
 const db=await restore(),admin=uuid(),other=uuid(),warehouse=uuid(),client=uuid(),customer=uuid(),supplier=uuid(),order=uuid(),purchase=uuid(),mailPurchase=uuid();
 const q=async(s,p=[])=>(await db.query(s,p)).rows;
 const rpc=async(action,data)=>(await q('select public.coco_order_followup($1,$2) r',[action,JSON.stringify(data)]))[0].r;
 const service=async(action,data)=>(await q('select public.coco_order_mail_service($1,$2) r',[action,JSON.stringify(data)]))[0].r;
 const base={kind:'sales',order_id:order};
 const actor=async(id,role='authenticated')=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role '+role)};
 try{
  for(const [id,email,role,name] of [[admin,'a@example.invalid','administrador','Alice'],[other,'b@example.invalid','administrador','Bob'],[warehouse,'w@example.invalid','almacenero','Warehouse'],[client,'c@example.invalid','cliente','Client']]){
   await q('insert into auth.users(id,email) values($1,$2)',[id,email]);await q('update profiles set active=true,role=$2,full_name=$3 where id=$1',[id,role,name]);
  }
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await q("insert into customers(id,name,email) values($1,'Customer','customer@example.invalid')",[customer]);await q("insert into suppliers(id,name,email) values($1,'Supplier','supplier@example.invalid')",[supplier]);
  await q("insert into sales_orders(id,customer_id,customer_name,created_by,request_key,status) values($1,$2,'Customer',$3,gen_random_uuid(),'draft')",[order,customer,admin]);
  await q("insert into purchase_orders(id,supplier_id,order_number,status,created_by) values($1,$2,'CHAT-PO','draft',$3)",[purchase,supplier,admin]);
  await q("insert into purchase_orders(id,supplier_id,order_number,status,created_by) values($1,$2,'CHAT-MAIL-PO','draft',$3)",[mailPurchase,supplier,admin]);
  await actor(admin);let result=await rpc('list',base);assert.equal(result.context.party,'Customer');assert(result.history.some(x=>x.action==='created'&&x.actor_name==='Alice'));
  const key=uuid(),note=await rpc('note',{...base,body:'Private operations note',request_key:key});assert.equal((await rpc('note',{...base,body:'Private operations note',request_key:key})).id,note.id);
  await assert.rejects(rpc('note',{...base,body:'changed',request_key:key}),/REQUEST_KEY_REUSED/);
  await assert.rejects(service('account',{user_id:admin}),/permission denied/);
  await assert.rejects(q('select * from private.coco_mail_accounts'),/permission denied/);
  await actor(admin,'service_role');await service('account_save',{user_id:admin,email:'a@example.invalid',provider:'google',credentials:'encrypted-test-only'});
  await service('oauth_store',{user_id:admin,state_hash:'opaque-hash',provider:'google',verifier:'ciphertext'});
  assert.equal((await service('oauth_take',{state_hash:'opaque-hash'})).user_id,admin);
  await assert.rejects(service('oauth_take',{state_hash:'opaque-hash'}),/OAUTH_EXPIRED/);
  await assert.rejects(service('account_save',{user_id:admin,email:'b@example.invalid',provider:'google',credentials:'test'}),/MAILBOX_EMAIL_MISMATCH/);
  await actor(admin);result=await rpc('context',base);assert.equal(result.mailbox.email,'a@example.invalid');assert(!JSON.stringify(result).includes('encrypted'));
  const payload={...base,to:'customer@example.invalid',subject:'Order',body:'Hello',request_key:uuid()},claim=await rpc('mail_claim',payload);assert.equal(claim.claimed,true);assert.equal((await rpc('mail_claim',payload)).claimed,false);
  await assert.rejects(rpc('mail_claim',{...payload,body:'other'}),/REQUEST_KEY_REUSED/);
  await assert.rejects(rpc('mail_claim',{...payload,request_key:uuid(),subject:'Header\r\nBcc: bad@example.invalid'}),/INVALID_MESSAGE/);
  await actor(admin,'service_role');await service('message_status',{user_id:admin,id:claim.id,status:'sent',provider_id:'sent-1',thread_id:'thread-1',internet_id:'<sent@example.invalid>'});
  const incoming={user_id:admin,...base,provider:'google',provider_id:'received-1',thread_id:'thread-1',internet_id:'<reply@example.invalid>',from_email:'customer@example.invalid',sender:'Customer',to_email:'a@example.invalid',subject:'Re: Order',body:'Yes please',created_at:new Date().toISOString()};
  assert.equal((await service('import',incoming)).imported,true);assert.equal((await service('import',incoming)).imported,false);
  await assert.rejects(service('import',{...incoming,thread_id:'unrelated'}),/THREAD_NOT_LINKED/);
  await actor(other);result=await rpc('list',base);assert(result.entries.some(x=>x.direction==='in'&&x.body==='Yes please'&&x.actor_name==='Customer'));assert(result.entries.some(x=>x.type==='note'&&x.actor_name==='Alice'));assert(!JSON.stringify(result).includes('encrypted-test-only'));assert(result.entries.filter(x=>x.type==='mail').every(x=>x.own_mailbox===false));
  await actor(warehouse);result=await rpc('list',base);assert.equal(result.context.can_mail,false);assert(!result.entries.some(x=>x.type==='mail'));await assert.rejects(rpc('mail_claim',{...payload,request_key:uuid()}),/MAILBOX_REQUIRED/);
  await actor(client);await assert.rejects(rpc('list',base),/ROLE_NOT_ALLOWED/);
  await actor(admin,'anon');await assert.rejects(rpc('list',base),/permission denied/);
  await actor(admin);await db.exec('reset role');await q("update public.sales_orders set notes='changed note' where id=$1",[order]);await actor(admin);result=await rpc('list',base);assert(result.entries.some(x=>x.subject==='order_updated'&&x.actor_name==='Alice'&&x.body.includes('notes')));
  result=await rpc('list',{kind:'purchase',order_id:purchase});assert.equal(result.context.email,'supplier@example.invalid');assert(result.history.some(x=>x.action==='purchase_created'));
  const mailBase={kind:'purchase',order_id:mailPurchase};
  const purchaseClaim=await rpc('mail_claim',{...payload,...mailBase,request_key:uuid()});
  await assert.rejects(rpc('purchase_mail_sent',{...mailBase,message_id:purchaseClaim.id}),/MESSAGE_NOT_SENT/);
  await assert.rejects(rpc('purchase_mail_sent',{...mailBase,message_id:claim.id}),/MESSAGE_NOT_SENT/);
  await actor(admin,'service_role');await service('message_status',{user_id:admin,id:purchaseClaim.id,status:'accepted',provider_id:'po-mail-1',thread_id:'po-thread-1'});
  await assert.rejects(service('message_status',{user_id:admin,id:purchaseClaim.id,thread_id:'thread-1'}),/THREAD_LINKED_ELSEWHERE/);
  await actor(admin);assert.equal((await rpc('purchase_mail_sent',{...mailBase,message_id:purchaseClaim.id})).status,'sent');
  await db.exec('reset role');await q("update public.purchase_orders set status='cancelled' where id=$1",[mailPurchase]);await actor(admin);
  assert.equal((await rpc('purchase_mail_sent',{...mailBase,message_id:purchaseClaim.id})).status,'cancelled');
  const manual={kind:'purchase',order_id:purchase,request_key:uuid(),body:'Confirmed by telephone'};
  const placed=await rpc('purchase_manual_sent',manual);assert.equal((await rpc('purchase_manual_sent',manual)).id,placed.id);
  result=await rpc('list',{kind:'purchase',order_id:purchase});assert.equal(result.context.status,'sent');assert(result.entries.some(x=>x.subject==='purchase_manual_sent'&&x.actor_name==='Alice'));
  await rpc('disconnect',base);assert.equal((await rpc('context',base)).mailbox,null);assert((await rpc('list',base)).entries.some(x=>x.direction==='in'));
 }finally{await db.close()}
});
