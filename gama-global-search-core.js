/* Spotlight queries: read-only, caller-scoped Supabase reads; no AI provider. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.GamaSearchCore=api;})(typeof window==='undefined'?globalThis:window,function(){
'use strict';
const PAGE=30;
const normalize=v=>String(v??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[’']/g,' ').replace(/\s+/g,' ').trim();
const aliases={cmd:'PED',ped:'PED',ord:'PED',fac:'FAC',inv:'FAC',cot:'COT',dev:'COT',quo:'COT',env:'ENV',exp:'ENV',ent:'ENT',liv:'ENT',cob:'COB',pay:'COB'};
const tables={PED:'sales_orders',FAC:'external_invoices',COT:'invoices',ENV:'sales_deliveries',ENT:'tms_deliveries',COB:'external_invoice_payments'};
function reference(value){const m=normalize(value).match(/^([a-z]{3})(?:[- ]([a-z]+))?[- ]?0*(\d+)$/);return m&&aliases[m[1]]?{prefix:aliases[m[1]],ordinal:m[2]?.toUpperCase()||'',number:Number(m[3]),table:tables[aliases[m[1]]]}:null;}
function sameReference(a,b){const x=reference(a),y=reference(b);return !!x&&!!y&&x.prefix===y.prefix&&x.number===y.number&&x.ordinal===y.ordinal;}
const entityWords={
 invoices:/\b(factures?|facturas?|invoices?)\b/g,orders:/\b(commandes?|pedidos?|orders?)\b/g,
 shipments:/\b(expeditions?|expediciones?|livraisons?|entregas?|deliveries|delivery|shipments?)\b/g,
 quotes:/\b(devis|presupuestos?|cotizaciones?|quotes?)\b/g,
 products:/\b(produits?|productos?|products?)\b/g,clients:/\b(clients?|clientes?|customers?)\b/g,
 suppliers:/\b(fournisseurs?|proveedores?|suppliers?)\b/g,contacts:/\b(contacts?|contactos?)\b/g,
 payments:/\b(paiements?|pagos?|cobros?|payments?)\b/g,knowledge:/\b(knowledge|articles?|articulos?)\b/g
};
const late=/\b(en retard|atrasad[oa]s?|retrasad[oa]s?|vencid[oa]s?|overdue|late|echues?|echu)\b/g;
const unpaid=/\b(impayees?|non payees?|non reglees?|sans paiement|sin pagar|no pagad[oa]s?|pendientes? de (pago|cobro)|unpaid|outstanding|not paid)\b/g;
const paid=/\b(payees?|reglees?|pagad[oa]s?|paid|settled)\b/g;
const unanswered=/\b(sans reponse|sin respuesta|unanswered|awaiting response)\b/g;
function parse(value){
 const raw=String(value??'').trim().slice(0,160),q=normalize(raw),ref=reference(q);
 if(ref)return {raw,text:q,ref,entity:null,intent:null};
 // Negation is deliberately kept literal unless it is the supported "not paid".
 let entity=null;for(const [key,re] of Object.entries(entityWords)){re.lastIndex=0;if(re.test(q)){entity=key;break}}
 let intent=null,condition=null;
 if(entity==='invoices'){unpaid.lastIndex=0;late.lastIndex=0;paid.lastIndex=0;if(unpaid.test(q)){intent='invoices_unpaid';condition=unpaid}else if(late.test(q)){intent='invoices_overdue';condition=late}else if(paid.test(q)){intent='invoices_paid';condition=paid}}
 if(['orders','shipments'].includes(entity)){late.lastIndex=0;if(late.test(q)){intent=entity+'_late';condition=late}}
 if(entity==='quotes'){unanswered.lastIndex=0;if(unanswered.test(q)){intent='quotes_unanswered';condition=unanswered}}
 if(intent){
  let rest=q.replace(condition,' ').replace(entityWords[entity],' ').replace(/\b(affiche|afficher|montre|montrer|trouve|trouver|recherche|chercher|liste|lister|show|find|list|search|buscar|busca|mostrar|muestra|las|los|les|des|mes|mis|my|the|all|toutes|tous|todas|todos|de|du|del|pour|for|par|client|cliente|customer)\b/g,' ').replace(/\s+/g,' ').trim();
  if(/\b(pas|not|non|no|sauf|except|sin)\b/.test(rest))return {raw,text:q,ref:null,entity:null,intent:null};
  return {raw,text:rest,ref:null,entity,intent};
 }
 return {raw,text:q,ref:null,entity:null,intent:null};
}
const roles={administrador:'admin',comercial:'commercial',almacenero:'magasinier',cliente:'client'};
const permissions={admin:'*',commercial:['clients','crm','products','suppliers','quotes','sales-orders','payments','knowledge','accounting'],magasinier:['products','sales-orders','tms','knowledge'],client:['client-catalog','quotes','client-deliveries']};
function access(profile,module,allowed=()=>true){const role=roles[profile?.role]||profile?.role;const p=permissions[role];return profile?.active!==false&&!!p&&(p==='*'||p.includes(module))&&allowed(module);}
const SOURCES=[
 {key:'clients',module:'clients',table:'customers',select:'id,name,identification,email,phone,city,active',fields:['name','identification','email','phone'],title:r=>r.name,subtitle:r=>[r.identification,r.email,r.city]},
 {key:'contacts',module:'crm',table:'crm_contacts',select:'id,first_name,last_name,email,phone,job_title,active',fields:['first_name','last_name','email','phone','job_title'],title:r=>[r.first_name,r.last_name].filter(Boolean).join(' ')||r.email,subtitle:r=>[r.job_title,r.email,r.phone]},
 {key:'suppliers',module:'suppliers',table:'suppliers',select:'id,name,tax_id,contact_name,email,phone,city,active',fields:['name','tax_id','contact_name','email','phone'],title:r=>r.name,subtitle:r=>[r.tax_id,r.contact_name,r.city]},
 {key:'products',module:'products',table:'products',select:'id,name,reference,barcode,category,brand,active',fields:['name','reference','barcode','category','brand'],title:r=>r.name,subtitle:r=>[r.reference,r.barcode,r.category]},
 {key:'quotes',module:'quotes',table:'invoices',select:'id,invoice_number,quote_state,quote_details->>client,quote_valid_until,quote_sent_at,total',fields:['invoice_number','quote_details->>client'],title:r=>r.invoice_number,subtitle:r=>[r.client,r.quote_state],number:'invoice_number'},
 {key:'orders',module:'sales-orders',table:'sales_orders',select:'id,number,customer_name,customer_identification,status',fields:['number','customer_name','customer_identification'],title:r=>r.number,subtitle:r=>[r.customer_name,r.status],number:'number'},
 {key:'shipments',module:'sales-orders',table:'sales_deliveries',select:'id,number,order_id,tms_delivery_id,dispatched_at,order:sales_orders!inner(customer_name)',fields:['number'],related:'order',title:r=>r.number,subtitle:r=>[r.order?.customer_name,r.dispatched_at?.slice(0,10)],number:'number'},
 {key:'deliveries',module:'tms',table:'tms_deliveries',select:'id,customer,address,delivery_date,status',fields:['customer','address'],title:r=>r.dossier_reference||r.customer,subtitle:r=>[r.customer,r.delivery_date,r.status]},
 {key:'invoices',module:'quotes',table:'external_invoices',select:'id,number,external_number,order_id,total,fiscal_status,document_kind,issue_date,order:sales_orders!inner(customer_name)',fields:['number','external_number'],related:'order',title:r=>r.number,subtitle:r=>[r.order?.customer_name,r.external_number,r.issue_date,r.fiscal_status],number:'number'},
 {key:'payments',module:'payments',table:'external_invoice_payments',select:'id,invoice_id,reference,account,paid_at,amount,method,status,invoice:external_invoices!inner(order:sales_orders!inner(customer_name))',fields:['reference','account'],related:'invoice.order',title:r=>r.dossier_reference||r.reference||r.paid_at,subtitle:r=>[r.invoice?.order?.customer_name,r.reference,r.paid_at,r.method]},
 {key:'expenses',module:'accounting',table:'expenses',select:'id,reference,description,expense_date,amount_total,status,supplier:suppliers(name)',fields:['reference','description'],title:r=>r.reference,subtitle:r=>[r.description,r.supplier?.name,r.expense_date,r.status],number:'reference'},
 {key:'supplier_invoices',module:'accounting',table:'supplier_invoices',select:'id,number,issue_date,due_date,total,status,supplier:suppliers!inner(name)',fields:['number'],related:'supplier',title:r=>r.number,subtitle:r=>[r.supplier?.name,r.issue_date,r.status],number:'number'},
 {key:'bank_transactions',module:'accounting',table:'bank_transactions',select:'id,value_date,reference,description,amount,status',fields:['reference','description'],title:r=>r.reference||r.description,subtitle:r=>[r.description,r.value_date,r.status]},
 {key:'entries',module:'accounting',table:'accounting_entries',select:'id,number,entry_date,reference,memo,status',fields:['number','reference','memo'],title:r=>r.number,subtitle:r=>[r.memo,r.reference,r.entry_date,r.status],number:'number'},
 {key:'vehicles',module:'fleet',table:'fleet_vehicles',select:'id,reference,plate,brand,model,kind,status,odometer,active',fields:['plate','brand','model','reference'],title:r=>r.plate,subtitle:r=>[r.brand,r.model,r.reference,r.status],number:'reference'},
 {key:'fleet_drivers',module:'fleet',table:'fleet_drivers',select:'id,name,phone,licence_number,licence_expiry,active',fields:['name','phone','licence_number'],title:r=>r.name,subtitle:r=>[r.phone,r.licence_number,r.licence_expiry]},
 {key:'knowledge',module:'knowledge',table:'knowledge_articles',select:'id,title,slug,body,updated_at',fields:['title','slug','body'],title:r=>r.title,subtitle:r=>[r.slug]}
];
function sources(profile,allowed){
 const role=roles[profile?.role]||profile?.role;
 const list=SOURCES.map(s=>s.key==='products'&&role==='client'?{...s,module:'client-catalog'}:s.key==='deliveries'&&!access(profile,'tms',allowed)&&access(profile,'sales-orders',allowed)?{...s,module:'sales-orders'}:s).filter(s=>access(profile,s.module,allowed)&&(s.key!=='invoices'||['admin','commercial'].includes(role)));
 if(access(profile,'client-deliveries',allowed)&&role==='client')list.push({key:'deliveries',module:'client-deliveries',table:'tms_deliveries',portal:true,fields:['shipment_number','customer','address','order_number'],title:r=>r.shipment_number||r.customer,subtitle:r=>[r.customer,r.order_number,r.date,r.status]});
 return list;
}
const tokens=text=>normalize(text).split(/\s+/).filter(Boolean).slice(0,8);
// Quoted PostgREST values: no query syntax or LIKE wildcards from user input.
const pattern=word=>'"%'+normalize(word).replace(/[\\%_*]/g,c=>'\\'+c).replace(/[aeioucn]/g,'_').replace(/"/g,'\\"')+'%"';
function applyText(q,fields,text,ids=[]){
 const parts=tokens(text).map(w=>'or('+fields.map(f=>f+'.ilike.'+pattern(w)).join(',')+')');
 if(parts.length){let expression='and('+parts.join(',')+')';if(ids.length)expression+=',id.in.('+ids.join(',')+')';q=q.or(expression)}else if(ids.length)q=q.in('id',ids);
 return q;
}
function matches(row,s,text,ref){if(ref){if(sameReference(s.title(row),ref.raw||'')||sameReference(row.original_number,ref.raw||''))return true;return [row.dossier_reference,row.number,row.invoice_number,row.reference].some(v=>{const r=reference(v);return r&&r.prefix===ref.prefix&&r.number===ref.number&&r.ordinal===ref.ordinal})}
 const hay=normalize([s.title(row),...(s.subtitle(row)||[]),...s.fields.map(f=>row[f.includes('->>')?f.split('->>')[1]:f])].join(' '));return tokens(text).every(w=>hay.includes(w));}
function rank(r,s,p){const title=normalize(s.title(r)),q=normalize(p.raw);return (p.ref&&matches(r,s,p.text,p.ref)?100:0)+(title===q||[r.barcode,r.reference,r.original_number].some(v=>normalize(v)===q)?80:0)+(title.startsWith(q)?20:0)+(r.active===false?-5:0);}
const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
async function result(query,signal){if(signal)query=query.abortSignal(signal);const r=await query;if(r.error)throw r.error;return r.data||[];}
async function attach(client,table,rows,signal){
 if(!rows.length||!['invoices','sales_orders','sales_deliveries','tms_deliveries','external_invoices','external_invoice_payments'].includes(table))return rows;
 const refs=await result(client.from('gama_document_references').select('document_id,document_reference').eq('table_name',table).in('document_id',rows.map(r=>r.id)),signal);
 return rows.map(r=>{const ref=refs.find(x=>x.document_id===r.id);if(!ref)return r;const field=table==='invoices'?'invoice_number':'number';return {...r,original_number:r[field],dossier_reference:ref.document_reference,...(['invoices','sales_orders','sales_deliveries','external_invoices'].includes(table)?{[field]:ref.document_reference}:{})}});
}
function item(s,row,p){return {key:s.key+':'+row.id,source:s.key,module:s.module,table:s.table,id:row.id,title:s.title(row)||'—',subtitle:s.subtitle(row).filter(Boolean).join(' · '),archived:row.active===false,score:rank(row,s,p),orderId:row.order_id,deliveryId:row.tms_delivery_id,invoiceId:row.invoice_id,total:row.total??row.amount,balance:row.balance};}
async function textPage(s,p,ctx,offset){
 const {client,signal}=ctx;let ids=[];
 if(s.portal){const rows=await result(client.rpc('gama_client_deliveries',{p_id:null,p_offset:offset}),signal);return {items:rows.slice(0,20).filter(r=>p.ref?sameReference(r.shipment_number,p.raw):matches(r,s,p.text)).filter(r=>p.intent!=='shipments_late'||(r.date&&r.date<today()&&!['Entregada','Cancelada'].includes(r.status))).map(r=>item(s,r,p)),more:rows.length>20,next:offset+20};}
 if(p.ref&&p.ref.table===s.table){
  const refs=await result(client.from('gama_document_references').select('document_id,document_reference').eq('table_name',s.table).eq('dossier_number',p.ref.number).order('document_id').range(offset,offset+PAGE-1),signal);
  ids=refs.filter(r=>{const ref=reference(r.document_reference);return ref?.ordinal===p.ref.ordinal}).map(r=>r.document_id);
 }
 let q=client.from(s.table).select(s.select);q=applyText(q,s.fields,p.ref?String(p.ref.number):p.text,ids);
 const relatedQuery=()=>{let linked=client.from(s.table).select(s.select);for(const word of tokens(p.text))linked=linked.or('customer_name.ilike.'+pattern(word),{referencedTable:s.related});return linked.order('id').range(offset,offset+PAGE-1)};
 const [raw,related]=await Promise.all([result(q.order('id').range(offset,offset+PAGE-1),signal),s.related&&!p.ref?result(relatedQuery(),signal):Promise.resolve([])]);
 // Pin exact identifiers before the page of partial matches, even in large catalogues.
 let exact=[];if(offset===0){
  if(ids.length)exact=await result(client.from(s.table).select(s.select).in('id',ids),signal);
  else if(!p.ref){const fields=s.fields.filter(f=>!f.includes('->')&&!['body','account'].includes(f));const quoted='"'+p.raw.replace(/\\/g,'\\\\').replace(/"/g,'\\"')+'"';exact=await result(client.from(s.table).select(s.select).or(fields.map(f=>f+'.eq.'+quoted).join(',')).order('id').limit(PAGE),signal);}
 }
 const rows=await attach(client,s.table,[...new Map([...exact,...raw,...related].map(r=>[r.id,r])).values()],signal);
 return {items:rows.filter(r=>matches(r,s,p.text,p.ref)).map(r=>item(s,r,p)),more:raw.length===PAGE||related.length===PAGE,next:offset+PAGE};
}
async function overdueOrders(p,ctx,offset){
 const {client,signal}=ctx,day=today(),s=SOURCES.find(s=>s.key==='orders');
 const [lines,deliveries]=await Promise.all([
  result(client.from('sales_order_lines').select('id,order_id,quantity,promised_date,order:sales_orders!inner(id,number,customer_name,status),sales_delivery_lines(quantity)').lt('promised_date',day).eq('order.status','confirmed').order('id').range(offset,offset+PAGE-1),signal),
  result(client.from('sales_deliveries').select('id,order:sales_orders!inner(id,number,customer_name,status),delivery:tms_deliveries!inner(delivery_date,status)').lt('delivery.delivery_date',day).not('delivery.status','in','("Entregada","Cancelada")').eq('order.status','confirmed').order('id').range(offset,offset+PAGE-1),signal)
 ]);
 const candidates=[...lines.filter(l=>Number(l.quantity)>(l.sales_delivery_lines||[]).reduce((n,d)=>n+Number(d.quantity),0)).map(l=>l.order),...deliveries.map(d=>d.order)].filter(Boolean);
 const rows=await attach(client,s.table,[...new Map(candidates.map(r=>[r.id,r])).values()],signal);
 return {items:rows.filter(r=>matches(r,s,p.text)).map(r=>item(s,r,p)),more:lines.length===PAGE||deliveries.length===PAGE,next:offset+PAGE};
}
async function financial(p,ctx,offset){
 const status={invoices_unpaid:'open',invoices_overdue:'overdue',invoices_paid:'paid'}[p.intent];
 // The existing ledger excludes cancelled payments and computes the true balance.
 const data=await result(ctx.client.rpc('gama_payment_action',{p_action:'list',p_data:{status,offset,search:''}}),ctx.signal);
 const s={...SOURCES.find(s=>s.key==='invoices'),module:'payments',subtitle:r=>[r.customer_name,r.payment_status,r.due_date]};
 return {items:(data.rows||[]).filter(r=>tokens(p.text).every(w=>normalize([r.number,r.external_number,r.customer_name].join(' ')).includes(w))).map(r=>item(s,r,p)),more:offset+(data.rows||[]).length<data.total,next:offset+30};
}
async function semanticPage(s,p,ctx,offset){
 if(s.portal)return textPage(s,p,ctx,offset);
 if(p.intent.startsWith('invoices_'))return financial(p,ctx,offset);
 if(p.intent==='orders_late')return overdueOrders(p,ctx,offset);
 let q=ctx.client.from(s.table).select(s.select);
 if(p.intent==='shipments_late')q=q.lt('delivery_date',today()).not('status','in','("Entregada","Cancelada")');
 if(p.intent==='quotes_unanswered')q=q.eq('quote_state','sent').lt('quote_sent_at',new Date(Date.now()-7*86400000).toISOString());
 q=applyText(q,s.fields,p.text);const raw=await result(q.order('id').range(offset,offset+PAGE-1),ctx.signal),rows=await attach(ctx.client,s.table,raw,ctx.signal);
 return {items:rows.filter(r=>matches(r,s,p.text)).map(r=>item(s,r,p)),more:raw.length===PAGE,next:offset+PAGE};
}
function selectedSources(p,ctx){
 let list=sources(ctx.profile,ctx.allowed);
 if(p.ref)list=list.filter(s=>s.table===p.ref.table||(s.portal&&p.ref.prefix==='ENV'));
 if(p.intent){
  if(p.intent.startsWith('invoices_'))return access(ctx.profile,'payments',ctx.allowed)?[SOURCES.find(s=>s.key==='invoices')]:[];
  list=list.filter(s=>s.key===({orders_late:'orders',shipments_late:'deliveries',quotes_unanswered:'quotes'}[p.intent]));
 }
 return list;
}
async function search(value,ctx){
 const p=parse(value);if(p.raw.length<2)return {parsed:p,groups:[]};
 const selected=selectedSources(p,ctx).filter(s=>!ctx.only||s.key===ctx.only);
 const groups=await Promise.all(selected.map(async s=>{try{return {source:s.key,...await (p.intent?semanticPage(s,p,ctx,ctx.offset||0):textPage(s,p,ctx,ctx.offset||0))}}catch(error){if(ctx.signal?.aborted)throw error;return {source:s.key,items:[],error:true,more:false}}}));
 return {parsed:p,groups};
}
return {normalize,parse,reference,sameReference,access,sources,selectedSources,search,PAGE,applyText};
});
