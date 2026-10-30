const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('native alerts and retained history preserve current driver and source audiences',async()=>{
 const db=await restore(),admin=uuid(),formerAdmin=uuid(),driverA=uuid(),driverB=uuid(),employeeA=uuid(),employeeB=uuid(),fleetA=uuid(),fleetB=uuid(),deliveryA=uuid(),deliveryB=uuid();
 const q=async(sql,args=[])=>(await db.query(sql,args)).rows,one=async(sql,args=[])=>Object.values((await q(sql,args))[0])[0];
 const as=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 const owner=async()=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[admin])};
 const ops=(action,data={})=>one('select public.gama_operations_action($1,$2::jsonb)',[action,JSON.stringify(data)]);
 try{
  for(const [id,role]of [[admin,'administrador'],[formerAdmin,'administrador'],[driverA,'almacenero'],[driverB,'almacenero']]){
   await q('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id,id+'@example.invalid']);await q('update profiles set role=$2,active=true where id=$1',[id,role]);
  }
  await owner();await q("insert into hr_employees(id,full_name,profile_id) values($1,'Driver A',$2),($3,'Driver B',$4)",[employeeA,driverA,employeeB,driverB]);
  await q("insert into fleet_drivers(id,name,employee_id,licence_expiry) values($1,'Driver A',$2,current_date+2),($3,'Driver B',$4,null)",[fleetA,employeeA,fleetB,employeeB]);
  const customer=await one("insert into customers(name) values('Notification fixture customer') returning id");
  const order=await one("insert into sales_orders(customer_id,customer_name,request_key,status,created_by) values($1,'Notification fixture customer',gen_random_uuid(),'confirmed',$2) returning id",[customer,admin]);
  await db.exec('begin');
  await q("insert into tms_deliveries(id,customer,address,driver_id,status,delivery_date) values($1,'Own dummy delivery','Quito',$2,'Excepción',current_date-1),($3,'Foreign dummy delivery','Quito',$4,'Excepción',current_date-1)",[deliveryA,fleetA,deliveryB,fleetB]);
  await q("insert into sales_deliveries(order_id,request_key,tms_delivery_id,created_by,loading_required) select $1,gen_random_uuid(),id,$2,false from tms_deliveries where id=any($3::uuid[])",[order,admin,[deliveryA,deliveryB]]);
  await db.exec('commit');
  await as(admin);const full=await ops('snapshot',{track:true,state:'all'}),foreign=full.alerts.find(a=>a.alert_key==='delivery:'+deliveryB);assert.ok(foreign);assert.equal(full.metrics.late_deliveries,2);
  const fleet=full.alerts.find(a=>a.kind==='fleet_deadline');assert.ok(fleet);
  await as(driverA);assert.equal(await one('select private.tms_can_read($1)',[deliveryB]),false);assert.equal(await one('select count(*)::int from tms_deliveries where id=$1',[deliveryB]),0);
  const own=await ops('snapshot',{track:true,state:'all'});assert.equal(own.alerts.some(a=>a.alert_key===foreign.alert_key),false);assert.equal(own.alerts.some(a=>a.alert_key==='delivery:'+deliveryA),true);assert.equal(own.metrics.late_deliveries,1);
  assert.equal((await ops('badge')).active_count,own.active_count);
  const priorities=await one('select public.gama_dashboard_priorities()');assert.equal(JSON.stringify(priorities).includes(deliveryB),false);
  await assert.rejects(ops('history',{key:foreign.alert_key}),/ALERT_NOT_FOUND/);await assert.rejects(ops('handle',{key:foreign.alert_key,fingerprint:foreign.fingerprint,status:'in_progress',note:'Foreign attempt'}),/ALERT_RESOLVED/);
  await owner();assert.equal(await one('select active from private.erp_alert_state where alert_key=$1',[foreign.alert_key]),true);
  await as(formerAdmin);await ops('snapshot',{track:true});await owner();await q("update profiles set role='comercial' where id=$1",[formerAdmin]);
  await as(admin);await ops('handle',{key:fleet.alert_key,fingerprint:fleet.fingerprint,status:'in_progress',note:'Restricted note after downgrade',next_action:'Administrator-only detail'});
  await as(formerAdmin);await assert.rejects(ops('history',{key:fleet.alert_key}),/ALERT_NOT_FOUND/);await ops('snapshot',{track:true});
  await owner();assert.equal(await one('select active from private.erp_alert_state where alert_key=$1',[fleet.alert_key]),true);assert.equal(await one("select count(*)::int from private.gama_alert_events where alert_key=$1 and action='resolved'",[fleet.alert_key]),0);
  await as(admin);assert.ok((await ops('history',{key:fleet.alert_key})).some(e=>e.note.includes('Restricted note after downgrade')));
 }finally{await db.close()}
});
