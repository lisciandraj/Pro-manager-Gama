const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {restore}=require('../scripts/restore-schema.cjs');

// supabase/tests/hr-p1.sql recorre RRHH con sesiones reales (RLS): perfil
// «Responsable RH», N+1 que valida a su equipo, empleado, compañero y cliente.
// Se ejecuta en una transacción que se deshace, como pide el propio fichero.
test('el recorrido SQL de RRHH pasa con el perfil RH y el N+1',async()=>{
 const db=await restore();
 try{
  await db.exec('begin');
  const results=await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/tests/hr-p1.sql'),'utf8'));
  assert.deepEqual(results.at(-1).rows,[{result:'HR P1 database checks passed'}]);
  await db.exec('rollback');
 }finally{await db.close()}
});
