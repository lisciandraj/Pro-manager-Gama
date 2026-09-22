const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs');

// Contactos reúne Clientes y Proveedores: su interruptor gobierna las
// comprobaciones de servidor que siguen nombrando los ids antiguos.
test('el permiso de Contactos gobierna clientes y proveedores',async()=>{
 const db=await restore();const user=randomUUID(),admin=randomUUID();
 const as=id=>db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[id]);
 const allowed=async m=>{await as(user);return (await db.query(`select private.erp_module_allowed($1,array['administrador','comercial']) ok`,[m])).rows[0].ok};
 const disable=async list=>{await as(admin);assert.equal((await db.query(`update role_module_access set disabled_modules=$1 where role='comercial'`,[list])).affectedRows,1)};
 try{
  await db.exec(`insert into auth.users(id,email) values('${user}','contactos@example.invalid'),('${admin}','contactos-admin@example.invalid');
   update profiles set active=true,role='comercial' where id='${user}';update profiles set active=true,role='administrador' where id='${admin}';`);
  await disable([]);
  for(const m of ['clients','suppliers','contacts'])assert.equal(await allowed(m),true,m);
  await disable(['contacts']);
  for(const m of ['clients','suppliers','contacts'])assert.equal(await allowed(m),false,'sin Contactos: '+m);
  assert.equal(await allowed('quotes'),true,'el resto de módulos no cambia');
  await disable(['dashboard']);
  assert.equal(await allowed('operations'),false,'el seguimiento vive en el panel de control');
 }finally{await db.close()}
});

// La fusión no abre nada: quien tenía cerrado Clientes o Proveedores tiene
// cerrado Contactos.
test('un perfil sin clientes ni proveedores queda sin Contactos',async()=>{
 const fs=require('node:fs'),path=require('node:path');
 const file=fs.readdirSync(path.join(__dirname,'../supabase/migrations')).find(f=>f.endsWith('_contacts_module.sql'));
 const sql=fs.readFileSync(path.join(__dirname,'../supabase/migrations',file),'utf8');
 const db=await restore();
 try{
  await db.exec(`alter table role_module_access disable trigger stamp_role_module_access;
   update role_module_access set disabled_modules='{suppliers,stock}' where role='comercial';
   update role_module_access set disabled_modules='{}' where role='almacenero';
   alter table role_module_access enable trigger stamp_role_module_access;`);
  const before=(await db.query(`select version from role_module_access where role='comercial'`)).rows[0].version;
  await db.exec(sql.slice(sql.indexOf('alter table public.role_module_access disable')));
  const rows=Object.fromEntries((await db.query(`select role,disabled_modules d,version from role_module_access`)).rows.map(r=>[r.role,r]));
  assert.deepEqual(rows.comercial.d,['suppliers','stock','contacts']);
  assert.equal(rows.comercial.version,before+1,'la versión avanza: las pantallas abiertas recargan');
  assert.deepEqual(rows.almacenero.d,[]);
 }finally{await db.close()}
});
