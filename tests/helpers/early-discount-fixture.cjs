const {randomUUID:uuid}=require('node:crypto'),{restore}=require('../../scripts/restore-schema.cjs');
async function fixture(options={}){
 const db=await restore(options),ids=Object.fromEntries(['admin','reader','customer','supplier','product','bank'].map(k=>[k,uuid()]));
 const q=(s,p=[])=>db.query(s,p),value=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0],rpc=(fn,a,d={})=>value(`select public.${fn}($1,$2::jsonb)`,[a,JSON.stringify(d)]);
 await q('insert into auth.users(id,email) values($1,$2),($3,$4)',[ids.admin,'early-admin@example.invalid',ids.reader,'early-reader@example.invalid']);await q("update profiles set active=true,role=case when id=$1 then 'administrador' else 'comercial' end",[ids.admin]);await q('insert into accounting_permissions(profile_id,can_view,can_read_all) values($1,true,true)',[ids.reader]);
 await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);await db.exec("update company_settings set configured=true,legal_name='Early isolated fixture',country='EC',currency='USD',address='Quito'");
 await q("insert into customers(id,name,address,payment_terms_days) values($1,'Escompte client <safe>','Quito',30)",[ids.customer]);await q("insert into suppliers(id,name) values($1,'Escompte vendor')",[ids.supplier]);await q("insert into products(id,name,reference,sale_price,purchase_price,tax_rate) values($1,'Isolated discount item','EARLY-ITEM',100,100,21)",[ids.product]);
 const chart=Object.fromEntries((await q("select code,id from accounting_accounts where code in('1000','1200','2000','4000','6000','6080','2100','1300')")).rows.map(r=>[r.code,r.id]));await q("insert into financial_accounts(id,name,kind,account_id) values($1,'Isolated early bank','bank',$2)",[ids.bank,chart['1000']]);
 const day=await value("select ((now() at time zone private.erp_timezone())::date)::text");await db.exec('set role authenticated');
 const early=(a,d={})=>rpc('coco_early_discounts',a,d),terms=(mode='on_payment')=>({percent:2,days:7,tax_reduction:mode,account_id:chart['6080']||chart['6000']});
 const direct=async(mode='on_payment',issue=day,taxRate=21)=>{const i=await rpc('coco_direct_invoice_action','save',{request_key:uuid(),customer_id:ids.customer,issue_date:issue,payment_terms_days:30,lines:[{description:'Isolated service',quantity:1,unit_price:100,tax_rate:taxRate}],early_discount:terms(mode)});return rpc('coco_direct_invoice_action','post',{request_key:uuid(),id:i.id,revision:i.direct_revision})};
 const context=(id,side='customer',paid_on=day)=>early('preview',{side,invoice_id:id,paid_on});
 const pay=(id,amount,paid=day)=>rpc('gama_payment_action','payment',{request_key:uuid(),invoice_id:id,amount,paid_at:paid,method:'transfer',financial_account_id:ids.bank});
 const settle=async(id,side='customer',paid=day,key=uuid())=>{const c=await context(id,side,paid);return early('settle',{request_key:key,side,invoice_id:id,amount:c.due,paid_on:paid,financial_account_id:ids.bank,method:'transfer',reference:'EARLY-TEST'})};
 return {db,ids,q,value,rpc,chart,day,early,terms,direct,context,pay,settle};
}
module.exports={fixture};
