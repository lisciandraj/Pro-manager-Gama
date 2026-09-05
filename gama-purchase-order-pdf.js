/* GAMA — Generador de PDF para pedidos a proveedores (usa jsPDF, cargado por CDN) */
(function(){
'use strict';
function esc(v){return String(v??'')}
function build(o){
 if(!window.jspdf||!window.jspdf.jsPDF)throw new Error('No se pudo cargar el generador de PDF.');
 const {jsPDF}=window.jspdf,doc=new jsPDF();
 let y=20;
 doc.setFontSize(18);doc.text('PEDIDO A PROVEEDOR',14,y);y+=10;
 doc.setFontSize(11);
 doc.text('N.º: '+esc(o.number||'-'),14,y);y+=6;
 doc.text('Fecha: '+esc(o.dateLabel||''),14,y);y+=6;
 if(o.expectedLabel){doc.text('Fecha prevista: '+esc(o.expectedLabel),14,y);y+=6}
 y+=4;
 doc.text('Proveedor: '+esc(o.supplier||''),14,y);y+=6;
 if(o.supplierEmail){doc.text(esc(o.supplierEmail),14,y);y+=6}
 if(o.supplierPhone){doc.text(esc(o.supplierPhone),14,y);y+=6}
 if(o.supplierAddress){doc.text(esc(o.supplierAddress),14,y);y+=6}
 y+=4;
 doc.setFont(undefined,'bold');
 doc.text('Producto',14,y);doc.text('Ref.',95,y);doc.text('Cant.',140,y);doc.text('P. compra',158,y);doc.text('Subtotal',180,y);
 doc.setFont(undefined,'normal');y+=3;doc.setLineWidth(0.2);doc.line(14,y,196,y);y+=6;
 (o.items||[]).forEach(x=>{
  if(y>270){doc.addPage();y=20}
  doc.text(esc(x.name),14,y,{maxWidth:78});
  doc.text(esc(x.reference||''),95,y,{maxWidth:42});
  doc.text(String(x.qty),140,y);
  doc.text('$'+Number(x.cost||0).toFixed(2),158,y);
  doc.text('$'+(Number(x.qty||0)*Number(x.cost||0)).toFixed(2),180,y);
  y+=7;
 });
 y+=1;doc.line(14,y,196,y);y+=8;
 doc.setFont(undefined,'bold');
 doc.text('TOTAL: $'+Number(o.total||0).toFixed(2),150,y);y+=10;
 doc.setFont(undefined,'normal');
 if(o.notes){doc.setFontSize(10);doc.text('Notas: '+esc(o.notes),14,y,{maxWidth:180});y+=10}
 doc.setFontSize(9);
 doc.text('Documento generado por GAMA Stock Manager. No constituye una factura.',14,y);
 return doc.output('blob');
}
async function send({o,email,subject,body,filename}){
 let blob=null;
 try{blob=build(o)}catch(e){console.warn('[GAMA Purchase PDF]',e)}
 return window.GamaQuotePdf.sendDocument({blob,email,subject,body,filename});
}
window.GamaPurchaseOrderPdf={build,send};
})();
