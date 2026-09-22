/* Contactos: clientes, proveedores y contactos de prospectos en un solo módulo.
   Cada pestaña es la pantalla que ya existía —la ficha de cliente, el
   directorio de proveedores y los contactos del CRM—; aquí sólo se reúnen y se
   elige, al crear, qué clase de contacto es. Las tablas no cambian. */
(function(){'use strict';
const esc=window.ArcUI.esc,$=id=>document.getElementById(id);
const T=s=>window.GamaI18n?.t?.(s)||s,tr=s=>`<span data-gi-live>${esc(s)}</span>`;
const TABS=[
 {id:'clients',label:'Clientes',kind:'Cliente',hint:'Quien te compra: ficha, condiciones de pago y categoría de precios.'},
 {id:'suppliers',label:'Proveedores',kind:'Proveedor',hint:'A quien le compras: contacto y condiciones.'},
 {id:'prospects',label:'Contactos de prospectos',kind:'Contacto de un prospecto',hint:'Una persona de una empresa que aún no es cliente, con su papel en la decisión.'}
];
let tab='clients',dispose=null,clientsPane=null,pendingNew=null;
// Clientes y Proveedores son el módulo Contactos; los contactos de prospectos son del CRM.
const can=id=>!!window.gamaAccessAllowed?.(id==='prospects'?'crm':'contacts');
const tabs=()=>TABS.filter(t=>can(t.id));
function section(){let s=$('contacts');if(!s){s=document.createElement('section');s.id='contacts';(document.querySelector('.wrap')||document.body).append(s)}return s}
// La ficha de cliente es HTML de index.html con sus funciones globales: se traslada una vez, intacta.
function clientsHost(){
 if(!clientsPane){clientsPane=document.createElement('div');clientsPane.id='contactsClients';const legacy=$('clients');if(legacy){legacy.querySelectorAll(':scope>.gamaStdHeader').forEach(h=>h.remove());clientsPane.append(...legacy.childNodes);legacy.remove()}}
 return clientsPane;
}
function pane(body,routed){
 dispose?.();dispose=null;
 // Al entrar por el router, renderForRoute ya pinta la lista de clientes: una sola vez.
 if(tab==='clients'){body.append(clientsHost());if(!routed)window.renderClients?.($('clientSearch')?.value||'');return}
 const host=document.createElement('div');host.id=tab==='suppliers'?'contactsSuppliers':'contactsProspects';body.append(host);
 if(tab==='suppliers'){dispose=window.GamaSuppliers?.mount(host)||null;return}
 window.GamaCRMContacts?.mount(host,{filter:'prospecto'});dispose=()=>window.GamaCRMContacts?.unmount(host);
}
function render(routed=false){
 const s=section(),list=tabs();
 if(!list.some(t=>t.id===tab))tab=list[0]?.id||'clients';
 const current=list.find(t=>t.id===tab);
 window.ArcUI.render(s,window.GamaUI.header({title:'Contactos',lead:'Clientes, proveedores y contactos de prospectos.',module:'contacts'})
  +`<div class="ctBar"><div class="gdfTabs" role="tablist" aria-label="${esc(T('Tipo de contacto'))}">${list.map(t=>`<button type="button" role="tab" class="gdfTab" data-contacts-tab="${t.id}" aria-selected="${t.id===tab}" aria-controls="contactsPanel-${t.id}">${tr(t.label)}</button>`).join('')}</div><button type="button" class="arcButton primary" id="ctNew">${tr('＋ Nuevo contacto')}</button></div>`
  +`<p class="gsHint" id="contactsHint">${current?tr(current.hint):''}</p><div id="contactsPanel-${tab}" class="ctPanel" role="tabpanel"></div>`);
 window.GamaUI.bindBack(s);
 s.querySelectorAll('[data-contacts-tab]').forEach(b=>b.onclick=()=>{tab=b.dataset.contactsTab;render()});
 s.querySelector('#ctNew').onclick=chooseKind;
 // Un panel por pestaña: el enlazado genérico de pestañas oculta el panel de las demás.
 pane(s.querySelector('.ctPanel'),routed);
 window.dispatchEvent(new CustomEvent('arc:module-rendered',{detail:{id:'contacts'}}));
 if(pendingNew){const kind=pendingNew;pendingNew=null;startNew(kind)}
}
/* Al crear, lo primero es decir qué es: cliente, proveedor o contacto de un
   prospecto. Cada respuesta abre el formulario que le corresponde. */
function chooseKind(){
 const list=tabs();
 const d=window.ArcUI.dialog({title:T('Nuevo contacto'),body:`<p>${tr('¿Qué clase de contacto es?')}</p><div class="ctKinds">${list.map(t=>`<button type="button" class="arcButton secondary" data-contact-kind="${t.id}"><b>${tr(t.kind)}</b><small>${tr(t.hint)}</small></button>`).join('')}</div>`,onSave:async()=>{}});
 d.querySelector('[type=submit]').remove();
 d.querySelectorAll('[data-contact-kind]').forEach(b=>b.onclick=()=>{d.close();open(b.dataset.contactKind,{create:true})});
}
function focus(id){const el=$(id);if(!el)return;el.scrollIntoView?.({block:'center'});try{el.focus()}catch(_){}}
function startNew(kind){
 if(kind==='clients'){window.clearClientForm?.();$('pmCustomerProjects')?.replaceChildren();focus('cName');return}
 if(kind==='suppliers'){$('supClear')?.click();focus($('supForm')?.querySelector('input,select,textarea')?.id);return}
 window.GamaCRMContacts?.create?.('prospecto');
}
function open(which,opts={}){
 const wanted={clients:'clients',suppliers:'suppliers',prospects:'prospects',crm:'prospects'}[which]||which;
 if(TABS.some(t=>t.id===wanted))tab=wanted;
 if(opts.create)pendingNew=tab;
 // El router pinta la pantalla al entrar (onEnter) y la cierra al salir.
 if(window.ArcRouter.current==='contacts'&&section().classList.contains('active')){render();return true}
 return window.ArcRouter.show('contacts');
}
window.ArcRouter.onEnter('contacts',()=>{render(true);return()=>{dispose?.();dispose=null}});
window.GamaContacts={open,tab:()=>tab};
})();
