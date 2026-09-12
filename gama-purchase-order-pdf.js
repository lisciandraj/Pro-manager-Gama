/* GAMA — Generador de PDF para pedidos a proveedores (usa jsPDF, cargado por CDN) */
(function(){
'use strict';
function esc(v){return String(v??'')}
function build(o){
 const l=window.GamaPdfTemplate.layout({title:'Pedido a proveedor',reference:o.number,date:'Fecha: '+esc(o.dateLabel||''),detail:o.expectedLabel?'Fecha prevista: '+o.expectedLabel:''}),doc=l.doc;
 l.section('Proveedor');
 [o.supplier,o.supplierEmail,o.supplierPhone,o.supplierAddress].filter(Boolean).forEach(v=>l.text(v));
 function columns(){l.room(16);doc.setFillColor(...window.GamaPdfTemplate.teal);doc.rect(14,l.y-5,182,9,'F');doc.setTextColor(255,255,255);doc.setFontSize(8);doc.setFont('helvetica','bold');[['Producto / referencia',16],['Cant.',119],['P. compra',140],['Subtotal',177]].forEach(([v,x])=>doc.text(v,x,l.y));l.y+=10}
 columns();
 (o.items||[]).forEach(x=>{
  doc.setFont('helvetica','normal');doc.setFontSize(9);
  const lines=doc.splitTextToSize(esc(x.name)+(x.reference?' / '+x.reference:''),97);
  let first=true;
  while(lines.length){
   if(l.y+10>270){l.next();columns()}
   const chunk=lines.splice(0,Math.max(1,Math.floor((266-l.y)/4)));
   doc.setTextColor(...window.GamaPdfTemplate.ink);doc.setFont('helvetica','normal');doc.setFontSize(9);doc.text(chunk,16,l.y);
   if(first){doc.text(String(x.qty),131,l.y,{align:'right'});doc.text('$'+Number(x.cost||0).toFixed(2),166,l.y,{align:'right'});doc.text('$'+(Number(x.qty||0)*Number(x.cost||0)).toFixed(2),194,l.y,{align:'right'});first=false}
   l.y+=chunk.length*4+5;
  }
  doc.setDrawColor(224,232,236);doc.setLineWidth(.2);doc.line(14,l.y-3,196,l.y-3);
 });
 l.room(20);l.y+=4;l.text('TOTAL: $'+Number(o.total||0).toFixed(2),14,true);
 if(o.notes){l.section('Notas');l.text(o.notes)}
 l.finish('Pedido de compra. No constituye una factura.');
 return doc.output('blob');
}

async function send({o,email,subject,body,filename}){
 let blob=null;
 try{blob=build(o)}catch(e){console.warn('[GAMA Purchase PDF]',e)}
 return window.GamaQuotePdf.sendDocument({blob,email,subject,body,filename});
}
window.GamaPurchaseOrderPdf={build,send};
})();
