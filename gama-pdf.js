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
 const l=window.GamaPdfTemplate.layout({title:titulo||'Pruebas de entrega',date:'Generado el '+fecha(new Date())});
 const rows=entregas||[];
 if(!rows.length)l.text('No hay ninguna prueba de entrega en este periodo.');
 rows.forEach((e,i)=>{if(i)l.next();proofContent(l,e,i+1)});
 return l.finish('Registro de pruebas de entrega.');
}
function proofContent(l,e,index){
 l.section(index?'Entrega '+index:'Datos de la entrega');
 for(const [k,v] of [['Cliente',e.cliente],['Dirección de entrega',e.direccion],['Fecha y hora de entrega',e.fecha?fecha(e.fecha):''],['Conductor',e.conductor],['Referencia',e.referencia]]){
  if(k==='Referencia'&&!v)continue;
  l.text(k+': '+(v||'-'),10);
 }
 l.y+=2;
 l.image(e.firma,'Firma de quien recibió',32);
 l.image(e.foto,'Fotografía tomada en la entrega',75);
}
function proofCertificate(e){
 const l=window.GamaPdfTemplate.layout({title:'Comprobante de entrega',reference:e.referencia,date:'Generado el '+fecha(new Date())});
 proofContent(l,e);
 return l.finish('Firma y fotografía registradas junto a los datos de la entrega.');
}

window.GamaPdf={save,fileName,proofReport,proofCertificate,money,jsPDF};
})();
