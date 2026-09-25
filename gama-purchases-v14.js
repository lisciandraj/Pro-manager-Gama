/* GAMA V14 — Compras + pedidos a proveedores + recepción + inventario automático */
(function(){
  'use strict';
  const MOD='gamaPurchasesV14';
  let orders=[], lines=[], products=[], suppliers=[], almacenes=[], ubicaciones=[], needs=[];
  let loading=false, selectedId=null, draft=[], projectContext=null, projectSaveKey=null,savePending=false,saveRequest=null;
  /* De dónde nace la compra en preparación: es el paso 1 del proceso de compra
     (PDC). Alerta de stock bajo, pedido de cliente que supera el stock, o nada
     —creada a mano en este módulo—. */
  let draftSource=null;
  const esc=window.ArcUI.esc;
  const C=()=>window.GamaCloud;
  const $=id=>document.getElementById(id);
  const sessionRole=()=>{try{return JSON.parse(localStorage.getItem('gama_session_v1')||'{}').role||''}catch(e){return ''}};
  const canOrder=()=>['admin','commercial'].includes(sessionRole());
  const canReceive=()=>['admin','magasinier'].includes(sessionRole());
  const money=n=>window.GamaCurrency.format(n);
  const date=d=>d?new Date(d).toLocaleDateString('es-ES'):'';
  const roleLabel=r=>r==='admin'?'Administrador':r==='commercial'?'Comercial':r==='magasinier'?'Almacenero':'Usuario';
  const statusLabel=s=>({draft:'Borrador',sent:'Pedido realizado',partial:'Recepción parcial',received:'Recibido',cancelled:'Cancelado'}[s]||s);
  const statusClass=s=>({draft:'gp14Draft',sent:'gp14Sent',partial:'gp14Partial',received:'gp14Received',cancelled:'gp14Cancelled'}[s]||'gp14Draft');
  function wait(){if(!window.GamaCloud||!window.GamaCloudReady)return setTimeout(wait,250);window.GamaCloudReady.then(boot).catch(e=>console.warn('[GAMA Compras]',e));}
  function inject(){
    if($('gamaPurchasesV14'))return;
    const s=document.createElement('section');s.id='gamaPurchasesV14';window.ArcUI.render(s,`
      ${window.GamaUI.header({title:'Compras',lead:'Pedidos a proveedores y su recepción.'})}
      <div class="gp14Kpis"><div><span data-gi=d86393bc38de>Pedidos</span><b id="gp14KOrders">0</b></div><div><span data-gi=09a954033115>Pendientes de recepción</span><b id="gp14KToReceive">0</b></div><div><span data-gi=def9cc99530b>Recepciones parciales</span><b id="gp14KPartial">0</b></div><div><span data-gi=5f10af8ca856>Recibidos</span><b id="gp14KReceived">0</b></div><div><span data-gi=7d135440c86a>Total de compras</span><b id="gp14KTotal">${money(0)}</b></div></div>
      <div class="arcPanel card gp14LowStock" id="gp14LowStock" style="display:none"></div>
      <div class="gp14Grid"><div class="arcPanel card gp14Form"><div class="gp14Title"><h3 data-gi=78205ea91be9>Nuevo pedido a proveedor</h3><span class="gp14Role" id="gp14Role" data-gi-live></span></div>
      <label data-gi=1915a7e9a5eb>Proveedor *</label><select id="gp14Supplier"><option value="" data-gi=5c9d95219fe7>Seleccionar proveedor…</option></select>
      <div class="row"><div><label data-gi=6f6c5ef33af1>Fecha prevista</label><input id="gp14Expected" type="date"></div><div><label data-gi=693a35ea5e01>Referencia del proveedor</label><input id="gp14SupplierRef" data-gi-placeholder=7655681cefb5 placeholder="N.º de pedido del proveedor"></div></div>
      <label>Destino previsto</label><select id="gp14Destination"><option value="" data-gi=84ca335e8bfc>Sin asignar</option></select><label data-gi=ae0e47ca14d2>Producto *</label><select id="gp14Product"><option value="" data-gi=b9d4bce5023b>Seleccionar producto…</option></select>
      <div class="row"><div><label data-gi=8930e00fcc39>Cantidad</label><input id="gp14Qty" type="number" min="0.01" step="0.01" value="1"></div><div><label data-gi=9ac648bc383c>Precio de compra unitario</label><input id="gp14Cost" type="number" min="0" step="0.01" value="0"></div></div>
      <label>Impuesto (%)</label><input id="gp14Tax" type="number" min="0" max="100" step="0.001" value="0"><button class="arcButton secondary gp14Full" id="gp14Add" data-gi=f24e9be8c27d>Añadir producto</button><div id="gp14Draft" class="gp14DraftBox"></div>
      <label data-gi=8a6172e21a87>Notas</label><textarea id="gp14Notes" data-gi-placeholder=484929ff17db placeholder="Transporte, condiciones, información del proveedor…"></textarea>
      <div class="actions"><button class="arcButton secondary" id="gp14Clear" data-gi=d50a3d446835>Borrar</button><button class="arcButton primary" id="gp14Save" data-gi=a989ed08ba1e>Crear pedido</button></div><div id="gp14Msg" class="gp14Msg"></div></div>
      <div class="arcPanel card"><div class="gp14ListHead"><div><h3 data-gi=b48340d308cd>Pedidos a proveedores</h3><small data-gi=1f2ba6d43489>El inventario solo aumenta al registrar la recepción.</small></div><select id="gp14Filter"><option value="all" data-gi=bd02b9a7d71d>Todos</option><option value="draft" data-gi=9b7da456a008>Borradores</option><option value="sent" data-gi=b006f5eb5c3f>Pedidos realizados</option><option value="partial" data-gi=fda93bc9f790>Recepción parcial</option><option value="received" data-gi=5f10af8ca856>Recibidos</option><option value="cancelled" data-gi=a1b8dcdc807e>Cancelados</option></select></div><div id="gp14Orders"></div></div></div>
      <div class="arcPanel card gp14Detail" id="gp14Detail" style="display:none"></div>`);
    (document.querySelector('.wrap')||document.body).appendChild(s);style();bind();
  }
  function style(){ /* Styles are compiled in architect-components.css. */ }
  /* Al elegir un producto se rellena lo que la ficha ya sabe: su precio de
     compra y, si tiene proveedor asignado, ese proveedor. Es lo que se venía
     a escribir a mano, y escribirlo a mano es donde se cuela el pedido hecho
     al proveedor equivocado.

     Lo que NO hace es pisar un proveedor ya elegido cuando el pedido lleva
     líneas: un pedido es de UN proveedor, y a esas alturas cambiárselo por
     debajo movería de sitio lo que ya hay dentro. En ese caso sólo se avisa,
     que es lo que hace falta para darse cuenta. Con el pedido todavía vacío no
     hay nada que mover, así que se cambia sin ceremonia. */
  function productoElegido(){
   const p=products.find(x=>x.id===$('gp14Product').value);
   if(!p)return;
   $('gp14Cost').value=Number(p.purchase_price||0).toFixed(2);$('gp14Tax').value=Number(p.tax_rate||0);
   const ss=$('gp14Supplier'),sid=p.supplier_id;
   if(!ss||!sid)return;
   const prov=suppliers.find(x=>String(x.id)===String(sid)&&x.active!==false);
   /* Si su proveedor no está en la lista —archivado, o todavía sin sincronizar—
      no se toca nada: mejor el hueco vacío que un proveedor inventado. */
   if(!prov||!ss.querySelector('option[value="'+String(sid).replace(/"/g,'\\"')+'"]'))return;
   if(String(ss.value)===String(sid))return;
   if(ss.value&&draft.length)return msg('Ojo: «'+(p.name||'el producto')+'» es de '+prov.name+', y este pedido va a otro proveedor.');
   ss.value=sid;
   /* El change se lanza a mano porque asignar .value no lo dispara, y el
      buscador de la lista tiene que enseñar lo que acaba de elegirse. */
   ss.dispatchEvent(new Event('change',{bubbles:true}));
   if(!draft.length)msg('Proveedor puesto desde la ficha del producto: '+prov.name,true);
  }
  function bind(){window.GamaUI.bindBack($('gamaPurchasesV14'));$('gp14Filter').onchange=()=>{GamaPage.reset('purchaseOrders');renderOrders()};GamaPage.register('purchaseOrders',renderOrders);$('gp14Add').onclick=addDraft;$('gp14Save').onclick=saveOrder;$('gp14Clear').onclick=clearForm;$('gp14Product').onchange=productoElegido}
  async function show(){inject();window.ArcRouter.show('gamaPurchasesV14');const sec=$('gamaPurchasesV14');sec.classList.add('active');document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));await load();window.scrollTo({top:0,behavior:'smooth'})}
  window.gamaShowPurchases=show;
  window.gamaCreateProjectPurchase=async context=>{
   if(!canOrder()||!window.gamaAccessAllowed?.('projects'))return;
   await show();if(draft.length){msg(window.GamaProjects.t('purchase_draft_open'));return}clearForm();projectContext=context;projectSaveKey=crypto.randomUUID();
   let box=$('gp14ProjectContext');if(!box){box=document.createElement('div');box.id='gp14ProjectContext';box.className='pmPanel';document.querySelector('.gp14Form').prepend(box)}
   const t=window.GamaProjects.t;window.ArcUI.render(box,'<b>'+esc(context.project_name)+'</b><div class="pmForm"><label>'+esc(t('source_currency'))+'<input id="gp14ProjectCurrency" value="'+esc(context.currency)+'" maxlength="3" required></label><label>'+esc(t('exchange_rate'))+'<input id="gp14ProjectFx" type="number" min="0.000001" step="any" value="1" required></label></div>');box.hidden=false;
   document.querySelector('.gp14Form')?.scrollIntoView({behavior:'smooth'});
  };

  window.gamaOpenPurchaseDossier=async id=>{
   if(!window.gamaAccessAllowed?.('gamaPurchasesV14'))throw Error('Acceso no permitido.');
   await show();
   const [o,l]=await Promise.all([window.GamaCloud.list('purchase_orders',{eq:{id}}),window.GamaCloud.list('purchase_order_lines',{eq:{purchase_order_id:id}})]);
   if(o.error||l.error)throw o.error||l.error;if(!o.data?.[0])throw Error('Pedido no disponible.');
   orders=orders.filter(x=>x.id!==id).concat(o.data);lines=lines.filter(x=>x.purchase_order_id!==id).concat(l.data||[]);
   await openOrder(id);$('gp14Detail').scrollIntoView({behavior:'smooth'});
  };
  function installTab(){const host=document.querySelector('.tabs');if(!host||$('gamaPurchasesV14Tab'))return;const b=document.createElement('button');b.id='gamaPurchasesV14Tab';b.type='button';b.className='tab';window.ArcUI.render(b,'<span data-gi=1bc70818a30d>Compras</span>');b.onclick=show;host.appendChild(b)}
  function populate(){const dest=$('gp14Destination'),destination=dest.value;window.ArcUI.render(dest,'<option value="" data-gi=84ca335e8bfc>Sin asignar</option>'+ubicaciones.map(l=>'<option value="'+esc(l.id)+'">'+esc((almacenes.find(w=>w.id===l.warehouse_id)?.name||'')+' · '+l.code)+'</option>').join(''));dest.value=destination;const ss=$('gp14Supplier'),ps=$('gp14Product');if(!ss||!ps)return;window.ArcUI.render(ss,'<option value="" data-gi=5c9d95219fe7>Seleccionar proveedor…</option>'+suppliers.filter(x=>x.active!==false).map(x=>`<option value="${x.id}">${esc(x.name)}${x.tax_id?' — '+esc(x.tax_id):''}</option>`).join(''));window.ArcUI.render(ps,'<option value="" data-gi=b9d4bce5023b>Seleccionar producto…</option>'+products.filter(x=>x.active!==false).map(x=>`<option value="${x.id}">${esc(x.name)}${x.barcode?' — '+esc(x.barcode):''}</option>`).join(''));$('gp14Role').textContent=roleLabel(sessionRole())}
  function addDraft(){if(!canOrder())return alert('Tu perfil no puede crear pedidos a proveedores.');const pid=$('gp14Product').value,q=Number($('gp14Qty').value),cost=Number($('gp14Cost').value),tax=Number($('gp14Tax').value);if(!Number.isFinite(tax)||tax<0||tax>100)return alert('Impuesto inválido.');if(!pid||!Number.isFinite(q)||q<=0||!Number.isFinite(cost)||cost<0)return alert('El producto, la cantidad y el precio de compra son obligatorios.');const p=products.find(x=>x.id===pid);const old=draft.find(x=>x.product_id===pid);if(old){old.quantity+=q;old.unit_cost=cost;old.tax_rate=tax}else draft.push({product_id:pid,quantity:q,unit_cost:cost,tax_rate:tax});renderDraft();$('gp14Product').value='';$('gp14Qty').value='1';$('gp14Cost').value=p?Number(p.purchase_price||0).toFixed(2):'0'}
  function renderDraft(){const h=$('gp14Draft');if(!draft.length){window.ArcUI.render(h,'<div class="muted" data-gi=e708556f30d1>No hay productos en el pedido.</div>');return}window.ArcUI.render(h,draft.map((l,i)=>{const p=products.find(x=>x.id===l.product_id);return `<div class="gp14DraftLine"><div><b>${esc(p?.name||'Producto')}</b><small>${esc(p?.reference||p?.barcode||'')}</small></div><span>${l.quantity}</span><span>${money(l.quantity*l.unit_cost*(1+Number(l.tax_rate||0)/100))}<small>${Number(l.tax_rate||0)}%</small></span><button class="arcButton gp14X" onclick="window.gamaRemovePurchaseLineV14(${i})">×</button></div>`}).join(''))}
  window.gamaRemovePurchaseLineV14=i=>{draft.splice(i,1);renderDraft()};

  async function saveOrder(){
   if(savePending||!canOrder())return;
   let sid=$('gp14Supplier').value;if(!sid)return alert('Selecciona un proveedor.');
   if(!draft.length)return alert('Añade al menos un producto.');
   savePending=true;$('gp14Save').disabled=true;
   try{
    if(sid.startsWith('legacy:')){sid=await window.gamaResolveSupplierId?.(sid);if(!sid)throw Error('No se pudo sincronizar el proveedor.');$('gp14Supplier').value=sid}
    const payload={supplier_id:sid,expected_date:$('gp14Expected').value?$('gp14Expected').value+'T12:00:00':null,destination_location_id:$('gp14Destination').value||null,
     notes:[$('gp14SupplierRef').value.trim()?('Ref. proveedor: '+$('gp14SupplierRef').value.trim()):'',$('gp14Notes').value.trim()].filter(Boolean).join(' | ')||null,
     lines:draft.map(l=>({...l}))};
    const signature=JSON.stringify(payload);if(saveRequest?.signature!==signature)saveRequest={signature,key:crypto.randomUUID()};
    let saved;
    if(projectContext){saved=await window.GamaProjects.rpc('create_purchase',{...payload,project_id:projectContext.project_id,id:projectContext.item_id,request_key:projectSaveKey,currency:$('gp14ProjectCurrency').value.toUpperCase(),exchange_rate:Number($('gp14ProjectFx').value)},true)}
    else saved=await window.ArcData.rpc('gama_purchase_save',{p_data:{...payload,source_kind:draftSource?.kind||'manual',source_order_id:draftSource?.order_id||null,request_key:saveRequest.key}});
    clearForm();await load();msg('Pedido creado. El inventario no cambia hasta la recepción.',true);
    if(saved.purchase_id)await openOrder(saved.purchase_id);
   }catch(e){msg(window.ArcErrors.message(e))}
   finally{savePending=false;$('gp14Save').disabled=false}
  }
  function msg(t,ok){const m=$('gp14Msg');m.textContent=t;m.className='gp14Msg '+(ok?'gp14Ok':'')}
  function clearForm(){saveRequest=null;$('gp14Destination').value='';$('gp14Tax').value='0';projectContext=null;projectSaveKey=null;if($('gp14ProjectContext')){$('gp14ProjectContext').hidden=true;$('gp14ProjectContext').replaceChildren()}$('gp14Supplier').value='';$('gp14Expected').value='';$('gp14SupplierRef').value='';$('gp14Product').value='';$('gp14Qty').value='1';$('gp14Cost').value='0';$('gp14Notes').value='';draft=[];draftSource=null;renderDraft();msg('')}
  /* Las columnas se piden una por una y no con «*». products guarda la foto de
     cada artículo en base64, y esta pantalla se carga en el ARRANQUE de la
     aplicación: pedirlas todas descargaría el catálogo de fotos entero cada vez
     que alguien abre GAMA, sin enseñar ni una. Aquí sólo hacen falta éstas.
     Antes no se notaba porque la llamada ni siquiera existía —se caía—, así que
     arreglarla destapó el problema; lo cazó tests/egress-photos.spec.js. */
  const PRODUCT_COLS='id,name,reference,barcode,purchase_price,stock,min_stock,active,supplier_id,tax_rate';
  /* list() y no select(): window.GamaCloud nunca ha tenido un select(). Esta
     pantalla llamaba a uno inexistente y se caía entera con «C().select is not
     a function» antes de pintar un solo pedido. El doble de las pruebas sí
     ofrecía ese método, así que ninguna prueba lo vio venir; ya no lo ofrece. */
  /* Sin permiso para pedir ni para recibir, esta pantalla no se carga. No es
     sólo ahorro: boot() llama a load() al arrancar la aplicación, así que una
     cuenta de CLIENTE pedía la tabla de productos con sus precios de compra,
     los proveedores y los pedidos. La base los deniega —las políticas son la
     frontera de verdad—, pero pedirlos siquiera es lo que esta mitad del
     límite existe para impedir, y es lo que cazó tests/security-boundaries. */
  /* Almacenes y ubicaciones son opcionales: si la migración de Inventario V2
     todavía no está aplicada, las consultas fallan, `ubicaciones` se queda
     vacío y la recepción sigue funcionando igual que antes —la RPC mete la
     mercancía en la ubicación por defecto. Una pantalla de compras no puede
     dejar de recibir porque falte una tabla nueva. */
  async function loadUbicaciones(){
    try{
      const [w,l]=await Promise.all([
        C().list('warehouses',{select:'id,code,name,active'}),
        C().list('warehouse_locations',{select:'id,warehouse_id,code,name,type,active,role'})]);
      if(w.error||l.error){almacenes=[];ubicaciones=[];return}
      almacenes=(w.data||[]).filter(x=>x.active!==false);
      ubicaciones=(l.data||[]).filter(x=>x.active!==false);
    }catch(e){almacenes=[];ubicaciones=[]}
  }
  async function load(){if(loading||!C()||!(canOrder()||canReceive()))return;loading=true;try{const [a,b,c,d,n]=await Promise.all([window.ArcData.all('purchase_orders'),window.ArcData.all('purchase_order_lines'),window.ArcData.all('products',{select:PRODUCT_COLS}),window.ArcData.all('suppliers',{select:'id,name,tax_id,email,active'}),canOrder()?window.ArcData.all('replenishment_needs',{order:'product_id',ascending:true}):Promise.resolve({data:[]})]);if(a.error)throw a.error;orders=a.data||[];lines=b.data||[];products=c.data||[];suppliers=d.data||[];needs=n.error?[]:(n.data||[]).filter(x=>Number(x.suggested_purchase)>0);await loadUbicaciones();populate();renderOrders();renderKpis();renderLowStock()}catch(e){console.warn('[GAMA Compras]',e);const m=$('gp14Msg');if(m)m.textContent='No se han podido cargar los datos: '+(e.message||e)}finally{loading=false}}
  function ubicacionPorDefecto(){
    const w=almacenes.find(x=>x.code==='PRINCIPAL');
    // Lo recibido entra por la zona de llegada del almacén principal (antes, la raíz STOCK).
    const u=w&&(ubicaciones.find(x=>x.warehouse_id===w.id&&x.role==='arrival')||ubicaciones.find(x=>x.warehouse_id===w.id&&x.code==='STOCK'));
    return u?u.id:((ubicaciones[0]||{}).id||'');
  }
  /* El desplegable de destino, agrupado por almacén. Se ofrece sólo si hay
     ubicaciones que ofrecer. */
  function selectorUbicacion(habilitado){
    if(!ubicaciones.length)return '';
    const porDefecto=ubicacionPorDefecto();
    const grupos=almacenes.map(w=>{
      const hijas=ubicaciones.filter(u=>u.warehouse_id===w.id);
      if(!hijas.length)return '';
      return `<optgroup label="${esc(w.name||w.code)}">`+hijas.map(u=>
        `<option value="${u.id}"${u.id===porDefecto?' selected':''}>${esc(u.code)}${u.name?' — '+esc(u.name):''}</option>`).join('')+'</optgroup>';
    }).join('');
    const sueltas=ubicaciones.filter(u=>!almacenes.some(w=>w.id===u.warehouse_id))
      .map(u=>`<option value="${u.id}"${u.id===porDefecto?' selected':''}>${esc(u.code)}</option>`).join('');
    return `<label for="gp14RecvUbicacion" data-gi=f56e6693ce83>Recibir en</label><select id="gp14RecvUbicacion" ${habilitado?'':'disabled'}>${grupos}${sueltas}</select>`;
  }
  function renderLowStock(){const host=$('gp14LowStock');if(!host)return;const low=needs;if(!low.length){host.style.display='none';window.ArcUI.render(host,'');return}host.style.display='block';const groups=new Map();low.forEach(n=>{const key=n.supplier_id||'__none';if(!groups.has(key))groups.set(key,[]);groups.get(key).push(n)});const cards=[...groups.entries()].map(([sid,items])=>{const name=sid==='__none'?'Sin proveedor asignado':supplierName(sid);const rows=items.map(n=>`<div class="gp14LowRow"><div><b>${esc(n.name)}</b><small>${esc(n.reference||'')} · Físico ${numPurchase(n.on_hand)} · Reservado ${numPurchase(n.reserved)} · Demanda ${numPurchase(n.sales_demand)} · Entrante ${numPurchase(n.incoming)}</small></div><span>Disp. ${numPurchase(n.available)}</span><span><b>+${numPurchase(n.suggested_purchase)}</b></span></div>`).join('');const canAct=sid!=='__none';return `<div class="gp14LowGroup"><div class="gp14LowGroupHead"><b>${esc(name)}</b>${canAct&&canOrder()?`<button class="arcButton secondary" type="button" onclick="window.gamaAddLowStockGroup('${esc(sid)}')" data-gi=23cba326fe88>Preparar pedido</button>`:canAct?'':'<span class="muted" data-gi=9c95809f22c9>Asigna un proveedor en Productos</span>'}</div>${rows}</div>`}).join('');window.ArcUI.render(host,`<div class="gp14LowGroupHead"><div><h3>Necesidades de aprovisionamiento — ${low.length}</h3><p class="muted" data-gi=8d4fd632a8e0>Produits sous le stock minimum : quantité proposée pour revenir au stock maximum, en tenant compte des réservations, de la demande et des achats déjà en route.</p></div>${canOrder()&&[...groups.keys()].some(x=>x!=='__none')?'<button class="arcButton primary" type="button" onclick="window.gamaCreateAllReplenishmentDrafts()">Créer les commandes pré-remplies</button>':''}</div>${cards}`)}
  const numPurchase=n=>Number(n||0).toLocaleString('es-EC',{maximumFractionDigits:3});
  window.gamaPrepareSupplierOffer=async o=>{if(!canOrder())throw Error('ROLE_NOT_ALLOWED');await load();window.ArcRouter.show('gamaPurchasesV14');if(draft.length&&!confirm('¿Reemplazar el borrador actual?'))return;const p=products.find(p=>p.id===o.product_id);if(!p)throw Error('PRODUCT_NOT_FOUND');$('gp14Supplier').value=o.supplier_id;draftSource=null;draft=[{product_id:o.product_id,quantity:o.ordered,unit_cost:Number(o.unit_cost),tax_rate:Number(p.tax_rate||0)}];const date=new Date();date.setDate(date.getDate()+Number(o.lead_time_days));if($('gp14Expected'))$('gp14Expected').value=date.toISOString().slice(0,10);renderDraft()};
  window.gamaPrepareActionPurchase=async ({order_id,product_id})=>{
   if(!canOrder()||!window.gamaAccessAllowed?.('gamaPurchasesV14'))throw Error('Tu perfil no permite preparar compras.');
   await show();if(draft.length)throw Error('Ya tienes una compra en preparación. Guárdala o vacíala antes de preparar otra.');
   const result=await C().list('replenishment_needs');if(result.error)throw result.error;
   let ids=product_id?[product_id]:[];
   if(order_id){const o=await C().list('sales_orders',{eq:{id:order_id}});if(o.error)throw o.error;if(o.data?.[0]?.status!=='confirmed')throw Error('El pedido ya no está confirmado.');const ls=await C().list('sales_order_lines',{eq:{order_id}});if(ls.error)throw ls.error;ids=(ls.data||[]).map(l=>l.product_id)}
   const candidates=(result.data||[]).filter(n=>ids.includes(n.product_id)&&Number(n.suggested_purchase)>0);
   if(!candidates.length)throw Error('No hay compra adicional pendiente: revisa las existencias y las compras en camino.');
   const groups=[...new Set(candidates.map(n=>n.supplier_id).filter(id=>id&&suppliers.some(s=>s.id===id&&s.active!==false)))];
   if(!groups.length)throw Error('Asigna un proveedor a estos productos en Productos antes de crear la compra.');
   window.GamaSales.modal('Preparar compra',`<p data-gi=776b07bb30c1>Necesidades actuales de los productos del dossier, descontando compras en camino. Revisa las cantidades antes de guardar.</p>${candidates.some(n=>!n.supplier_id)?'<p data-gi=b235194cf12d>Hay productos sin proveedor: asígnalo en Productos para comprarlos.</p>':''}<label data-gi=e746643f4479>Proveedor<select id="gpActionSupplier">${groups.map(id=>`<option value="${esc(id)}">${esc(supplierName(id))}</option>`).join('')}</select></label>`,'Preparar',async el=>{
    if(draft.length)throw Error('Ya existe una compra en preparación.');
    const sid=el.querySelector('#gpActionSupplier').value;
    const fresh=await C().list('replenishment_needs');if(fresh.error)throw fresh.error;
    const selected=(fresh.data||[]).filter(n=>ids.includes(n.product_id)&&n.supplier_id===sid&&Number(n.suggested_purchase)>0);
    if(!selected.length)throw Error('La necesidad cambió. Actualiza el centro de acción.');
    const ps=await C().list('products',{select:PRODUCT_COLS,in:{id:selected.map(n=>n.product_id)}});if(ps.error)throw ps.error;
    for(const p of ps.data||[])if(!products.some(x=>x.id===p.id))products.push(p);
    if(selected.some(n=>!products.some(p=>p.id===n.product_id)))throw Error('No se pudieron cargar todos los productos.');
    $('gp14Supplier').value=sid;if($('gp14Supplier').value!==sid)throw Error('El proveedor no está disponible. Actualiza Compras.');draft=selected.map(n=>({product_id:n.product_id,quantity:Number(n.suggested_purchase),unit_cost:Number(products.find(p=>p.id===n.product_id).purchase_price||0)}));draftSource=order_id?{kind:'sales_order',order_id}:{kind:'low_stock'};renderDraft();msg('Compra preparada. Revisa las cantidades y guarda el pedido.',true);document.querySelector('.gp14Form')?.scrollIntoView({behavior:'smooth',block:'start'});
   });
  };
  window.gamaCreateAllReplenishmentDrafts=async function(){
    if(!canOrder())return alert('Tu perfil no puede crear pedidos a proveedores.');
    const actionable=needs.filter(n=>n.supplier_id&&Number(n.suggested_purchase)>0&&suppliers.some(s=>s.id===n.supplier_id&&s.active!==false));
    if(!actionable.length)return alert('No hay necesidades con proveedor asignado.');
    const groups=new Map();actionable.forEach(n=>{if(!groups.has(n.supplier_id))groups.set(n.supplier_id,[]);groups.get(n.supplier_id).push(n)});
    const missing=needs.filter(n=>!n.supplier_id&&Number(n.suggested_purchase)>0).length;
    if(!confirm('Crear '+groups.size+' pedido(s) borrador pre-rellenado(s) por proveedor para '+actionable.length+' producto(s)?'+(missing?' '+missing+' producto(s) sin proveedor quedarán pendientes.':'')))return;
    let created=0,failed=0;
    for(const [sid,items] of groups){
      try{
        const fresh=await C().list('replenishment_needs');if(fresh.error)throw fresh.error;
        const wanted=new Set(items.map(x=>x.product_id));
        const selected=(fresh.data||[]).filter(n=>wanted.has(n.product_id)&&n.supplier_id===sid&&Number(n.suggested_purchase)>0);
        if(!selected.length)continue;
        const payload={supplier_id:sid,expected_date:null,destination_location_id:ubicacionPorDefecto()||null,
          notes:'Réapprovisionnement automatique : stock sous minimum → stock maximum.',
          source_kind:'low_stock',source_order_id:null,request_key:crypto.randomUUID(),
          lines:selected.map(n=>{const p=products.find(x=>x.id===n.product_id);return {product_id:n.product_id,quantity:Number(n.suggested_purchase),unit_cost:Number(p?.purchase_price||0),tax_rate:Number(p?.tax_rate||0)}})};
        const saved=await window.ArcData.rpc('gama_purchase_save',{p_data:payload});
        if(!saved?.purchase_id)throw Error('PURCHASE_NOT_CREATED');created++;
      }catch(e){console.error('[Coco replenishment]',sid,e);failed++}
    }
    await load();
    msg(created+' commande(s) fournisseur créée(s) en brouillon, pré-remplie(s) jusqu’au stock maximum.'+(failed?' '+failed+' échec(s).':'')+(missing?' '+missing+' produit(s) sans fournisseur non inclus.':''),failed===0);
  };
  window.gamaAddLowStockGroup=function(sid){if(!canOrder())return alert('Tu perfil no puede crear pedidos a proveedores.');const selected=needs.filter(n=>n.supplier_id===sid);if(!selected.length)return;if(!draftSource)draftSource={kind:'low_stock'};$('gp14Supplier').value=sid;selected.forEach(n=>{const p=products.find(x=>x.id===n.product_id);if(!p)return;const suggest=Number(n.suggested_purchase);const existing=draft.find(x=>x.product_id===p.id);if(existing)existing.quantity=Math.max(existing.quantity,suggest);else draft.push({product_id:p.id,quantity:suggest,unit_cost:Number(p.purchase_price||0)})});renderDraft();msg(selected.length>1?'Se prepararon '+selected.length+' productos según la necesidad calculada.':'Se preparó 1 producto según la necesidad calculada.',true);document.querySelector('.gp14Form')?.scrollIntoView({behavior:'smooth',block:'start'})};
  function supplierName(id){return suppliers.find(x=>x.id===id)?.name||'Proveedor'}
  function renderKpis(){const active=orders.filter(o=>o.status!=='cancelled');$('gp14KOrders').textContent=active.length;$('gp14KToReceive').textContent=active.filter(o=>['sent','partial'].includes(o.status)).length;$('gp14KPartial').textContent=active.filter(o=>o.status==='partial').length;$('gp14KReceived').textContent=active.filter(o=>o.status==='received').length;$('gp14KTotal').textContent=money(active.reduce((a,o)=>a+Number(o.total||0),0))}
  function renderOrders(){const h=$('gp14Orders');if(!h)return;const f=$('gp14Filter')?.value||'all';const arr=orders.filter(o=>f==='all'||o.status===f).sort((a,b)=>new Date(b.order_date)-new Date(a.order_date));if(!arr.length){window.ArcUI.render(h,'<div class="muted" style="padding:20px 0" data-gi=828814d36c0a>No hay pedidos para mostrar.</div>');return}window.ArcUI.render(h,GamaPage.slice('purchaseOrders',arr).map(o=>{const ls=lines.filter(l=>l.purchase_order_id===o.id);const qty=ls.reduce((a,l)=>a+Number(l.quantity||0),0),rec=ls.reduce((a,l)=>a+Number(l.received_quantity||0),0);return `<div class="gp14Order" onclick="window.gamaOpenPurchaseV14('${o.id}')"><div class="gp14OrderTop"><b>${esc(o.order_number)}</b><span class="gp14Status ${statusClass(o.status)}" data-gi-live>${statusLabel(o.status)}</span></div><div class="gp14Meta"><span>${esc(supplierName(o.supplier_id))}</span><span>${rec}/${qty} · ${money(o.total)}</span></div><div class="gp14Meta"><span><span data-gi=916801fe1ea1>Pedido: </span>${date(o.order_date)}</span><span><span data-gi=f5573964a548>Previsto: </span>${date(o.expected_date)}</span></div></div>`}).join('')+GamaPage.controls('purchaseOrders',arr.length))}
  window.gamaOpenPurchaseV14=openOrder;
  async function openOrder(id){selectedId=id;const o=orders.find(x=>x.id===id);if(!o)return;const ls=lines.filter(x=>x.purchase_order_id===id);const d=$('gp14Detail');d.style.display='block';const canRecv=canReceive()&&['sent','partial'].includes(o.status);const allReceived=ls.length>0&&ls.every(l=>Number(l.received_quantity)>=Number(l.quantity));window.ArcUI.render(d,`<div class="gp14DetailHead"><div><h3><span data-gi=9e9ea5774a2d>Pedido </span>${esc(o.order_number)}</h3><div class="muted">${esc(supplierName(o.supplier_id))} · <span data-gi-live>${statusLabel(o.status)}</span></div></div><button class="arcButton secondary" onclick="window.gamaClosePurchaseV14()" data-gi=aeccae342e4b>Cerrar</button></div><div class="gp14Info">${o.status==='draft'?'Al enviar el pedido se prepara un correo con el PDF adjunto para el proveedor y el pedido pasa a estado «Pedido realizado».<br><span data-gi=3a3337679779>':''}Una recepción validada crea automáticamente un movimiento de </span><b data-gi=b40b2944d0e8>Entrada</b>, aumenta el inventario y registra el precio de compra.${ubicaciones.length?' La mercancía entra en la ubicación que elijas abajo.':''}</div>${ls.map(l=>{const p=products.find(x=>x.id===l.product_id);const pending=Math.max(0,Number(l.quantity)-Number(l.received_quantity));return `<div class="gp14ReceiveLine"><div><b>${esc(p?.name||'Producto')}</b><small><span data-gi=916801fe1ea1>Pedido: </span>${l.quantity} · Recibido: ${l.received_quantity} · Pendiente: ${pending}</small></div><span>${money(l.unit_cost)}</span><span>${pending?'<input id="gp14Recv_'+l.id+'" type="number" min="0" max="'+pending+'" step="0.01" value="'+pending+'" '+(canRecv?'':'disabled')+'>':'<span class="gp14Status gp14Received" data-gi=23e3685fbe6c>Completo</span>'}</span><span>${money(Number(l.quantity)*Number(l.unit_cost))}</span></div>`}).join('')}${o.notes?`<div class="gp14Warn">${esc(o.notes)}</div>`:''}${canRecv?selectorUbicacion(true):''}<label data-gi=59b6c0ea5e7b>Comentario de recepción</label><textarea id="gp14ReceiveComment" data-gi-placeholder=c64dd7b6130a placeholder="Albarán, lote, transporte, incidencia…" ${canRecv?'':'disabled'}></textarea><div class="gp14Actions">${o.status==='draft'&&canOrder()?`<button class="arcButton primary" onclick="window.gamaSendPurchaseV14('${o.id}')" data-gi=79563c6e5003>Enviar pedido por correo</button><button class="arcButton secondary" onclick="window.gamaDownloadPurchaseV14('${o.id}')" data-gi=59e0b6ca6f89>Descargar PDF</button>`:''}${canRecv?`<button class="arcButton success" onclick="window.gamaReceivePurchaseV14('${o.id}')" data-gi=e6de47c3a5db>Registrar recepción</button>`:''}${o.status==='sent'&&canOrder()?`<button class="arcButton danger" onclick="window.gamaCancelPurchaseV14('${o.id}')" data-gi=9f98a45211d0>Cancelar pedido</button>`:''}${ls.some(l=>Number(l.received_quantity)>0)?`<button class="arcButton secondary" onclick="window.GamaReturns?.createFrom('supplier','${o.id}')" data-gi-live data-gi=5f1f857a6a73>Crear una devolución</button>`:''}${allReceived?'<span class="gp14Locked" data-gi=b30ad6797230>Todas las cantidades ya han sido recibidas.</span>':''}</div><div id="gp14DetailMsg" class="gp14Msg"></div>`);if(o.destination_location_id&&$('gp14RecvUbicacion'))$('gp14RecvUbicacion').value=o.destination_location_id}
  window.gamaClosePurchaseV14=()=>{selectedId=null;$('gp14Detail').style.display='none'};
  /* Arma el pedido tal y como lo espera el generador de PDF. Lo usan tanto el
     envío por correo como la descarga: si cada uno armara el suyo, acabarían
     enseñando cosas distintas. */
  function orderForPdf(o){
    const ls=lines.filter(x=>x.purchase_order_id===o.id);
    const supplier=suppliers.find(s=>s.id===o.supplier_id)||{};
    const dateLabel=o.order_date?new Date(o.order_date).toLocaleDateString('es-EC'):'';
    const expectedLabel=o.expected_date?new Date(o.expected_date).toLocaleDateString('es-EC'):'';
    return {number:o.order_number,dateLabel,expectedLabel,supplier:supplier.name||'',
      supplierEmail:supplier.email||'',supplierPhone:supplier.phone||'',supplierAddress:supplier.address||'',
      items:ls.map(l=>{const p=products.find(x=>x.id===l.product_id)||{};
        return {name:p.name||'',qty:Number(l.quantity||0),cost:Number(l.unit_cost||0)}}),
      total:Number(o.total||0),notes:o.notes||''};
  }
  async function downloadOrder(id){
    const o=orders.find(x=>x.id===id);if(!o)return;
    if(!window.GamaPurchaseOrderPdf||!window.GamaPdf)return detailMsg('El generador de PDF no está disponible. Recarga la aplicación.');
    try{
      await window.GamaCompany?.load(true);
      const doc=window.GamaPurchaseOrderPdf.build(orderForPdf(o));
      window.GamaPdf.save(doc,window.GamaPdf.fileName('pedido',o.order_number));
    }catch(e){console.error('[GAMA PDF pedido]',e);detailMsg('No se pudo generar el PDF: '+(e&&e.message||e))}
  }
  async function sendOrder(id){
    if(!canOrder())return alert('Tu perfil no puede cambiar el estado de los pedidos.');
    const o=orders.find(x=>x.id===id);if(!o||o.status!=='draft')return;
    const supplier=suppliers.find(x=>x.id===o.supplier_id);if(!supplier)return detailMsg('Proveedor no encontrado.');
    const ls=lines.filter(x=>x.purchase_order_id===id);
    const dateLabel=date(o.order_date),expectedLabel=o.expected_date?date(o.expected_date):'';
    const items=ls.map(l=>{const p=products.find(x=>x.id===l.product_id);return{name:p?.name||'Producto',reference:p?.reference||p?.barcode||'',qty:Number(l.quantity||0),cost:Number(l.unit_cost||0)}});
    const itemLines=items.map(x=>`- ${x.name} x${x.qty} — ${GamaCurrency.format(x.cost)} c/u — ${GamaCurrency.format(x.qty*x.cost)}`).join('\n');
    const body=`Estimado/a ${supplier.name},\n\nLe solicitamos el siguiente pedido:\n\nN.º de pedido: ${o.order_number}\nFecha: ${dateLabel}${expectedLabel?`\nFecha prevista: ${expectedLabel}`:''}\n\n${itemLines}\n\nTOTAL estimado: ${GamaCurrency.format(o.total)}\n\n${o.notes?o.notes+'\n\n':''}Quedamos atentos a su confirmación.\n\nGAMA Enterprise Resource Planning`;
    const orderPdf={number:o.order_number,dateLabel,expectedLabel,supplier:supplier.name,supplierEmail:supplier.email||'',supplierPhone:supplier.phone||'',supplierAddress:supplier.address||'',items,total:Number(o.total||0),notes:o.notes||''};
    if(!supplier.email)detailMsg('Este proveedor no tiene un correo registrado: complétalo manualmente al enviar.');
    await window.GamaPurchaseOrderPdf.send({o:orderPdf,email:supplier.email||'',subject:'Pedido '+o.order_number+' — Coco ERP',body,filename:'Pedido-'+o.order_number+'.pdf'});
    const r=await C().update('purchase_orders',id,{status:'sent',updated_at:new Date().toISOString()});
    if(r.error)return detailMsg('El correo se preparó, pero no se pudo actualizar el estado del pedido: '+r.error.message);
    await load();
    if(selectedId===id){await openOrder(id);detailMsg('Correo del pedido preparado y pedido marcado como realizado.',true)}
  }
  window.gamaDownloadPurchaseV14=downloadOrder;window.gamaSendPurchaseV14=sendOrder;
  async function cancelOrder(id){if(!canOrder())return alert('Tu perfil no puede cancelar pedidos.');if(!confirm('¿Cancelar este pedido a proveedor?'))return;const o=orders.find(x=>x.id===id);if(!o||o.status!=='sent')return;const r=await C().update('purchase_orders',id,{status:'cancelled',updated_at:new Date().toISOString()});if(r.error)return detailMsg('No se pudo cancelar el pedido: '+r.error.message);await load()} window.gamaCancelPurchaseV14=cancelOrder;
  function detailMsg(t,ok){const m=$('gp14DetailMsg');if(!m)return;m.textContent=t;m.className='gp14Msg '+(ok?'gp14Ok':'')}
  const receiptCommands=new Map();
  async function receive(id){if(!canReceive())return alert('Tu perfil no puede registrar recepciones.');const o=orders.find(x=>x.id===id);if(!o||!['sent','partial'].includes(o.status))return;const ls=lines.filter(x=>x.purchase_order_id===id);const destino=$('gp14RecvUbicacion')?.value||'';const payload=[];for(const l of ls){const pending=Math.max(0,Number(l.quantity)-Number(l.received_quantity));if(!pending)continue;const input=$('gp14Recv_'+l.id);const q=Number(input?.value||0);if(q<0||q>pending)return detailMsg('Una cantidad recibida no es válida.');if(q>0)payload.push(destino?{line_id:l.id,quantity:q,location_id:destino}:{line_id:l.id,quantity:q})}if(!payload.length)return detailMsg('Introduce al menos una cantidad para recibir.');const comment=$('gp14ReceiveComment')?.value.trim()||null;const client=await C().db();const data={purchase_order_id:id,lines:payload,comment},sig=JSON.stringify(data);let command=receiptCommands.get(id);if(command?.sig!==sig){command={sig,key:crypto.randomUUID()};receiptCommands.set(id,command)}const r=await window.ArcData.rawRpc('gama_receive_purchase_once',{p_data:{...data,request_key:command.key}});if(r.error){detailMsg(mapRpcError(r.error.message));return}receiptCommands.delete(id);await load();if(selectedId===id){await openOrder(id);detailMsg('Recepción registrada. Stock actualizado para los artículos; realización registrada para los servicios.',true)}}
  window.gamaReceivePurchaseV14=receive;
  function mapRpcError(e){const m=String(e||'');if(m.includes('RECEIPT_EXCEEDS_ORDERED'))return 'La cantidad recibida supera la cantidad pedida.';if(m.includes('PURCHASE_ORDER_CANCELLED'))return 'Este pedido está cancelado.';if(m.includes('FORBIDDEN'))return 'Tu perfil no tiene permiso para registrar recepciones.';if(m.includes('PURCHASE_ORDER_NOT_FOUND'))return 'Pedido no encontrado.';return 'No se ha podido registrar la recepción: '+m}
  window.addEventListener('gama:auth-change',()=>{receiptCommands.clear();projectContext=null;projectSaveKey=null;draft=[];draftSource=null;$('gp14ProjectContext')?.remove()});
  function subscribe(){['purchase_orders','purchase_order_lines','stock_movements','products'].forEach(t=>{try{C().subscribe(t,()=>{if(!loading&&$('gamaPurchasesV14')?.classList.contains('active'))load()})}catch(e){}})}
  async function boot(){if(window[MOD])return;window[MOD]=true;try{inject();installTab();subscribe()}catch(e){console.warn('[GAMA Compras V14]',e)}}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',wait,{once:true});else wait();
})();
