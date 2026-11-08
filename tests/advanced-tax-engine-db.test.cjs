const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),fs=require('node:fs');
const {restore}=require('../scripts/restore-schema.cjs');
test('advanced tax engine keeps exact bases, frozen rules, fiscal substitutions and balanced rounding',async t=>{
 const db=await restore({before:'20261108163457'});await db.exec(fs.readFileSync('supabase/migrations/20261108163457_advanced_tax_engine.sql','utf8'));
 const q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const pure=(lines,rounding='line')=>v('select private.coco_tax_calculate_frozen($1::jsonb,$2)',[JSON.stringify(lines),rounding]);
 const rule=(over={})=>({id:uuid(),code:'VAT',rate:15,calculation_type:'percent',fixed_amount:0,price_included:false,sequence:10,include_base_amount:false,...over});
 const line=(rules,over={})=>({quantity:1,unit_price:100,discount:0,rules,...over});
 try{
  await t.test('excluded and included rates derive the same net and tax',async()=>{
   const a=await pure([line([rule()])]),b=await pure([line([rule({price_included:true})],{unit_price:115})]);
   for(const r of [a,b]){assert.equal(r.subtotal,100);assert.equal(r.tax,15);assert.equal(r.total,115)}
  });
  await t.test('fixed taxes follow quantities and expand later percentage bases in sequence',async()=>{
   const r=await pure([line([rule({calculation_type:'fixed',fixed_amount:5,rate:0,include_base_amount:true}),rule({sequence:20})],{quantity:2,unit_price:50})]);
   assert.equal(r.subtotal,100);assert.equal(r.tax,26.5);assert.equal(r.total,126.5);assert.deepEqual(r.lines[0].taxes.map(t=>t.amount),[10,16.5]);
  });
  await t.test('multiple included compounded rules invert prices algebraically without effective-rate approximation',async()=>{
   const r=await pure([line([rule({rate:5,price_included:true,include_base_amount:true}),rule({rate:10,sequence:20,price_included:true})],{unit_price:115.5})]);
   assert.equal(r.subtotal,100);assert.equal(r.tax,15.5);assert.deepEqual(r.lines[0].taxes.map(t=>t.amount),[5,10.5]);
   const high=await pure([line([rule({rate:15,price_included:true})],{quantity:10000,unit_price:1})]);assert.equal(high.subtotal,8695.65);assert.equal(high.tax,1304.35);assert.equal(high.total,10000);
  });
  await t.test('global rounding allocates residual cents and preserves every line and tax total',async()=>{
   const tax=rule(),lines=Array.from({length:3},(_,i)=>line([tax],{key:String(i),unit_price:.03}));
   const a=await pure(lines),b=await pure(lines,'global');assert.equal(a.tax,0);assert.equal(b.tax,.01);assert.equal(b.total,.1);
   assert.equal(b.lines.reduce((n,l)=>Math.round((n+l.tax)*100)/100,0),b.tax);assert.equal(b.taxes[0].amount,.01);
   assert.equal((await pure(lines,'global')).lines[0].tax,b.lines[0].tax);
  });
  await t.test('discount adjustments suppress fixed quantities while reducing percentage bases',async()=>{
   const rules=[rule({calculation_type:'fixed',rate:0,fixed_amount:5,include_base_amount:true}),rule({rate:10,sequence:20})];
   const r=await pure([line(rules),line(rules,{unit_price:-10,tax_quantity:0,line_kind:'discount'})]);
   assert.equal(r.subtotal,90);assert.equal(r.tax,14.5);assert.equal(r.total,104.5);assert.deepEqual(r.lines[1].taxes.map(t=>t.amount),[0,-1]);
  });
  await t.test('early tax-base reductions retain full revenue and recompute solely from frozen rules',async()=>{
   const source=await pure([line([rule({rate:21,price_included:true})],{unit_price:121})]);
   const result=await v('select private.coco_tax_recompute_snapshot($1::jsonb,.98)',[JSON.stringify(source)]);
   assert.equal(result.subtotal,100);assert.equal(result.tax,20.58);assert.equal(result.total,120.58);
  });
  await t.test('empty rules are exempt and legacy percentage arithmetic retains old four-decimal unit rounding',async()=>{
   assert.equal((await pure([line([])])).total,100);
   const r=await pure([line([rule({legacy:true})],{quantity:3,unit_price:.1234,discount:12.3456})]);const base=Math.round(3*(Math.round(.1234*(1-12.3456/100)*10000)/10000)*100)/100;assert.equal(r.subtotal,base);assert.equal(r.tax,Math.round(base*15)/100);
  });
  await t.test('included prices retain their currency total at sub-cent boundaries',async()=>{
   for(const rounding of ['line','global'])for(const amount of [.01,.02,.03,.04,.05,.06,.07,.08,.09]){const r=await pure([line([rule({price_included:true})],{unit_price:amount})],rounding);assert.equal(r.total,amount)}
   for(const rounding of ['line','global']){const many=await pure([line(Array.from({length:5},(_,i)=>rule({rate:10,sequence:i,price_included:true})),{unit_price:.09})],rounding);assert.equal(many.total,.09);assert.ok(many.lines[0].taxes.every(t=>t.amount>=0))}
   const r=await pure([line([rule({calculation_type:'fixed',rate:0,fixed_amount:.005,price_included:true})],{unit_price:.03})]);assert.equal(r.subtotal,.02);assert.equal(r.tax,.01);assert.equal(r.total,.03);
  });
  await t.test('invalid numbers, oversize quantities and inconsistent included fixed prices fail explicitly',async()=>{
   for(const change of [{quantity:0},{unit_price:'NaN'},{discount:101},{tax_base_factor:-1},{tax_quantity:2}])await assert.rejects(pure([line([rule()],change)]),/TAX_NUMBER_INVALID|TAX_LINES_INVALID/);
   await assert.rejects(pure([line([rule({calculation_type:'fixed',fixed_amount:10,price_included:true})],{unit_price:5})]),/TAX_INCLUDED_PRICE_TOO_LOW/);
   await assert.rejects(pure([line([])],'unknown'),/TAX_ROUNDING_INVALID/);
  });
 }finally{await db.close()}
});
