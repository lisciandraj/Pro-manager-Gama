const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{fixture}=require('./helpers/early-discount-fixture.cjs');
test('a partial direct-invoice credit reduces the component tax base proportionally',async()=>{
 const {db,ids,rpc,chart,day}=await fixture();try{
  const tax=await rpc('coco_tax_engine','tax_save',{request_key:uuid(),code:'CREDIT-BASE-VAT',name:'Credit base VAT',rate:15,kind:'collected',active:true,country:'EC',collected_account_id:chart['2100']});
  let invoice=await rpc('coco_direct_invoice_action','save',{request_key:uuid(),customer_id:ids.customer,issue_date:day,lines:[{description:'Partial credited service',quantity:1,unit_price:100,tax_ids:[tax.id]}]});invoice=await rpc('coco_direct_invoice_action','post',{request_key:uuid(),id:invoice.id,revision:invoice.direct_revision});
  await rpc('coco_direct_invoice_action','credit',{request_key:uuid(),id:invoice.id,percent:25,issued_on:day,reference:'CREDIT-BASE-25',reason:'Reviewed partial correction'});
  const report=await rpc('gama_accounting_action','taxes',{from:day,to:day}),component=report.components.find(x=>x.tax_id===tax.id);assert.equal(Number(component.amount),11.25);assert.equal(Number(component.base),75);
 }finally{await db.close()}
});
