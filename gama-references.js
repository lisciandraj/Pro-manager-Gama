/* Canonical dossier references; original/fiscal numbers remain in storage. */
(function(){'use strict';
const types=new Set(["customer_requests", "invoices", "sales_orders", "fulfillment_preparations", "fulfillment_packages", "sales_deliveries", "tms_deliveries", "tms_proofs", "external_invoices", "external_invoice_payments", "return_orders", "purchase_orders", "inventory_counts", "stock_reservations", "stock_movements", "crm_opportunities", "pm_projects", "fleet_vehicles", "hr_documents", "hr_payroll", "service_tickets", "business_documents", "accounting_entries", "expenses", "supplier_invoices", "supplier_invoice_payments", "return_credits", "return_refunds", "tms_routes", "knowledge_articles", "pm_items"]);
const dossierTypes=new Set(['customer_requests','invoices','sales_orders','fulfillment_preparations','fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices','external_invoice_payments','return_orders']);
async function attach(table,result,client){
 if(result.error||!result.data||!types.has(table))return result;
 const rows=Array.isArray(result.data)?result.data:[result.data],key=table==='tms_proofs'?'delivery_id':'id',ids=rows.map(r=>r[key]).filter(Boolean);
 if(!ids.length)return result;
 const refs=new Map(),groups=new Map(),jobs=[];
 const refKey=(t,id)=>t+':'+id,get=(t,id)=>refs.get(refKey(t,id));
 const need=(t,id)=>{if(!id)return;if(!groups.has(t))groups.set(t,new Set());groups.get(t).add(id)};
 for(const r of rows){
  // Independent documents already carry their canonical number. Only the
  // sales chain needs the registry's shared dossier metadata.
  if(!dossierTypes.has(table)&&r.erp_reference)refs.set(refKey(table,r[key]),{document_reference:r.erp_reference,dossier_number:0,dossier_label:null,legacy_reference:r.legacy_reference});
  else need(table,r[key]);
  need('invoices',r.source_quote_id);need('customer_requests',r.source_request_id);
  if(r.document_snapshot)need('sales_orders',r.order_id);
 }
 for(const [t,set] of groups){const keys=[...set];for(let offset=0;offset<keys.length;offset+=100)jobs.push({table:t,ids:keys.slice(offset,offset+100)})}
 // Independent own/parent reads share a bounded wave, not a serial waterfall.
 for(let offset=0;offset<jobs.length;offset+=4){
  const results=await Promise.all(jobs.slice(offset,offset+4).map(job=>client.from('gama_document_references').select('table_name,document_id,dossier_number,document_reference,dossier_label,legacy_reference').eq('table_name',job.table).in('document_id',job.ids)));
  for(const r of results){if(r.error)return {...result,data:null,error:r.error};for(const ref of r.data||[])refs.set(refKey(ref.table_name,ref.document_id),ref)}
 }
 for(const r of rows){const ref=get(table,r[key]);if(!ref)continue;r.dossier_number=ref.dossier_number;r.dossier_reference=ref.document_reference;
  r.erp_reference=ref.document_reference;r.legacy_reference=ref.legacy_reference;r.dossier_label=ref.dossier_label||(ref.dossier_number>0?'EXP-'+String(ref.dossier_number).padStart(8,'0'):null);
  if(table==='invoices'){r.original_number=r.invoice_number;r.invoice_number=ref.document_reference;}
  else if(['sales_orders','sales_deliveries','fulfillment_preparations','return_orders','external_invoices'].includes(table)){
   r.original_number=r.number;
   if(table==='external_invoices'&&r.document_kind==='external')r.external_number=r.number;
   r.number=ref.document_reference;
  }
  if(r.document_snapshot)r.document_snapshot={...r.document_snapshot,quote_number:get('invoices',r.source_quote_id)?.document_reference||r.document_snapshot.quote_number,order_number:get('sales_orders',r.order_id)?.document_reference||r.document_snapshot.order_number};
  r.source_quote_reference=get('invoices',r.source_quote_id)?.document_reference;
  r.source_request_reference=get('customer_requests',r.source_request_id)?.document_reference;
 }
 return result;
}
const tx=s=>window.GamaI18n?.t(s)||s;
async function mountConfig(host){if(!host)return;const U=window.ArcUI,E=U.esc;let formats=[],busy=false;
 const error=e=>tx(String(e?.message).includes('STALE')?'Otro administrador cambió los prefijos. Actualiza antes de guardar.':String(e?.message).includes('PREFIX_USED')?'Este prefijo ya pertenece a otro tipo de documento.':String(e?.message).includes('ADMIN_REQUIRED')?'Solo un administrador puede modificar los prefijos.':String(e?.message).includes('INVALID')?'Usa exactamente tres letras de A a Z, sin repetir prefijos.':'No se pudieron guardar los prefijos. Tus cambios se conservan.');
 const render=()=>{if(!host.isConnected)return;U.render(host,`<div class="arcPanel card"><h3>${E(tx('Referencias de documentos'))}</h3><p>${E(tx('Tres letras, un guion y ocho cifras. Los prefijos se basan en los nombres españoles de los documentos.'))}</p><p class="sdMuted">${E(tx('Los cambios se aplican a las nuevas referencias. Las ya emitidas conservan su número.'))}</p><form id="cfgReferenceForm">${U.table({columns:[{label:'Tipo de documento',html:r=>`<strong>${E(tx(r.label_es))}</strong>`},{label:'Módulo',value:r=>tx(window.ArcModules?.registry.find(m=>m.id===r.module_id)?.label||r.module_id)},{label:'Prefijo',html:r=>`<input aria-label="${E(tx('Prefijo')+' — '+tx(r.label_es))}" data-ref-kind="${E(r.kind)}" value="${E(r.prefix)}" required pattern="[A-Za-z]{3}" minlength="3" maxlength="3" autocomplete="off" autocapitalize="characters" style="max-width:7rem;text-transform:uppercase">`},{label:'Ejemplo',html:r=>`<code data-ref-preview="${E(r.kind)}">${E(r.prefix)}-00000001</code>`}],items:formats})}<div class="arcToolbar">${U.button({label:tx('Guardar prefijos'),type:'submit',variant:'primary'})}${U.button({label:tx('Actualizar'),attrs:'data-ref-reload'})}</div><p role="status" id="cfgReferenceStatus"></p></form></div>`);
 host.querySelectorAll('[data-ref-kind]').forEach(input=>input.oninput=()=>{input.value=input.value.toUpperCase();host.querySelector('[data-ref-preview="'+input.dataset.refKind+'"]').textContent=input.value+'-00000001'});
 host.querySelector('[data-ref-reload]').onclick=()=>load();host.querySelector('form').onsubmit=async event=>{event.preventDefault();if(busy)return;const changes=[...host.querySelectorAll('[data-ref-kind]')].map(input=>{const row=formats.find(r=>r.kind===input.dataset.refKind);return {...row,prefix:input.value.trim().toUpperCase()}}).filter(row=>row.prefix!==formats.find(r=>r.kind===row.kind).prefix).map(({kind,prefix,version})=>({kind,prefix,version}));if(!changes.length)return;busy=true;host.querySelectorAll('input,button').forEach(el=>el.disabled=true);
 try{const c=await window.GamaCloud.db(),res=await c.rpc('gama_save_reference_formats',{p_changes:changes});if(res.error)throw res.error;formats=res.data;render();host.querySelector('#cfgReferenceStatus').textContent=tx('Prefijos guardados.')}catch(e){host.querySelector('#cfgReferenceStatus').textContent=error(e)}finally{busy=false;host.querySelectorAll('input,button').forEach(el=>el.disabled=false)}};
 };
 async function load(){try{await window.GamaCloudReady;const c=await window.GamaCloud.db(),res=await c.from('erp_reference_formats').select('*').order('module_id').order('label_es');if(res.error)throw res.error;formats=res.data||[];render()}catch(e){if(host.isConnected){host.textContent=tx('No se pudieron cargar los prefijos.');const b=document.createElement('button');b.className='arcButton';b.textContent=tx('Reintentar');b.onclick=load;host.appendChild(b)}}}
 await load();
}
window.GamaReferences={attach,types,mountConfig};
})();
