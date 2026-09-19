/* GAMA — Catálogo de productos */
(function(){'use strict';
const C=()=>window.GamaCloud,$=id=>document.getElementById(id);
const esc=window.ArcUI.esc;
const money=v=>Number(v||0).toLocaleString('es-EC',{style:'currency',currency:'USD',minimumFractionDigits:2,maximumFractionDigits:2});
let cart=[],products=[],favorites=[];
function isClient(){try{return JSON.parse(localStorage.getItem('gama_session_v1')||'null')?.role==='client'}catch(_){return false}}
function inject(){if($('gamaClientCatalogStyle'))return;const s=document.createElement('style');s.id='gamaClientCatalogStyle';document.head.appendChild(s)}
function ensureUI(){inject();let sec=$('client-catalog');if(!sec){sec=document.createElement('section');sec.id='client-catalog';(document.querySelector('.wrap')||document.body).appendChild(sec)}if(sec.dataset.ready)return;sec.dataset.ready='1';window.ArcUI.render(sec,`${window.GamaUI.header({title:'🛍️ Catálogo de productos',lead:'Elija sus productos y envíe el pedido a Architect.'})}<div class="cc"><div class="ccTools"><input id="ccSearch" data-gi-placeholder=48d9573a38c4 placeholder="Buscar un producto…"><select id="ccCategory"><option value="" data-gi=425a839def0b>Todas las categorías</option></select><span class="badge" id="ccCount">0 productos</span></div><div class="muted" id="ccStatus"><span class="gamaSpin"></span>Cargando…</div><div class="ccGrid" id="ccProducts"></div><div class="ccFav" id="ccFav"><div class="ccFavHead"><h3 data-gi=cb6b4fa7ebba>⭐ Mis pedidos favoritos</h3></div><div id="ccFavRows" class="muted" data-gi=73a81c321e99>Sin favoritos guardados.</div></div><div class="ccCart"><div class="ccCartHead"><h3 data-gi=af887267f60d>🛒 Mi pedido</h3><b id="ccTotal">$0,00</b></div><div id="ccCartRows" style="margin:8px 0"><span class="muted" data-gi=a63b1e7d1713>Su pedido está vacío.</span></div><div class="ccResumen"><div><span data-gi=53de02aa48c6>Subtotal sin IVA</span><b id="ccNeto">$0,00</b></div><div><span data-gi=ba6da46c5e1c>IVA</span><b id="ccIva">$0,00</b></div><div class="ccResumenTotal"><span data-gi=0db5bb8bb2fe>Total con IVA</span><b id="ccBruto">$0,00</b></div></div><textarea id="ccNotes" data-gi-placeholder=0ada0d45e88a placeholder="Comentario o indicación para el pedido…"></textarea><button class="arcButton primary" id="ccSend" style="width:100%;margin-top:9px" data-gi=10b4a1190405>Enviar pedido</button><button class="arcButton secondary" id="ccSaveFav" style="width:100%;margin-top:8px" data-gi=580cb2abec1a>☆ Guardar como favorito</button><div id="ccMsg" class="ccMsg"></div></div></div>`);window.GamaUI.bindBack(sec);$('ccSearch').oninput=()=>{GamaPage.reset('catalog');render()};$('ccCategory').onchange=()=>{GamaPage.reset('catalog');render()};GamaPage.register('catalog',render);$('ccSend').onclick=send;$('ccSaveFav').onclick=saveFavorite}
function populateCategorySelect(){const s=$('ccCategory');if(!s)return;const cur=s.value;const cats=[...new Set(products.map(p=>(p.category||'').trim()).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'es'));window.ArcUI.render(s,'<option value="" data-gi=425a839def0b>Todas las categorías</option>'+cats.map(c=>`<option value="${esc(c)}">${esc(c)}</option>`).join(''));if(cur&&cats.includes(cur))s.value=cur}
async function load(){ensureUI();window.ArcUI.render($('ccStatus'),'<span class="gamaSpin"></span>Cargando productos desde la base de datos…');try{const r=await C().list('catalog_products',{select:'id,name,reference,barcode,category,sale_price,base_price,contract_price,tax_rate,stock,has_photo,active',order:'name',ascending:true});if(r.error)throw r.error;products=(r.data||[]).filter(p=>p.active!==false);$('ccCount').textContent=products.length+' producto'+(products.length>1?'s':'');$('ccStatus').textContent='Catálogo sincronizado.';populateCategorySelect();render()}catch(e){console.error('[GAMA Catalog]',e);$('ccStatus').textContent='Error de carga: '+(e.message||e)}loadFavorites()}
async function loadFavorites(){try{const sr=await C().getSession(),uid=sr?.data?.session?.user?.id;if(!uid)return;const fr=await C().list('favorite_orders',{eq:{created_by:uid},order:'created_at',ascending:false});if(fr.error)throw fr.error;favorites=fr.data||[];renderFavorites()}catch(e){console.error('[GAMA Catalog favorites]',e)}}
function renderFavorites(){const host=$('ccFavRows');if(!host)return;window.ArcUI.render(host,favorites.length?favorites.map(f=>`<div class="ccFavRow"><b>${esc(f.name)}</b><span class="ccFavActions"><button class="arcButton secondary" data-fav-load="${f.id}" data-gi=7214d0203007>Cargar</button><button class="arcButton ccDel" data-fav-del="${f.id}">×</button></span></div>`).join(''):'<div class="muted" data-gi=73a81c321e99>Sin favoritos guardados.</div>');host.querySelectorAll('[data-fav-load]').forEach(b=>b.onclick=()=>loadFavorite(b.dataset.favLoad));host.querySelectorAll('[data-fav-del]').forEach(b=>b.onclick=()=>deleteFavorite(b.dataset.favDel))}
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
function existencias(p){
 const n=Number(p.stock);
 if(!Number.isFinite(n))return '';
 if(n<=0)return '<span class="ccStock agotado" data-gi=be6038d25214>Sin existencias</span>';
 if(n<=5)return '<span class="ccStock bajo">Últimas '+n+' unidades</span>';
 return '<span class="ccStock" data-gi=bac44c6502ca>En stock</span>';
}
function ficha(p){
 const qty=cart.find(x=>x.product_id===p.id)?.quantity||0;
 return `<article class="ccProduct">
<div class="ccMedia">${ccPhoto(p)}${p.contract_price?'<span class="ccFlag" data-gi=051ff0420afc>Precio pactado</span>':''}</div>
<div class="ccInfo"><h3>${esc(p.name)}</h3>${p.barcode?'<div class="ccBarcode">Código de barras: '+esc(p.barcode)+'</div>':''}<div class="ccMeta">${p.reference?'<span>Ref. '+esc(p.reference)+'</span>':''}${p.category?'<span>'+esc(p.category)+'</span>':''}</div>${existencias(p)}</div>
<div class="ccPrecio"><b class="ccPrice">${money(p.sale_price)} <span data-gi=3c7895a92a52>sin IVA</span></b><div class="ccPrecioIva">${lineaIva(p)}</div><small data-gi=b69201d8c5f1>Precio por unidad</small></div>
<div class="ccAcciones">
<div class="ccQty"><button class="arcButton" type="button" data-minus="${esc(p.id)}" data-gi-aria-label=ffa160172bac aria-label="Quitar uno">−</button><input type="number" min="0" value="${qty}" data-input="${esc(p.id)}" aria-label="Cantidad de ${esc(p.name)}"><button class="arcButton" type="button" data-plus="${esc(p.id)}" data-gi-aria-label=05193a4d8db8 aria-label="Añadir uno">+</button></div>
<button type="button" class="arcButton ccAdd${qty?' dentro':''}" data-add="${esc(p.id)}" data-gi-live>${qty?'✓ En el pedido ('+qty+')':'🛒 Añadir al pedido'}</button>
</div></article>`;
}
function render(){const q=($('ccSearch')?.value||'').toLowerCase().trim(),cat=$('ccCategory')?.value||'',rows=products.filter(p=>(!q||[p.name,p.reference,p.barcode,p.category].some(v=>String(v||'').toLowerCase().includes(q)))&&(!cat||p.category===cat));$('ccCount').textContent=rows.length+' producto'+(rows.length>1?'s':'');window.ArcUI.render($('ccProducts'),rows.length?GamaPage.slice('catalog',rows).map(ficha).join('')+GamaPage.controls('catalog',rows.length):'<div class="muted" data-gi=31f22142a6d8>No se encontraron productos.</div>');$('ccProducts').querySelectorAll('[data-minus]').forEach(b=>b.onclick=()=>qty(b.dataset.minus,(cart.find(x=>x.product_id===b.dataset.minus)?.quantity||0)-1));$('ccProducts').querySelectorAll('[data-plus]').forEach(b=>b.onclick=()=>qty(b.dataset.plus,(cart.find(x=>x.product_id===b.dataset.plus)?.quantity||0)+1));$('ccProducts').querySelectorAll('[data-input]').forEach(i=>i.onchange=()=>qty(i.dataset.input,Number(i.value)||0));
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
 window.ArcUI.render(host,cart.length?cart.map(x=>`<div class="ccCartRow"><div><b>${esc(x.name)}</b><small>${money(x.unit_price)} c/u</small></div><div class="ccQty ccCartQty"><button class="arcButton secondary" data-cminus="${esc(x.product_id)}" data-gi-aria-label=ffa160172bac aria-label="Quitar uno">−</button><input type="number" min="0" step="1" value="${x.quantity}" data-cinput="${esc(x.product_id)}" aria-label="Cantidad de ${esc(x.name)}"><button class="arcButton primary" data-cplus="${esc(x.product_id)}" data-gi-aria-label=05193a4d8db8 aria-label="Añadir uno">+</button></div><span>${money(x.quantity*x.unit_price)}</span><button class="arcButton ccDel" data-del="${esc(x.product_id)}" data-gi-aria-label=aa7484780ab1 aria-label="Quitar del pedido">×</button></div>`).join(''):'<span class="muted" data-gi=a63b1e7d1713>Su pedido está vacío.</span>');
 /* Consultas acotadas al pedido: la parrilla usa data-minus/plus/input y no
    debe reaccionar a los controles de aquí. */
 const cur=id=>cart.find(x=>x.product_id===id)?.quantity||0;
 host.querySelectorAll('[data-del]').forEach(b=>b.onclick=()=>qty(b.dataset.del,0));
 host.querySelectorAll('[data-cminus]').forEach(b=>b.onclick=()=>qty(b.dataset.cminus,cur(b.dataset.cminus)-1));
 host.querySelectorAll('[data-cplus]').forEach(b=>b.onclick=()=>qty(b.dataset.cplus,cur(b.dataset.cplus)+1));
 host.querySelectorAll('[data-cinput]').forEach(i=>i.onchange=()=>qty(i.dataset.cinput,Number(i.value)||0));
}
async function send(){const m=$('ccMsg');m.className='ccMsg';m.textContent='';if(!cart.length){m.classList.add('ccErr');m.textContent='Añada al menos un producto.';return}try{const sr=await C().getSession(),uid=sr?.data?.session?.user?.id;if(!uid)throw Error('Sesión cliente no encontrada.');const pr=await C().getProfile(),email=pr?.data?.email||sr.data.session.user.email||'',name=pr?.data?.full_name||'';let customer=null;if(email){const cr=await C().list('customers',{eq:{email},limit:1});customer=(cr.data||[])[0]||null}const total=cart.reduce((s,x)=>s+x.quantity*x.unit_price,0);const r=await C().insert('customer_requests',{created_by:uid,customer_id:customer?.id||null,requester_name:name||null,requester_email:email||null,status:'pending',notes:$('ccNotes').value.trim()||null,total});if(r.error)throw r.error;for(const x of cart){const l=await C().insert('customer_request_lines',{request_id:r.data.id,product_id:x.product_id,quantity:x.quantity,unit_price:x.unit_price,tax_rate:x.tax_rate,line_total:x.quantity*x.unit_price});if(l.error)throw l.error}cart=[];$('ccNotes').value='';render();m.classList.add('ccOk');m.textContent=(window.GamaI18n?.t('Pedido enviado correctamente.')||'Pedido enviado correctamente.')+(r.data.dossier_reference?' · '+r.data.dossier_reference:'');window.dispatchEvent(new CustomEvent('gama:customer-request-created',{detail:{requestId:r.data.id}}))}catch(e){console.error('[GAMA Catalog send]',e);m.classList.add('ccErr');m.textContent='Error: '+(e.message||e)}}
function show(){if(!window.gamaAccessAllowed?.('client-catalog'))return;ensureUI();window.ArcRouter.show('client-catalog');load()}
window.GamaOpenClientCatalog=show;
function boot(){ensureUI();window.addEventListener('gama:auth-change',()=>setTimeout(()=>{if(isClient())load()},150));if(isClient())setTimeout(load,100)}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();})();