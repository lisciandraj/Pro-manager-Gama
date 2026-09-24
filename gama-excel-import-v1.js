/* GAMA Excel Import V1 — products, clients, suppliers, customer tariffs */
(function(){'use strict';
const excelIcon=n=>'<svg viewBox="0 0 24 24" data-icon="'+n+'" aria-hidden="true" focusable="false">'+(window.ArcUI&&window.ArcUI.icons&&window.ArcUI.icons[n]||'')+'</svg>';
const TABLES={products:'products',clients:'customers',suppliers:'suppliers',customerPrices:'customer_special_prices'};
const LABELS={products:'Productos',clients:'Clientes',suppliers:'Proveedores',customerPrices:'Tarifas de cliente'};
const ALIASES={products:{name:['name','nombre','producto','product','descripcion','description','nom','nom_du_produit','nom_produit','designation','désignation','articulo','artículo','detalle'],description:['descripcion_larga','description_longue','long_description','detalle_completo'],reference:['sku','codigo','código','referencia','reference','code','referencia_unica','referencia_única','reference_unique','ref_unique','ref'],barcode:['barcode','ean','upc','codigo_barras','código_barras','code_barre','code_barres','codigo_barra'],category:['category','categoria','categoría','categorie','catégorie'],family:['family','familia','famille'],lines:['lines','lineas','líneas','lignes'],brand:['brand','marca','marque'],presentation:['presentation','presentación','présentation'],location:['location','ubicacion','ubicación','zona','almacen','almacén','bodega','zona_de_almacenamiento','zona_almacenamiento','emplacement','zone_de_stockage','zone_stockage'],stock:['stock','cantidad','quantity','qty','quantite','quantité','stock_actuel'],min_stock:['min_stock','stock_minimo','stock_mínimo','minimum_stock','stock_minimum','stock_min'],max_stock:['max_stock','stock_maximo','stock_máximo','maximum_stock','stock_maximum','stock_max'],qty_per_carton:['qty_per_carton','cantidad_por_carton','cantidad_por_cartón','quantite_par_carton','quantité_par_carton'],weight_g:['weight_g','peso','peso_g','poids','poids_g'],volume_cm3:['volume_cm3','volumen','volumen_cm3','volume'],sale_price:['price','precio','precio_venta','sale_price','precio_venta_a','precio_mayorista','prix','prix_de_vente','prix_vente'],sale_price_b:['sale_price_b','precio_venta_b','precio_venta_detalle','prix_vente_detail'],purchase_price:['purchase_price','precio_compra','cost','costo','coste','cout','coût','prix_achat','prix_d_achat'],tax_rate:['tax_rate','iva','tva','impuesto','tasa_impuesto','taux_tva','taxe','taux_de_tva']},clients:{name:['name','nombre','cliente','customer','razon_social','razón_social','nombre_razon_social','nom','nom_du_cliente','client','societe','société','raison_sociale'],email:['email','correo','mail','courriel','correo_electronico','correo_electrónico'],phone:['phone','telefono','teléfono','mobile','telephone','téléphone','portable'],address:['address','direccion','dirección','adresse'],city:['city','ciudad','ville'],province:['province','provincia'],tax_id:['tax_id','ruc','nif','cif','identificacion','identificación','siret','siren','numero_fiscal','numéro_fiscal'],category:['category','categoria','categoría','categorie','catégorie'],notes:['notes','notas','observaciones','remarques','commentaire','commentaires']},suppliers:{name:['name','nombre','proveedor','supplier','razon_social','razón_social','nombre_razon_social','nom','nom_du_fournisseur','fournisseur','societe','société','raison_sociale'],email:['email','correo','mail','courriel','correo_electronico','correo_electrónico'],phone:['phone','telefono','teléfono','mobile','telephone','téléphone','portable'],address:['address','direccion','dirección','adresse'],city:['city','ciudad','ciudad_pais','ciudad_país','ville'],contact_name:['contact_name','persona_de_contacto','contacto','nombre_de_contacto'],tax_id:['tax_id','ruc','nif','cif','identificacion','identificación','ruc_identificacion','ruc_identificación','siret','siren','numero_fiscal','numéro_fiscal'],notes:['notes','notas','observaciones','informacion_clave','información_clave','remarques','commentaire','commentaires']},customerPrices:{
 customer:['cliente','cliente_nombre','client','customer','customer_name','nombre_cliente','razon_social','razón_social','razon_social_cliente','nombre_razon_social'],
 customer_tax_id:['ruc','ruc_cliente','nif','cif','cedula','cédula','identificacion','identificación','tax_id','customer_tax_id','ruc_identificacion'],
 reference:['sku','codigo','código','referencia','reference','code','ref','referencia_producto','codigo_producto','product_reference'],
 barcode:['barcode','ean','upc','codigo_barras','código_barras','code_barre','ean13'],
 unit_price:['precio','precio_contrato','precio_pactado','precio_negociado','precio_venta','precio_unitario','tarifa','unit_price','price','prix','prix_contrat','prix_unitaire'],
 contract_ref:['contrato','contract','referencia_contrato','n_contrato','num_contrato','contract_ref','numero_de_contrato','contrat']
}};
let state={type:'products',rows:[],file:null};
let photoState={matches:[]};
const NUMERIC_FIELDS={customerPrices:new Set(['unit_price']),products:new Set(['stock','min_stock','max_stock','qty_per_carton','weight_g','volume_cm3','sale_price','sale_price_b','purchase_price','tax_rate'])};
const norm=v=>String(v??'').trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]+/g,'_').replace(/^_|_$/g,'');
const toNumber=v=>{const text=String(v).trim().replace(/^[€$£]\s*|\s*[%€$£]$/g,'').replace(',','.');return /^-?\d+(?:\.\d+)?$/.test(text)&&Number.isFinite(Number(text))?Number(text):null;};
function mapRow(row,type){const out={};const keys=Object.keys(row);const numeric=NUMERIC_FIELDS[type];for(const field of Object.keys(ALIASES[type])){const aliases=ALIASES[type][field].map(norm);const k=keys.find(x=>aliases.includes(norm(x)));if(!k)continue;const raw=row[k];if(String(raw).trim()==='')continue;if(numeric&&numeric.has(field)){const n=toNumber(raw);if(n!==null)out[field]=n;else out._errors=(out._errors?out._errors+'; ':'')+field+': '+String(raw);}else{out[field]=typeof raw==='string'?raw.trim():raw;}}return out;}
function host(){return document.getElementById('excel-import-module')||document.getElementById('excelImportModule')||document.querySelector('[data-module="excel"]');}
function css(){ /* Styles are compiled in architect-components.css. */ }
function render(){const h=host();if(!h)return;h.classList.add('gamaExcelModule');window.ArcUI.render(h,`${window.GamaUI.header({title:'Importar datos',lead:'Importa datos desde Excel y fotos de tus productos.'})}<div class="gamaExcelModes"><button type="button" data-mode="data" class="arcButton active" data-gi=478bc01902a2>Datos desde Excel</button><button class="arcButton" type="button" data-mode="photos" data-gi=ea8bdb9f487d>Fotos de productos</button><button class="arcButton" type="button" data-mode="optimize" data-gi=32a316506aa1>Optimizar fotos</button></div><div class="gamaExcelBody" id="gamaExcelPanelData"><div class="gamaExcelDrop" id="gamaExcelDrop"><div class="gamaExcelIcon">${excelIcon('spreadsheet')}</div><b data-gi=37b772c6e8fa>Selecciona o arrastra un archivo Excel</b><span data-gi=18ed7e649564>Formatos compatibles: .xlsx, .xls y .csv</span><input id="gamaExcelFile" type="file" accept=".xlsx,.xls,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel,text/csv"></div><div id="gamaExcelStatus" class="gamaExcelInfo" data-gi=5b5c815f3c1f>Ningún archivo seleccionado.</div><div class="gamaExcelTypes"><button type="button" data-type="products" class="arcButton active" data-gi=f598138f026c>Productos</button><button class="arcButton" type="button" data-type="clients" data-gi=07e1ce1859da>Clientes</button><button class="arcButton" type="button" data-type="suppliers" data-gi=bb1bb5cc7a83>Proveedores</button><button class="arcButton" type="button" data-type="customerPrices" data-gi=d8be464ab5cf>Tarifas de cliente</button></div><div id="gamaExcelPreview" class="gamaExcelPreview" data-gi=8810c4c2df6b>Selecciona un archivo para mostrar una vista previa.</div><div class="gamaExcelActions"><button type="button" id="gamaExcelTemplate" class="arcButton secondary" data-gi=d02205871bd5>Descargar plantilla</button><button type="button" id="gamaExcelValidate" class="arcButton secondary" data-gi=5a293f298d65>Simular todas las filas</button><button type="button" id="gamaExcelBatches" class="arcButton secondary">Historial de importaciones</button><button type="button" id="gamaExcelImport" class="arcButton primary" disabled data-gi=63e31998d5d9>Importar datos</button></div></div><div class="gamaExcelBody" id="gamaExcelPanelPhotos" hidden><div class="gamaExcelDrop" id="gamaPhotoDrop"><div class="gamaExcelIcon">${excelIcon('cube')}</div><b data-gi=c3f8ff5acbf2>Selecciona o arrastra las fotos de tus productos</b><span data-gi=e9250d978d8e>Formatos compatibles: .jpg, .png y .webp — puedes seleccionar varias a la vez</span><input id="gamaPhotoFiles" type="file" accept="image/*" multiple></div><div class="gamaPhotoHint" data-gi=0107e8f8d234>El nombre del archivo puede contener la <b data-gi=ba93fb125822>referencia, el nombre del producto o ambos</b>: <code>SKU-001.jpg</code>, <code>Tornillo hexagonal.png</code> o <code>SKU-001 Tornillo hexagonal frente.jpg</code>. Mayúsculas, acentos, espacios, guiones y guiones bajos se reconocen. Si hay varios candidatos, añade la referencia y el nombre; las coincidencias ambiguas no se importan.</div><div id="gamaPhotoStatus" class="gamaExcelInfo" data-gi=d674f2920b4c>Ninguna foto seleccionada.</div><label class="gamaPhotoOpt"><input type="checkbox" id="gamaPhotoKeep"><span data-gi=32d46931ce14> Conservar las fotos que ya existen (no reemplazarlas)</span></label><div id="gamaPhotoPreview" class="gamaExcelPreview" data-gi=06f5ea0fcb93>Selecciona fotos para comprobar la correspondencia con tus productos.</div><div class="gamaExcelActions"><button type="button" id="gamaPhotoImport" class="arcButton primary" disabled data-gi=dd9cf954111a>Importar fotos</button></div></div><div class="gamaExcelBody" id="gamaExcelPanelOptimize" hidden><div class="gamaPhotoHint" data-gi=77d1ab5a2a1a>Vuelve a guardar las fotos ya subidas a un tamaño ajustado a la pantalla (<b>320 px</b>). La aplicación nunca las enseña más grandes, así que no se nota la diferencia, pero pesan mucho menos y la base de datos gasta menos tráfico. Las fotos que ya sean pequeñas se dejan como están.</div><div id="gamaOptStatus" class="gamaExcelInfo" data-gi=43ec50213d03>Pulsa el botón para revisar las fotos guardadas.</div><div id="gamaOptResult" class="gamaExcelPreview" data-gi=0976200111c1>Todavía no se ha optimizado nada.</div><div class="gamaExcelActions"><button type="button" id="gamaOptRun" class="arcButton primary" data-gi=d3f1025271c5>Optimizar las fotos guardadas</button></div></div>`);bind();}
function loadXLSX(){if(window.XLSX)return Promise.resolve();return new Promise((resolve,reject)=>{const s=document.createElement('script');s.src='assets/vendor/xlsx-0.18.5.full.min.js';s.integrity='sha384-vtjasyidUo0kW94K5MXDXntzOJpQgBKXmE7e2Ga4LG0skTTLeBi97eFAXsqewJjw';s.crossOrigin='anonymous';s.onload=resolve;s.onerror=()=>reject(new Error('No se pudo cargar el lector Excel'));document.head.appendChild(s);});}
async function parse(file){await loadXLSX();return new Promise((resolve,reject)=>{const r=new FileReader();r.onload=e=>{try{const wb=XLSX.read(e.target.result,{type:'array',cellDates:true});const ws=wb.Sheets[state.type]||wb.Sheets[wb.SheetNames[0]];resolve(XLSX.utils.sheet_to_json(ws,{defval:''}));}catch(err){reject(err);}};r.onerror=reject;r.readAsArrayBuffer(file);});}
function bind(){window.GamaUI.bindBack(host());const file=document.getElementById('gamaExcelFile'),drop=document.getElementById('gamaExcelDrop');drop.onclick=()=>file.click();file.onchange=()=>{state.file=file.files[0];if(state.file)load(state.file);};drop.ondragover=e=>e.preventDefault();drop.ondrop=e=>{e.preventDefault();state.file=e.dataTransfer.files[0];if(state.file)load(state.file);};document.querySelectorAll('.gamaExcelTypes button').forEach(b=>b.onclick=()=>{state.type=b.dataset.type;document.querySelectorAll('.gamaExcelTypes button').forEach(x=>x.classList.remove('active'));b.classList.add('active');if(state.file)load(state.file);});document.getElementById('gamaExcelValidate').onclick=prepareImport;document.getElementById('gamaExcelBatches').onclick=importHistory;document.getElementById('gamaExcelImport').onclick=importRows;document.getElementById('gamaExcelTemplate').onclick=downloadTemplate;bindPhotos();}
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
  window.ArcUI.render(res,'<b>'+r.reducidas+' foto(s) reducida(s)</b>'
   +(r.sinCambio?' · '+r.sinCambio+' ya estaba(n) bien':'')
   +(r.fallidas?' · <span style="color:var(--arc-danger)">'+r.fallidas+' con error</span>':'')
   +'<br>'+kb(r.antes)+' → <b>'+kb(r.despues)+'</b>'+(ahorro>0?' (−'+ahorro+'%)':''));
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
/* Exact identifiers first; otherwise complete token sequences in the title.
   Reference + name can disambiguate legacy duplicates; never choose the first row. */
