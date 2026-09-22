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
function mapProduct(p){return window.ArcEntities.legacyProduct(p)}
function mapClient(c){return window.ArcEntities.legacyCustomer(c)}
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
function scheduleReload(event){if(event?.detail?.table)window.ArcData.invalidate(event.detail.table);if(reloadTimer)return;reloadTimer=setTimeout(()=>{reloadTimer=null;if(loading){scheduleReload();return}loadAll()},RELOAD_DEBOUNCE_MS)}
/* El espejo completo (productos, clientes, facturas, movimientos) sólo tiene
   sentido para el personal. Un perfil 'cliente' recibía cero filas por RLS,
   pero seguía lanzando seis consultas denegadas en cada arranque. */
function isStaffSession(){try{const s=JSON.parse(localStorage.getItem('gama_session_v1')||'null');return !!s&&['admin','administrador','commercial','comercial','magasinier','almacenero'].includes(s.role)}catch(e){return false}}
async function cachedList(table,options){return window.ArcData.all(table,options,true)}
const routeTables={products:['products','suppliers'],clients:['customers'],contacts:['customers'],movement:['products'],barcode:['products'],billing:['products','customers','invoices'],quotes:['products','customers']};
let dataEpoch=0,loadJobs=new Map();
async function loadAll(route=window.ArcRouter?.current){
 const tables=routeTables[route];if(!tables||!window.GamaCloud||!isStaffSession())return false;
 if(loadJobs.has(route))return loadJobs.get(route);
 const epoch=dataEpoch,started=performance.now();
 const job=(async()=>{loading=true;try{
  const values=await Promise.all(tables.map(async table=>{
   const options=table==='products'?{select:PRODUCT_COLUMNS,order:'name'}:table==='stock_movements'?{order:'created_at',ascending:false}:table==='invoices'?{order:'issue_date',ascending:false}:table==='profiles'?{select:'id,full_name',order:'id'}:{order:'name'};
   const result=await cachedList(table,options);if(result.error)throw result.error;return [table,result.data||[]];
  }));
  if(epoch!==dataEpoch)return false;
  const rows=Object.fromEntries(values);
  if(rows.profiles)profilesById=Object.fromEntries(rows.profiles.filter(x=>x.full_name).map(x=>[x.id,x.full_name]));
  if(rows.products){const all=rows.products.map(mapProduct);db.products=all.filter(x=>x.active!==false);db.archivedProducts=all.filter(x=>x.active===false)}
  if(rows.customers){const all=rows.customers.map(mapClient);db.clients=all.filter(x=>x.active!==false);db.archivedClients=all.filter(x=>x.active===false)}
  if(rows.suppliers){db.suppliers=rows.suppliers.filter(x=>x.active!==false);window.ArcEntities.suppliersCache=db.suppliers}
  if(rows.stock_movements)db.moves=rows.stock_movements.map(mapMove);
  if(rows.invoices){const ids=rows.invoices.map(i=>i.id),result=ids.length?await window.ArcData.byIds('invoice_lines','invoice_id',ids,{order:'id'},true):{data:[]};
   if(result.error)throw result.error;if(epoch!==dataEpoch)return false;
   const groups=new Map();for(const line of result.data||[]){if(!groups.has(line.invoice_id))groups.set(line.invoice_id,[]);groups.get(line.invoice_id).push(line)}
   db.invoices=rows.invoices.map(i=>mapInvoice(i,groups.get(i.id)||[]));
  }
  db.__cloud=true;ready=true;
  if(window.ArcRouter?.current===route)window.renderForRoute?.(route);
  window.dispatchEvent(new CustomEvent('architect:route-data-ready',{detail:{route,milliseconds:performance.now()-started,tables}}));
  return true;
 }catch(e){console.error('[GAMA CLOUD]',e);if(epoch===dataEpoch&&window.ArcRouter?.current===route)window.gamaToast?.(window.ArcErrors.message(e));return false}
 finally{loadJobs.delete(route);loading=loadJobs.size>0}})();loadJobs.set(route,job);return job;
}
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;dataEpoch++;loadJobs=new Map();loading=false;ready=false;profilesById={};for(const key of ['products','archivedProducts','clients','archivedClients','suppliers','moves','invoices'])db[key]=[];window.ArcEntities.suppliersCache=[];if(e.detail?.session)loadAll()});
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
async function createProductCloud(){const editingId=$('editingProductId')?.value,editing=$('editingBarcode')?.value,b=$('pBarcode')?.value.trim(),n=$('pName')?.value.trim();if(!b||!n)return alert('El código de barras y el nombre son obligatorios.');const old=editingId?db.products.find(p=>p.id===editingId):editing?db.products.find(p=>p.barcode===editing):null;if((editingId||editing)&&!old)return alert('Producto no encontrado.');if(!old&&db.products.some(p=>p.barcode===b))return alert('Este código de barras ya existe.');const duplicate=window.gamaProductDuplicate?.({name:n,barcode:b,ref:$('pRef').value.trim()},old);if(duplicate)return alert(duplicate);let photo=null;if($('pPhoto')?.files?.[0]&&window.compressPhoto)photo=await compressPhoto($('pPhoto').files[0]);const row={barcode:b,name:n,description:$('pDescription')?.value.trim()||null,reference:$('pRef').value.trim()||null,category:$('pCat').value.trim()||null,family:$('pFamily')?.value.trim()||null,lines:$('pLines')?.value.trim()||null,brand:$('pBrand')?.value.trim()||null,presentation:$('pPresentation')?.value.trim()||null,location:$('pLoc').value.trim()||null,supplier_id:$('pSupplier')?.value||null,min_stock:Number($('pMin').value)||0,max_stock:Number($('pMaxStock')?.value)||0,qty_per_carton:Number($('pQtyCarton')?.value)||0,weight_g:Number($('pWeight')?.value)||0,volume_cm3:Number($('pVolume')?.value)||0,sale_price:Number($('pPrice').value)||0,sale_price_b:Number($('pSalePriceB')?.value)||0,purchase_price:Number($('pCost')?.value)||0,tax_rate:Number($('pIva').value),active:true};
 /* photo_data solo viaja cuando el usuario acaba de elegir una imagen. Antes se
    reenviaba la foto vieja en cada edicion (150 kB por guardado) y, ahora que
    las listas ya no traen photo_data, mandarla en blanco habria borrado la foto
    del producto al cambiarle el precio. */
 if(photo)row.photo_data=photo;
 const r=old?await GamaCloud.update('products',old.id,row):await GamaCloud.insert('products',row);if(r.error){alert('No se pudo guardar el producto en la base central: '+r.error.message);return}if(photo&&window.GamaPhotos)GamaPhotos.seed(r.data?.id||old?.id,photo);
 clearProductForm();window.ArcData.invalidate();await loadAll();alert(old?'Producto actualizado en la base central.':'Producto creado en la base central.')}
