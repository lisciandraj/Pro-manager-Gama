/* GAMA Excel Import V1 — products, clients, suppliers */
(function(){'use strict';
const TABLES={products:'products',clients:'customers',suppliers:'suppliers'};
const LABELS={products:'Productos',clients:'Clientes',suppliers:'Proveedores'};
const ALIASES={products:{name:['name','nombre','producto','product','descripcion','description','nom','nom_du_produit','nom_produit','designation','désignation','articulo','artículo','detalle'],description:['descripcion_larga','description_longue','long_description','detalle_completo'],reference:['sku','codigo','código','referencia','reference','code','referencia_unica','referencia_única','reference_unique','ref_unique','ref'],barcode:['barcode','ean','upc','codigo_barras','código_barras','code_barre','code_barres','codigo_barra'],category:['category','categoria','categoría','categorie','catégorie'],family:['family','familia','famille'],lines:['lines','lineas','líneas','lignes'],brand:['brand','marca','marque'],presentation:['presentation','presentación','présentation'],location:['location','ubicacion','ubicación','zona','almacen','almacén','bodega','zona_de_almacenamiento','zona_almacenamiento','emplacement','zone_de_stockage','zone_stockage'],stock:['stock','cantidad','quantity','qty','quantite','quantité','stock_actuel'],min_stock:['min_stock','stock_minimo','stock_mínimo','minimum_stock','stock_minimum','stock_min'],max_stock:['max_stock','stock_maximo','stock_máximo','maximum_stock','stock_maximum','stock_max'],qty_per_carton:['qty_per_carton','cantidad_por_carton','cantidad_por_cartón','quantite_par_carton','quantité_par_carton'],weight_g:['weight_g','peso','peso_g','poids','poids_g'],volume_cm3:['volume_cm3','volumen','volumen_cm3','volume'],sale_price:['price','precio','precio_venta','sale_price','prix','prix_de_vente','prix_vente'],price_a:['price_a','precio_compra_a','precio_grossiste','purchase_price','cost','costo','coste','cout','coût','prix_achat','prix_d_achat'],price_b:['price_b','precio_compra_b','precio_detalle','prix_achat_detail','prix_d_achat_detail'],tax_rate:['tax_rate','iva','tva','impuesto','tasa_impuesto','taux_tva','taxe','taux_de_tva']},clients:{name:['name','nombre','cliente','customer','razon_social','razón_social','nombre_razon_social','nom','nom_du_cliente','client','societe','société','raison_sociale'],email:['email','correo','mail','courriel','correo_electronico','correo_electrónico'],phone:['phone','telefono','teléfono','mobile','telephone','téléphone','portable'],address:['address','direccion','dirección','adresse'],city:['city','ciudad','ville'],province:['province','provincia'],tax_id:['tax_id','ruc','nif','cif','identificacion','identificación','siret','siren','numero_fiscal','numéro_fiscal'],notes:['notes','notas','observaciones','remarques','commentaire','commentaires']},suppliers:{name:['name','nombre','proveedor','supplier','razon_social','razón_social','nombre_razon_social','nom','nom_du_fournisseur','fournisseur','societe','société','raison_sociale'],email:['email','correo','mail','courriel','correo_electronico','correo_electrónico'],phone:['phone','telefono','teléfono','mobile','telephone','téléphone','portable'],address:['address','direccion','dirección','adresse'],city:['city','ciudad','ciudad_pais','ciudad_país','ville'],contact_name:['contact_name','persona_de_contacto','contacto','nombre_de_contacto'],tax_id:['tax_id','ruc','nif','cif','identificacion','identificación','ruc_identificacion','ruc_identificación','siret','siren','numero_fiscal','numéro_fiscal'],category:['category','categoria','categoría','categorie','catégorie'],notes:['notes','notas','observaciones','informacion_clave','información_clave','remarques','commentaire','commentaires']}};
let state={type:'products',rows:[],file:null};
let photoState={matches:[]};
const NUMERIC_FIELDS={products:new Set(['stock','min_stock','max_stock','qty_per_carton','weight_g','volume_cm3','sale_price','price_a','price_b','tax_rate'])};
const norm=v=>String(v??'').trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]+/g,'_').replace(/^_|_$/g,'');
const toNumber=v=>{const n=parseFloat(String(v).replace(/,/g,'.').replace(/[^0-9.\-]/g,''));return Number.isFinite(n)?n:null;};
function mapRow(row,type){const out={};const keys=Object.keys(row);const numeric=NUMERIC_FIELDS[type];for(const field of Object.keys(ALIASES[type])){const aliases=ALIASES[type][field].map(norm);const k=keys.find(x=>aliases.includes(norm(x)));if(!k)continue;const raw=row[k];if(String(raw).trim()==='')continue;if(numeric&&numeric.has(field)){const n=toNumber(raw);if(n!==null)out[field]=n;}else{out[field]=typeof raw==='string'?raw.trim():raw;}}return out;}
function host(){return document.getElementById('excel-import-module')||document.getElementById('excelImportModule')||document.querySelector('[data-module="excel"]');}
function css(){if(document.getElementById('gamaExcelCss'))return;const s=document.createElement('style');s.id='gamaExcelCss';s.textContent=`#excel-import-module,.gamaExcelModule{max-width:1100px;margin:auto}.gamaExcelBody{background:#fff;border:1px solid #e2e8ec;border-radius:18px;padding:18px}.gamaExcelDrop{border:2px dashed #b9cbd0;border-radius:16px;padding:30px;text-align:center;background:#f8fbfb;cursor:pointer}.gamaExcelDrop input{display:none}.gamaExcelIcon{font-size:38px;color:#087c8b}.gamaExcelDrop b,.gamaExcelDrop span{display:block}.gamaExcelDrop span{font-size:13px;color:#71808a;margin-top:5px}.gamaExcelTypes{display:flex;gap:7px;flex-wrap:wrap;margin:10px 0}.gamaExcelTypes button{background:#eef3f4;color:#18324a}.gamaExcelTypes button.active{background:#087c8b;color:#fff}.gamaExcelInfo{margin-top:10px;color:#71808a;font-size:13px}.gamaExcelPreview{overflow:auto;max-height:320px;border:1px solid #edf1f2;border-radius:10px;margin-top:12px}.gamaExcelPreview table{width:100%;border-collapse:collapse}.gamaExcelPreview th,.gamaExcelPreview td{padding:8px;border-bottom:1px solid #edf1f2;text-align:left;white-space:nowrap;font-size:12px}.gamaExcelActions{display:flex;gap:8px;justify-content:flex-end;margin-top:12px}.gamaExcelActions .primary{background:#087c8b;color:#fff}.gamaExcelActions .secondary{background:#eef3f4;color:#18324a}.gamaExcelModes{display:flex;gap:7px;flex-wrap:wrap;margin-bottom:12px}.gamaExcelModes button{background:#fff;border:1px solid #c9d6df;color:#18324a;border-radius:999px;padding:10px 16px;font-weight:800;cursor:pointer}.gamaExcelModes button.active{background:#087c8b;border-color:#087c8b;color:#fff}.gamaPhotoHint{background:#f8fbfb;border:1px solid #dbe6ea;border-radius:12px;padding:12px;font-size:13px;color:#4c5c68;margin-top:12px}.gamaPhotoHint code{background:#eef3f4;border-radius:5px;padding:1px 5px;font-size:12px}.gamaPhotoOpt{display:flex;align-items:center;gap:8px;margin-top:12px;font-size:13px;color:#4c5c68}.gamaPhotoOpt input{width:auto;margin:0}.gamaPhotoThumb{width:42px;height:42px;object-fit:cover;border-radius:7px;border:1px solid #dbe6ea;display:block}.gamaPhotoOk{color:#138a69;font-weight:800}.gamaPhotoBad{color:#c94f45;font-weight:800}.gamaPhotoWarn{color:#c75e18;font-weight:800}@media(max-width:700px){.gamaExcelActions{display:grid;grid-template-columns:1fr}.gamaExcelDrop{padding:24px 12px}}`;document.head.appendChild(s);}
function render(){const h=host();if(!h)return;h.classList.add('gamaExcelModule');h.innerHTML=`${window.GamaUI.header({title:'📥 Importación Excel',lead:'Sube datos y fotos de golpe desde Excel.'})}<div class="gamaExcelModes"><button type="button" data-mode="data" class="active">📄 Datos desde Excel</button><button type="button" data-mode="photos">🖼️ Fotos de productos</button><button type="button" data-mode="optimize">🗜️ Optimizar fotos</button></div><div class="gamaExcelBody" id="gamaExcelPanelData"><div class="gamaExcelDrop" id="gamaExcelDrop"><div class="gamaExcelIcon">▦</div><b>Selecciona o arrastra un archivo Excel</b><span>Formatos compatibles: .xlsx, .xls y .csv</span><input id="gamaExcelFile" type="file" accept=".xlsx,.xls,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel,text/csv"></div><div id="gamaExcelStatus" class="gamaExcelInfo">Ningún archivo seleccionado.</div><div class="gamaExcelTypes"><button type="button" data-type="products" class="active">📦 Productos</button><button type="button" data-type="clients">👥 Clientes</button><button type="button" data-type="suppliers">🚚 Proveedores</button></div><div id="gamaExcelPreview" class="gamaExcelPreview">Selecciona un archivo para mostrar una vista previa.</div><div class="gamaExcelActions"><button type="button" id="gamaExcelTemplate" class="secondary">Descargar plantilla</button><button type="button" id="gamaExcelImport" class="primary" disabled>Importar datos</button></div></div><div class="gamaExcelBody" id="gamaExcelPanelPhotos" hidden><div class="gamaExcelDrop" id="gamaPhotoDrop"><div class="gamaExcelIcon">🖼️</div><b>Selecciona o arrastra las fotos de tus productos</b><span>Formatos compatibles: .jpg, .png y .webp — puedes seleccionar varias a la vez</span><input id="gamaPhotoFiles" type="file" accept="image/*" multiple></div><div class="gamaPhotoHint">El <b>nombre del archivo es la referencia del producto</b>. Por ejemplo <code>SKU-001.jpg</code> se asigna al producto cuya referencia es <code>SKU-001</code>. Mayúsculas, espacios, guiones y acentos no importan.</div><div id="gamaPhotoStatus" class="gamaExcelInfo">Ninguna foto seleccionada.</div><label class="gamaPhotoOpt"><input type="checkbox" id="gamaPhotoKeep"> Conservar las fotos que ya existen (no reemplazarlas)</label><div id="gamaPhotoPreview" class="gamaExcelPreview">Selecciona fotos para comprobar la correspondencia con tus productos.</div><div class="gamaExcelActions"><button type="button" id="gamaPhotoImport" class="primary" disabled>Importar fotos</button></div></div><div class="gamaExcelBody" id="gamaExcelPanelOptimize" hidden><div class="gamaPhotoHint">Vuelve a guardar las fotos ya subidas a un tamaño ajustado a la pantalla (<b>320 px</b>). La aplicación nunca las enseña más grandes, así que no se nota la diferencia, pero pesan mucho menos y la base de datos gasta menos tráfico. Las fotos que ya sean pequeñas se dejan como están.</div><div id="gamaOptStatus" class="gamaExcelInfo">Pulsa el botón para revisar las fotos guardadas.</div><div id="gamaOptResult" class="gamaExcelPreview">Todavía no se ha optimizado nada.</div><div class="gamaExcelActions"><button type="button" id="gamaOptRun" class="primary">Optimizar las fotos guardadas</button></div></div>`;bind();}
function loadXLSX(){if(window.XLSX)return Promise.resolve();return new Promise((resolve,reject)=>{const s=document.createElement('script');s.src='https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js';s.integrity='sha384-vtjasyidUo0kW94K5MXDXntzOJpQgBKXmE7e2Ga4LG0skTTLeBi97eFAXsqewJjw';s.crossOrigin='anonymous';s.onload=resolve;s.onerror=()=>reject(new Error('No se pudo cargar el lector Excel'));document.head.appendChild(s);});}
async function parse(file){await loadXLSX();return new Promise((resolve,reject)=>{const r=new FileReader();r.onload=e=>{try{const wb=XLSX.read(e.target.result,{type:'array',cellDates:true});const ws=wb.Sheets[state.type]||wb.Sheets[wb.SheetNames[0]];resolve(XLSX.utils.sheet_to_json(ws,{defval:''}));}catch(err){reject(err);}};r.onerror=reject;r.readAsArrayBuffer(file);});}
function bind(){window.GamaUI.bindBack(host());const file=document.getElementById('gamaExcelFile'),drop=document.getElementById('gamaExcelDrop');drop.onclick=()=>file.click();file.onchange=()=>{state.file=file.files[0];if(state.file)load(state.file);};drop.ondragover=e=>e.preventDefault();drop.ondrop=e=>{e.preventDefault();state.file=e.dataTransfer.files[0];if(state.file)load(state.file);};document.querySelectorAll('.gamaExcelTypes button').forEach(b=>b.onclick=()=>{state.type=b.dataset.type;document.querySelectorAll('.gamaExcelTypes button').forEach(x=>x.classList.remove('active'));b.classList.add('active');if(state.file)load(state.file);});document.getElementById('gamaExcelImport').onclick=importRows;document.getElementById('gamaExcelTemplate').onclick=downloadTemplate;bindPhotos();}
function bindPhotos(){
 document.querySelectorAll('.gamaExcelModes button').forEach(b=>b.onclick=()=>{
  document.querySelectorAll('.gamaExcelModes button').forEach(x=>x.classList.remove('active'));
  b.classList.add('active');
  const mode=b.dataset.mode;
  document.getElementById('gamaExcelPanelData').hidden=mode!=='data';
  document.getElementById('gamaExcelPanelPhotos').hidden=mode!=='photos';
  document.getElementById('gamaExcelPanelOptimize').hidden=mode!=='optimize';
 });
 const input=document.getElementById('gamaPhotoFiles'),drop=document.getElementById('gamaPhotoDrop');
 drop.onclick=()=>input.click();
 input.onchange=()=>loadPhotos(input.files);
 drop.ondragover=e=>e.preventDefault();
 drop.ondrop=e=>{e.preventDefault();loadPhotos(e.dataTransfer.files)};
 document.getElementById('gamaPhotoImport').onclick=importPhotos;
 document.getElementById('gamaOptRun').onclick=optimizePhotos;
}

