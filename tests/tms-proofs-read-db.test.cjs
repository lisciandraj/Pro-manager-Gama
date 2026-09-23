const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');const {restore}=require('../scripts/restore-schema.cjs');

// Las pruebas de entrega se leen por tms_proofs_read (gama-supabase.js cambia
// la tabla por la vista, que sirve la foto). Seguimiento de procesos pide ahí
// columnas concretas; si una falta, PostgREST responde 400 y ninguna venta con
// una entrega creada se abre. Pasó con erp_reference.
test('la vista de las pruebas de entrega tiene todo lo que pide Seguimiento de procesos',async()=>{
 const src=fs.readFileSync(path.join(__dirname,'..','gama-dossier-flow.js'),'utf8');
 const asked=src.match(/by\('tms_proofs','delivery_id',ids\([^)]*\),'([a-z_,]+)'\)/);
 assert.ok(asked,'la lectura de las pruebas sigue en gama-dossier-flow.js');
 const db=await restore();
 try{
  const cols=new Set((await db.query(`select column_name from information_schema.columns where table_schema='public' and table_name='tms_proofs_read'`)).rows.map(r=>r.column_name));
  for(const c of asked[1].split(','))assert.ok(cols.has(c),'falta tms_proofs_read.'+c);
  // La misma vista de siempre: con los permisos de quien lee y sólo para usuarios con sesión.
  assert.deepEqual((await db.query(`select reloptions from pg_class where oid='public.tms_proofs_read'::regclass`)).rows[0].reloptions,['security_invoker=true']);
  const grants=(await db.query(`select has_table_privilege('authenticated','public.tms_proofs_read','select') a,has_table_privilege('anon','public.tms_proofs_read','select') b`)).rows[0];
  assert.deepEqual({...grants},{a:true,b:false});
  await db.query(`select ${asked[1]} from public.tms_proofs_read limit 1`);
 }finally{await db.close()}
});
