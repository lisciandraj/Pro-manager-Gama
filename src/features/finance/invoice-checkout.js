/* Staff invoice payment links; tokens stay only in this dialog. */
(function(){'use strict';
const U=window.ArcUI,E=U.esc,L=(es,fr,en)=>({es,fr,en}[window.GamaI18n?.language||'es']||es),owned=new Set();let epoch=0;
const rpc=(action,data)=>window.ArcData.rpc('coco_sales_checkout',{p_action:action,p_data:data});
const hash=async blob=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await blob.arrayBuffer())),n=>n.toString(16).padStart(2,'0')).join('');
const stamp=d=>new Date(d).toLocaleString(window.GamaI18n?.language||'es');
function error(e){const s=String(e?.message||e);return /CHANGED|POSTED_INVOICE_REQUIRED/.test(s)?L('La factura o su saldo cambiaron. Actualiza antes de crear el enlace.','La facture ou son solde ont changé. Actualisez avant de créer le lien.','The invoice or balance changed. Refresh before creating the link.'):window.ArcErrors?.message?.(e)||s}
async function open(invoice){const owner=epoch,[c,payment]=await Promise.all([rpc('context',{invoice_id:invoice.id}),rpc('payment_context',{invoice_id:invoice.id})]);if(owner!==epoch)return;
 let invite,uploaded,committed=false,client,link,pending=false;
 const d=U.dialog({title:L('Enlace de pago de la factura','Lien de paiement de la facture','Invoice payment link'),saveLabel:L('Volver','Retour','Back'),error,className:'gsDialog',ids:{error:'icError'},body:`<div data-gi-ignore><p><strong>${E(invoice.number)}</strong> · ${E(window.ArcFormat.money(invoice.total))}</p><p>${E(L('El enlace muestra el PDF conservado y el saldo actual. Un pago verificado se registra con el circuito habitual de cobros.','Le lien affiche le PDF conservé et le solde actuel. Un paiement vérifié suit le circuit habituel d’encaissement.','The link shows the preserved PDF and current balance. Verified payments use the existing receipt workflow.'))}</p>${window.CocoEnvironment?.name==='development'?`<p class="gaHint">${E(L('Vista previa de desarrollo: se requiere un administrador autenticado.','Aperçu de développement : un administrateur authentifié est requis.','Development preview requires an authenticated administrator.'))}</p>`:''}
 <label class="gsField">${E(L('Válido durante (días)','Valide pendant (jours)','Valid for (days)'))}<input id="icDays" type="number" min="1" max="30" step="1" value="7" required></label><button type="button" class="arcButton primary" id="icCreate">${E(L('Crear enlace de pago','Créer le lien de paiement','Create payment link'))}</button>
 <div id="icLink" hidden><label class="gsField">${E(L('Enlace para compartir','Lien à partager','Link to share'))}<input id="icShare" type="url" readonly></label><button type="button" class="arcButton secondary" id="icCopy">${E(L('Copiar enlace','Copier le lien','Copy link'))}</button><a class="arcButton secondary" id="icOpen" target="_blank" rel="noopener noreferrer">${E(L('Abrir enlace','Ouvrir le lien','Open link'))}</a><p>${E(L('Copia el enlace ahora. El código secreto no se conserva en la aplicación.','Copiez le lien maintenant. Le code secret n’est pas conservé dans l’application.','Copy the link now. Its secret code is not retained by the application.'))}</p></div>
 ${payment.can_configure?`<button type="button" class="arcButton secondary" id="icConfigure">${E(L('Configurar pagos en línea','Configurer les paiements en ligne','Configure online payments'))}</button>`:''}<ul>${c.invitations.map(i=>`<li>${E(stamp(i.created_at))} · ${E(i.revoked_at?L('Revocado','Révoqué','Revoked'):L('Válido hasta','Valide jusqu’au','Valid through')+' '+stamp(i.expires_at))}${!i.revoked_at?` <button type="button" class="arcButton secondary" data-ic-revoke="${E(i.id)}">${E(L('Revocar enlace','Révoquer le lien','Revoke link'))}</button>`:''}</li>`).join('')}</ul></div>`});
 d.dataset.invoiceCheckout='';owned.add(d);d.addEventListener('close',()=>owned.delete(d),{once:true});
 const create=d.querySelector('#icCreate'),close=d.querySelector('[data-arc-dialog-close]');create.disabled=!c.can_create;d.querySelector('#icDays').disabled=!c.can_create;
 d.addEventListener('cancel',e=>{if(pending)e.preventDefault()});
 create.onclick=async()=>{if(pending||!d.querySelector('form').reportValidity())return;pending=true;create.disabled=true;close.disabled=true;d.querySelector('#icError').textContent='';try{
  if(owner!==epoch)throw Error('AUTH_CHANGED');
  if(link){await navigator.clipboard.writeText(link);return}
  if(!invite)invite={id:crypto.randomUUID(),token:Array.from(crypto.getRandomValues(new Uint8Array(32)),n=>n.toString(16).padStart(2,'0')).join('')};
  client=await window.GamaCloud.db();
  if(!uploaded){const document=await window.GamaInternalInvoices.blob(invoice),sha=await hash(document);if(document.size>52428800)throw Error('CHECKOUT_PDF_TOO_LARGE');if(owner!==epoch)throw Error('AUTH_CHANGED');
   const user=(await client.auth.getUser()).data?.user;if(!user?.id)throw Error('AUTH_CHANGED');const path=user.id+'/'+invite.id+'.pdf';
   const r=await client.storage.from('sales-checkout-documents').upload(path,document,{upsert:false,contentType:'application/pdf'});if(r.error)throw r.error;uploaded={path,sha};
  }
  const days=Number(d.querySelector('#icDays').value);if(!Number.isInteger(days)||days<1||days>30)throw Error('CHECKOUT_EXPIRY_INVALID');
  if(!invite.expires_at)invite.expires_at=new Date(Date.now()+days*86400000).toISOString();
  if(owner!==epoch)throw Error('AUTH_CHANGED');await rpc('create',{...invite,invoice_id:invoice.id,revision:invoice.direct_revision,pdf_sha256:uploaded.sha,require_signature:false,payment_percent:100});committed=true;
  if(owner!==epoch)throw Error('AUTH_CHANGED');const url=new URL('coco-checkout.html',location.href);url.searchParams.set('lang',window.GamaI18n?.language||'es');url.hash=invite.token;link=url.href;
  d.querySelector('#icLink').hidden=false;d.querySelector('#icShare').value=link;d.querySelector('#icOpen').href=link;d.querySelector('#icDays').disabled=true;create.textContent=L('Copiar enlace','Copier le lien','Copy link');
 }catch(e){d.querySelector('#icError').textContent=error(e)}finally{pending=false;create.disabled=!c.can_create;close.disabled=false}};
 d.querySelector('#icConfigure')?.addEventListener('click',async()=>{try{await window.ArcLoadScript('coco-checkout-payments.js');if(owner!==epoch)return;return window.CocoSalesCheckoutPayments.configure(payment,async()=>{d.close();await open(invoice)})}catch(e){d.querySelector('#icError').textContent=error(e)}});
 d.querySelector('#icCopy').onclick=()=>navigator.clipboard.writeText(link).catch(()=>d.querySelector('#icShare').select());
 d.querySelectorAll('[data-ic-revoke]').forEach(b=>{b.disabled=!c.can_create;b.onclick=async()=>{b.disabled=true;try{await rpc('revoke',{id:b.dataset.icRevoke,invoice_id:invoice.id});b.textContent=L('Revocado','Révoqué','Revoked')}catch(e){b.disabled=false;d.querySelector('#icError').textContent=error(e)}}});
 d.addEventListener('close',()=>{if(uploaded&&!committed&&client)client.storage.from('sales-checkout-documents').remove([uploaded.path]).catch(()=>{})},{once:true});return d;
}
window.CocoInvoiceCheckout={open};window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;epoch++;owned.forEach(d=>d.close())});
})();
