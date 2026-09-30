/* Generated from src/legacy/workspace.js. Edit the source and run npm run build. */
const KEY='stock_manager_v6_ecuador';
let db=JSON.parse(localStorage.getItem(KEY)||'{"products":[],"moves":[],"invoices":[]}');
db.products=db.products||[];db.moves=db.moves||[];db.invoices=db.invoices||[];db.clients=db.clients||[];
let invoiceItems=[];let lastQuote=null;
const $=id=>document.getElementById(id);
function save(){localStorage.setItem(KEY,JSON.stringify(db));renderAll()}
function showTab(id,btn){return window.ArcRouter.show(id,btn)}

function product(b){return db.products.find(p=>p.barcode===b)}
function uid(prefix='MOV'){return prefix+'-'+Date.now().toString(36).toUpperCase()+'-'+Math.random().toString(36).slice(2,7).toUpperCase()}
function compressPhoto(file){return new Promise((resolve,reject)=>{let r=new FileReader();r.onload=()=>{let i=new Image();i.onload=()=>{let max=320,s=Math.min(1,max/i.width,max/i.height),c=document.createElement('canvas');c.width=Math.max(1,Math.round(i.width*s));c.height=Math.max(1,Math.round(i.height*s));const ctx=c.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,c.width,c.height);ctx.drawImage(i,0,0,c.width,c.height);resolve(c.toDataURL('image/jpeg',.6))};i.onerror=reject;i.src=r.result};r.onerror=reject;r.readAsDataURL(file)})}
$('pPhoto').addEventListener('change',()=>{let f=$('pPhoto').files[0];if(f){$('pPreview').src=URL.createObjectURL(f);$('pPreview').style.display='block'}});

