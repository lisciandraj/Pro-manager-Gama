const fs=require('node:fs'),path=require('node:path');
const {isolateLocalPage}=require('./local-browser-fixture.cjs');
const cloud=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const order='10000000-0000-4000-8000-000000000001',purchase='10000000-0000-4000-8000-000000000002',delivery='10000000-0000-4000-8000-000000000003';
async function boot(page,{kind='sales',connected=true,language='fr',proposal=false,summary='Demande client : trois paquets de papier.'}={}){
 await isolateLocalPage(page);
 await page.addInitScript(({order,purchase,delivery,language})=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Test'}));localStorage.setItem('gama_language',language);localStorage.setItem('gama_tms_migrated_v1','1');const day=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil'}).format(new Date());
  window.__DB={products:[{id:'p1',name:'Papier A4',reference:'PAP-01',sale_price:10,purchase_price:6,tax_rate:15,stock:100,active:true,supplier_id:'s1'}],customers:[{id:'c1',name:'Costa Azul',email:'client@example.invalid',address:'Quito',active:true}],suppliers:[{id:'s1',name:'Papelera Central',email:'supplier@example.invalid',active:true}],sales_orders:[{id:order,number:'PV-000001',customer_id:'c1',customer_name:'Costa Azul',delivery_address:'Quito',status:'confirmed',created_at:'2026-10-16T12:00:00Z'}],sales_order_lines:[{id:'l1',order_id:order,product_id:'p1',product_name:'Papier A4',reference:'PAP-01',quantity:10,unit_price:10,tax_rate:15}],sales_events:[],purchase_orders:[{id:purchase,supplier_id:'s1',order_number:'OC-000001',order_date:'2026-10-16',status:'draft',subtotal:60,total:60}],purchase_order_lines:[{id:'pl1',purchase_order_id:purchase,product_id:'p1',quantity:10,received_quantity:0,unit_cost:6,tax_rate:0,line_total:60}],stock_quants:[],warehouse_locations:[],profiles:[],hr_employees:[],hr_absences:[],tms_routes:[],tms_proofs:[],tms_settings:[],fleet_drivers:[],fleet_assignments:[],fleet_vehicles:[],tms_events:[],tms_deliveries:[{id:delivery,customer:'Costa Azul',address:'Quito',delivery_date:day,status:'Pendiente de preparación',erp_reference:'TMS-001'}],__today:day};
 },{order,purchase,delivery,language});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaSales&&window.GamaCloudReady);
 await page.evaluate(async({connected,language,proposal,summary})=>{
  await window.GamaCloudReady;await window.GamaI18n?.setLanguage?.(language);window.__mailCalls=[];window.__notes=[];window.__decisions=[];window.__bridgeEnabled=connected;window.__entries=[];window.__proposals=proposal?[{id:'proposal-1',status:'pending',action:'quote_draft',summary,payload:{customer_id:'c1',customer_name:'Costa Azul',delivery_address:'Quito',lines:[{product_id:'p1',description:'Papier A4',quantity:3}]},source_email:'client@example.invalid',source_subject:'Demande de devis',message_id:'mail-1'}]:[];
  if(proposal)window.__entries.push({id:'analysis-1',type:'note',subject:'mail_analysis',actor_name:'ChatGPT',body:window.__proposals[0].summary,proposal_id:'proposal-1',created_at:'2026-10-17T12:00:00Z'});
  const original=window.GamaCloud.db;
  window.GamaCloud.db=async()=>{const c=await original();return {...c,functions:{invoke:async(name,args)=>{window.__mailCalls.push({name,...args});throw Error('Mailbox connector retired')}},rpc:async(name,args)=>{
   if(name==='coco_dossier'){
    const b=args.p_data,kind=b.kind,o=kind==='sales'||kind==='quote'?window.__DB.sales_orders[0]:kind==='tms'?window.__DB.tms_deliveries[0]:window.__DB.purchase_orders[0],ctx={kind,id:b.order_id,number:b.order_id?(o.number||o.order_number||o.erp_reference):'Ventas',status:b.order_id?o.status:'inbox',party:!b.order_id?'ChatGPT':kind==='purchase'?'Papelera Central':'Costa Azul',account_email:'alice@example.invalid',actor_id:'alice',can_note:true,commercial:true,can_review:true,bridge:{enabled:window.__bridgeEnabled,email:'alice@example.invalid'},stages:[{title:'Presupuesto',state:'done'},{title:'Pedido',state:'done'},{title:'Preparación',state:'current'},{title:'Entrega',state:'pending'},{title:'Factura',state:'pending'},{title:'Pago',state:'pending'}]};
    if(args.p_action==='note'){window.__notes.push(b);window.__entries.push({id:'note-'+window.__notes.length,type:'note',actor_name:'Alice',actor_id:'alice',body:b.body,status:'recorded',created_at:new Date().toISOString()});return {data:{id:'note-1'}}}
    if(args.p_action==='bridge_disable'){window.__bridgeEnabled=false;return {data:{enabled:false}}}
    if(args.p_action==='review_proposal'){window.__reviewPayload=b.payload;return {data:{hash:'checked-v1',action:'quote_draft',review:{details:{client:'Costa Azul',delivery_address:'Quito'},lines:[{description:'Papier A4',quantity:3,list_price:10,tax_rate:15}]}}}}
    if(args.p_action==='approve_proposal'){window.__decisions.push(b);window.__proposals[0].status='approved';window.__proposals[0].result={kind:'quote',id:'new-quote'};return {data:{kind:'quote',id:'new-quote'}}}
    if(args.p_action==='reject_proposal'){window.__proposals[0].status='rejected';return {data:{status:'rejected'}}}
    return {data:args.p_action==='context'?ctx:{context:ctx,entries:window.__entries,proposals:window.__proposals,portraits:{alice:'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1AAAAABJRU5ErkJggg=='},history:[{id:'created',step:2,action:'created',at:'2026-10-16T12:00:00Z',actor_id:'alice',actor_name:'Alice',total:1}]}};
   }
   if(name==='coco_order_followup'&&args.p_action==='purchase_manual_sent'){window.__DB.purchase_orders[0].status='sent';window.__entries.push({id:'manual-1',type:'note',subject:'purchase_manual_sent',actor_name:'Alice',actor_id:'alice',body:args.p_data.body,created_at:new Date().toISOString()});return {data:{id:'manual-1'}}}
   return c.rpc(name,args);
  }};};
 },{connected,language,proposal,summary});
 if(kind==='sales')await page.evaluate(id=>window.GamaSales.openOrder(id),order);
 else if(kind==='tms')await page.evaluate(()=>window.ArcRouter.open('tms'));
 else {await page.evaluate(()=>window.gamaShowPurchases());await page.waitForSelector('#gp14Orders .gp14Order');await page.evaluate(id=>window.gamaOpenPurchaseV14(id),purchase)}
 await page.waitForSelector('.cocoFollowupParty',{state:'attached'});
}
module.exports={boot,order,purchase,delivery};
