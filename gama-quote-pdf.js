/* GAMA — Generador de PDF para presupuestos (usa jsPDF, cargado por CDN) */
(function(){
'use strict';
function esc(v){return String(v??'')}
/* esc() no escapa: sólo alimenta a jsPDF. Todo lo que entra en innerHTML
   pasa por escHtml, porque un nombre de cliente puede contener < o ". */
function escHtml(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
const logoReady=Promise.resolve();
function build(q){
 if(!window.jspdf?.jsPDF)throw new Error('No se pudo cargar el generador de PDF.');
 const doc=new window.jspdf.jsPDF(),ink=[24,50,74],teal=[8,124,139];let y=0;
 function header(){y=window.GamaPdfTemplate.header(doc,{title:q.documentType==='internal_invoice'?'FACTURA INTERNA':'PRESUPUESTO',reference:q.number,date:'Fecha: '+esc(q.dateLabel||''),detail:q.validUntil?'Válido hasta: '+q.validUntil+' · v'+(q.revision||1):''})}
 function room(h){if(y+h>272){doc.addPage();header()}}
 function paragraph(text,size=10){doc.setFontSize(size);const ls=doc.splitTextToSize(esc(text),180);for(const line of ls){room(5);doc.text(line,14,y);y+=5}y+=3}
 function tableHead(){room(15);doc.setFillColor(...teal);doc.rect(14,y-5,182,9,'F');doc.setTextColor(255,255,255);doc.setFontSize(8);[['Producto',16],['Cant.',99],['Precio',117],['Dto.',139],['IVA',153],['Subtotal',170]].forEach(([t,x])=>doc.text(t,x,y));doc.setTextColor(...ink);y+=10}
 header();paragraph(q.seller||'GAMA',12);paragraph('RUC: '+esc(q.sellerRuc||'—')+(q.sellerAddress?' · '+q.sellerAddress:''),9);
 paragraph('PREPARADO PARA',9);paragraph(q.client||'');paragraph([q.clientId,q.clientAddress,q.clientEmail].filter(Boolean).join(' · '),9);
 if(q.delivery_address)paragraph('Entrega: '+q.delivery_address+(q.delivery_terms?' · '+q.delivery_terms:''),9);
 tableHead();
 (q.items||[]).forEach(x=>{
  doc.setFontSize(9);const lines=doc.splitTextToSize(esc(x.name),78);let first=true;
  while(lines.length){
   if(y+10>270){doc.addPage();header();tableHead()}
   const chunk=lines.splice(0,Math.max(1,Math.floor((266-y)/4)));
   doc.setFontSize(9);doc.text(chunk,16,y);
   if(first){doc.setFontSize(8);doc.text(String(x.qty),99,y);doc.text('$'+Number(x.listPrice??x.price??0).toFixed(2),117,y);doc.text(Number(x.discount||0)+'%',139,y);doc.text(Number(x.taxRate??q.rate??0)+'%',153,y);doc.text('$'+(Number(x.qty||0)*Number(x.price||0)).toFixed(2),194,y,{align:'right'});first=false}
   y+=Math.max(9,chunk.length*4+4);
  }
  doc.setDrawColor(224,232,236);doc.setLineWidth(0.2);doc.line(14,y-4,196,y-4);
 });
 room(38);y+=4;doc.setFontSize(10);doc.text('Subtotal: $'+Number(q.sub||0).toFixed(2),196,y,{align:'right'});y+=6;doc.text('IVA: $'+Number(q.tax||0).toFixed(2),196,y,{align:'right'});y+=9;doc.setFontSize(15);doc.setTextColor(...teal);doc.setFont(undefined,'bold');doc.text('TOTAL  $'+Number(q.total||0).toFixed(2),196,y,{align:'right'});doc.setTextColor(...ink);doc.setFont(undefined,'normal');y+=12;
 if(q.payment||q.pay)paragraph('Forma de pago: '+(q.payment||q.pay),9);
 if(q.terms)paragraph('Condiciones: '+q.terms,9);
 if(q.notes)paragraph(q.notes,9);
 window.GamaPdfTemplate.footer(doc,q.documentType==='internal_invoice'?'Factura interna de gestión. Sin validez fiscal. No es un comprobante SRI.':'Documento informativo. No constituye una factura.');
 return doc.output('blob');
}
/* Windows y macOS aceptan navigator.share con archivos, pero su hoja de
   compartir adjunta el PDF y descarta "text": el correo salía en blanco. Se
   reserva al móvil, donde adjuntar a mano es lo doloroso; en escritorio el
   mensaje se redacta en la propia aplicación.

   "pointer: coarse" no servía para distinguirlos: un portátil con pantalla
   táctil lo activa y
   volvía a caer en la hoja de compartir del sistema, que adjunta el PDF y
   descarta el texto. Se identifica el móvil por el agente de usuario, que un
   PC con Windows nunca cumple. iPadOS 13+ se anuncia como Macintosh, de ahí
   la comprobación de puntos táctiles. */
function isMobile(){
 const ua=navigator.userAgent||'';
 if(/Android|iPhone|iPod/i.test(ua))return true;
 if(/iPad|Macintosh/.test(ua)&&(navigator.maxTouchPoints||0)>1)return true;
 return false;
}
/* Los clientes de correo cortan las URL largas (Outlook y el shell de Windows
   rondan los 2 000 caracteres) y lo hacen en silencio. Mejor recortar nosotros
   y decirlo que entregar un mensaje truncado a media frase. */
const MAILTO_MAX=1800;
function buildMailto({email,subject,body}){
 const url=t=>'mailto:'+(email||'')+'?subject='+encodeURIComponent(subject||'')+'&body='+encodeURIComponent(t||'');
 let text=String(body||''),truncated=false;
 while(text.length>120&&url(text).length>MAILTO_MAX){text=text.slice(0,Math.floor(text.length*0.85));truncated=true}
 if(truncated)text=text.replace(/\s+\S*$/,'')+'\n\n[…] El detalle completo está en el PDF adjunto.';
 return{url:url(text),truncated};
}
function download(blob,filename){
 const href=URL.createObjectURL(blob),a=document.createElement('a');
 a.href=href;a.download=filename;document.body.appendChild(a);a.click();a.remove();
 setTimeout(()=>URL.revokeObjectURL(href),30000);
}
function openMail(url){window.location.href=url}
function openTab(url){window.open(url,'_blank','noopener')}
async function copyToClipboard(text){try{await navigator.clipboard.writeText(text);return true}catch(e){return false}}
/* Los webmails no reciben nada de mailto: ni de la hoja de compartir. Se
   generan sus URL de redacción, que sí aceptan destinatario, asunto y cuerpo. */
const gmailUrl=(e,s,b)=>'https://mail.google.com/mail/?view=cm&fs=1&to='+encodeURIComponent(e||'')+'&su='+encodeURIComponent(s||'')+'&body='+encodeURIComponent(b||'');
const outlookUrl=(e,s,b)=>'https://outlook.live.com/mail/0/deeplink/compose?to='+encodeURIComponent(e||'')+'&subject='+encodeURIComponent(s||'')+'&body='+encodeURIComponent(b||'');
function dialogCss(){
 if(document.getElementById('gamaMailCss'))return;
 const s=document.createElement('style');s.id='gamaMailCss';
 s.textContent=`#gamaMailBack{position:fixed;inset:0;background:#17324688;z-index:100000;display:grid;place-items:center;padding:16px}#gamaMailBox{width:min(620px,100%);max-height:92vh;overflow:auto;background:#fff;border-radius:18px;padding:22px;box-shadow:0 20px 60px #17324640}#gamaMailBox h3{margin:0 0 4px;color:#18324a;font-size:20px}#gamaMailBox .gmSub{margin:0 0 14px;color:#71808a;font-size:13px}#gamaMailBox label{display:block;font-size:11px;font-weight:800;color:#61717c;margin:10px 0 4px}#gamaMailBox input,#gamaMailBox textarea{width:100%;box-sizing:border-box;padding:10px;border:1px solid #c9d6df;border-radius:9px;font-size:13px;font-family:inherit}#gamaMailBox textarea{min-height:190px;resize:vertical}#gamaMailNote{background:#fff6ef;border-left:4px solid #f47a2a;border-radius:9px;padding:11px;font-size:13px;color:#4c5c68;margin-bottom:6px}#gamaMailBox .gmRow{display:flex;gap:8px;flex-wrap:wrap;margin-top:14px}#gamaMailBox button{border:0;border-radius:9px;padding:11px 14px;font-weight:800;cursor:pointer}#gamaMailBox .gmPrimary{background:#087c8b;color:#fff}#gamaMailBox .gmLight{background:#eef3f4;color:#18324a}#gamaMailBox .gmClose{margin-left:auto}@media(max-width:600px){#gamaMailBox .gmRow{display:grid;grid-template-columns:1fr}#gamaMailBox .gmClose{margin-left:0}}`;
 document.head.appendChild(s);
}
/* Se redacta aquí, no en el sistema operativo: así el mensaje es el mismo
   tanto si usas Gmail en el navegador como Outlook instalado, y siempre se
   puede copiar aunque el equipo no tenga ninguna aplicación de correo. */
function composeDialog({email,subject,body,filename}){
 dialogCss();
 document.getElementById('gamaMailBack')?.remove();
 const back=document.createElement('div');back.id='gamaMailBack';
 back.innerHTML=`<div id="gamaMailBox" role="dialog" aria-modal="true" aria-label="Enviar por correo"><h3>Enviar por correo</h3><p class="gmSub">Revisa el mensaje y elige tu correo. Puedes modificarlo antes de enviarlo.</p>${filename?`<div id="gamaMailNote">📎 <b>${escHtml(filename)}</b> se ha descargado. Ningún correo permite adjuntar un archivo automáticamente: adjúntalo desde tu mensaje.</div>`:''}<label for="gamaMailTo">Para</label><input id="gamaMailTo" type="email" value="${escHtml(email||'')}"><label for="gamaMailSubject">Asunto</label><input id="gamaMailSubject" value="${escHtml(subject||'')}"><label for="gamaMailBody">Mensaje</label><textarea id="gamaMailBody">${escHtml(body||'')}</textarea><div class="gmRow"><button type="button" class="gmPrimary" id="gamaMailGmail">Abrir Gmail</button><button type="button" class="gmLight" id="gamaMailOutlook">Abrir Outlook</button><button type="button" class="gmLight" id="gamaMailApp">Mi aplicación de correo</button></div><div class="gmRow"><button type="button" class="gmLight" id="gamaMailCopy">📋 Copiar mensaje</button><button type="button" class="gmLight gmClose" id="gamaMailClose">Cerrar</button></div></div>`;
 document.body.appendChild(back);
 const val=id=>document.getElementById(id).value;
 const close=()=>back.remove();
 back.onclick=e=>{if(e.target===back)close()};
 document.getElementById('gamaMailClose').onclick=close;
 document.getElementById('gamaMailGmail').onclick=()=>{api.openTab(gmailUrl(val('gamaMailTo'),val('gamaMailSubject'),val('gamaMailBody')));close()};
 document.getElementById('gamaMailOutlook').onclick=()=>{api.openTab(outlookUrl(val('gamaMailTo'),val('gamaMailSubject'),val('gamaMailBody')));close()};
 document.getElementById('gamaMailApp').onclick=()=>{api.openMail(buildMailto({email:val('gamaMailTo'),subject:val('gamaMailSubject'),body:val('gamaMailBody')}).url);close()};
 document.getElementById('gamaMailCopy').onclick=async()=>{
  const btn=document.getElementById('gamaMailCopy');
  btn.textContent=await copyToClipboard(val('gamaMailBody'))?'✅ Copiado':'No se pudo copiar';
  setTimeout(()=>{if(document.getElementById('gamaMailCopy'))btn.textContent='📋 Copiar mensaje'},2000);
 };
 document.getElementById('gamaMailBody').focus();
 return back;
}
async function sendDocument({blob,email,subject,body,filename}){
 if(blob&&api.isMobile()&&navigator.canShare&&navigator.canShare({files:[new File([blob],filename,{type:'application/pdf'})]})){
  try{await navigator.share({files:[new File([blob],filename,{type:'application/pdf'})],title:subject,text:body});return}
  catch(e){if(e&&e.name==='AbortError')return}
 }
 if(blob)download(blob,filename);
 composeDialog({email,subject,body,filename:blob?filename:''});
}
async function send({q,email,subject,body,filename}){
 let blob=null;
 try{await logoReady;blob=build(q)}catch(e){console.warn('[GAMA PDF]',e)}
 return sendDocument({blob,email,subject,body,filename});
}
/* openMail, openTab e isMobile se llaman a través de api para poder
   sustituirlos en las pruebas sin navegar de verdad ni depender del equipo. */
const api={build,logoReady,send,sendDocument,buildMailto,composeDialog,openMail,openTab,isMobile,gmailUrl,outlookUrl};
window.GamaQuotePdf=api;
})();
