/* GAMA Stock Manager — Import Excel module
 * Bulk import Products / Clients / Suppliers from one workbook.
 * Uses SheetJS in the browser and keeps the module isolated from the core UI.
 */
(function(){
  'use strict';
  const MOD='gamaExcelImport';
  const SUP_KEY='gama_suppliers_v1';
  const CLIENT_KEY='gama_clients_v1';
  const DB_KEYS=['gama_db','gamaStockDB','gama_stock_db','gamaData','gama_data'];
  const XLSX_URL='https://cdn.sheetjs.com/xlsx-0.20.3/package/dist/xlsx.full.min.js';
  let state={workbook:null,file:null,type:'products',rows:[],headers:[],sheet:''};

  const $=id=>document.getElementById(id);
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const norm=v=>String(v??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim().replace(/[^a-z0-9]+/g,'');
  const uid=()=>crypto.randomUUID?crypto.randomUUID():Date.now().toString(36)+Math.random().toString(36).slice(2);
  function load(k,f=[]){try{const v=JSON.parse(localStorage.getItem(k)||'null');return Array.isArray(v)?v:f}catch(e){return f}}
  function save(k,v){try{localStorage.setItem(k,JSON.stringify(v));}catch(e){}}
  function injectStyles(){
    if($('gamaExcelStyles'))return;
    const s=document.createElement('style');s.id='gamaExcelStyles';
    s.textContent=`
      #excelImport{scroll-margin-top:90px}.gxiHead{display:flex;justify-content:space-between;align-items:flex-start;gap:12px;margin-bottom:15px}.gxiHead h2{margin:0;font-size:27px}.gxiHead p{margin:5px 0;color:#71808a}.gxiSteps{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-bottom:12px}.gxiStep{padding:10px;border:1px solid var(--gama-line,#e2e8ec);border-radius:11px;background:#f7f9fa;color:#71808a;font-size:12px;font-weight:750}.gxiStep.active{background:#eaf7f7;color:#087c8b;border-color:#9ed6d9}.gxiGrid{display:grid;grid-template-columns:1.25fr .75fr;gap:12px}.gxiCard{background:#fff;border:1px solid var(--gama-line,#e2e8ec);border-radius:15px;padding:16px}.gxiTypes{display:grid;grid-template-columns:repeat(3,1fr);gap:9px}.gxiType{border:1px solid #dce5e8;background:#fff;border-radius:12px;padding:14px;text-align:left;cursor:pointer;color:#18324a}.gxiType.active{border:2px solid #087c8b;background:#f2fbfb}.gxiType .ico{width:42px;height:42px;border-radius:12px;display:grid;place-items:center;background:#eaf7f7;color:#087c8b;font-size:22px;margin-bottom:8px}.gxiType.client .ico{background:#edf8f0;color:#128c68}.gxiType.supplier .ico{background:#f4efff;color:#6d42d8}.gxiDrop{border:2px dashed #b9cbd1;border-radius:14px;padding:28px 15px;text-align:center;background:#fbfdfe;cursor:pointer}.gxiDrop.drag{border-color:#087c8b;background:#effafa}.gxiDrop strong{display:block;font-size:16px}.gxiDrop small{display:block;color:#71808a;margin:7px 0 14px}.gxiFile{display:inline-flex;align-items:center;gap:8px;background:#087c8b;color:#fff;border-radius:9px;padding:10px 14px;font-weight:750}.gxiInfo{font-size:12px;color:#71808a;line-height:1.55}.gxiInfo b{color:#18324a}.gxiMap{display:grid;grid-template-columns:1fr 1fr;gap:8px}.gxiMap label{font-size:11px}.gxiMap select{padding:9px;font-size:13px}.gxiPreview{overflow:auto;margin-top:12px}.gxiPreview table{min-width:760px;width:100%;border-collapse:collapse}.gxiPreview th,.gxiPreview td{padding:8px;border-bottom:1px solid #edf1f2;font-size:11px;text-align:left}.gxiPreview th{background:#f4f7f8}.gxiStats{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin:10px 0}.gxiStat{background:#f7f9fa;border-radius:11px;padding:10px}.gxiStat small{display:block;color:#71808a}.gxiStat b{font-size:19px}.gxiResult{padding:10px;border-radius:9px;margin-top:8px}.gxiGood{background:#eaf7f0;color:#116b51}.gxiWarn{background:#fff7e8;color:#8a5a08}.gxiBad{background:#fff0ee;color:#a63c33}.gxiActions{display:flex;gap:8px;flex-wrap:wrap;margin-top:12px}.gxiBadge{display:inline-block;padding:4px 7px;border-radius:99px;background:#eef3f5;color:#60717b;font-size:10px;font-weight:750}.gxiReq{margin-top:10px;font-size:11px;color:#71808a}.gxiHelp{margin-top:12px;background:#fff6ef;border-left:4px solid #f47a2a;border-radius:8px;padding:11px;font-size:12px;color:#6f5a4e}
      @media(max-width:800px){.gxiGrid{grid-template-columns:1fr}.gxiTypes{grid-template-columns:1fr}.gxiSteps{grid-template-columns:1fr 1fr}.gxiStats{grid-template-columns:1fr 1fr}.gxiMap{grid-template-columns:1fr}.gxiHead{flex-direction:column}.gxiHead h2{font-size:24px}}
    `;document.head.appendChild(s);
  }
  function section(){
    let s=$('excelImport');if(s)return s;
    s=document.createElement('section');s.id='excelImport';
    const wrap=document.querySelector('.wrap')||document.body;wrap.appendChild(s);return s;
  }
  function icon(type){return type==='products'?'▣':type==='clients'?'👥':'🚚'}
  function required(type){
    return type==='products'?['reference','name']:type==='clients'?['name']:['name'];
  }
  const aliases={
    reference:['reference','ref','code','sku','article','articlenumber','productcode','codigo','referencia'],
    name:['name','nom','nombre','product','productname','client','customer','supplier','fournisseur','proveedor','raison sociale','raisonsociale'],
    category:['category','categorie','categoría','familia'],barcode:['barcode','ean','codebarres','codigo barras','gtin'],
    unit:['unit','unite','unidad'],purchasePrice:['purchaseprice','prixachat','cost','cout','coût'],salePrice:['saleprice','prixvente','price','prix','precio'],
    stock:['stock','stockinitial','initialstock','quantite','quantity','qty'],minStock:['minimumstock','stockminimum','minstock','seuil'],description:['description','details','notes'],
    email:['email','mail','correo'],phone:['phone','telephone','tel','telefono'],address:['address','adresse','direccion'],city:['city','ville','ciudad'],
    tax:['tax','vat','tva','ruc','siret','identification'],contact:['contact','contactperson','personcontact','contacto'],payment:['paymentterms','conditionspaiement','condicionespago']
  };
  function findHeader(headers,key){
    const a=aliases[key]||[key], nh=headers.map(norm);for(const wanted of a){const i=nh.indexOf(norm(wanted));if(i>=0)return headers[i]}
    return '';
  }
  function pickSheet(wb,type){
    const names=wb.SheetNames||[];const wanted=type==='products'?['produits','products','producto','articles']:type==='clients'?['clients','customers','clientes']:['fournisseurs','suppliers','proveedores'];
    return names.find(n=>wanted.some(w=>norm(n).includes(norm(w))))||names[0]||'';
  }
  function rowsFromSheet(wb,sheet){
    const ws=wb.Sheets[sheet];if(!ws)return {headers:[],rows:[]};
    const data=XLSX.utils.sheet_to_json(ws,{defval:'',raw:false});
    const headers=data.length?Object.keys(data[0]):XLSX.utils.sheet_to_json(ws,{header:1,defval:''})[0]||[];
    return {headers,rows:data};
  }
  function selectType(type){state.type=type;state.sheet=state.workbook?pickSheet(state.workbook,type):'';if(state.workbook){const r=rowsFromSheet(state.workbook,state.sheet);state.headers=r.headers;state.rows=r.rows}render()}
  function loadXLSX(){
    if(window.XLSX)return Promise.resolve(window.XLSX);
    return new Promise((resolve,reject)=>{const s=document.createElement('script');s.src=XLSX_URL;s.onload=()=>window.XLSX?resolve(window.XLSX):reject(new Error('XLSX indisponible'));s.onerror=()=>reject(new Error('Impossible de charger le moteur Excel'));document.head.appendChild(s)})
  }
  async function readFile(file){
    if(!file)return;if(file.size>10*1024*1024){alert('Le fichier dépasse la limite de 10 Mo.');return}
    try{const lib=await loadXLSX();const wb=lib.read(await file.arrayBuffer(),{type:'array',cellDates:true});state.file=file;state.workbook=wb;state.sheet=pickSheet(wb,state.type);const r=rowsFromSheet(wb,state.sheet);state.headers=r.headers;state.rows=r.rows;render()}catch(e){alert('Fichier Excel invalide : '+e.message)}}
  function normalizedRow(row){const out={};Object.keys(aliases).forEach(k=>{const h=findHeader(state.headers,k);out[k]=h?row[h]:''});return out}
  function render(){
    injectStyles();const s=section();
    const types=[['products','Produits','Références, prix, stock',''],['clients','Clients','Contacts et coordonnées','client'],['suppliers','Fournisseurs','Contacts et conditions','supplier']];
    const has=!!state.file;
    s.innerHTML=`<div class="card"><div class="gxiHead"><div><h2>📊 Import Excel</h2><p>Importez vos <b>produits, clients et fournisseurs</b> directement depuis un fichier Excel.</p></div><span class="gxiBadge">.xlsx · .xls · max. 10 Mo</span></div>
      <div class="gxiSteps"><div class="gxiStep active">1 · Sélection</div><div class="gxiStep ${has?'active':''}">2 · Prévisualisation</div><div class="gxiStep">3 · Import</div><div class="gxiStep">4 · Résultats</div></div>
      <div class="gxiGrid"><div class="gxiCard"><h3 style="margin-top:0">Que souhaitez-vous importer ?</h3><div class="gxiTypes">${types.map(t=>`<button type="button" class="gxiType ${t[3]} ${state.type===t[0]?'active':''}" data-gxi-type="${t[0]}"><div class="ico">${icon(t[0])}</div><b>${t[1]}</b><small style="display:block;color:#71808a;margin-top:4px">${t[2]}</small></button>`).join('')}</div>
      <div class="gxiDrop" id="gxiDrop" style="margin-top:12px"><div style="font-size:35px">☁️</div><strong>${has?esc(state.file.name):'Glissez-déposez votre fichier Excel ici'}</strong><small>${has?'Fichier chargé · '+state.rows.length+' ligne(s)':'ou cliquez pour sélectionner un fichier'}</small><label class="gxiFile">📁 Choisir un fichier<input id="gxiFile" type="file" accept=".xlsx,.xls" hidden></label></div>
      <div class="gxiHelp"><b>Conseil :</b> pour un import sans erreur, utilisez une feuille par type : <b>Produits</b>, <b>Clients</b> et <b>Fournisseurs</b>. Les colonnes sont reconnues même si leurs intitulés sont en français ou en anglais.</div></div>
      <div class="gxiCard"><h3 style="margin-top:0">Feuille Excel</h3><select id="gxiSheet" ${!state.workbook?'disabled':''}>${(state.workbook?.SheetNames||[]).map(n=>`<option ${n===state.sheet?'selected':''}>${esc(n)}</option>`).join('')}</select><p class="gxiInfo"><b>Colonnes obligatoires</b><br>${required(state.type).map(k=>`• ${k==='reference'?'Référence':k==='name'?'Nom':'Nom / raison sociale'}`).join('<br>')}<br><br><b>Détection automatique</b><br>Référence, nom, catégorie, prix, stock, email, téléphone, adresse, TVA/RUC, contact, etc.</p><div id="gxiMap"></div></div></div>
      ${has?previewHtml():''}<div class="gxiActions"><button class="primary" id="gxiImport" ${has&&state.rows.length?'':'disabled'}>⬆ Importer ${state.rows.length||''} ligne(s)</button><button class="secondary" id="gxiReset">Réinitialiser</button></div><div id="gxiResult"></div></div>`;
    s.querySelectorAll('[data-gxi-type]').forEach(b=>b.onclick=()=>selectType(b.dataset.gxiType));
    $('gxiFile').onchange=e=>readFile(e.target.files[0]);$('gxiReset').onclick=()=>{state={workbook:null,file:null,type:'products',rows:[],headers:[],sheet:''};render()};
    if($('gxiSheet'))$('gxiSheet').onchange=e=>{state.sheet=e.target.value;const r=rowsFromSheet(state.workbook,state.sheet);state.headers=r.headers;state.rows=r.rows;render()};
    const drop=$('gxiDrop');drop.ondragover=e=>{e.preventDefault();drop.classList.add('drag')};drop.ondragleave=()=>drop.classList.remove('drag');drop.ondrop=e=>{e.preventDefault();drop.classList.remove('drag');readFile(e.dataTransfer.files[0])};drop.onclick=e=>{if(e.target.tagName!=='INPUT'&&!e.target.closest('.gxiFile'))$('gxiFile').click()};
    if($('gxiImport'))$('gxiImport').onclick=importRows;
  }
  function previewHtml(){
    const preview=state.rows.slice(0,8);const keys=state.headers.slice(0,8);const missing=required(state.type).filter(k=>!findHeader(state.headers,k));
    return `<div class="gxiCard" style="margin-top:12px"><div style="display:flex;justify-content:space-between;gap:10px;align-items:center"><h3 style="margin:0">Prévisualisation</h3><span class="gxiBadge">${state.rows.length} ligne(s) · feuille « ${esc(state.sheet)} »</span></div><div class="gxiStats"><div class="gxiStat"><small>Lignes</small><b>${state.rows.length}</b></div><div class="gxiStat"><small>Colonnes</small><b>${state.headers.length}</b></div><div class="gxiStat"><small>Obligatoires OK</small><b>${missing.length?'Non':'Oui'}</b></div><div class="gxiStat"><small>Feuille</small><b>${esc(state.sheet)}</b></div></div>${missing.length?`<div class="gxiResult gxiBad">Colonnes obligatoires introuvables : ${missing.map(esc).join(', ')}.</div>`:''}<div class="gxiPreview"><table><thead><tr>${keys.map(h=>`<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${preview.map(r=>`<tr>${keys.map(k=>`<td>${esc(r[k])}</td>`).join('')}</tr>`).join('')}</tbody></table></div></div>`
  }
  async function importRows(){
    const missing=required(state.type).filter(k=>!findHeader(state.headers,k));if(missing.length){alert('Import impossible : colonnes obligatoires manquantes.');return}
    const result={inserted:0,skipped:0,errors:[],cloud:0};const rows=state.rows.map(normalizedRow);
    if(state.type==='suppliers'){
      const arr=load(SUP_KEY);const seen=new Set(arr.map(x=>norm(x.name)));rows.forEach((r,i)=>{const name=String(r.name||'').trim();if(!name){result.skipped++;result.errors.push('Ligne '+(i+2)+' : nom fournisseur vide');return}if(seen.has(norm(name))){result.skipped++;return}arr.push({id:uid(),name,tax:String(r.tax||''),contact:String(r.contact||''),phone:String(r.phone||''),email:String(r.email||''),city:String(r.city||''),address:String(r.address||''),notes:String(r.description||r.payment||'')});seen.add(norm(name));result.inserted++});save(SUP_KEY,arr);
    }else if(state.type==='clients'){
      const arr=load(CLIENT_KEY);const seen=new Set(arr.map(x=>norm(x.email||x.name)));rows.forEach((r,i)=>{const name=String(r.name||'').trim();if(!name){result.skipped++;result.errors.push('Ligne '+(i+2)+' : nom client vide');return}const key=norm(r.email||name);if(seen.has(key)){result.skipped++;return}arr.push({id:uid(),name,email:String(r.email||''),phone:String(r.phone||''),address:String(r.address||''),city:String(r.city||''),tax:String(r.tax||''),notes:String(r.description||r.payment||'')});seen.add(key);result.inserted++});save(CLIENT_KEY,arr);
    }else{
      let db=window.db;if(!db||typeof db!=='object')db={products:[]};if(!Array.isArray(db.products))db.products=[];const seen=new Set(db.products.map(x=>norm(x.barcode||x.reference||x.name)));const cloud=window.GamaCloudProducts;
      for(let i=0;i<rows.length;i++){const r=rows[i],name=String(r.name||'').trim(),reference=String(r.reference||'').trim(),barcode=String(r.barcode||reference).trim();if(!name||!reference){result.skipped++;result.errors.push('Ligne '+(i+2)+' : référence ou nom manquant');continue}const key=norm(barcode||reference||name);if(seen.has(key)){result.skipped++;continue}const p={id:uid(),reference,name,barcode,category:String(r.category||''),unit:String(r.unit||''),purchasePrice:Number(String(r.purchasePrice||'').replace(',','.'))||0,salePrice:Number(String(r.salePrice||'').replace(',','.'))||0,stock:Number(String(r.stock||'').replace(',','.'))||0,minStock:Number(String(r.minStock||'').replace(',','.'))||0,description:String(r.description||'')};db.products.push(p);seen.add(key);result.inserted++;if(cloud&&typeof cloud.createProduct==='function'){try{await cloud.createProduct(p);result.cloud++}catch(e){}}}
      window.db=db;DB_KEYS.forEach(k=>save(k,db));try{localStorage.setItem('gama_products',JSON.stringify(db.products))}catch(e){}window.dispatchEvent(new CustomEvent('gama:products-imported',{detail:result}));
    }
    renderResult(result);
  }
  function renderResult(r){const el=$('gxiResult');if(!el)return;el.innerHTML=`<div class="gxiResult gxiGood"><b>Import terminé.</b> ${r.inserted} ligne(s) importée(s), ${r.skipped} ignorée(s).${r.cloud?' Synchronisation cloud : '+r.cloud+'.':''}</div>${r.errors.length?`<div class="gxiResult gxiWarn"><b>À vérifier :</b><br>${r.errors.slice(0,12).map(esc).join('<br>')}${r.errors.length>12?'<br>…':''}</div>`:''}`}
  function replaceEmptyMenu(){
    const host=$('mainmenu');if(!host)return false;
    const buttons=[...host.querySelectorAll('button')];let target=buttons.find(b=>{const t=(b.innerText||'').toLowerCase();return t.includes('agenda')||t.includes('calendrier')||t.includes('calendar')});
    if(!target)return false;
    if(target.dataset.gxiDone)return true;target.dataset.gxiDone='1';target.onclick=()=>window.showTab&&window.showTab('excelImport',null);
    const title=target.querySelector('.gamaApp b,.gamaF2Title,.gamaMenuTitle');if(title)title.textContent='Import Excel';
    const sub=target.querySelector('small');if(sub)sub.textContent='Produits, clients, fournisseurs';
    const ico=target.querySelector('.gamaIcon,.gamaMenuIcon,.gamaF2Icon');if(ico){ico.innerHTML='<span style="font-size:30px;line-height:1">▦</span>';ico.classList.add('orange')}
    return true;
  }
  function hook(){
    injectStyles();section();
    const old=window.showTab;if(old&&!old.__gamaExcel){window.showTab=function(id,el){if(id==='excelImport')render();return old.apply(this,arguments)};window.showTab.__gamaExcel=true}
    replaceEmptyMenu();const host=$('mainmenu');if(host&&!host.__gxiObs){host.__gxiObs=true;new MutationObserver(()=>replaceEmptyMenu()).observe(host,{childList:true,subtree:true})}
  }
  function boot(){hook();setTimeout(hook,250);setTimeout(hook,1000)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