function gamaProductDuplicate(values,old){
 const key=v=>String(v??'').trim().toLowerCase().replace(/\s+/g,' ');
 for(const [field,label] of [['name','nombre'],['barcode','código de barras'],['ref','referencia']]){
  const value=key(values[field]);if(!value||(old&&value===key(old[field])))continue;
  if([...(db.products||[]),...(db.archivedProducts||[])].some(p=>p!==old&&(!old?.id||p.id!==old.id)&&key(p[field])===value))return 'Ya existe un producto con este '+label+'. Revisa también los productos archivados.';
 }
 return '';
}
async function createProduct(){
 let editingId=$('editingProductId').value,editing=$('editingBarcode').value,b=$('pBarcode').value.trim(),n=$('pName').value.trim();
 if(!b||!n)return alert('El código de barras y el nombre son obligatorios.');
 const old=editingId?db.products.find(p=>p.id===editingId):editing?product(editing):null;
 if((editingId||editing)&&!old)return alert('Producto no encontrado.');
 if(!old&&product(b))return alert('Este código de barras ya existe.');
 let photo=old?.photo||'';
 const duplicate=gamaProductDuplicate({name:n,barcode:b,ref:$('pRef').value.trim()},old);if(duplicate)return alert(duplicate);
 if($('pPhoto').files[0])photo=await compressPhoto($('pPhoto').files[0]);
 if(old){
  old.barcode=b;old.name=n;old.ref=$('pRef').value.trim();old.cat=$('pCat').value.trim();old.description=$('pDescription').value.trim();old.family=$('pFamily').value.trim();old.lines=$('pLines').value.trim();old.brand=$('pBrand').value.trim();old.presentation=$('pPresentation').value.trim();old.loc=$('pLoc').value.trim();old.min=Number($('pMin').value)||0;old.maxStock=Number($('pMaxStock').value)||0;old.qtyCarton=Number($('pQtyCarton').value)||0;old.weightG=Number($('pWeight').value)||0;old.volumeCm3=Number($('pVolume').value)||0;old.purchase_price=Number($('pCost').value)||0;old.price=Number($('pPrice').value)||0;old.salePriceB=Number($('pSalePriceB').value)||0;old.iva=Number($('pIva').value);old.photo=photo;
  alert('Producto actualizado correctamente.');
 }else{
  db.products.push({barcode:b,name:n,ref:$('pRef').value.trim(),cat:$('pCat').value.trim(),description:$('pDescription').value.trim(),family:$('pFamily').value.trim(),lines:$('pLines').value.trim(),brand:$('pBrand').value.trim(),presentation:$('pPresentation').value.trim(),loc:$('pLoc').value.trim(),min:Number($('pMin').value)||0,maxStock:Number($('pMaxStock').value)||0,qtyCarton:Number($('pQtyCarton').value)||0,weightG:Number($('pWeight').value)||0,volumeCm3:Number($('pVolume').value)||0,purchase_price:Number($('pCost').value)||0,price:Number($('pPrice').value)||0,salePriceB:Number($('pSalePriceB').value)||0,iva:Number($('pIva').value),photo,stock:0});
  alert('Producto creado correctamente.');
 }
 clearProductForm();save();
}
function populateSupplierSelect(){const s=$('pSupplier');if(!s)return;const cur=s.value;s.innerHTML='<option value="" data-gi=480def1d15a8>Sin proveedor</option>'+(db.suppliers||[]).map(x=>`<option value="${x.id}">${(x.name||'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]))}</option>`).join('');if(cur&&(db.suppliers||[]).some(x=>x.id===cur))s.value=cur}
async function editProduct(b,id){await window.ArchitectLegacyData?.load('products');let p=id?[...db.products,...(db.archivedProducts||[])].find(p=>p.id===id):product(b);if(!p)return;$('pActive').value=String(p.active!==false);$('editingProductId').value=p.id||'';$('editingBarcode').value=p.barcode||'';$('pBarcode').value=p.barcode;$('pName').value=p.name;$('pRef').value=p.ref||'';$('pCat').value=p.cat||'';$('pDescription').value=p.description||'';$('pFamily').value=p.family||'';$('pLines').value=p.lines||'';$('pBrand').value=p.brand||'';$('pPresentation').value=p.presentation||'';$('pLoc').value=p.loc||'';$('pMin').value=p.min||0;$('pMaxStock').value=p.maxStock||0;$('pQtyCarton').value=p.qtyCarton||0;$('pWeight').value=p.weightG||0;$('pVolume').value=p.volumeCm3||0;$('pCost').value=p.purchase_price||0;$('pPrice').value=p.price||0;$('pSalePriceB').value=p.salePriceB||0;$('pIva').value=p.iva??15;populateSupplierSelect();$('pSupplier').value=p.supplierId||'';gamaShowProductPhoto(p);showTab('products',null);window.scrollTo({top:0,behavior:'smooth'})}
/* La ficha muestra la foto en grande: es la unica pantalla que necesita el
   original, asi que se pide justo aqui y para un solo producto. */
function gamaShowProductPhoto(p){
 const el=$('pPreview');if(!el)return;
 el.src='';el.style.display='none';
 if(p.photo){el.src=p.photo;el.style.display='block';return}
 if(!p.hasPhoto||!window.GamaPhotos||!p.id)return;
 GamaPhotos.load([p.id]).then(([data])=>{
  // El usuario puede haber cambiado de ficha mientras llegaba la foto.
  if(data&&$('editingProductId').value===p.id){el.src=data;el.style.display='block'}
 }).catch(()=>{});
}
function clearProductForm(){$('pActive').value='true';$('editingProductId').value='';$('editingBarcode').value='';['pBarcode','pName','pRef','pCat','pLoc','pDescription','pFamily','pLines','pBrand','pPresentation'].forEach(id=>$(id).value='');$('pMin').value=0;$('pMaxStock').value=0;$('pQtyCarton').value=0;$('pWeight').value=0;$('pVolume').value=0;$('pCost').value=0;$('pPrice').value=0;$('pSalePriceB').value=0;$('pIva').value=15;$('pSupplier').value='';$('pPhoto').value='';$('pPreview').src='';$('pPreview').style.display='none'}
function deleteProduct(b){let p=product(b);if(!p)return;if(p.stock!==0)return alert('No se puede eliminar un producto con stock. Primero deja el stock en 0.');if(!confirm(`¿Eliminar "${p.name}" de la lista de productos?`))return;db.products=db.products.filter(x=>x.barcode!==b);save();alert('Producto eliminado.')}
function renderProducts(filter=''){populateSupplierSelect();if(window.GamaCloud)window.ArcDirectories.directory('products',filter)}


