const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs');

// La pista de auditoría enseña sólo lo importante: stock, cobros y pagos,
// facturas, validaciones y accesos, con palabras de negocio y quién lo hizo.
test('la pista reúne las acciones importantes y se filtra por tipo, persona y texto',async()=>{
 const db=await restore();const admin=randomUUID(),seller=randomUUID(),product=randomUUID();
 const as=id=>db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[id]);
 const trail=async(f={})=>{await as(admin);return (await db.query('select public.gama_audit_trail($1) r',[f])).rows[0].r};
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','pista-admin@example.invalid'),('${seller}','pista-ventas@example.invalid');
   update profiles set active=true,role='administrador',full_name='Ana Admin' where id='${admin}';update profiles set active=true,role='comercial',full_name='Víctor Ventas' where id='${seller}';
   insert into products(id,name,barcode,stock) values('${product}','Tornillo M8','PISTA-01',0);`);
  for(const [type,kind,qty,user,at] of [['in','receipt',10,admin,'2026-09-01'],['out','delivery',3,seller,'2026-09-05'],['out','inventory_adjustment',1,admin,'2026-09-10']])
   await db.query(`insert into stock_movements(product_id,type,movement_type,quantity,reason,user_id,created_at) values($1,$2,$3,$4,'QA',$5,$6)`,[product,type,kind,qty,user,at]);
  await db.query(`insert into erp_approvals(module,document_id,fingerprint,reason,status,requested_by,reviewed_by,reviewed_at,decision_reason) values('quotes',gen_random_uuid(),'x','Descuento 20 %','approved',$1,$2,'2026-09-11','Cliente estratégico')`,[seller,admin]);

  const all=await trail();
  const labels=all.items.map(i=>i.label);
  for(const l of ['Recepción de compra','Salida por entrega','Ajuste de inventario','Validación aprobada'])assert.ok(labels.includes(l),l);
  assert.ok(all.items.every((x,i,a)=>!i||a[i-1].at>=x.at),'lo más reciente primero');
  const delivery=all.items.find(i=>i.label==='Salida por entrega');
  assert.equal(delivery.actor,'Víctor Ventas');assert.equal(Number(delivery.quantity),-3);assert.match(delivery.detail,/Tornillo M8/);

  const stock=await trail({kind:'stock'});assert.equal(stock.items.length,3);assert.ok(stock.items.every(i=>i.kind==='stock'));
  const mine=await trail({kind:'stock',actor:seller});assert.deepEqual(mine.items.map(i=>i.label),['Salida por entrega']);
  const found=await trail({search:'estratégico'});assert.deepEqual(found.items.map(i=>i.label),['Validación aprobada']);
  const range=await trail({kind:'stock',from:'2026-09-02',to:'2026-09-05'});assert.deepEqual(range.items.map(i=>i.label),['Salida por entrega']);
  const first=await trail({kind:'stock',limit:2});assert.equal(first.items.length,2);assert.equal(first.has_more,true);
  const next=await trail({kind:'stock',limit:2,offset:2});assert.equal(next.items.length,1);assert.equal(next.has_more,false);
  const access=await trail({kind:'access'});assert.ok(access.items.some(i=>i.label==='Usuario modificado'&&/Víctor Ventas/.test(i.detail)),'los cambios de usuario');
  await assert.rejects(trail({kind:'otro'}),/INVALID_KIND/);

  await as(seller);await assert.rejects(db.query('select public.gama_audit_trail($1)',[{}]),/ROLE_NOT_ALLOWED/,'sólo el administrador');
 }finally{await db.close()}
});
