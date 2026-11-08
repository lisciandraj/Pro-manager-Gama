/* Optional invoice actions load when the invoice dialog is opened. */
(function(){'use strict';
let epoch=0;const attached=new WeakMap(),L=(es,fr,en)=>({es,fr,en}[window.GamaI18n?.language||'es']||es);
function text(i){const s=i.document_snapshot,d=s.details||{};return ['FACTURA INTERNA '+i.number,'Sin validez fiscal',...(i.invoice_origin==='direct'?[L('Factura de cliente sin pedido','Facture client sans commande','Customer invoice without an order')]:['Presupuesto: '+(s.quote_number||'Pedido directo'),'Pedido: '+(s.order_number||'—')]),'Cliente: '+s.customer,'Identificación: '+s.customer_identification,'Dirección: '+(d.clientAddress||''),'Email: '+(d.clientEmail||''),'Fecha: '+i.issue_date,'Vencimiento: '+(i.due_date||''),'Producto\tReferencia\tCantidad\tPrecio lista\tDescuento %\tPrecio neto\tIVA %\tSubtotal\tIVA',...s.lines.map(l=>[l.name,l.reference,l.qty,l.listPrice??l.price,l.discount||0,l.price,l.taxRate,l.subtotal,l.tax].join('\t')),'Subtotal: '+i.subtotal,'IVA: '+i.tax,'TOTAL USD: '+i.total,'Pago: '+(d.payment||''),'Condiciones: '+(d.terms||''),...(d.customer_comment?['Comentario del cliente: '+d.customer_comment]:[])].join('\n')}
const owner=()=>{try{const s=JSON.parse(localStorage.getItem('gama_session_v1')||'{}');return [s.userId||s.id||s.email||s.username||s.name||'',s.role||''].join(':')}catch{return ''}};
window.addEventListener('gama:auth-change',event=>{if(event.detail?.event==='TOKEN_REFRESHED')return;epoch++;document.querySelectorAll('[data-coco-invoice-tool]').forEach(button=>button.remove())});
function attach(invoice,dialog,onDone){
 if(!dialog?.isConnected||attached.has(dialog))return;
 const state={epoch,owner:owner(),active:true};attached.set(dialog,state);
 const valid=()=>state.active&&dialog.isConnected&&state.epoch===epoch&&state.owner===owner();
 dialog.addEventListener('close',()=>{state.active=false},{once:true});
 const error=e=>{if(valid()){const node=dialog.querySelector('#gsFormError');if(node)node.textContent=e.message||String(e)}};
 const bind=(id,run)=>{const node=dialog.querySelector('#'+id);if(!node)return;node.dataset.cocoInvoiceTool='';node.disabled=false;node.onclick=async()=>{if(!valid())return;node.disabled=true;try{await run()}catch(e){error(e)}finally{if(valid())node.disabled=false}}};
 const data=dialog.querySelector('#giText');if(data)data.value=text(invoice);
 bind('giLink',async()=>{await window.GamaInternalInvoices.link(invoice.id,onDone);if(valid())dialog.remove()});
 bind('giPdf',()=>window.GamaInternalInvoices.pdf(invoice));
 bind('giCopy',async()=>{try{await navigator.clipboard.writeText(data.value);if(valid())dialog.querySelector('#giCopyStatus').textContent='Datos copiados.'}catch(_){if(valid()){data.focus();data.select();dialog.querySelector('#giCopyStatus').textContent='Selecciona y copia el texto.'}}});
 const button=(id,label,permission,asset,run,onError=error)=>{
  if(!window.gamaAccessAllowed?.(permission))return;
  const node=document.createElement('button');node.type='button';node.id=id;node.className='arcButton secondary';node.textContent=label;node.dataset.cocoInvoiceTool='';
  node.onclick=async()=>{if(!valid()||!window.gamaAccessAllowed?.(permission))return;node.disabled=true;try{if(asset)await window.ArcLoadScript(asset);if(valid()&&window.gamaAccessAllowed?.(permission))await run()}catch(e){onError(e)}finally{if(valid())node.disabled=false}};
  dialog.querySelector('.gsActions')?.append(node);return node;
 };
 if(window.gamaAccessAllowed?.('accounting')&&window.gamaAccessAllowed?.('sri')){
  const sri=button('giSri',window.GamaI18n?.t('Facturación SRI')||'Facturación SRI','accounting',null,()=>{if(window.gamaAccessAllowed?.('sri')){dialog.remove();window.GamaAccounting?.openSri(invoice.id)}});if(sri)sri.className='arcButton primary';
 }
 button('giDeferrals',window.GamaI18n?.t('Diferidos de facturas')||'Diferidos de facturas','accounting','coco-accounting-invoice-deferrals.js',async()=>{dialog.close();await window.CocoInvoiceDeferrals.showPlans('customer',invoice.id)},e=>{if(state.epoch===epoch&&state.owner===owner())window.gamaToast?.(e.message)});
 if(invoice.fiscal_status==='cancelled')return;
 button('giRewards',window.GamaI18n?.t('Usar saldo regalo')||'Usar saldo regalo','payments','coco-sales-rewards.js',()=>window.CocoSalesRewards.invoice(invoice.id,async()=>{if(!valid())return;dialog.close();await window.GamaInternalInvoices.view(invoice.id,onDone)}));
 const lang=window.GamaI18n?.language;
 button('giPaymentLink',lang==='fr'?'Lien de paiement':lang==='en'?'Payment link':'Enlace de pago','accounting','coco-invoice-checkout.js',()=>window.CocoInvoiceCheckout.open(invoice));
}
window.CocoInvoiceTools=Object.freeze({attach});
})();