// La ficha de cliente vive en Contactos, en su formulario único.
function editClient(id){const c=(db.clients||[]).find(x=>x.id===id||x.cloudId===id);window.GamaContacts?.edit('clients',c?.cloudId||id)}

function populateClientSelect(){
 const current=$('clientSelect').value;
 $('clientSelect').innerHTML='<option value="" data-gi=57780de4ab62>Selecciona un cliente...</option>'+db.clients.map(c=>`<option value="${c.id}">${c.name} — ${c.id}</option>`).join('');
 if(current&&db.clients.some(c=>c.id===current))$('clientSelect').value=current;
}
function selectClientForInvoice(){
 const c=db.clients.find(x=>x.id===$('clientSelect').value);
 $('clientId').value=c?c.id:'';$('clientName').value=c?c.name:'';$('clientAddress').value=c?c.address||'':'';$('clientEmail').value=c?c.email||'':'';
 window.gamaQuoteCategory=c?c.category||'A':'A';
 window.gamaResetQuoteOverrides?.();
 renderInvoiceItems();
}
function exportExcel(){return window.GamaExcelExport.run()}
function exportJSONBackup(){
 const blob=new Blob([JSON.stringify({version:'V6.1',exportedAt:new Date().toISOString(),data:db},null,2)],{type:'application/json'}),a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='stock_manager_backup_'+new Date().toISOString().slice(0,10)+'.json';a.click()
}
function searchProduct(){let p=product($('homeBarcode').value.trim());$('homeResult').innerHTML=p?`<p><b>${p.name}</b><br><span data-gi=ce4f7ecc850e>Stock: </span>${p.stock}<br>Precio: $${Number(p.price||0).toFixed(2)}<br>${p.photo?`<img class="product-img" src="${p.photo}">`:''}</p>`:'<p class="low" data-gi=beb1469ff83c>Producto no encontrado.</p>'}

function addInvoiceItem(){let p=product($('invoiceBarcode').value.trim()),q=Number($('invoiceQty').value);if(!p)return alert('Producto no encontrado.');if(q<1)return alert('Cantidad inválida.');let already=invoiceItems.reduce((a,x)=>a+x.q*(x.p.barcode===p.barcode),0);if(p.stock<already+q)return alert(`Stock insuficiente. Disponible: ${p.stock}`);invoiceItems.push({p,q});$('invoiceBarcode').value='';$('invoiceProductInfo').textContent='';renderInvoiceItems()}
function renderInvoiceItems(){$('invoiceItems').innerHTML='<table class="arcTable"><tr><th data-gi=494e0843d958>Foto</th><th data-gi=77b9238931ed>Producto</th><th data-gi=4805b9ed5d23>Cant.</th><th data-gi=2e4385b6057f>Precio</th><th data-gi=8c0f2cb34079>Subtotal</th><th></th></tr>'+invoiceItems.map((x,i)=>{
 const ref=gamaPriceFor(x.p),precio=quoteLinePrice(x),ajustado=x.price!==undefined&&x.price!==null;
 // El precio de referencia se deja a la vista tachado: quien firma el
 // presupuesto tiene que ver de cuánto era el descuento, no sólo el resultado.
 const pct=ref>0?Math.round((precio-ref)/ref*100):0;
 const marca=ajustado
  ?`<small class="quoteWas">antes $${ref.toFixed(2)}</small> <small class="quoteTag quoteOffer">oferta ${pct>0?'+':''}${pct}%</small>`
  :(gamaHasContractPrice(x.p)?' <small class="quoteTag" data-gi=82c2d641d0f5>tarifa</small>':'');
 return `<tr><td>${gamaPhotoCell(x.p)}</td><td>${x.p.name}</td><td>${x.q}</td>`
  +`<td class="quotePriceCell"><input type="number" min="0" step="0.01" value="${precio.toFixed(2)}" aria-label="${(window.GamaI18n?.t?.('Precio de')||'Precio de')} ${x.p.name}" onchange="setInvoiceItemPrice(${i},this.value)">`
  +(ajustado?`<button class="arcButton secondary quoteUndo" data-gi-title=ac492001216a title="Volver al precio de la tarifa" onclick="clearInvoiceItemPrice(${i})">↺</button>`:'')
  +`<div>${marca}</div></td>`
  +`<td>$${(x.q*precio).toFixed(2)}</td><td><button class="arcButton danger" onclick="removeInvoiceItem(${i})">×</button></td></tr>`;
}).join('')+'</table>'}
function removeInvoiceItem(i){invoiceItems.splice(i,1);renderInvoiceItems()}
/* Precio efectivo de una línea del presupuesto.

   Manda el precio escrito a mano si lo hay; si no, el de la tarifa del cliente;
   si tampoco, el precio base de la ficha. Todo lo que necesite un precio —la
   tabla, los totales, el impreso y la línea que se guarda— pasa por aquí. Es
   deliberado: cuando este cálculo estaba repetido en cuatro sitios, dos de
   ellos se quedaron con el precio base y el documento no cuadraba consigo
   mismo. */
