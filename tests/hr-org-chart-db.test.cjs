const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {randomUUID}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs');
const migration=fs.readdirSync(path.join(__dirname,'../supabase/migrations')).find(f=>f.endsWith('_hr_base_role_org_chart.sql'));
const E=n=>'00000000-0000-0000-0000-00000000e00'+n;

// «Responsable RH» es un perfil de base, no un derecho añadido; el N+1 de cada
// empleado es otro empleado, y quien es N+1 con cuenta valida lo de su equipo.
// Se reproduce la base de antes (derechos en hr_permissions, responsable como
// cuenta) y se le aplica la migración.
test('el perfil RH gestiona RRHH sin ver ventas ni almacén, y el N+1 valida a su equipo',async()=>{
 const db=await restore({before:migration});
 const admin=randomUUID(),hr=randomUUID(),keeper=randomUUID(),seller=randomUUID(),legacy=randomUUID();
 const as=uid=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated`);
 const su=()=>db.exec(`reset role;select set_config('request.jwt.claim.sub','',false)`);
 const rows=async(sql,args=[])=>(await db.query(sql,args)).rows;
 const one=async(sql,args=[])=>(await rows(sql,args))[0];
 const status=async id=>{await su();return (await one('select status from hr_absences where id=$1',[id])).status};
 try{
  // Antes: un comercial con el derecho «Responsable RH», el almacenero con el de
  // «Responsable de equipo» y un empleado cuyo responsable es su cuenta.
  await db.exec(`insert into auth.users(id,email) values('${admin}','org-admin@example.invalid'),('${hr}','org-hr@example.invalid'),('${keeper}','org-keeper@example.invalid'),('${seller}','org-seller@example.invalid'),('${legacy}','org-legacy@example.invalid');
   update profiles set active=true,role=case id when '${admin}' then 'administrador' when '${keeper}' then 'almacenero' else 'comercial' end;
   insert into hr_permissions(profile_id,role) values('${legacy}','hr'),('${keeper}','manager');
   insert into hr_employees(id,full_name,profile_id) values('${E(1)}','Jefa de almacén','${keeper}'),('${E(2)}','Mozo','${seller}'),('${E(3)}','Chófer sin cuenta',null);
   update hr_employees set manager_profile_id='${keeper}' where id in ('${E(2)}','${E(3)}');
   insert into hr_employee_private(employee_id,salary) values('${E(1)}',1200),('${E(2)}',700),('${E(3)}',650);
   insert into products(name,reference) values('Cemento','CEM');`);
  await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations',migration),'utf8'));

  // El derecho antiguo pasa al perfil; el responsable-cuenta pasa a N+1-empleado.
  assert.equal((await one('select role from profiles where id=$1',[legacy])).role,'rrhh');
  assert.deepEqual((await rows('select id,manager_id from hr_employees order by id')).map(r=>r.manager_id),[null,E(1),E(1)]);
  assert.deepEqual({...await one(`select base_role,is_custom,display_name,disabled_modules from role_module_access where role='rrhh'`)},{base_role:'rrhh',is_custom:false,display_name:'Responsable RH',disabled_modules:[]});

  // El administrador da el perfil desde Usuarios, como cualquier otro; el Asistente conoce el N+1.
  await as(admin);
  assert.ok((await one('select public.gama_ai_catalog() c')).c.find(t=>t.table==='hr_employees').columns.includes('manager_id'));
  await db.query('select public.gama_assign_access_profile($1,$2)',[hr,'rrhh']);
  await su();assert.equal((await one('select role,access_profile from profiles where id=$1',[hr])).role,'rrhh');

  // RRHH: toda la plantilla con sus datos privados y las cuentas que se pueden ligar…
  await as(hr);
  assert.equal((await rows('select id from hr_employees')).length,3);
  assert.equal((await rows('select salary from hr_employee_private')).length,3);
  const directory=(await one('select public.gama_hr_directory() d')).d.map(p=>p.role).sort();
  assert.deepEqual(directory,['administrador','almacenero','comercial','rrhh','rrhh']);
  // …y documentos de RRHH o de equipo, pero no los de dirección.
  assert.deepEqual({...await one(`select private.document_audience('hr') hr,private.document_audience('team') team,private.document_audience('management') management`)},{hr:true,team:true,management:false});
  // Nada de ventas ni de almacén: no es personal de esos módulos.
  assert.equal((await rows('select id from products')).length,0);

  // La ficha guarda su N+1; guardarla sin la clave no lo toca.
  const nuevo=(await one('select public.gama_hr_save_employee($1,$2,null) id',[{full_name:'Aprendiz',manager_id:E(2)},{}])).id;
  assert.equal((await one('select manager_id from hr_employees where id=$1',[nuevo])).manager_id,E(2));
  await db.query('select public.gama_hr_save_employee($1,$2,$3)',[{full_name:'Aprendiz'},{},nuevo]);
  assert.equal((await one('select manager_id from hr_employees where id=$1',[nuevo])).manager_id,E(2));
  await db.query('select public.gama_hr_save_employee($1,$2,$3)',[{full_name:'Aprendiz',manager_id:''},{},nuevo]);
  assert.equal((await one('select manager_id from hr_employees where id=$1',[nuevo])).manager_id,null);

  // Un organigrama sin círculos, sin uno mismo y sin N+1 archivado.
  await assert.rejects(db.query('update hr_employees set manager_id=$1 where id=$2',[E(2),E(1)]),/HR_MANAGER_CYCLE/);
  await assert.rejects(db.query('update hr_employees set manager_id=$1 where id=$1',[E(1)]),/HR_MANAGER_SELF/);
  await db.query('update hr_employees set active=false where id=$1',[E(3)]);
  await assert.rejects(db.query('update hr_employees set manager_id=$1 where id=$2',[E(3),nuevo]),/HR_MANAGER_INACTIVE/);

  // El N+1 con cuenta valida lo de su equipo, nunca lo suyo (RRHH registra las solicitudes).
  const [mozo,jefa]=(await rows(`insert into hr_absences(employee_id,kind,start_date,end_date,status) values('${E(2)}','permiso','2026-10-05','2026-10-05','pendiente'),('${E(1)}','permiso','2026-10-06','2026-10-06','pendiente') returning id`)).map(r=>r.id);
  await as(keeper);await db.query(`update hr_absences set status='aprobada' where id=$1`,[mozo]);
  assert.equal(await status(mozo),'aprobada');
  await as(keeper);await db.query(`update hr_absences set status='aprobada' where id=$1`,[jefa]).catch(()=>{});
  assert.equal(await status(jefa),'pendiente');
  // Un compañero sin equipo no valida nada.
  await as(seller);await db.query(`update hr_absences set status='aprobada' where id=$1`,[jefa]).catch(()=>{});
  assert.equal(await status(jefa),'pendiente');

  // Los derechos antiguos ya no cuentan: sin el vínculo de N+1, el «Responsable
  // de equipo» no valida; con una fila «hr», un comercial no ve la plantilla.
  await su();await db.exec(`update hr_employees set manager_id=null where id='${E(2)}';insert into hr_permissions(profile_id,role) values('${seller}','hr') on conflict(profile_id) do update set role='hr';`);
  await as(hr);const otra=(await one(`insert into hr_absences(employee_id,kind,start_date,end_date,status) values('${E(2)}','permiso','2026-10-07','2026-10-07','pendiente') returning id`)).id;
  await as(keeper);await db.query(`update hr_absences set status='aprobada' where id=$1`,[otra]).catch(()=>{});
  assert.equal(await status(otra),'pendiente');
  await as(seller);assert.deepEqual((await rows('select employee_id from hr_employee_private')).map(r=>r.employee_id),[E(2)]);
 }finally{await db.close()}
});

// Con la pantalla nueva publicada, lo antiguo se retira: ni tabla de derechos ni
// responsable-cuenta, y el traspaso de una cuenta ya no mueve equipos.
test('la limpieza retira los derechos antiguos y el responsable-cuenta',async()=>{
 const db=await restore();
 try{
  const cols=(await db.query(`select column_name from information_schema.columns where table_schema='public' and table_name='hr_employees'`)).rows.map(r=>r.column_name);
  assert.ok(cols.includes('manager_id'));assert.ok(!cols.includes('manager_profile_id'));
  assert.equal((await db.query(`select to_regclass('public.hr_permissions')::text t`)).rows[0].t,null);
  const def=async f=>(await db.query(`select pg_get_functiondef($1::regprocedure) d`,[f])).rows[0].d;
  assert.ok(!(await def('private.gama_user_handover(jsonb)')).includes('manager_profile_id'));
  const catalog=await def('public.gama_ai_catalog()');
  assert.ok(!catalog.includes('hr_permissions')&&!catalog.includes('manager_profile_id')&&catalog.includes('"manager_id"'));
 }finally{await db.close()}
});
