/* GAMA V10 - Módulos Proveedores + Matriz comercial */
(function(){
'use strict';
const SUP_KEY='gama_suppliers_v1', MAT_KEY='gama_matrix_v1';
/* La descripción de cada pantalla, en un solo sitio: section() sólo escribe la
   cabecera la primera vez, así que si el texto estuviera repetido ganaría el
   de quien llame antes — que es justo lo que pasaba con la matriz. */
const SUP_LEAD='El contacto y las condiciones de cada proveedor.';
const MAT_LEAD='Calcula el precio de venta según tu margen.';
const $=id=>document.getElementById(id);
function load(k,fallback=[]){try{const v=JSON.parse(localStorage.getItem(k)||'null');return Array.isArray(v)?v:fallback}catch(e){return fallback}}
function save(k,v){localStorage.setItem(k,JSON.stringify(v))}
function esc(v){return window.ArcUI.esc(v)}
function money(n){return window.GamaCurrency.format(n)}
function products(){return Array.isArray(window.db?.products)?window.db.products:[]}
function injectStyles(){ /* Styles are compiled in architect-components.css. */ }
/* La cabecera es la misma que la del resto de la aplicación; sólo cambian el
   título y las frases que explican la pantalla. */
function section(id,title,sub){let s=$(id);if(s)return s;s=document.createElement('section');s.id=id;window.ArcUI.render(s,window.GamaUI.header({title,lead:sub})+`<div id="${id}Content"></div>`);const wrap=document.querySelector('.wrap');(wrap||document.body).appendChild(s);window.GamaUI.bindBack(s);return s}
const CLOUD=()=>window.GamaCloud;
const SUP_FIELDS=['supName','supTax','supContact','supPhone','supEmail','supCity','supAddress','supNotes'];
const MIGRATED_KEY='gama_suppliers_migrated_v1';
let cloudSuppliers=[];
const supKey=v=>String(v??'').trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]+/g,'');
function supFromCloud(r){return window.ArcEntities.legacySupplier(r)}
async function fetchSuppliers(){if(!CLOUD())return [];const r=await window.ArcData.all('suppliers',{order:'name',ascending:true},true);if(r.error)throw r.error;return (r.data||[]).map(supFromCloud)}
/* The supplier directory used to live only in localStorage, disconnected from the
   central suppliers table that Compras and the product sheets already read. Copy
   anything that only exists locally into the cloud once, then never again. */
async function migrateLocalSuppliersOnce(existing){
 try{if(localStorage.getItem(MIGRATED_KEY))return 0}catch(e){return 0}
 const local=load(SUP_KEY);
 if(!Array.isArray(local)||!local.length){try{localStorage.setItem(MIGRATED_KEY,'1')}catch(e){}return 0}
 const have=new Set(existing.map(x=>supKey(x.name)));
 let moved=0;
 for(const s of local){
  if(!s||!s.name||have.has(supKey(s.name)))continue;
  const r=await CLOUD().insert('suppliers',{name:s.name,tax_id:s.tax||null,contact_name:s.contact||null,phone:s.phone||null,email:s.email||null,city:s.city||null,address:s.address||null,notes:s.notes||null,active:true});
  if(!r.error){have.add(supKey(s.name));moved++}
 }
 try{localStorage.setItem(MIGRATED_KEY,'1')}catch(e){}
 return moved;
}
function renderSuppliers(){section('suppliers','🏭 Proveedores',SUP_LEAD);const host=$('suppliersContent');if(!host)return;const cleanup=window.ArcDirectories.suppliers(host);fetchSuppliers().then(rows=>{cloudSuppliers=rows;return migrateLocalSuppliersOnce(rows)}).then(moved=>{if(moved){window.ArcData.invalidate('suppliers');window.dispatchEvent(new CustomEvent('gama:data-change',{detail:{table:'suppliers'}}))}}).catch(console.error);return cleanup}