/* Reduce las fotos ya guardadas. El trabajo lo hace GamaPhotos en este mismo
   navegador: el canvas sólo existe aquí, y así la escritura pasa por la sesión
   y los permisos del usuario que lo pide. */
function kb(chars){return Math.round(chars/1024)+' kB'}
async function optimizePhotos(){
 const st=document.getElementById('gamaOptStatus'),res=document.getElementById('gamaOptResult');
 const btn=document.getElementById('gamaOptRun');
 if(!window.GamaPhotos||!window.GamaPhotos.optimizeAll){st.textContent='El módulo de fotos no está disponible. Recarga la aplicación.';return}
 if(!confirm('Se van a volver a guardar las fotos de los productos a 320 px.\n\nLa aplicación nunca las enseña más grandes, así que no se notará en pantalla, pero el cambio no se puede deshacer.\n\n¿Continuar?'))return;
 btn.disabled=true;res.textContent='';
 try{
  const r=await window.GamaPhotos.optimizeAll((hechas,total,nombre)=>{
   st.textContent=hechas>=total?'Terminando…':`Optimizando ${hechas+1} de ${total}: ${nombre}`;
  });
  const ahorro=r.antes>0?Math.round(100-100*r.despues/r.antes):0;
  st.textContent='Optimización terminada.';
  res.innerHTML='<b>'+r.reducidas+' foto(s) reducida(s)</b>'
   +(r.sinCambio?' · '+r.sinCambio+' ya estaba(n) bien':'')
   +(r.fallidas?' · <span style="color:#c94f45">'+r.fallidas+' con error</span>':'')
   +'<br>'+kb(r.antes)+' → <b>'+kb(r.despues)+'</b>'+(ahorro>0?' (−'+ahorro+'%)':'');
  // Las listas ya pintadas siguen enseñando la foto vieja de la caché.
  if(window.renderAll)try{window.renderAll()}catch(e){}
 }catch(e){
  console.error('[GAMA Optimizar fotos]',e);
  st.textContent='No se pudo optimizar: '+(e&&e.message||e);
 }finally{btn.disabled=false}
}
/* El nombre del archivo es la referencia: "SKU-001.jpg" → referencia "SKU-001".
   Sólo se quita la última extensión, para no romper referencias con puntos. */
