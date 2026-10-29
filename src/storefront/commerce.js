/* GAMA purchasing additions. Authorization and amounts are checked by the server. */
(()=>{'use strict';
const $=id=>document.getElementById(id),E=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=v=>Number(v||0).toLocaleString('es-EC',{style:'currency',currency:'USD'});
let policyVersion='',policies={};let context,settings={},commerce={},preview=null,previewSignature='',checkoutKey='',checkoutSignature='',busy=false,widget,token='',scriptPromise,verificationBox;
let receipts=[];try{receipts=JSON.parse(sessionStorage.getItem('gama.guest.receipts')||'[]').slice(0,20)}catch(_){}
const errors={COMMERCE_POLICY_CHANGED:'La información legal cambió. Revisa la nueva versión antes de volver a enviar.',WEBSITE_RATE_LIMIT:'Has enviado varias solicitudes. Espera un momento o utiliza el contacto publicado.',COMMERCE_BILLING_REQUIRED:'Completa los datos de facturación y el teléfono.',COMMERCE_PRICE_REQUIRED:'Un producto necesita precio confirmado. Solicita una cotización.',CART_PRICE_CHANGED:'Los precios cambiaron. Revisa los nuevos importes antes de confirmar.',COMMERCE_PURCHASE_REQUIRED:'Solo puedes publicar una opinión después de una compra confirmada.',COMMERCE_TERMS_REQUIRED:'Lee y acepta las condiciones antes de enviar el pedido.',HUMAN_VERIFICATION_REQUIRED:'Completa la verificación de seguridad y vuelve a enviar.',HUMAN_VERIFICATION_UNAVAILABLE:'La verificación de seguridad no está disponible. Inténtalo de nuevo o contacta con GAMA.',WEBSITE_REQUEST_KEY_REUSED:'Esta solicitud cambió. Actualiza la selección antes de volver a enviarla.',NOT_FOUND:'Este pedido no está disponible en esta sesión.'};
const message=e=>Object.entries(errors).find(([k])=>String(e?.message||e).includes(k))?.[1]||'No se pudo completar la operación. Conservamos tus datos. Vuelve a intentarlo.';
const api=(a,d={})=>context.api('commerce_'+a,d);
function isCheckout(){return $('purchaseMode')?.value==='order'}
function mode(){const active=isCheckout();$('billingFields').hidden=!active;$('billingFields').querySelectorAll('[data-required]').forEach(i=>i.required=active);const phone=$('quoteForm').elements.phone;phone.required=active;phone.closest('label').firstChild.textContent=active?'Teléfono *':'Teléfono (opcional)';$('cartTitle').textContent=active?'Solicitar un pedido sin cuenta':'Solicitar una cotización';$('quoteForm').querySelector('.checkout-contact .checkout-title').textContent=active?'Contacto para este pedido':'¿A quién enviamos la cotización?';$('checkoutTerms').hidden=!active;$('checkoutTerms').querySelector('input').required=active;preview=null;previewSignature='';$('checkoutAmounts').textContent='';$('quoteSend').firstChild.textContent=active?'Revisar pedido ':'Enviar solicitud ';}
function resetHuman(){token='';if(widget!==undefined&&window.turnstile)window.turnstile.reset(widget)}
async function ensureHuman(target){
 const host=target||$('quoteSend').parentElement;
 if(verificationBox.parentElement!==host){
  if(widget!==undefined){window.turnstile.remove(widget);widget=undefined;token=''}
  if(target)host.append(verificationBox);else $('quoteSend').before(verificationBox);
 }
 if(widget!==undefined)return;
 if(!commerce.turnstile_sitekey)await refreshPolicies();
 if(!commerce.turnstile_sitekey)throw Error('HUMAN_VERIFICATION_UNAVAILABLE');
 if(!scriptPromise)scriptPromise=new Promise((resolve,reject)=>{const s=document.createElement('script');s.src='https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';s.async=true;s.onload=resolve;s.onerror=()=>reject(Error('HUMAN_VERIFICATION_UNAVAILABLE'));document.head.append(s)}).catch(e=>{scriptPromise=null;throw e});
 await scriptPromise;if(widget!==undefined)return;
 widget=window.turnstile.render($('humanVerification'),{sitekey:commerce.turnstile_sitekey,size:'compact',action:'gama_commerce','response-field':false,language:'es',callback:t=>{token=t},'expired-callback':()=>{token=''},'error-callback':()=>{token='';$('humanStatus').textContent='No se pudo verificar la conexión. Vuelve a abrir tu selección.'}});
}
async function humanToken(target){await ensureHuman(target);if(!token)throw Error('HUMAN_VERIFICATION_REQUIRED');return token}
function attach(ctx){
 context=ctx;const f=$('quoteForm');
 const chooser=document.createElement('label');chooser.className='purchase-mode';chooser.innerHTML='¿Qué quieres hacer?<select id="purchaseMode"><option value="quote">Solicitar una cotización</option><option value="order">Solicitar un pedido sin cuenta</option></select>';
 f.querySelector('.checkout-section').prepend(chooser);
 const billing=document.createElement('fieldset');billing.id='billingFields';billing.hidden=true;
 billing.innerHTML='<legend>Datos de facturación</legend><p>No necesitas crear una cuenta. El pedido se confirma después de acordar disponibilidad, entrega y pago.</p><div class="form-grid"><label>Nombre o razón social *<input name="billing_name" maxlength="160" minlength="2" autocomplete="organization" data-required></label><label>Tipo de identificación *<select name="id_type" data-required><option value="ruc">RUC</option><option value="cedula">Cédula</option><option value="passport">Pasaporte</option></select></label><label>Identificación *<input name="identification" maxlength="20" data-required></label><label>Ciudad *<input name="city" maxlength="100" minlength="2" autocomplete="address-level2" data-required></label><label class="full-width">Dirección de facturación y entrega *<input name="billing_address" maxlength="500" minlength="5" autocomplete="street-address" data-required></label></div>';
 f.querySelector('.checkout-contact').append(billing);
 const terms=document.createElement('label');terms.className='consent';terms.id='checkoutTerms';terms.hidden=true;terms.innerHTML='<input type="checkbox" name="terms_accepted"><span>He leído las <button type="button" class="text-link" data-legal="terms">condiciones del pedido</button> y la información de <button type="button" class="text-link" data-legal="delivery">entregas y devoluciones</button>. GAMA confirmará el envío y el total antes de aceptar el pedido.</span>';billing.after(terms);
 const amounts=document.createElement('div');amounts.id='checkoutAmounts';amounts.className='commerce-totals';$('quoteSend').before(amounts);
 verificationBox=document.createElement('div');verificationBox.innerHTML='<div id="humanVerification"></div><p id="humanStatus" role="status"></p>';$('quoteSend').before(verificationBox);
 $('purchaseMode').onchange=mode;
 f.addEventListener('input',()=>{if(preview){preview=null;previewSignature='';$('checkoutAmounts').textContent='La selección cambió. Revisa nuevamente el total.';if(isCheckout())$('quoteSend').firstChild.textContent='Revisar pedido ';}});
 const history=document.createElement('button');history.type='button';history.className='text-link';history.textContent='Pedidos sin cuenta de esta sesión';history.onclick=guestHistory;$('footerNavigation').after(history);
 const cookies=document.createElement('button');cookies.type='button';cookies.className='text-link';cookies.textContent='Preferencias de cookies';cookies.onclick=cookiePreferences;history.after(cookies);
 const help=document.createElement('button');help.type='button';help.className='text-link';help.id='commerceSupport';help.textContent='Privacidad, devoluciones y reclamaciones';help.onclick=()=>support();cookies.after(help);
 $('whatsappLink')?.addEventListener('click',e=>{e.preventDefault();whatsapp()});
}
function setPolicies(p){if(!p?.version||!p.documents)return;if(policyVersion&&policyVersion!==p.version){preview=null;previewSignature='';const agreed=$('quoteForm')?.elements.terms_accepted;if(agreed)agreed.checked=false}policyVersion=p.version;policies=p.documents}
function configure(data){settings=data.settings||{};if(data.commerce)commerce=data.commerce;setPolicies(data.policies)}
async function refreshPolicies(){const p=await api('policies');if(!p?.version||!p.documents)throw Error('NETWORK_ERROR');setPolicies(p);if(p.commerce)commerce=p.commerce;return p}
async function checkout(form,lines){
 if(busy)return;busy=true;const button=$('quoteSend');button.disabled=true;
 try{
  const values=Object.fromEntries(new FormData(form));
  const billing={name:values.billing_name,id_type:values.id_type,identification:values.identification,address:values.billing_address,city:values.city};
  const payload={contact_name:values.contact_name,email:values.email,company:values.company,phone:values.phone,notes:values.notes,website:values.website,billing,lines,terms_accepted:form.elements.terms_accepted.checked,policy_version:policyVersion};
  const signature=JSON.stringify(payload);
  if(!preview||previewSignature!==signature){
   preview=await api('preview',{lines});previewSignature=signature;
   $('checkoutAmounts').innerHTML=`<dl><dt>Subtotal sin IVA</dt><dd>${money(preview.subtotal)}</dd><dt>IVA</dt><dd>${money(preview.tax)}</dd><dt>Total de productos</dt><dd><strong>${money(preview.total)}</strong></dd></dl><p>Envío: pendiente de acuerdo. No se cobra ningún importe al enviar esta solicitud.</p><button type="button" disabled aria-describedby="paymentAvailability">Pagar en línea</button><small id="paymentAvailability">El pago en línea todavía no está disponible.</small>`;
   button.firstChild.textContent='Enviar pedido para confirmación ';$('quoteStatus').textContent='Revisa el desglose y vuelve a pulsar para enviar el pedido.';return;
  }
  if(signature!==checkoutSignature){checkoutKey=crypto.randomUUID();checkoutSignature=signature}
  const result=await api('checkout',{...payload,price_hash:preview.price_hash,request_key:checkoutKey,human_token:await humanToken()});
  receipts.unshift({id:result.id,access_token:result.access_token,reference:result.reference});receipts=receipts.slice(0,20);
  try{sessionStorage.setItem('gama.guest.receipts',JSON.stringify(receipts))}catch(_){}
  context.clearCart();form.reset();mode();$('quoteStatus').textContent=`Pedido ${result.reference} recibido para confirmación. GAMA acordará contigo la entrega y el pago. No se ha efectuado ningún cobro.`;checkoutSignature='';checkoutKey='';
 }catch(e){if(String(e.message).includes('COMMERCE_POLICY_CHANGED')){try{await refreshPolicies()}catch(_){}form.elements.terms_accepted.checked=false;preview=null;previewSignature=''}if(String(e.message).includes('CART_PRICE_CHANGED')){preview=null;previewSignature=''}$('quoteStatus').textContent=message(e)}finally{busy=false;button.disabled=false;resetHuman()}
}
function dialog(title){const d=document.createElement('dialog');d.className='commerce-dialog';d.innerHTML=`<div class="dialog-heading"><h2>${E(title)}</h2><button type="button" class="text-link">Cerrar</button></div><div class="commerce-dialog-body"></div>`;d.querySelector('button').onclick=()=>d.close();d.addEventListener('close',()=>{disposeHuman(d);d.remove()});document.body.append(d);d.showModal();return d}
async function guestHistory(){
 const d=dialog('Pedidos sin cuenta'),body=d.querySelector('.commerce-dialog-body');body.textContent='Consultando tus pedidos…';
 const results=await Promise.allSettled(receipts.map(r=>api('guest_order',r)));if(!d.isConnected)return;
 body.innerHTML='<p>Estos comprobantes se conservan en esta pestaña. No incluyen los pedidos de otras personas. Guarda la referencia para contactar con GAMA.</p>'+(receipts.length?results.map((r,i)=>r.status==='fulfilled'?`<article class="commerce-row"><h3>${E(r.value.reference)}</h3><p>${E(r.value.status)} · ${money(r.value.total)}</p><div class="approval-toolbar"><button type="button" data-repeat-guest="${i}">Copiar productos</button><button type="button" data-download-guest="${i}">Descargar comprobante</button><button type="button" data-support-guest="${i}">Solicitar atención</button></div></article>`:`<p>No se pudo consultar ${E(receipts[i].reference)}. Vuelve a intentarlo.</p>`).join(''):'<p>Aún no hay pedidos en esta sesión.</p>');
 body.querySelectorAll('[data-download-guest]').forEach(b=>b.onclick=()=>receiptDownload(results[Number(b.dataset.downloadGuest)].value));
 body.querySelectorAll('[data-support-guest]').forEach(b=>b.onclick=()=>{const reference=receipts[Number(b.dataset.supportGuest)].reference;d.close();support(reference)});
 body.querySelectorAll('[data-repeat-guest]').forEach(b=>b.onclick=async()=>{b.disabled=true;try{const r=await api('guest_repeat',receipts[Number(b.dataset.repeatGuest)]);await context.repeat(r.lines);d.close()}catch(e){body.append(Object.assign(document.createElement('p'),{textContent:message(e)}));b.disabled=false}});
}
async function reviews(product,host){
 const section=document.createElement('section');section.className='product-reviews';section.innerHTML='<h3>Opiniones de compradores</h3><p role="status">Consultando opiniones…</p>';host.append(section);
 const active=window.GamaCustomer?.isActive();const call=(a,d)=>active?window.GamaCustomer.commerce(a,d):api(a,d);
 try{
  const r=await api('reviews',{product_id:product.id});if(!section.isConnected)return;
  section.innerHTML=`<h3>Opiniones de compradores</h3><p>${r.count?`${E(r.average)} / 5 · ${E(r.count)} opiniones`:'Este producto todavía no tiene opiniones.'}</p>${r.items.map(x=>`<article class="commerce-row"><strong>${E(x.rating)} / 5 · Compra verificada</strong><p>${E(x.body)}</p><small>${E(String(x.created_at).slice(0,10))}</small></article>`).join('')}`;
  let credential={};let eligibility={eligible:false};
  if(active)eligibility=await call('review_eligibility',{product_id:product.id});
  else for(const receipt of receipts){const e=await api('review_eligibility',{...receipt,product_id:product.id});if(e.eligible||e.own_review){eligibility=e;credential=receipt;break}}
  if(!section.isConnected)return;
  if(!eligibility.eligible&&!eligibility.own_review){section.insertAdjacentHTML('beforeend','<p>Las opiniones están reservadas a compradores verificados. Accede a tu cuenta de empresa o conserva el comprobante de tu pedido sin cuenta.</p>');return}
  const f=document.createElement('form');f.className='review-form';f.innerHTML='<label>Tu valoración<select name="rating" required><option value="">Elige una nota</option><option value="5">5 — Excelente</option><option value="4">4 — Bueno</option><option value="3">3 — Regular</option><option value="2">2 — Mejorable</option><option value="1">1 — Malo</option></select></label><label>Tu opinión<textarea name="body" required minlength="3" maxlength="2000" rows="3"></textarea></label><p>Tu texto y valoración serán públicos con la etiqueta Compra verificada. No incluyas datos personales.</p><button type="submit">Publicar opinión</button><p role="status"></p>';section.append(f);
  if(eligibility.own_review){f.elements.rating.value=String(eligibility.own_review.rating);f.elements.body.value=eligibility.own_review.body;const remove=document.createElement('button');remove.type='button';remove.textContent='Eliminar mi opinión';remove.onclick=async()=>{remove.disabled=true;try{const data={...credential,product_id:product.id};if(!active)data.human_token=await humanToken(f);await call('review_delete',data);section.remove();await reviews(product,host)}catch(e){f.querySelector('[role=status]').textContent=message(e)}finally{remove.disabled=false;if(!active)resetHuman()}};f.append(remove)}
  f.querySelector('[type=submit]').disabled=!eligibility.eligible;
  f.onsubmit=async e=>{e.preventDefault();const b=f.querySelector('[type=submit]');if(b.disabled)return;b.disabled=true;try{
   const data={...credential,product_id:product.id,rating:Number(f.elements.rating.value),body:f.elements.body.value};
   if(!active)data.human_token=await humanToken(f);
   await call('review_save',data);f.querySelector('[role=status]').textContent=eligibility.own_review?.hidden?'Opinión guardada. Su publicación sigue pendiente de revisión.':'Opinión publicada. Gracias por compartir tu experiencia.';
  }catch(e){f.querySelector('[role=status]').textContent=message(e)}finally{b.disabled=false;if(!active)resetHuman()}};
  if(!active)ensureHuman(f).catch(e=>{f.querySelector('[role=status]').textContent=message(e)});
 }catch(e){if(section.isConnected)section.innerHTML='<h3>Opiniones de compradores</h3><p>No se pudieron cargar las opiniones. Vuelve a abrir este producto para intentarlo de nuevo.</p>'}
}
function cookiePreferences(){
 const d=dialog('Cookies y almacenamiento');d.querySelector('.commerce-dialog-body').innerHTML='<p>Usamos almacenamiento necesario para la selección, la sesión de empresa y los comprobantes de pedidos. La protección contra bots utiliza Cloudflare Turnstile.</p><p>No hay analítica de comportamiento ni publicidad activadas. Las preferencias opcionales permanecen desactivadas y no se solicita consentimiento para servicios inexistentes.</p><label><input type="checkbox" checked disabled> Funciones necesarias</label><p>Puedes borrar la selección y cerrar sesión desde el sitio. Eliminar los datos de navegación también elimina los comprobantes guardados en esta pestaña.</p><button type="button" id="essentialCookies">Mantener solo lo necesario</button>';
 d.querySelector('#essentialCookies').onclick=()=>{try{localStorage.setItem('gama.cookie.preferences',JSON.stringify({version:policyVersion,necessary:true,analytics:false,marketing:false,updated_at:new Date().toISOString()}))}catch(_){}d.close()};
}
function legal(kind,cfg){return policies[kind]?policies[kind]+'\n\nVersión: '+policyVersion:null}
function disposeHuman(host){if(verificationBox&&host.contains(verificationBox)){if(widget!==undefined&&window.turnstile)window.turnstile.remove(widget);widget=undefined;token=''}}
function receiptDownload(r){
 const data={reference:r.reference,status:r.status,received_at:r.created_at,products:r.cart,policy_version:r.policy_version,accepted_at:r.accepted_at,policies:r.policies,
  notice:'Solicitud pendiente de confirmación. No es una factura fiscal ni un comprobante de pago. Envío, disponibilidad y pago deben acordarse con GAMA.'};
 download('GAMA-'+String(r.reference||'solicitud').replace(/[^A-Za-z0-9-]/g,'')+'.json',JSON.stringify(data,null,2),'application/json');
}
function download(name,content,type){const url=URL.createObjectURL(new Blob([content],{type})),a=document.createElement('a');a.href=url;a.download=name;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000)}
function whatsapp(){
 const digits=(settings.whatsapp||'').replace(/\D/g,'');if(!/^[1-9][0-9]{7,14}$/.test(digits))return;
 const d=dialog('Contactar por WhatsApp'),body=d.querySelector('.commerce-dialog-body');body.innerHTML=`<p>Vas a abrir WhatsApp para comunicarte con GAMA en +${E(digits)}. Es un servicio externo sujeto a sus propias condiciones y política de privacidad. No se envía tu selección ni información de facturación.</p><a class="button primary" target="_blank" rel="noopener noreferrer" href="https://wa.me/${digits}${settings.whatsapp_message?'?text='+E(encodeURIComponent(settings.whatsapp_message)):''}">Continuar a WhatsApp</a>`;
}
async function support(reference=''){
 const d=dialog('Privacidad, devoluciones y reclamaciones'),body=d.querySelector('.commerce-dialog-body');
 body.innerHTML=`<p>Este canal es gratuito y no requiere una cuenta. Para consultas sobre datos personales, verificaremos tu identidad de forma proporcional antes de facilitar o modificar información. No adjuntes documentos de identidad, datos de tarjeta ni información sensible.</p><form class="commerce-support"><label>Tipo de solicitud *<select name="kind"><option value="privacy">Datos personales</option><option value="return">Devolución</option><option value="warranty">Garantía / producto defectuoso</option><option value="complaint">Reclamación</option></select></label><label data-right>Derecho que deseas ejercer *<select name="right_kind"><option value="access">Acceso</option><option value="rectification">Rectificación / actualización</option><option value="erasure">Eliminación</option><option value="opposition">Oposición</option><option value="portability">Portabilidad</option><option value="restriction">Suspensión</option><option value="withdrawal">Retirar un consentimiento opcional</option><option value="other">Otro derecho / consulta</option></select></label><label>Nombre completo *<input name="contact_name" required minlength="2" maxlength="120" autocomplete="name"></label><label>Correo para recibir la respuesta *<input name="email" type="email" required maxlength="254" autocomplete="email"></label><label>Referencia del pedido o producto (opcional)<input name="order_reference" value="${E(reference)}" maxlength="100"></label><label>Describe tu solicitud *<textarea name="message" rows="5" required minlength="5" maxlength="3000"></textarea></label><label class="commerce-honeypot" aria-hidden="true">Sitio web<input name="website" tabindex="-1" autocomplete="off"></label><p>Usaremos estos datos para atender y dar seguimiento a tu solicitud. Consulta la <button type="button" class="text-link" data-legal="privacy">información de privacidad</button>. Este formulario no te suscribe a publicidad ni crea un reembolso automático.</p><div data-human></div><p role="status" aria-live="polite"></p><button type="submit">Enviar solicitud</button></form>`;
 const f=body.querySelector('form'),notice=f.querySelector('[role=status]');let key='',signature='';
 f.elements.kind.onchange=()=>{f.querySelector('[data-right]').hidden=f.elements.kind.value!=='privacy'};
 try{if(!policyVersion)await refreshPolicies();if(d.isConnected)await ensureHuman(f.querySelector('[data-human]'))}catch(e){if(d.isConnected)notice.textContent=message(e)}
 f.onsubmit=async e=>{e.preventDefault();const b=f.querySelector('[type=submit]');if(b.disabled)return;b.disabled=true;try{
  const payload={...Object.fromEntries(new FormData(f)),policy_version:policyVersion};if(payload.kind!=='privacy')payload.right_kind='';
  const next=JSON.stringify(payload);if(signature!==next){signature=next;key=crypto.randomUUID()}
  const r=await api('case_submit',{...payload,request_key:key,human_token:await humanToken(f.querySelector('[data-human]'))});if(!d.isConnected)return;
  disposeHuman(d);body.innerHTML=`<p role="status">Solicitud recibida. Referencia: <strong>${E(r.reference)}</strong></p><p>Guarda esta referencia. GAMA revisará la solicitud y te responderá por el canal indicado. La recepción no confirma la identidad ni la procedencia de un retorno.</p><button type="button" data-receipt>Descargar comprobante</button>`;
  body.querySelector('[data-receipt]').onclick=()=>download(r.reference+'.txt',`GAMA — Solicitud recibida\nReferencia: ${r.reference}\nRecepción: ${r.received_at}\nTipo: ${payload.kind}\nVersión de información: ${policyVersion}\nNo es factura ni comprobante de pago.`, 'text/plain;charset=utf-8');
 }catch(e){if(String(e.message).includes('COMMERCE_POLICY_CHANGED')){try{await refreshPolicies()}catch(_){}}if(d.isConnected)notice.textContent=message(e)}finally{b.disabled=false;resetHuman()}};
}
window.GamaCommerce={attach,configure,isCheckout,checkout,reviews,ensureHuman,humanToken,resetHuman,message,legal,policyVersion:()=>policyVersion};
})();