function quoteLinePrice(x){
 if(!x)return 0;
 return x.price===undefined||x.price===null?gamaPriceFor(x.p):Number(x.price);
}
/* Un precio a mano vale para ESTE cliente. Al cambiar de cliente se descartan:
   arrastrar la oferta de uno al presupuesto de otro es justo el error que no
   se ve hasta que el cliente lo ve. */
window.gamaResetQuoteOverrides=function(){invoiceItems.forEach(x=>{delete x.price})};
function setInvoiceItemPrice(i,value){
 const x=invoiceItems[i];if(!x)return;
 const n=parseFloat(String(value).replace(',','.'));
 if(!Number.isFinite(n)||n<0){renderInvoiceItems();return}
 // Volver al precio de la tarifa se marca quitando el ajuste, no fijándolo.
 if(Math.abs(n-gamaPriceFor(x.p))<0.005)delete x.price;else x.price=n;
 renderInvoiceItems();
}
function clearInvoiceItemPrice(i){const x=invoiceItems[i];if(!x)return;delete x.price;renderInvoiceItems()}
$('invoiceBarcode').addEventListener('input',()=>{let p=product($('invoiceBarcode').value.trim());$('invoiceProductInfo').textContent=p?`${p.name} — Precio: $${gamaPriceFor(p).toFixed(2)}${gamaHasContractPrice(p)?' (tarifa del cliente)':''} — Stock: ${p.stock}`:''});
function validateQuoteForm(){if(!$('sellerRuc').value||!$('sellerName').value){alert('Completa el RUC y la razón social.');return false}if(!$('clientId').value||!$('clientName').value){alert('Completa los datos del cliente.');return false}if(!invoiceItems.length){alert('Añade al menos un producto.');return false}return true}
function quoteTotals(){const sub=invoiceItems.reduce((a,x)=>a+x.q*quoteLinePrice(x),0),rate=15,tax=sub*rate/100,total=sub+tax;return{sub,rate,tax,total}}
function quoteNumber(count){return($('sellerEst').value||'001')+'-'+($('sellerPoint').value||'001')+'-'+String(count+1).padStart(9,'0')}
/* El precio congelado en el presupuesto es el que se acaba de facturar: si el
   cliente tiene tarifa, el impreso y el PDF deben mostrar ese precio, no el
   precio base de la ficha, o no cuadraría con sus propios totales. */