const baseName=n=>String(n||'').replace(/\.[^.\\/]+$/,'').trim();
/* Se busca primero la referencia exacta y luego una normalizada (sin mayúsculas,
   acentos ni separadores), porque los nombres de archivo rara vez conservan el
   formato exacto. Si dos productos comparten la forma normalizada, no se
   adivina: se marca como ambigua y no se toca ninguno. */
function refIndex(products){
 const exact=new Map(),loose=new Map(),ambiguous=new Set();
 for(const p of products||[]){
  const ref=String(p.reference??'').trim();
  if(!ref)continue;
  if(!exact.has(ref))exact.set(ref,p);
  const n=norm(ref);
  if(!n)continue;
  if(loose.has(n)&&loose.get(n).id!==p.id)ambiguous.add(n);
  else if(!loose.has(n))loose.set(n,p);
 }
 return{exact,loose,ambiguous};
}
function matchProduct(idx,ref){
 if(!ref)return{error:'Nombre de archivo vacío'};
 if(idx.exact.has(ref))return{product:idx.exact.get(ref)};
 const n=norm(ref);
 if(!n)return{error:'Nombre de archivo vacío'};
 if(idx.ambiguous.has(n))return{error:'Varios productos con esa referencia'};
 if(idx.loose.has(n))return{product:idx.loose.get(n)};
 return{error:'Ningún producto con esa referencia'};
}
/* Mismos parámetros que la foto tomada desde la ficha de producto (700 px,
   JPEG 0.78): una foto de catálogo legible sin llenar la tabla de megabytes. */
