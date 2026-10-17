const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('dossier discussion preserves history, retires mailbox OAuth and requires human approval for ChatGPT proposals',async t=>{
 const db=await restore(),ids=Object.fromEntries(['admin','other','warehouse','client','customer','supplier','order','purchase','product','delivery'].map(k=>[k,uuid()]));
 const q=async(s,p=[])=>(await db.query(s,p)).rows,one=async(s,p=[])=>Object.values((await q(s,p))[0])[0];
 const actor=async(id,role='authenticated')=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role '+role)};
 const rpc=(a,d)=>one('select public.coco_dossier($1,$2::jsonb)',[a,JSON.stringify(d)]),bridge=(a,d)=>one('select public.coco_mail_bridge($1,$2::jsonb)',[a,JSON.stringify({mailbox_email:'bridge@example.invalid',...d})]);
 const base={kind:'sales',order_id:ids.order},inbox={kind:'sales',order_id:null};
 try{
  for(const [key,role,email,name] of [['admin','administrador','bridge@example.invalid','Alice'],['other','administrador','other@example.invalid','Bob'],['warehouse','almacenero','warehouse@example.invalid','Warehouse'],['client','cliente','client@example.invalid','Client']]){
   await q('insert into auth.users(id,email) values($1,$2)',[ids[key],email]);await q('update profiles set active=true,role=$2,full_name=$3 where id=$1',[ids[key],role,name]);
  }
  await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);
  await q("update company_settings set currency='USD',country='EC',configured=true,legal_name='Coco',tax_id='1790012345001',address='Quito'");
  await q("insert into customers(id,name,address,email) values($1,'Costa Azul','Quito','customer@example.invalid')",[ids.customer]);
  await q("insert into suppliers(id,name,email) values($1,'Supplier','supplier@example.invalid')",[ids.supplier]);
  await q("insert into products(id,name,reference,barcode,sale_price,purchase_price,tax_rate,base_unit) values($1,'Paper','CHAT-A4','CHAT-A4',10,4,15,'Unidad')",[ids.product]);
  await q("insert into sales_orders(id,customer_id,customer_name,created_by,request_key,status) values($1,$2,'Costa Azul',$3,gen_random_uuid(),'draft')",[ids.order,ids.customer,ids.admin]);
  await q("insert into purchase_orders(id,supplier_id,order_number,status,created_by) values($1,$2,'CHAT-PO','draft',$3)",[ids.purchase,ids.supplier,ids.admin]);
  await db.exec('set session_replication_role=replica');await q("insert into tms_deliveries(id,customer,address,status,created_by,customer_id) values($1,'Costa Azul','Quito','Pendiente de preparación',$2,$3)",[ids.delivery,ids.admin,ids.customer]);await db.exec('set session_replication_role=origin');
  await q("insert into hr_employees(full_name,profile_id,photo_data) values('Alice',$1,'data:image/png;base64,AA=='),('Other',$2,'data:image/png;base64,AA==')",[ids.admin,ids.other]);
  await actor(ids.admin);
  await t.test('notes are attributed and idempotent; old mailbox access is removed',async()=>{
   const data={...base,body:'Appel client',request_key:uuid()},r=await rpc('note',data);assert.equal((await rpc('note',data)).id,r.id);
   await assert.rejects(rpc('note',{...data,body:'changed'}),/REQUEST_KEY_REUSED/);
   const result=await rpc('list',base);assert(result.entries.some(x=>x.actor_id===ids.admin&&x.actor_name==='Alice'));assert(result.history.some(x=>x.action==='created'&&x.actor_id===ids.admin));assert(result.context.stages.length>=5);assert(result.portraits[ids.admin]);assert.equal(result.portraits[ids.other],undefined);assert.equal(result.context.mailbox,undefined);
   await assert.rejects(one('select public.coco_order_followup($1,$2)',['mail_claim',JSON.stringify(base)]),/MAIL_CONNECTOR_REMOVED/);
   await assert.rejects(bridge('enable',{}),/permission denied/);
   await assert.rejects(q('select * from private.coco_mail_proposals'),/permission denied/);
   await actor(ids.admin,'service_role');await assert.rejects(one('select public.coco_order_mail_service($1,$2)',['account',JSON.stringify({user_id:ids.admin})]),/permission denied/);await bridge('enable',{});await actor(ids.admin);
  });
  let proposal;
  const mail={message_id:'gmail-message-1',thread_id:'thread-1',source_email:'customer@example.invalid',subject:'Devis papier',received_at:new Date().toISOString(),kind:'sales',target_kind:'quote',action:'quote_draft',summary:'Le client demande 3 paquets de papier.',payload:{customer_id:ids.customer,customer_name:'Costa Azul',lines:[{product_id:ids.product,description:'Paper',quantity:3}]}};
  await t.test('mail ingestion creates only a pending note and never a quote or order',async()=>{
   await actor(ids.admin,'service_role');const context=await bridge('context',{source_email:mail.source_email,search:'CHAT-A4'});assert.equal(context.contacts[0].id,ids.customer);assert.equal(context.products[0].id,ids.product);const reference=await one('select order_number from public.purchase_orders where id=$1',[ids.purchase]);const dossier=await bridge('context',{source_email:'supplier@example.invalid',reference});assert.equal(dossier.dossiers[0].id,ids.purchase);assert.equal((await bridge('context',{source_email:mail.source_email,reference})).dossiers.length,0);
   await assert.rejects(bridge('propose',{...mail,message_id:'wrong-dossier',kind:'purchase',target_kind:'purchase',target_id:ids.purchase,action:'record_note'}),/MAIL_TARGET_MISMATCH/);const before=await one('select count(*) from invoices');proposal=await bridge('propose',mail);assert.equal(proposal.status,'pending');assert.equal((await bridge('propose',mail)).duplicate,true);assert.equal(await one('select count(*) from invoices'),before);
   await actor(ids.admin);const data=await rpc('list',inbox);assert(data.entries.some(x=>x.actor_name==='ChatGPT'&&x.type==='note'));assert.equal(data.proposals[0].status,'pending');
  });
  let result;
  await t.test('a checked proposal creates exactly one draft with ERP prices, validation author and source note',async()=>{
   const data={...inbox,proposal_id:proposal.id};await assert.rejects(rpc('approve_proposal',{...data,hash:'invented'}),/PROPOSAL_CHANGED/);
   let review=await rpc('review_proposal',data);assert.equal(review.review.lines[0].list_price,10);
   await db.exec('reset role');await q('update products set sale_price=12 where id=$1',[ids.product]);await actor(ids.admin);await assert.rejects(rpc('approve_proposal',{...data,hash:review.hash}),/PROPOSAL_CHANGED/);
   review=await rpc('review_proposal',{...data,payload:{...mail.payload,delivery_address:'Nouvelle adresse Quito'}});assert.equal(review.review.lines[0].list_price,12);
   result=await rpc('approve_proposal',{...data,hash:review.hash});assert.equal((await rpc('approve_proposal',{...data,hash:review.hash})).id,result.id);
   const doc=(await q('select quote_state,quote_details,total from invoices where id=$1',[result.id]))[0];assert.equal(doc.quote_state,'draft');assert.equal(doc.quote_details.delivery_address,'Nouvelle adresse Quito');assert.equal(Number(doc.total),41.4);
   assert.equal(await one('select count(*) from sales_orders'),1);const history=await rpc('list',{kind:'quote',order_id:result.id});assert(history.entries.some(x=>x.actor_name==='ChatGPT'));assert(history.entries.some(x=>x.actor_name==='Alice'&&x.subject==='proposal_approved'));
  });
  await t.test('shared notes and refusal work for purchases and TMS, respecting module rights',async()=>{
   for(const kind of ['purchase','tms']){
    const order_id=ids[kind==='purchase'?'purchase':'delivery'];await actor(ids.admin,'service_role');const r=await bridge('propose',{...mail,source_email:kind==='purchase'?'supplier@example.invalid':mail.source_email,message_id:'mail-'+kind,kind,target_kind:kind,target_id:order_id,action:'record_note',summary:'Confirmer le rendez-vous par téléphone',payload:{}});await actor(ids.admin);
    const data={kind,order_id,proposal_id:r.id};assert.equal((await rpc('list',data)).proposals[0].status,'pending');await rpc('reject_proposal',data);assert.equal((await rpc('list',data)).proposals[0].status,'rejected');
   }
   await actor(ids.admin);const manual={kind:'purchase',order_id:ids.purchase,request_key:uuid(),body:'Confirmed by telephone'};const placed=await one('select public.coco_order_followup($1,$2)',['purchase_manual_sent',JSON.stringify(manual)]);assert.equal((await one('select public.coco_order_followup($1,$2)',['purchase_manual_sent',JSON.stringify(manual)])).id,placed.id);
   await actor(ids.warehouse);const data=await rpc('list',base);assert(data.entries.some(x=>x.body==='Appel client'));assert.equal(data.context.can_review,false);await assert.rejects(rpc('approve_proposal',{...inbox,proposal_id:proposal.id}),/ROLE_NOT_ALLOWED/);
   await db.exec('reset role');const driver=uuid();await q("insert into hr_employees(full_name,profile_id) values('Driver',$1) returning id",[ids.warehouse]).then(async rows=>q("insert into fleet_drivers(id,name,employee_id) values($1,'Driver',$2)",[driver,rows[0].id]));await actor(ids.warehouse);await assert.rejects(rpc('list',{kind:'tms',order_id:ids.delivery}),/TMS_ACCESS_DENIED/);
   await actor(ids.client);await assert.rejects(rpc('list',base),/ROLE_NOT_ALLOWED/);await actor(ids.admin,'anon');await assert.rejects(rpc('list',base),/permission denied/);
   await actor(ids.admin);await rpc('bridge_disable',inbox);await actor(ids.admin,'service_role');await assert.rejects(bridge('propose',{...mail,message_id:'paused'}),/BRIDGE_DISABLED/);
  });
 }finally{await db.close()}
});
