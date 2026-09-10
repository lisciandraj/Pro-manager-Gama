/* GAMA — Catálogo de productos */
(function(){'use strict';
const C=()=>window.GamaCloud,$=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=v=>Number(v||0).toLocaleString('es-EC',{style:'currency',currency:'USD',minimumFractionDigits:2,maximumFractionDigits:2});
let cart=[],products=[],favorites=[];
function isClient(){try{return JSON.parse(localStorage.getItem('gama_session_v1')||'null')?.role==='client'}catch(_){return false}}
function inject(){if($('gamaClientCatalogStyle'))return;const s=document.createElement('style');s.id='gamaClientCatalogStyle';s.textContent=`#client-catalog{display:none}#client-catalog.active{display:block}.cc{background:#fff;border:1px solid #E2E8EC;border-radius:16px;padding:16px;box-shadow:0 3px 16px #1732460d}.ccTools{display:flex;gap:9px;align-items:center;margin:16px 0;flex-wrap:wrap}.ccTools input{flex:1 1 260px;min-width:0;width:auto}.ccTools select{flex:0 0 auto;width:240px;min-width:0;padding:11px;border-radius:10px;border:1px solid #d4e0e4}.ccTools .badge{flex:0 0 auto;white-space:nowrap}
/* La ficha del catálogo es la única pantalla que ve un cliente, así que se
   parece a lo que un cliente conoce: foto, de qué es, qué lleva, y el precio
   con y sin IVA —que en una compra entre empresas es la cifra que se compara—.
   Lo que se enseña sale de la vista catalog_products y de nada más: esa vista
   esconde a propósito el precio de compra, el proveedor y la ubicación. */
.ccGrid{display:grid;grid-template-columns:1fr;gap:12px}
.ccProduct{display:grid;grid-template-columns:180px 1fr 220px;grid-template-areas:'media info precio' 'acciones acciones acciones';gap:8px 20px;border:1px solid #E2E8EC;border-radius:14px;padding:16px 18px;background:#fff;box-shadow:0 1px 2px #1732460a;transition:box-shadow .12s ease,border-color .12s ease}
.ccProduct:hover{border-color:#CBD9E0;box-shadow:0 2px 4px #1732460f,0 10px 24px #17324612}
.ccMedia{grid-area:media;position:relative;display:grid;place-items:center}
.ccProduct img,.ccNoImg{width:100%;height:150px;object-fit:contain;border-radius:10px;background:#F7F9FA}
.ccNoImg{display:grid;place-items:center;font-size:42px}
.ccFlag{position:absolute;top:6px;left:6px;background:#E8F5F6;color:#087C8B;border-radius:999px;padding:3px 9px;font-size:10px;font-weight:850}
.ccInfo{grid-area:info;min-width:0}
.ccProduct h3{font-size:17px;margin:0 0 3px;line-height:1.25;color:#173246}
.ccMeta{font-size:11.5px;color:#71808A}
.ccPuntos{list-style:none;margin:10px 0 0;padding:0;font-size:13px;color:#4E5F6B;line-height:1.5}
.ccPuntos li{position:relative;padding-left:15px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.ccPuntos li:before{content:'';position:absolute;left:3px;top:9px;width:5px;height:5px;border-radius:50%;background:#9FB3BE}
.ccStock{display:inline-block;margin-top:10px;font-size:11px;font-weight:800;border-radius:999px;padding:4px 10px;background:#E7F6F0;color:#0F7A5B}
.ccStock.bajo{background:#FFF3E6;color:#9E5B14}
.ccStock.agotado{background:#F1F4F6;color:#6D7D88}
.ccPrecio{grid-area:precio;text-align:right;align-self:start}
.ccPrecio b{display:block;font-size:23px;font-weight:900;color:#173246;letter-spacing:-.4px;line-height:1.15}
.ccPrecio b span{font-size:12.5px;font-weight:750;color:#5C6B76;letter-spacing:0}
.ccPrecioIva{font-size:13px;color:#71808A;margin-top:2px}
.ccPrecio small{display:block;font-size:11px;color:#8A98A2;margin-top:5px}
.ccAcciones{grid-area:acciones;display:flex;gap:10px;align-items:center;margin-top:12px;padding-top:13px;border-top:1px solid #EDF1F3}
.ccAdd{flex:1;background:#F47A2A;color:#fff;font-weight:800;font-size:14px;border-radius:10px;padding:13px;display:flex;align-items:center;justify-content:center;gap:8px}
.ccAdd:hover:not(:disabled){background:#E06D20}
.ccAdd.dentro{background:#0F7A5B}
.ccAdd.dentro:hover:not(:disabled){background:#0C6549}
.ccQty{display:grid;grid-template-columns:42px 62px 42px;gap:0;flex:0 0 auto;border:1px solid #D4E0E4;border-radius:10px;overflow:hidden}
.ccQty button{background:#fff;color:#173246;border-radius:0;font-size:17px;padding:11px 0}
.ccQty button:hover{background:#EEF3F4}
.ccQty input{text-align:center;border:0;border-left:1px solid #D4E0E4;border-right:1px solid #D4E0E4;border-radius:0;font-size:15px;font-weight:700;padding:11px 0}
.ccQty input:focus{box-shadow:none;outline:2px solid #087C8B;outline-offset:-2px}.ccCartQty{grid-template-columns:32px 1fr 32px;gap:4px}.ccCartQty button{padding:6px 0;font-size:14px}.ccCartQty input{padding:6px 2px;font-size:13px}.ccCartRow small{display:block;color:#7b8992;font-size:11px;margin-top:2px}.ccCart{margin-top:18px;border:1px solid #E2E8EC;border-radius:14px;background:#F8FAFB;padding:14px}.ccCartHead{display:flex;justify-content:space-between;align-items:center}.ccCartHead h3{margin:0}.ccCartRow{display:grid;grid-template-columns:1fr 122px 85px 32px;gap:8px;align-items:center;padding:8px 0;border-bottom:1px solid #E2E8EC;font-size:12px}.ccCartRow:last-child{border-bottom:0}
.ccResumen{margin:12px 0 4px;padding-top:11px;border-top:1px solid #E2E8EC;font-size:13px}
.ccResumen div{display:flex;justify-content:space-between;padding:4px 0;color:#5C6B76}
.ccResumen b{color:#173246}
.ccResumenTotal{margin-top:4px;padding-top:8px!important;border-top:1px solid #E2E8EC;font-size:15px;font-weight:800;color:#173246}
.ccResumenTotal b{font-size:17px;color:#087C8B}.ccDel{background:#FFF0EC;color:#C94F45;padding:6px}.ccMsg{margin-top:8px;font-size:12px;font-weight:700}.ccOk{color:#138A69}.ccErr{color:#C94F45}.ccFav{margin-top:14px;border:1px solid #E2E8EC;border-radius:14px;background:#fff;padding:14px}.ccFavHead{display:flex;justify-content:space-between;align-items:center}.ccFavHead h3{margin:0;font-size:15px}.ccFavRow{display:flex;justify-content:space-between;align-items:center;gap:8px;padding:8px 0;border-bottom:1px solid #EDF1F2;font-size:12px}.ccFavRow:last-child{border-bottom:0}.ccFavActions{display:flex;gap:6px}@media(max-width:820px){
 .ccProduct{grid-template-columns:120px 1fr;grid-template-areas:'media info' 'precio precio' 'acciones acciones';gap:6px 14px;padding:14px}
 .ccProduct img,.ccNoImg{height:104px}
 .ccProduct h3{font-size:15px}
 .ccPrecio{text-align:left;margin-top:10px}
 .ccPrecio b{font-size:20px}
 .ccPuntos{font-size:12.5px;margin-top:8px}
}
@media(max-width:560px){
 /* En el teléfono, las cuatro columnas del pedido dejaban el nombre en una
    tira de 100px: «Cemento Portland tipo I saco de 50 kg» salía en cuatro
    líneas. Se parte en dos filas — nombre arriba, contador y total debajo. */
 .ccCartRow{grid-template-columns:1fr auto auto;grid-template-areas:'nombre nombre borrar' 'contador total total';gap:7px 9px;padding:11px 0}
 .ccCartRow>:nth-child(1){grid-area:nombre}
 .ccCartRow>:nth-child(2){grid-area:contador;justify-self:start}
 .ccCartRow .ccCartQty{grid-template-columns:34px 56px 34px}
 .ccCartRow>:nth-child(3){grid-area:total;align-self:center;text-align:right;font-weight:800;font-size:14px}
 .ccCartRow>:nth-child(4){grid-area:borrar}
 .ccTools{flex-direction:column;align-items:stretch}/* En columna, el flex-basis es la ALTURA: sin esto el buscador se estiraba a 260px de alto. */
 .ccTools input,.ccTools select{flex:0 0 auto;width:100%}.ccQty{grid-template-columns:38px 52px 38px}}`;document.head.appendChild(s)}
function ensureUI(){inject();let sec=$('client-catalog');if(!sec){sec=document.createElement('section');sec.id='client-catalog';(document.querySelector('.wrap')||document.body).appendChild(sec)}if(sec.dataset.ready)return;sec.dataset.ready='1';sec.innerHTML=`${window.GamaUI.header({title:'🛍️ Catálogo de productos',lead:'Elija sus productos y envíe el pedido a GAMA.'})}<div class="cc"><div class="ccTools"><input id="ccSearch" placeholder="Buscar un producto…"><select id="ccCategory"><option value="">Todas las categorías</option></select><span class="badge" id="ccCount">0 productos</span></div><div class="muted" id="ccStatus"><span class="gamaSpin"></span>Cargando…</div><div class="ccGrid" id="ccProducts"></div><div class="ccFav" id="ccFav"><div class="ccFavHead"><h3>⭐ Mis pedidos favoritos</h3></div><div id="ccFavRows" class="muted">Sin favoritos guardados.</div></div><div class="ccCart"><div class="ccCartHead"><h3>🛒 Mi pedido</h3><b id="ccTotal">$0,00</b></div><div id="ccCartRows" style="margin:8px 0"><span class="muted">Su pedido está vacío.</span></div><div class="ccResumen"><div><span>Subtotal sin IVA</span><b id="ccNeto">$0,00</b></div><div><span>IVA</span><b id="ccIva">$0,00</b></div><div class="ccResumenTotal"><span>Total con IVA</span><b id="ccBruto">$0,00</b></div></div><textarea id="ccNotes" placeholder="Comentario o indicación para el pedido…"></textarea><button class="primary" id="ccSend" style="width:100%;margin-top:9px">Enviar pedido</button><button class="secondary" id="ccSaveFav" style="width:100%;margin-top:8px">☆ Guardar como favorito</button><div id="ccMsg" class="ccMsg"></div></div></div>`;window.GamaUI.bindBack(sec);$('ccSearch').oninput=()=>{GamaPage.reset('catalog');render()};$('ccCategory').onchange=()=>{GamaPage.reset('catalog');render()};GamaPage.register('catalog',render);$('ccSend').onclick=send;$('ccSaveFav').onclick=saveFavorite}
function populateCategorySelect(){const s=$('ccCategory');if(!s)return;const cur=s.value;const cats=[...new Set(products.map(p=>(p.category||'').trim()).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'es'));s.innerHTML='<option value="">Todas las categorías</option>'+cats.map(c=>`<option value="${esc(c)}">${esc(c)}</option>`).join('');if(cur&&cats.includes(cur))s.value=cur}
async function load(){ensureUI();$('ccStatus').innerHTML='<span class="gamaSpin"></span>Cargando productos desde la base de datos…';try{const r=await C().list('catalog_products',{select:'id,name,reference,barcode,category,sale_price,base_price,contract_price,tax_rate,stock,has_photo,active',order:'name',ascending:true});if(r.error)throw r.error;products=(r.data||[]).filter(p=>p.active!==false);$('ccCount').textContent=products.length+' producto'+(products.length>1?'s':'');$('ccStatus').textContent='Catálogo sincronizado.';populateCategorySelect();render()}catch(e){console.error('[GAMA Catalog]',e);$('ccStatus').textContent='Error de carga: '+(e.message||e)}loadFavorites()}
async function loadFavorites(){try{const sr=await C().getSession(),uid=sr?.data?.session?.user?.id;if(!uid)return;const fr=await C().list('favorite_orders',{eq:{created_by:uid},order:'created_at',ascending:false});if(fr.error)throw fr.error;favorites=fr.data||[];renderFavorites()}catch(e){console.error('[GAMA Catalog favorites]',e)}}
function renderFavorites(){const host=$('ccFavRows');if(!host)return;host.innerHTML=favorites.length?favorites.map(f=>`<div class="ccFavRow"><b>${esc(f.name)}</b><span class="ccFavActions"><button class="secondary" data-fav-load="${f.id}">Cargar</button><button class="ccDel" data-fav-del="${f.id}">×</button></span></div>`).join(''):'<div class="muted">Sin favoritos guardados.</div>';host.querySelectorAll('[data-fav-load]').forEach(b=>b.onclick=()=>loadFavorite(b.dataset.favLoad));host.querySelectorAll('[data-fav-del]').forEach(b=>b.onclick=()=>deleteFavorite(b.dataset.favDel))}
async function loadFavorite(id){const m=$('ccMsg');m.className='ccMsg';try{const lr=await C().list('favorite_order_lines',{eq:{favorite_order_id:id}});if(lr.error)throw lr.error;const favLines=lr.data||[];let skipped=0;cart=[];favLines.forEach(l=>{const p=products.find(x=>x.id===l.product_id);if(!p){skipped++;return}cart.push({product_id:p.id,name:p.name,quantity:Number(l.quantity),unit_price:Number(p.sale_price||0),tax_rate:Number(p.tax_rate||0),line_total:Number(l.quantity)*Number(p.sale_price||0)})});render();m.classList.add('ccOk');m.textContent=skipped?`Favorito cargado (${skipped} producto${skipped>1?'s':''} ya no disponible${skipped>1?'s':''}).`:'Favorito cargado en el pedido.'}catch(e){console.error('[GAMA Catalog favorites]',e);m.classList.add('ccErr');m.textContent='No se pudo cargar el favorito: '+(e.message||e)}}
async function saveFavorite(){if(!cart.length)return alert('Añada al menos un producto antes de guardar como favorito.');const name=prompt('Nombre para este pedido favorito:');if(!name||!name.trim())return;const m=$('ccMsg');m.className='ccMsg';try{const sr=await C().getSession(),uid=sr?.data?.session?.user?.id;if(!uid)throw Error('Sesión cliente no encontrada.');const r=await C().insert('favorite_orders',{created_by:uid,name:name.trim()});if(r.error)throw r.error;for(const x of cart){const l=await C().insert('favorite_order_lines',{favorite_order_id:r.data.id,product_id:x.product_id,quantity:x.quantity});if(l.error)throw l.error}m.classList.add('ccOk');m.textContent='Guardado como favorito.';await loadFavorites()}catch(e){console.error('[GAMA Catalog favorites]',e);m.classList.add('ccErr');m.textContent='No se pudo guardar el favorito: '+(e.message||e)}}
async function deleteFavorite(id){if(!confirm('¿Eliminar este pedido favorito?'))return;try{const r=await C().remove('favorite_orders',id);if(r.error)throw r.error;await loadFavorites()}catch(e){console.error('[GAMA Catalog favorites]',e);alert('No se pudo eliminar: '+(e.message||e))}}
/* El catalogo pide la lista sin photo_data: nueve fotos base64 son 1,4 MB y
   el cliente las recibia enteras aunque solo mirara media pantalla. Se pinta un
   hueco y GamaPhotos trae de una vez las fotos de las tarjetas visibles. */
function ccPhoto(p){
 if(p.photo_data)return '<img loading="lazy" src="'+esc(p.photo_data)+'" alt="">';
 if(p.has_photo&&window.GamaPhotos)return window.GamaPhotos.slot(p.id,'ccNoImg');
 return '<div class="ccNoImg">📦</div>';
}
/* El IVA sale de la ficha del producto y de ningún otro sitio. Poner el 15%
   general del Ecuador cuando la ficha no lo dice enseñaría un impuesto que el
   pedido no va a cobrar: la línea guarda el de la ficha, y sin dato guarda
   cero. Dos cifras distintas para el mismo producto en la misma pantalla, y
   encima sobre dinero. Sin dato no se enseña importe con impuestos; y sólo se
   dice «exento» cuando la ficha lo dice, que es afirmar algo. */
const ivaDe=p=>{const v=Number(p.tax_rate);return Number.isFinite(v)&&v>=0?v:null};
const conIva=p=>Number(p.sale_price||0)*(1+(ivaDe(p)||0)/100);
const lineaIva=p=>{const r=ivaDe(p);return r?money(conIva(p))+' IVA incl.':r===0?'Exento de IVA':''};

/* Las viñetas salen de lo que la vista del catálogo deja ver. No hay texto
   comercial que enseñar —la vista no expone la descripción de la ficha—, así
   que se dice lo que un comprador necesita para decidir: qué referencia es,
   de qué categoría y con qué IVA se factura. */
function puntos(p){
 const l=[];
 if(p.reference)l.push('Referencia '+esc(p.reference));
 else if(p.barcode)l.push('Código '+esc(p.barcode));
 if(p.category)l.push('Categoría: '+esc(p.category));
 const r=ivaDe(p);
 if(r)l.push('IVA '+r+'% sobre el precio sin impuestos');
 else if(r===0)l.push('Producto exento de IVA');
 return l.slice(0,3).map(x=>'<li>'+x+'</li>').join('');
}
function existencias(p){
 const n=Number(p.stock);
 if(!Number.isFinite(n))return '';
 if(n<=0)return '<span class="ccStock agotado">Sin existencias</span>';
 if(n<=5)return '<span class="ccStock bajo">Últimas '+n+' unidades</span>';
 return '<span class="ccStock">En stock</span>';
}
function ficha(p){
 const qty=cart.find(x=>x.product_id===p.id)?.quantity||0;
 return `<article class="ccProduct">
<div class="ccMedia">${ccPhoto(p)}${p.contract_price?'<span class="ccFlag">Precio pactado</span>':''}</div>
<div class="ccInfo"><h3>${esc(p.name)}</h3><div class="ccMeta">${esc(p.reference||p.barcode||'')}${p.category?' · '+esc(p.category):''}</div><ul class="ccPuntos">${puntos(p)}</ul>${existencias(p)}</div>
<div class="ccPrecio"><b class="ccPrice">${money(p.sale_price)} <span>sin IVA</span></b><div class="ccPrecioIva">${lineaIva(p)}</div><small>Precio por unidad</small></div>
<div class="ccAcciones">
<div class="ccQty"><button type="button" data-minus="${esc(p.id)}" aria-label="Quitar uno">−</button><input type="number" min="0" value="${qty}" data-input="${esc(p.id)}" aria-label="Cantidad de ${esc(p.name)}"><button type="button" data-plus="${esc(p.id)}" aria-label="Añadir uno">+</button></div>
<button type="button" class="ccAdd${qty?' dentro':''}" data-add="${esc(p.id)}">${qty?'✓ En el pedido ('+qty+')':'🛒 Añadir al pedido'}</button>
</div></article>`;
}
function render(){const q=($('ccSearch')?.value||'').toLowerCase().trim(),cat=$('ccCategory')?.value||'',rows=products.filter(p=>(!q||[p.name,p.reference,p.barcode,p.category].some(v=>String(v||'').toLowerCase().includes(q)))&&(!cat||p.category===cat));$('ccCount').textContent=rows.length+' producto'+(rows.length>1?'s':'');$('ccProducts').innerHTML=rows.length?GamaPage.slice('catalog',rows).map(ficha).join('')+GamaPage.controls('catalog',rows.length):'<div class="muted">No se encontraron productos.</div>';$('ccProducts').querySelectorAll('[data-minus]').forEach(b=>b.onclick=()=>qty(b.dataset.minus,(cart.find(x=>x.product_id===b.dataset.minus)?.quantity||0)-1));$('ccProducts').querySelectorAll('[data-plus]').forEach(b=>b.onclick=()=>qty(b.dataset.plus,(cart.find(x=>x.product_id===b.dataset.plus)?.quantity||0)+1));$('ccProducts').querySelectorAll('[data-input]').forEach(i=>i.onchange=()=>qty(i.dataset.input,Number(i.value)||0));
 /* El botón grande es para quien no quiere pelearse con el contador: si el
    producto no está en el pedido lo añade, y si ya está lleva al pedido en vez
    de sumar otro sin querer. */
 $('ccProducts').querySelectorAll('[data-add]').forEach(b=>b.onclick=()=>{const id=b.dataset.add;const actual=cart.find(x=>x.product_id===id)?.quantity||0;if(actual)$('ccCartRows')?.scrollIntoView({behavior:'smooth',block:'center'});else qty(id,1)});
 if(window.GamaPhotos)GamaPhotos.hydrate($('ccProducts'),'catalog_products');renderCart()}
function qty(id,n){const p=products.find(x=>x.id===id);if(!p)return;n=Math.max(0,Number(n)||0);const i=cart.findIndex(x=>x.product_id===id);if(n===0){if(i>=0)cart.splice(i,1)}else{const x={product_id:p.id,name:p.name,quantity:n,unit_price:Number(p.sale_price||0),tax_rate:Number(p.tax_rate||0),line_total:n*Number(p.sale_price||0)};i>=0?cart[i]=x:cart.push(x)}render()}
function renderCart(){
 /* El pedido se cierra con las dos cifras que se comparan en una compra entre
    empresas: lo que suma la mercancía y lo que se va a pagar con impuestos.
    Cada línea lleva su propio IVA, que no tiene por qué ser el mismo. */
 const total=cart.reduce((s,x)=>s+x.quantity*x.unit_price,0);
 const iva=cart.reduce((s,x)=>s+x.quantity*x.unit_price*(Number(x.tax_rate)||0)/100,0);
 $('ccTotal').textContent=money(total);
 if($('ccNeto'))$('ccNeto').textContent=money(total);
 if($('ccIva'))$('ccIva').textContent=money(iva);
 if($('ccBruto'))$('ccBruto').textContent=money(total+iva);
 const host=$('ccCartRows');
 host.innerHTML=cart.length?cart.map(x=>`<div class="ccCartRow"><div><b>${esc(x.name)}</b><small>${money(x.unit_price)} c/u</small></div><div class="ccQty ccCartQty"><button class="secondary" data-cminus="${esc(x.product_id)}" aria-label="Quitar uno">−</button><input type="number" min="0" step="1" value="${x.quantity}" data-cinput="${esc(x.product_id)}" aria-label="Cantidad de ${esc(x.name)}"><button class="primary" data-cplus="${esc(x.product_id)}" aria-label="Añadir uno">+</button></div><span>${money(x.quantity*x.unit_price)}</span><button class="ccDel" data-del="${esc(x.product_id)}" aria-label="Quitar del pedido">×</button></div>`).join(''):'<span class="muted">Su pedido está vacío.</span>';
 /* Consultas acotadas al pedido: la parrilla usa data-minus/plus/input y no
    debe reaccionar a los controles de aquí. */
 const cur=id=>cart.find(x=>x.product_id===id)?.quantity||0;
 host.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>qty(b.dataset.del,0));
 host.querySelectorAll('[data-cminus]').forEach(b=>b.onclick=()=>qty(b.dataset.cminus,cur(b.dataset.cminus)-1));
 host.querySelectorAll('[data-cplus]').forEach(b=>b.onclick=()=>qty(b.dataset.cplus,cur(b.dataset.cplus)+1));
 host.querySelectorAll('[data-cinput]').forEach(i=>i.onchange=()=>qty(i.dataset.cinput,Number(i.value)||0));
}
async function send(){const m=$('ccMsg');m.className='ccMsg';m.textContent='';if(!cart.length){m.classList.add('ccErr');m.textContent='Añada al menos un producto.';return}try{const sr=await C().getSession(),uid=sr?.data?.session?.user?.id;if(!uid)throw Error('Sesión cliente no encontrada.');const pr=await C().getProfile(),email=pr?.data?.email||sr.data.session.user.email||'',name=pr?.data?.full_name||'';let customer=null;if(email){const cr=await C().list('customers',{eq:{email},limit:1});customer=(cr.data||[])[0]||null}const total=cart.reduce((s,x)=>s+x.quantity*x.unit_price,0);const r=await C().insert('customer_requests',{created_by:uid,customer_id:customer?.id||null,requester_name:name||null,requester_email:email||null,status:'pending',notes:$('ccNotes').value.trim()||null,total});if(r.error)throw r.error;for(const x of cart){const l=await C().insert('customer_request_lines',{request_id:r.data.id,product_id:x.product_id,quantity:x.quantity,unit_price:x.unit_price,tax_rate:x.tax_rate,line_total:x.quantity*x.unit_price});if(l.error)throw l.error}cart=[];$('ccNotes').value='';render();m.classList.add('ccOk');m.textContent='Pedido enviado correctamente.';window.dispatchEvent(new CustomEvent('gama:customer-request-created',{detail:{requestId:r.data.id}}))}catch(e){console.error('[GAMA Catalog send]',e);m.classList.add('ccErr');m.textContent='Error: '+(e.message||e)}}
function show(){ensureUI();document.querySelectorAll('section').forEach(s=>{const active=s.id==='client-catalog';s.classList.toggle('active',active);s.hidden=!active;s.style.display=active?'block':'none'});load()}
window.GamaOpenClientCatalog=show;
function boot(){ensureUI();window.addEventListener('gama:auth-change',()=>setTimeout(()=>{if(isClient())load()},150));if(isClient())setTimeout(load,100)}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();})();