const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');const {restore}=require('../scripts/restore-schema.cjs');

// Las pruebas de entrega se leen por tms_proofs_read (gama-supabase.js cambia
// la tabla por la vista, que sirve la foto). Seguimiento de procesos pide ahí
// columnas concretas (las barras de la lista y el detalle); si una falta,
// PostgREST responde 400 y ninguna venta con una entrega creada se abre.
// Pasó con erp_reference.
test('la vista de las pruebas de entrega tiene todo lo que pide Seguimiento de procesos',async()=>{
 const src=fs.readFileSync(path.join(__dirname,'..','gama-dossier-flow.js'),'utf8');
 assert.match(src,/by\('tms_proofs','delivery_id',\w+,proofColumns\)/,'la lectura de las pruebas sigue en gama-dossier-flow.js');
 const asked=[...src.matchAll(/PROOF_\w*COLUMNS='([a-z_,]+)'/g)].map(m=>m[1]);
 assert.equal(asked.length,2,'las columnas de la barra y las del detalle');
 const db=await restore();
 try{
  const cols=new Set((await db.query(`select column_name from information_schema.columns where table_schema='public' and table_name='tms_proofs_read'`)).rows.map(r=>r.column_name));
  for(const c of asked.join(',').split(','))assert.ok(cols.has(c),'falta tms_proofs_read.'+c);
  // La misma vista de siempre: con los permisos de quien lee y sólo para usuarios con sesión.
  assert.deepEqual((await db.query(`select reloptions from pg_class where oid='public.tms_proofs_read'::regclass`)).rows[0].reloptions,['security_invoker=true']);
  const grants=(await db.query(`select has_table_privilege('authenticated','public.tms_proofs_read','select') a,has_table_privilege('anon','public.tms_proofs_read','select') b`)).rows[0];
  assert.deepEqual({...grants},{a:true,b:false});
  for(const columns of asked)await db.query(`select ${columns} from public.tms_proofs_read limit 1`);
 }finally{await db.close()}
});