let matrixEpoch=0,matrixRequest=null;
const mt=(es,fr,en)=>({es,fr,en}[window.GamaI18n?.language||'es']||es);
async function renderMatrix(){
 section('matrix','📊 Matriz comercial',MAT_LEAD);const c=$('matrixContent');if(!c)return;
 const epoch=++matrixEpoch;c.textContent=mt('Cargando…','Chargement…','Loading…');
 try{
  const [rows,pr,sr]=await Promise.all([
   window.ArcData.all('commercial_matrix',{order:'created_at',ascending:false,eq:{active:true}}),
   window.ArcData.all('products',{select:'id,name,reference,barcode,sale_price,purchase_price',eq:{active:true},order:'name'}),fetchSuppliers()]);
  if(epoch!==matrixEpoch)return;if(rows.error||pr.error)throw rows.error||pr.error;
  const ps=pr.data||[],sups=sr.filter(x=>x.active!==false),mats=rows.data||[];
  const legacy=load(MAT_KEY);const admin=['admin','administrador'].includes(JSON.parse(localStorage.getItem('gama_session_v1')||'{}').role);
  c.dataset.giIgnore='';window.ArcUI.render(c,`<div class="arcPanel">
  <p>${mt('Cada simulación se conserva. Aplicar un precio requiere la validación de un administrador.','Chaque simulation est conservée. L’application d’un prix nécessite la validation d’un administrateur.','Each scenario is retained. Applying a price requires administrator approval.')}</p>
  <form id="matrixForm"><div class="row"><label>${mt('Producto','Produit','Product')}<select id="matProduct" required><option value="">—</option>${ps.map(p=>`<option value="${esc(p.id)}">${esc(p.name)} · ${esc(p.reference||p.barcode||'')}</option>`).join('')}</select></label>
  <label>${mt('Proveedor','Fournisseur','Supplier')}<select id="matSupplier"><option value="">—</option>${sups.map(s=>`<option value="${esc(s.id)}">${esc(s.name)}</option>`).join('')}</select></label></div>
  <label>${mt('Nombre de la simulación','Nom de la simulation','Scenario name')}<input id="matName" maxlength="120" required></label>
  <div class="row"><label>${mt('Compra unitaria','Achat unitaire','Unit purchase')}<input id="matPurchase" type="number" min="0.01" step="0.01" required></label>
  <label>${mt('Gastos por unidad','Frais par unité','Additional unit cost')}<input id="matExtra" type="number" min="0" step="0.01" value="0" required></label>
  <label>${mt('Margen sobre ventas (%)','Marge sur ventes (%)','Margin on sales (%)')}<input id="matMargin" type="number" min="0" max="99.999" step="0.001" value="30" required></label></div>
  <p id="matPreview" role="status"></p><button class="arcButton primary" type="submit" id="matAdd">${mt('Guardar simulación','Enregistrer la simulation','Save scenario')}</button></form>
  <p id="matStatus" role="status"></p>
  ${legacy.length?`<button class="arcButton secondary" id="matMigrate">${mt('Importar simulaciones de este dispositivo','Importer les simulations de cet appareil','Import scenarios from this device')} (${legacy.length})</button>`:''}
  </div><div class="arcPanel"><input type="search" id="matSearch" placeholder="${mt('Buscar','Rechercher','Search')}" aria-label="${mt('Buscar','Rechercher','Search')}"><div id="matRows"></div></div>`);
  const preview=()=>{const cost=Number($('matPurchase').value)+Number($('matExtra').value),margin=Number($('matMargin').value);$('matPreview').textContent=mt('Precio propuesto: ','Prix proposé : ','Proposed price: ')+money(margin>=0&&margin<100?cost/(1-margin/100):0)};
  ['matPurchase','matExtra','matMargin'].forEach(id=>$(id).oninput=preview);
  $('matProduct').onchange=()=>{const p=ps.find(p=>p.id===$('matProduct').value);if(p){$('matPurchase').value=p.purchase_price||0;$('matName').value=p.name+' · '+new Date().toISOString().slice(0,10);preview()}};preview();
  const action=async(name,payload)=>window.ArcData.rpc('gama_matrix_action',{p_action:name,p_data:payload});
  $('matrixForm').onsubmit=async e=>{e.preventDefault();const button=$('matAdd');if(button.disabled)return;button.disabled=true;
   const payload={product_id:$('matProduct').value,supplier_id:$('matSupplier').value||null,scenario_name:$('matName').value,purchase_price:Number($('matPurchase').value),additional_cost:Number($('matExtra').value),target_margin:Number($('matMargin').value)};
   const signature=JSON.stringify(payload);if(matrixRequest?.signature!==signature)matrixRequest={signature,key:crypto.randomUUID()};
   try{await action('save',{...payload,request_key:matrixRequest.key});matrixRequest=null;await renderMatrix()}catch(e){$('matStatus').textContent=window.ArcErrors.message(e);button.disabled=false}
  };
  function draw(){const q=$('matSearch').value.toLocaleLowerCase(),filtered=mats.filter(m=>{const p=ps.find(p=>p.id===m.product_id);return (m.scenario_name+' '+(p?.name||'')).toLocaleLowerCase().includes(q)});
   const subset=window.GamaPage?.slice('matrix',filtered)||filtered;
   window.ArcUI.render($('matRows'),`<table class="arcTable"><thead><tr>${[mt('Simulación','Simulation','Scenario'),mt('Producto','Produit','Product'),mt('Coste completo','Coût complet','Landed cost'),mt('Margen','Marge','Margin'),mt('Precio','Prix','Price'),mt('Estado','État','Status')].map(h=>'<th>'+h+'</th>').join('')}</tr></thead><tbody>${subset.map(m=>{const p=ps.find(p=>p.id===m.product_id),margin=Number(m.sale_price)?100*(Number(m.sale_price)-Number(m.purchase_price)-Number(m.additional_cost||0))/Number(m.sale_price):0;return `<tr><td>${esc(m.scenario_name)}<small>${esc(new Date(m.created_at).toLocaleString())}</small></td><td>${esc(p?.name||m.product_id)}</td><td>${money(Number(m.purchase_price)+Number(m.additional_cost||0))}</td><td>${margin.toFixed(2)}%</td><td>${money(m.sale_price)}</td><td>${m.applied_at?mt('Aplicado','Appliqué','Applied'):admin?`<button class="arcButton secondary" data-mat-apply="${esc(m.id)}">${mt('Validar y aplicar','Valider et appliquer','Approve and apply')}</button>`:mt('Por validar','À valider','Awaiting approval')}<button class="arcButton ghost" data-mat-archive="${esc(m.id)}">${mt('Archivar','Archiver','Archive')}</button></td></tr>`}).join('')}</tbody></table>`+(window.GamaPage?.controls('matrix',filtered.length)||''));
   $('matRows').querySelectorAll('[data-mat-apply]').forEach(b=>b.onclick=async()=>{const m=mats.find(m=>m.id===b.dataset.matApply),p=ps.find(p=>p.id===m.product_id);if(!confirm(`${p?.name||''}\n${money(p?.sale_price)} → ${money(m.sale_price)}\n${mt('¿Validar y aplicar este precio?','Valider et appliquer ce prix ?','Approve and apply this price?')}`))return;b.disabled=true;try{await action('apply',{id:m.id});window.ArcData.invalidate('products');await renderMatrix()}catch(e){$('matStatus').textContent=window.ArcErrors.message(e);b.disabled=false}});
   $('matRows').querySelectorAll('[data-mat-archive]').forEach(b=>b.onclick=async()=>{b.disabled=true;try{await action('archive',{id:b.dataset.matArchive});await renderMatrix()}catch(e){$('matStatus').textContent=window.ArcErrors.message(e);b.disabled=false}});
  }
  $('matSearch').oninput=()=>{window.GamaPage?.reset('matrix');draw()};window.GamaPage?.register('matrix',draw);draw();
  $('matMigrate')?.addEventListener('click',async()=>{const button=$('matMigrate');button.disabled=true;const remaining=[...legacy];let moved=0;
   try{for(const m of legacy){const matches=ps.filter(p=>m.barcode?p.barcode===m.barcode:p.name===m.name);if(matches.length!==1)continue;
    const keyName='architect_matrix_import_'+String(m.id||m.barcode||m.name);let key=localStorage.getItem(keyName);if(!key){key=crypto.randomUUID();localStorage.setItem(keyName,key)}
    await action('save',{request_key:key,product_id:matches[0].id,supplier_id:sups.some(s=>s.id===m.supplierId)?m.supplierId:null,purchase_price:Number(m.purchase),additional_cost:0,target_margin:Number(m.margin),scenario_name:mt('Importación local','Import local','Local import')+' · '+m.name});
    remaining.splice(remaining.indexOf(m),1);save(MAT_KEY,remaining);moved++;
   }await renderMatrix();$('matStatus').textContent=mt('Importadas: ','Importées : ','Imported: ')+moved+(remaining.length?' · '+mt('Sin correspondencia: ','Sans correspondance : ','Unmatched: ')+remaining.length:'');
   }catch(e){$('matStatus').textContent=window.ArcErrors.message(e);button.disabled=false}
  });
 }catch(e){if(epoch===matrixEpoch){c.textContent=window.ArcErrors.message(e);const retry=document.createElement('button');retry.className='arcButton secondary';retry.textContent=mt('Reintentar','Réessayer','Retry');retry.onclick=renderMatrix;c.append(retry)}}
}
window.addEventListener('gama:auth-change',()=>{matrixEpoch++;matrixRequest=null;$('matrixContent')?.replaceChildren()});
/* Aquí vivía patchMenu(): buscaba la tarjeta «Configuración» del menú, le
   cambiaba el nombre a «Matriz comercial» y le robaba el clic, con un
   MutationObserver que lo repetía en cada cambio del DOM por si el menú se
   repintaba. El efecto secundario era que Configuración no se podía abrir
   desde ninguna parte. Matriz comercial tiene ahora su propia entrada en
   gama-menu-final2.js, que es donde se declaran las demás. */
function hook(){injectStyles();section('matrix','📊 Matriz comercial',MAT_LEAD);window.ArcRouter.onEnter('suppliers',renderSuppliers);window.ArcRouter.onEnter('matrix',renderMatrix)}

if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(hook,50),{once:true});else setTimeout(hook,50);
})();