/* Canonical dossier references; original/fiscal numbers remain in storage. */
(function(){'use strict';
const types=new Set(['customer_requests','invoices','sales_orders','fulfillment_preparations','fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices','external_invoice_payments','customer_returns']);
async function attach(table,result,client){
 if(result.error||!result.data||!types.has(table))return result;
 const rows=Array.isArray(result.data)?result.data:[result.data],key=table==='tms_proofs'?'delivery_id':'id',ids=rows.map(r=>r[key]).filter(Boolean);
 if(!ids.length)return result;
 const refs=[];
 for(let offset=0;offset<ids.length;offset+=100){const r=await client.from('gama_document_references').select('table_name,document_id,dossier_number,document_reference').eq('table_name',table).in('document_id',ids.slice(offset,offset+100));if(r.error)return {...result,data:null,error:r.error};refs.push(...r.data);}
 const parents=[...new Set(rows.flatMap(r=>[r.order_id,r.source_quote_id,r.source_request_id]).filter(Boolean))];
 for(let offset=0;offset<parents.length;offset+=100){const r=await client.from('gama_document_references').select('table_name,document_id,dossier_number,document_reference').in('document_id',parents.slice(offset,offset+100));if(r.error)return {...result,data:null,error:r.error};refs.push(...r.data);}
 const get=(t,id)=>refs.find(r=>r.table_name===t&&r.document_id===id);
 for(const r of rows){const ref=get(table,r[key]);if(!ref)continue;r.dossier_number=ref.dossier_number;r.dossier_reference=ref.document_reference;
  r.dossier_label='EXP-'+String(ref.dossier_number).padStart(8,'0');
  if(table==='invoices'){r.original_number=r.invoice_number;r.invoice_number=ref.document_reference;}
  else if(['sales_orders','sales_deliveries','fulfillment_preparations','customer_returns','external_invoices'].includes(table)){
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
window.GamaReferences={attach,types};
})();
