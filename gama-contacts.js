/* Contactos: clientes, proveedores y contactos de prospectos en una sola tabla.
   Arriba se elige la categoría —todas o una de las tres— y se busca; cada fila
   abre, encima de la tabla, la ficha que ya existía: la del cliente, la del
   proveedor o la del CRM. Las tablas de la base no cambian: la lista sólo las
   reúne, y cada categoría se ve con el derecho que ya la protegía. */
(function(){'use strict';
const U=window.ArcUI,esc=U.esc,$=id=>document.getElementById(id);
const T=s=>window.GamaI18n?.t?.(s)||s,tr=s=>`<span data-gi-live>${esc(s)}</span>`;
const KINDS=[
 {id:'clients',label:'Clientes',one:'Cliente',hint:'Quien te compra: ficha, condiciones de pago y categoría de precios.'},
 {id:'suppliers',label:'Proveedores',one:'Proveedor',hint:'A quien le compras: contacto y condiciones.'},
 {id:'prospects',label:'Contactos de prospectos',one:'Contacto de prospecto',hint:'Una persona de una empresa que aún no es cliente, con su papel en la decisión.'}
];
const ALL_HINT='Todos tus contactos en una sola lista: elige una categoría o busca por nombre, identificación, empresa, ciudad o correo.';
const ARCHIVE='contacts',PAGE=20;
let kind='all',rows=null,grid=null,closeForm=null,clientsPane=null,pendingNew=null,pendingShow=null,epoch=0;
// Clientes y proveedores son del módulo Contactos; los contactos de prospectos, del CRM.
const can=id=>!!window.gamaAccessAllowed?.(id==='prospects'?'crm':'contacts');
const kinds=()=>KINDS.filter(k=>can(k.id));
const kindOf=id=>KINDS.find(k=>k.id===id);
const norm=v=>String(v??'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'');
function section(){let s=$('contacts');if(!s){s=document.createElement('section');s.id='contacts';(document.querySelector('.wrap')||document.body).append(s)}return s}
const active=()=>window.ArcRouter.current==='contacts'&&section().classList.contains('active');

/* ---- datos: tres tablas, una lista ---- */
async function load(){
 if(rows)return rows;
 const token=epoch,D=window.ArcData,E=window.ArcEntities,out=[];
 const take=r=>{if(r.error)throw r.error;return r.data||[]};
 const jobs=[];
 if(can('clients'))jobs.push(D.all('customers',{select:E.entities.customers.select,order:'name'},true).then(r=>{for(const x of take(r)){const c=E.customerFromRow(x);
  out.push({key:'clients:'+c.id,kind:'clients',id:c.id,name:c.name,detail:c.category?T('Categoría de precios')+' '+c.category:'',ref:c.taxId,phone:c.phone,email:c.email,city:c.city,active:c.active,record:c})}}));
 if(can('suppliers'))jobs.push(D.all('suppliers',{select:E.entities.suppliers.select,order:'name'},true).then(r=>{for(const x of take(r)){const s=E.supplierFromRow(x);
  out.push({key:'suppliers:'+s.id,kind:'suppliers',id:s.id,name:s.name,detail:s.contactName?T('Contacto')+': '+s.contactName:'',ref:s.taxId,phone:s.phone,email:s.email,city:s.city,active:s.active,record:s})}}));
 if(can('prospects'))jobs.push(Promise.all([
  D.all('crm_contacts',{select:'id,first_name,last_name,job_title,email,phone,lead_id,is_primary,active',order:'id'},true),
  D.all('crm_leads',{select:'id,company,first_name,last_name,city',order:'id'},true)]).then(([k,l])=>{
  const leads=new Map(take(l).map(x=>[x.id,x]));
  for(const x of take(k)){if(!x.lead_id)continue;const lead=leads.get(x.lead_id)||{};
   const name=[x.first_name,x.last_name].filter(Boolean).join(' ').trim()||x.email||T('(sin nombre)');
   out.push({key:'prospects:'+x.id,kind:'prospects',id:x.id,name,detail:[x.job_title,x.is_primary?T('★ Principal'):''].filter(Boolean).join(' · '),
    ref:String(lead.company||'').trim()||[lead.first_name,lead.last_name].filter(Boolean).join(' '),phone:x.phone,email:x.email,city:lead.city,active:x.active!==false,record:x})}}));
 await Promise.all(jobs);
 // Otra sesión entró mientras tanto: no se guarda lo de la anterior.
 if(token!==epoch)return [];
 const order=Object.fromEntries(KINDS.map((k,i)=>[k.id,i]));
 out.sort((a,b)=>a.name.localeCompare(b.name,undefined,{sensitivity:'base'})||order[a.kind]-order[b.kind]);
 rows=out;return rows;
}
function refresh(){rows=null;if(grid&&$('ctTable')?.isConnected)grid.refresh()}
const matches=(r,terms)=>{if(!terms.length)return true;const h=norm([r.name,r.detail,r.ref,r.phone,r.email,r.city,T(kindOf(r.kind).one)].join(' '));return terms.every(t=>h.includes(t))};
async function source(req){
 const all=await load(),archived=window.GamaArchive.mode(ARCHIVE)==='archived';
 const inKind=all.filter(r=>kind==='all'||r.kind===kind);
 // Los contadores de las categorías cuentan lo que hay, no lo que coincide con la búsqueda.
 const count=k=>all.filter(r=>(k==='all'||r.kind===k)&&r.active!==archived).length;
 section().querySelectorAll('[data-ct-count]').forEach(n=>n.textContent=count(n.dataset.ctCount));
 const box=$('ctArchive');if(box)box.innerHTML=window.GamaArchive.tabs(ARCHIVE,inKind.filter(r=>r.active).length,inKind.filter(r=>!r.active).length);
 const terms=norm(req.search).split(/\s+/).filter(Boolean);
 let items=inKind.filter(r=>r.active!==archived&&matches(r,terms));
 const by={name:r=>r.name,kind:r=>T(kindOf(r.kind).one),city:r=>r.city||'',ref:r=>r.ref||''}[req.sort];
 if(by){const dir=req.ascending===false?-1:1;items=[...items].sort((a,b)=>dir*String(by(a)).localeCompare(String(by(b)),undefined,{sensitivity:'base'}))}
 return {items:items.slice(req.page*req.pageSize,(req.page+1)*req.pageSize),total:items.length,page:req.page,pageSize:req.pageSize};
}

/* ---- tabla ---- */
function actions(r){
 const b=(label,attr,variant)=>U.button({label:T(label),variant,attrs:attr+'="'+esc(r.key)+'"'});
 const out=[];
 if(r.kind!=='prospects')out.push(b('Historial','data-ct-history'));
 if(r.active)out.push(b('✏️ Editar','data-ct-edit'),b('🗄️ Archivar','data-ct-archive','danger'));
 else{out.push(b('♻️ Restaurar','data-ct-restore'));if(r.kind!=='prospects')out.push(b('🗑️ Borrar definitivamente','data-ct-purge','danger'))}
 return out.join(' ');
}
const columns=()=>[
 {label:'Nombre',sort:'name',html:r=>`<b>${esc(r.name)}</b>${r.detail?`<small class="ctSub">${esc(r.detail)}</small>`:''}`},
 {label:'Categoría',sort:'kind',html:r=>`<span class="ctBadge" data-kind="${r.kind}">${esc(T(kindOf(r.kind).one))}</span>`},
 {label:'Identificación / empresa',sort:'ref',value:r=>r.ref||'—'},
 {label:'Teléfono',value:r=>r.phone||'—'},
 {label:'Correo',value:r=>r.email||'—'},
 {label:'Ciudad',sort:'city',value:r=>r.city||'—'},
 {label:'Acciones',actions:true,html:actions}
];
const find=key=>(rows||[]).find(r=>r.key===key);
const say=text=>{const s=$('ctStatus');if(s)s.textContent=text?T(text):''};
async function archive(key,on){
 const r=find(key);if(!r)return;say('');
 try{
  if(r.kind==='clients'){await(on?window.restoreClient(r.id):window.deleteClient(r.id));window.ArcData.invalidate('customers')}
  else{
   if(!on&&r.kind==='suppliers'&&!confirm(T('¿Archivar al proveedor «')+r.name+'»?'))return;
   const table=r.kind==='suppliers'?'suppliers':'crm_contacts',x=await window.GamaCloud.update(table,r.id,{active:on});if(x.error)throw x.error;
   window.ArcData.invalidate(table);window.dispatchEvent(new CustomEvent('gama:data-change',{detail:{table}}));
   say(on?'Contacto restaurado.':'Contacto archivado.');
  }
 }catch(e){say(window.GamaArchive.friendlyError(e,r.kind==='suppliers'?'supplier':'client'))}
 refresh();
}
async function purge(key){
 const r=find(key);if(!r)return;say('');
 try{
  if(r.kind==='clients'){await window.purgeClient(r.id);window.ArcData.invalidate('customers')}
  else if(r.kind==='suppliers'){
   if(!confirm(T('¿Borrar definitivamente a «')+r.name+'»?'))return;
   const x=await window.GamaCloud.remove('suppliers',r.id);if(x.error)throw x.error;
   window.ArcData.invalidate('suppliers');window.dispatchEvent(new CustomEvent('gama:data-change',{detail:{table:'suppliers'}}));
  }
 }catch(e){say(window.GamaArchive.friendlyError(e,r.kind==='suppliers'?'supplier':'client'))}
 refresh();
}

/* ---- la ficha, encima de la tabla ---- */
// La ficha de cliente es HTML de index.html con sus funciones globales: se traslada una vez, intacta, y queda siempre en el documento.
function clientsHost(){
 if(!clientsPane){
  clientsPane=document.createElement('div');clientsPane.id='contactsClients';
  const legacy=$('clients');
  if(legacy){legacy.querySelectorAll(':scope>.gamaStdHeader').forEach(h=>h.remove());clientsPane.append(...legacy.childNodes);legacy.remove()}
  const saveButton=clientsPane.querySelector('[onclick^="saveClient"]');
  // Guardado con éxito = el formulario queda vacío: se cierra la ficha y la tabla se pone al día.
  if(saveButton)saveButton.onclick=async()=>{await window.saveClient?.();if(!$('cName')?.value&&!$('editingClientId')?.value){closeEditor();refresh()}};
 }
 return clientsPane;
}
function editorBody(){return $('ctEditor')?.querySelector('.ctEditorBody')}
function closeEditor(){
 const box=$('ctEditor');const f=closeForm;closeForm=null;f?.();
 if(clientsPane&&$('ctHold'))$('ctHold').append(clientsPane);
 if(!box)return;box.hidden=true;box.dataset.kind='';editorBody()?.replaceChildren();
}
function focus(el){if(!el)return;el.scrollIntoView?.({block:'center'});try{el.focus()}catch(_){}}
function openEditor(k,record=null,keep=false){
 closeEditor();
 const box=$('ctEditor'),body=editorBody();if(!box||!body||!can(k))return;
 box.hidden=false;box.dataset.kind=k;
 if(k==='clients'){
  body.append(clientsHost());
  if(!keep){window.clearClientForm?.();$('pmCustomerProjects')?.replaceChildren();if(record)window.editClient?.(record.taxId)}
  focus($('cName'));return;
 }
 if(k==='suppliers'){
  closeForm=window.ArcDirectories.supplierForm(body,{supplier:record,onDone:saved=>{closeEditor();if(saved){say('Proveedor guardado.');refresh()}}});
  focus($('supName'));return;
 }
 closeForm=()=>window.GamaCRMContacts?.close(body);
 window.GamaCRMContacts?.edit(body,{id:record?.id,onDone:saved=>{closeEditor();if(saved){window.ArcData.invalidate('crm_contacts');say('Contacto guardado.');refresh()}}})
  .then(()=>focus(body.querySelector(record?'#crmKFirst':'#crmKProspecto')));
}
/* Al crear, lo primero es decir qué es: cliente, proveedor o contacto de un
   prospecto. Cada respuesta abre el formulario que le corresponde. */
function chooseKind(){
 const d=U.dialog({title:T('Nuevo contacto'),body:`<p>${tr('¿Qué clase de contacto es?')}</p><div class="ctKinds">${kinds().map(k=>`<button type="button" class="arcButton secondary" data-contact-kind="${k.id}"><b>${tr(k.one)}</b><small>${tr(k.hint)}</small></button>`).join('')}</div>`,onSave:async()=>{}});
 d.querySelector('[type=submit]').remove();
 // La ficha se abre cuando el diálogo ya se ha ido y ha devuelto el foco: si no, se lo quitaría al formulario.
 let chosen=null;d.addEventListener('close',()=>{if(chosen)openEditor(chosen)},{once:true});
 d.querySelectorAll('[data-contact-kind]').forEach(b=>b.onclick=()=>{chosen=b.dataset.contactKind;d.close()});
}

/* ---- pantalla ---- */
function setKind(k,{focusChip=false}={}){
 kind=k==='all'||kinds().some(x=>x.id===k)?k:'all';
 const s=section();
 s.querySelectorAll('[data-ct-kind]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.ctKind===kind)));
 const hint=$('contactsHint');if(hint)hint.innerHTML=tr(kind==='all'?ALL_HINT:kindOf(kind).hint);
 // Comparar ofertas y Fusionar duplicados dependen de la categoría elegida.
 s.querySelector('[data-controls-bar]')?.remove();window.ArchitectControls?.mount('contacts');
 if(focusChip)s.querySelector(`[data-ct-kind="${kind}"]`)?.focus();
 grid?.refresh({page:0});
}
function render(){
 const s=section(),list=kinds();
 if(kind!=='all'&&!list.some(k=>k.id===kind))kind='all';
 grid?.dispose();grid=null;closeForm?.();closeForm=null;
 const chip=(id,label)=>`<button type="button" class="ctKind" data-ct-kind="${id}" aria-pressed="${id===kind}">${tr(label)} <span class="ctCount" data-ct-count="${id}"></span></button>`;
 U.render(s,window.GamaUI.header({title:'Contactos',lead:'Clientes, proveedores y contactos de prospectos en una sola lista.',module:'contacts'})
  +`<div class="ctBar"><div class="ctKindFilter" role="group" aria-label="${esc(T('Categoría'))}">${chip('all','Todos')}${list.map(k=>chip(k.id,k.label)).join('')}</div><button type="button" class="arcButton primary" id="ctNew">${tr('＋ Nuevo contacto')}</button></div>`
  +`<div class="ctTools"><input id="ctSearch" type="search" autocomplete="off" aria-label="${esc(T('Buscar contactos'))}" placeholder="${esc(T('Buscar por nombre, identificación, empresa, ciudad o correo…'))}"><div id="ctArchive"></div></div>`
  +`<p class="gsHint" id="contactsHint"></p><p class="gsHint ctStatus" id="ctStatus" role="status"></p>`
  +`<div id="ctEditor" class="ctEditor" hidden><div class="ctEditorHead"><button type="button" class="arcButton secondary" id="ctClose">${tr('✕ Cerrar')}</button></div><div class="ctEditorBody"></div></div>`
  +`<div id="ctTable" class="ctTable"></div><div id="ctHold" hidden></div>`);
 window.GamaUI.bindBack(s);
 $('ctHold').append(clientsHost());
 s.querySelectorAll('[data-ct-kind]').forEach(b=>b.onclick=()=>setKind(b.dataset.ctKind,{focusChip:true}));
 $('ctNew').onclick=chooseKind;$('ctClose').onclick=closeEditor;
 const hint=$('contactsHint');hint.innerHTML=tr(kind==='all'?ALL_HINT:kindOf(kind).hint);
 grid=U.dataTable($('ctTable'),{columns:columns(),source,searchInput:$('ctSearch'),className:'ctList',empty:T('Ningún contacto en esta lista.'),initial:{pageSize:PAGE,sort:'name',ascending:true},actions:{
  'data-ct-edit':key=>{const r=find(key);if(r)openEditor(r.kind,r.record)},
  'data-ct-history':key=>{const r=find(key);if(r)window.ArchitectPartners?.open(r.kind==='clients'?'customer':'supplier',r.id)},
  'data-ct-archive':key=>archive(key,false),'data-ct-restore':key=>archive(key,true),'data-ct-purge':purge}});
 window.GamaSuppliers?.migrate?.();
 window.dispatchEvent(new CustomEvent('arc:module-rendered',{detail:{id:'contacts'}}));
 flush();
}
function flush(){
 if(pendingNew){const k=pendingNew;pendingNew=null;openEditor(k)}
 if(pendingShow){const k=pendingShow;pendingShow=null;openEditor(k,null,true)}
}
function open(which,opts={}){
 const wanted={clients:'clients',suppliers:'suppliers',prospects:'prospects',crm:'prospects'}[which];
 if(wanted&&can(wanted))kind=wanted;
 if(opts.create&&wanted)pendingNew=wanted;
 // El router pinta la pantalla al entrar (onEnter) y la cierra al salir.
 if(active()){setKind(kind);flush();return true}
 return window.ArcRouter.show('contacts');
}
// La ficha se rellena fuera (editClient, desde un cobro por ejemplo): aquí sólo se enseña, sin vaciarla.
function edit(k){
 if(active()){if($('ctEditor')?.dataset.kind!==k)openEditor(k,null,true);return true}
 pendingShow=k;return window.ArcRouter.show('contacts');
}
window.GamaArchive.register(ARCHIVE,()=>grid?.refresh({page:0}));
window.addEventListener('gama:data-change',e=>{if(['customers','suppliers','crm_contacts','crm_leads'].includes(e.detail?.table))refresh()});
window.addEventListener('gama:language-change',()=>{if(active())render()});
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;epoch++;rows=null});
window.ArcRouter.onEnter('contacts',()=>{
 // Los contactos del CRM no llegan en tiempo real: al entrar se leen de nuevo.
 for(const t of ['crm_contacts','crm_leads'])window.ArcData.invalidate(t);
 rows=null;render();return()=>{closeEditor();grid?.dispose();grid=null}});
window.GamaContacts={open,edit,refresh,tab:()=>kind};
})();
