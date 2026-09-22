const {test}=require('node:test'),assert=require('node:assert/strict');
const {restore}=require('../scripts/restore-schema.cjs');
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');

// «Prioridades de hoy» sustituye al módulo Control comercial y logístico. La
// promesa es corta: rojo lo que ya se pasó —fecha o límite—, naranja lo que
// vence en la semana o está a punto, y ni lo pospuesto ni lo que el perfil no
// puede ver. El tono se decide en la base, con las fechas reales, así que es
// aquí donde se comprueba.
test('las prioridades de hoy separan lo vencido de lo que vence esta semana',async()=>{
 const db=await restore(),admin=id(9801),warehouse=id(9802),client=id(9803),customer=id(9810),order=id(9811),supplier=id(9812);
 const as=async uid=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated`);
 const read=async()=>(await db.query('select gama_dashboard_priorities() p')).rows[0].p;
 const tz="(now() at time zone private.erp_timezone())::date";
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','prio-admin@example.invalid'),('${warehouse}','prio-wh@example.invalid'),('${client}','prio-client@example.invalid');
   update profiles set active=true,role=case id when '${admin}' then 'administrador' when '${warehouse}' then 'almacenero' else 'cliente' end where id in ('${admin}','${warehouse}','${client}');
   insert into customers(id,name,identification) values('${customer}','Cliente prioridades','PRIO-QA');
   insert into suppliers(id,name) values('${supplier}','Proveedor prioridades');
   select set_config('request.jwt.claim.sub','${admin}',false);
   insert into sales_orders(id,number,customer_id,customer_name,created_by,request_key,status) values('${order}','PRIO-001','${customer}','Cliente prioridades','${admin}',gen_random_uuid(),'confirmed');
   set session_replication_role=replica;
   insert into external_invoices(id,request_key,order_id,number,issue_date,due_date,subtotal,tax,fiscal_status,issuer_ruc,document_kind,payment_terms_days,payment_delivery_date,created_by) values
    ('${id(9820)}',gen_random_uuid(),'${order}','PRIO-VENCIDA',${tz}-40,${tz}-10,100,15,'authorized','1234567890001','external',30,${tz}-40,'${admin}'),
    ('${id(9821)}',gen_random_uuid(),'${order}','PRIO-SEMANA',${tz}-25,${tz}+3,100,15,'authorized','1234567890001','external',30,${tz}-27,'${admin}'),
    ('${id(9822)}',gen_random_uuid(),'${order}','PRIO-LEJOS',${tz},${tz}+40,100,15,'authorized','1234567890001','external',40,${tz},'${admin}');
   insert into supplier_invoices(id,number,supplier_id,issue_date,due_date,subtotal,tax,total,status) values
    ('${id(9830)}','PROV-VENCIDA','${supplier}',${tz}-60,${tz}-2,100,0,100,'posted'),
    ('${id(9831)}','PROV-SEMANA','${supplier}',${tz}-20,${tz}+5,100,0,100,'posted'),
    ('${id(9832)}','PROV-LEJOS','${supplier}',${tz},${tz}+30,100,0,100,'posted');
   insert into tms_deliveries(id,customer,address,delivery_date,status) values('${id(9840)}','Cliente prioridades','Quito',${tz}-1,'Planificada');
   set session_replication_role=origin;`);

  await as(admin);let p=await read();
  const by=ref=>p.items.find(x=>x.reference===ref);
  // Vencido: rojo. Vence esta semana: naranja. Dentro de un mes: nada todavía.
  assert.equal(by('PRIO-VENCIDA')?.tone,'danger',JSON.stringify(p.items.map(x=>[x.reference,x.kind,x.tone])));
  assert.equal(by('PRIO-SEMANA')?.tone,'warning');
  assert.equal(by('PRIO-LEJOS'),undefined,'una factura que vence en 40 días no es prioridad de hoy');
  assert.equal(by('PROV-VENCIDA')?.tone,'danger');
  assert.equal(by('PROV-SEMANA')?.tone,'warning','el pago a proveedor que vence esta semana entra en naranja');
  assert.equal(by('PROV-SEMANA')?.kind,'payable_due_soon');
  assert.equal(by('PROV-LEJOS'),undefined);
  const late=p.items.find(x=>x.kind==='late_delivery');
  assert.equal(late?.tone,'danger','una entrega con la fecha pasada es roja');
  // La fecha que decide el color viaja con la alerta.
  assert.ok(by('PRIO-SEMANA').due_on,'la alerta naranja lleva su vencimiento');
  // Rojo primero, siempre: nadie tiene que buscar lo urgente al final.
  const tones=p.items.map(x=>x.tone);
  assert.deepEqual(tones,[...tones].sort((a,b)=>(a==='danger'?0:1)-(b==='danger'?0:1)));
  assert.equal(p.counts.danger,p.items.filter(x=>x.tone==='danger').length);
  assert.equal(p.counts.warning,p.items.filter(x=>x.tone==='warning').length);

  // Las tareas de oficina llegan en bloque: un grupo con su número, no una línea por movimiento.
  await db.exec(`reset role;set session_replication_role=replica;
   insert into financial_accounts(id,name,kind,currency) values('${id(9850)}','Banco QA','bank','USD');
   insert into bank_transactions(financial_account_id,value_date,amount,description,status) select '${id(9850)}',${tz},10+n,'Movimiento '||n,'unmatched' from generate_series(1,3) n;
   set session_replication_role=origin;`);
  await as(admin);p=await read();
  assert.equal(p.items.filter(x=>x.kind==='bank_unmatched').length,0,'los movimientos bancarios no se listan uno a uno');
  const bank=p.groups.find(g=>g.kind==='bank_unmatched');
  assert.equal(bank?.count,3);assert.equal(bank?.tone,'warning');
  assert.equal(p.counts.warning,p.items.filter(x=>x.tone==='warning').length+3,'el contador de la columna sigue contando todo');

  // Pospuesta: sale de las prioridades de hoy hasta que vence el aplazamiento.
  await db.exec(`reset role;insert into private.gama_alert_handling(alert_key,fingerprint,status,snoozed_until,updated_by) values('overdue_invoice:${id(9820)}','x','snoozed',now()+interval '2 days','${admin}')`);
  await as(admin);p=await read();
  assert.equal(p.items.find(x=>x.reference==='PRIO-VENCIDA'),undefined,'lo pospuesto no aparece hoy');

  // El almacenero no ve lo financiero; sí las entregas.
  await as(warehouse);p=await read();
  assert.ok(p.items.every(x=>!['overdue_invoice','due_soon_invoice','payable_overdue','payable_due_soon'].includes(x.kind)),'el almacén no ve facturas');
  assert.ok(p.items.some(x=>x.kind==='late_delivery'));

  // Un cliente no entra, y sin sesión tampoco.
  await as(client);await assert.rejects(read(),/ROLE_NOT_ALLOWED/);
  await db.exec('reset role;set role anon');await assert.rejects(read(),/permission denied/);
 }finally{await db.close()}
});
