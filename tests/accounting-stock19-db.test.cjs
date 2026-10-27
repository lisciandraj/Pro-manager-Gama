const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('Stock 19 observed costs and reviewed periodic closing use the canonical ledger',async t=>{
 const db=await restore(),admin=uuid(),reader=uuid(),supplier=uuid();
 const q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const rpc=(fn,a,d={})=>v(`select public.${fn}($1,$2::jsonb)`,[a,JSON.stringify(d)]),api=(a,d={})=>rpc('gama_accounting_stock19',a,d);
 const write=(a,d={})=>api(a,{request_key:uuid(),reason:'Reviewed isolated accounting fixture',...d});
 let day,location,chart,journal;
 const product=async()=>v("insert into products(name,purchase_price) values($1,99) returning id",['Isolated stock nineteen '+uuid()]);
 const book=(id,method='fifo',cost='12')=>write('configure',{product_id:id,method,opening_unit_cost:cost});
 const policy=(id,extra={})=>write('policy',{product_id:id,mode:'periodic',standard:'continental',start_date:day,stock_account_id:chart['1200'],expense_account_id:chart['5000'],variation_account_id:chart['6010'],journal_id:journal,...extra});
 const receive=async(id,qty,cost)=>{
  const order=await v('select gama_purchase_save($1::jsonb)',[JSON.stringify({request_key:uuid(),supplier_id:supplier,lines:[{product_id:id,quantity:qty,unit_cost:cost,tax_rate:0}]})]);
  await q("update purchase_orders set status='sent' where id=$1",[order.id]);const line=await v('select id from purchase_order_lines where purchase_order_id=$1',[order.id]);
  return v('select gama_receive_purchase_once($1::jsonb)',[JSON.stringify({request_key:uuid(),purchase_order_id:order.id,lines:[{line_id:line,quantity:qty,location_id:location.id}],comment:'Isolated counted stock'})]);
 };
 const adjust=(id,qty)=>v('select gama_stock_adjust($1,$2,$3,null,$4)',[id,location.id,qty,'Isolated approved count']);
 const balance=async id=>Number(await v("select coalesce(sum(l.debit-l.credit),0)::numeric from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where account_id=$1 and e.status in('posted','reversed')",[id]));
 const preview=()=>api('preview',{as_of:day});
 const generate=async()=>write('generate',{as_of:day,revision:(await preview()).revision});
 const deny=async(fn,pattern)=>{await db.exec('savepoint rejection');try{await assert.rejects(fn(),pattern)}finally{await db.exec('rollback to rejection;release rejection')}};
 const scenario=(name,fn)=>t.test(name,async()=>{await db.exec('begin');try{await fn()}finally{await db.exec('rollback;set role authenticated');await q("select set_config('request.jwt.claim.sub',$1,false)",[admin])}});
 try{
  await q('insert into auth.users(id,email) values($1,$2),($3,$4)',[admin,'stock19@example.invalid',reader,'stock-reader@example.invalid']);await q("update profiles set active=true,role=case when id=$1 then 'administrador' else 'comercial' end",[admin]);
  await q('insert into accounting_permissions(profile_id,can_view,can_read_all,can_edit,can_validate) values($1,true,true,false,false)',[reader]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await q("insert into suppliers(id,name) values($1,'Isolated stock supplier')",[supplier]);
  chart=Object.fromEntries((await q("select code,id from accounting_accounts where code in('1200','5000','6010')")).rows.map(r=>[r.code,r.id]));journal=await v("select id from accounting_journals where code='OD'");
  location=(await q('select id from warehouse_locations where active limit 1')).rows[0];day=await v("select ((now() at time zone private.erp_timezone())::date)::text");await db.exec('set role authenticated');
  await scenario('unvalued physical quantity blocks closing without inventing catalogue cost',async()=>{
   const id=await product();await adjust(id,5);const p=await preview();assert.equal(p.blocked,1);assert.equal(p.products[0].value,null);assert.equal(p.products[0].review,'cost_book_missing');
   await deny(()=>generate(),/COVERAGE_INCOMPLETE/);assert.equal(await v('select count(*)::int from accounting_entries'),0);
  });
  for(const method of ['fifo','avco','standard'])await scenario('receipt, shipment, draft and posting: '+method,async()=>{
   const id=await product();await book(id,method,'12');await policy(id);await receive(id,10,10);await receive(id,10,20);await adjust(id,8);
   const expected={fifo:160,avco:120,standard:96}[method],p=await preview();assert.equal(p.blocked,0);assert.equal(p.products[0].value,expected);assert.equal(p.accounts[0].inventory_value,expected);assert.equal(await balance(chart['1200']),0);
   const input={request_key:uuid(),reason:'Reviewed isolated stock closing',as_of:day,revision:p.revision},draft=await api('generate',input);assert.deepEqual(await api('generate',input),draft);
   assert.equal(await balance(chart['1200']),0);let d=await api('detail',{id:draft.id});assert.equal(d.entries[0].status,'draft');assert.equal(d.entries[0].lines[0].debit,expected);
   await deny(()=>generate(),/DRAFT_EXISTS/);await write('post',{id:draft.id});assert.equal(Number(await balance(chart['1200'])),expected);assert.equal(Number(await balance(chart['6010'])),-expected);
   assert.equal((await preview()).accounts[0].difference,0);await deny(()=>generate(),/ALREADY_ALIGNED/);
   const totals=(await q('select sum(debit)::text debit,sum(credit)::text credit from accounting_entry_lines')).rows[0];assert.equal(totals.debit,totals.credit);
  });
  await scenario('cost revision revalues only remaining stock and preserves movement evidence',async()=>{
   const id=await product();await book(id,'standard','12');await policy(id);await receive(id,8,30);await adjust(id,5);
   const count=await v('select count(*)::int from stock_movements');await write('standard_cost',{product_id:id,unit_cost:'15'});assert.equal(await v('select count(*)::int from stock_movements'),count);
   assert.equal((await preview()).products[0].value,75);assert.equal(Number(await v("select value_delta from stock_valuation_entries where kind='revaluation'")),15);
   await deny(()=>write('standard_cost',{product_id:id,unit_cost:'NaN'}),/NUMBER_INVALID/);
  });
  await scenario('changed inventory expires a draft, which can be discarded and regenerated',async()=>{
   const id=await product();await book(id);await policy(id);await receive(id,8,12);const d=await generate();await adjust(id,5);
   await deny(()=>write('post',{id:d.id}),/REVIEW_STALE/);assert.equal(await balance(chart['1200']),0);
   await write('discard',{id:d.id});assert.equal((await api('detail',{id:d.id})).review.status,'cancelled');assert.equal(await v('select count(*)::int from accounting_entries'),0);
   const next=await generate();await write('post',{id:next.id});assert.equal(Number(await balance(chart['1200'])),60);
  });
  await scenario('locked dates, request conflicts, API permissions and Agent proposals are enforced',async()=>{
   const id=await product();await book(id);const request={request_key:uuid(),reason:'Reviewed accounting policy',product_id:id,mode:'periodic',standard:'anglo_saxon',start_date:day,stock_account_id:chart['1200'],expense_account_id:chart['5000'],variation_account_id:chart['6010'],journal_id:journal};
   const p=await api('policy',request);assert.deepEqual(await api('policy',request),p);await deny(()=>api('policy',{...request,standard:'continental'}),/REQUEST_KEY_CONFLICT/);await receive(id,8,12);const d=await generate();
   await q("select set_config('coco.activity_source_type','chat',true)");await deny(()=>write('post',{id:d.id}),/HUMAN_APPROVAL/);await q("select set_config('coco.activity_source_type','',true)");
   await q("select set_config('request.jwt.claim.sub',$1,false)",[reader]);await deny(()=>write('post',{id:d.id}),/NOT_ALLOWED/);await deny(()=>q('select * from private.accounting_stock_reviews'),/permission denied/);
   await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await rpc('gama_accounting_configuration','lock_save',{request_key:uuid(),kind:'all',lock_date:day,reason:'Isolated locked stock period'});await deny(()=>write('post',{id:d.id}),/DATE_LOCKED/);
   await db.exec('reset role;set role anon');await deny(()=>api('context'),/permission denied/);
  });
  await scenario('old movement automation cannot coexist with a new policy',async()=>{
   const id=await product();await book(id);await policy(id);const receipt=await v("select id from accounting_accounts where code='2000'"),opening=await v("select id from accounting_accounts where code='3000'");await deny(()=>rpc('gama_accounting_audit','stock_accounting_save',{request_key:uuid(),product_id:id,stock_account_id:chart['1200'],expense_account_id:chart['5000'],receipt_account_id:receipt,opening_counter_account_id:opening,auto_accounting:true,reason:'Conflicting isolated automation'}),/POLICY_IMMUTABLE/);
  });
  await scenario('correction retains original entries, uses the chosen open date and is idempotent',async()=>{
   const id=await product();await book(id);await policy(id);await receive(id,8,12);const d=await generate();await write('post',{id:d.id});
   const r={id:d.id,request_key:uuid(),reversal_date:day,reason:'Reviewed isolated stock correction'};const reversed=await api('reverse',r);assert.deepEqual(await api('reverse',r),reversed);
   const detail=await api('detail',{id:d.id});assert.equal(detail.review.status,'reversed');assert.ok(detail.entries[0].reversal_entry_id);assert.equal(Number(await balance(chart['1200'])),0);
   assert.equal(await v('select entry_date::text from accounting_entries where id=$1',[detail.entries[0].reversal_entry_id]),day);
   assert.equal((await preview()).accounts[0].difference,96);await deny(()=>write('reverse',{...r,request_key:uuid()}),/STATE_INVALID/);
  });
  await scenario('the old manual valuation API cannot double-post a periodic product',async()=>{
   const id=await product();await book(id);await policy(id);await receive(id,8,12);
   const sequence=await v("select max(sequence)::int from stock_valuation_entries where product_id=$1",[id]);await deny(()=>rpc('gama_accounting_ec','valuation_post',{request_key:uuid(),sequence,counter_account_id:chart['6010'],reason:'Old movement posting attempt'}),/USE_CLOSING/);
  });
  await scenario('all pages and historical opening boundaries retain real sources',async()=>{
   const ids=[];for(let i=0;i<51;i++){const id=await product();ids.push(id);await book(id)}
   const first=await preview(),last=await api('preview',{as_of:day,offset:50});assert.equal(first.total,51);assert.equal(first.products.length,50);assert.equal(last.products.length,1);assert.equal(first.revision,last.revision);assert.equal(first.blocked,51);
   const old=await api('preview',{as_of:'2000-01-01'});assert.ok(old.products.every(p=>p.value===null));
  });
 }finally{await db.close()}
});
