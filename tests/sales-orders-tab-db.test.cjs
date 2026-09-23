const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs');

// Los pedidos y las facturas son pestañas de Presupuestos y facturas: apagar el
// módulo, para la empresa o para un perfil, apaga también sus comprobaciones de servidor.
test('sales-orders and payments follow the quotes switch on the server',async()=>{
 const db=await restore();const seller=randomUUID(),warehouse=randomUUID(),admin=randomUUID();
 const as=id=>db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[id]);
 const allowed=async(who,roles,module='sales-orders')=>{await as(who);return (await db.query(`select private.erp_module_allowed($2,$1) ok`,[roles,module])).rows[0].ok};
 const staff=['administrador','comercial','almacenero'];
 try{
  await db.exec(`insert into auth.users(id,email) values('${seller}','orders-sales@example.invalid'),('${warehouse}','orders-wh@example.invalid'),('${admin}','orders-admin@example.invalid');
   update profiles set active=true,role='comercial' where id='${seller}';update profiles set active=true,role='almacenero' where id='${warehouse}';update profiles set active=true,role='administrador' where id='${admin}';`);
  assert.deepEqual((await db.query(`select private.erp_module_parent('sales-orders') o,private.erp_module_parent('payments') p`)).rows[0],{o:'quotes',p:'quotes'});
  assert.equal(await allowed(seller,staff),true);assert.equal(await allowed(warehouse,staff),true);
  assert.equal(await allowed(seller,staff,'payments'),true);
  await db.exec(`reset role;insert into app_modules(id,enabled) values('quotes',false) on conflict(id) do update set enabled=false`);
  assert.equal(await allowed(seller,staff),false,'módulo apagado para la empresa');
  assert.equal(await allowed(seller,staff,'payments'),false,'las facturas también');
  assert.equal(await allowed(warehouse,staff),false);
  await db.exec(`reset role;update app_modules set enabled=true where id='quotes'`);
  await as(admin);await db.query(`update role_module_access set disabled_modules=array['quotes'] where role='almacenero'`);
  assert.equal(await allowed(warehouse,staff),false,'módulo apagado para el perfil');
  assert.equal(await allowed(seller,staff),true,'los demás perfiles no cambian');
 }finally{await db.close()}
});
