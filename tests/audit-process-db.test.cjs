const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('shared process state includes service completion, full credit, open return and purchase follow-up',async()=>{
 const db=await restore(),u=uuid(),customer=uuid(),product=uuid(),order=uuid(),line=uuid(),invoice=uuid(),quote=uuid(),ret=uuid(),supplier=uuid();
 const rpc=async(n,a,d)=>(await db.query(`select ${n}($1,$2) r`,[a,d])).rows[0].r;
 try{
 await db.exec(`insert into auth.users(id,email) values('${u}','audit-process@example.invalid');update profiles set active=true,role='administrador';select set_config('request.jwt.claim.sub','${u}',false);
 insert into customers(id,name) values('${customer}','Audit client');insert into suppliers(id,name) values('${supplier}','Audit supplier');
 insert into products(id,name,product_kind,sale_price) values('${product}','Audit service','service',100);
 insert into invoices(id,invoice_number,quote_state,quote_details) values('${quote}','AUDIT-Q','draft','{}');
 insert into sales_orders(id,customer_id,customer_name,created_by,request_key,status) values('${order}','${customer}','Audit client','${u}',gen_random_uuid(),'confirmed');
 insert into sales_order_lines(id,order_id,product_id,product_name,product_kind,quantity,unit_price,tax_rate) values('${line}','${order}','${product}','Audit service','service',1,100,0);
 insert into sales_service_completions(order_line_id,quantity,performed_on,evidence,created_by) values('${line}',1,current_date,'Signed work report','${u}');
 insert into external_invoices(id,request_key,order_id,number,issuer_ruc,issue_date,subtotal,tax,fiscal_status,document_kind,source_quote_id,document_snapshot,created_by) values('${invoice}',gen_random_uuid(),'${order}','AUDIT-001','0999999999001',current_date,100,0,'unverified','internal','${quote}','{}','${u}');
 insert into external_invoice_lines(invoice_id,order_line_id,quantity) values('${invoice}','${line}',1);
 insert into return_orders(id,kind,status,customer_id,order_id,invoice_id,reason,financial_action,created_by) values('${ret}','customer','to_process','${customer}','${order}','${invoice}','defective','credit','${u}');
 insert into return_credits(return_id,invoice_id,amount,issued_on,created_by) values('${ret}','${invoice}',100,current_date,'${u}');set role authenticated;`);
 const key='o:'+order,s=await rpc('gama_processes','state',{key});assert.equal(s.checks.delivery_remainder,0);assert.equal(s.checks.unpaid_amount,0);assert.equal(s.checks.open_returns,1);assert.equal(s.operational_complete,false);assert.equal(s.steps[7].state,'blocked');assert.equal(s.external_complete,false);
 await rpc('gama_dossier_followup','save',{key,owner_id:u,next_action:'Review return',due_date:'2099-01-01'});await assert.rejects(rpc('gama_dossier_followup','close',{key,note:'Should not close'}),/DOSSIER_INCOMPLETE/);
 await db.exec(`reset role;update return_orders set status='closed',closed_at=now() where id='${ret}';set role authenticated;`);
 const done=await rpc('gama_processes','state',{key});assert.equal(done.operational_complete,true);const closed=await rpc('gama_dossier_followup','close',{key,note:'Service and credit verified'});assert.equal(closed.closed,true);
 const list=await rpc('gama_processes','list',{kind:'PDV'});assert.deepEqual(list.items.find(x=>x.key===key).state,await rpc('gama_processes','state',{key}));
 const po=(await db.query('select gama_purchase_save($1) r',[{request_key:uuid(),supplier_id:supplier,lines:[{product_id:product,quantity:1,unit_cost:40,tax_rate:0}]}])).rows[0].r;
 const ps=await rpc('gama_dossier_followup','save',{key:'p:'+po.id,owner_id:u,next_action:'Request service acceptance',due_date:'2099-01-01'});assert.equal(ps.followup.owner_id,u);assert.equal(ps.operational_complete,false);
 const page=await rpc('gama_processes','list',{kind:'PDC',search:'Audit supplier'});assert.equal(page.total,1);assert.equal(page.items[0].state.key,'p:'+po.id);
 await db.exec('reset role');await db.query("update purchase_orders set status='received' where id=$1",[po.id]);await db.query('update purchase_order_lines set received_quantity=1 where purchase_order_id=$1',[po.id]);
 const purchaseLine=(await db.query('select id from purchase_order_lines where purchase_order_id=$1',[po.id])).rows[0].id;
 const bill=(await db.query("insert into supplier_invoices(supplier_id,number,issue_date,subtotal,tax,total,status,purchase_order_id) values($1,'AUDIT-SERVICE-BILL',current_date,40,0,40,'posted',$2) returning id",[supplier,po.id])).rows[0].id;
 await db.exec('set role authenticated');const unmatched=await rpc('gama_processes','state',{key:'p:'+po.id});assert.equal(unmatched.unbilled_received,1);assert.equal(unmatched.steps[3].state,'skip');assert.equal(unmatched.operational_complete,false);
 await rpc('gama_supplier_match','approve',{id:bill,lines:[{purchase_line_id:purchaseLine,quantity:1,unit_cost:40,tax_rate:0}]});
 await db.exec('reset role');const supplierReturn=uuid();await db.query("insert into return_orders(id,kind,status,supplier_id,purchase_order_id,supplier_invoice_id,reason,financial_action,created_by) values($1,'supplier','closed',$2,$3,$4,'defective','credit',$5)",[supplierReturn,supplier,po.id,bill,u]);await db.query('insert into return_credits(return_id,supplier_invoice_id,amount,issued_on,created_by) values($1,$2,40,current_date,$3)',[supplierReturn,bill,u]);await db.exec('set role authenticated');
 const purchaseDone=await rpc('gama_processes','state',{key:'p:'+po.id});assert.equal(purchaseDone.unbilled_received,0);assert.equal(purchaseDone.checks.unpaid_amount,0);assert.equal(purchaseDone.operational_complete,true);
 assert.equal((await rpc('gama_dossier_followup','close',{key:'p:'+po.id,note:'Accepted service and supplier credit verified'})).closed,true);
 await db.exec('reset role;set role anon');await assert.rejects(rpc('gama_processes','list',{}),/permission denied/);
 }finally{await db.close()}
});
