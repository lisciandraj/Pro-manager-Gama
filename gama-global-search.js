(function(){
'use strict';
if(window.GamaGlobalSearch)return;
const Core=window.GamaSearchCore,$=id=>document.getElementById(id);
const copy={
 fr:{placeholder:'Rechercher dans GAMA…',title:'Recherche globale',hint:'Un nom, une référence, un code-barres ou une question métier.',close:'Fermer',loading:'Recherche en cours…',empty:'Aucun résultat. Essaie un nom, un code-barres ou une référence.',short:'Saisis au moins 2 caractères.',more:'Voir plus',scan:'Poursuivre la recherche',error:'Recherche indisponible pour certaines catégories. Réessaie.',retry:'Réessayer',auth:'Connecte-toi pour rechercher dans GAMA.',open:'Ouvrir le module',back:'Retour aux résultats',archived:'Archivé',results:'résultat(s)',keyboard:'↑ ↓ parcourir · Entrée ouvrir · Échap fermer',partial:'Les résultats sont chargés par pages.',balance:'Solde',total:'Montant',modules:'Modules',clients:'Clients',contacts:'Contacts',suppliers:'Fournisseurs',products:'Produits et codes-barres',quotes:'Devis',orders:'Commandes',shipments:'Expéditions',deliveries:'Livraisons',invoices:'Factures',payments:'Paiements',knowledge:'Knowledge',orders_late:'Commandes en retard : date promise dépassée avec quantité à expédier, ou livraison en retard.',shipments_late:'Livraisons en retard : date prévue dépassée, hors livraisons terminées et annulées.',invoices_unpaid:'Factures impayées : solde restant, paiements partiels inclus, hors factures annulées.',invoices_overdue:'Factures échues : solde restant et échéance dépassée.',invoices_paid:'Factures payées : solde nul, hors factures annulées.',quotes_unanswered:'Devis envoyés depuis plus de 7 jours, sans réponse.',suggestions:['commandes en retard','factures impayées','devis sans réponse','livraisons en retard']},
 es:{placeholder:'Buscar en GAMA…',title:'Búsqueda global',hint:'Un nombre, una referencia, un código de barras o una consulta de negocio.',close:'Cerrar',loading:'Buscando…',empty:'Sin resultados. Prueba un nombre, código de barras o referencia.',short:'Escribe al menos 2 caracteres.',more:'Ver más',scan:'Continuar búsqueda',error:'No se pudieron consultar algunas categorías. Reintenta.',retry:'Reintentar',auth:'Inicia sesión para buscar en GAMA.',open:'Abrir módulo',back:'Volver a resultados',archived:'Archivado',results:'resultado(s)',keyboard:'↑ ↓ recorrer · Intro abrir · Esc cerrar',partial:'Los resultados se cargan por páginas.',balance:'Saldo',total:'Importe',modules:'Módulos',clients:'Clientes',contacts:'Contactos',suppliers:'Proveedores',products:'Productos y códigos de barras',quotes:'Presupuestos',orders:'Pedidos',shipments:'Expediciones',deliveries:'Entregas',invoices:'Facturas',payments:'Pagos',knowledge:'Knowledge',orders_late:'Pedidos atrasados: fecha prometida vencida con cantidad pendiente de expedición, o entrega atrasada.',shipments_late:'Entregas atrasadas: fecha prevista vencida, sin entregas completadas o canceladas.',invoices_unpaid:'Facturas sin pagar: saldo pendiente, incluidos pagos parciales, sin facturas anuladas.',invoices_overdue:'Facturas vencidas: saldo pendiente y vencimiento superado.',invoices_paid:'Facturas pagadas: saldo cero, sin facturas anuladas.',quotes_unanswered:'Presupuestos enviados hace más de 7 días, sin respuesta.',suggestions:['pedidos atrasados','facturas sin pagar','presupuestos sin respuesta','entregas atrasadas']},
 en:{placeholder:'Search GAMA…',title:'Global search',hint:'A name, reference, barcode or business query.',close:'Close',loading:'Searching…',empty:'No results. Try a name, barcode or reference.',short:'Enter at least 2 characters.',more:'Show more',scan:'Continue searching',error:'Some categories could not be searched. Try again.',retry:'Retry',auth:'Sign in to search GAMA.',open:'Open module',back:'Back to results',archived:'Archived',results:'result(s)',keyboard:'↑ ↓ navigate · Enter open · Esc close',partial:'Results load in pages.',balance:'Balance',total:'Amount',modules:'Modules',clients:'Customers',contacts:'Contacts',suppliers:'Suppliers',products:'Products and barcodes',quotes:'Quotes',orders:'Orders',shipments:'Shipments',deliveries:'Deliveries',invoices:'Invoices',payments:'Payments',knowledge:'Knowledge',orders_late:'Late orders: overdue promised date with quantity still to ship, or an overdue delivery.',shipments_late:'Late deliveries: scheduled date passed, excluding completed and cancelled deliveries.',invoices_unpaid:'Unpaid invoices: remaining balance, including partial payments, excluding cancelled invoices.',invoices_overdue:'Overdue invoices: remaining balance and due date passed.',invoices_paid:'Paid invoices: zero balance, excluding cancelled invoices.',quotes_unanswered:'Quotes sent more than 7 days ago, with no response.',suggestions:['late orders','unpaid invoices','unanswered quotes','late deliveries']}
};
const lang=()=>copy[window.GamaI18n?.language]||copy.es,t=k=>lang()[k]||k;
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=v=>Number(v||0).toLocaleString(window.GamaI18n?.locale||'es-EC',{style:'currency',currency:'USD'});
const icon='<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/></svg>';
const marks={modules:'▦',clients:'CL',contacts:'CO',suppliers:'FO',products:'PR',quotes:'COT',orders:'PED',shipments:'ENV',deliveries:'ENT',invoices:'FAC',payments:'COB',knowledge:'K'};
let dialog,profile=null,client=null,version=0,sessionEpoch=0,closing=false,controller=null,timer=null,groups=[],parsed=null,active=-1,visible=[],busy=false,returnFocus=null;
const allowed=id=>!!window.gamaAccessAllowed?.(id);
function mount(input){
 input.placeholder=t('placeholder');input.setAttribute('aria-label',t('placeholder'));input.setAttribute('aria-haspopup','dialog');input.setAttribute('autocomplete','off');input.setAttribute('data-gi-ignore','');input.maxLength=160;
 input.onfocus=()=>{if(!closing)open(input.value)};input.oninput=()=>open(input.value);input.onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();open(input.value)}};
 const kbd=input.parentElement?.querySelector('kbd');if(kbd)kbd.textContent=/Mac|iPhone|iPad/.test(navigator.platform)?'⌘ K':'Ctrl K';
}
function ensure(){
 if(dialog)return;dialog=document.createElement('dialog');dialog.id='gamaSpotlight';dialog.className='gamaSpotlight';dialog.dataset.giIgnore='';dialog.setAttribute('aria-labelledby','gamaSpotlightTitle');
 dialog.innerHTML=`<h2 id="gamaSpotlightTitle" class="gspSr"></h2><div class="gspSearch">${icon}<input id="gspInput" type="search" maxlength="160" autocomplete="off" role="combobox" aria-autocomplete="list" aria-controls="gspList" aria-expanded="false"><button id="gspClose" type="button">×</button></div><div class="gspBody"><div id="gspHint"></div><div id="gspStatus" role="status" aria-live="polite"></div><div id="gspList" role="listbox"></div><div id="gspExtra"></div></div><footer id="gspFooter"></footer>`;
 document.body.appendChild(dialog);$('gspClose').onclick=close;dialog.addEventListener('cancel',e=>{e.preventDefault();close()});dialog.addEventListener('click',e=>{if(e.target===dialog){const b=dialog.getBoundingClientRect();if(e.clientX<b.left||e.clientX>b.right||e.clientY<b.top||e.clientY>b.bottom)close()}});
 $('gspInput').oninput=()=>{clearTimeout(timer);controller?.abort();version++;groups=[];visible=[];active=-1;render();timer=setTimeout(()=>run(),230)};
 $('gspInput').onkeydown=e=>{
  if(e.key==='Escape'){e.preventDefault();e.stopPropagation();close();return;}
  if(['ArrowDown','ArrowUp'].includes(e.key)&&visible.length){e.preventDefault();active=(active+(e.key==='ArrowDown'?1:-1)+visible.length)%visible.length;selection();}
  if(e.key==='Enter'&&visible.length){e.preventDefault();activate(visible[active<0?0:active]);}
 };
 dialog.addEventListener('close',()=>{clearTimeout(timer);controller?.abort();version++;groups=[];visible=[];active=-1;profile=null;client=null;$('gspList').replaceChildren();$('gspExtra').replaceChildren();$('gspInput').value='';$('gspInput').setAttribute('aria-expanded','false');document.body.classList.remove('gspOpen');});
}
function context(){return {client,profile,allowed,signal:controller?.signal};}
async function identity(){
 await window.GamaCloudReady;const c=await window.GamaCloud.db();const r=await window.GamaCloud.getProfile();
 if(r.error||!r.data||r.data.active===false)throw Error('AUTH_REQUIRED');return {client:c,profile:r.data};
}
async function open(value=''){
 ensure();if(dialog.open){if(value&&value!==$('gspInput').value){$('gspInput').value=value;run()}return;}
 returnFocus=document.activeElement;dialog.showModal();document.body.classList.add('gspOpen');$('gspInput').value=String(value||'').slice(0,160);$('gspInput').focus();labels();render();
 const epoch=sessionEpoch;
 try{const data=await identity();if(epoch!==sessionEpoch||!dialog.open)return;client=data.client;profile=data.profile;await run()}catch(e){if(epoch===sessionEpoch&&dialog.open)$('gspStatus').textContent=t('auth')}
}
function close(){closing=true;sessionEpoch++;if(dialog?.open)dialog.close();if(returnFocus?.id==='gamaF2Buscar'){returnFocus.value='';returnFocus.blur()}else returnFocus?.focus?.();queueMicrotask(()=>{closing=false});}
function labels(){if(!dialog)return;$('gamaSpotlightTitle').textContent=t('title');$('gspInput').placeholder=t('placeholder');$('gspInput').setAttribute('aria-label',t('placeholder'));$('gspClose').setAttribute('aria-label',t('close'));$('gspFooter').textContent=t('keyboard');}
function moduleItems(q){
 if(!profile||parsed?.intent||parsed?.ref||q.length<2)return [];
 return [...document.querySelectorAll('#mainmenu .gamaF2Card')].filter(b=>{const id=b.dataset.gamaModule||(b.dataset.gamaTmsCard!==undefined?'tms':'');return id&&allowed(id)&&Core.normalize(b.textContent).includes(Core.normalize(q));}).map(b=>({key:'module:'+b.dataset.gamaModule,id:b.dataset.gamaModule,source:'modules',module:b.dataset.gamaModule,title:b.querySelector('.gamaF2Title')?.textContent||b.textContent,subtitle:'',element:b,score:0}));
}
function selection(){
 $('gspList').querySelectorAll('[role=option]').forEach((el,i)=>el.setAttribute('aria-selected',String(i===active)));
 const el=$('gspList').querySelectorAll('[role=option]')[active];if(el){$('gspInput').setAttribute('aria-activedescendant',el.id);el.scrollIntoView({block:'nearest'})}else $('gspInput').removeAttribute('aria-activedescendant');
}
function render(){
 if(!dialog?.open)return;const q=$('gspInput').value.trim(),all=groups.flatMap(g=>g.items),mods=moduleItems(q);visible=[];
 $('gspHint').textContent=parsed?.intent?t(parsed.intent):t('hint');$('gspHint').className=parsed?.intent?'gspIntent':'gspHint';
 $('gspStatus').textContent=busy?t('loading'):q.length<2?t('short'):all.length+mods.length?`${all.length+mods.length} ${t('results')}`:t('empty');
 const sorted=[...groups].sort((a,b)=>Math.max(0,...b.items.map(i=>i.score))-Math.max(0,...a.items.map(i=>i.score)));if(mods.length)sorted.push({source:'modules',items:mods});
 $('gspList').innerHTML=sorted.filter(g=>g.items.length).map(g=>`<div role="group" aria-label="${esc(t(g.source))}"><div class="gspGroup">${esc(t(g.source))}<span>${g.items.length}</span></div>${[...g.items].sort((a,b)=>b.score-a.score||a.title.localeCompare(b.title)).map(r=>{const index=visible.push(r)-1;return `<div role="option" tabindex="-1" id="gspOption${index}" data-index="${index}" aria-selected="false"><span class="gspIcon">${esc(marks[r.source]||'↗')}</span><span class="gspText"><strong>${esc(r.title)}</strong><small>${esc(r.subtitle)}${r.archived?' · '+esc(t('archived')):''}</small></span>${r.balance!=null?`<span class="gspAmount">${esc(t('balance'))}<b>${esc(money(r.balance))}</b></span>`:r.total!=null?`<span class="gspAmount"><b>${esc(money(r.total))}</b></span>`:''}<span class="gspArrow" aria-hidden="true">↗</span></div>`}).join('')}</div>`).join('');
 $('gspInput').setAttribute('aria-expanded',String(visible.length>0));active=-1;selection();
 $('gspList').querySelectorAll('[data-index]').forEach(el=>{el.onclick=()=>activate(visible[Number(el.dataset.index)]);el.onpointermove=()=>{active=Number(el.dataset.index);selection()}});
 const more=groups.filter(g=>g.more),errors=groups.filter(g=>g.error);
 $('gspExtra').innerHTML=(q.length<2?`<div class="gspSuggestions">${t('suggestions').filter(s=>!profile||Core.selectedSources(Core.parse(s),context()).length).map(s=>`<button type="button" data-suggestion="${esc(s)}">${esc(s)}</button>`).join('')}</div>`:'')+(errors.length?`<p class="gspError">${esc(t('error'))} (${errors.map(g=>esc(t(g.source))).join(', ')})</p><button type="button" id="gspRetry">${esc(t('retry'))}</button>`:'')+(more.length?`<p class="gspHint">${esc(t('partial'))}</p><div class="gspMore">${more.map(g=>`<button type="button" data-more="${esc(g.source)}" ${busy?'disabled':''}>${esc(g.items.length?t('more'):t('scan'))} · ${esc(t(g.source))}</button>`).join('')}</div>`:'');
 $('gspExtra').querySelectorAll('[data-suggestion]').forEach(b=>b.onclick=()=>{$('gspInput').value=b.dataset.suggestion;run();$('gspInput').focus()});$('gspRetry')?.addEventListener('click',()=>run());$('gspExtra').querySelectorAll('[data-more]').forEach(b=>b.onclick=()=>run(b.dataset.more));
}
async function run(only){
 clearTimeout(timer);if(!profile||!client||!dialog?.open)return;controller?.abort();controller=new AbortController();const token=++version,q=$('gspInput').value.trim();parsed=Core.parse(q);
 const previous=only?groups.find(g=>g.source===only):null;if(!only)groups=[];busy=q.length>=2;render();if(!busy)return;
 try{const r=await Core.search(q,{...context(),only,offset:previous?.next||0});if(token!==version||!dialog.open)return;
  if(only){const next=r.groups[0];if(next){if(next.error){previous.error=true;}else{const items=[...new Map([...previous.items,...next.items].map(r=>[r.key,r])).values()];Object.assign(previous,next,{items})}}}
  else groups=r.groups;parsed=r.parsed;
 }catch(e){if(token===version&&!controller.signal.aborted)groups=[{source:only||'modules',items:[],error:true}]}finally{if(token===version){busy=false;render()}}
}
const details={
 clients:{table:'customers',select:'id,name,identification,email,phone,address,city,province,category,payment_terms_days,active'},
 products:{table:'products',select:'id,name,reference,barcode,category,brand,description,presentation,active'},
 contacts:{table:'crm_contacts',select:'id,first_name,last_name,job_title,email,phone,decision_role,is_primary,active'},
 suppliers:{table:'suppliers',select:'id,name,tax_id,contact_name,email,phone,address,city,country,active'}
};
const fieldLabels={fr:{name:'Nom',identification:'Identification',email:'E-mail',phone:'Téléphone',address:'Adresse',city:'Ville',province:'Province',category:'Catégorie',payment_terms_days:'Délai de paiement (jours)',reference:'Référence',barcode:'Code-barres',brand:'Marque',description:'Description',presentation:'Présentation',first_name:'Prénom',last_name:'Nom',job_title:'Fonction',decision_role:'Rôle de décision',is_primary:'Contact principal',tax_id:'Identification fiscale',contact_name:'Contact',country:'Pays',active:'Actif'},es:{name:'Nombre',identification:'Identificación',email:'Email',phone:'Teléfono',address:'Dirección',city:'Ciudad',province:'Provincia',category:'Categoría',payment_terms_days:'Plazo de pago (días)',reference:'Referencia',barcode:'Código de barras',brand:'Marca',description:'Descripción',presentation:'Presentación',first_name:'Nombre',last_name:'Apellidos',job_title:'Cargo',decision_role:'Papel de decisión',is_primary:'Contacto principal',tax_id:'Identificación fiscal',contact_name:'Contacto',country:'País',active:'Activo'},en:{name:'Name',identification:'Identification',email:'Email',phone:'Phone',address:'Address',city:'City',province:'Province',category:'Category',payment_terms_days:'Payment terms (days)',reference:'Reference',barcode:'Barcode',brand:'Brand',description:'Description',presentation:'Presentation',first_name:'First name',last_name:'Last name',job_title:'Job title',decision_role:'Decision role',is_primary:'Primary contact',tax_id:'Tax ID',contact_name:'Contact',country:'Country',active:'Active'}};
async function preview(r,c,signal){
 const spec=details[r.source];let query=c.from(spec.table).select(spec.select).eq('id',r.id).maybeSingle();if(signal)query=query.abortSignal(signal);const response=await query;
 if(response.error||!response.data)throw Error('NOT_FOUND');if(signal?.aborted)return;
 const data=response.data,labels=fieldLabels[window.GamaI18n?.language]||fieldLabels.es,queryText=$('gspInput').value;
 close();const d=document.createElement('dialog');d.className='gamaSpotlight gspRecord';d.dataset.giIgnore='';d.dataset.gamaSession='';d.setAttribute('aria-labelledby','gspRecordTitle');
 d.innerHTML=`<div class="gspRecordHead"><h2 id="gspRecordTitle">${esc(r.title)}</h2><button type="button" data-close aria-label="${esc(t('close'))}">×</button></div><dl>${Object.entries(data).filter(([key,v])=>key!=='id'&&v!=null&&v!=='').map(([key,v])=>`<div><dt>${esc(labels[key]||key)}</dt><dd>${esc(typeof v==='boolean'?(v?'✓':'—'):v)}</dd></div>`).join('')}</dl><div class="gspRecordActions"><button data-back>${esc(t('back'))}</button><button data-module>${esc(t('open'))}</button></div>`;
 document.body.appendChild(d);d.showModal();d.addEventListener('close',()=>d.remove());d.querySelector('[data-close]').onclick=()=>d.close();d.querySelector('[data-back]').onclick=()=>{d.close();open(queryText)};
 d.querySelector('[data-module]').onclick=()=>{d.close();document.querySelector(`#mainmenu [data-gama-module="${r.module}"]`)?.click()};
}
async function activate(r){
 if(!r||busy)return;busy=true;const token=version;controller?.abort();controller=new AbortController();const signal=controller.signal;
 try{
  const data=await identity();if(token!==version||signal.aborted)return;if(!Core.access(data.profile,r.module,allowed)&&r.source!=='modules')throw Error('AUTH_REQUIRED');if(!allowed(r.module))throw Error('AUTH_REQUIRED');
  if(details[r.source])return await preview(r,data.client,signal);
  close();
  if(r.source==='modules')return r.element.click();
  if(r.source==='orders')return await window.GamaSales.openOrder(r.id);
  if(r.source==='shipments')return await window.GamaSales.openOrder(r.orderId);
  if(r.source==='deliveries'){
   if(r.module==='client-deliveries')return await window.GamaQuotes.deliveries(r.id);
   if(allowed('tms'))return await window.gamaTMS.openDelivery(r.id);
   const found=await data.client.from('sales_deliveries').select('order_id').eq('tms_delivery_id',r.id).limit(1);if(found.error||!found.data?.[0])throw Error('NOT_FOUND');return await window.GamaSales.openOrder(found.data[0].order_id);
  }
  if(r.source==='quotes'){await window.GamaQuotes.open();return await window.GamaQuotes.view(r.id)}
  if(r.source==='invoices'){if(allowed('payments'))return await window.GamaPayments.open({invoiceId:r.id});return await window.GamaSales.openOrder(r.orderId)}
  if(r.source==='payments')return await window.GamaPayments.open({invoiceId:r.invoiceId});
  if(r.source==='knowledge')return await window.GamaKnowledge.openArticle(r.id);
 }catch(e){if(dialog?.open)$('gspStatus').textContent=t('error');else window.gamaToast?.(t('error'))}finally{busy=false}
}
function clear(){controller?.abort();version++;profile=null;client=null;groups=[];visible=[];busy=false;close();document.querySelectorAll('.gspRecord').forEach(d=>d.close());}
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event!=='TOKEN_REFRESHED')clear()});window.addEventListener('gama:modules-change',clear);window.addEventListener('storage',e=>{if(e.key==='gama_session_v1')clear()});
window.addEventListener('gama:language-change',()=>{const input=$('gamaF2Buscar');if(input)mount(input);labels();if(dialog?.open)render()});
document.addEventListener('keydown',e=>{if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='k'&&!e.altKey){e.preventDefault();open()}});
window.GamaGlobalSearch={open,close,mount};const input=$('gamaF2Buscar');if(input)mount(input);
})();
