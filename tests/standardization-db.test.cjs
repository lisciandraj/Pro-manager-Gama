const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {restore}=require('../scripts/restore-schema.cjs');
const {fixtureMigration}=require('../scripts/fresh-migration.cjs');
const actions=require('./standardization-actions.json');
const migrationFolder=path.join(__dirname,'../supabase/migrations');
const firstChange=fs.readdirSync(migrationFolder).find(f=>f.endsWith('_standardize_domain_dispatch.sql'));
const admin='00000000-0000-0000-0000-000000009001',client='00000000-0000-0000-0000-000000009002',product='00000000-0000-0000-0000-000000009003',customer='00000000-0000-0000-0000-000000009004';
const actAs=async(db,id)=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);set role authenticated;`);
// Fleet SQL ranks consumption by average only. Equal ranks have no secondary
// order; normalize each consecutive tie without reordering distinct ranks.
const fleetRankTies=rows=>{
 const result=rows.slice();
 for(let from=0;from<result.length;){let to=from+1;while(to<result.length&&result[to].avg_litres_100km===result[from].avg_litres_100km)to++;
  result.splice(from,to-from,...result.slice(from,to).sort((a,b)=>a.vehicle_id.localeCompare(b.vehicle_id)));from=to;
 }
 return result;
};
test('fleet parity normalizes equal ranks while preserving rank order and complete records',()=>{
 const a={vehicle_id:'a',avg_litres_100km:10,cost_per_km:2},b={vehicle_id:'b',avg_litres_100km:10,cost_per_km:3},c={vehicle_id:'c',avg_litres_100km:5,cost_per_km:1},d={vehicle_id:'d',avg_litres_100km:null,cost_per_km:null};
 assert.deepEqual(fleetRankTies([b,a,c,d]),[a,b,c,d]);
 assert.notDeepEqual(fleetRankTies([c,b,a,d]),[a,b,c,d],'different ranks must retain the SQL order');
 assert.notDeepEqual(fleetRankTies([{...a,cost_per_km:9},b,c,d]),[a,b,c,d],'changed amounts must remain observable');
 assert.notDeepEqual(fleetRankTies([a,c,d]),[a,b,c,d],'missing vehicles must remain observable');
});
test('reconstructed schema preserves domain dispatch results, errors and permissions',async()=>{
 const db=await restore({before:firstChange});
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','admin@example.invalid'),('${client}','client@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' else 'cliente' end;`);
  const probe=async(domain,action)=>{
   await db.exec('savepoint probe');
   try{const r=await db.query(`select public.gama_${domain}_action($1,$2) as result`,[action,{}]);const result=r.rows[0].result;if(result?.checked_at)result.checked_at=!!Date.parse(result.checked_at);return{ok:true,result};}
   catch(e){return{ok:false,code:e.code,message:e.message};}
   finally{await db.exec('rollback to probe;release probe');}
  };
  const outcomes=[];
  // References deliberately migrate to the new canonical format; business results must match.
  const canonicalize=v=>JSON.parse(JSON.stringify(v).replace(/VH-(\d{6})/g,(_,n)=>'VEH-'+n.padStart(8,'0')));
  for(const uid of [admin,client]){
   await actAs(db,uid);await db.exec('begin');
   for(const [domain,list] of Object.entries(actions))for(const action of [...list,'unknown_action'])outcomes.push({uid,domain,action,before:await probe(domain,action)});
   await db.exec('rollback');
  }
  await db.exec('reset role');
  const folder=path.join(__dirname,'../supabase/migrations');
  for(const file of fs.readdirSync(folder).filter(f=>f>=firstChange&&f.endsWith('.sql')).sort())await db.exec(fixtureMigration(file,fs.readFileSync(path.join(folder,file),'utf8')));
  for(const uid of [admin,client]){
   await actAs(db,uid);await db.exec('begin');
   for(const item of outcomes.filter(x=>x.uid===uid)){
    // P0 refunds now require an idempotency key before validating the amount.
    const expected=uid===admin&&item.domain==='returns'&&item.action==='refund'?{ok:false,code:'P0001',message:'REQUEST_KEY_REQUIRED'}:canonicalize(item.before);
    const actual=await probe(item.domain,item.action);
    if(uid===admin&&item.domain==='accounting'&&['chart','settings'].includes(item.action)&&actual.ok){const field=item.action==='chart'?'rows':'accounts';const advance=actual.result[field].find(a=>a.code==='2090');assert.equal(advance?.type,'liability');actual.result[field]=actual.result[field].filter(a=>a.code!=='2090');}
    // Audit additions extend read metadata while preserving the historical business result.
    if(uid===admin&&item.domain==='accounting'&&actual.ok&&expected.ok){
     if(item.action==='bank_list')Object.assign(expected.result,{batches:[],offset:0,limit:50,total:0});
     if(item.action==='chart')expected.result.rows.forEach(a=>{a.cashflow_class=a.type==='equity'?'financing':'operating';a.account_type=null;});
     if(item.action==='settings')expected.result.currency_locked=false;
     if(item.action==='overview'){
      assert.ok(Date.parse(actual.result.generated_at));const today=new Date(expected.result.today+'T00:00:00Z'),start=new Date(Date.UTC(today.getUTCFullYear(),today.getUTCMonth()-1,1)),last=new Date(Date.UTC(today.getUTCFullYear(),today.getUTCMonth(),0)),end=new Date(Math.min(last.getTime(),start.getTime()+(today.getUTCDate()-1)*86400000));
      Object.assign(expected.result,{basis:'ledger',generated_at:actual.result.generated_at,previous_from:start.toISOString().slice(0,10),previous_to:end.toISOString().slice(0,10),fiscal_from:expected.result.today.slice(0,4)+'-01-01'});expected.result.rights.pay=true;
     }
     if(item.action==='report_balance')Object.assign(expected.result,{stock_basis:'dated_valuation',stock_controls:[],stock_coverage:{before_opening:0,complete:true,configured:0,unconfigured:0}});
     if(item.action==='report_cashflow')Object.assign(expected.result,{basis:'ledger',opening:0,net:0});
    }
    // Returned goods go back to the arrival zone or a chosen location, never to the warehouse root.
    if(item.domain==='returns'&&item.action==='overview'&&actual.ok&&expected.ok){assert.ok(actual.result.locations.every(l=>l.code!=='STOCK'));assert.ok(actual.result.locations.some(l=>l.code==='LLEGADA'));delete actual.result.locations;delete expected.result.locations;
     // The empty overview now reports its exact pagination count.
     assert.equal(expected.result.rows.length,0);expected.result.total=0;}
    if(item.domain==='fleet'&&item.action==='overview'&&actual.ok&&expected.ok){
     actual.result.consumption=fleetRankTies(actual.result.consumption);
     expected.result.consumption=fleetRankTies(expected.result.consumption);
    }
    assert.deepEqual(actual,expected,uid+': '+item.domain+'.'+item.action);
   }
   await db.exec('rollback');
  }
  await db.exec('reset role');
  const schema=(await db.query("select count(*)::int tables,count(*) filter(where relrowsecurity)::int rls from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'")).rows[0];
  assert.ok(schema.tables>=116,'The existing business schema is retained');
  assert.equal(schema.rls,schema.tables,'Every public business table enables RLS');
  const leaves=(await db.query("select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and proname ~ '^gama_(accounting|returns|fleet)_action[0-9]+$'")).rows;
  assert.equal(leaves.length,0);
 }finally{await db.close();}
});
test('legacy quote command is atomic, idempotent, server-calculated and authorized',async()=>{
 const db=await restore();
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','admin@example.invalid'),('${client}','client@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' else 'cliente' end;insert into customers(id,name,identification) values('${customer}','Customer QA','QA-TAX');insert into products(id,name,barcode,sale_price) values('${product}','Product QA','QA-ITEM',12);`);
  const key='00000000-0000-0000-0000-000000009005';
  const payload={request_key:key,customer_id:customer,lines:[{product_id:product,quantity:2,unit_price:12,tax_rate:15}]};
  const save=async p=>(await db.query('select public.gama_legacy_quote_save($1) as result',[p])).rows[0].result;
  await actAs(db,client);await assert.rejects(save(payload),/ROLE_NOT_ALLOWED/);
  await actAs(db,admin);
  await assert.rejects(save({...payload,lines:[...payload.lines,{product_id:product,quantity:-1,unit_price:10,tax_rate:15}]}),/INVALID_QUANTITY/);
  assert.equal((await db.query('select count(*)::int n from invoices')).rows[0].n,0);
  assert.equal((await db.query('select count(*)::int n from invoice_lines')).rows[0].n,0);
  const result=await save(payload);assert.equal(result.subtotal,24);assert.equal(result.tax,3.6);assert.equal(result.total,27.6);assert.ok(result.number);
  assert.deepEqual(await save(payload),result);assert.equal((await db.query('select count(*)::int n from invoices')).rows[0].n,1);
  await assert.rejects(save({...payload,notes:'Different payload'}),/REQUEST_KEY_REUSED/);
  await db.exec('reset role');assert.equal((await db.query('select count(*)::int n from private.command_receipts')).rows[0].n,1);
 }finally{await db.close();}
});
