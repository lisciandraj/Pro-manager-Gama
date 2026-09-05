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
async function send({q,email,subject,body,filename}){
 let blob=null;
 try{blob=build(q)}catch(e){console.warn('[GAMA PDF]',e)}
 const mailtoUrl='mailto:'+email+'?subject='+encodeURIComponent(subject)+'&body='+encodeURIComponent(body);
 if(!blob){
  alert('No se pudo generar el PDF del presupuesto. Se abrirá el correo sin adjunto.');
  window.location.href=mailtoUrl;
  return;
 }
 const file=new File([blob],filename,{type:'application/pdf'});
 if(navigator.canShare&&navigator.canShare({files:[file]})){
  try{await navigator.share({files:[file],title:subject,text:body});return}
  catch(e){if(e&&e.name==='AbortError')return}
 }
 const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=filename;document.body.appendChild(a);a.click();a.remove();
 alert('Se descargó el PDF del presupuesto. Los enlaces de correo no permiten adjuntar archivos automáticamente: adjúntalo manualmente en el correo que se abrirá a continuación.');
 window.location.href=mailtoUrl;
}
window.GamaQuotePdf={build,send};
})();
