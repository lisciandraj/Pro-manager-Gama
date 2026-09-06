/* GAMA — Generador de PDF para presupuestos (usa jsPDF, cargado por CDN) */
(function(){
'use strict';
function esc(v){return String(v??'')}
function build(q){
 if(!window.jspdf||!window.jspdf.jsPDF)throw new Error('No se pudo cargar el generador de PDF.');
 const {jsPDF}=window.jspdf,doc=new jsPDF();
 let y=20;
 doc.setFontSize(18);doc.text('PRESUPUESTO',14,y);y+=10;
 doc.setFontSize(11);
 doc.text(esc(q.seller||'GAMA Stock Manager'),14,y);y+=6;
 doc.text('RUC: '+esc(q.sellerRuc||'-'),14,y);y+=6;
 doc.text('N.º: '+esc(q.number||'-'),14,y);y+=6;
 doc.text('Fecha: '+esc(q.dateLabel||''),14,y);y+=10;
 doc.text('Cliente: '+esc(q.client||''),14,y);y+=6;
 if(q.clientId){doc.text('Identificación: '+esc(q.clientId),14,y);y+=6}
 if(q.clientAddress){doc.text(esc(q.clientAddress),14,y);y+=6}
 if(q.clientEmail){doc.text(esc(q.clientEmail),14,y);y+=6}
 y+=4;
 doc.setFont(undefined,'bold');
 doc.text('Producto',14,y);doc.text('Cant.',110,y);doc.text('Precio',140,y);doc.text('Subtotal',170,y);
 doc.setFont(undefined,'normal');y+=3;doc.setLineWidth(0.2);doc.line(14,y,196,y);y+=6;
 (q.items||[]).forEach(x=>{
  if(y>270){doc.addPage();y=20}
  doc.text(esc(x.name),14,y,{maxWidth:90});
  doc.text(String(x.qty),110,y);
  doc.text('$'+Number(x.price||0).toFixed(2),140,y);
  doc.text('$'+(Number(x.qty||0)*Number(x.price||0)).toFixed(2),170,y);
  y+=7;
 });
 y+=1;doc.line(14,y,196,y);y+=8;
 doc.text('Subtotal: $'+Number(q.sub||0).toFixed(2),140,y);y+=6;
 doc.text('IVA '+esc(q.rate||0)+'%: $'+Number(q.tax||0).toFixed(2),140,y);y+=6;
 doc.setFont(undefined,'bold');
 doc.text('TOTAL: $'+Number(q.total||0).toFixed(2),140,y);y+=10;
 doc.setFont(undefined,'normal');doc.setFontSize(9);
 doc.text('Documento informativo. No constituye una factura.',14,y);
 return doc.output('blob');
}
/* Windows y macOS aceptan navigator.share con archivos, pero su hoja de
   compartir adjunta el PDF y descarta "text": el correo salía en blanco. En
   escritorio se usa por eso el enlace mailto, que sí redacta el mensaje, más
   la descarga del PDF para adjuntarlo. La hoja de compartir se reserva al
   móvil, donde adjuntar a mano es lo doloroso. */
function touchPrimary(){try{return !!(window.matchMedia&&window.matchMedia('(pointer: coarse)').matches)}catch(e){return false}}
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
async function copyToClipboard(text){try{await navigator.clipboard.writeText(text);return true}catch(e){return false}}
async function sendDocument({blob,email,subject,body,filename}){
 if(!blob){
  alert('No se pudo generar el PDF del documento. Se abrirá el correo, ya redactado, sin adjunto.');
  api.openMail(buildMailto({email,subject,body}).url);
  return;
 }
 if(touchPrimary()&&navigator.canShare&&navigator.canShare({files:[new File([blob],filename,{type:'application/pdf'})]})){
  try{await navigator.share({files:[new File([blob],filename,{type:'application/pdf'})],title:subject,text:body});return}
  catch(e){if(e&&e.name==='AbortError')return}
 }
 download(blob,filename);
 const mail=buildMailto({email,subject,body});
 const copied=mail.truncated?await copyToClipboard(String(body||'')):false;
 alert('Se descargó «'+filename+'».\n\nSe abrirá tu correo con el asunto y el mensaje ya redactados: solo falta adjuntar ese archivo.'
  +(mail.truncated?'\n\nEl mensaje es largo y se ha resumido para que el correo no lo corte.'+(copied?' El texto completo está copiado en el portapapeles.':''):''));
 api.openMail(mail.url);
}
async function send({q,email,subject,body,filename}){
 let blob=null;
 try{blob=build(q)}catch(e){console.warn('[GAMA PDF]',e)}
 return sendDocument({blob,email,subject,body,filename});
}
/* openMail se llama a través de api para poder sustituirlo en las pruebas
   sin navegar de verdad a un mailto:. */
const api={build,send,sendDocument,buildMailto,openMail};
window.GamaQuotePdf=api;
})();
