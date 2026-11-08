const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid,randomBytes,createHash}=require('node:crypto'),{fixture}=require('./helpers/early-discount-fixture.cjs');
test('posted invoice capabilities freeze private PDFs, remain actor-bound and preserve accounting-only history access',async t=>{
 const {db,ids,value:v,q,rpc,direct}=await fixture(),staff=(a,d)=>rpc('coco_sales_checkout',a,d),sha=createHash('sha256').update('%PDF-1.4 immutable invoice fixture').digest('hex');
 const denied=async(fn,re)=>{await db.exec('savepoint denied');try{await assert.rejects(fn(),re)}finally{await db.exec('rollback to denied;release denied')}};
 try{
  await db.exec('begin');
  const i=await direct(),id=uuid(),token=randomBytes(32).toString('hex');
  await db.exec('reset role');await q("insert into storage.objects(bucket_id,name,owner_id,metadata) values('sales-checkout-documents',$1,$2,'{\"size\":35,\"mimetype\":\"application/pdf\"}')",[ids.admin+'/'+id+'.pdf',ids.admin]);await db.exec('set role authenticated');
  const payload={id,token,invoice_id:i.id,revision:i.direct_revision,pdf_sha256:sha,require_signature:false,payment_percent:100};
  const saved=await staff('create',payload);assert.equal(saved.id,id);assert.deepEqual(await staff('create',payload),saved);await denied(()=>staff('create',{...payload,expires_at:new Date(Date.now()+86400000).toISOString()}),/REQUEST_KEY_CONFLICT/);
  const context=await staff('context',{invoice_id:i.id});assert.equal(context.invitations.length,1);assert.equal(context.invitations[0].require_signature,false);assert.ok(!JSON.stringify(context).includes(token));
  await denied(()=>staff('create',{...payload,id:uuid(),require_signature:true}),/CHECKOUT_INVOICE_OPTIONS_INVALID/);
  await db.exec('reset role');const record=(await q('select * from private.sales_checkout_invitations where id=$1',[id])).rows[0];assert.equal(record.quote_id,null);assert.equal(record.document.invoice_id,i.id);assert.equal(record.document.total,121);assert.equal(record.document.lines[0].description,'Isolated service');assert.ok(!JSON.stringify(record.document).includes('account_id'));assert.equal(record.token_hash,createHash('sha256').update(token).digest('hex'));
  const history=(await q("select * from private.coco_module_events where record_table='sales_checkout_invitations' and record_id=$1",[id])).rows;assert.ok(history.some(h=>h.module_id==='accounting'));assert.ok(!JSON.stringify(history).includes(token));await db.exec('set role authenticated');
  assert.equal((await q("delete from storage.objects where bucket_id='sales-checkout-documents' and name=$1 returning id",[record.pdf_path])).rows.length,0);
  await db.exec("reset role;update role_module_access set disabled_modules=array_append(disabled_modules,'quotes') where role='comercial';set role authenticated");
  await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.reader]);assert.equal(await v("select private.erp_module_allowed('quotes',array['administrador','comercial'])"),false);assert.equal((await staff('context',{invoice_id:i.id})).can_create,false);assert.equal(await v("select private.coco_history_record_visible('sales_checkout_invitations',$1,null)",[id]),true);await denied(()=>staff('create',{...payload,id:uuid()}),/ROLE_NOT_ALLOWED/);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);assert.equal((await staff('revoke',{id,invoice_id:i.id})).revoked,true);assert.equal((await staff('context',{invoice_id:i.id})).invitations[0].revoked_at!==null,true);
  await denied(()=>staff('evidence',{id,invoice_id:i.id}),/CHECKOUT_SIGNATURE_NOT_FOUND/);
 }finally{await db.exec('rollback');await db.close()}
});
