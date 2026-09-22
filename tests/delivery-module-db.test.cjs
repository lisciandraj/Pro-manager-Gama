const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs');

// La preparación es una pestaña de Entrega: apagar 'tms' a un perfil también
// cierra las comprobaciones de servidor que aún nombran 'order-preparation'.
test('el permiso de Entrega gobierna la preparación',async()=>{
 const db=await restore();const user=randomUUID(),admin=randomUUID();
 const as=id=>db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[id]);
 const allowed=async m=>{await as(user);return (await db.query(`select private.erp_module_allowed($1,array['administrador','almacenero']) ok`,[m])).rows[0].ok};
 const disable=async list=>{await as(admin);assert.equal((await db.query(`update role_module_access set disabled_modules=$1 where role='almacenero'`,[list])).affectedRows,1)};
 try{
  await db.exec(`insert into auth.users(id,email) values('${user}','entrega@example.invalid'),('${admin}','entrega-admin@example.invalid');
   update profiles set active=true,role='almacenero' where id='${user}';update profiles set active=true,role='administrador' where id='${admin}';`);
  await disable([]);
  assert.equal(await allowed('order-preparation'),true);
  await disable(['tms']);
  assert.equal(await allowed('order-preparation'),false,'sin Entrega no hay preparación');
  assert.equal(await allowed('tms'),false);
  assert.equal(await allowed('warehouses'),true,'el resto de módulos no cambia');
  await disable([]);
  await db.exec(`insert into app_modules(id,enabled) values('tms',false) on conflict(id) do update set enabled=false`);
  assert.equal(await allowed('order-preparation'),false,'Entrega desinstalada: tampoco preparación');
 }finally{await db.close()}
});