function refIndex(products){
 const exact=new Map();
 const rows=(products||[]).map(p=>({product:p,ref:norm(p.reference),name:norm(p.name)}));
 for(const p of products||[]){for(const value of [p.reference,p.name]){
  const key=String(value??'').trim();if(!key)continue;
  if(!exact.has(key))exact.set(key,[]);
  if(!exact.get(key).some(x=>x.id===p.id))exact.get(key).push(p);
 }}
 return{exact,rows};
}
function matchProduct(idx,title){
 const n=norm(title);if(!n)return{error:'Nombre de archivo vacío'};
 const exact=idx.exact.get(String(title).trim())||[];
 if(exact.length===1)return{product:exact[0]};
 const contains=key=>key&&('_'+n+'_').includes('_'+key+'_');
 const refs=idx.rows.filter(r=>contains(r.ref));
 const names=idx.rows.filter(r=>contains(r.name));
 let hits=refs.length&&names.length?refs.filter(r=>names.some(x=>x.product.id===r.product.id)):(refs.length?refs:names);
 if(refs.length&&names.length&&!hits.length)return{error:'Referencia y nombre corresponden a productos diferentes'};
 // Prefer a full longer identifier over a shorter identifier contained within it.
 hits=hits.filter(r=>!hits.some(other=>other!==r&&
  ((r.ref&&other.ref&&other.ref!==r.ref&&('_'+other.ref+'_').includes('_'+r.ref+'_'))||
   (!refs.length&&r.name&&other.name!==r.name&&('_'+other.name+'_').includes('_'+r.name+'_')))));
 if(hits.length===1)return{product:hits[0].product};
 if(hits.length>1)return{error:'Varios productos con esa referencia o nombre; añade ambos al archivo'};
 return{error:'Ningún producto con esa referencia o nombre'};
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
 if(!api){st.textContent='La conexión con la nube de Coco ERP no está disponible.';return}
 st.textContent='Comprobando '+files.length+' foto(s) con tu catálogo…';
 let products=[];
 try{for(let offset=0;;offset+=500){const r=await api.list('products',{select:'id,name,reference,has_photo',order:'id',range:[offset,offset+499]});if(r.error)throw r.error;const rows=r.data||[];products.push(...rows);if(rows.length<500)break}}
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
 window.ArcUI.render(p,'<table class="arcTable"><thead><tr><th></th><th data-gi=75d6b4579e1d>Archivo</th><th data-gi=10ddff5fcc6f>Referencia</th><th data-gi=77b9238931ed>Producto</th><th data-gi=98e5acddb6c4>Estado</th></tr></thead><tbody>'
  +photoState.matches.map((m,i)=>{
   const state=m.error?'<span class="gamaPhotoBad">'+esc(m.error)+'</span>'
    :m.product.has_photo?'<span class="gamaPhotoWarn" data-gi=114d9bb63cab>Reemplaza la foto actual</span>'
    :'<span class="gamaPhotoOk" data-gi=5094a1047d5c>Listo para importar</span>';
   return '<tr><td><img class="gamaPhotoThumb" data-thumb="'+i+'" alt=""></td><td>'+esc(m.file.name)+'</td><td>'+esc(m.product?.reference||'—')+'</td><td>'+esc(m.product?m.product.name:'—')+'</td><td>'+state+'</td></tr>';
  }).join('')+'</tbody></table>');
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
 if(!api){alert('La conexión con la nube de Coco ERP no está disponible.');return}
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
async function load(file){state.batch=null;state.request_key=crypto.randomUUID();const st=document.getElementById('gamaExcelStatus');st.textContent='Leyendo '+file.name+'…';try{const raw=await parse(file);state.rows=raw.map(r=>mapRow(r,state.type)).filter(r=>Object.keys(r).length);preview();st.textContent=state.rows.length+' fila(s) detectada(s) para '+LABELS[state.type]+'.';document.getElementById('gamaExcelImport').disabled=true;}catch(e){st.textContent='Error: '+e.message;}}
function preview(){const p=document.getElementById('gamaExcelPreview');if(!state.rows.length){p.textContent='Ninguna fila utilizable. Verifica los encabezados del archivo.';return;}const cols=[...new Set(state.rows.flatMap(Object.keys))];window.ArcUI.render(p,'<table class="arcTable"><thead><tr>'+cols.map(c=>'<th>'+esc(c)+'</th>').join('')+'</tr></thead><tbody>'+state.rows.slice(0,30).map(r=>'<tr>'+cols.map(c=>'<td>'+esc(r[c])+'</td>').join('')+'</tr>').join('')+'</tbody></table>');}
const dupKey=(name,address)=>norm(name)+'|'+norm(address);
/* Same name + same address is treated as the same contact, so re-importing a
   file (or a file listing someone twice) tops up instead of duplicating. */
/* ---- Tarifas de cliente ----

   Un precio pactado vale para UN cliente y UN producto, así que el archivo
   tiene que decir a quién y a qué se refiere cada línea. Se admite lo que trae
   una lista de verdad: del cliente su nombre o su RUC, y del producto nuestra
   referencia o su código de barras.

   Se guarda con upsert sobre (cliente, producto): volver a subir la lista
   cuando el contrato cambia tiene que CORREGIR el precio, no fallar por
   duplicado ni dejar dos. Ése es justo el caso de uso. */
function claveTexto(v){return String(v??'').trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/\s+/g,' ')}
function indiceClientes(filas){
 const m=new Map();
 for(const c of filas){
  if(c.active===false)continue;
  if(c.name)m.set('n:'+claveTexto(c.name),c);
  if(c.identification)m.set('r:'+claveTexto(c.identification),c);
 }
 return m;
}
function indiceProductos(filas){
 const m=new Map();
 for(const p of filas){
  if(p.active===false)continue;
  if(p.reference)m.set('r:'+claveTexto(p.reference),p.id);
  if(p.barcode)m.set('b:'+claveTexto(p.barcode),p.id);
 }
 return m;
}
async function importarTarifas(api,filas,st){
 const [cl,pr]=await Promise.all([
  api.list('customers',{select:'id,name,identification,category,active'}),
  api.list('products',{select:'id,reference,barcode,active'}),
 ]);
 if(cl.error)throw cl.error;
 if(pr.error)throw pr.error;
 const clientes=indiceClientes(cl.data||[]),prods=indiceProductos(pr.data||[]);
 let ok=0,sinCliente=0,sinProducto=0,sinPrecio=0,fail=0;
 const noC=new Set();
 for(const f of filas){
  const cliente=clientes.get('n:'+claveTexto(f.customer))||clientes.get('r:'+claveTexto(f.customer_tax_id));
  if(!cliente){sinCliente++;continue}
  const pid=prods.get('r:'+claveTexto(f.reference))||prods.get('b:'+claveTexto(f.barcode));
  if(!pid){sinProducto++;continue}
  /* Number(null) y Number('') son 0, así que una celda vacía se habría
     guardado como un precio de cero y el producto se facturaría gratis. Un
     cero escrito a propósito sí vale; un hueco no. */
  const precio=(f.unit_price===null||f.unit_price===undefined||f.unit_price==='')?NaN:Number(f.unit_price);
  if(!Number.isFinite(precio)||precio<0){sinPrecio++;continue}
  try{
   const r=await api.upsert('customer_special_prices',
    {customer_id:cliente.id,product_id:pid,unit_price:precio,contract_ref:f.contract_ref||null},
    {onConflict:'customer_id,product_id'});
   if(r.error)throw r.error;
   ok++;
   /* El precio se guarda igual, pero sólo se aplica a un cliente de categoría
      C: al resto se le factura el de su categoría. Callarlo dejaría una tarifa
      cargada que no hace nada y nadie sabría por qué. */
   if((cliente.category||'A')!=='C')noC.add(cliente.name||cliente.id);
  }catch(e){console.error(e);fail++}
 }
 /* Se dice POR QUÉ se quedó fuera cada línea: en una lista ajena lo que casi
    siempre falla es que la referencia del producto no es la nuestra, y
    «12 errores» a secas no se arregla. */
 const partes=[ok+' tarifa(s) guardada(s)'];
 if(sinCliente)partes.push(sinCliente+' sin cliente reconocido');
 if(sinProducto)partes.push(sinProducto+' sin producto reconocido');
 if(sinPrecio)partes.push(sinPrecio+' sin precio válido');
 if(fail)partes.push(fail+' error(es)');
 let texto='Importación finalizada: '+partes.join(', ')+'.';
 if(noC.size)texto+=' Ojo: '+[...noC].join(', ')+' no '+(noC.size>1?'son':'es')+' de categoría C, así que su tarifa no se aplicará hasta cambiarles la categoría en su ficha.';
 st.textContent=texto;
}

