const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('Retired customer tokens cannot read owner rows or storage; staff business records remain',async()=>{
 const migration=fs.readdirSync(__dirname+'/../supabase/migrations').find(f=>f.endsWith('_retire_client_access.sql'));const db=await restore({before:migration}),admin=uuid(),buyer=uuid(),contact=uuid();
 try{
 await db.exec(`insert into auth.users(id,email) values('${admin}','staff@example.invalid'),('${buyer}','buyer@example.invalid');update profiles set role='administrador',active=true where id='${admin}';update profiles set role='cliente',active=true where id='${buyer}';insert into customers(id,name,email) values('${contact}','Preserved customer','buyer@example.invalid');`);
 await db.exec(`create policy test_owner on storage.objects for select to authenticated using(owner_id=auth.uid()::text);insert into storage.objects(bucket_id,name,owner_id) values('private','retired.txt','${buyer}');`);
 await db.exec(fs.readFileSync(__dirname+'/../supabase/migrations/'+migration,'utf8'));
 assert.equal((await db.query('select active from profiles where id=$1',[buyer])).rows[0].active,false);
 await db.exec(`update profiles set active=true where id='${buyer}'`);
 assert.equal((await db.query('select active from profiles where id=$1',[buyer])).rows[0].active,false);
 assert.equal((await db.query('select count(*)::int n from customers where id=$1',[contact])).rows[0].n,1);
 await db.exec(`select set_config('request.jwt.claim.sub','${buyer}',false);set role authenticated`);
 assert.equal((await db.query('select count(*)::int n from profiles')).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from customers')).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from storage.objects')).rows[0].n,0);
 await assert.rejects(db.query("select gama_catalog_command('preview','{}')"),/permission denied/);
 await assert.rejects(db.query('select gama_client_deliveries(null,0)'),/permission denied/);
 await db.exec(`reset role;select set_config('request.jwt.claim.sub','${admin}',false);set role authenticated`);
 assert.equal((await db.query('select count(*)::int n from customers where id=$1',[contact])).rows[0].n,1);
 await assert.rejects(db.query("select gama_assign_access_profile($1,'cliente')",[buyer]),/ACCESS_CLIENT_RETIRED/);
 const modules=(await db.query("select enabled from app_modules where id in('client-catalog','client-deliveries')")).rows;assert.equal(modules.length,2);assert(modules.every(x=>x.enabled===false));
 }finally{await db.close()}
});
