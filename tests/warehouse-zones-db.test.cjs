const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs');

// Otras ubicaciones a medida: tres zonas con papel por almacén (llegada,
// salida, cuarentena) y, al vaciar lo que había, las existencias pasan a la
// llegada con su movimiento; las estanterías no se tocan.
test('las otras ubicaciones se vacían hacia la zona de llegada y se gestionan a mano',async()=>{
 const db=await restore();const admin=randomUUID(),seller=randomUUID(),wh=randomUUID(),product=randomUUID();
 const as=id=>db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[id]);
 const act=async(a,d,who=admin)=>{await as(who);return (await db.query('select public.gama_location_action($1,$2) r',[a,d])).rows[0].r};
 const one=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
 const loc=code=>one(`select * from warehouse_locations where warehouse_id=$1 and code=$2`,[wh,code]);
 const qty=async code=>Number((await one(`select coalesce(sum(q.quantity),0) n from stock_quants q join warehouse_locations l on l.id=q.location_id where l.warehouse_id=$1 and l.code=$2`,[wh,code])).n);
 try{
  // La migración ya dejó las tres zonas en el almacén principal; la llegada es la ubicación por defecto.
  const principal=(await db.query(`select l.role,l.code from warehouse_locations l join warehouses w on w.id=l.warehouse_id where w.code='PRINCIPAL' and l.role is not null order by l.role`)).rows;
  assert.deepEqual(principal,[{role:'arrival',code:'LLEGADA'},{role:'departure',code:'SALIDA'},{role:'quarantine',code:'CUARENTENA'}]);
  assert.equal((await one(`select l.role from warehouse_locations l where l.id=private.gama_default_location()`)).role,'arrival');

  await db.exec(`insert into auth.users(id,email) values('${admin}','zones-admin@example.invalid'),('${seller}','zones-sales@example.invalid');
   update profiles set active=true,role='administrador' where id='${admin}';update profiles set active=true,role='comercial' where id='${seller}';
   insert into warehouses(id,code,name) values('${wh}','ZONE-QA','Almacén de prueba');
   insert into warehouse_locations(warehouse_id,code,name,type) values('${wh}','STOCK','Existencias','warehouse');
   insert into products(id,name,barcode,stock) values('${product}','Tornillo','ZONE-01',0);`);
  const root=(await loc('STOCK')).id;
  await db.query(`insert into warehouse_locations(warehouse_id,parent_id,code,name,type) values($1,$2,'A10','A10','bin'),($1,$2,'Z01','Zona 1','zone'),($1,null,'PR-00000001','Preparación PR-00000001','zone'),($1,null,'RET-QUARANTINE','Devoluciones — cuarentena','zone')`,[wh,root]);
  await db.query(`insert into warehouse_locations(warehouse_id,parent_id,code,name,type) values($1,(select id from warehouse_locations where warehouse_id=$1 and code='Z01'),'Z01-A01','Z01-A01','bin')`,[wh]);
  const shelf=await (async()=>{await as(admin);return (await db.query(`select public.gama_shelf_action('save',$1) r`,[{warehouse_id:wh,code:'AB',column_count:1,row_count:1}])).rows[0].r})();
  await db.exec('reset role');
  for(const [code,n] of [['STOCK',3],['A10',5],['Z01-A01',4],['AB01-01',2]])
   await db.query(`insert into stock_quants(product_id,location_id,quantity,reserved_quantity) values($1,(select id from warehouse_locations where warehouse_id=$2 and code=$3),$4,0)`,[product,wh,code,n]);
  // A10 tiene historial: se archivará en vez de borrarse.
  await db.query(`insert into stock_movements(product_id,type,quantity,user_id,destination_location_id) values($1,'in',5,$2,(select id from warehouse_locations where warehouse_id=$3 and code='A10'))`,[product,admin,wh]);
  const before=Number((await one(`select sum(quantity) n from stock_quants where product_id=$1`,[product])).n);

  // Como en la migración: sin sesión de usuario.
  await db.query(`select set_config('request.jwt.claim.sub','',false)`);
  const r=(await db.query(`select private.gama_locations_reset($1) r`,[wh])).rows[0].r;
  assert.equal(r.moved,3,'raíz, A10 y Z01-A01');
  assert.equal(await qty('LLEGADA'),12);assert.equal(await qty('AB01-01'),2,'la estantería no se toca');
  assert.equal(Number((await one(`select sum(quantity) n from stock_quants where product_id=$1`,[product])).n),before,'el total no cambia');
  assert.equal(Number((await one(`select count(*) n from stock_movements where product_id=$1 and movement_type='internal_transfer' and destination_location_id=$2`,[product,r.arrival])).n),3);
  const left=(await db.query(`select code,role,active,type from warehouse_locations where warehouse_id=$1 and shelf_id is null order by code`,[wh])).rows;
  assert.deepEqual(left,[
   {code:'A10',role:null,active:false,type:'bin'},
   {code:'CUARENTENA',role:'quarantine',active:true,type:'zone'},
   {code:'LLEGADA',role:'arrival',active:true,type:'zone'},
   {code:'SALIDA',role:'departure',active:true,type:'zone'},
   {code:'STOCK',role:null,active:true,type:'warehouse'},
   // Z01-A01 queda nombrada por el movimiento que la vació; Z01, por ser su padre.
   {code:'Z01',role:null,active:false,type:'zone'},
   {code:'Z01-A01',role:null,active:false,type:'bin'}]);
  assert.equal(await loc('PR-00000001'),undefined,'la zona de preparación sin historial se borra');
  assert.equal((await loc('CUARENTENA')).name,'Cuarentena','la antigua RET-QUARANTINE pasa a ser la cuarentena');
  assert.equal((await loc('AB01-01')).parent_id,root);

  // Los procesos usan las zonas por su papel.
  for(const [fn,text] of [['gama_fulfillment_action',"gama_zone(loc.warehouse_id,'departure')"],['gama_returns_processing',"gama_zone(loc.warehouse_id,'quarantine')"]])
   assert.ok((await one(`select pg_get_functiondef(p.oid) d from pg_proc p where p.proname=$1 and p.pronamespace='private'::regnamespace`,[fn])).d.includes(text),fn);

  // A mano: crear, renombrar, quitar.
  const m=await act('save',{warehouse_id:wh,code:' muelle-1 ',name:'Muelle 1'});
  assert.equal(m.code,'MUELLE-1');assert.equal((await loc('MUELLE-1')).parent_id,root);
  await assert.rejects(act('save',{warehouse_id:wh,code:'AB02-01',name:'x'}),/LOCATION_CODE_RESERVED/);
  await assert.rejects(act('save',{warehouse_id:wh,code:'LLEGADA',name:'x'}),/LOCATION_CODE_TAKEN/);
  await assert.rejects(act('save',{warehouse_id:wh,code:'a b',name:'x'}),/LOCATION_CODE_INVALID/);
  await assert.rejects(act('save',{warehouse_id:wh,code:'OTRA',name:'x'},seller),/ROLE_NOT_ALLOWED/);
  const arrival=await loc('LLEGADA');
  assert.equal((await act('save',{id:arrival.id,name:'Muelle de recepción'})).role,'arrival');
  await assert.rejects(act('save',{id:arrival.id,code:'OTRO',name:'x'}),/LOCATION_CODE_IMMUTABLE/);
  await assert.rejects(act('delete',{id:arrival.id}),/LOCATION_ROLE_REQUIRED/);
  await db.exec('reset role');
  await db.query(`insert into stock_quants(product_id,location_id,quantity,reserved_quantity) values($1,$2,1,0)`,[product,m.id]);
  await assert.rejects(act('delete',{id:m.id}),/LOCATION_NOT_EMPTY/);
  await db.exec('reset role');await db.query(`update stock_quants set quantity=0 where location_id=$1`,[m.id]);
  assert.equal((await act('delete',{id:m.id})).deleted,1);
  assert.equal(await loc('MUELLE-1'),undefined);
  // Un código archivado vuelve con su historial.
  const back=await act('save',{warehouse_id:wh,code:'A10',name:'Pasillo A10'});
  assert.equal(back.restored,true);assert.equal((await loc('A10')).active,true);
  assert.ok(shelf.id);
 }finally{await db.close()}
});