function quoteItemsSnapshot(){return invoiceItems.map(x=>({name:x.p.name,barcode:x.p.barcode,qty:x.q,price:quoteLinePrice(x),listPrice:gamaPriceFor(x.p)}))}
function finishQuote(inv){lastQuote=inv;$('invoicePreview').innerHTML=invoiceHTML(inv);invoiceItems=[];renderInvoiceItems()}
function generateInvoice(){if(!validateQuoteForm())return;const{sub,rate,tax,total}=quoteTotals(),number=quoteNumber(db.invoices.length),ref=uid('COT');let inv={...window.GamaCompany?.defaultsForQuote(),id:ref,number,date:new Date().toISOString(),clientId:$('clientId').value,client:$('clientName').value,clientEmail:$('clientEmail').value,clientAddress:$('clientAddress').value,seller:$('sellerName').value,sellerRuc:$('sellerRuc').value,items:quoteItemsSnapshot(),sub,tax,total,rate,pay:$('payment').value};db.invoices.unshift(inv);finishQuote(inv);save();alert('Presupuesto generado. Puedes imprimirlo o enviarlo por correo al cliente.')}
function invoiceHTML(i){return `<div class="invoice-preview"><h2 data-gi=d684c0be2b1d>PRESUPUESTO</h2><b>${i.seller}</b><br>RUC: ${i.sellerRuc}<br><span data-gi=38178a20b470>No. </span>${i.number}<br><span data-gi=5964f4d099df>Fecha: </span>${new Date(i.date).toLocaleDateString('es-EC')}<hr><b data-gi=07dc559c3d74>Cliente:</b> ${i.client}<br><span data-gi=60c3a5b64c7c>Identificación: </span>${i.clientId}<br>${i.clientAddress||''}<br>${i.clientEmail||''}<table class="arcTable"><tr><th data-gi=77b9238931ed>Producto</th><th data-gi=4805b9ed5d23>Cant.</th><th data-gi=2e4385b6057f>Precio</th><th data-gi=8c0f2cb34079>Subtotal</th></tr>${i.items.map(x=>`<tr><td>${x.name}</td><td>${x.qty}</td><td>${x.listPrice!==undefined&&Math.abs(x.listPrice-x.price)>=0.005?`<s>$${x.listPrice.toFixed(2)}</s> `:''}$${x.price.toFixed(2)}</td><td>$${(x.qty*x.price).toFixed(2)}</td></tr>`).join('')}</table><div class="totals"><div><span data-gi=8c0f2cb34079>Subtotal</span><span>$${i.sub.toFixed(2)}</span></div><div><span><span data-gi=ba6da46c5e1c>IVA </span>${i.rate}%</span><span>$${i.tax.toFixed(2)}</span></div><div class="grand"><span data-gi=ab2882c86465>TOTAL</span><span>$${i.total.toFixed(2)}</span></div></div><p><span data-gi=89d1f3dfeace>Forma de pago propuesta: </span>${i.pay}</p><p class="low" data-gi=40e465f455ef>Documento informativo. No constituye una factura.</p></div>`}
/* Antes esto llamaba a window.print(), que abre el diálogo del sistema encima
   de la propia página. En la aplicación instalada el usuario se quedaba
   encerrado: sin diálogo visible que cerrar y sin manera de volver atrás, había
   que cerrar la aplicación entera. Un PDF se abre en el visor del dispositivo,
   que siempre trae su botón de volver — y desde ahí también se imprime. */
async function downloadInvoicePdf(){
 if(!lastQuote)return alert('Genera primero el presupuesto.');
 if(!window.GamaQuotePdf||!window.GamaPdf)return alert('El generador de PDF no está disponible. Recarga la aplicación.');
 try{
  await window.GamaCompany?.load(true);
  await window.GamaPdf.ready();
  const doc=window.GamaQuotePdf.build(lastQuote);
  window.GamaPdf.save(doc,window.GamaPdf.fileName('presupuesto',lastQuote.number));
 }catch(e){console.error('[GAMA PDF]',e);alert('No se pudo generar el PDF: '+(e&&e.message||e))}
}
/* Se conserva el nombre antiguo: había accesos directos y llamadas sueltas. */
function printInvoice(){downloadInvoicePdf()}
/* La etiqueta de código de barras tenía el mismo window.print() y por tanto la
   misma trampa. El SVG generado se pasa a imagen y de ahí al PDF. */
