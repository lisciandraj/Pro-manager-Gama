const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),fs=require('node:fs');
const {restore}=require('../scripts/restore-schema.cjs'),migration='20261018102218_unified_legacy_draft_references.sql';
test('old drafts use SOL while issued archives keep COT without rewriting commercial data',async()=>{
 const db=await restore({before:migration}),admin=uuid(),draft=uuid(),issued=uuid(),fresh=uuid();
 const q=async(s,p=[])=>(await db.query(s,p)).rows,one=async(s,p=[])=>Object.values((await q(s,p))[0])[0];
 const list=()=>one("select public.gama_sales_workspace('quote_list','{\"layout\":\"requests-quotes\"}')");
 try{
  await q("insert into auth.users(id,email,email_confirmed_at) values($1,'legacy-unified-admin@example.invalid',now())",[admin]);await q("update profiles set role='administrador',active=true where id=$1",[admin]);await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await q("insert into invoices(id,user_id,status,quote_state,subtotal,tax,total) values($1,$3,'draft',null,10,1.5,11.5),($2,$3,'issued',null,20,3,23)",[draft,issued,admin]);
  const before=await q('select id,invoice_number,status,quote_state,subtotal,tax,total from invoices order by id');
  await db.exec(fs.readFileSync('supabase/migrations/'+migration,'utf8'));await db.exec('set role authenticated');
  const rows=(await list()).rows;assert.match(rows.find(r=>r.id===draft).display_reference,/^SOL-\d{8}$/);assert.equal(rows.find(r=>r.id===draft).quote_state,'draft');assert.equal(rows.find(r=>r.id===issued).display_reference,before.find(r=>r.id===issued).invoice_number);assert.equal(rows.find(r=>r.id===issued).quote_state,'legacy');
  const filtered=await one("select public.gama_sales_workspace('quote_list','{\"layout\":\"requests-quotes\",\"status\":\"draft\"}')");assert.equal(filtered.total,1);assert.equal(filtered.rows[0].id,draft);
  await db.exec('reset role');assert.deepEqual(await q('select id,invoice_number,status,quote_state,subtotal,tax,total from invoices order by id'),before);
  await q("insert into invoices(id,user_id,status,quote_state) values($1,$2,'draft',null)",[fresh,admin]);assert.equal(await one("select count(*) from private.erp_issued_references where kind='request' and document_key='draft/invoices/'||$1::text",[fresh]),1);
  assert.equal(await one("select count(*) from private.erp_issued_references where kind='request' and document_key='draft/invoices/'||$1::text",[issued]),0);
  for(const table of ['customer_requests','sales_orders','stock_reservations','stock_movements','external_invoices'])assert.equal(await one('select count(*) from '+table),0);
 }finally{await db.close()}
});
