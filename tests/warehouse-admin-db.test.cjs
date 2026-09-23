const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs');

// Almacenes a medida: se crean con su raíz y sus tres zonas, y se modifican
// sin tocar el código. Lo hacen el administrador y el almacenero.
test('un almacén se crea listo para trabajar y se modifica sin cambiar su código',async()=>{
 const db=await restore();const admin=randomUUID(),keeper=randomUUID(),seller=randomUUID();
 const as=id=>db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[id]);
 const act=async(a,d,who=admin)=>{await as(who);return (await db.query('select public.gama_warehouse_action($1,$2) r',[a,d])).rows[0].r};
 const one=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','wh-admin@example.invalid'),('${keeper}','wh-keeper@example.invalid'),('${seller}','wh-sales@example.invalid');
   update profiles set active=true,role='administrador' where id='${admin}';update profiles set active=true,role='almacenero' where id='${keeper}';update profiles set active=true,role='comercial' where id='${seller}';`);

  // Crear: código en mayúsculas y sin espacios alrededor; nace con su raíz y sus tres zonas.
  const w=await act('save',{code:' sur-1 ',name:'  Almacén sur ',city:'Guayaquil'});
  assert.equal(w.code,'SUR-1');assert.equal(w.name,'Almacén sur');assert.equal(w.created,true);
  assert.deepEqual({...await one(`select code,name,address,city,active from warehouses where id=$1`,[w.id])},{code:'SUR-1',name:'Almacén sur',address:null,city:'Guayaquil',active:true});
  await db.exec('reset role');
  const locs=(await db.query(`select l.code,l.type,l.role,p.code parent from warehouse_locations l left join warehouse_locations p on p.id=l.parent_id where l.warehouse_id=$1 order by l.code`,[w.id])).rows;
  assert.deepEqual(locs.map(x=>({...x})),[
   {code:'CUARENTENA',type:'zone',role:'quarantine',parent:'STOCK'},
   {code:'LLEGADA',type:'zone',role:'arrival',parent:'STOCK'},
   {code:'SALIDA',type:'zone',role:'departure',parent:'STOCK'},
   {code:'STOCK',type:'warehouse',role:null,parent:null}]);
  // Las recepciones sin destino siguen entrando por el almacén principal.
  assert.equal((await one(`select w.code from warehouse_locations l join warehouses w on w.id=l.warehouse_id where l.id=private.gama_default_location()`)).code,'PRINCIPAL');

  // Lo demás funciona en el almacén nuevo: sus ubicaciones y sus estanterías cuelgan de su raíz.
  await as(keeper);
  const muelle=(await db.query('select public.gama_location_action($1,$2) r',['save',{warehouse_id:w.id,code:'MUELLE',name:'Muelle'}])).rows[0].r;
  const shelf=(await db.query('select public.gama_shelf_action($1,$2) r',['save',{warehouse_id:w.id,code:'AB',column_count:2,row_count:1}])).rows[0].r;
  await db.exec('reset role');
  assert.equal((await one(`select p.code from warehouse_locations l join warehouse_locations p on p.id=l.parent_id where l.id=$1`,[muelle.id])).code,'STOCK');
  assert.equal(Number((await one(`select count(*) n from warehouse_locations where shelf_id=$1`,[shelf.id])).n),2);

  // Reglas: código válido y libre, nombre obligatorio, textos acotados, sólo personal de almacén.
  await assert.rejects(act('save',{code:'PRINCIPAL',name:'Otro'}),/WAREHOUSE_CODE_TAKEN/);
  await assert.rejects(act('save',{code:'sur-1',name:'Otro'}),/WAREHOUSE_CODE_TAKEN/);
  await assert.rejects(act('save',{code:'a b',name:'x'}),/WAREHOUSE_CODE_INVALID/);
  await assert.rejects(act('save',{code:'',name:'x'}),/WAREHOUSE_CODE_INVALID/);
  await assert.rejects(act('save',{code:'NORTE',name:'  '}),/WAREHOUSE_NAME_REQUIRED/);
  await assert.rejects(act('save',{code:'NORTE',name:'x',city:'c'.repeat(121)}),/WAREHOUSE_TEXT_TOO_LONG/);
  await assert.rejects(act('save',{code:'NORTE',name:'Norte'},seller),/ROLE_NOT_ALLOWED/);
  await assert.rejects(act('delete',{id:w.id}),/INVALID_ACTION/);
  await db.exec('reset role');
  assert.equal(Number((await one(`select count(*) n from warehouses where code='NORTE'`)).n),0,'nada a medias');

  // Modificar: nombre, dirección y ciudad; el código no cambia.
  const k=await act('save',{id:w.id,name:'Almacén Guayaquil',address:' Av. 9 de Octubre 100 ',city:''},keeper);
  assert.equal(k.code,'SUR-1');
  await db.exec('reset role');
  assert.deepEqual({...await one(`select code,name,address,city from warehouses where id=$1`,[w.id])},{code:'SUR-1',name:'Almacén Guayaquil',address:'Av. 9 de Octubre 100',city:null});
  await assert.rejects(act('save',{id:w.id,code:'OTRO',name:'x'}),/WAREHOUSE_CODE_IMMUTABLE/);
  assert.equal((await act('save',{id:w.id,code:'sur-1',name:'Almacén Guayaquil'})).code,'SUR-1','el mismo código no es un cambio');
  await assert.rejects(act('save',{id:randomUUID(),name:'x'}),/WAREHOUSE_NOT_FOUND/);
  await assert.rejects(act('save',{id:w.id,name:'Sur'},seller),/ROLE_NOT_ALLOWED/);
 }finally{await db.close()}
});
