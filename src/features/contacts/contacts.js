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
 {id:'people',one:'Contacto de cliente',table:'crm_contacts',hint:'Una persona vinculada a una empresa cliente, con su cargo y sus datos de contacto.'},
 {id:'prospects',one:'Contacto de prospecto',table:'crm_contacts',hint:'Una persona de una empresa que aún no es cliente, con su papel en la decisión.'}
];
const PAPELES=[['decisor','Decisor'],['prescriptor','Prescriptor'],['usuario','Usuario'],['comprador','Comprador'],['otro','Otro']];
const CATEGORIAS=[['A','A · Mayorista (por defecto)'],['B','B · Venta al detalle'],['C','C · Contrato especial (tarifa)']];
/* Los campos de cada tipo, en su orden. Lo que tienen en común (nombre,
   teléfono, correo, ciudad…) se conserva al cambiar de tipo antes de guardar. */
const FIELDS={
 name:{label:'Nombre / razón social',required:true,maxLength:300},
 identKind:{label:'Tipo de identificación fiscal',type:'select',options:[['auto','Automático (RUC o cédula)'],['cedula','Cédula'],['ruc_natural','RUC persona natural'],['ruc_company','RUC sociedad'],['ruc_public','RUC entidad pública'],['ruc_foreign','RUC extranjero sin cédula'],['foreign_document','Documento extranjero'],['consumer','Consumidor final']]},
 ident:{label:'Identificación (RUC, cédula o pasaporte)',maxLength:100},
 contactName:{label:'Persona de contacto',maxLength:200},
 customer:{label:'Cliente',type:'select',required:true},
 country:{label:'País',maxLength:120},
 postalCode:{label:'Código postal',maxLength:30},
 lead:{label:'Prospecto',type:'select',required:true},
 fullName:{label:'Nombre del contacto',maxLength:241},
 jobTitle:{label:'Cargo',maxLength:120},
 role:{label:'Papel en la decisión',type:'select',options:PAPELES},
 phone2:{label:'Otro teléfono',type:'tel',maxLength:80},
 website:{label:'Sitio web',type:'url',maxLength:500},
 industry:{label:'Sector',maxLength:120},
 language:{label:'Idioma',type:'select',options:[['es','Español'],['fr','Français'],['en','English']]},
 addressMode:{label:'Origen de la dirección',type:'select',options:[['parent','Dirección de la empresa'],['own','Dirección propia']]},
 phone:{label:'Teléfono',type:'tel',maxLength:80},
 email:{label:'Correo',type:'email',maxLength:250},
 address:{label:'Dirección',maxLength:500},
 city:{label:'Ciudad',maxLength:200},
 province:{label:'Provincia',maxLength:120},
 category:{label:'Categoría de precios',type:'select',options:CATEGORIAS},
 terms:{label:'Plazo de pago desde la entrega (días)',type:'number',required:true,min:0,max:3650,step:1,help:'0 = pago a la entrega.'},
 linkedin:{label:'LinkedIn',maxLength:300},
 primary:{label:'Contacto principal',type:'checkbox'},
 lat:{label:'Latitud GPS',type:'number',min:-85,max:85,step:'any'},
 lng:{label:'Longitud GPS',type:'number',min:-180,max:180,step:'any'},
 notes:{label:'Observaciones',type:'textarea',maxLength:4000}
};
// One common field vocabulary; role-specific conditions and personal names stay distinct.
const COORDINATES=['phone','phone2','email','address','city','province','postalCode','country','lat','lng'];
const SHARED_PROFILE=['website','industry','language'];
const LAYOUT={
 clients:['name',['ident',{label:'Identificación (RUC, cédula o pasaporte)',required:true}],'identKind',...COORDINATES,...SHARED_PROFILE,'category','terms','notes'],
 suppliers:['name','ident','identKind','contactName',...COORDINATES,...SHARED_PROFILE,'notes'],
 people:['customer','fullName','ident','identKind','jobTitle','role','addressMode',...COORDINATES,...SHARED_PROFILE,'linkedin','primary','notes'],
 prospects:['lead','fullName','ident','identKind','jobTitle','role','addressMode',...COORDINATES,...SHARED_PROFILE,'linkedin','primary','notes']
};
const ARCHIVE='contacts',PAGE=20;
let directoryUnavailable=false,pageRows=[];
let kindFilter='',qualityFilter='',rows=null,leads=[],grid=null,editing=null,draft={},pendingOpen=null,epoch=0,editorSeq=0,who;
// Clientes y proveedores son del módulo Contactos; los contactos de prospectos, del CRM.
const can=id=>!!window.gamaAccessAllowed?.(['prospects','people'].includes(id)?'crm':'contacts');
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
 if(can('clients'))jobs.push(D.all('customers',{select:E.entities.customers.select+',identification_kind',order:'name'},true).then(r=>{for(const x of take(r)){const c=E.customerFromRow(x);
  out.push({key:'clients:'+c.id,kind:'clients',id:c.id,name:c.name,detail:c.category?T('Categoría de precios')+' '+c.category:'',ref:c.taxId,phone:c.phone,email:c.email,city:c.city,active:c.active,record:c})}}));
 if(can('suppliers'))jobs.push(D.all('suppliers',{select:E.entities.suppliers.select+',identification_kind',order:'name'},true).then(r=>{for(const x of take(r)){const s=E.supplierFromRow(x);
  out.push({key:'suppliers:'+s.id,kind:'suppliers',id:s.id,name:s.name,detail:s.contactName?T('Contacto')+': '+s.contactName:'',ref:s.taxId,phone:s.phone,email:s.email,city:s.city,active:s.active,record:s})}}));
 if(can('prospects'))jobs.push(Promise.all([
  D.all('crm_contacts',{select:'id,first_name,last_name,job_title,email,phone,phone2,website,industry,language,address,city,province,postal_code,country,lat,lng,address_mode,identification,identification_kind,linkedin,decision_role,notes,lead_id,customer_id,is_primary,active',order:'id'},true),
  D.all('crm_leads',{select:'id,company,first_name,last_name,address,city,province,postal_code,country,active',order:'id'},true)]).then(([k,l])=>{
  found=take(l);const byId=new Map(found.map(x=>[x.id,x]));
  for(const x of take(k)){if(!x.lead_id&&!x.customer_id)continue;const lead=byId.get(x.lead_id)||{},kind=x.customer_id?'people':'prospects';
   const name=[x.first_name,x.last_name].filter(Boolean).join(' ').trim()||x.email||T('(sin nombre)');
   out.push({key:kind+':'+x.id,kind,id:x.id,name,detail:[x.job_title,x.is_primary?T('★ Principal'):''].filter(Boolean).join(' · '),
    ref:lead.id?leadName(lead):'',phone:x.phone,email:x.email,city:x.address_mode==='own'?x.city:lead.city,active:x.active!==false,record:x})}}));
 await Promise.all(jobs);
 // Otra sesión entró mientras tanto: no se guarda lo de la anterior.
 if(token!==epoch)return [];
 const order=Object.fromEntries(KINDS.map((k,i)=>[k.id,i]));
 out.sort((a,b)=>a.name.localeCompare(b.name,undefined,{sensitivity:'base'})||order[a.kind]-order[b.kind]);
 for(const r of out.filter(x=>x.kind==='people')){const parent=out.find(x=>x.kind==='clients'&&x.id===r.record.customer_id);r.ref=parent?.name||'';r.city=r.record.address_mode==='own'?r.record.city:(parent?.city||'')}
 leads=found;rows=out;return rows;
}
function refresh(){rows=null;if(grid&&$('ctTable')?.isConnected)grid.refresh()}
const matches=(r,terms)=>{if(!terms.length)return true;const h=norm([r.name,r.detail,r.ref,r.phone,r.email,r.city,T(kindOf(r.kind).one)].join(' '));return terms.every(t=>h.includes(t))};
async function source(req){
 if(!directoryUnavailable){
  const token=epoch;try{
   const data=await window.ArcData.rpc('coco_contact_directory',{p_data:{...req,kind:kindFilter,quality:qualityFilter,archived:window.GamaArchive.mode(ARCHIVE)==='archived'}});
   if(token!==epoch)return {items:[],total:0,page:0,pageSize:PAGE};
   if(data?.version===1){
    const E=window.ArcEntities;pageRows=data.items.map(r=>({...r,key:r.kind+':'+r.id,record:r.kind==='clients'?E.customerFromRow(r.record):r.kind==='suppliers'?E.supplierFromRow(r.record):r.record}));
    const box=$('ctArchive');if(box)box.innerHTML=window.GamaArchive.tabs(ARCHIVE,data.active_total,data.archived_total);
    return {...data,items:pageRows};
   }
   if(data!=null)throw Error('CONTACT_DIRECTORY_INVALID_RESPONSE');
   directoryUnavailable=true;
  }catch(e){if(e?.code==='PGRST202'||/Could not find the function.*coco_contact_directory/.test(String(e?.message||'')))directoryUnavailable=true;else throw e}
 }

 const all=await load(),archived=window.GamaArchive.mode(ARCHIVE)==='archived';
 const box=$('ctArchive');if(box)box.innerHTML=window.GamaArchive.tabs(ARCHIVE,all.filter(r=>r.active).length,all.filter(r=>!r.active).length);
 const terms=norm(req.search).split(/\s+/).filter(Boolean);
 let items=all.filter(r=>r.active!==archived&&matches(r,terms)&&(!kindFilter||r.kind===kindFilter)&&(!qualityFilter||(qualityFilter==='email'?!r.email:!r.phone)));
 const by=Object.fromEntries([...Object.entries({name:r=>r.name,kind:r=>T(kindOf(r.kind).one),city:r=>r.city||'',ref:r=>r.ref||'',phone:r=>r.phone||'',email:r=>r.email||''}),...extraColumns.map(([key,,value])=>[key,value])])[req.sort];
 if(by)items=[...items].sort((a,b)=>window.GamaTable.compare(by(a),by(b),req.ascending===false?'desc':'asc'));
 return {items:items.slice(req.page*req.pageSize,(req.page+1)*req.pageSize),total:items.length,page:req.page,pageSize:req.pageSize};
}