async function saveClientCloud(){const terms=$('cPaymentTerms').value.trim();if(!/^\d+$/.test(terms)||Number(terms)>3650)return alert('Indica un plazo de pago entre 0 y 3650 días.');const name=$('cName').value.trim(),id=$('cId').value.trim(),editing=$('editingClientId').value;if(!name||!id)return alert('El nombre y la identificación son obligatorios.');const old=editing?db.clients.find(c=>c.cloudId===editing||c.id===editing):null;if(!old&&db.clients.some(c=>c.id===id))return alert('Ya existe un cliente con esta identificación.');const row={payment_terms_days:Number(terms),name,identification:id,address:$('cAddress').value.trim()||null,phone:$('cPhone').value.trim()||null,email:$('cEmail').value.trim()||null,city:$('cCity').value.trim()||null,province:$('cProvince').value.trim()||null,category:$('cCategory')?.value||'A',notes:$('cNotes').value.trim()||null,active:true};const r=old?await GamaCloud.update('customers',old.cloudId,row):await GamaCloud.insert('customers',row);if(r.error){alert('No se pudo guardar el cliente en la base central: '+r.error.message);return}clearClientForm();window.ArcData.invalidate('customers');await loadAll();window.dispatchEvent(new Event('gama:sales-change'));alert(old?'Cliente actualizado en la base central.':'Cliente guardado en la base central.')}
let movementPending=false,movementRequest=null;
async function registerMovementCloud(){if(movementPending)return;const code=($('moveBarcode').value||'').trim();let p=db.products.find(x=>x.barcode===code),unit=null;if(!p){try{unit=await window.ArchitectBarcode.lookup(code);if(unit.kind==='parcel')return alert('Este código identifica un bulto, no un producto.');p=db.products.find(x=>x.id===unit.product_id);if(!p){const r=await window.GamaCloud.list('products',{eq:{id:unit.product_id},limit:1});if(r.error)throw r.error;p=r.data?.[0]}}catch(e){return alert(window.ArcErrors.message(e))}}const quantity=Number($('moveQty').value),q=unit?.kind==='pack'?(await window.ArcData.rpc('gama_convert_unit',{p_product:p.id,p_unit:unit.unit_id,p_quantity:quantity})).base_quantity:quantity,type=$('moveType').value;if(!p)return alert('Producto no encontrado.');if(!Number.isFinite(q)||q<=0)return alert('Cantidad inválida.');const data={p_product_id:p.id,p_type:type==='IN'?'in':type==='OUT'?'out':'adjustment',p_quantity:q,p_reason:$('moveReason').value,p_comment:$('moveComment').value||null},signature=JSON.stringify(data);if(!movementRequest||movementRequest.signature!==signature)movementRequest={signature,key:crypto.randomUUID()};movementPending=true;try{await window.ArcData.rpc('gama_register_stock_movement_once',{p_request_key:movementRequest.key,p_data:data});movementRequest=null;$('moveQty').value='';$('moveInfo').textContent=p.name+' — movimiento registrado.';window.ArcData.invalidate();await loadAll()}catch(e){alert(window.ArcErrors.message(e));if(String(e.message).includes('ADJUSTMENT_APPROVAL_REQUIRED'))window.ArchitectStockControls.open()}finally{movementPending=false}}