async function downloadBarcodePdf(){
 const svg=document.getElementById('barcodeSvg');
 if(!svg||!svg.querySelector('rect'))return alert('Genera primero el código de barras.');
 if(!window.GamaPdf)return alert('El generador de PDF no está disponible. Recarga la aplicación.');
 try{
  /* Las medidas salen del viewBox, no de lo que ocupa en pantalla: si se
     tomaran de la pantalla, la proporción cambiaría con el ancho del móvil y
     las barras saldrían estiradas. Un código de barras deformado puede dejar
     de leerse, que es justo para lo que sirve la etiqueta. */
  await window.GamaCompany?.load(true);
  const vb=(svg.getAttribute('viewBox')||'0 0 300 150').split(/\s+/).map(Number);
  const w=vb[2]||300,h=vb[3]||150;
  // El SVG sólo tiene viewBox; sin width/height explícitos el navegador no
  // sabe a qué tamaño rasterizarlo al cargarlo como imagen.
  const copia=svg.cloneNode(true);
  copia.setAttribute('width',w);copia.setAttribute('height',h);
  copia.setAttribute('xmlns','http://www.w3.org/2000/svg');
  const xml=new XMLSerializer().serializeToString(copia);
  const img=new Image();
  img.onload=async()=>{
   try{
    const esc=3;                                   // x3: una etiqueta borrosa no se escanea
    const c=document.createElement('canvas');
    c.width=w*esc;c.height=h*esc;
    const ctx=c.getContext('2d');
    ctx.fillStyle='#fff';ctx.fillRect(0,0,c.width,c.height);
    ctx.drawImage(img,0,0,c.width,c.height);
    /* Etiqueta GAMA de 80x50 mm. El código conserva su proporción
       y una zona libre independiente del encabezado. */
    const LW=80,LH=50,MG=6;
    const escala=Math.min((LW-2*MG)/w,(LH-18)/h);
    const iw=w*escala,ih=h*escala;
    await window.GamaPdf.ready();
    const doc=new (window.GamaPdf.jsPDF())({orientation:'landscape',unit:'mm',format:[LW,LH]});
    window.GamaPdfTemplate.label(doc);
    doc.addImage(c.toDataURL('image/png'),'PNG',(LW-iw)/2,13+(LH-13-ih)/2,iw,ih);
    window.GamaPdf.save(doc,window.GamaPdf.fileName('etiqueta',$('barcodeValue').value));
   }catch(e){console.error('[GAMA PDF etiqueta]',e);alert('No se pudo generar la etiqueta: '+(e&&e.message||e))}
  };
  img.onerror=()=>alert('No se pudo leer el código de barras generado.');
  img.src='data:image/svg+xml;charset=utf-8,'+encodeURIComponent(xml);
 }catch(e){console.error('[GAMA PDF etiqueta]',e);alert('No se pudo generar la etiqueta: '+(e&&e.message||e))}
}
function emailInvoice(){if(!lastQuote)return alert('Genera primero el presupuesto.');const i=lastQuote;if(!i.clientEmail)return alert('El cliente seleccionado no tiene un correo registrado.');const dateLabel=new Date(i.date).toLocaleDateString('es-EC');const lines=i.items.map(x=>`- ${x.name} x${x.qty} — $${x.price.toFixed(2)} c/u — $${(x.qty*x.price).toFixed(2)}`).join('\n');const body=`Estimado/a ${i.client},\n\nAdjuntamos el presupuesto solicitado:\n\nN.º de presupuesto: ${i.number}\nFecha: ${dateLabel}\n\n${lines}\n\nSubtotal: $${i.sub.toFixed(2)}\nIVA ${i.rate}%: $${i.tax.toFixed(2)}\nTOTAL: $${i.total.toFixed(2)}\n\nQuedamos atentos a sus comentarios.\n\n${i.seller}`;window.GamaQuotePdf.send({q:{...i,dateLabel},email:i.clientEmail,subject:'Presupuesto '+i.number+' - '+i.seller,body,filename:'Presupuesto-'+i.number+'.pdf'})}


