/* GAMA — alertas operativas y análisis independiente de cada etapa. */
(function(){
'use strict';
const $=id=>document.getElementById(id),esc=window.ArcUI.esc;
const money=v=>window.GamaCurrency.format(v),num=v=>Number(v||0).toLocaleString('es-EC',{maximumFractionDigits:3});
const kinds={crm_stale:'Oportunidades sin seguimiento',service_late:'SAV fuera de plazo',all:'Todas',low_stock:'Productos bajo mínimo',overdue_invoice:'Facturas vencidas',due_soon_invoice:'Pagos próximos a vencer',quote:'Presupuestos sin respuesta',shortage:'Pedidos bloqueados',receipt:'Recepciones atrasadas',failed_delivery:'Entregas fallidas',late_delivery:'Entregas atrasadas',backorder:'Reliquats',stock_variance:'Diferencias de inventario',unbilled:'Pendiente de facturar',fleet_deadline:'Vencimientos de flota',payable_overdue:'Facturas de proveedor vencidas',payable_due_soon:'Pagos a proveedor próximos a vencer'};
let version=0,snapshot=null,offset=0,kind='all',state='active',from='',to='',timer=null,notificationClass='all',win=null,current=null,projectCount=0;
const allowed=()=>window.gamaAccessAllowed?.('operations')||window.gamaAccessAllowed?.('notifications');
async function rpc(action,data={}){await window.GamaCloudReady;const c=await window.GamaCloud.db();const r=await window.ArcData.rawRpc('gama_operations_action',{p_action:action,p_data:data});if(r.error)throw r.error;if(!r.data)throw Error('No se recibieron los datos.');return r.data}
function error(e){const s=String(e?.message||e);return /ALERT_RESOLVED|ALERT_CHANGED/.test(s)?'El dossier cambió. Actualiza las alertas.':/AUTH_REQUIRED|ROLE_NOT_ALLOWED/.test(s)?'Tu sesión no permite acceder a estos datos.':'No se pudo completar la operación. '+s}
function css(){ /* Styles are compiled in architect-components.css. */ }
function badge(n){document.querySelectorAll('[data-go-badge]').forEach(x=>{x.textContent=num(n);x.setAttribute('aria-label',num(n)+' alertas activas')})}
/* Notificaciones: la campana abre una ventana con un menú lateral. Arriba,
   todas las alertas; después, cada categoría del centro de acción con su
   recuento completo (también lo pospuesto); al final, los proyectos, las
   validaciones y las preferencias. Abrir un dossier cierra la ventana. */
const CATEGORIES=[
 {id:'shortage',label:'Pedidos bloqueados',phrase:'pedidos bloqueados por falta de stock',red:true,icon:'cart'},
 {id:'late_delivery',label:'Entregas atrasadas',phrase:'entregas atrasadas',red:true,icon:'truck'},
 {id:'quote',label:'Presupuestos sin respuesta',phrase:'presupuestos sin respuesta desde hace más de 7 días',finance:true,icon:'invoice'},
 {id:'low_stock',label:'Productos bajo mínimo',phrase:'productos bajo stock mínimo',icon:'stock'},
 {id:'receipt',label:'Recepciones atrasadas',phrase:'recepciones de proveedores atrasadas',icon:'warehouse'},
 {id:'due_soon_invoice',label:'Pagos próximos a vencer',phrase:'pagos próximos a vencer',finance:true,icon:'banknote'},
 {id:'overdue_invoice',label:'Facturas vencidas',phrase:'en facturas vencidas',finance:true,red:true,icon:'ledger'},
];
const SLIDERS='<path d="M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1"/><circle cx="15" cy="6" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="17" cy="18" r="2"/>';
// Antes del primer recuento, las categorías de finanzas se suponen por el perfil; el servidor lo confirma.
const financeRole=()=>{try{return ['admin','administrador','commercial','comercial'].includes(JSON.parse(localStorage.getItem('gama_session_v1')||'{}').role)}catch(_){return false}};
// Las facturas se cuentan por alerta: el centro de acción da el importe de las vencidas.
const count=(d,k)=>Number((['due_soon_invoice','overdue_invoice'].includes(k)?d?.counts?.[k]:d?.action_center?.[k])||0);
function tabsFor(d){
 const icon=n=>window.ArcUI.icons[n]||'',fin=d?d.finance:financeRole();
 return [{id:'all',label:'Todas las alertas',icon:icon('bell'),pane:'alerts',badge:d?.active_count?num(d.active_count):''},
  ...CATEGORIES.filter(c=>fin||!c.finance).map(c=>{const n=count(d,c.id);return {id:c.id,label:c.label,icon:icon(c.icon),pane:'alerts',badge:n?num(n):'',tone:n?(c.red?'danger':'warning'):''}}),
  ...(window.gamaAccessAllowed?.('projects')?[{id:'projects',label:'Proyectos',icon:icon('project'),pane:'projects',badge:projectCount?num(projectCount):'',tone:projectCount?'warning':''}]:[]),
  {id:'approvals',label:'Validaciones',icon:icon('checklist'),pane:'approvals'},
  {id:'preferences',label:'Preferencias',icon:SLIDERS,pane:'preferences'}];
}
const otherDialog=()=>[...document.querySelectorAll('dialog[open]')].some(d=>d!==win?.el);
const paneError=(host,e)=>{if(host?.isConnected)window.ArcUI.render(host,'<p class="goBox goError" role="alert">'+esc(error(e))+'</p>')};
function choose(t){
 if(t.pane==='alerts'){
  // Cada categoría enseña todas sus alertas, también las pospuestas; «Todas», las activas.
  if(t.id!==current){kind=t.id;state=t.id==='all'?'active':'all';offset=0}
  current=t.id;return load();
 }
 current=t.id;
 if(t.pane==='projects')return projects();
 if(t.pane==='approvals')return window.ArchitectControls?.approvals($('goApprovals')).catch(e=>paneError($('goApprovals'),e));
 if(t.pane==='preferences')return preferences($('goPreferences'));
}
function openWindow(first='all'){
 if(win?.el.open){win.select(first,{focus:true});return win}
 // Una ventana que se está cerrando (su «close» llega después) no se reutiliza.
 win?.el.remove();win=null;current=null;
 win=window.ArcUI.sideDialog({id:'arcNotifyDialog',prefix:'notify',title:'Notificaciones',navLabel:'Apartados de las notificaciones',opener:$('arcNotify'),tabs:tabsFor(snapshot),
  panes:[{id:'alerts',html:'<div class="goTools"><button type="button" class="arcButton secondary" id="goRefresh" data-gi-live data-gi=fe5f6628c7b5>Actualizar</button><button type="button" class="arcButton secondary" id="goSwitch" data-gi-live data-gi=334fff09abf7>Ver el panel de control</button></div><div id="goMain" aria-live="polite" data-gi-live></div>'},
   {id:'projects',html:'<div id="goProjects"></div>'},{id:'approvals',html:'<div id="goApprovals" data-gi-ignore></div>'},{id:'preferences',html:'<div id="goPreferences" data-gi-ignore></div>'}],
  onSelect:choose,onClose:api=>{if(win===api){win=null;version++}}});
 $('goRefresh').onclick=()=>{load();if(current==='projects')projects()};$('goSwitch').onclick=()=>window.ArcRouter?.open('dashboard');
 win.select(first,{focus:true});
 return win;
}
async function open(id='notifications',{tab}={}){if(id==='operations')return window.ArcRouter?.open('dashboard');if(!window.gamaAccessAllowed?.(id))return;openWindow(tab||'all')}
// Los proyectos tienen su apartado: su recuento se suma a la campana.
function projects(){const host=$('goProjects');if(!host||!window.gamaAccessAllowed?.('projects'))return;const token=version;return window.GamaProjects?.mountAlerts(host).then(n=>{if(token!==version||!Number.isFinite(n))return;projectCount=n;if(snapshot)badge(Number(snapshot.active_count)+n);win?.setTabs(tabsFor(snapshot))})}
function actionButton(a,i,d){if(d.finance&&window.gamaAccessAllowed?.('payments')&&['due_soon_invoice','overdue_invoice'].includes(a.kind))return `<button class="arcButton primary" data-go-action="${i}" data-gi-live data-gi=bec97941a8a9>Preparar recordatorio de pago</button>`;return d.finance&&['shortage','low_stock','quote'].includes(a.kind)?`<button class="arcButton primary" data-go-action="${i}" data-gi-live>${a.kind==='quote'?'Preparar recordatorio':a.kind==='low_stock'?'Crear compra':'Preparar compra'}</button>`:''}
async function primaryAction(a){if(['due_soon_invoice','overdue_invoice'].includes(a.kind))return window.GamaPayments.remind(a.target_id);if(a.kind==='quote')return window.GamaQuotes.remind(a.target_id);return window.gamaPrepareActionPurchase(a.kind==='shortage'?{order_id:a.target_id}:{product_id:a.target_id})}
function render(d){const host=$('goMain');if(!host)return;const cat=CATEGORIES.find(c=>c.id===current);window.ArcUI.render(host,`<div class="goBox">${cat?`<h3 data-gi-live>${cat.label}</h3><p class="goLead"><b>${cat.id==='overdue_invoice'?money(d.action_center?.overdue_invoice||0):num(count(d,cat.id))}</b> <span data-gi-live>${cat.phrase}</span></p><p class="goMeta" data-gi-live data-gi=f56232d4b01b>Recuento completo, incluidas las alertas pospuestas.</p>`:`<h3 data-gi=fa5e06b81d3b>Alertas y dossiers pendientes</h3><p class="goMeta" data-gi=b8ceeb8f0273>Se cierran automáticamente al desaparecer su causa. Tomar o posponer una alerta no cambia el pedido ni el stock.</p>`}<div class="goTools">${cat?'':`<label data-gi=3868d2843d59>Tipo<select id="goKind">${Object.entries(kinds).filter(([k])=>d.finance||!['quote','unbilled','overdue_invoice','due_soon_invoice'].includes(k)).filter(([k])=>d.warehouse||k!=='stock_variance').filter(([k])=>k!=='fleet_deadline'||window.gamaAccessAllowed?.('fleet')).map(([k,v])=>`<option value="${k}" ${kind===k?'selected':''} data-gi-live>${esc(window.GamaI18n?.t?.(v)||v)}${d.counts[k]?' ('+num(d.counts[k])+')':''}</option>`).join('')}</select></label>`}<label data-gi=6b2421cb1936>Seguimiento<select id="goState">${[['active','Activas'],['mine','A mi cargo'],['snoozed','Pospuestas'],['all','Todas']].map(([k,v])=>`<option value="${k}" ${state===k?'selected':''} data-gi-live>${v}</option>`).join('')}</select></label></div><p>${num(d.total)} <span data-gi-live data-gi=218f1e55d352>alertas</span> · <span data-gi-live data-gi=8b0062fa48c5>Actualizado</span> ${esc(new Date(d.generated_at).toLocaleString(window.GamaI18n?.locale||'es-EC'))}</p></div><div id="goAlerts">${d.alerts.map((a,i)=>`<article class="goAlert" data-priority="${a.priority}"><h3><span data-gi-live>${esc(a.title)}</span> · ${esc(a.reference)}</h3><b>${esc(a.customer)}</b><p data-gi-live>${esc(a.detail)}</p><div class="goMeta">${(a.handling==='snoozed'?'<span data-gi-live data-gi=1a1e46a26c37>Pospuesta hasta</span> '+esc(new Date(a.snoozed_until).toLocaleString(window.GamaI18n?.locale||'es-EC')):'<span data-gi-live>'+(a.handling==='in_progress'?'En tratamiento':'Pendiente')+'</span>')}${a.assigned_name?' · '+esc(a.assigned_name):''}</div>${a.escalated?'<p class="goError">Requiere escalación: plazo de seguimiento superado</p>':''}${a.next_action?`<p><strong data-gi=9acafd51ebe3>Próxima acción:</strong> ${esc(a.next_action)}${a.due_at?' · '+esc(new Date(a.due_at).toLocaleString()):''}</p>`:''}${a.root_cause?`<p>Causa: ${esc(a.root_cause)}</p>`:''}${a.note?`<p class="goNote">${esc(a.note)}</p>`:''}<div class="goActions"><button class="arcButton primary" data-go-open="${i}" data-gi=ea9c6b5027ee>Abrir dossier</button>${actionButton(a,i,d)}<button class="arcButton secondary" data-go-history="${i}" data-gi=995c071dfaee>Historial</button><button class="arcButton secondary" data-go-handle="${i}" data-status="in_progress" data-gi=2a0649ddbb72>Tomar a mi cargo</button><button class="arcButton secondary" data-go-handle="${i}" data-status="snoozed" data-gi=67867df644d2>Posponer 24 h</button>${a.handling!=='open'?`<button class="arcButton secondary" data-go-handle="${i}" data-status="open" data-gi=44f9bcc46952>Reactivar</button>`:''}</div></article>`).join('')||'<div class="goBox" data-gi=7d2fbc623876>No hay alertas para este filtro.</div>'}</div><div class="goTools"><button class="arcButton secondary" id="goPrev" ${offset===0?'disabled':''} data-gi=e4ce7c09d51e>Anterior</button><span data-gi-live>Página ${Math.floor(offset/50)+1}</span><button class="arcButton secondary" id="goNext" ${offset+50>=d.total?'disabled':''} data-gi-live>Siguiente</button></div>`);
 if($('goKind'))$('goKind').onchange=()=>{kind=$('goKind').value;offset=0;load()};$('goState').onchange=()=>{state=$('goState').value;offset=0;load()};$('goPrev').onclick=()=>{offset=Math.max(0,offset-50);load()};$('goNext').onclick=()=>{offset+=50;load()};$('goPeriod')?.addEventListener('click',()=>{from=$('goFrom').value;to=$('goTo').value;if(!from||!to||from>to){window.gamaToast?.('Revisa las fechas del periodo.');return}load()});
 host.querySelectorAll('[data-go-open]').forEach(b=>b.onclick=()=>act(b,()=>dossier(d.alerts[Number(b.dataset.goOpen)])));
 host.querySelectorAll('[data-go-action]').forEach(b=>b.onclick=()=>act(b,()=>primaryAction(d.alerts[Number(b.dataset.goAction)])));
 host.querySelectorAll('[data-go-history]').forEach(b=>b.onclick=()=>act(b,async()=>{const rows=await rpc('history',{key:d.alerts[Number(b.dataset.goHistory)].alert_key});window.ArcUI.dialog({title:'Historial de la alerta',saveLabel:'Cerrar',body:window.ArcUI.table({columns:[{key:'created_at',label:'Fecha'},{key:'action',label:'Acción'},{key:'actor',label:'Responsable'},{key:'note',label:'Nota'}],items:rows}),onSave:async()=>{}})}));
 host.querySelectorAll('[data-go-handle]').forEach(b=>b.onclick=()=>handle(d.alerts[Number(b.dataset.goHandle)],b.dataset.status));
}
async function act(btn,fn){btn.disabled=true;try{await fn()}catch(e){window.gamaToast?.(error(e))}finally{btn.disabled=false}}
async function load(){if(!allowed()||!win)return;const token=++version,host=$('goMain');if(host)window.ArcUI.render(host,'<div class="goBox" data-gi=5c6c1068bf1a>Cargando datos…</div>');try{const d=await rpc('snapshot',{from,to,kind,state,offset,track:true,respect_preferences:true,notification_class:notificationClass});if(token!==version)return;snapshot=d;from=d.from;to=d.to;badge(d.active_count+projectCount);win?.setTabs(tabsFor(d));render(d);projects()}catch(e){if(token===version&&host)window.ArcUI.render(host,'<p class="goBox goError" role="alert">'+esc(error(e))+'</p>')}}
async function handle(a,status){const people=await window.ArcData.all('profiles',{select:'id,full_name',eq:{active:true},order:'full_name'});if(people.error){window.gamaToast?.(people.error.message);return}const title=status==='snoozed'?'Posponer durante 24 horas':status==='open'?'Reactivar alerta':'Organizar seguimiento';window.ArcUI.dialog({title,body:`<p>${esc(a.reference)} · ${esc(a.title)}</p>`+window.ArcUI.field({key:'assigned_to',label:'Responsable (vacío: yo)',type:'select',value:a.assigned_to||'',options:people.data.map(p=>({id:p.id,name:p.full_name}))})+window.ArcUI.field({key:'root_cause',label:'Causa identificada',type:'textarea',value:a.root_cause||''})+window.ArcUI.field({key:'next_action',label:'Próxima acción',value:a.next_action||'',required:status!=='open'})+window.ArcUI.field({key:'due_at',label:'Plazo de seguimiento',type:'datetime-local',value:a.due_at?new Date(new Date(a.due_at)-new Date().getTimezoneOffset()*60000).toISOString().slice(0,16):'',required:status!=='open'})+window.ArcUI.field({key:'note',label:'Nota',type:'textarea',value:a.note||''}),onSave:async el=>{const data=Object.fromEntries(new FormData(el.querySelector('form')));data.due_at=data.due_at?new Date(data.due_at).toISOString():null;await rpc('handle',{key:a.alert_key,fingerprint:a.fingerprint,status,...data});await load()}})}

async function dossier(a){
 if(a.target==='opportunity'){window.GamaOpenCRM?.();window.ArcRouter.show('crm');return}
 if(a.target==='service'){window.ArcRouter.show('sav');return}

 const mod={order:'sales-orders',quote:'quotes',purchase:'gamaPurchasesV14',count:'warehouses',invoice:'payments',product:'products',fleet_vehicle:'fleet',fleet_driver:'fleet',return:'returns',opportunity:'crm',service:'sav',supplier_invoice:'accounting',expense:'accounting',bank_transaction:'accounting',accounting_entry:'accounting'}[a.target];if(mod&&!window.gamaAccessAllowed?.(mod))throw Error('Este módulo está desactivado o tu perfil no permite abrirlo.');
 if(a.target==='product'){const rows=await window.GamaSales.rows('replenishment_needs',{eq:{product_id:a.target_id}});const n=rows[0];if(!n)throw Error('Producto no disponible.');return window.GamaSales.modal('Stock · '+n.name,`<p>${esc(n.reference)}</p><p><span data-gi=f7c81b7f5a10>Stock físico: </span>${num(n.on_hand)} · reservado: ${num(n.reserved)} · disponible: ${num(n.available)}</p><p><span data-gi=cb0215950a6c>Mínimo: </span>${num(n.min_stock)} · entrante: ${num(n.incoming)} · compra sugerida: ${num(n.suggested_purchase)}</p>`,'Cerrar',async()=>{})}
 if(a.target==='return')return window.GamaReturns.openReturn(a.target_id);
 const ledger={supplier_invoice:'payables',expense:'expenses',bank_transaction:'cash',accounting_entry:'ledger'}[a.target];
 if(ledger)return window.GamaAccounting.open({section:ledger});
 if(a.target==='fleet_vehicle')return window.GamaFleet.openVehicle(a.target_id);
 if(a.target==='fleet_driver')return window.GamaFleet.openDriver();
 if(a.target==='invoice')return window.GamaPayments.open({invoiceId:a.target_id});
 if(a.target==='order')return window.GamaSales.openOrder(a.target_id);
 if(a.target==='quote'){await window.GamaQuotes.open();return window.GamaQuotes.view(a.target_id)}
 if(a.target==='purchase')return window.gamaOpenPurchaseDossier(a.target_id);
 if(a.target==='count')return window.GamaInventoryV2.openCount(a.target_id);
 if(a.target==='delivery'){
  if(window.gamaAccessAllowed?.('tms')){if(!window.gamaTMS?.openDelivery)throw Error('El módulo TMS está cargando. Reintenta.');return window.gamaTMS.openDelivery(a.target_id)}
  const rows=await window.GamaSales.rows('sales_deliveries',{eq:{tms_delivery_id:a.target_id}});if(!rows[0])throw Error('No se encontró el pedido relacionado.');return window.GamaSales.openOrder(rows[0].order_id);
 }
}
// Preferencias: en su apartado de la ventana, con su propio «Guardar».
async function preferences(host){if(!host)return;const U=window.ArcUI,t=(es,fr,en)=>({fr,en}[window.GamaI18n?.locale?.slice(0,2)]||es);U.render(host,`<div class="goBox">${t('Cargando…','Chargement…','Loading…')}</div>`);try{const session=await window.GamaCloud.getSession(),uid=session.data?.session?.user?.id;if(!uid)throw Error('AUTH_REQUIRED');const r=await window.GamaCloud.list('erp_notification_preferences',{eq:{user_id:uid}});if(r.error)throw r.error;if(!host.isConnected)return;const pref=r.data?.[0]||{hidden_kinds:[],only_mine:false};
 U.render(host,`<form class="arcPanel card goPrefs" data-go-prefs><h3>${t('Preferencias de notificación','Préférences de notification','Notification preferences')}</h3>`+`<p>${t('Estas preferencias filtran tus notificaciones. Los indicadores operativos conservan todas las alertas.','Ces préférences filtrent vos notifications. Les indicateurs opérationnels conservent toutes les alertes.','These preferences filter your notifications. Operational indicators retain all alerts.')}</p><label class="goCheck"><input name="mine" type=checkbox ${pref.only_mine?'checked':''}> ${t('Sólo a mi cargo','Seulement à ma charge','Only assigned to me')}</label>`+U.field({key:'class',label:t('Prioridad mostrada','Priorité affichée','Displayed priority'),type:'select',value:notificationClass,options:[{id:'all',name:t('Todas','Toutes','All')},{id:'action',name:t('Acciones prioritarias','Actions prioritaires','Priority actions')},{id:'information',name:t('Información','Information','Information')}]})+`<fieldset class="goTypes"><legend>${t('Tipos visibles','Types visibles','Visible types')}</legend>`+Object.entries(kinds).filter(([k])=>k!=='all').map(([k,label])=>`<label><input type=checkbox name="kind" value="${esc(k)}" ${pref.hidden_kinds.includes(k)?'':'checked'}> ${esc(window.GamaI18n?.t(label)||label)}</label>`).join('')+'</fieldset>'+`<p class="arcFormError gsError" role="alert"></p><div class="arcToolbar"><button type="submit" class="arcButton primary">${t('Guardar las preferencias','Enregistrer les préférences','Save preferences')}</button></div><p class="goMeta" role="status" data-go-prefs-status></p></form>`);
 const form=host.querySelector('[data-go-prefs]'),status=host.querySelector('[data-go-prefs-status]');form.addEventListener('input',()=>{status.textContent=''});
 U.bindForm(form,async()=>{const data=new FormData(form),visible=data.getAll('kind'),res=await window.GamaCloud.upsert('erp_notification_preferences',{user_id:uid,hidden_kinds:Object.keys(kinds).filter(k=>k!=='all'&&!visible.includes(k)),only_mine:data.has('mine'),updated_at:new Date().toISOString()});if(res.error)throw res.error;notificationClass=data.get('class');offset=0;load();refreshBadge()},{onSuccess:()=>{status.textContent=t('Preferencias guardadas.','Préférences enregistrées.','Preferences saved.')}});
}catch(e){paneError(host,e)}}
async function refreshBadge(){if(!allowed()||document.hidden)return;try{const token=version;const [d,projects]=await Promise.all([rpc('snapshot',{offset:0,respect_preferences:true}),window.GamaProjects?.countAlerts().catch(()=>0)||0]);if(token===version&&allowed())badge(Number(d.active_count)+projects)}catch(_){document.querySelectorAll('[data-go-badge]').forEach(x=>{x.textContent='?';x.setAttribute('aria-label','Alertas sin actualizar')})}}
function install(){css();document.querySelectorAll('[data-go-nav="notifications"]').forEach(b=>{if(!b.querySelector('[data-go-badge]')){const x=document.createElement('span');x.className='goBadge';x.dataset.goBadge='';x.textContent='…';b.appendChild(x)}});}
let queued=false;new MutationObserver(()=>{if(queued)return;queued=true;setTimeout(()=>{queued=false;install()},250)}).observe(document.body,{childList:true,subtree:true});
for(const event of ['gama:sales-change','gama:projects-change'])window.addEventListener(event,()=>{clearTimeout(timer);timer=setTimeout(()=>{refreshBadge();if(win?.el.open&&!otherDialog())load()},500)});
// Renovar el token no cambia nada; cerrar la sesión o perder el permiso cierra la ventana.
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;version++;snapshot=null;projectCount=0;document.querySelectorAll('[data-go-badge]').forEach(x=>x.textContent='…');if(win?.el.open){if(e.detail?.event==='SIGNED_OUT'||!allowed())win.close();else load()}});
setInterval(()=>{if(document.hidden||!allowed())return;if(win?.el.open&&!otherDialog())load();else refreshBadge()},60000);
window.addEventListener('focus',refreshBadge);window.GamaOperations={open,dossier,refreshBadge,preferences:()=>open('notifications',{tab:'preferences'})};install();setTimeout(refreshBadge,2500);
})();