/* Archivar en lugar de borrar: un producto facturado no se puede eliminar sin
   romper la trazabilidad, y ese era el error de clave ajena que veía el usuario. */
async function deleteProductCloud(b){const p=db.products.find(x=>x.barcode===b);if(!p)return;
 if(!confirm('¿Archivar «'+p.name+'»?\n\nDejará de aparecer en las listas y en la facturación, pero se conserva en la pestaña Archivados y en el historial.'))return;
 const r=await GamaCloud.update('products',p.id,{active:false});
 if(r.error)alert('No se pudo archivar: '+GamaArchive.friendlyError(r.error,'product'));else {window.ArcData.invalidate();await loadAll()}}
async function restoreProductCloud(id){const r=await GamaCloud.update('products',id,{active:true});if(r.error)alert('No se pudo restaurar: '+r.error.message);else {window.ArcData.invalidate();await loadAll()}}
async function purgeProductCloud(id){const p=(db.archivedProducts||[]).find(x=>x.id===id);if(!p)return;
 if(!confirm('¿Borrar definitivamente «'+p.name+'»?\n\nEsta accion no se puede deshacer. Solo es posible si el producto no aparece en ninguna factura, pedido ni movimiento de stock.'))return;
 const r=await GamaCloud.remove('products',id);
 if(r.error)alert(GamaArchive.friendlyError(r.error,'product'));else {window.ArcData.invalidate();await loadAll()}}
async function deleteClientCloud(id){const c=db.clients.find(x=>x.cloudId===id||x.id===id);if(!c)return;
 if(!confirm('¿Archivar a «'+c.name+'»?\n\nDejará de aparecer en las listas y en la facturación, pero se conserva en la pestaña Archivados y en sus facturas.'))return;
 const r=await GamaCloud.update('customers',c.cloudId,{active:false});
 if(r.error)alert('No se pudo archivar: '+GamaArchive.friendlyError(r.error,'client'));else {window.ArcData.invalidate();await loadAll()}}
async function restoreClientCloud(id){const r=await GamaCloud.update('customers',id,{active:true});if(r.error)alert('No se pudo restaurar: '+r.error.message);else {window.ArcData.invalidate();await loadAll()}}
async function purgeClientCloud(id){const c=(db.archivedClients||[]).find(x=>x.cloudId===id||x.id===id);if(!c)return;
 if(!confirm('¿Borrar definitivamente a «'+c.name+'»?\n\nEsta accion no se puede deshacer. Solo es posible si el cliente no tiene facturas ni solicitudes.'))return;
 const r=await GamaCloud.remove('customers',c.cloudId);
 if(r.error)alert(GamaArchive.friendlyError(r.error,'client'));else {window.ArcData.invalidate();await loadAll()}}