const C39={"*":"100101101101","0":"101001101101","1":"110100101011","2":"101100101011","3":"110110010101","4":"101001101011","5":"110100110101","6":"101100110101","7":"101001011011","8":"110100101101","9":"101100101101","A":"110101001011","B":"101101001011","C":"110110100101","D":"101011001011","E":"110101100101","F":"101101100101","G":"101010011011","H":"110101001101","I":"101101001101","J":"101011001101","K":"110101010011","L":"101101010011","M":"110110101001","N":"101011010011","O":"110101101001","P":"101101101001","Q":"101010110011","R":"110101011001","S":"101101011001","T":"101011011001","U":"110010101011","V":"100110101011","W":"110011010101","X":"100101101011","Y":"110010110101","Z":"100110110101","-":"100101011011",".":"110010101101"," ":"100110101101","$":"100100100101","/":"100100101001","+":"100101001001","%":"101001001001"};
function code39Bits(s){s=s.toUpperCase();if(!s||s.includes('*')||[...s].some(c=>!C39[c]))throw Error('Carácter no permitido en Code 39.');let b='';for(const c of '*'+s+'*')b+=C39[c]+'0';return b}
const EL=["0001101","0011001","0010011","0111101","0100011","0110001","0101111","0111011","0110111","0001011"],EG=["0100111","0110011","0011011","0100001","0011101","0111001","0000101","0010001","0001001","0010111"],ER=["1110010","1100110","1101100","1000010","1001110","1000110","1010000","1000100","1001000","1110100"],EP=["LLLLLL","LLGLGG","LLGGLG","LLGGGL","LGLLGG","LGGLLG","LGGGLL","LGLGLG","LGLGGL","LGGLGL"];
function eanBits(v){v=String(v).trim();if(!/^\d{12,13}$/.test(v))throw Error('EAN-13 requiere 12 o 13 dígitos.');const raw=v;v=v.slice(0,12);let s=0;for(let i=0;i<12;i++)s+=+v[i]*(i%2?3:1);let code=v+((10-s%10)%10);if(raw.length===13&&raw!==code)throw Error('Dígito de control EAN-13 incorrecto.');let p=EP[+code[0]],b='101';for(let i=1;i<=6;i++)b+=p[i-1]==='L'?EL[+code[i]]:EG[+code[i]];b+='01010';for(let i=7;i<13;i++)b+=ER[+code[i]];return [b+'101',code]}
function generateBarcode(){let err=$('barcodeError');err.textContent='';try{let raw=$('barcodeValue').value.trim(),bits,label;if($('barcodeType').value==='EAN13'){[bits,label]=eanBits(raw)}else{bits=code39Bits(raw);label=raw.toUpperCase()}let ns='http://www.w3.org/2000/svg',svg=$('barcodeSvg'),w=bits.length*3+40;svg.setAttribute('viewBox',`0 0 ${w} 150`);svg.innerHTML='';let x=20;for(const b of bits){if(b==='1'){let r=document.createElementNS(ns,'rect');r.setAttribute('x',x);r.setAttribute('y',10);r.setAttribute('width',3);r.setAttribute('height',100);r.setAttribute('fill','#000');svg.appendChild(r)}x+=3}let t=document.createElementNS(ns,'text');t.setAttribute('x',w/2);t.setAttribute('y',135);t.setAttribute('text-anchor','middle');t.setAttribute('font-family','monospace');t.setAttribute('font-size','16');t.textContent=label;svg.appendChild(t);$('barcodeText').textContent=label}catch(e){err.textContent=e.message}}

async function scan(target){await window.loadZXing();let v=$('camera');v.style.display='block';try{if(!window.ZXingBrowser)throw Error();let ds=await ZXingBrowser.BrowserCodeReader.listVideoInputDevices();if(!ds.length)throw Error();let d=ds.find(x=>/back|rear|environment|trasera|arrière/i.test(x.label))||ds[ds.length-1],r=new ZXingBrowser.BrowserMultiFormatReader(),controls;controls=await r.decodeFromVideoDevice(d.deviceId,v,res=>{if(res){$(target).value=res.getText();controls.stop();v.srcObject=null;v.style.display='none';if(target==='invoiceBarcode'){let p=product(res.getText());$('invoiceProductInfo').textContent=p?`${p.name} — Precio: $${Number(p.price||0).toFixed(2)} — Stock: ${p.stock}`:'Producto no encontrado'}else searchProduct()}})}catch(e){v.style.display='none';alert('No se pudo usar la cámara. Abre la aplicación con HTTPS y permite la cámara en Safari.')}}
function exportCSV(){let rows=[['Código','Nombre','Descripción','Familia','Líneas','Marca','Presentación','Referencia','Categoría','Ubicación','Stock','Mínimo','Máximo','Cantidad por cartón','Peso (g)','Volumen (cm3)','Precio compra','Precio venta A','Precio venta B','IVA'],...db.products.map(p=>[p.barcode,p.name,p.description,p.family,p.lines,p.brand,p.presentation,p.ref,p.cat,p.loc,p.stock,p.min,p.maxStock,p.qtyCarton,p.weightG,p.volumeCm3,p.purchase_price,p.price,p.salePriceB,p.iva])];let s=rows.map(r=>r.map(x=>`"${String(x??'').replaceAll('"','""')}"`).join(';')).join('\\n');let a=document.createElement('a');a.href=URL.createObjectURL(new Blob(['\\ufeff'+s],{type:'text/csv'}));a.download='inventario.csv';a.click()}

