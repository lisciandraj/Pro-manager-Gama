const {test}=require('node:test'),assert=require('node:assert/strict');
const {restore}=require('../scripts/restore-schema.cjs');
const id=n=>'83000000-0000-0000-0000-'+String(n).padStart(12,'0');
test('TMS customer costs preserve route cents, unknown costs and legacy stops with guarded server pagination',async t=>{
 const db=await restore(),admin=id(1),seller=id(2),a=id(4),b=id(5),c=id(6);
 const as=uid=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated`);
 const report=async(data={},from='2026-10-01',to='2026-10-31')=>(await db.query('select gama_tms_customer_costs($1::date,$2::date,$3) r',[from,to,data])).rows[0].r;
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','tms-cost-admin@example.invalid'),('${seller}','tms-cost-sales@example.invalid');
   update profiles set active=true,role=case id when '${admin}' then 'administrador' else 'comercial' end;
   select set_config('request.jwt.claim.sub','${admin}',false);
   insert into customers(id,name) values('${a}','Alfa'),('${b}','Beta'),('${c}','Coste desconocido');
   begin;set session_replication_role=replica;
   insert into tms_deliveries(id,customer_id,customer,address,delivery_date) values
    ('${id(10)}','${a}','Alfa','Quito','2026-10-05'),('${id(11)}','${b}','Beta','Quito','2026-10-05'),('${id(12)}','${a}','Alfa agencia','Quito','2026-10-05'),
    ('${id(13)}','${a}','Alfa','Quito','2026-10-06'),('${id(14)}','${c}','Coste desconocido','Quito','2026-10-06');
   insert into tms_routes(id,route_date,stops,distance,cost_per_km) values
    ('${id(20)}','2026-10-05','["__depot","${id(10)}","${id(11)}","${id(12)}","${id(10)}","__depot"]',100,1),
    ('${id(21)}','2026-10-06','["${id(13)}","${id(14)}"]',4,null),
    ('${id(22)}','2026-10-05','["__depot"]',5,1),
    ('${id(23)}','2026-09-30','["${id(10)}"]',900,1),
    ('${id(24)}','2026-10-05','["legacy-non-uuid"]',3,1);
   insert into tms_route_schedules(route_id,starts_at,legs,road_source,road_km,duration_minutes,updated_by)
    values('${id(20)}','2026-10-05T08:00:00Z','[]','Verified fixture',10,30,'${admin}');
   set session_replication_role=origin;commit;`);
  await as(admin);
  await t.test('verified distance and deterministic cents reconcile while missing rates remain unknown',async()=>{
   const r=await report(),alfa=r.items.find(x=>x.customer_id===a),beta=r.items.find(x=>x.customer_id===b),unknown=r.items.find(x=>x.customer_id===null),missing=r.items.find(x=>x.customer_id===c);
   assert.equal(r.total,4);assert.equal(r.unassigned_routes,1);assert.equal(r.unassigned_cost,5);assert.equal(r.unassigned_missing_cost,0);
   assert.equal(alfa.cost,6.67);assert.equal(beta.cost,3.33);assert.equal(alfa.cost+beta.cost,10,'allocated cents equal the rounded verified route total');
   assert.equal(alfa.deliveries,3);assert.equal(alfa.routes,2);assert.equal(alfa.missing_cost,1);assert.equal(alfa.estimated_stops,1);assert.ok(Math.abs(alfa.km-(20/3+2))<0.00001);
   assert.equal(beta.estimated_stops,0);assert.equal(missing.cost,null);assert.equal(missing.missing_cost,1);
   assert.equal(unknown.cost,3);assert.equal(unknown.unknown_stops,1);assert.equal(unknown.customer,'Cliente no identificado');
  });
  await t.test('search precedes pagination and uses literal characters',async()=>{
   const first=await report({limit:1}),second=await report({limit:1,offset:1});assert.equal(first.items.length,1);assert.equal(first.items[0].customer,'Alfa');assert.equal(second.items[0].customer,'Beta');assert.equal(second.total,4);
   const r=await report({search:'BETA',limit:1});assert.equal(r.total,1);assert.equal(r.items[0].customer_id,b);assert.equal(r.unassigned_routes,1);
   assert.equal((await report({search:'%'})).total,0);assert.equal((await report({offset:20})).items.length,0);
  });
  await t.test('invalid requests and unauthorized users cannot inspect costs',async()=>{
   await assert.rejects(report({},'2026-10-31','2026-10-01'),/INVALID_PERIOD/);
   await assert.rejects(report({},'2025-01-01','2026-10-01'),/INVALID_PERIOD/);
   for(const data of [null,[],{search:'x'.repeat(101)},{offset:-1},{limit:'oops'}])await assert.rejects(report(data),/INVALID_REQUEST/);
   await as(seller);await assert.rejects(report(),/TMS_ACCESS_DENIED/);await assert.rejects(db.query('select private.gama_tms_customer_costs($1,$2,$3)',['2026-10-01','2026-10-31',{}]),/TMS_ACCESS_DENIED/);
   await db.exec('reset role;set role anon');await assert.rejects(report(),/permission denied/);await as(admin);
  });
  await t.test('the report remains read-only and empty periods do not invent costs',async()=>{
   await db.exec('reset role');assert.equal((await db.query('select count(*)::int n from tms_routes')).rows[0].n,5);assert.equal((await db.query('select cost_per_km from tms_routes where id=$1',[id(21)])).rows[0].cost_per_km,null);
   await as(admin);const empty=await report({},'2026-11-01','2026-11-30');assert.equal(empty.total,0);assert.deepEqual(empty.items,[]);assert.equal(empty.unassigned_routes,0);assert.equal(empty.unassigned_cost,null);
  });
 }finally{await db.close()}
});
