const fs=require('node:fs'),path=require('node:path');
const {isolateLocalPage}=require('./local-browser-fixture.cjs');
const cloud=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const order='10000000-0000-4000-8000-000000000001',purchase='10000000-0000-4000-8000-000000000002';
async function boot(page,{kind='sales',connected=true,language='fr'}={}){
 await isolateLocalPage(page);
 await page.addInitScript(({order,purchase,language})=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Test'}));localStorage.setItem('gama_language',language);
  window.__DB={products:[{id:'p1',name:'Papier A4',reference:'PAP-01',sale_price:10,purchase_price:6,tax_rate:15,stock:100,active:true,supplier_id:'s1'}],customers:[{id:'c1',name:'Costa Azul',email:'client@example.invalid',active:true}],suppliers:[{id:'s1',name:'Papelera Central',email:'supplier@example.invalid',active:true}],sales_orders:[{id:order,number:'PV-000001',customer_id:'c1',customer_name:'Costa Azul',delivery_address:'Quito',status:'confirmed',created_at:'2026-10-16T12:00:00Z'}],sales_order_lines:[{id:'l1',order_id:order,product_id:'p1',product_name:'Papier A4',reference:'PAP-01',quantity:10,unit_price:10,tax_rate:15}],sales_events:[],purchase_orders:[{id:purchase,supplier_id:'s1',order_number:'OC-000001',order_date:'2026-10-16',status:'draft',subtotal:60,total:60}],purchase_order_lines:[{id:'pl1',purchase_order_id:purchase,product_id:'p1',quantity:10,received_quantity:0,unit_cost:6,tax_rate:0,line_total:60}],stock_quants:[],warehouse_locations:[],profiles:[]};
 },{order,purchase,language});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaSales&&window.GamaCloudReady);
 await page.evaluate(async({connected,language})=>{
  await window.GamaCloudReady;await window.GamaI18n?.setLanguage?.(language);window.__mailCalls=[];window.__notes=[];window.__connected=connected;window.__entries=[];
  const original=window.GamaCloud.db;
  window.GamaCloud.db=async()=>{const c=await original();return {...c,functions:{invoke:async(_name,{body})=>{
   window.__mailCalls.push(body);
   if(body.action==='status')return {data:{google:false,microsoft:false,mailbox:null}};
   if(body.action==='send'){
    if(window.__sendFailure)return {data:{error:'MAIL_SEND_UNCERTAIN'},error:null};
    window.__entries.push({id:'sent-1',kind:body.kind,order_id:body.order_id,type:'mail',actor_name:'Alice',direction:'out',status:'sent',subject:body.subject,body:body.body,from_email:'alice@example.invalid',to_email:body.to,own_mailbox:true,created_at:new Date().toISOString(),attachments:(body.attachments||[]).map(a=>({name:a.name}))});return {data:{id:'sent-1',status:'sent'}};
   }
   if(body.action==='sync'&&window.__incoming&&!window.__entries.some(e=>e.id==='in-1'))window.__entries.push({id:'in-1',type:'mail',actor_name:'Client',direction:'in',status:'received',subject:'Re: PV-000001',body:'Livraison confirmée, merci.',from_email:'client@example.invalid',to_email:'alice@example.invalid',created_at:'2026-10-16T18:00:00Z',own_mailbox:true,attachments:[]});
   return {data:{imported:0}};
  }},rpc:async(name,args)=>{
   if(name==='coco_order_followup'){
    const b=args.p_data,kind=b.kind,o=kind==='sales'?window.__DB.sales_orders[0]:window.__DB.purchase_orders[0],ctx={kind,id:o.id,number:o.number||o.order_number,status:o.status,party:kind==='sales'?'Costa Azul':'Papelera Central',email:kind==='sales'?'client@example.invalid':'supplier@example.invalid',account_email:'alice@example.invalid',actor_id:'alice',can_mail:true,can_note:true,commercial:true,mailbox:window.__connected?{email:'alice@example.invalid',provider:'google'}:null};
    if(args.p_action==='note'){window.__notes.push(b);window.__entries.push({id:'note-'+window.__notes.length,type:'note',actor_name:'Alice',body:b.body,status:'recorded',created_at:new Date().toISOString()});return {data:{id:'note-1'}}}
    if(args.p_action==='disconnect'){window.__connected=false;return {data:{disconnected:true}}}
    if(args.p_action==='purchase_mail_sent'){if(o.status==='draft')o.status='sent';return {data:ctx}}
    if(args.p_action==='purchase_manual_sent'){o.status='sent';window.__entries.push({id:'manual-1',type:'action',subject:'purchase_manual_sent',actor_name:'Alice',body:b.body,status:'recorded',created_at:new Date().toISOString()});return {data:{id:'manual-1'}}}
    return {data:args.p_action==='context'?ctx:{context:ctx,entries:window.__entries,history:[{id:'created',step:3,action:'created',at:'2026-10-16T12:00:00Z',actor_name:'Alice',total:1}]}};
   }
   return c.rpc(name,args);
  }};
  };
 },{connected,language});
 if(kind==='sales')await page.evaluate(id=>window.GamaSales.openOrder(id),order);
 else {await page.evaluate(()=>window.gamaShowPurchases());await page.waitForSelector('#gp14Orders .gp14Order');await page.evaluate(id=>window.gamaOpenPurchaseV14(id),purchase)}
 await page.waitForSelector('.cocoFollowupParty',{state:'attached'});
}
module.exports={boot,order,purchase};
