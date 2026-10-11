const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
const migration='20261011155754_performance_paged_stock_and_dashboard.sql';
test('paged reads preserve global totals, snapshots, management calculations and access boundaries',async()=>{
 const db=await restore({before:migration}),admin=uuid(),warehouse=uuid(),client=uuid(),inactive=uuid(),supplier=uuid();
 const as=async id=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);select set_config('request.jwt.claims','{}',false);set role authenticated`);
 const rpc=async(name,args=[])=>(await db.query(`select ${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) d`,args)).rows[0].d;
 const stable=d=>{const result=structuredClone(d);delete result.generated_at;delete result.as_of;return result};
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','perf-admin@example.invalid'),('${warehouse}','perf-warehouse@example.invalid'),('${client}','perf-client@example.invalid'),('${inactive}','perf-inactive@example.invalid');update profiles set active=id<>'${inactive}',role=case when id='${warehouse}' then 'almacenero' when id='${client}' then 'cliente' else 'administrador' end;insert into suppliers(id,name) values('${supplier}','Perf supplier');`);
  const loc=(await db.query('select id,warehouse_id from warehouse_locations where active order by code limit 1')).rows[0];
  const ids=[];for(let i=0;i<65;i++){const id=uuid();ids.push(id);await db.query('insert into products(id,name,reference,barcode,category,min_stock,max_stock,purchase_price,supplier_id) values($1,$2,$3,$3,$4,5,50,2,$5)',[id,'Paged '+String(i).padStart(3,'0'),'PERF-'+i,i%2?'Odd':'Even',supplier]);await db.query('insert into stock_quants(product_id,location_id,quantity,reserved_quantity) values($1,$2,$3,$4)',[id,loc.id,i,i%4]);}
  await db.query('insert into products(name,barcode,product_kind) values($1,$2,$3)',['Service','PERF-SERVICE','service']);
  await db.query('insert into reorder_rules(product_id,min_quantity,max_quantity,lead_time_days,supplier_id) values($1,8,40,10,$2)',[ids[3],supplier]);
  await as(admin);const fullBefore=await rpc('gama_company_dashboard',['2020-02-01','2020-02-29']);
  const managementBefore=await rpc('gama_management_overview'),insightsBefore=await rpc('gama_stock_insights',['reabastecimiento']);
  const stockBefore=await rpc('gama_inventory_snapshot',[null,null]);
  await db.exec('reset role');const quantBefore=(await db.query('select * from stock_quants order by product_id')).rows;
  await db.exec(fs.readFileSync('supabase/migrations/'+migration,'utf8'));await as(admin);
  assert.deepEqual(stable(await rpc('gama_company_dashboard',['2020-02-01','2020-02-29'])),stable(fullBefore));
  assert.deepEqual(stable(await rpc('gama_management_overview')),stable(managementBefore));
  assert.deepEqual(stable(await rpc('gama_stock_insights',['reabastecimiento'])),stable(insightsBefore));
  const page=await rpc('gama_inventory_page');assert.equal(page.total,65);assert.equal(page.rows.length,20);assert.equal(page.page,0);
  assert.equal(page.totals.current_cost_value,stockBefore.rows.reduce((n,r)=>n+r.current_cost_value,0));
  assert.equal(page.totals.out,1);assert.equal(page.totals.low,7);assert.deepEqual(page.categories,['Even','Odd']);
  const collected=[];for(let p=0;p<4;p++){const data=await rpc('gama_inventory_page',[null,null,'','','','','name','asc',p,20]);collected.push(...data.rows);assert.deepEqual(data.totals,page.totals)}
  assert.equal(new Set(collected.map(r=>r.id)).size,65);assert.deepEqual(collected.map(r=>r.name),[...collected.map(r=>r.name)].sort());
  for(const r of collected){const old=stockBefore.rows.find(x=>x.id===r.id);for(const k of ['physical','reserved','available','incoming','projected','current_cost_value'])assert.equal(r[k],old[k],k);assert.ok(!Object.hasOwn(r,'photo_data'));assert.equal(r.lines.length,1)}
  let data=await rpc('gama_inventory_page',[null,null,'PERF-64']);assert.equal(data.total,1);assert.equal(data.rows[0].id,ids[64]);assert.equal(data.totals.current_cost_value,128);
  data=await rpc('gama_inventory_page',[null,null,'','Odd','','','physical','desc',0,20]);assert.equal(data.total,32);assert.equal(data.rows[0].physical,63);
  data=await rpc('gama_inventory_page',[null,null,'','','agotado']);assert.equal(data.total,1);
  data=await rpc('gama_inventory_page',[null,null,'','','','Paged 064']);assert.equal(data.total,1);
  data=await rpc('gama_inventory_page',[null,null,'','','','','name','asc',999,20]);assert.equal(data.page,3);assert.equal(data.rows.length,5);
  await assert.rejects(rpc('gama_inventory_page',[null,null,'','','','','secret']),/INVALID_FILTER/);
  const sections=await rpc('gama_company_dashboard_sections',['2020-02-01','2020-02-29',['payments','warehouses']]);assert.deepEqual(Object.keys(sections.sections).sort(),['payments','warehouses']);assert.deepEqual(sections.sections.warehouses,fullBefore.sections.warehouses);
  const context=await rpc('gama_accounting_action',['context',{}]);assert.equal(context.currency,'USD');assert.equal(context.scope,'all');assert.ok(context.rights.view);assert.ok(!Object.hasOwn(context,'treasury'));
  await as(warehouse);data=await rpc('gama_inventory_page');assert.equal(data.total,65);assert.equal(data.incoming_visible,false);for(const r of data.rows){assert.equal(r.incoming,null);assert.equal(r.projected,null)}
  const warehouseDash=await rpc('gama_company_dashboard_sections',['2020-02-01','2020-02-29',['payments','warehouses','accounting']]);assert.deepEqual(Object.keys(warehouseDash.sections),['warehouses']);
  for(const id of [client,inactive]){await as(id);await assert.rejects(rpc('gama_inventory_page'),/ROLE_NOT_ALLOWED/);await assert.rejects(rpc('gama_company_dashboard_sections',[null,null,['payments']]),/DASHBOARD_ACCESS_DENIED/);await assert.rejects(rpc('gama_accounting_action',['context',{}]),/ROLE_NOT_ALLOWED/)}
  await db.exec('reset role');assert.deepEqual((await db.query('select * from stock_quants order by product_id')).rows,quantBefore);
  await db.exec('set role anon');await assert.rejects(rpc('gama_inventory_page'),/permission denied/);
  await db.exec(`reset role;insert into auth.mfa_factors(user_id,status) values('${admin}','verified')`);await as(admin);await assert.rejects(rpc('gama_inventory_page'),/ROLE_NOT_ALLOWED/);await assert.rejects(rpc('gama_accounting_action',['context',{}]),/AUTH_OR_MFA_REQUIRED/);
 }finally{await db.close()}
});
