const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('Stock 19 additive upgrade preserves existing valuation and posted balances',async()=>{
 const migration=fs.readdirSync(path.join(__dirname,'../supabase/migrations')).find(f=>f.endsWith('_accounting_stock19_review.sql'));
 const db=await restore({before:migration}),admin=uuid();
 const v=async(s,p=[])=>Object.values((await db.query(s,p)).rows[0])[0],rpc=(a,d)=>v('select gama_valuation($1,$2::jsonb)',[a,JSON.stringify(d)]);
 const snapshot=async()=>{
  const tables={};for(const name of ['stock_cost_books','stock_cost_layers','stock_valuation_entries','accounting_entries','accounting_entry_lines','stock_quants','stock_movements'])tables[name]=await v(`select md5(coalesce(jsonb_agg((to_jsonb(t)-'standard_unit_cost'-'effective_on') order by to_jsonb(t)::text),'[]')::text) from public.${name} t`);return tables;
 };
 try{
  await db.query('insert into auth.users(id,email) values($1,$2)',[admin,'stock-upgrade@example.invalid']);await db.exec("update profiles set active=true,role='administrador'");await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  const product=await v("insert into products(name,purchase_price) values('Preserved FIFO stock',12) returning id"),loc=await v('select id from warehouse_locations where active limit 1');
  await v("select gama_stock_adjust($1,$2,8,null,'Isolated legacy stock')",[product,loc]);
  await rpc('configure',{request_key:uuid(),product_id:product,method:'fifo',opening_unit_cost:'12',reason:'Observed isolated historical cost'});
  const chart=Object.fromEntries((await db.query("select code,id from accounting_accounts where code in('1200','5000','2000','3000')")).rows.map(r=>[r.code,r.id]));
  await v("select gama_accounting_audit('stock_accounting_save',$1::jsonb)",[JSON.stringify({request_key:uuid(),product_id:product,stock_account_id:chart['1200'],expense_account_id:chart['5000'],receipt_account_id:chart['2000'],opening_counter_account_id:chart['3000'],auto_accounting:true,reason:'Approved isolated legacy automation'})]);
  const before=await snapshot(),report=await rpc('report',{});assert.equal(report.items[0].value,96);
  await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations',migration),'utf8'));assert.deepEqual(await snapshot(),before);
  assert.equal(await v('select count(*)::int from private.accounting_stock_policies'),0);assert.equal(await v('select count(*)::int from private.accounting_stock_reviews'),0);
  assert.equal((await rpc('report',{})).items[0].value,96);
  await v("select gama_stock_adjust($1,$2,5,null,'Preserved legacy consumption')",[product,loc]);
  assert.equal((await rpc('report',{})).items[0].value,60);
  assert.equal(Number(await v("select sum(l.debit-l.credit) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where e.status='posted' and l.account_id=$1",[chart['1200']])),60);
  await assert.rejects(v("select gama_accounting_stock19('policy',$1::jsonb)",[JSON.stringify({request_key:uuid(),product_id:product,reason:'Cannot silently change legacy policy',start_date:'2026-10-27',mode:'periodic'})]),/LEGACY_TRANSITION_REQUIRED/);
 }finally{await db.close()}
});