let legacyQuoteRequest=null;
async function generateInvoiceCloud(){
 if(!validateQuoteForm())return;
 const customer=db.clients.find(c=>c.id===$('clientId').value);if(!customer)return alert('Cliente no encontrado en Cloud.');
 const {rate}=quoteTotals();
 const payload={customer_id:customer.cloudId,lines:invoiceItems.map(x=>({product_id:x.p.id,quantity:x.q,unit_price:window.quoteLinePrice(x),tax_rate:rate})),notes:$('payment').value||null,details:{client:customer.name,clientId:customer.id,clientEmail:customer.email,clientAddress:customer.address,seller:$('sellerName').value,sellerRuc:$('sellerRuc').value}};
 const signature=JSON.stringify(payload);if(legacyQuoteRequest?.signature!==signature)legacyQuoteRequest={signature,key:crypto.randomUUID()};
 try{
  const result=await window.ArcData.rpc('gama_legacy_quote_save',{p_data:{...payload,request_key:legacyQuoteRequest.key}});
  finishQuote({id:result.id,number:result.number,date:result.date,clientId:customer.id,client:customer.name,clientEmail:customer.email,clientAddress:customer.address,seller:payload.details.seller,sellerRuc:payload.details.sellerRuc,items:quoteItemsSnapshot(),sub:result.subtotal,tax:result.tax,total:result.total,rate,pay:payload.notes});
  window.ArcData.invalidate('invoices');window.ArcData.invalidate('invoice_lines');await loadAll();
  alert('Presupuesto generado en la base central. Puedes imprimirlo o enviarlo por correo al cliente.');
 }catch(error){alert('No se pudo crear el presupuesto: '+window.ArcErrors.message(error));}
}

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
function populateClientSelectCloud(){const s=$('clientSelect');if(!s)return;const cur=s.value;window.ArcUI.render(s,'<option value="" data-gi=57780de4ab62>Selecciona un cliente...</option>'+db.clients.map(c=>`<option value="${c.id}">${c.name} — ${c.id}</option>`).join(''));if(cur&&db.clients.some(c=>c.id===cur))s.value=cur}
window.ArchitectLegacyData={load:loadAll};
async function boot(){if(window.__gamaCentralSyncBoot)return;window.__gamaCentralSyncBoot=true;while(!window.GamaCloud)await new Promise(r=>setTimeout(r,150));while(!window.GamaCloudReady)await new Promise(r=>setTimeout(r,150));try{await window.GamaCloudReady;for(const route of Object.keys(routeTables))window.ArcRouter.onEnter(route,()=>{loadAll(route)});if(routeTables[window.ArcRouter?.current])await loadAll();if(window.GamaCloudProducts){window.addEventListener('gama:products-cloud-change',scheduleReload);window.addEventListener('gama:stock-cloud-change',scheduleReload)}['customers','suppliers','invoices','invoice_lines'].forEach(table=>GamaCloud.subscribe(table,()=>{window.ArcData.invalidate(table);scheduleReload()}));window.save=function(){try{renderAll()}catch(e){}return true};window.createProduct=window.ArcUI.guard(createProductCloud);window.saveClient=window.ArcUI.guard(saveClientCloud);window.registerMovement=window.ArcUI.guard(registerMovementCloud);window.restoreProduct=restoreProductCloud;window.purgeProduct=purgeProductCloud;window.restoreClient=restoreClientCloud;window.purgeClient=purgeClientCloud;window.deleteProduct=deleteProductCloud;window.deleteClient=deleteClientCloud;window.generateInvoice=window.ArcUI.guard(generateInvoiceCloud);window.selectClientForInvoice=selectClientForInvoiceCloud;window.populateClientSelect=populateClientSelectCloud;window.ArcRouter.onEnter('billing',populateClientSelectCloud);document.body.dataset.dataSource='supabase-central';const badge=document.querySelector('.onlineBadge');if(badge)window.ArcUI.render(badge,'<i></i> Cloud • Tiempo real')}catch(e){console.error('[GAMA] central sync boot failed',e)}}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
