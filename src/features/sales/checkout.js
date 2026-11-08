/* Staff-issued, revocable capabilities for a frozen commercial document. */
(function(){'use strict';
const E=s=>window.ArcUI.esc(s),L=(es,fr,en)=>({es,fr,en}[window.GamaI18n?.language||'es']||es);
let epoch=0;const ownedDialogs=new Set();
const failure=e=>String(e?.message||e).includes('QUOTE_CHANGED')?L('El presupuesto cambió. Actualiza antes de crear el enlace.','Le devis a changé. Actualisez avant de créer le lien.','The quote changed. Refresh before creating a link.'):L('No se pudo completar la operación. Revisa tu acceso y vuelve a intentarlo.','L’opération n’a pas abouti. Vérifiez votre accès et réessayez.','The operation did not complete. Check your access and retry.');
async function rpc(action,data={}){const owner=epoch,r=await window.ArcData.rawRpc('coco_sales_checkout',{p_action:action,p_data:data},{read:['context','evidence','payment_context'].includes(action)});if(owner!==epoch)throw Error('AUTH_CHANGED');if(r.error)throw r.error;return r.data}
function dialog(title,body,label,save,keepOpen=false){
 if(!keepOpen){const d=window.GamaSales.modal(title,body,label,save);ownedDialogs.add(d);d.addEventListener('close',()=>ownedDialogs.delete(d),{once:true});return d}
 const d=window.GamaSales.modal(title,body+`<button type="button" class="arcButton primary" data-checkout-create>${E(label)}</button>`,L('Volver','Retour','Back'),async()=>{});
 ownedDialogs.add(d);d.addEventListener('close',()=>ownedDialogs.delete(d),{once:true});
 let pending=false;const b=d.querySelector('[data-checkout-create]'),close=d.querySelector('[data-arc-dialog-close]');
 d.addEventListener('cancel',e=>{if(pending)e.preventDefault()});
 b.onclick=async()=>{if(pending||!d.querySelector('form').reportValidity())return;pending=true;b.disabled=true;if(close)close.disabled=true;d.querySelector('#gsFormError').textContent='';try{await save(d)}catch(e){d.querySelector('#gsFormError').textContent=failure(e)}finally{pending=false;b.disabled=false;if(close)close.disabled=false}};return d;
}
const stamp=v=>v?new Date(v).toLocaleString(window.GamaI18n?.language||'es'):'';
const download=(blob,name)=>{const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),60000)};
async function proof(id){const owner=epoch,d=await rpc('evidence',{id});if(owner!==epoch)return;
 const modal=dialog(L('Prueba de firma','Preuve de signature','Signature evidence'),`<p><strong>${E(d.signed_name)}</strong> · ${E(stamp(d.signed_at))}</p><p>${E(L('Documento firmado: SHA-256','Document signé : SHA-256','Signed document: SHA-256'))}</p><code class="gqReference">${E(d.pdf_sha256)}</code><p>${E(L('La firma expresa la aceptación comercial del PDF conservado.','La signature exprime l’acceptation commerciale du PDF conservé.','The signature records commercial acceptance of the preserved PDF.'))}</p><div data-signature-image></div>`,L('Descargar documento y prueba','Télécharger le document et la preuve','Download document and evidence'),async()=>{
  if(owner!==epoch)throw Error('AUTH_CHANGED');const client=await window.GamaCloud.db(),r=await client.storage.from('sales-checkout-documents').download(d.pdf_path);if(r.error)throw r.error;
  if(owner!==epoch)throw Error('AUTH_CHANGED');download(r.data,'Coco-'+d.document.number+'.pdf');download(new Blob([JSON.stringify(d,null,2)],{type:'application/json'}),'Coco-signature-'+id+'.json');
 });
 if(d.signature_png){const img=document.createElement('img');img.src=d.signature_png;img.alt=L('Firma del cliente','Signature du client','Customer signature');img.width=300;modal.querySelector('[data-signature-image]').append(img)}
}
async function quote(q){const owner=epoch,c=await rpc('context',{quote_id:q.id});if(owner!==epoch)return;
 let invite=null,link=null,uploaded=null,committed=false,client;
 const history=(c.invitations||[]).map(i=>`<tr><td>${E(stamp(i.created_at))}</td><td>${E(i.signed_at?L('Firmado','Signé','Signed'):i.revoked_at?L('Revocado','Révoqué','Revoked'):Date.parse(i.expires_at)<Date.now()?L('Caducado','Expiré','Expired'):L('Pendiente','En attente','Pending'))}${i.signed_name?' · '+E(i.signed_name):''}</td><td>${i.signed_at?`<button type="button" class="arcButton secondary" data-checkout-proof="${E(i.id)}">${E(L('Ver prueba','Voir la preuve','View evidence'))}</button>`:''}${!i.revoked_at?`<button type="button" class="arcButton secondary" data-checkout-revoke="${E(i.id)}">${E(L('Revocar enlace','Révoquer le lien','Revoke link'))}</button>`:''}</td></tr>`).join('');
 const d=dialog(L('Firma y pago a distancia','Signature et paiement à distance','Remote signature and payment'),`<p>${E(L('El enlace contiene el PDF completo de esta versión, con sus anexos. Quien reciba el enlace podrá revisarlo y firmarlo.','Le lien contient le PDF complet de cette version, avec ses annexes. Son destinataire pourra le consulter et le signer.','The link contains this version’s complete PDF and attachments. Its recipient can review and sign it.'))}</p>${window.CocoEnvironment?.name==='development'?`<p class="gsHint">${E(L('Vista previa de desarrollo: solo los administradores autenticados pueden abrir el enlace.','Aperçu de développement : seuls les administrateurs authentifiés peuvent ouvrir le lien.','Development preview: only authenticated administrators can open the link.'))}</p>`:''}${q.quote_state==='sent'?`<label class="gsField">${E(L('Válido durante (días)','Valide pendant (jours)','Valid for (days)'))}<input name="days" type="number" value="7" min="1" max="30" required></label><p>${E(L('La caducidad nunca supera la vigencia del presupuesto.','L’expiration ne dépasse jamais la validité du devis.','Expiry never exceeds the quote’s validity.'))}</p><div data-checkout-link hidden><label class="gsField">${E(L('Enlace para compartir','Lien à partager','Link to share'))}<input name="share" type="url" readonly></label><button class="arcButton secondary" type="button" data-checkout-copy>${E(L('Copiar enlace','Copier le lien','Copy link'))}</button> <a class="arcButton secondary" target="_blank" rel="noopener noreferrer" data-checkout-open>${E(L('Abrir enlace','Ouvrir le lien','Open link'))}</a><p>${E(L('Copia el enlace ahora; su código secreto no se conserva en la aplicación.','Copiez le lien maintenant ; son code secret n’est pas conservé dans l’application.','Copy the link now; its secret code is not retained by the application.'))}</p></div>`:''}${history?`<div class="cocoSalesScroll"><table class="arcTable"><thead><tr>${['Fecha','Estado','Acciones'].map((x,i)=>'<th>'+E([L(x,'Date','Date'),L(x,'État','Status'),L(x,'Actions','Actions')][i])+'</th>').join('')}</tr></thead><tbody>${history}</tbody></table></div>`:''}`,q.quote_state==='sent'?L('Crear enlace de firma','Créer le lien de signature','Create signature link'):L('Volver','Retour','Back'),async form=>{
  if(q.quote_state!=='sent')return;if(owner!==epoch)throw Error('AUTH_CHANGED');
  if(link){await navigator.clipboard.writeText(link);return false}
  if(!invite){const bytes=crypto.getRandomValues(new Uint8Array(32));invite={id:crypto.randomUUID(),token:Array.from(bytes,n=>n.toString(16).padStart(2,'0')).join('')};}
  client=await window.GamaCloud.db();if(!uploaded){await window.GamaCompany?.load(true);await window.GamaPdf.ready();await window.GamaQuotePdf.logoReady;
   const fresh=await window.GamaQuotes.documentData(q.id);if(fresh.quote_revision!==q.quote_revision)throw Error('QUOTE_CHANGED');
   const generated=await window.GamaQuotePdf.compose(window.GamaQuotes.pdfData(fresh)),blob=generated instanceof Blob?generated:generated.output('blob');
   if(blob.size>52428800)throw Error('CHECKOUT_PDF_TOO_LARGE');const sha=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await blob.arrayBuffer())),n=>n.toString(16).padStart(2,'0')).join('');
   if(owner!==epoch)throw Error('AUTH_CHANGED');const user=(await client.auth.getUser()).data?.user;if(!user?.id)throw Error('AUTH_CHANGED');const path=user.id+'/'+invite.id+'.pdf';
   const r=await client.storage.from('sales-checkout-documents').upload(path,blob,{upsert:false,contentType:'application/pdf'});if(r.error)throw r.error;uploaded={path,sha};
  }
  if(owner!==epoch)throw Error('AUTH_CHANGED');const days=Number(form.querySelector('[name=days]').value);if(!Number.isInteger(days)||days<1||days>30)throw Error('CHECKOUT_EXPIRY_INVALID');
  if(!invite.expires_at)invite.expires_at=new Date(Date.now()+days*86400000).toISOString();
  await rpc('create',{...invite,quote_id:q.id,revision:q.quote_revision,pdf_sha256:uploaded.sha,...window.CocoSalesCheckoutPayments?.readQuote(form)||{require_signature:true,payment_percent:0}});
  committed=true;if(owner!==epoch)throw Error('AUTH_CHANGED');const target=new URL('coco-checkout.html',location.href);target.searchParams.set('lang',window.GamaI18n?.language||'es');target.hash=invite.token;link=target.href;
  form.querySelector('[data-checkout-link]').hidden=false;form.querySelector('[name=share]').value=link;form.querySelector('[data-checkout-open]').href=link;form.querySelector('[name=days]').disabled=true;
  const button=form.querySelector('[data-checkout-create]');if(button)button.textContent=L('Copiar enlace','Copier le lien','Copy link');return false;
 },q.quote_state==='sent');
 await window.ArcLoadScript('coco-checkout-payments.js');await window.CocoSalesCheckoutPayments.staffQuote(q,d,c);
 d.querySelector('[data-checkout-copy]')?.addEventListener('click',()=>navigator.clipboard.writeText(link).catch(()=>{d.querySelector('[name=share]').select()}));
 d.querySelectorAll('[data-checkout-revoke]').forEach(b=>b.onclick=async()=>{b.disabled=true;try{await rpc('revoke',{id:b.dataset.checkoutRevoke});b.textContent=L('Revocado','Révoqué','Revoked')}catch(e){b.disabled=false;d.querySelector('#gsFormError').textContent=failure(e)}});
 d.querySelectorAll('[data-checkout-proof]').forEach(b=>b.onclick=()=>proof(b.dataset.checkoutProof).catch(e=>window.gamaToast?.(failure(e))));
 d.addEventListener('close',()=>{if(uploaded&&!committed&&client)client.storage.from('sales-checkout-documents').remove([uploaded.path]).catch(()=>{})},{once:true});
}
window.CocoSalesCheckout={quote,proof,rpc,error:failure};
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;epoch++;for(const d of ownedDialogs){d.close();d.remove()}ownedDialogs.clear()});
})();