function norm(s){return String(s??'').trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'')}
function parseSpreadsheetXML(text){
 const doc=new DOMParser().parseFromString(text,'application/xml');
 if(doc.querySelector('parsererror'))throw Error('Archivo Excel XML no válido.');
 const sheets={};
 doc.querySelectorAll('Worksheet').forEach(ws=>{
  const name=ws.getAttribute('ss:Name')||ws.getAttribute('Name')||'Hoja';
  sheets[name]=[...ws.querySelectorAll('Row')].map(r=>[...r.querySelectorAll('Data')].map(d=>d.textContent));
 });
 return sheets;
}
function rowsObj(rows){if(!rows||!rows.length)return[];let h=rows[0].map(norm);return rows.slice(1).map(r=>Object.fromEntries(h.map((k,i)=>[k,r[i]??''])))}
function restoreJSON(){
 const f=$('jsonImport').files[0];if(!f)return alert('Selecciona una copia JSON.');
 if(!confirm('ATENCIÓN: se reemplazarán Productos, Clientes, Movimientos y Facturas. ¿Continuar?'))return;
 const r=new FileReader();r.onload=()=>{try{const x=JSON.parse(r.result);if(!x.data||!Array.isArray(x.data.products)||!Array.isArray(x.data.clients))throw Error('Copia no reconocida.');db={products:x.data.products,clients:x.data.clients,moves:x.data.moves||[],invoices:x.data.invoices||[]};save();alert('Copia restaurada correctamente.')}catch(e){alert('Copia inválida: '+e.message)}};r.readAsText(f)
}

function renderDonut(id,legendId,data){let entries=Object.entries(data).sort((a,b)=>b[1]-a[1]);if(!entries.length){$(id).style.background='var(--arc-surface-3)';$(legendId).innerHTML='<div class="muted" data-gi=03dc8297d3d6>Sin datos</div>';return}let total=entries.reduce((a,x)=>a+x[1],0),colors=['var(--arc-viz-1)','var(--arc-viz-2)','var(--arc-viz-3)','var(--arc-viz-4)','var(--arc-viz-5)'],cur=0;let stops=entries.map((x,i)=>{let start=cur;cur+=x[1]/total*100;return `${colors[i%colors.length]} ${start}% ${cur}%`}).join(',');$(id).style.background=`conic-gradient(${stops})`;$(legendId).innerHTML=entries.slice(0,5).map((x,i)=>`<div><span>${x[0]}</span><b>${Math.round(x[1]/total*100)}%</b></div>`).join('')}
function focusGlobalSearch(){const el=document.getElementById('arcSearchInput');if(el){el.focus();return}const alt=document.querySelector('#productSearch')||document.querySelector('#homeBarcode');showTab('products',null);setTimeout(()=>alt?.focus(),50)}
function renderDashboard(){window.ArchitectDashboard?.refresh()}
GamaArchive.register('products',()=>renderProducts(document.getElementById('productSearch')?.value||''));GamaPage.register('products',()=>renderProducts($('productSearch')?.value||''));

function renderForRoute(id){
 if(id==='products')renderProducts($('productSearch')?.value||'');
 else if(id==='billing')populateClientSelect();
}
function renderAll(){renderDashboard();renderForRoute(document.querySelector('section.active')?.id)}
showTab('mainmenu',null);
