/* GAMA — personal language configuration and administrator access settings.
   Module writes remain protected by the existing app_modules RLS policy. */
(function(){
'use strict';
if(window.GamaSettings)return;

const $=id=>document.getElementById(id);
const esc=window.ArcUI.esc;
const role=()=>{try{return JSON.parse(localStorage.getItem('gama_session_v1')||'null')?.role||''}catch(e){return ''}};
const isAdmin=()=>role()==='admin'||role()==='administrador';

let busy=false;
const tx=s=>window.GamaI18n?.t?.(s)||s;
const live=s=>`<span data-gi-live>${esc(s)}</span>`;
function moduleTile(m,{on,disabled,detail=''}){
 const definition=window.ArcModules.registry.find(x=>x.id===m.id)||m;
 const label=definition.label||m.label,key='module-'+m.id;
 const icon=window.ArcUI.icons[definition.icon]||window.ArcUI.icons.invoice;
 return `<div class="cfgModuleTile cfgInstallTile${on?' cfgInstalled':''}"><span class="cfgTileTop"><span class="cfgTileIcon gamaF2Icon" data-arc-fam="${esc(definition.accent||'cyan')}" aria-hidden="true"><svg viewBox="0 0 24 24">${icon}</svg></span></span><b id="${esc(key)}-name" data-gi-live>${esc(label)}</b><span id="${esc(key)}-desc" class="cfgTileDesc" data-gi-live>${esc(definition.description||'')}</span>${detail?`<small id="${esc(key)}-state" class="cfgTileState">${live(detail)}</small>`:''}<button id="${esc(key)}" type="button" class="arcButton cfgModuleAction ${on?'cfgUninstall':'cfgInstall'}" data-mod="${esc(m.id)}" ${disabled?'disabled':''} aria-labelledby="${esc(key)}-action ${esc(key)}-name" aria-describedby="${esc(key)}-desc${detail?' '+esc(key)+'-state':''}"><span id="${esc(key)}-action" data-gi-live>${on?'Desinstalar':'Instalar'}</span></button></div>`;
}
function msg(t,err){const m=$('cfgMsg');if(!m)return;m.textContent=t||'';m.className='cfgMsg'+(t?(err?' cfgErr':' cfgOk'):'')}

function section(id='settings'){
 let s=$(id);
 if(!s){s=document.createElement('section');s.id=id;(document.querySelector('.wrap')||document.body).appendChild(s)}
 return s;
}
function css(){ /* Styles are compiled in architect-components.css. */ }

function render(id='settings'){
 // La configuración ya no es una página: se abre en su ventana, desde la barra superior.
 if(id!=='access-settings'){openDialog();return}
 css();
 const s=section(id);
 if(!isAdmin()){window.ArcUI.render(s,'');return}
 // Los accesos de cada tipo de usuario vienen definidos por defecto (ArcModules.roles);
 // aquí sólo se eligen los módulos que existen para toda la empresa.
 const head=window.GamaUI.header({title:'Parámetros de acceso',lead:'Módulos disponibles para toda la empresa.'});

 const mods=window.GamaModules.list();
 const activos=mods.filter(m=>m.enabled).length;
 const rows=mods.map(m=>moduleTile(m,{on:m.enabled,disabled:m.locked,detail:m.locked?'Disponible permanentemente.':''})).join('');

 window.ArcUI.render(s,head+`<details open class="arcPanel card"><summary>${live('Activación general de módulos')}</summary>
  <h3 data-gi=ba8656559345>Módulos de la aplicación</h3>
  <p class="cfgNote">${live('Los accesos de cada tipo de usuario vienen definidos por defecto.')}</p>
  <div class="cfgCount">${activos} de ${mods.length} activos</div>
  <div id="cfgMsg" class="cfgMsg" role="status" aria-live="polite"></div>
  <div class="cfgTileGrid">${rows}</div>
 </details>`);
 window.GamaI18n?.mount();
 bind(id);
}

function bind(viewId){
 const s=section(viewId);
 window.GamaUI.bindBack(s);
 s.querySelectorAll('button[data-mod]').forEach(button=>{
  button.onclick=async()=>{
   if(busy||!isAdmin()||button.disabled)return;
   const id=button.dataset.mod,on=!window.GamaModules.enabled(id);
   busy=true;button.disabled=true;button.setAttribute('aria-busy','true');msg(tx('Guardando…'));
   try{
    await window.GamaModules.setEnabled(id,on);
    render(viewId);
    msg(tx(on?'Módulo activado.':'Módulo desactivado. Ya no aparece para nadie.'));
    $('module-'+id)?.focus({preventScroll:true});
   }catch(e){
    // Keep the previous action and colour until the change is saved.
    console.warn('[GAMA Configuración]',e);
    msg(tx('No se pudo guardar: ')+(e&&(e.message||e.details)||e),true);
   }finally{busy=false;button.disabled=false;button.removeAttribute('aria-busy')}
  };
 });
}

/* Configuración: una ventana desde la rueda de la barra superior, con sus
   apartados en un menú lateral. El idioma es de cada uno; lo demás, de la
   empresa y sólo para el administrador. La ficha de la empresa sigue siendo
   un único formulario con un solo «Guardar»: cada apartado enseña su parte. */
const PREFERENCES='<div class="arcPanel card"><h3 data-gi-live data-gi=a44204ce1a2f>Idioma de la aplicación</h3><p data-gi-live data-gi=0527a0d7acec>El idioma se guarda en este dispositivo.</p><div id="gamaSettingsLanguage"></div></div>';
const GLOBE='<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.7 2.5 15.3 0 18-2.5-2.7-2.5-15.3 0-18Z"/>';
const SECTIONS=[
 {id:'language',label:'Idioma',icon:GLOBE,pane:'language'},
 {id:'company',label:'Información de la empresa',icon:'factory',pane:'company',admin:true},
 {id:'identity',label:'Identidad de los documentos',icon:'documents',pane:'company',admin:true},
 {id:'fiscal',label:'Ajustes fiscales',icon:'ledger',pane:'company',admin:true},
 {id:'references',label:'Referencias de documentos',icon:'tag',pane:'references',admin:true},
 {id:'policies',label:'Reglas operativas',icon:'gauge',pane:'policies',admin:true},
 {id:'security',label:'Seguridad de mi cuenta',icon:'lock',pane:'security'},
];
// Cada apartado se carga la primera vez que se enseña: abrir la ventana para el idioma no pide nada al servidor.
const PANES={
 company:host=>window.GamaCompany?.mount(host),
 references:host=>window.GamaReferences?.mountConfig(host),
 policies:host=>window.ArchitectControls?.mountPolicies(host),
 security:host=>window.ArchitectIdentity?.security(host),
};
const HOSTS={company:'coCompany',references:'cfgReferences',policies:'cfgPolicies',security:'cfgSecurity'};
let dialog=null;
function show(section){
 const el=dialog?.el;if(!el)return;
 const host=el.querySelector(`[data-side-pane="${section.pane}"] [data-cfg-host]`);
 if(host&&!host.dataset.cfgMounted){host.dataset.cfgMounted='1';PANES[section.pane]?.(host)}
 // La ficha de la empresa es una: cada apartado enseña sólo sus tarjetas.
 el.querySelector('[data-side-pane="company"]')?.setAttribute('data-co-view',section.id);
}
function openDialog(section='language'){
 const admin=isAdmin(),items=SECTIONS.filter(s=>!s.admin||admin);
 if(dialog?.el.open){dialog.select(section);return dialog.el}
 // Una ventana que se está cerrando (su «close» llega después) no se reutiliza.
 dialog?.el.remove();dialog=null;
 const icon=s=>window.ArcUI.icons[s.icon]||s.icon;
 dialog=window.ArcUI.sideDialog({id:'arcSettingsDialog',prefix:'cfg',title:'Configuración',navLabel:'Apartados de la configuración',opener:document.getElementById('arcSettings'),
  tabs:items.map(s=>({id:s.id,label:s.label,icon:icon(s),pane:s.pane})),
  panes:[{id:'language',html:PREFERENCES},...[...new Set(items.map(s=>s.pane))].filter(p=>HOSTS[p]).map(p=>({id:p,html:`<div id="${HOSTS[p]}" data-cfg-host data-gi-ignore></div>`}))],
  onSelect:show,onClose:api=>{if(dialog===api)dialog=null}});
 const el=dialog.el;
 // Con la ventana abierta, si la cuenta deja de ser administradora se cierra (ver gama:auth-change).
 if(admin)el.dataset.admin='';
 // La ficha de la empresa se guarda entera: si falta algo de otro apartado, se va a él.
 el.addEventListener('invalid',e=>{const part=e.target.closest?.('[data-co-section]')?.dataset.coSection,pane=el.querySelector('[data-side-pane="company"]');if(part&&pane&&pane.dataset.coView!==part)dialog.select(part)},true);
 dialog.select(items.some(s=>s.id===section)?section:'language',{focus:true});
 window.GamaI18n?.mount();
 return el;
}
// open('fiscal'), open('references')…: la ventana en ese apartado. Los accesos siguen siendo una página.
function open(id='settings'){
 if(id!=='access-settings')return openDialog(SECTIONS.some(s=>s.id===id)?id:'language');
 if(!isAdmin()){window.gamaToast?.(window.GamaI18n?.t('Acceso denegado para este perfil.')||'Acceso denegado para este perfil.');return false}
 css();
 render(id);
 window.ArcRouter.show(id);
 document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));
 window.scrollTo({top:0,behavior:'smooth'});
 // Se relee por si otro administrador cambió algo desde otro dispositivo.
 window.GamaModules.load().then(()=>{if(!busy)render(id)}).catch(()=>{if(!busy)render(id)});
}

window.GamaSettings={open,render,openDialog};
window.GamaOpenSettings=()=>openDialog();
window.GamaOpenAccessSettings=()=>open('access-settings');
window.addEventListener('gama:auth-change',e=>{if(!isAdmin())$('access-settings')?.replaceChildren();if(dialog?.el.open&&(e.detail?.event==='SIGNED_OUT'||!role()||(dialog.el.dataset.admin!=null&&!isAdmin())))dialog.close()});
})();
