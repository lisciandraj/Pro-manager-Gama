/* Quote selection only: prices and availability remain server-owned. */
(function(){
'use strict';
const U=window.ArcUI,E=U.esc,T=s=>window.GamaI18n?.t?.(s)||s;
const rpc=(action,data)=>window.CocoSalesWorkspace.rpc(action,data);
const money=n=>window.ArcFormat.money(n);
const number=n=>Number(n).toLocaleString(window.GamaI18n?.getLanguage?.()||'es',{maximumFractionDigits:3});
let active=null;

function open({customerId,date,existingIds=[],isCurrent,onAdd}){
 if(active?.open)return active;
 if(!customerId)throw Error(T('Selecciona un cliente antes de abrir el catálogo.'));
 const excluded=new Set(existingIds),choices=new Map(),selected=new Map(),cards=new Map(),timers=new Map();
 const capacity=Math.max(0,200-excluded.size);
 let dialog,results=[],searchVersion=0,searchTimer,loading=false,committing=false,disposed=false;
 const current=()=>!disposed&&dialog?.open&&isCurrent();
 const ensureCurrent=()=>{if(!current())throw Error(T('El presupuesto cambió. Cierra el catálogo y vuelve a abrirlo.'))};
 const unit=c=>(c.product.units||[]).find(u=>u.id===c.unitId);
 function line(c){
  const u=unit(c),factor=Number(u?.factor||1),sold=Number(c.quantity),quantity=Math.round(sold*factor*1000)/1000;
  if(c.unitId&&!u)throw Error(T('El condicionamiento cambió. Revisa la selección.'));
  if(!Number.isFinite(factor)||factor<=0||!Number.isFinite(sold)||sold<=0||!Number.isFinite(quantity)||quantity<=0||
   (factor!==1&&!Number.isInteger(sold))||Math.abs(sold*factor-quantity)>0.0000001)
   throw Error(T('Revisa productos, cantidades, precios, descuentos e impuestos.'));
  return {product_id:c.product.id,description:c.product.name,quantity,sales_quantity:sold,
   sales_unit_id:u?.id||null,sales_unit_label:u?.label||c.product.base_unit||T('Unidad'),
   sales_unit_factor:factor,discount:0,tax_rate:Number(c.product.tax_rate||0),price_mode:'auto',price_reason:''};
 }
 function stock(c){
  if(c.product.product_kind==='service')return T('Servicio · sin control de stock');
  const available=c.product.available;
  if(available==null||!Number.isFinite(Number(available)))return T('Disponibilidad no informada');
  let label=T('Disponible sin reservar')+': '+number(available)+' '+(c.product.base_unit||T('Unidad'));
  try{if(selected.has(c.product.id)&&line(c).quantity>Number(available))label+=' · '+T('Cantidad superior al disponible');}catch{}
  return label;
 }
 function summary(){
  if(!dialog?.isConnected)return;
  dialog.querySelector('[data-catalog-summary]').textContent=T('Productos seleccionados')+': '+selected.size;
  dialog.querySelector('#cocoCatalogAdd').disabled=loading||committing||!selected.size;
 }
 function updateCard(c){
  const card=cards.get(c.product.id);if(!card)return;
  const chosen=selected.has(c.product.id),blocked=excluded.has(c.product.id);
  card.dataset.selected=String(chosen);
  const check=card.querySelector('[data-select]');check.checked=chosen;check.disabled=blocked||committing;
  card.querySelectorAll('select,input[type=number]').forEach(el=>el.disabled=!chosen||committing);
  card.querySelector('[data-stock]').textContent=stock(c);
  card.querySelector('[data-base]').textContent='';
  try{if(chosen){const l=line(c);card.querySelector('[data-base]').textContent=T('Cantidad de stock')+': '+number(l.quantity)+' '+(c.product.base_unit||T('Unidad'));}}catch{}
  card.querySelector('[data-price]').textContent=blocked?'':c.price==null?T(c.priceError?'Tarifa no disponible. Actualiza para reintentar.':'Calculando tarifa…'):T('Precio sin IVA')+': '+money(c.price*Number(unit(c)?.factor||1));
  card.querySelector('[data-source]').textContent=c.source||'';
 }
 async function priceEntries(entries){
  const batch=entries.filter(c=>!excluded.has(c.product.id)).map(c=>{
   c.price=null;c.source='';c.priceError=false;
   try{const l=line(c);updateCard(c);return {c,revision:++c.revision,line:l};}
   catch{c.priceError=true;updateCard(c);return null;}
  }).filter(Boolean);
  if(!batch.length)return;
  try{
   const prices=await rpc('prices',{customer_id:customerId,date,lines:batch.map(x=>({product_id:x.line.product_id,quantity:x.line.quantity}))});
   if(!current())return;
   batch.forEach((x,i)=>{
    if(x.c.revision!==x.revision)return;
    const p=prices?.[i],valid=p&&p.unit_price!=null&&Number.isFinite(Number(p.unit_price))&&Number(p.unit_price)>=0&&(!p.product_id||p.product_id===x.line.product_id);
    x.c.price=valid?Number(p.unit_price):null;x.c.priceError=!valid;x.c.source=valid?p.label||'':'';updateCard(x.c);
   });
  }catch{
   if(current())batch.forEach(x=>{if(x.c.revision===x.revision){x.c.price=null;x.c.priceError=true;updateCard(x.c);}});
  }
 }
 function schedulePrice(c){
  c.revision++;c.price=null;c.source='';c.priceError=false;clearTimeout(timers.get(c.product.id));
  updateCard(c);
  timers.set(c.product.id,setTimeout(()=>{timers.delete(c.product.id);if(current())priceEntries([c]);},250));
 }
 function draw(){
  if(!current())return;
  const shown=dialog.querySelector('#cocoCatalogSelected').checked?[...selected.values()]:results;
  const root=dialog.querySelector('[data-catalog-results]');cards.clear();
  U.render(root,shown.length?shown.map(c=>{
   const p=c.product,blocked=excluded.has(p.id),chosen=selected.has(p.id),factor=Number(unit(c)?.factor||1);
   return '<article class="cocoCatalogCard" data-product="'+E(p.id)+'" data-selected="'+chosen+'">'+
    '<label class="cocoCatalogChoice"><input type="checkbox" data-select '+(blocked?'disabled ':'')+(chosen?'checked':'')+'><span><strong>'+E(p.name)+'</strong><small>'+E(p.reference||p.barcode||'')+'</small></span></label>'+
    (blocked?'<p class="cocoCatalogExisting">'+E(T('Ya está en el presupuesto'))+'</p>':'')+
    '<p data-stock></p><div class="cocoCatalogFields"><label>'+E(T('Condicionamiento'))+'<select data-unit aria-label="'+E(T('Condicionamiento')+' · '+p.name)+'" '+(!chosen?'disabled':'')+'><option value="">'+E(p.base_unit||T('Unidad'))+'</option>'+
    (p.units||[]).map(u=>'<option value="'+E(u.id)+'" '+(u.id===c.unitId?'selected':'')+'>'+E(u.label)+' × '+number(u.factor)+'</option>').join('')+'</select></label>'+
    '<label>'+E(T('Cantidad'))+'<input type="number" data-quantity aria-label="'+E(T('Cantidad')+' · '+p.name)+'" value="'+E(c.quantity)+'" min="'+(factor===1?'0.001':'1')+'" step="'+(factor===1?'0.001':'1')+'" '+(!chosen?'disabled':'')+' required></label></div>'+
    '<small data-base></small><strong data-price></strong><small data-source></small></article>';
  }).join(''):'<p>'+E(T('No hay productos para esta búsqueda.'))+'</p>');
  root.querySelectorAll('[data-product]').forEach(card=>{
   const c=choices.get(card.dataset.product);cards.set(c.product.id,card);updateCard(c);
   card.querySelector('[data-select]').onchange=e=>{
    if(committing)return;
    if(e.target.checked){
     if(selected.size>=capacity){e.target.checked=false;dialog.querySelector('[role=alert]').textContent=T('El presupuesto admite hasta 200 productos.');return;}
     selected.set(c.product.id,c);
    }else selected.delete(c.product.id);
    updateCard(c);summary();
    if(dialog.querySelector('#cocoCatalogSelected').checked&&!e.target.checked)draw();
   };
   card.querySelector('[data-unit]').onchange=e=>{
    c.unitId=e.target.value;const factor=Number(unit(c)?.factor||1),input=card.querySelector('[data-quantity]');
    input.min=input.step=factor===1?'0.001':'1';schedulePrice(c);
   };
   card.querySelector('[data-quantity]').oninput=e=>{c.quantity=e.target.value;schedulePrice(c);};
  });
  summary();
 }
 async function search(){
  if(!current()||committing)return;
  const version=++searchVersion;loading=true;summary();
  const status=dialog.querySelector('[data-catalog-status]');status.textContent=T('Cargando productos…');
  dialog.querySelector('#cocoCatalogRefresh').disabled=true;
  try{
   const found=await rpc('lookups',{kind:'products',search:dialog.querySelector('#cocoCatalogSearch').value.trim()});
   if(!current()||version!==searchVersion)return;
   results=found.map(p=>{
    let c=choices.get(p.id);
    if(!c){c={product:p,unitId:'',quantity:1,price:null,priceError:false,revision:0};choices.set(p.id,c);}else c.product=p;
    return c;
   });
   draw();status.textContent=T('Hasta 30 resultados. Afina la búsqueda por nombre, referencia o código.');
   priceEntries(results);
  }catch(e){if(current()&&version===searchVersion)status.textContent=window.CocoSalesWorkspace.error(e);}
  finally{if(current()&&version===searchVersion){loading=false;dialog.querySelector('#cocoCatalogRefresh').disabled=false;summary();}}
 }
 async function add(){
  ensureCurrent();
  if(committing||!selected.size)throw Error(T('Selecciona al menos un producto.'));
  committing=true;clearTimeout(searchTimer);timers.forEach(clearTimeout);timers.clear();searchVersion++;
  const controls=[...dialog.querySelectorAll('input,select')],disabled=controls.map(el=>el.disabled);
  controls.forEach(el=>el.disabled=true);
  try{
   const batch=[...selected.values()];batch.forEach(c=>c.revision++);
   const fresh=await rpc('lookups',{kind:'products',ids:batch.map(c=>c.product.id)});
   ensureCurrent();
   const prepared=batch.map(c=>{
    const p=fresh.find(p=>p.id===c.product.id&&p.active!==false);
    if(!p)throw Error(T('Un producto ya no está disponible. Actualiza el catálogo.'));
    // Do not silently reinterpret a previously selected pack.
    const before=unit(c),after=(p.units||[]).find(u=>u.id===c.unitId);
    if(c.unitId&&(!after||Number(before?.factor)!==Number(after.factor)))throw Error(T('El condicionamiento cambió. Revisa la selección.'));
    const next={...c,product:p};return {product:p,line:line(next)};
   });
   const prices=await rpc('prices',{customer_id:customerId,date,lines:prepared.map(x=>({product_id:x.line.product_id,quantity:x.line.quantity}))});
   ensureCurrent();
   prepared.forEach((x,i)=>{
    const p=prices?.[i];
    if(!p||p.unit_price==null||!Number.isFinite(Number(p.unit_price))||Number(p.unit_price)<0||(p.product_id&&p.product_id!==x.line.product_id))
     throw Error(T('Tarifa no disponible. Actualiza para reintentar.'));
    x.line.list_price=Number(p.unit_price);x.line.price_source=p.label||'';
   });
   onAdd(prepared);
  }finally{
   committing=false;
   if(current())controls.forEach((el,i)=>el.disabled=disabled[i]);
  }
 }
 dialog=U.dialog({
  title:'Catálogo del presupuesto',saveLabel:'Añadir selección',className:'cocoQuoteCatalog',
  ids:{save:'cocoCatalogAdd',close:'cocoCatalogBack'},
  error:e=>T(window.CocoSalesWorkspace.error(e)),onSave:add,
  body:'<div data-gi-ignore><p>'+E(T('Precios del cliente y disponibilidad orientativa. El stock se reserva al confirmar el pedido.'))+'</p>'+
   '<div class="cocoCatalogTools"><label>'+E(T('Buscar producto, referencia o código…'))+'<input type="search" id="cocoCatalogSearch" maxlength="120"></label>'+
   '<button type="button" class="arcButton secondary" id="cocoCatalogRefresh">'+E(T('Actualizar'))+'</button></div>'+
   '<div class="cocoCatalogTools"><label class="cocoCatalogChoice"><input type="checkbox" id="cocoCatalogSelected">'+E(T('Ver selección'))+'</label><strong data-catalog-summary role="status"></strong></div>'+
   '<p data-catalog-status role="status"></p><div class="cocoCatalogGrid" data-catalog-results></div></div>'
 });
 active=dialog;
 dialog.querySelector('#cocoCatalogSearch').addEventListener('input',()=>{
  clearTimeout(searchTimer);searchVersion++;searchTimer=setTimeout(search,250);
 });
 dialog.querySelector('#cocoCatalogSearch').addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();clearTimeout(searchTimer);search();}});
 dialog.querySelector('#cocoCatalogRefresh').onclick=search;
 dialog.querySelector('#cocoCatalogSelected').onchange=draw;
 const close=()=>dialog.close(),auth=e=>{if(e.detail?.event!=='TOKEN_REFRESHED')close();};
 window.addEventListener('arc:route-change',close);window.addEventListener('gama:auth-change',auth);
 dialog.addEventListener('close',()=>{
  disposed=true;searchVersion++;clearTimeout(searchTimer);timers.forEach(clearTimeout);timers.clear();selected.clear();choices.clear();cards.clear();
  window.removeEventListener('arc:route-change',close);window.removeEventListener('gama:auth-change',auth);if(active===dialog)active=null;
 },{once:true});
 summary();search();dialog.querySelector('#cocoCatalogSearch').focus();
 return dialog;
}
window.CocoSalesCatalog={open};
})();