async function existingKeys(api,type){const seen=new Set();if(type!=='clients'&&type!=='suppliers')return seen;try{const r=await api.list(TABLES[type],{});if(r.error)throw r.error;(r.data||[]).forEach(x=>seen.add(dupKey(x.name,x.address)))}catch(e){console.warn('[GAMA Excel] no se pudo comprobar duplicados',e)}return seen;}
const importRPC=(action,data)=>window.ArcData.rpc('gama_import_batch',{p_action:action,p_data:data});
function showImportResult(r){state.batch=r.batch;const good=r.rows.filter(x=>x.status==='ready').length,done=r.rows.filter(x=>x.status==='imported').length,errors=r.rows.filter(x=>x.status==='error');document.getElementById('gamaExcelStatus').textContent=`${r.batch.filename} · ${good} listas · ${done} importadas · ${errors.length} errores`;const host=document.getElementById('gamaExcelPreview');window.ArcUI.render(host,window.ArcUI.table({columns:[{key:'row_number',label:'Fila'},{key:'status',label:'Estado'},{label:'Registro',value:r=>r.data.name||r.data.customer||r.data.reference||''},{key:'error',label:'Error'}],items:r.rows})+(errors.length?'<button type=button class="arcButton secondary" id="gamaExcelErrors" data-gi=79da091cf3a0>Descargar todos los errores</button>':''));const download=document.getElementById('gamaExcelErrors');if(download)download.onclick=()=>{const csv=['fila;error;registro',...errors.map(x=>[x.row_number,x.error,JSON.stringify(x.data)].map(v=>'"'+String(v).replace(/"/g,'""')+'"').join(';'))].join('\n'),url=URL.createObjectURL(new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8'})),a=document.createElement('a');a.href=url;a.download='errores-importacion.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};const btn=document.getElementById('gamaExcelImport');btn.disabled=done===r.rows.length;btn.textContent=done?'Reintentar filas pendientes':'Confirmar importación'}
async function prepareImport(){const btn=document.getElementById('gamaExcelValidate');btn.disabled=true;try{if(!state.rows.length)throw Error('Selecciona un archivo.');const r=await importRPC('prepare',{kind:state.type,filename:state.file?.name||'Import',request_key:state.request_key||(state.request_key=crypto.randomUUID()),rows:state.rows});showImportResult(r)}catch(e){document.getElementById('gamaExcelStatus').textContent=e.message}finally{btn.disabled=false}}
async function importRows(){const btn=document.getElementById('gamaExcelImport');if(!state.batch)return;btn.disabled=true;try{const r=await importRPC('apply',{id:state.batch.id});showImportResult(r);window.ArcData.invalidate();window.dispatchEvent(new CustomEvent('gama:data-change',{detail:{table:TABLES[state.type]}}))}catch(e){document.getElementById('gamaExcelStatus').textContent=e.message;btn.disabled=false}}
async function importHistory(){try{const r=await window.GamaCloud.list('erp_import_batches',{select:'id,kind,filename,status,created_at',order:'created_at',ascending:false,limit:100});if(r.error)throw r.error;const d=window.ArcUI.dialog({title:'Historial de importaciones',saveLabel:'Cerrar',body:window.ArcUI.table({columns:[{key:'filename',label:'Archivo'},{key:'kind',label:'Tipo'},{key:'status',label:'Estado'},{key:'created_at',label:'Fecha'},{label:'',html:b=>`<button type=button class="arcButton secondary" data-import-batch="${esc(b.id)}">Ver / reintentar</button>`}],items:r.data}),onSave:async()=>{}});d.querySelectorAll('[data-import-batch]').forEach(b=>b.onclick=async()=>{try{const r=await importRPC('detail',{id:b.dataset.importBatch});state.type=r.batch.kind;showImportResult(r);d.close()}catch(e){d.querySelector('[role=alert]').textContent=e.message}})}catch(e){document.getElementById('gamaExcelStatus').textContent=e.message}}

async function downloadTemplate(){await loadXLSX();const examples={customerPrices:[{cliente:'Nombre del cliente',ruc:'0991234567001',referencia:'SKU-001',codigo_barras:'376000000001',precio_contrato:12.5,contrato:'CTR-2026-01'}],products:[{name:'Producto ejemplo',description:'Descripción del producto',reference:'SKU-001',barcode:'376000000001',category:'Categoría',family:'Familia',lines:'Línea',brand:'Marca',presentation:'Caja x12',location:'Z01-A01',stock:10,min_stock:2,max_stock:100,qty_per_carton:12,weight_g:500,volume_cm3:1000,sale_price:12.5,sale_price_b:14,purchase_price:7,tax_rate:15}],clients:[{name:'Cliente ejemplo',email:'cliente@example.com',phone:'000000000',address:'Dirección',city:'Quito',province:'Pichincha',tax_id:'ID-001',category:'A',notes:''}],suppliers:[{name:'Proveedor ejemplo',email:'proveedor@example.com',phone:'000000000',address:'Dirección',city:'Quito',contact_name:'Persona de contacto',tax_id:'ID-001',notes:''}]};const wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,XLSX.utils.json_to_sheet(examples[state.type]),LABELS[state.type]);XLSX.writeFile(wb,'GAMA_'+state.type+'_plantilla.xlsx');}
function esc(v){return window.ArcUI.esc(v)}
css();window.GamaExcelImport={render,_mapRowForTests:mapRow,_importTariffsForTests:importarTarifas,_refIndexForTests:refIndex,_matchProductForTests:matchProduct,_baseNameForTests:baseName};if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',render,{once:true});else render();
})();