const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs');

// El correo de creación de acceso se personaliza desde Usuarios: sólo el
// administrador lo lee y lo cambia, y dos ediciones a la vez no se pisan.
test('el modelo de invitación lo edita el administrador, con control de versión',async()=>{
 const db=await restore();const admin=randomUUID(),seller=randomUUID();
 const as=id=>db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[id]);
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','inv-admin@example.invalid'),('${seller}','inv-ventas@example.invalid');
   update profiles set active=true,role='administrador' where id='${admin}';update profiles set active=true,role='comercial' where id='${seller}';`);
  await as(admin);await db.exec('set role authenticated');
  const row=(await db.query('select subject,message,version from access_invitation_template')).rows[0];
  assert.match(row.subject,/\{empresa\}/);assert.match(row.message,/\{nombre\}/);
  const saved=(await db.query('select public.gama_save_invitation_template($1,$2,$3) r',['Bienvenida a {empresa}','Hola {nombre}',row.version])).rows[0].r;
  assert.equal(saved.subject,'Bienvenida a {empresa}');assert.equal(saved.version,row.version+1);
  await assert.rejects(db.query('select public.gama_save_invitation_template($1,$2,$3)',['Otro','Otro',row.version]),/TEMPLATE_STALE/,'una versión vieja no pisa la nueva');
  await assert.rejects(db.query('select public.gama_save_invitation_template($1,$2,$3)',['','Texto',saved.version]),/INVALID_TEMPLATE/);
  await assert.rejects(db.query(`update access_invitation_template set subject='x'`),/permission denied/,'nadie escribe la tabla directamente');
  await db.exec('reset role');await as(seller);await db.exec('set role authenticated');
  assert.equal((await db.query('select count(*)::int n from access_invitation_template')).rows[0].n,0,'el comercial no lo ve');
  await assert.rejects(db.query('select public.gama_save_invitation_template($1,$2,$3)',['A','B',saved.version]),/ROLE_NOT_ALLOWED/);
 }finally{await db.exec('reset role').catch(()=>{});await db.close()}
});
