/* Contactos: una sola tabla y un solo formulario. Clientes, proveedores y
   contactos de prospectos se listan juntos, cada uno con su tipo; al crear, el
   primer campo del formulario es el tipo de contacto y los demás cambian con
   él: la identificación y el plazo de pago de un cliente, la persona de
   contacto de un proveedor, el prospecto y el papel en la decisión de un
   contacto de prospecto. Las tablas de la base no cambian: la lista sólo las
   reúne, y cada tipo se ve y se crea con el derecho que ya lo protegía. */
(function(){'use strict';
const U=window.ArcUI,esc=U.esc,$=id=>document.getElementById(id);
const T=s=>window.GamaI18n?.t?.(s)||s,tr=s=>`<span data-gi-live>${esc(s)}</span>`;
const KINDS=[
 {id:'clients',one:'Cliente',table:'customers',hint:'Quien te compra: identificación, condiciones de pago y categoría de precios.'},
 {id:'suppliers',one:'Proveedor',table:'suppliers',hint:'A quien le compras: persona de contacto y condiciones.'},
 {id:'prospects',one:'Contacto de prospecto',table:'crm_contacts',hint:'Una persona de una empresa que aún no es cliente, con su papel en la decisión.'}
];
const PAPELES=[['decisor','Decisor'],['prescriptor','Prescriptor'],['usuario','Usuario'],['comprador','Comprador'],['otro','Otro']];
const CATEGORIAS=[['A','A · Mayorista (por defecto)'],['B','B · Venta al detalle'],['C','C · Contrato especial (tarifa)']];
/* Los campos de cada tipo, en su orden. Lo que tienen en común (nombre,
   teléfono, correo, ciudad…) se conserva al cambiar de tipo antes de guardar. */
const FIELDS={
 name:{label:'Nombre / razón social',required:true,maxLength:300},
 ident:{label:'RUC / identificación',maxLength:100},
 contactName:{label:'Persona de contacto',maxLength:200},
 lead:{label:'Prospecto',type:'select',required:true},
 firstName:{label:'Nombre',maxLength:120},
 lastName:{label:'Apellidos',maxLength:120},
 jobTitle:{label:'Cargo',maxLength:120},
 role:{label:'Papel en la decisión',type:'select',options:PAPELES},
 phone:{label:'Teléfono',type:'tel',maxLength:80},
 email:{label:'Correo',type:'email',maxLength:250},
 address:{label:'Dirección',maxLength:500},
 city:{label:'Ciudad',maxLength:200},
 province:{label:'Provincia',maxLength:120},
 category:{label:'Categoría de precios',type:'select',options:CATEGORIAS},
 terms:{label:'Plazo de pago desde la entrega (días)',type:'number',required:true,min:0,max:3650,step:1,help:'0 = pago a la entrega.'},
 linkedin:{label:'LinkedIn',maxLength:300},
 primary:{label:'Es el contacto principal del prospecto',type:'checkbox'},
 notes:{label:'Observaciones',type:'textarea',maxLength:4000}
};
const LAYOUT={
 clients:['name',['ident',{label:'Identificación (RUC, cédula o pasaporte)',required:true}],'phone','email','address','city','province','category','terms','notes'],
 suppliers:['name','ident','contactName','phone','email','address','city','notes'],
 prospects:['lead','firstName','lastName','jobTitle','role','phone','email','linkedin','primary','notes']
};
const ARCHIVE='contacts',PAGE=20;
let rows=null,leads=[],grid=null,editing=null,draft={},pendingOpen=null,epoch=0,who;
// Clientes y proveedores son del módulo Contactos; los contactos de prospectos, del CRM.
const can=id=>!!window.gamaAccessAllowed?.(id==='prospects'?'crm':'contacts');
const kinds=()=>KINDS.filter(k=>can(k.id));
const kindOf=id=>KINDS.find(k=>k.id===id);
const norm=v=>String(v??'').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g,'');
const clean=v=>{const s=String(v??'').trim();return s||null};
function section(){let s=$('contacts');if(!s){s=document.createElement('section');s.id='contacts';(document.querySelector('.wrap')||document.body).append(s)}return s}
const active=()=>window.ArcRouter.current==='contacts'&&section().classList.contains('active');
const leadName=l=>String(l.company||'').trim()||[l.first_name,l.last_name].filter(Boolean).join(' ').trim()||T('(sin nombre)');

/* ---- datos: tres tablas, una lista ---- */
async function load(){
 if(rows)return rows;
 const token=epoch,D=window.ArcData,E=window.ArcEntities,out=[];
 const take=r=>{if(r.error)throw r.error;return r.data||[]};
 const jobs=[];let found=[];
 if(can('clients'))jobs.push(D.all('customers',{select:E.entities.customers.select,order:'name'},true).then(r=>{for(const x of take(r)){const c=E.customerFromRow(x);
  out.push({key:'clients:'+c.id,kind:'clients',id:c.id,name:c.name,detail:c.category?T('Categoría de precios')+' '+c.category:'',ref:c.taxId,phone:c.phone,email:c.email,city:c.city,active:c.active,record:c})}}));
 if(can('suppliers'))jobs.push(D.all('suppliers',{select:E.entities.suppliers.select,order:'name'},true).then(r=>{for(const x of take(r)){const s=E.supplierFromRow(x);
  out.push({key:'suppliers:'+s.id,kind:'suppliers',id:s.id,name:s.name,detail:s.contactName?T('Contacto')+': '+s.contactName:'',ref:s.taxId,phone:s.phone,email:s.email,city:s.city,active:s.active,record:s})}}));
 if(can('prospects'))jobs.push(Promise.all([
  D.all('crm_contacts',{select:'id,first_name,last_name,job_title,email,phone,linkedin,decision_role,notes,lead_id,customer_id,is_primary,active',order:'id'},true),
  D.all('crm_leads',{select:'id,company,first_name,last_name,city,active',order:'id'},true)]).then(([k,l])=>{
  found=take(l);const byId=new Map(found.map(x=>[x.id,x]));
  for(const x of take(k)){if(!x.lead_id)continue;const lead=byId.get(x.lead_id)||{};
   const name=[x.first_name,x.last_name].filter(Boolean).join(' ').trim()||x.email||T('(sin nombre)');
   out.push({key:'prospects:'+x.id,kind:'prospects',id:x.id,name,detail:[x.job_title,x.is_primary?T('★ Principal'):''].filter(Boolean).join(' · '),
    ref:lead.id?leadName(lead):'',phone:x.phone,email:x.email,city:lead.city,active:x.active!==false,record:x})}}));
 await Promise.all(jobs);
 // Otra sesión entró mientras tanto: no se guarda lo de la anterior.
 if(token!==epoch)return [];
 const order=Object.fromEntries(KINDS.map((k,i)=>[k.id,i]));
 out.sort((a,b)=>a.name.localeCompare(b.name,undefined,{sensitivity:'base'})||order[a.kind]-order[b.kind]);
 leads=found;rows=out;return rows;
}
function refresh(){rows=null;if(grid&&$('ctTable')?.isConnected)grid.refresh()}
const matches=(r,terms)=>{if(!terms.length)return true;const h=norm([r.name,r.detail,r.ref,r.phone,r.email,r.city,T(kindOf(r.kind).one)].join(' '));return terms.every(t=>h.includes(t))};
async function source(req){
 const all=await load(),archived=window.GamaArchive.mode(ARCHIVE)==='archived';
 const box=$('ctArchive');if(box)box.innerHTML=window.GamaArchive.tabs(ARCHIVE,all.filter(r=>r.active).length,all.filter(r=>!r.active).length);
 const terms=norm(req.search).split(/\s+/).filter(Boolean);
 let items=all.filter(r=>r.active!==archived&&matches(r,terms));
 const by={name:r=>r.name,kind:r=>T(kindOf(r.kind).one),city:r=>r.city||'',ref:r=>r.ref||''}[req.sort];
 if(by){const dir=req.ascending===false?-1:1;items=[...items].sort((a,b)=>dir*String(by(a)).localeCompare(String(by(b)),undefined,{sensitivity:'base'}))}
 return {items:items.slice(req.page*req.pageSize,(req.page+1)*req.pageSize),total:items.length,page:req.page,pageSize:req.pageSize};
}

/* ---- tabla ---- */
function actions(r){
 const b=(label,attr,variant)=>U.button({label:T(label),variant,attrs:attr+'="'+esc(r.key)+'"'});
 const out=[];
 if(r.kind!=='prospects')out.push(b('Historial','data-ct-history'));
 if(r.active)out.push(b('Editar','data-ct-edit'),b('Archivar','data-ct-archive','danger'));
 else{out.push(b('Restaurar','data-ct-restore'));if(r.kind!=='prospects')out.push(b('Borrar definitivamente','data-ct-purge','danger'))}
 return out.join(' ');
}
const columns=()=>[
 {label:'Nombre',sort:'name',html:r=>`<b>${esc(r.name)}</b>${r.detail?`<small class="ctSub">${esc(r.detail)}</small>`:''}`},
 {label:'Tipo',sort:'kind',html:r=>`<span class="ctBadge" data-kind="${r.kind}">${esc(T(kindOf(r.kind).one))}</span>`},
 {label:'Identificación / empresa',sort:'ref',value:r=>r.ref||'—'},
 {label:'Teléfono',value:r=>r.phone||'—'},
 {label:'Correo',value:r=>r.email||'—'},
 {label:'Ciudad',sort:'city',value:r=>r.city||'—'},
 {label:'Acciones',actions:true,html:actions}
];
const find=key=>(rows||[]).find(r=>r.key===key);
const say=text=>{const s=$('ctStatus');if(s)s.textContent=text?T(text):''};
const changed=table=>{window.ArcData.invalidate(table);window.dispatchEvent(new CustomEvent('gama:data-change',{detail:{table}}));if(table==='customers')window.dispatchEvent(new Event('gama:sales-change'))};
const friendly=(e,r)=>window.GamaArchive.friendlyError(e,{clients:'client',suppliers:'supplier'}[r.kind]||'contact');
async function archive(key,on){
 const r=find(key);if(!r)return;say('');
 if(!on&&!confirm(T('¿Archivar a «')+r.name+'»?'))return;
 const table=kindOf(r.kind).table;
 try{const x=await window.GamaCloud.update(table,r.id,{active:on});if(x.error)throw x.error;changed(table);say(on?'Contacto restaurado.':'Contacto archivado.')}
 catch(e){say(friendly(e,r))}
 refresh();
}
async function purge(key){
 const r=find(key);if(!r||r.kind==='prospects')return;say('');
 if(!confirm(T('¿Borrar definitivamente a «')+r.name+'»?'))return;
 const table=kindOf(r.kind).table;
 try{const x=await window.GamaCloud.remove(table,r.id);if(x.error)throw x.error;changed(table);say('Contacto borrado.')}
 catch(e){say(friendly(e,r))}
 refresh();
}

/* ---- el formulario ---- */
function fromRecord(kind,x){
 if(kind==='clients')return {name:x.name,ident:x.taxId,phone:x.phone,email:x.email,address:x.address,city:x.city,province:x.province,category:x.category||'A',terms:x.paymentTermsDays??'',notes:x.notes};
 if(kind==='suppliers')return {name:x.name,ident:x.taxId,contactName:x.contactName,phone:x.phone,email:x.email,address:x.address,city:x.city,notes:x.notes};
 return {lead:x.lead_id,firstName:x.first_name,lastName:x.last_name,jobTitle:x.job_title,role:x.decision_role,phone:x.phone,email:x.email,linkedin:x.linkedin,primary:!!x.is_primary,notes:x.notes};
}
const leadOptions=current=>leads.filter(l=>l.active!==false||l.id===current).map(l=>({value:l.id,label:leadName(l)})).sort((a,b)=>a.label.localeCompare(b.label));
function fieldsHtml(kind){
 return LAYOUT[kind].map(entry=>{
  const [key,over]=Array.isArray(entry)?entry:[entry,{}];
  const f={...FIELDS[key],...over};
  const options=key==='lead'?leadOptions(draft.lead):(f.options||[]).map(([value,label])=>({value,label:T(label)}));
  return U.field({id:'ctf-'+key,key,label:f.label,type:f.type||'text',value:draft[key]??(f.type==='checkbox'?false:''),required:!!f.required,
   maxLength:f.maxLength,min:f.min,max:f.max,step:f.step,help:f.help||'',options,className:f.type==='textarea'?'ctWide':f.type==='checkbox'?'ctCheck':''});
 }).join('');
}
function readDraft(){
 $('ctFields')?.querySelectorAll('[name]').forEach(el=>{draft[el.name]=el.type==='checkbox'?el.checked:el.value});
}
function paintFields(){
 const kind=$('ctType').value,box=$('ctFields');
 box.innerHTML=fieldsHtml(kind);U.mount(box);
 $('ctKindHint').innerHTML=tr(kindOf(kind).hint);
 $('ctNoLeads').hidden=!(kind==='prospects'&&!leadOptions(draft.lead).length);
}
function openForm(kind,record=null){
 const list=kinds();if(!list.length)return;
 if(!list.some(k=>k.id===kind))kind=list[0].id;
 const box=$('ctEditor');if(!box)return;
 editing=record?{kind,id:record.id,record}:null;draft=record?fromRecord(kind,record):{category:'A'};
 box.hidden=false;box.dataset.kind=kind;
 U.render(box,`<form id="ctForm" class="arcPanel arcForm ctForm"><div class="ctFormHead"><h3>${tr(record?'Editar contacto':'Nuevo contacto')}</h3><button type="button" class="arcButton secondary" id="ctClose">${tr('Cerrar')}</button></div>`
  +`<div class="arcFormGrid">${U.field({id:'ctType',label:'Tipo de contacto',type:'select',required:true,value:kind,disabled:!!record,options:list.map(k=>({value:k.id,label:T(k.one)}))})}</div>`
  +`<p class="gsHint" id="ctKindHint"></p><p class="gsHint" id="ctNoLeads" hidden>${tr('Todavía no hay prospectos: créalos primero en el CRM → Prospectos.')}</p>`
  +`<div class="arcFormGrid ctFields" id="ctFields"></div>`
  +`<p id="ctMsg" role="alert" class="arcFormError"></p><div class="arcToolbar">${U.button({id:'ctSave',type:'submit',variant:'primary',label:T('Guardar contacto')})}${U.button({id:'ctCancel',label:T('Cancelar')})}</div></form>`
  +(record&&kind==='clients'?'<div id="pmCustomerProjects"></div>':''));
 // El tipo es la primera pregunta; al cambiarlo se conserva lo ya escrito que sirva.
 const type=$('ctType');type.querySelector('option[value=""]')?.remove();type.value=kind;
 type.onchange=()=>{readDraft();box.dataset.kind=type.value;paintFields()};
 paintFields();
 $('ctClose').onclick=closeForm;$('ctCancel').onclick=closeForm;
 U.bindForm($('ctForm'),save);
 if(record&&kind==='clients')window.GamaProjects?.customerProjects(record.id,$('pmCustomerProjects'));
 const first=record?$('ctFields').querySelector('input,select,textarea'):type;
 first?.scrollIntoView?.({block:'center'});try{first?.focus()}catch(_){}
}
function closeForm(){const box=$('ctEditor');editing=null;draft={};if(!box)return;box.hidden=true;box.dataset.kind='';box.replaceChildren()}
async function userId(){if(who!==undefined)return who;try{const s=await window.GamaCloud.getSession();who=s?.data?.session?.user?.id||null}catch(_){who=null}return who}
async function save(){
 readDraft();
 const kind=editing?.kind||$('ctType').value,d=draft,C=window.GamaCloud;
 const call=async p=>{const r=await p;if(r.error)throw r.error;return r.data};
 if(kind==='clients'){
  const name=clean(d.name),ident=clean(d.ident),terms=String(d.terms??'').trim();
  if(!name||!ident)throw Error(T('El nombre y la identificación son obligatorios.'));
  if(!/^\d+$/.test(terms)||Number(terms)>3650)throw Error(T('Indica un plazo de pago entre 0 y 3650 días.'));
  if((rows||[]).some(r=>r.kind==='clients'&&r.id!==editing?.id&&norm(r.ref)===norm(ident)))throw Error(T('Ya existe un cliente con esta identificación.'));
  const row={name,identification:ident,phone:clean(d.phone),email:clean(d.email),address:clean(d.address),city:clean(d.city),province:clean(d.province),category:d.category||'A',payment_terms_days:Number(terms),notes:clean(d.notes)};
  await call(editing?C.update('customers',editing.id,row):C.insert('customers',{...row,active:true}));
  changed('customers');
 }else if(kind==='suppliers'){
  const value={name:clean(d.name),taxId:clean(d.ident)||'',contactName:clean(d.contactName)||'',phone:clean(d.phone)||'',email:clean(d.email)||'',city:clean(d.city)||'',address:clean(d.address)||'',notes:clean(d.notes)||''};
  if(!value.name)throw Error(T('El nombre del proveedor es obligatorio.'));
  const row=window.ArcEntities.supplierToRow({...editing?.record,...value,active:editing?.record?.active!==false});
  // El país y la provincia no están en este formulario: al crear se quedan con lo que diga la base.
  if(!editing)for(const k of ['country','province','postal_code'])delete row[k];
  await call(editing?C.update('suppliers',editing.id,row):C.insert('suppliers',row));
  changed('suppliers');
 }else{
  const row={lead_id:clean(d.lead),customer_id:null,first_name:clean(d.firstName),last_name:clean(d.lastName),job_title:clean(d.jobTitle),decision_role:clean(d.role),
   phone:clean(d.phone),email:clean(d.email),linkedin:clean(d.linkedin),notes:clean(d.notes),is_primary:!!d.primary};
  if(!row.lead_id)throw Error(T('Elige el prospecto al que pertenece el contacto.'));
  if(!(row.first_name||row.last_name||row.email))throw Error(T('Un contacto necesita al menos un nombre, unos apellidos o un correo.'));
  // Un solo principal por prospecto: se le quita al de ahora antes de ponérselo al nuevo.
  if(row.is_primary){
   const others=await call(C.list('crm_contacts',{select:'id',eq:{lead_id:row.lead_id,is_primary:true,active:true}}));
   for(const o of others||[])if(o.id!==editing?.id)await call(C.update('crm_contacts',o.id,{is_primary:false}));
  }
  await call(editing?C.update('crm_contacts',editing.id,row):C.insert('crm_contacts',{...row,active:true,created_by:await userId()}));
  changed('crm_contacts');
 }
 closeForm();say('Contacto guardado.');refresh();
}

/* ---- pantalla ---- */
function render(){
 const s=section();
 grid?.dispose();grid=null;
 U.render(s,window.GamaUI.header({title:'Contactos',lead:'Clientes, proveedores y contactos de prospectos en una sola lista.',module:'contacts'})
  +`<div class="ctBar"><input id="ctSearch" type="search" autocomplete="off" aria-label="${esc(T('Buscar contactos'))}" placeholder="${esc(T('Buscar por nombre, tipo, identificación, empresa, ciudad o correo…'))}"><div id="ctArchive"></div><button type="button" class="arcButton primary" id="ctNew">${tr('Nuevo contacto')}</button></div>`
  +`<p class="gsHint ctStatus" id="ctStatus" role="status"></p><div id="ctEditor" class="ctEditor" hidden></div><div id="ctTable" class="ctTable"></div>`);
 window.GamaUI.bindBack(s);
 $('ctNew').onclick=()=>openForm(kinds()[0]?.id);
 grid=U.dataTable($('ctTable'),{columns:columns(),source,searchInput:$('ctSearch'),className:'ctList',empty:T('Ningún contacto en esta lista.'),initial:{pageSize:PAGE,sort:'name',ascending:true},actions:{
  'data-ct-edit':key=>{const r=find(key);if(r)openForm(r.kind,r.record)},
  'data-ct-history':key=>{const r=find(key);if(r)window.ArchitectPartners?.open(r.kind==='clients'?'customer':'supplier',r.id)},
  'data-ct-archive':key=>archive(key,false),'data-ct-restore':key=>archive(key,true),'data-ct-purge':purge}});
 window.GamaSuppliers?.migrate?.();
 window.dispatchEvent(new CustomEvent('arc:module-rendered',{detail:{id:'contacts'}}));
 flush();
}
async function flush(){
 if(!pendingOpen)return;const p=pendingOpen;pendingOpen=null;
 if(!p.id){openForm(p.kind);return}
 await load();const r=find(p.kind+':'+p.id);if(r)openForm(r.kind,r.record);
}
// Las direcciones antiguas (clientes, proveedores) abren Contactos; con create, el formulario de ese tipo.
function open(which,opts={}){
 const kind={clients:'clients',suppliers:'suppliers',prospects:'prospects',crm:'prospects'}[which];
 if(opts.create&&kind)pendingOpen={kind};
 if(active()){flush();return true}
 return window.ArcRouter.show('contacts');
}
// Abre la ficha de un contacto concreto (desde un cobro, por ejemplo).
function edit(kind,id){pendingOpen={kind,id};if(active()){flush();return true}return window.ArcRouter.show('contacts')}
window.GamaArchive.register(ARCHIVE,()=>grid?.refresh({page:0}));
window.addEventListener('gama:data-change',e=>{if(['customers','suppliers','crm_contacts','crm_leads'].includes(e.detail?.table))refresh()});
window.addEventListener('gama:language-change',()=>{if(active())render()});
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;epoch++;rows=null;who=undefined});
window.ArcRouter.onEnter('contacts',()=>{
 // Los contactos del CRM no llegan en tiempo real: al entrar se leen de nuevo.
 for(const t of ['crm_contacts','crm_leads'])window.ArcData.invalidate(t);
 rows=null;editing=null;render();
 return()=>{closeForm();grid?.dispose();grid=null};
});
window.GamaContacts={open,edit,refresh,create:kind=>openForm(kind)};
})();
