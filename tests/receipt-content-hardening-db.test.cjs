const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID:uuid}=require('node:crypto');
const fs=require('node:fs');
const path=require('node:path');
const {restore}=require('../scripts/restore-schema.cjs');
const {freshMigration}=require('../scripts/fresh-migration.cjs');

const migration='20261107195905_audit_receipt_validation.sql';
const pdf=Buffer.from('%PDF-1.7\n1 0 obj << /Type /Catalog >> endobj\n%%EOF\n');
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aOc8AAAAASUVORK5CYII=','base64');
const jpeg=Buffer.from([255,216,255,224,0,2,255,217]);
const webp=Buffer.from('RIFF0000WEBPfixture');
const receipt=(mime,bytes=pdf)=>({filename:'fixture.'+({ 'application/pdf':'pdf','image/png':'png','image/jpeg':'jpg','image/webp':'webp' }[mime]||'bin'),mime_type:mime,data_url:'data:'+mime+';base64,'+bytes.toString('base64')});

test('expense receipt storage validates passive content for legacy and commercial RPCs without rewriting history',async t=>{
 const db=await restore({before:migration}),admin=uuid(),customer=uuid(),employee=uuid();
 const q=async(sql,params=[])=>(await db.query(sql,params)).rows;
 const v=async(sql,params=[])=>Object.values((await q(sql,params))[0])[0];
 const as=async(id=admin,role='authenticated')=>{
  await db.exec('reset role');
  await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[id||'',JSON.stringify({sub:id||'',role,aal:'aal2'})]);
  await db.exec('set role '+role);
 };
 const legacy=(action,data={})=>v('select public.gama_accounting_action($1,$2::jsonb)',[action,JSON.stringify(data)]);
 const claim=(action,data={})=>v('select public.coco_expenses($1,$2::jsonb)',[action,JSON.stringify(data)]);
 let today,category,historicalExpense,historicalReceipt;
 const expensePayload=()=>({request_key:uuid(),description:'Receipt boundary fixture',expense_date:today,category_id:category,amount_untaxed:10,tax_amount:0,amount_total:10,currency:'USD',payment_method:'card'});
 const newExpense=async()=>{await as();return (await legacy('expense_save',expensePayload())).id;};
 const upload=(expense_id,file)=>legacy('expense_receipt',{expense_id,...file});
 const total=async()=>{await as(admin,'postgres');return Number(await v('select count(*) from expense_receipts'));};
 try{
  await q('insert into auth.users(id,email) values($1,$2),($3,$4)',[admin,'receipt-admin@example.invalid',customer,'receipt-client@example.invalid']);
  await q("update profiles set active=true,role=case when id=$1 then 'administrador' else 'cliente' end",[admin]);
  await q("update company_settings set currency='USD',country='EC',configured=true,legal_name='Receipt fixture',tax_id='1790012345001',address='Quito'");
  await q('insert into hr_employees(id,full_name) values($1,$2)',[employee,'Receipt fixture employee']);
  today=await v('select ((now() at time zone private.erp_timezone())::date)::text');
  category=await v('select id from expense_categories where active limit 1');
  historicalExpense=await newExpense();
  // This was accepted by the historical writer. Applying the new migration
  // must not scan, delete or silently transform the existing user's attachment.
  historicalReceipt=(await upload(historicalExpense,{filename:'historical.pdf',mime_type:'application/pdf',data_url:'https://example.invalid/historical-receipt.pdf'})).id;
  await as(admin,'postgres');
  const directory=path.join(__dirname,'../supabase/migrations');
  for(const file of fs.readdirSync(directory).filter(f=>f.endsWith('.sql')&&f>=migration).sort()){
   let sql=fs.readFileSync(path.join(directory,file),'utf8').replace(/create extension if not exists (pgcrypto|pg_cron|pg_net)(?: with schema \w+)?;/gi,'');
   await db.exec(freshMigration(file,sql));
  }

  await t.test('migration preserves historical bytes and validates a replacement at the shared boundary',async()=>{
   assert.equal(await v('select data_url from expense_receipts where id=$1',[historicalReceipt]),'https://example.invalid/historical-receipt.pdf');
   await q("update expense_receipts set filename='historical-renamed.pdf',data_url=data_url where id=$1",[historicalReceipt]);
   await assert.rejects(q("update expense_receipts set data_url='data:application/pdf;base64,PGh0bWw+' where id=$1",[historicalReceipt]),/RECEIPT_CONTENT_INVALID/);
   await q('update expense_receipts set data_url=$1 where id=$2',[receipt('application/pdf').data_url,historicalReceipt]);
   assert.equal(await v('select data_url from expense_receipts where id=$1',[historicalReceipt]),receipt('application/pdf').data_url);
  });

  await t.test('legacy RPC accepts the four matching MIME/signature pairs and exact stored bytes remain readable',async()=>{
   const expense=await newExpense();
   for(const [mime,bytes] of [['application/pdf',pdf],['image/png',png],['image/jpeg',jpeg],['image/webp',webp]]){
    const file=receipt(mime,bytes),id=(await upload(expense,file)).id;
    const saved=await legacy('expense_receipt_get',{id});
    assert.equal(saved.mime_type,mime);assert.equal(saved.data_url,file.data_url);
   }
  });

  await t.test('legacy RPC cannot bypass HTML, arbitrary URLs, mismatched MIME or malformed base64 rejection',async()=>{
   const expense=await newExpense(),before=await total();await as();
   const badFiles=[
    ['HTML MIME',receipt('text/html',Buffer.from('<html>not a passive receipt</html>'))],
    ['arbitrary HTTPS URL',{...receipt('application/pdf'),data_url:'https://example.invalid/file.pdf'}],
    ['quoted iframe attribute',{...receipt('application/pdf'),data_url:'x" onload="throw 1'}],
    ['HTML under PDF MIME',receipt('application/pdf',Buffer.from('<html>not a PDF</html>'))],
    ['PNG under PDF MIME',receipt('application/pdf',png)],
    ['metadata MIME differs from data URL',{...receipt('image/png',png),mime_type:'application/pdf'}],
    ['noncanonical unused base64 bits',{...receipt('application/pdf'),data_url:'data:application/pdf;base64,JVBERi1='}],
    ['unnecessary whitespace',{...receipt('application/pdf'),data_url:receipt('application/pdf').data_url+'\n'}],
    ['missing required padding',{...receipt('application/pdf'),data_url:'data:application/pdf;base64,JVBERi0'}],
    ['invalid alphabet',{...receipt('application/pdf'),data_url:'data:application/pdf;base64,%%%%'}],
    ['invalid padding',{...receipt('application/pdf'),data_url:'data:application/pdf;base64,AAAA===='}],
    ['empty body',{...receipt('application/pdf'),data_url:'data:application/pdf;base64,'}],
    ['partial PNG signature',receipt('image/png',png.subarray(0,7))],
    ['partial JPEG signature',receipt('image/jpeg',jpeg.subarray(0,2))],
    ['wrong WebP container type',receipt('image/webp',Buffer.from('RIFF0000WAVEdata'))]
   ];
   for(const [name,file] of badFiles)await assert.rejects(upload(expense,file),/RECEIPT_CONTENT_INVALID/,name);
   assert.equal(await total(),before,'invalid uploads allocate no receipt rows');
  });

  await t.test('decoded byte cap is enforced before an oversized receipt reaches storage',async()=>{
   const expense=await newExpense(),oversized=Buffer.alloc(2000001,32);pdf.subarray(0,5).copy(oversized);
   await assert.rejects(upload(expense,receipt('application/pdf',oversized)),/RECEIPT_CONTENT_INVALID/);
   await as(admin,'postgres');
   assert.equal(Number(await v('select count(*) from expense_receipts where expense_id=$1',[expense])),0);
  });

  await t.test('commercial save uses the same trigger and rolls back the entire invalid claim',async()=>{
   await as();
   const payload={...expensePayload(),version:0,paid_by:'employee',employee_id:employee,due_date:today};
   const valid=await claim('save',{...payload,receipt:receipt('application/pdf')});
   assert.ok(valid.id);
   await as(admin,'postgres');
   assert.equal((await q('select mime_type,data_url from expense_receipts where expense_id=$1',[valid.id]))[0].data_url,receipt('application/pdf').data_url);
   const beforeExpenses=Number(await v('select count(*) from expenses')),beforeClaims=Number(await v('select count(*) from private.expense_claims'));
   await as();
   await assert.rejects(claim('save',{...payload,request_key:uuid(),description:'Invalid commercial receipt',receipt:receipt('application/pdf',Buffer.from('<html>rejected</html>'))}),/RECEIPT_CONTENT_INVALID/);
   await as(admin,'postgres');
   assert.equal(Number(await v('select count(*) from expenses')),beforeExpenses);
   assert.equal(Number(await v('select count(*) from private.expense_claims')),beforeClaims);
  });

  await t.test('the validator is internal and an unauthorised customer gains no upload API',async()=>{
   await as();await assert.rejects(v('select private.coco_receipt_content_valid($1,$2)',['application/pdf',receipt('application/pdf').data_url]),/permission denied/);
   await as(customer);await assert.rejects(upload(historicalExpense,receipt('application/pdf')),/NOT_ALLOWED|ROLE_NOT_ALLOWED|AUTH_OR_MFA_REQUIRED/);
   await as(null,'anon');await assert.rejects(upload(historicalExpense,receipt('application/pdf')),/permission denied/);
  });
 }finally{await db.close();}
});