/* ---- tabla ---- */
function actions(r){
 const b=(label,attr,variant)=>U.button({label:T(label),variant,attrs:attr+'="'+esc(r.key)+'"'});
 const dossierLabel={es:'Ficha de contacto',fr:'Fiche contact',en:'Contact dossier'}[window.GamaI18n?.language||'es'];
 const out=[U.button({label:dossierLabel,attrs:'data-ct-dossier="'+esc(r.key)+'"'})];
 if(r.kind==='clients')out.push(b('Direcciones de entrega','data-ct-addresses'));
 if(['clients','suppliers'].includes(r.kind))out.push(b('Historial','data-ct-history'));
 if(r.kind==='clients'&&r.active&&window.gamaAccessAllowed?.('website')&&window.gamaAccessAllowed?.('users'))out.push(b('Cuenta cloud del cliente','data-ct-cloud'));
 if(r.active)out.push(b('Editar','data-ct-edit'),b('Archivar','data-ct-archive','danger'));
 else{out.push(b('Restaurar','data-ct-restore'));if(['clients','suppliers'].includes(r.kind))out.push(b('Borrar definitivamente','data-ct-purge','danger'))}
 return out.join(' ');
}
const extraColumns=[
 ['address','Dirección',r=>r.record.address],['province','Provincia',r=>r.record.province],
 ['postalCode','Código postal',r=>r.record.postalCode],['country','País',r=>r.record.country],
 ['contactName','Persona de contacto',r=>r.record.contactName],
 ['category','Categoría de precios',r=>r.kind==='clients'?r.record.category:null],
 ['terms','Plazo de pago (días)',r=>r.kind==='clients'?r.record.paymentTermsDays:null],
 ['jobTitle','Cargo',r=>r.record.job_title],
 ['role','Papel en la decisión',r=>r.record.decision_role?T(PAPELES.find(p=>p[0]===r.record.decision_role)?.[1]||r.record.decision_role):null],
 ['linkedin','LinkedIn',r=>r.record.linkedin],['primary','Contacto principal',r=>['prospects','people'].includes(r.kind)?T(r.record.is_primary?'Sí':'No'):null],
 ['phone2','Otro teléfono',r=>r.record.phone2],['website','Sitio web',r=>r.record.website],['industry','Sector',r=>r.record.industry],['language','Idioma',r=>r.record.language],
 ['notes','Observaciones',r=>r.record.notes],['active','Estado',r=>T(r.active?'Activo':'Archivado')]
];
const columns=()=>[
 {label:'Nombre',sort:'name',html:r=>`<button class="arcButton secondary" type="button" data-ct-open="${esc(r.key)}"><b>${esc(r.name)}</b></button>${r.detail?`<small class="ctSub">${esc(r.detail)}</small>`:''}`},
 {label:'Tipo',sort:'kind',html:r=>(r.roles?.length?r.roles:[r]).map(role=>`<span class="ctBadge" data-kind="${role.kind}">${esc(T(kindOf(role.kind)?.one||role.kind))}</span>`).join(' ')},
 {label:'Identificación / empresa',sort:'ref',value:r=>r.ref||'—'},
 {label:'Teléfono',sort:'phone',html:r=>r.phone?`<a href="tel:${esc(String(r.phone).replace(/[^+0-9]/g,''))}">${esc(r.phone)}</a>`:'—'},
 {label:'Correo',sort:'email',html:r=>r.email?`<a href="mailto:${esc(encodeURIComponent(r.email))}">${esc(r.email)}</a>`:'—'},
 {label:'Ciudad',sort:'city',value:r=>r.city||'—'},
 ...extraColumns.map(([sort,label,value])=>({sort,label,value:r=>value(r)??'—'})),
 {label:'Acciones',actions:true,html:actions}
];
const find=key=>[...pageRows,...(rows||[])].find(r=>r.key===key);
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
 const r=find(key);if(!r||!['clients','suppliers'].includes(r.kind))return;say('');
 if(!confirm(T('¿Borrar definitivamente a «')+r.name+'»?'))return;
 const table=kindOf(r.kind).table;
 try{const x=await window.GamaCloud.remove(table,r.id);if(x.error)throw x.error;changed(table);say('Contacto borrado.')}
 catch(e){say(friendly(e,r))}
 refresh();
}

