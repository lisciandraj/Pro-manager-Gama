/* GAMA V12 — centralized Supabase source of truth + Realtime mirror */
(function(){'use strict';
/* Este archivo se carga dos veces: con <script> desde index.html y de forma
   dinámica desde gama-access-control.js en cuanto GamaCloud está listo. Sin
   esta guarda se ejecutaban dos copias del módulo: boot() sólo corría en la
   primera (tiene su propio candado), pero las asignaciones a window de la
   segunda pisaban a las de la primera. Las dos copias no comparten estado, así
   que window.gamaPriceFor acababa leyendo el mapa de tarifas vacío de la copia
   que nunca cargó nada: el cliente con tarifa se presupuestaba a precio base.
   gama-supabase.js lleva la misma guarda por el mismo motivo. */
if(window.__gamaCentralSync)return;window.__gamaCentralSync=true;
const LOCAL_KEY='stock_manager_v6_ecuador';let ready=false,loading=false;let profilesById={};const $=id=>document.getElementById(id);
function localSnapshot(){try{return JSON.parse(localStorage.getItem(LOCAL_KEY)||'null')}catch(e){return null}}function clearLocalBusinessData(){try{localStorage.removeItem(LOCAL_KEY)}catch(e){}}function uid(){return JSON.parse(localStorage.getItem('gama_session_v1')||'{}').userId||null}
/* Nunca se pide photo_data en una lista: nueve fotos base64 pesan 1,4 MB y se
   descargaban enteras en cada recarga, mostrara o no fotos la pantalla. Basta
   con has_photo; la foto la trae GamaPhotos sólo para las filas visibles. */
const PRODUCT_COLUMNS='id,barcode,name,description,reference,category,family,lines,brand,presentation,location,supplier_id,min_stock,max_stock,qty_per_carton,weight_g,volume_cm3,stock,sale_price,sale_price_b,purchase_price,tax_rate,active,has_photo,created_at';
function mapProduct(p){return {id:p.id,barcode:p.barcode||'',name:p.name||'',description:p.description||'',ref:p.reference||'',cat:p.category||'',family:p.family||'',lines:p.lines||'',brand:p.brand||'',presentation:p.presentation||'',loc:p.location||'',supplierId:p.supplier_id||'',min:Number(p.min_stock||0),maxStock:Number(p.max_stock||0),qtyCarton:Number(p.qty_per_carton||0),weightG:Number(p.weight_g||0),volumeCm3:Number(p.volume_cm3||0),stock:Number(p.stock||0),price:Number(p.sale_price||0),salePriceB:Number(p.sale_price_b||0),purchase_price:Number(p.purchase_price||0),iva:Number(p.tax_rate??15),photo:p.photo_data||'',hasPhoto:p.photo_data?true:!!p.has_photo,active:p.active!==false}}
function mapClient(c){return {cloudId:c.id,category:c.category||'A',id:c.identification||'',name:c.name||'',idType:'RUC',address:c.address||'',phone:c.phone||'',email:c.email||'',city:c.city||'',province:c.province||'',notes:c.notes||'',active:c.active!==false}}
function userLabel(userId){if(!userId)return'Sistema';return profilesById[userId]||'Usuario desconocido'}
function mapMove(m){const p=db.products.find(x=>x.id===m.product_id);return {cloudId:m.id,id:m.id,date:m.created_at,type:(m.type==='in'?'IN':m.type==='out'?'OUT':'ADJUSTMENT'),barcode:p?.barcode||'',name:p?.name||'',qty:Number(m.quantity||0),user:userLabel(m.user_id),reason:m.reason||'',comment:m.comment||'',source:'Cloud',reference:'',stockBefore:m.stock_before===null||m.stock_before===undefined?null:Number(m.stock_before),stockAfter:m.stock_after===null||m.stock_after===undefined?null:Number(m.stock_after)}}
function mapInvoice(i,lines){const p=(lines||[]).map(l=>{const pr=db.products.find(x=>x.id===l.product_id);return {name:pr?.name||'',barcode:pr?.barcode||'',qty:Number(l.quantity),price:Number(l.unit_price)}});return {cloudId:i.id,id:i.id,number:i.invoice_number||'',date:i.issue_date,clientId:db.clients.find(c=>c.cloudId===i.customer_id)?.id||'',client:db.clients.find(c=>c.cloudId===i.customer_id)?.name||'',items:p,sub:Number(i.subtotal),tax:Number(i.tax),total:Number(i.total),rate:p.length?Number(lines[0]?.tax_rate||15):15,pay:(i.notes&&!i.notes.startsWith('GAMA_META:'))?i.notes:''}}
let reloadTimer=null;
/* Cada canal en tiempo real pedía su propia recarga completa: recibir un pedido
   de 5 líneas disparaba una decena de recargas de 7 tablas. Se agrupan en una.
   La ventana es de 1,5 s y no de 0,4 s: una recepción de mercancía o un
   presupuesto largo escriben varias filas seguidas, y con la ventana corta cada
   una arrastraba su propia recarga de siete tablas. Segundo y medio no se nota
   al usarlo y agrupa la ráfaga entera en una sola recarga. */
const RELOAD_DEBOUNCE_MS=1500;
function scheduleReload(){if(reloadTimer)return;reloadTimer=setTimeout(()=>{reloadTimer=null;if(loading){scheduleReload();return}loadAll()},RELOAD_DEBOUNCE_MS)}
/* El espejo completo (productos, clientes, facturas, movimientos) sólo tiene
   sentido para el personal. Un perfil 'cliente' recibía cero filas por RLS,
   pero seguía lanzando seis consultas denegadas en cada arranque. */
function isStaffSession(){try{const s=JSON.parse(localStorage.getItem('gama_session_v1')||'null');return !!s&&['admin','administrador','commercial','comercial','magasinier','almacenero'].includes(s.role)}catch(e){return false}}
async function loadAll(){if(!window.GamaCloud)return false;if(!isStaffSession())return false;loading=true;try{const [pr,cl,su,mv,iv,pf]=await Promise.all([GamaCloud.list('products',{select:PRODUCT_COLUMNS,order:'name',ascending:true}),GamaCloud.list('customers',{order:'name',ascending:true}),GamaCloud.list('suppliers',{order:'name',ascending:true}),GamaCloud.list('stock_movements',{order:'created_at',ascending:false}),GamaCloud.list('invoices',{order:'issue_date',ascending:false}),GamaCloud.list('profiles',{order:'created_at',ascending:true})]);if(pr.error||cl.error||su.error||mv.error||iv.error)throw(pr.error||cl.error||su.error||mv.error||iv.error);if(pf.error)console.warn('[GAMA CLOUD] profiles',pf.error);profilesById=Object.fromEntries((pf.data||[]).filter(x=>x.full_name).map(x=>[x.id,x.full_name]));const allP=(pr.data||[]).map(mapProduct),allC=(cl.data||[]).map(mapClient);db.products=allP.filter(x=>x.active!==false);db.archivedProducts=allP.filter(x=>x.active===false);db.clients=allC.filter(x=>x.active!==false);db.archivedClients=allC.filter(x=>x.active===false);db.suppliers=(su.data||[]).filter(x=>x.active!==false);db.moves=(mv.data||[]).map(mapMove);const invIds=(iv.data||[]).map(i=>i.id);const linesRes=invIds.length?await GamaCloud.list('invoice_lines',{in:{invoice_id:invIds},order:'id',ascending:true}):{data:[]};const linesByInvoice=new Map();(linesRes.data||[]).forEach(l=>{const k=String(l.invoice_id);if(!linesByInvoice.has(k))linesByInvoice.set(k,[]);linesByInvoice.get(k).push(l)});db.invoices=(iv.data||[]).map(i=>mapInvoice(i,linesByInvoice.get(String(i.id))||[]));db.__cloud=true;ready=true;clearLocalBusinessData();try{renderAll()}catch(e){}return true}catch(e){console.error('[GAMA CLOUD]',e);return false}finally{loading=false}}
async function migrateLocalOnce(){
 const snap=localSnapshot();if(!snap||snap.__migratedToCloud||(!snap.products?.length&&!snap.clients?.length&&!snap.moves?.length&&!snap.invoices?.length))return;
 const [pr,cl]=await Promise.all([GamaCloud.list('products',{select:'id',limit:1}),GamaCloud.list('customers',{select:'id',limit:1})]);if((pr.data||[]).length||(cl.data||[]).length)return;
 let productMap={},clientMap={};
 for(const p of snap.products||[]){try{const r=await GamaCloud.insert('products',{barcode:p.barcode||null,name:p.name,description:p.description||null,reference:p.ref||null,category:p.cat||null,family:p.family||null,lines:p.lines||null,brand:p.brand||null,presentation:p.presentation||null,location:p.loc||null,min_stock:Number(p.min||0),max_stock:Number(p.maxStock||0),qty_per_carton:Number(p.qtyCarton||0),weight_g:Number(p.weightG||0),volume_cm3:Number(p.volumeCm3||0),stock:Number(p.stock||0),sale_price:Number(p.price||0),sale_price_b:Number(p.salePriceB||0),purchase_price:Number(p.purchase_price||0),tax_rate:Number(p.iva??15),photo_data:p.photo||null,active:true});if(r.data)productMap[p.barcode]=r.data.id}catch(e){console.warn('Producto local no migrado',e)}}
 for(const c of snap.clients||[]){try{const r=await GamaCloud.insert('customers',{name:c.name,identification:c.id||null,address:c.address||null,city:c.city||null,province:c.province||null,phone:c.phone||null,email:c.email||null,category:c.category||'A',notes:c.notes||null,active:true});if(r.data)clientMap[c.id]=r.data.id}catch(e){console.warn('Cliente local no migrado',e)}}
 for(const m of snap.moves||[]){const pid=productMap[m.barcode];if(!pid)continue;try{await GamaCloud.insert('stock_movements',{product_id:pid,type:m.type==='IN'?'in':m.type==='OUT'?'out':'adjustment',quantity:Number(m.qty||0),reason:m.reason||null,comment:m.comment||null,user_id:uid()})}catch(e){console.warn('Movimiento local no migrado',e)}}
 for(const inv of snap.invoices||[]){try{const r=await GamaCloud.insert('invoices',{invoice_number:inv.number||inv.id||null,customer_id:clientMap[inv.clientId]||null,user_id:uid(),status:'issued',issue_date:inv.date||new Date().toISOString(),subtotal:Number(inv.sub||0),tax:Number(inv.tax||0),total:Number(inv.total||0),notes:inv.pay||null});if(r.data){for(const line of inv.items||[]){const pid=productMap[line.barcode];if(pid)await GamaCloud.insert('invoice_lines',{invoice_id:r.data.id,product_id:pid,quantity:Number(line.qty||0),unit_price:Number(line.price||0),tax_rate:Number(inv.rate||15),line_total:Number(line.qty||0)*Number(line.price||0)*(1+Number(inv.rate||15)/100)})}}}catch(e){console.warn('Factura local no migrada',e)}}
 try{localStorage.setItem(LOCAL_KEY,JSON.stringify({__migratedToCloud:true}))}catch(e){}
}
async function createProductCloud(){const editing=$('editingBarcode')?.value,b=$('pBarcode')?.value.trim(),n=$('pName')?.value.trim();if(!b||!n)return alert('El código de barras y el nombre son obligatorios.');if(!editing&&db.products.some(p=>p.barcode===b))return alert('Este código de barras ya existe.');const old=editing?db.products.find(p=>p.barcode===editing):null;let photo=null;if($('pPhoto')?.files?.[0]&&window.compressPhoto)photo=await compressPhoto($('pPhoto').files[0]);const row={barcode:b,name:n,description:$('pDescription')?.value.trim()||null,reference:$('pRef').value.trim()||null,category:$('pCat').value.trim()||null,family:$('pFamily')?.value.trim()||null,lines:$('pLines')?.value.trim()||null,brand:$('pBrand')?.value.trim()||null,presentation:$('pPresentation')?.value.trim()||null,location:$('pLoc').value.trim()||null,supplier_id:$('pSupplier')?.value||null,min_stock:Number($('pMin').value)||0,max_stock:Number($('pMaxStock')?.value)||0,qty_per_carton:Number($('pQtyCarton')?.value)||0,weight_g:Number($('pWeight')?.value)||0,volume_cm3:Number($('pVolume')?.value)||0,sale_price:Number($('pPrice').value)||0,sale_price_b:Number($('pSalePriceB')?.value)||0,purchase_price:Number($('pCost')?.value)||0,tax_rate:Number($('pIva').value),active:true};
 /* photo_data solo viaja cuando el usuario acaba de elegir una imagen. Antes se
    reenviaba la foto vieja en cada edicion (150 kB por guardado) y, ahora que
    las listas ya no traen photo_data, mandarla en blanco habria borrado la foto
    del producto al cambiarle el precio. */
 if(photo)row.photo_data=photo;
 const r=old?await GamaCloud.update('products',old.id,row):await GamaCloud.insert('products',row);if(r.error){alert('No se pudo guardar el producto en la base central: '+r.error.message);return}if(photo&&window.GamaPhotos)GamaPhotos.seed(r.data?.id||old?.id,photo);
 clearProductForm();await loadAll();alert(old?'Producto actualizado en la base central.':'Producto creado en la base central.')}
async function saveClientCloud(){const name=$('cName').value.trim(),id=$('cId').value.trim(),editing=$('editingClientId').value;if(!name||!id)return alert('El nombre y la identificación son obligatorios.');const old=editing?db.clients.find(c=>c.cloudId===editing||c.id===editing):null;if(!old&&db.clients.some(c=>c.id===id))return alert('Ya existe un cliente con esta identificación.');const row={name,identification:id,address:$('cAddress').value.trim()||null,phone:$('cPhone').value.trim()||null,email:$('cEmail').value.trim()||null,city:$('cCity').value.trim()||null,province:$('cProvince').value.trim()||null,category:$('cCategory')?.value||'A',notes:$('cNotes').value.trim()||null,active:true};const r=old?await GamaCloud.update('customers',old.cloudId,row):await GamaCloud.insert('customers',row);if(r.error){alert('No se pudo guardar el cliente en la base central: '+r.error.message);return}clearClientForm();await loadAll();alert(old?'Cliente actualizado en la base central.':'Cliente guardado en la base central.')}
async function registerMovementCloud(){const p=db.products.find(x=>x.barcode===($('moveBarcode').value||'').trim()),q=Number($('moveQty').value),type=$('moveType').value;if(!p)return alert('Producto no encontrado.');if(q<1)return alert('Cantidad inválida.');const c=await GamaCloud.db();const {error}=await c.rpc('gama_register_stock_movement',{p_product_id:p.id,p_type:type==='IN'?'in':type==='OUT'?'out':'adjustment',p_quantity:q,p_reason:$('moveReason').value,p_comment:$('moveComment').value||null});if(error){alert(error.message.includes('INSUFFICIENT_STOCK')?'Stock insuficiente.':('No se pudo registrar el movimiento: '+error.message));return}$('moveInfo').textContent=`${p.name} — movimiento registrado en Cloud.`;await loadAll();alert('Movimiento registrado y sincronizado para todos los usuarios.')}
async function createCorrectionCloud(){const b=prompt('Código de barras del producto a corregir:');if(!b)return;const p=db.products.find(x=>x.barcode===b);if(!p)return alert('Producto no encontrado.');const target=Number(prompt(`Stock actual: ${p.stock}. ¿Cuál debe ser el stock correcto?`));if(!Number.isFinite(target)||target<0)return alert('Valor inválido.');const delta=target-p.stock;if(delta===0)return alert('No hay diferencia de stock.');const comment=prompt('Motivo obligatorio de la corrección:')||'';if(!comment)return alert('La corrección requiere un comentario.');const c=await GamaCloud.db();const {error}=await c.rpc('gama_register_stock_movement',{p_product_id:p.id,p_type:'adjustment',p_quantity:delta,p_reason:'Corrección de inventario',p_comment:comment});if(error){alert('No se pudo registrar la corrección: '+error.message);return}await loadAll();alert('Corrección registrada centralmente y visible para todos los usuarios.')}
/* Archivar en lugar de borrar: un producto facturado no se puede eliminar sin
   romper la trazabilidad, y ese era el error de clave ajena que veía el usuario. */
async function deleteProductCloud(b){const p=db.products.find(x=>x.barcode===b);if(!p)return;
 if(!confirm('¿Archivar «'+p.name+'»?\n\nDejará de aparecer en las listas y en la facturación, pero se conserva en la pestaña Archivados y en el historial.'))return;
 const r=await GamaCloud.update('products',p.id,{active:false});
 if(r.error)alert('No se pudo archivar: '+GamaArchive.friendlyError(r.error,'product'));else await loadAll()}
async function restoreProductCloud(id){const r=await GamaCloud.update('products',id,{active:true});if(r.error)alert('No se pudo restaurar: '+r.error.message);else await loadAll()}
async function purgeProductCloud(id){const p=(db.archivedProducts||[]).find(x=>x.id===id);if(!p)return;
 if(!confirm('¿Borrar definitivamente «'+p.name+'»?\n\nEsta accion no se puede deshacer. Solo es posible si el producto no aparece en ninguna factura, pedido ni movimiento de stock.'))return;
 const r=await GamaCloud.remove('products',id);
 if(r.error)alert(GamaArchive.friendlyError(r.error,'product'));else await loadAll()}
async function deleteClientCloud(id){const c=db.clients.find(x=>x.cloudId===id||x.id===id);if(!c)return;
 if(!confirm('¿Archivar a «'+c.name+'»?\n\nDejará de aparecer en las listas y en la facturación, pero se conserva en la pestaña Archivados y en sus facturas.'))return;
 const r=await GamaCloud.update('customers',c.cloudId,{active:false});
 if(r.error)alert('No se pudo archivar: '+GamaArchive.friendlyError(r.error,'client'));else await loadAll()}
async function restoreClientCloud(id){const r=await GamaCloud.update('customers',id,{active:true});if(r.error)alert('No se pudo restaurar: '+r.error.message);else await loadAll()}
async function purgeClientCloud(id){const c=(db.archivedClients||[]).find(x=>x.cloudId===id||x.id===id);if(!c)return;
 if(!confirm('¿Borrar definitivamente a «'+c.name+'»?\n\nEsta accion no se puede deshacer. Solo es posible si el cliente no tiene facturas ni solicitudes.'))return;
 const r=await GamaCloud.remove('customers',c.cloudId);
 if(r.error)alert(GamaArchive.friendlyError(r.error,'client'));else await loadAll()}
async function generateInvoiceCloud(){if(!validateQuoteForm())return;const customer=db.clients.find(c=>c.id===$('clientId').value);if(!customer)return alert('Cliente no encontrado en Cloud.');const{sub,rate,tax,total}=quoteTotals(),number=quoteNumber(db.invoices?.length||0);const session=(await GamaCloud.getSession()).data.session;const inv=await GamaCloud.insert('invoices',{invoice_number:number,customer_id:customer.cloudId,user_id:session?.user?.id||null,status:'issued',issue_date:new Date().toISOString(),subtotal:sub,tax,total,notes:$('payment').value||null});if(inv.error){alert('No se pudo crear el presupuesto: '+inv.error.message);return}for(const x of invoiceItems){const line=await GamaCloud.insert('invoice_lines',{invoice_id:inv.data.id,product_id:x.p.id,quantity:x.q,unit_price:window.quoteLinePrice(x),tax_rate:rate,line_total:x.q*window.quoteLinePrice(x)*(1+rate/100)});if(line.error){alert('El presupuesto se creó pero una línea falló: '+line.error.message);return}}const localInv={id:inv.data.id,number,date:inv.data.issue_date,clientId:customer.id,client:customer.name,clientEmail:customer.email,clientAddress:customer.address,seller:$('sellerName').value,sellerRuc:$('sellerRuc').value,items:quoteItemsSnapshot(),sub,tax,total,rate,pay:$('payment').value};finishQuote(localInv);await loadAll();alert('Presupuesto generado en la base central. Puedes imprimirlo o enviarlo por correo al cliente.')}
/* Tarifas especiales: al elegir el cliente se cargan sus precios negociados.
   Sólo se guardan allí los productos cuyo precio se pactó aparte, así que lo
   que falte cae en el precio de la ficha según su categoría. */
let contractPrices={},contractCategory='A';
/* Categoría del cliente: A factura al precio mayorista de la ficha, B al
   precio al detalle y C al precio pactado en su tarifa. Un cliente C cae en
   el precio de la categoría A cuando el producto no está en su tarifa. */
window.gamaPriceFor=function(p){
 if(!p)return 0;
 const v=contractPrices[p.id];
 if(v!==undefined)return Number(v);
 return window.gamaCategoryPrice(p,contractCategory);
};
window.gamaHasContractPrice=function(p){return !!p&&contractPrices[p.id]!==undefined};
async function loadContractPrices(customerId){
 contractPrices={};
 if(!customerId)return;
 try{
  const r=await GamaCloud.list('customer_special_prices',{eq:{customer_id:customerId}});
  if(r.error)throw r.error;
  (r.data||[]).forEach(i=>{contractPrices[i.product_id]=Number(i.unit_price)});
 }catch(e){console.warn('[GAMA Tarifas] no se pudieron leer los precios negociados del cliente',e)}
}
async function selectClientForInvoiceCloud(){
 const c=db.clients.find(x=>x.id===$('clientSelect').value);
 $('clientId').value=c?c.id:'';$('clientName').value=c?c.name:'';
 $('clientAddress').value=c?c.address||'':'';$('clientEmail').value=c?c.email||'':'';
 contractCategory=c?c.category||'A':'A';
 await loadContractPrices(c&&contractCategory==='C'?c.cloudId:null);
 // Al cambiar de cliente se vuelve a valorar lo que ya esté en el presupuesto,
 // y se descartan los precios escritos a mano: una oferta se pactó con ESTE
 // cliente, arrastrarla al presupuesto de otro es un error que no se ve.
 window.gamaResetQuoteOverrides?.();
 if(typeof window.renderInvoiceItems==='function')window.renderInvoiceItems();
 const tag=$('quoteTariff');
 if(tag)tag.textContent=!c?'':contractCategory==='C'
  ?(Object.keys(contractPrices).length?'Categoría C · precios negociados aplicados':'Categoría C sin precios negociados: precio mayorista')
  :(contractCategory==='B'?'Categoría B · precio al detalle':'Categoría A · precio mayorista');
}
function populateClientSelectCloud(){const s=$('clientSelect');if(!s)return;const cur=s.value;s.innerHTML='<option value="">Selecciona un cliente...</option>'+db.clients.map(c=>`<option value="${c.id}">${c.name} — ${c.id}</option>`).join('');if(cur&&db.clients.some(c=>c.id===cur))s.value=cur}
async function boot(){if(window.__gamaCentralSyncBoot)return;window.__gamaCentralSyncBoot=true;while(!window.GamaCloud)await new Promise(r=>setTimeout(r,150));while(!window.GamaCloudReady)await new Promise(r=>setTimeout(r,150));try{await window.GamaCloudReady;await migrateLocalOnce();await loadAll();if(window.GamaCloudProducts){window.addEventListener('gama:products-cloud-change',scheduleReload);window.addEventListener('gama:stock-cloud-change',scheduleReload)}['customers','suppliers','invoices','invoice_lines'].forEach(table=>GamaCloud.subscribe(table,scheduleReload));window.save=function(){try{renderAll()}catch(e){}return true};window.createProduct=createProductCloud;window.saveClient=saveClientCloud;window.registerMovement=registerMovementCloud;window.createCorrection=createCorrectionCloud;window.restoreProduct=restoreProductCloud;window.purgeProduct=purgeProductCloud;window.restoreClient=restoreClientCloud;window.purgeClient=purgeClientCloud;window.deleteProduct=deleteProductCloud;window.deleteClient=deleteClientCloud;window.generateInvoice=generateInvoiceCloud;window.selectClientForInvoice=selectClientForInvoiceCloud;window.populateClientSelect=populateClientSelectCloud;const oldShowTab=window.showTab;window.showTab=function(id,btn){oldShowTab(id,btn);if(id==='billing')populateClientSelectCloud()};document.body.dataset.dataSource='supabase-central';const badge=document.querySelector('.onlineBadge');if(badge)badge.innerHTML='<i></i> Cloud • Tiempo real'}catch(e){console.error('[GAMA] central sync boot failed',e)}}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
