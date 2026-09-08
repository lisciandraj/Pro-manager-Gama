/* GAMA — Descarga en PDF de los documentos que genera la aplicación.

   Antes el presupuesto sólo se podía «imprimir» con window.print(), que abre el
   diálogo del sistema sobre la propia página. En la aplicación instalada eso
   dejaba al usuario encerrado: sin diálogo que cerrar y sin manera de volver,
   había que cerrar la aplicación entera. Un PDF se abre en el visor del
   dispositivo, que siempre tiene su propio botón de volver, y además es lo que
   hace falta para guardarlo o mandarlo.

   Aquí vive lo común: bajar un documento de jsPDF, y armar el informe de
   pruebas de entrega, que no tenía generador propio. */
(function(){
'use strict';
if(window.GamaPdf)return;

function jsPDF(){
 if(!window.jspdf||!window.jspdf.jsPDF)throw new Error('No se pudo cargar el generador de PDF. Comprueba tu conexión y recarga.');
 return window.jspdf.jsPDF;
}

/* Guarda el documento. En iOS dentro de la aplicación instalada la descarga
   por <a download> se ignora en silencio, así que ahí se abre el PDF en una
   pestaña: el usuario lo ve y lo guarda desde el visor. */
function save(doc,filename){
 const blob=doc.output('blob'),name=filename||'documento.pdf';
 const ua=navigator.userAgent||'';
 const iOS=/iPad|iPhone|iPod/.test(ua)||(/Macintosh/.test(ua)&&(navigator.maxTouchPoints||0)>1);
 const url=URL.createObjectURL(blob);
 if(iOS){
  const w=window.open(url,'_blank');
  // Si el navegador bloquea la pestaña se intenta la descarga normal.
  if(!w)link(url,name);
 }else link(url,name);
 setTimeout(()=>URL.revokeObjectURL(url),30000);
 return blob;
}
function link(url,name){
 const a=document.createElement('a');
 a.href=url;a.download=name;a.rel='noopener';
 document.body.appendChild(a);a.click();a.remove();
}
/* Un nombre de fichero que el sistema acepte en cualquier plataforma. */
function fileName(prefix,ref){
 const limpio=String(ref||'').replace(/[^\w.-]+/g,'-').replace(/^-+|-+$/g,'');
 return prefix+(limpio?'-'+limpio:'')+'.pdf';
}

const money=v=>'$'+Number(v||0).toFixed(2);
const fecha=v=>{try{return new Date(v).toLocaleString('es-EC')}catch(e){return String(v||'')}};

/* Informe de pruebas de entrega. Recibe las entregas ya resueltas por quien
   llama —este módulo no consulta la base— para que sirva igual a una entrega
   suelta que a un listado. */
function proofReport(entregas,titulo){
 const doc=new (jsPDF())();
 let y=20;
 doc.setFontSize(18);doc.text(titulo||'Pruebas de entrega',14,y);y+=8;
 doc.setFontSize(9);doc.setTextColor(110,110,110);
 doc.text('Generado el '+fecha(new Date()),14,y);y+=10;
 doc.setTextColor(0,0,0);
 const filas=entregas||[];
 if(!filas.length){doc.setFontSize(11);doc.text('No hay ninguna prueba de entrega en este periodo.',14,y);return doc}
 filas.forEach((e,i)=>{
  // Una entrega no se parte entre dos páginas: se salta antes.
  if(y>250){doc.addPage();y=20}
  doc.setFontSize(12);
  doc.text(String(i+1)+'. '+(e.cliente||'Sin cliente'),14,y);y+=6;
  doc.setFontSize(9);doc.setTextColor(90,90,90);
  if(e.direccion){doc.text(String(e.direccion).slice(0,110),14,y);y+=5}
  if(e.fecha){doc.text('Entregado: '+fecha(e.fecha),14,y);y+=5}
  if(e.conductor){doc.text('Conductor: '+e.conductor,14,y);y+=5}
  doc.setTextColor(0,0,0);
  if(e.firma){
   try{doc.addImage(e.firma,'PNG',14,y,50,20);y+=24}
   catch(err){doc.setFontSize(9);doc.text('(firma no legible)',14,y);y+=6}
  }
  if(e.foto){
   try{doc.addImage(e.foto,'JPEG',14,y,45,34);y+=38}
   catch(err){doc.setFontSize(9);doc.text('(foto no legible)',14,y);y+=6}
  }
  y+=4;
  doc.setDrawColor(220);doc.line(14,y,196,y);y+=8;
 });
 return doc;
}

/* Comprobante de UNA entrega, en UNA página. Sirve para un litigio: quien lo
   recibe tiene que ver de un vistazo quién firmó, qué día, a qué hora y en qué
   dirección, con la firma y la foto delante. Repartirlo en dos hojas obligaría
   a demostrar que la segunda pertenece a la primera. */
function proofCertificate(e){
 const doc=new (jsPDF())();
 const P=16, ANCHO=210-2*P;
 let y=20;

 doc.setFontSize(20);doc.setFont(undefined,'bold');
 doc.text('COMPROBANTE DE ENTREGA',P,y);
 doc.setFont(undefined,'normal');
 y+=7;doc.setFontSize(9);doc.setTextColor(110,110,110);
 doc.text('GAMA Enterprise Resource Planning · documento generado el '+fecha(new Date()),P,y);
 doc.setTextColor(0,0,0);
 y+=6;doc.setDrawColor(24,50,74);doc.setLineWidth(0.6);doc.line(P,y,P+ANCHO,y);y+=10;

 /* Los datos primero y en texto: si la foto o la firma no se pudieran pintar,
    el documento sigue diciendo quién, cuándo y dónde. */
 const filas=[
  ['Cliente', e.cliente||'-'],
  ['Dirección de entrega', e.direccion||'-'],
  ['Fecha y hora de entrega', e.fecha?fecha(e.fecha):'-'],
  ['Conductor', e.conductor||'-'],
 ];
 if(e.referencia)filas.push(['Referencia',e.referencia]);
 doc.setFontSize(10);
 filas.forEach(([k,v])=>{
  doc.setTextColor(110,110,110);doc.text(k,P,y);
  doc.setTextColor(0,0,0);doc.setFont(undefined,'bold');
  doc.text(doc.splitTextToSize(String(v),ANCHO-52),P+52,y);
  doc.setFont(undefined,'normal');
  y+=8;
 });
 y+=4;doc.setDrawColor(215,215,215);doc.setLineWidth(0.3);doc.line(P,y,P+ANCHO,y);y+=10;

 /* Encaja la imagen en su hueco sin deformarla: una firma estirada pierde
    valor como prueba. Si jsPDF no sabe leerla, se dice y se sigue. */
 function imagen(dataUrl,titulo,maxW,maxH){
  doc.setFontSize(10);doc.setTextColor(110,110,110);doc.text(titulo,P,y);doc.setTextColor(0,0,0);y+=5;
  if(!dataUrl){
   doc.setFontSize(9);doc.setTextColor(150,150,150);
   doc.text('No se capturó.',P,y+5);doc.setTextColor(0,0,0);y+=14;return;
  }
  let w=maxW,h=maxH;
  try{
   const pr=doc.getImageProperties(dataUrl);
   const k=Math.min(maxW/pr.width,maxH/pr.height);
   w=pr.width*k;h=pr.height*k;
  }catch(err){}
  try{
   const x=P+(maxW-w)/2;
   doc.addImage(dataUrl,x,y,w,h);
   // El marco va después: la imagen es opaca y taparía la línea.
   doc.setDrawColor(215,215,215);doc.setLineWidth(0.3);
   doc.rect(x,y,w,h);
   y+=h+9;
  }catch(err){
   doc.setFontSize(9);doc.setTextColor(150,150,150);
   doc.text('(no se pudo incluir la imagen)',P,y+5);doc.setTextColor(0,0,0);y+=14;
  }
 }
 imagen(e.firma,'Firma de quien recibió',ANCHO,38);
 imagen(e.foto,'Fotografía tomada en la entrega',ANCHO,92);

 doc.setFontSize(8);doc.setTextColor(110,110,110);
 const pie='La firma y la fotografía fueron capturadas por el conductor en el momento de la entrega y quedan registradas junto a la fecha y la hora indicadas.';
 doc.text(doc.splitTextToSize(pie,ANCHO),P,282);
 doc.setTextColor(0,0,0);
 return doc;
}

window.GamaPdf={save,fileName,proofReport,proofCertificate,money,jsPDF};
})();
