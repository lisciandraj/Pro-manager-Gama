const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('employee portraits preserve HR permissions, validate image sources and preserve omitted photos',async()=>{
 const db=await restore(),admin=randomUUID(),staff=randomUUID(),hr=randomUUID();
 const photo='data:image/jpeg;base64,YWJj';
 const as=uid=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated`);
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','photo-admin@example.invalid'),('${staff}','photo-staff@example.invalid'),('${hr}','photo-hr@example.invalid');update profiles set active=true,role=case id when '${admin}' then 'administrador' when '${hr}' then 'rrhh' else 'comercial' end;`);
  await as(admin);
  const save=(id,row)=>db.query('select public.gama_hr_save_employee($1::jsonb,$2::jsonb,$3::uuid) id',[JSON.stringify(row),'{}',id]);
  const id=(await save(null,{full_name:'Portrait User',profile_id:staff,photo_data:photo})).rows[0].id;
  await save(id,{full_name:'Portrait User',profile_id:staff});
  assert.equal((await db.query('select photo_data from hr_employees where id=$1',[id])).rows[0].photo_data,photo);
  await assert.rejects(save(id,{full_name:'Portrait User',profile_id:staff,photo_data:'https://example.invalid/portrait.png'}),/hr_employee_photo_format/);
  await assert.rejects(save(id,{full_name:'Portrait User',profile_id:staff,photo_data:'data:image/svg+xml;base64,YWJj'}),/hr_employee_photo_format/);
  await assert.rejects(save(id,{full_name:'Portrait User',profile_id:staff,photo_data:'data:image/jpeg;base64,'+'a'.repeat(120001)}),/hr_employee_photo_format/);
  await as(staff);
  assert.equal((await db.query('select photo_data from hr_employees where profile_id=$1',[staff])).rows[0].photo_data,photo);
  await assert.rejects(save(id,{full_name:'Portrait User',profile_id:staff,photo_data:null}),/HR permission required/);
  const direct=await db.query('update hr_employees set photo_data=null where id=$1 returning id',[id]);assert.equal(direct.rows.length,0);
  await as(hr);await save(id,{full_name:'Portrait User',profile_id:staff,photo_data:null});
  assert.equal((await db.query('select photo_data from hr_employees where id=$1',[id])).rows[0].photo_data,null);
  await db.exec('reset role;set role anon');
  await assert.rejects(save(id,{full_name:'Portrait User',photo_data:photo}),/permission denied/);
 }finally{await db.close()}
});
