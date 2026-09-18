/* One workbook per export, one sheet per business module. Reads use the signed-in
   user's Supabase client: no service key, privileged RPC or local cache fallback. */
(function(){'use strict';
const groups=[
 ['Produits','Productos','Products',['products']],
 ['Clients','Clientes','Customers',['customers']],
 ['Fournisseurs','Proveedores','Suppliers',['suppliers']],
 ['Tarifs','Tarifas','Prices',['customer_special_prices','commercial_matrix']],
 ['Devis et facture','Presupuestos y facturas','Quotes and invoices',['invoices','invoice_lines','quote_events','external_invoices','external_invoice_lines','external_invoice_deliveries','external_invoice_files']],
 ['Demandes clients','Solicitudes de clientes','Customer requests',['customer_requests','customer_request_lines','favorite_orders','favorite_order_lines']],
 ['CRM','CRM','CRM',[]],
 ['Commandes clients','Pedidos de venta','Sales orders',['sales_orders','sales_order_lines','sales_reservation_links','sales_fulfillment_options','sales_events']],
 ['Préparation','Preparación','Picking',[]],
 ['Livraisons','Entregas','Deliveries',['sales_deliveries','sales_delivery_lines']],
 ['Paiements','Pagos','Payments',['external_invoice_payments']],
 ['Achats','Compras','Purchases',['purchase_orders','purchase_order_lines','reorder_rules']],
 ['Stock et inventaire','Stock e inventario','Stock and inventory',[]],
 ['Entrepôts','Almacenes','Warehouses',['warehouses','warehouse_locations']],
 ['TMS','TMS','TMS',[]],
 ['Retours','Devoluciones','Returns',[]],
 ['RH','RRHH','HR',[]],
 ['Knowledge','Knowledge','Knowledge',['knowledge_articles']],
 ['Audit','Auditoría','Audit',['gama_audit']],
 ['Configuration','Configuración','Configuration',['app_modules','profiles','gama_document_references','company_settings']],
 ['Facturation SRI','Facturación SRI','SRI invoicing',[]],
 ['Projets','Proyectos','Projects',['pm_projects','pm_items','pm_members','pm_templates','pm_comments','pm_files','pm_links']],
 ['Comptabilité','Contabilidad','Accounting',['accounting_accounts','accounting_journals','accounting_entries','accounting_entry_lines','accounting_periods','accounting_permissions','accounting_taxes','financial_accounts','bank_transactions','reconciliations','expenses','expense_categories','expense_receipts','supplier_invoices','supplier_invoice_payments']],
 ['Flotte','Flota','Fleet',[]]
];
const prefixes={crm_:6,fulfillment_:8,stock_:12,inventory_:12,tms_:14,customer_return:15,hr_:16,sri_:20,fleet_:23};
function group(t){const i=groups.findIndex(g=>g[3].includes(t));if(i>=0)return i;for(const [p,n]of Object.entries(prefixes))if(t.startsWith(p))return n;throw Error('Unmapped export table: '+t)}
const lang=()=>window.GamaI18n?.language||document.documentElement.lang||'es';
const tr=(fr,es,en)=>({fr,es,en}[lang()]||es);
let busy=false,loading;
function loadXLSX(){if(window.XLSX)return Promise.resolve();if(loading)return loading;loading=new Promise((resolve,reject)=>{const s=document.createElement('script');s.src='https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js';s.integrity='sha384-vtjasyidUo0kW94K5MXDXntzOJpQgBKXmE7e2Ga4LG0skTTLeBi97eFAXsqewJjw';s.crossOrigin='anonymous';s.onload=()=>window.XLSX?resolve():reject(Error('Excel unavailable'));s.onerror=()=>{s.remove();loading=null;reject(Error('Excel unavailable'))};document.head.appendChild(s)});return loading}
async function readTable(client,spec){const rows=[];for(let offset=0;;){let q=client.from(spec.table).select(spec.columns.join(','));for(const key of spec.pk)q=q.order(key,{ascending:true});const r=await q.range(offset,offset+499);if(r.error)throw Object.assign(Error(spec.table+': '+r.error.message),{code:r.error.code});if(!Array.isArray(r.data))throw Error(spec.table+': invalid response');if(!r.data.length)return rows;rows.push(...r.data);offset+=r.data.length;if(offset>1000000)throw Error(spec.table+': Excel row limit');}}
function textValue(v){if(v===null||v===undefined)return '';if(typeof v==='object')return JSON.stringify(v,(k,x)=>typeof x==='string'&&/^data:[^,]*;base64,/i.test(x)?'[binary attachment]':x);return v}
// Excel limits a cell to 32767 characters. Preserve long articles and JSON in
// numbered continuation columns instead of truncating them or failing writeFile.
function block(spec,records){const values=records.map(r=>spec.columns.map(c=>textValue(r[c]))),widths=spec.columns.map((_,i)=>values.reduce((n,r)=>Math.max(n,typeof r[i]==='string'?Math.ceil(r[i].length/32000):1),1));
 const header=spec.columns.flatMap((c,i)=>Array.from({length:widths[i]},(_,j)=>j?c+' ['+(j+1)+']':c));
 if(header.length>16384)throw Error(spec.table+': Excel column limit');
 return [[spec.table],[...header],...values.map(row=>row.flatMap((v,i)=>Array.from({length:widths[i]},(_,j)=>typeof v==='string'?v.slice(j*32000,(j+1)*32000):j?'':v))),[]];}
function status(message){for(const button of document.querySelectorAll('[onclick="exportExcel()"]')){let el=button.parentElement.querySelector('[data-export-status]');if(!el){el=document.createElement('p');el.dataset.exportStatus='';el.setAttribute('role','status');button.parentElement.appendChild(el)}el.textContent=message}}
async function run(){if(busy)return;busy=true;const buttons=[...document.querySelectorAll('[onclick="exportExcel()"]')];buttons.forEach(b=>b.disabled=true);
 try{status(tr('Préparation de l’export…','Preparando exportación…','Preparing export…'));const p=await window.GamaCloud.getProfile();if(p.error)throw p.error;if(!p.data||p.data.active===false||!['administrador','comercial','almacenero'].includes(p.data.role))throw Error(tr('Accès refusé.','Acceso denegado.','Access denied.'));
 await loadXLSX();const client=await GamaCloud.db(),sheets=groups.map(()=>[]),summary=[[tr('Export GAMA ERP','Exportación GAMA ERP','GAMA ERP export'),new Date().toISOString()],[tr('Périmètre','Alcance','Scope'),tr('Données accessibles au compte connecté. Photos et fichiers binaires exclus. Textes longs répartis en colonnes numérotées.','Datos accesibles a la cuenta conectada. Sin fotos ni archivos binarios. Textos largos en columnas numeradas.','Data accessible to the signed-in account. No photos or binary files. Long text continues in numbered columns.')],[],['Module','Table','Rows','Status']];let denied=0;
 for(const [i,spec] of window.GamaExportSchema.entries()){const n=group(spec.table),name=groups[n][{fr:0,es:1,en:2}[lang()]??1];status(tr('Lecture','Lectura','Reading')+' '+(i+1)+'/'+GamaExportSchema.length+' — '+name);try{const rows=await readTable(client,spec);for(const row of block(spec,rows))sheets[n].push(row);summary.push([name,spec.table,rows.length,'OK']);}catch(e){if(e.code==='42501'){denied++;summary.push([name,spec.table,'',tr('Accès refusé','Acceso denegado','Access denied')]);}else throw e;}}
 const wb=XLSX.utils.book_new();function append(rows,name){if(rows.length>1048576)throw Error(name+': Excel row limit');const ws=XLSX.utils.aoa_to_sheet(rows);ws['!cols']=Array.from({length:rows.reduce((n,r)=>Math.max(n,r.length),1)},()=>({wch:24}));XLSX.utils.book_append_sheet(wb,ws,name)}
 append(summary,tr('Sommaire','Resumen','Summary'));sheets.forEach((rows,i)=>{if(rows.length)append(rows,groups[i][{fr:0,es:1,en:2}[lang()]??1])});
 XLSX.writeFile(wb,'GAMA_export_'+new Date().toISOString().replace(/[:.]/g,'-')+'.xlsx',{compression:true});status(denied?tr('Export terminé. Consultez le sommaire pour les accès refusés.','Exportación terminada. Consulte los accesos denegados en el resumen.','Export complete. See summary for denied access.'):tr('Export Excel terminé.','Exportación Excel terminada.','Excel export complete.'));
 }catch(e){console.error('[GAMA export]',e);status(tr('Export interrompu : aucun fichier incomplet téléchargé. ','Exportación interrumpida: no se descargó ningún archivo incompleto. ','Export stopped: no incomplete file downloaded. ')+(e.message||e));}finally{busy=false;buttons.forEach(b=>b.disabled=false)}}
window.GamaExcelExport={run,readTable,block,group,loadXLSX};
})();
