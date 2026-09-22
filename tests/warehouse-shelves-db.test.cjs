const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs');

// Estanterías simuladas: dos letras, columnas y filas; cada celda es una
// ubicación AAXX-XX de verdad. Sólo se quita lo vacío.
test('una estantería genera sus espacios AAXX-XX y sólo se reduce o se borra vacía',async()=>{
 const db=await restore();const admin=randomUUID(),seller=randomUUID(),wh=randomUUID(),product=randomUUID();
 const as=id=>db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[id]);
 const act=async(a,d,who=admin)=>{await as(who);return (await db.query('select public.gama_shelf_action($1,$2) r',[a,d])).rows[0].r};
 const spaces=async id=>(await db.query(`select code,active from warehouse_locations where shelf_id=$1 order by code`,[id])).rows;
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','shelf-admin@example.invalid'),('${seller}','shelf-sales@example.invalid');
   update profiles set active=true,role='administrador' where id='${admin}';update profiles set active=true,role='comercial' where id='${seller}';
   insert into warehouses(id,code,name) values('${wh}','SHELF-QA','Almacén de prueba');
   insert into warehouse_locations(warehouse_id,code,name,type) values('${wh}','STOCK','Existencias','warehouse');
   insert into products(id,name,barcode,stock) values('${product}','Tornillo','SHELF-01',0);`);
  const s=await act('save',{warehouse_id:wh,code:'ab',name:'Pasillo norte',column_count:3,row_count:2});
  assert.equal(s.code,'AB');assert.equal(s.spaces,6);assert.equal(s.created,6);
  assert.deepEqual((await spaces(s.id)).map(x=>x.code),['AB01-01','AB01-02','AB02-01','AB02-02','AB03-01','AB03-02']);
  const root=(await db.query(`select id from warehouse_locations where warehouse_id=$1 and code='STOCK'`,[wh])).rows[0].id;
  assert.equal((await db.query(`select count(*)::int n from warehouse_locations where shelf_id=$1 and parent_id=$2 and type='bin'`,[s.id,root])).rows[0].n,6,'bajo la raíz del almacén');

  await assert.rejects(act('save',{warehouse_id:wh,code:'A1',column_count:1,row_count:1}),/SHELF_CODE_INVALID/);
  await assert.rejects(act('save',{warehouse_id:wh,code:'AB',column_count:1,row_count:1}),/SHELF_CODE_TAKEN/);
  await assert.rejects(act('save',{warehouse_id:wh,code:'CD',column_count:100,row_count:1}),/SHELF_SIZE_INVALID/);
  await assert.rejects(act('save',{warehouse_id:wh,code:'CD',column_count:1,row_count:1},seller),/ROLE_NOT_ALLOWED/);

  // Con existencias en AB03-02, no se puede reducir a 2 columnas.
  const busy=(await db.query(`select id from warehouse_locations where code='AB03-02' and warehouse_id=$1`,[wh])).rows[0].id;
  await db.exec(`reset role`);await db.query(`insert into stock_quants(product_id,location_id,quantity,reserved_quantity) values($1,$2,5,0)`,[product,busy]);
  await assert.rejects(act('save',{id:s.id,version:s.version,column_count:2,row_count:2}),/SHELF_SPACE_IN_USE:AB03-02/);
  await assert.rejects(act('delete',{id:s.id}),/SHELF_NOT_EMPTY:AB03-02/);
  await assert.rejects(act('save',{id:s.id,version:s.version+5,column_count:3,row_count:3}),/SHELF_STALE/);

  // Vacía, se reduce: AB03-* desaparecen; el historial archiva en vez de borrar.
  await db.query(`update stock_quants set quantity=0 where location_id=$1`,[busy]);
  await db.query(`insert into stock_movements(product_id,type,quantity,user_id,destination_location_id) values($1,'in',5,$2,$3)`,[product,admin,busy]);
  const smaller=await act('save',{id:s.id,version:s.version,column_count:2,row_count:2,name:'Pasillo norte'});
  assert.equal(smaller.version,s.version+1);assert.deepEqual(smaller.removed,{deleted:1,archived:1});
  assert.deepEqual((await spaces(s.id)).map(x=>x.code),['AB01-01','AB01-02','AB02-01','AB02-02']);
  assert.equal((await db.query(`select active from warehouse_locations where id=$1`,[busy])).rows[0].active,false,'AB03-02 queda archivada por su historial');

  // Borrar la estantería: se van sus espacios; volver a crearla reactiva los archivados.
  const gone=await act('delete',{id:s.id});assert.deepEqual(gone.removed,{deleted:4,archived:0});
  assert.equal((await db.query(`select count(*)::int n from warehouse_shelves`)).rows[0].n,0);
  const again=await act('save',{warehouse_id:wh,code:'AB',column_count:3,row_count:2});
  assert.equal(again.created,5,'AB03-02 se reutiliza');
  assert.equal((await db.query(`select active,shelf_id from warehouse_locations where id=$1`,[busy])).rows[0].shelf_id,again.id);

  // Un código ya usado por otra ubicación activa no se pisa.
  await db.query(`insert into warehouse_locations(warehouse_id,code,name,type) values($1,'CD01-01','Manual','bin')`,[wh]);
  await assert.rejects(act('save',{warehouse_id:wh,code:'CD',column_count:1,row_count:1}),/SHELF_SPACE_TAKEN:CD01-01/);
 }finally{await db.close()}
});