function compressPhoto(file){
 return new Promise((resolve,reject)=>{
  const r=new FileReader();
  r.onerror=()=>reject(new Error('No se pudo leer el archivo'));
  r.onload=()=>{
   const img=new Image();
   img.onerror=()=>reject(new Error('Archivo de imagen no válido'));
   img.onload=()=>{
    try{
     const max=320,s=Math.min(1,max/img.width,max/img.height),c=document.createElement('canvas');
     c.width=Math.max(1,Math.round(img.width*s));c.height=Math.max(1,Math.round(img.height*s));
     c.getContext('2d').drawImage(img,0,0,c.width,c.height);
     resolve(c.toDataURL('image/jpeg',.6));
    }catch(e){reject(e)}
   };
   img.src=r.result;
  };
  r.readAsDataURL(file);
 });
}
async function loadPhotos(fileList){
 const files=[...(fileList||[])].filter(f=>/^image\//.test(f.type)||/\.(jpe?g|png|webp|gif|bmp)$/i.test(f.name));
 const st=document.getElementById('gamaPhotoStatus'),btn=document.getElementById('gamaPhotoImport');
 photoState={matches:[]};btn.disabled=true;
 if(!files.length){st.textContent='Ningún archivo de imagen seleccionado.';photoPreview();return}
 const api=window.GamaCloud;
 if(!api){st.textContent='La conexión con la nube de GAMA no está disponible.';return}
 st.textContent='Comprobando '+files.length+' foto(s) con tu catálogo…';
 let products=[];
 try{const r=await api.list('products',{select:'id,name,reference,has_photo'});if(r.error)throw r.error;products=r.data||[]}
 catch(e){st.textContent='Error al leer los productos: '+(e.message||e);return}
 const idx=refIndex(products),usedRefs=new Map();
 photoState.matches=files.map(f=>{
  const ref=baseName(f.name),m=matchProduct(idx,ref);
  if(m.product){
   const key=m.product.id;
   if(usedRefs.has(key))return{file:f,ref,error:'Ya asignada por «'+usedRefs.get(key)+'»'};
   usedRefs.set(key,f.name);
  }
  return{file:f,ref,product:m.product,error:m.error};
 });
 photoPreview();
 const ok=photoState.matches.filter(m=>m.product).length;
 st.textContent=`${files.length} foto(s): ${ok} con producto correspondiente, ${files.length-ok} sin correspondencia.`;
 btn.disabled=!ok;
}
function photoPreview(){
 const p=document.getElementById('gamaPhotoPreview');
 if(!photoState.matches.length){p.textContent='Selecciona fotos para comprobar la correspondencia con tus productos.';return}
 p.innerHTML='<table><thead><tr><th></th><th>Archivo</th><th>Referencia</th><th>Producto</th><th>Estado</th></tr></thead><tbody>'
  +photoState.matches.map((m,i)=>{
   const state=m.error?'<span class="gamaPhotoBad">'+esc(m.error)+'</span>'
    :m.product.has_photo?'<span class="gamaPhotoWarn">Reemplaza la foto actual</span>'
    :'<span class="gamaPhotoOk">Listo para importar</span>';
   return '<tr><td><img class="gamaPhotoThumb" data-thumb="'+i+'" alt=""></td><td>'+esc(m.file.name)+'</td><td>'+esc(m.ref)+'</td><td>'+esc(m.product?m.product.name:'—')+'</td><td>'+state+'</td></tr>';
  }).join('')+'</tbody></table>';
 // Las miniaturas se generan con object URL para no cargar 50 base64 en memoria.
 p.querySelectorAll('[data-thumb]').forEach(img=>{
  const m=photoState.matches[+img.dataset.thumb];
  if(!m)return;
  const url=URL.createObjectURL(m.file);
  img.src=url;img.onload=()=>URL.revokeObjectURL(url);
 });
}
async function importPhotos(){
 const btn=document.getElementById('gamaPhotoImport'),st=document.getElementById('gamaPhotoStatus');
 const api=window.GamaCloud;
 if(!api){alert('La conexión con la nube de GAMA no está disponible.');return}
 const keep=document.getElementById('gamaPhotoKeep').checked;
 const todo=photoState.matches.filter(m=>m.product&&!(keep&&m.product.has_photo));
 const skippedKept=photoState.matches.filter(m=>m.product&&keep&&m.product.has_photo).length;
 if(!todo.length){st.textContent='No hay ninguna foto que importar.';return}
 btn.disabled=true;
 let ok=0,fail=0;
 for(let i=0;i<todo.length;i++){
  const m=todo[i];
  st.textContent=`Importando foto ${i+1} de ${todo.length}…`;
  try{
   const photo=await compressPhoto(m.file);
   const r=await api.update('products',m.product.id,{photo_data:photo});
   if(r&&r.error)throw r.error;
   m.product.has_photo=true;if(window.GamaPhotos)GamaPhotos.seed(m.product.id,photo);
   ok++;
  }catch(e){console.error('[GAMA Fotos]',m.file.name,e);fail++}
 }
 const unmatched=photoState.matches.filter(m=>!m.product).length;
 st.textContent=`Importación finalizada: ${ok} foto(s) asignada(s)`
  +(skippedKept?`, ${skippedKept} conservada(s)`:'')
  +(unmatched?`, ${unmatched} sin correspondencia`:'')
  +(fail?`, ${fail} error(es)`:'')+'.';
 photoPreview();
 btn.disabled=false;
}
async function load(file){const st=document.getElementById('gamaExcelStatus');st.textContent='Leyendo '+file.name+'…';try{const raw=await parse(file);state.rows=raw.map(r=>mapRow(r,state.type)).filter(r=>Object.keys(r).length);preview();st.textContent=state.rows.length+' fila(s) detectada(s) para '+LABELS[state.type]+'.';document.getElementById('gamaExcelImport').disabled=!state.rows.length;}catch(e){st.textContent='Error: '+e.message;}}
function preview(){const p=document.getElementById('gamaExcelPreview');if(!state.rows.length){p.textContent='Ninguna fila utilizable. Verifica los encabezados del archivo.';return;}const cols=[...new Set(state.rows.flatMap(Object.keys))];p.innerHTML='<table><thead><tr>'+cols.map(c=>'<th>'+esc(c)+'</th>').join('')+'</tr></thead><tbody>'+state.rows.slice(0,30).map(r=>'<tr>'+cols.map(c=>'<td>'+esc(r[c])+'</td>').join('')+'</tr>').join('')+'</tbody></table>';}
const dupKey=(name,address)=>norm(name)+'|'+norm(address);
/* Same name + same address is treated as the same contact, so re-importing a
   file (or a file listing someone twice) tops up instead of duplicating. */
async function existingKeys(api,type){const seen=new Set();if(type!=='clients'&&type!=='suppliers')return seen;try{const r=await api.list(TABLES[type],{});if(r.error)throw r.error;(r.data||[]).forEach(x=>seen.add(dupKey(x.name,x.address)))}catch(e){console.warn('[GAMA Excel] no se pudo comprobar duplicados',e)}return seen;}
async function importRows(){const btn=document.getElementById('gamaExcelImport'),st=document.getElementById('gamaExcelStatus');btn.disabled=true;const api=window.GamaCloud;if(!api){alert('La conexión con la nube de GAMA no está disponible.');btn.disabled=false;return;}st.textContent='Comprobando duplicados…';const seen=await existingKeys(api,state.type);let ok=0,fail=0,dup=0;for(const row of state.rows){try{if(state.type==='clients'||state.type==='suppliers'){if(!row.name){fail++;continue}const k=dupKey(row.name,row.address);if(seen.has(k)){dup++;continue}seen.add(k)}if(state.type==='products'&&window.GamaCloudProducts?.createProduct)await window.GamaCloudProducts.createProduct(row);else if(state.type==='clients')await api.insert('customers',{name:row.name,identification:row.tax_id||null,address:row.address||null,city:row.city||null,province:row.province||null,phone:row.phone||null,email:row.email||null,notes:row.notes||null,active:true});else if(state.type==='suppliers')await api.insert('suppliers',{name:row.name,tax_id:row.tax_id||null,address:row.address||null,city:row.city||null,contact_name:row.contact_name||null,phone:row.phone||null,email:row.email||null,notes:row.notes||null,active:true});ok++;}catch(e){console.error(e);fail++;}}st.textContent=`Importación finalizada: ${ok} fila(s) importada(s), ${dup} duplicada(s) omitida(s), ${fail} error(es).`;btn.disabled=false;}
async function downloadTemplate(){await loadXLSX();const examples={products:[{name:'Producto ejemplo',description:'Descripción del producto',reference:'SKU-001',barcode:'376000000001',category:'Categoría',family:'Familia',lines:'Línea',brand:'Marca',presentation:'Caja x12',location:'Z01-A01',stock:10,min_stock:2,max_stock:100,qty_per_carton:12,weight_g:500,volume_cm3:1000,sale_price:12.5,price_a:7,price_b:8.5,tax_rate:15}],clients:[{name:'Cliente ejemplo',email:'cliente@example.com',phone:'000000000',address:'Dirección',city:'Quito',province:'Pichincha',tax_id:'ID-001',notes:''}],suppliers:[{name:'Proveedor ejemplo',email:'proveedor@example.com',phone:'000000000',address:'Dirección',city:'Quito',contact_name:'Persona de contacto',tax_id:'ID-001',category:'A',notes:''}]};const wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,XLSX.utils.json_to_sheet(examples[state.type]),LABELS[state.type]);XLSX.writeFile(wb,'GAMA_'+state.type+'_plantilla.xlsx');}
function esc(v){return String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));}
css();window.GamaExcelImport={render,_mapRowForTests:mapRow,_refIndexForTests:refIndex,_matchProductForTests:matchProduct,_baseNameForTests:baseName};if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',render,{once:true});else render();
})();