/* ---- el formulario ---- */
function fromRecord(kind,x){
 const common={ident:x.taxId??x.identification,identKind:x.identificationKind||x.identification_kind||'auto',phone:x.phone,phone2:x.phone2,email:x.email,
  address:x.address,city:x.city,province:x.province,postalCode:x.postalCode??x.postal_code,country:x.country,lat:x.lat??'',lng:x.lng??'',
  website:x.website,industry:x.industry,language:x.language,notes:x.notes};
 if(kind==='clients')return {...common,name:x.name,category:x.category||'A',terms:x.paymentTermsDays??''};
 if(kind==='suppliers')return {...common,name:x.name,contactName:x.contactName};
 return {...common,customer:x.customer_id,lead:x.lead_id,fullName:[x.first_name,x.last_name].filter(Boolean).join(' ').trim(),jobTitle:x.job_title,role:x.decision_role,
  addressMode:x.address_mode||'parent',linkedin:x.linkedin,primary:!!x.is_primary};
}
async function openRecord(kind,id){
 const token=epoch,request=++editorSeq;say('Cargando…');
 try{
  const data=await window.ArcData.rpc('coco_contact_record',{p_kind:kind,p_id:id});
  if(token!==epoch||request!==editorSeq||!active())return;
  if(!data?.record||!Number.isInteger(data.version))throw Error('CONTACT_INVALID_RESPONSE');
  const record=kind==='clients'?window.ArcEntities.customerFromRow(data.record):kind==='suppliers'?window.ArcEntities.supplierFromRow(data.record):data.record;
  openForm(kind,{...record,_contactVersion:data.version,_conflicts:data.profile?.alignment_conflicts||{},_inheritedAddress:data.inherited_address});say('');
 }catch(e){if(token===epoch&&request===editorSeq)say(window.ArcErrors?.message(e)||e.message)}
}
const leadOptions=current=>leads.filter(l=>l.active!==false||l.id===current).map(l=>({value:l.id,label:leadName(l)})).sort((a,b)=>a.label.localeCompare(b.label));
function fieldsHtml(kind){
 const rendered=LAYOUT[kind].map(entry=>{
  const [key,over]=Array.isArray(entry)?entry:[entry,{}];
  const f={...FIELDS[key],...over};
  const options=key==='customer'?(rows||[]).filter(r=>r.kind==='clients'&&(r.active||r.id===draft.customer)).map(r=>({value:r.id,label:r.name})):key==='lead'?leadOptions(draft.lead):(f.options||[]).map(([value,label])=>({value,label:T(label)}));
  return U.field({id:'ctf-'+key,key,label:f.label,type:f.type||'text',value:draft[key]??(f.type==='checkbox'?false:''),required:!!f.required&&!(editing&&((key==='ident'&&!editing.record.taxId)||(key==='terms'&&editing.record.paymentTermsDays==null))),
   maxLength:f.maxLength,min:f.min,max:f.max,step:f.step,help:f.help||'',options,className:f.type==='textarea'?'ctWide':f.type==='checkbox'?'ctCheck':''});
 });
 const keys=LAYOUT[kind].map(e=>Array.isArray(e)?e[0]:e);
 const groups=[['Identidad',['name','ident','identKind','customer','lead','fullName']],['Datos de contacto',['contactName','phone','phone2','email','website']],['Dirección',['addressMode','address','city','province','postalCode','country']],['Información comercial',['category','terms','jobTitle','role','primary','industry','language']],['Observaciones',['notes']]];
 const blocks=groups.map(([label,fields])=>{const html=fields.filter(k=>keys.includes(k)).map(k=>rendered[keys.indexOf(k)]).join('');return html?`<fieldset class="ctGroup"><legend>${tr(label)}</legend><div class="arcFormGrid ctFields">${html}</div></fieldset>`:''}).join('');
 const more=keys.filter(k=>!groups.some(g=>g[1].includes(k))).map(k=>rendered[keys.indexOf(k)]).join('');
 const gpsHint={es:'Para localizar la dirección, indica la calle, el número y la ciudad. Las coordenadas guardadas se utilizan en la planificación TMS. Geocodificación: Photon / © OpenStreetMap contributors.',fr:'Pour localiser l’adresse, renseignez la rue, le numéro et la ville. Les coordonnées enregistrées sont utilisées pour la planification TMS. Géocodage : Photon / © OpenStreetMap contributors.',en:'To locate the address, enter the street, number and city. Saved coordinates are used for TMS planning. Geocoding: Photon / © OpenStreetMap contributors.'}[window.GamaI18n?.language||'es'];
 return blocks+(more?`<details class="ctGroup"><summary>${tr('Información adicional')}</summary><div class="arcFormGrid ctFields">${more}</div></details><p class="gsHint ctGpsHint">${esc(gpsHint)}</p>`:'')+(['people','prospects'].includes(kind)?'<p id="ctParentAddress" class="gsHint"></p>':'');
}
function parentAddress(){
 const kind=$('ctType').value,person=['people','prospects'].includes(kind),inherit=person&&($('ctf-addressMode')?.value||'parent')==='parent';
 const parent=kind==='people'?(rows||[]).find(r=>r.kind==='clients'&&r.id===$('ctf-customer')?.value)?.record:leads.find(l=>l.id===$('ctf-lead')?.value);
 const box=$('ctParentAddress');if(box){box.hidden=!inherit;box.textContent=inherit?T('Dirección de la empresa')+': '+(window.ArcEntities.formatAddress(parent||editing?.record?._inheritedAddress||{})||'—'):''}
 for(const key of ['address','city','province','postalCode','country','lat','lng']){const el=$('ctf-'+key);if(el){el.disabled=inherit;const wrapper=el.closest('.arcField');if(wrapper)wrapper.hidden=inherit}}
}
function readDraft(){
 $('ctFields')?.querySelectorAll('[name]').forEach(el=>{draft[el.name]=el.type==='checkbox'?el.checked:el.value});
}
function paintFields(){
 const kind=$('ctType').value,box=$('ctFields');
 box.innerHTML=fieldsHtml(kind);U.mount(box);
 for(const id of ['ctf-customer','ctf-lead','ctf-addressMode'])if($(id))$(id).addEventListener('change',parentAddress);parentAddress();
 $('ctKindHint').innerHTML=tr(kindOf(kind).hint);
 $('ctNoLeads').hidden=!(kind==='prospects'&&!leadOptions(draft.lead).length);
}
function openForm(kind,record=null){
 const list=kinds();if(!list.length)return;
 if(!list.some(k=>k.id===kind))kind=list[0].id;
 const box=$('ctEditor');if(!box)return;
 editing=record?{kind,id:record.id,record}:null;draft=record?fromRecord(kind,record):{category:'A',addressMode:'parent'};
 box.hidden=false;box.dataset.kind=kind;
 U.render(box,`<form id="ctForm" class="arcPanel arcForm ctForm"><div class="ctFormHead"><h3>${tr(record?'Editar contacto':'Nuevo contacto')}</h3><button type="button" class="arcButton secondary" id="ctClose">${tr('Cerrar')}</button></div>`
  +`<div class="arcFormGrid">${U.field({id:'ctType',label:'Tipo de contacto',type:'select',required:true,value:kind,disabled:!!record,options:list.map(k=>({value:k.id,label:T(k.one)}))})}</div>`
  +`<p class="gsHint" id="ctKindHint"></p><p class="gsHint" id="ctNoLeads" hidden>${tr('Todavía no hay prospectos: créalos primero en el CRM → Prospectos.')}</p>`
  +`<p class="gsHint">${tr('Los datos comunes se sincronizan entre los roles de la misma identidad. Las condiciones y notas permanecen separadas.')}</p>`
  +`<div id="ctFields"></div>`
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
function closeForm(){const box=$('ctEditor');editorSeq++;editing=null;draft={};if(!box)return;box.hidden=true;box.dataset.kind='';box.replaceChildren()}
async function userId(){if(who!==undefined)return who;try{const s=await window.GamaCloud.getSession();who=s?.data?.session?.user?.id||null}catch(_){who=null}return who}
function writeGps(row,values,previous){
 const lat=String(values.lat??'').trim(),lng=String(values.lng??'').trim();
 if((lat||lng)&&(!lat||!lng||!Number.isFinite(+lat)||!Number.isFinite(+lng)||Math.abs(+lat)>85||Math.abs(+lng)>180))throw Error(T('Coordenadas inválidas.'));
 const a=lat===''?null:Number(lat),b=lng===''?null:Number(lng);
 // An unchanged GPS field must not erase coordinates found by the server
 // after this editor opened. Address changes are invalidated by the database.
 if(!previous||a!==(previous.lat??null)||b!==(previous.lng??null)){row.lat=a;row.lng=b}
}
async function save(){
 readDraft();const kind=editing?.kind||$('ctType').value,d=draft,token=epoch,request=editorSeq;
 const data={phone:clean(d.phone),phone2:clean(d.phone2),email:clean(d.email),website:clean(d.website),industry:clean(d.industry),language:clean(d.language),
  identification_kind:d.identKind||'auto',notes:clean(d.notes)};
 data[kind==='suppliers'?'tax_id':'identification']=clean(d.ident);
 const own=!['people','prospects'].includes(kind)||d.addressMode==='own';
 if(own){for(const [key,column] of [['address','address'],['city','city'],['province','province'],['postalCode','postal_code'],['country','country']])data[column]=clean(d[key]);
  writeGps(data,d,editing?.record);
 }
 if(kind==='clients'||kind==='suppliers'){
  data.name=clean(d.name);if(!data.name)throw Error(T('El nombre del proveedor es obligatorio.'));
  if(data[kind==='clients'?'identification':'tax_id']&&(rows||[]).some(r=>r.kind===kind&&r.id!==editing?.id&&norm(r.ref)===norm(d.ident)))throw Error(T('Ya existe un cliente con esta identificación.'));
  if(kind==='clients'){
   if(!data.identification&&(!editing||editing.record.taxId))throw Error(T('El nombre y la identificación son obligatorios.'));
   const terms=String(d.terms??'').trim();if((terms===''&&(!editing||editing.record.paymentTermsDays!=null))||(terms!==''&&(!/^\d+$/.test(terms)||Number(terms)>3650)))throw Error(T('Indica un plazo de pago entre 0 y 3650 días.'));
   data.category=d.category||'A';data.payment_terms_days=terms===''?null:Number(terms);
  }else data.contact_name=clean(d.contactName);
 }else{
  Object.assign(data,{customer_id:kind==='people'?clean(d.customer):null,lead_id:kind==='prospects'?clean(d.lead):null,
   first_name:clean(d.fullName),last_name:null,job_title:clean(d.jobTitle),decision_role:clean(d.role),linkedin:clean(d.linkedin),is_primary:!!d.primary,address_mode:d.addressMode||'parent'});
  const oldName=[editing?.record?.first_name,editing?.record?.last_name].filter(Boolean).join(' ').trim();
  if(editing&&clean(d.fullName)===clean(oldName)){data.first_name=editing.record.first_name;data.last_name=editing.record.last_name}
  if(!data.customer_id&&!data.lead_id)throw Error(T('Elige el prospecto al que pertenece el contacto.'));
  if(!(data.first_name||data.last_name||data.email))throw Error(T('Un contacto necesita al menos un nombre, unos apellidos o un correo.'));
 }
 const result=await window.ArcData.rpc('coco_contact_save',{p_kind:kind,p_id:editing?.id||null,p_data:data,p_version:editing?.record?._contactVersion??null});
 if(!result?.record)throw Error('CONTACT_INVALID_RESPONSE');
 if(token!==epoch)return;
 for(const table of ['customers','suppliers','crm_contacts','crm_leads'])changed(table);
 if(request===editorSeq){closeForm();say('Contacto guardado.')}refresh();
}

/* ---- pantalla ---- */
function render(){
 const s=section();
 grid?.dispose();grid=null;
 U.render(s,window.GamaUI.header({title:'Contactos',lead:'Clientes, proveedores y sus personas de contacto en una sola lista.',module:'contacts'})
  +`<div class="ctBar"><input id="ctSearch" type="search" autocomplete="off" aria-label="${esc(T('Buscar contactos'))}" placeholder="${esc(T('Buscar por nombre, tipo, identificación, empresa, ciudad o correo…'))}"><div id="ctArchive"></div><button type="button" class="arcButton secondary" id="ctAging">${tr('Balance por antigüedad')}</button><button type="button" class="arcButton primary" id="ctNew">${tr('Nuevo contacto')}</button></div>`
  +`<div class="arcToolbar ctFilters"><label>${tr('Tipo de contacto')}<select id="ctKindFilter"><option value="">${esc(T('Todos los tipos'))}</option>${kinds().map(k=>`<option value="${k.id}" ${kindFilter===k.id?'selected':''}>${esc(T(k.one))}</option>`).join('')}</select></label><label>${tr('Datos de contacto')}<select id="ctQualityFilter"><option value="">${esc(T('Todos'))}</option><option value="email" ${qualityFilter==='email'?'selected':''}>${esc(T('Sin correo'))}</option><option value="phone" ${qualityFilter==='phone'?'selected':''}>${esc(T('Sin teléfono'))}</option></select></label></div>`
  +`<p class="gsHint ctStatus" id="ctStatus" role="status"></p><div id="ctEditor" class="ctEditor" hidden></div><div id="ctTable" class="ctTable"></div>`);
 window.GamaUI.bindBack(s);
 $('ctKindFilter').onchange=e=>{kindFilter=e.target.value;grid?.refresh({page:0})};$('ctQualityFilter').onchange=e=>{qualityFilter=e.target.value;grid?.refresh({page:0})};
 $('ctAging').onclick=async()=>{try{await window.ArcLoadScript('gama-collections.js');await window.GamaCollections.aging()}catch(e){window.gamaToast?.(window.ArcErrors.message(e))}};$('ctNew').onclick=async()=>{const token=epoch,req=++editorSeq;await load();if(token===epoch&&req===editorSeq&&active())openForm(kinds()[0]?.id)};
 grid=U.dataTable($('ctTable'),{columns:columns(),source,searchInput:$('ctSearch'),className:'ctList',empty:T('Ningún contacto en esta lista.'),initial:{pageSize:PAGE,sort:'name',ascending:true},actions:{
  'data-ct-edit':async key=>{const r=find(key);if(r){await load();await openRecord(r.kind,r.id)}},
  'data-ct-open':async key=>{const r=find(key);if(!r)return;try{await window.ArcLoadScript('coco-contact-hub.js');await window.CocoContactHub.open(r.kind,r.id)}catch(e){window.gamaToast?.(window.ArcErrors.message(e))}},
  'data-ct-dossier':async key=>{const r=find(key);if(!r)return;try{await window.ArcLoadScript('coco-contact-hub.js');await window.CocoContactHub.open(r.kind,r.id)}catch(e){window.gamaToast?.(window.ArcErrors.message(e))}},
  'data-ct-addresses':async key=>{const r=find(key);if(!r||r.kind!=='clients')return;try{await window.ArcLoadScript('coco-contact-hub.js');await window.CocoContactHub.open('clients',r.id,{tab:'relations'})}catch(e){window.gamaToast?.(window.ArcErrors.message(e))}},
  'data-ct-history':key=>{const r=find(key);if(r)window.ArchitectPartners?.open(r.kind==='clients'?'customer':'supplier',r.id)},
  'data-ct-cloud':async key=>{const r=find(key);if(!r)return;try{await window.ArcLoadScript('gama-store-admin.js');await window.GamaStoreAdmin.customerAccounts(r.id)}catch(e){window.gamaToast?.(window.ArcErrors.message(e))}},
  'data-ct-archive':key=>archive(key,false),'data-ct-restore':key=>archive(key,true),'data-ct-purge':purge}});
 window.GamaSuppliers?.migrate?.();
 window.dispatchEvent(new CustomEvent('arc:module-rendered',{detail:{id:'contacts'}}));
 flush();
}
async function flush(){
 if(!pendingOpen)return;const p=pendingOpen;pendingOpen=null;
 if(!p.id){openForm(p.kind);return}
 await load();await openRecord(p.kind,p.id);
}
// Las direcciones antiguas (clientes, proveedores) abren Contactos; con create, el formulario de ese tipo.
function open(which,opts={}){
 const kind={clients:'clients',suppliers:'suppliers',prospects:'prospects',people:'people',crm:'prospects'}[which];
 if(opts.create&&kind)pendingOpen={kind};
 if(active()){flush();return true}
 return window.ArcRouter.show('contacts');
}
// Abre la ficha de un contacto concreto (desde un cobro, por ejemplo).
function edit(kind,id){pendingOpen={kind,id};if(active()){flush();return true}return window.ArcRouter.show('contacts')}
window.GamaArchive.register(ARCHIVE,()=>grid?.refresh({page:0}));
window.addEventListener('gama:data-change',e=>{if(['customers','suppliers','crm_contacts','crm_leads'].includes(e.detail?.table))refresh()});
window.addEventListener('gama:language-change',()=>{if(active())render()});
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;epoch++;rows=null;pageRows=[];directoryUnavailable=false;who=undefined;closeForm()});
window.ArcRouter.onEnter('contacts',()=>{
 // Los contactos del CRM no llegan en tiempo real: al entrar se leen de nuevo.
 for(const t of ['crm_contacts','crm_leads'])window.ArcData.invalidate(t);
 rows=null;editing=null;render();
 return()=>{closeForm();grid?.dispose();grid=null};
});
window.GamaContacts={open,edit,refresh,create:async(kind,initial={})=>{const token=epoch;await load();if(token!==epoch)return;if(!active())await open();openForm(kind);for(const [key,value] of Object.entries(initial)){const field=key==='customer_id'?'customer':key==='lead_id'?'lead':key;draft[field]=value}paintFields()}};
if(window.ArcRouter.current==='contacts')render();
})();
