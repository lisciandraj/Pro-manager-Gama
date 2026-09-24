/* GAMA — personal language configuration and administrator access settings.
   Module writes remain protected by the existing app_modules RLS policy. */
(function(){
'use strict';
if(window.GamaSettings)return;

const $=id=>document.getElementById(id);
const esc=window.ArcUI.esc;
const role=()=>{try{return JSON.parse(localStorage.getItem('gama_session_v1')||'null')?.role||''}catch(e){return ''}};
const isAdmin=()=>role()==='admin'||role()==='administrador';

let busy=false,profile='commercial',draft=null,draftVersion=0,accessError='';
const tx=s=>window.GamaI18n?.t?.(s)||s;
const live=s=>`<span data-gi-live>${esc(s)}</span>`;
function moduleTile(m,{scope,on,disabled,detail=''}){
 const definition=window.ArcModules.registry.find(x=>x.id===m.id)||m;
 const label=definition.label||m.label,key=scope+'-'+m.id;
 const icon=window.ArcUI.icons[definition.icon]||window.ArcUI.icons.invoice;
 if(scope==='module')return `<div class="cfgModuleTile cfgInstallTile${on?' cfgInstalled':''}"><span class="cfgTileTop"><span class="cfgTileIcon gamaF2Icon" data-arc-fam="${esc(definition.accent||'cyan')}" aria-hidden="true"><svg viewBox="0 0 24 24">${icon}</svg></span></span><b id="${esc(key)}-name" data-gi-live>${esc(label)}</b><span id="${esc(key)}-desc" class="cfgTileDesc" data-gi-live>${esc(definition.description||'')}</span>${detail?`<small id="${esc(key)}-state" class="cfgTileState">${live(detail)}</small>`:''}<button id="${esc(key)}" type="button" class="arcButton cfgModuleAction ${on?'cfgUninstall':'cfgInstall'}" data-mod="${esc(m.id)}" ${disabled?'disabled':''} aria-labelledby="${esc(key)}-action ${esc(key)}-name" aria-describedby="${esc(key)}-desc${detail?' '+esc(key)+'-state':''}"><span id="${esc(key)}-action" data-gi-live>${on?'Desinstalar':'Instalar'}</span></button></div>`;
 return `<label class="cfgModuleTile" for="${esc(key)}"><span class="cfgTileTop"><span class="cfgTileIcon gamaF2Icon" data-arc-fam="${esc(definition.accent||'cyan')}" aria-hidden="true"><svg viewBox="0 0 24 24">${icon}</svg></span><input id="${esc(key)}" type="checkbox" ${scope==='profile'?'data-role-module':'data-mod'}="${esc(m.id)}" ${on?'checked':''} ${disabled?'disabled':''} aria-labelledby="${esc(key)}-name" aria-describedby="${esc(key)}-desc${detail?' '+esc(key)+'-state':''}"></span><b id="${esc(key)}-name" data-gi-live>${esc(label)}</b><span id="${esc(key)}-desc" class="cfgTileDesc" data-gi-live>${esc(definition.description||'')}</span>${detail?`<small id="${esc(key)}-state" class="cfgTileState">${live(detail)}</small>`:''}</label>`;
}
function profilePanel(){
 const api=window.GamaRoleAccess;
 if(!api?.isReady())return `<div class="arcPanel card"><p role="alert">${live('No se pudieron cargar los permisos. Reintenta para configurarlos.')}</p><button class="arcButton" id="cfgAccessRetry">${live('Reintentar')}</button></div>`;
 if(draft===null){const saved=api.snapshot(profile);draft=new Set(saved.disabled_modules);draftVersion=saved.version;}
 const mods=window.ArcModules.registry.filter(m=>m.menu);
 const rows=mods.map(m=>{
  // Presupuestos y facturas también es el módulo de quien sólo tiene sus pedidos (el almacenero).
  const compatible=api.base(profile,m.id)||window.ArcModules.tabsOf(m.id).some(t=>api.base(profile,t)),locked=api.locked(profile,m.id),on=compatible&&!draft.has(m.id);
  const detail=locked?'Acceso protegido.':!compatible?'No disponible para este perfil.':window.GamaModules.enabled(m.id)?'':'Módulo desactivado para toda la empresa.';
  return moduleTile(m,{scope:'profile',on,disabled:locked||!compatible,detail});
 }).join('');
 return `<div class="arcPanel card"><h3>${live('Accesos por perfil')}</h3><p>${live('Elige los módulos visibles y accesibles para cada perfil. Los permisos sobre los datos y las acciones se mantienen.')}</p><label class="arcField">${live('Perfil')}<select id="cfgProfile">${api.options().map(r=>`<option value="${esc(r.id)}" ${r.id===profile?'selected':''} ${r.custom?'data-gi-ignore':'data-gi-live'}>${esc(r.label)}</option>`).join('')}</select></label><div class="arcToolbar"><button class="arcButton secondary" id="cfgNewProfile">${live('Crear un perfil')}</button></div><div id="cfgCreateProfile" hidden><label class="arcField">${live('Nombre del perfil')}<input id="cfgProfileName" required maxlength="64" autocomplete="off"></label><p>${live('El nuevo perfil copia los permisos del perfil seleccionado. Después puedes personalizar sus módulos.')}</p><div class="arcToolbar"><button class="arcButton primary" id="cfgCreateProfileSave">${live('Crear el perfil')}</button><button class="arcButton secondary" id="cfgCreateProfileCancel">${live('Cancelar')}</button></div></div><div class="cfgTileGrid">${rows}</div><div class="arcToolbar"><button class="arcButton primary" id="cfgSaveProfile">${live('Guardar permisos')}</button><button class="arcButton secondary" id="cfgResetProfile">${live('Restaurar permisos predeterminados')}</button></div><p id="cfgAccessStatus" role="status" class="cfgMsg">${esc(accessError)}</p></div>`;
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
 const head=window.GamaUI.header({title:'🔐 Parámetros de acceso',lead:'Configura los módulos de la empresa y los accesos de cada perfil.'});

 const mods=window.GamaModules.list();
 const activos=mods.filter(m=>m.enabled).length;
 const rows=mods.map(m=>moduleTile(m,{scope:'module',on:m.enabled,disabled:m.locked,detail:m.locked?'Disponible permanentemente.':''})).join('');

 window.ArcUI.render(s,head+profilePanel()+`<details open class="arcPanel card"><summary>${live('Activación general de módulos')}</summary>
  <h3 data-gi=ba8656559345>Módulos de la aplicación</h3>
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
 const api=window.GamaRoleAccess;
 if($('cfgNewProfile'))$('cfgNewProfile').onclick=()=>{$('cfgCreateProfile').hidden=false;$('cfgProfileName').focus()};
 if($('cfgCreateProfileCancel'))$('cfgCreateProfileCancel').onclick=()=>{$('cfgCreateProfile').hidden=true};
 if($('cfgCreateProfileSave'))$('cfgCreateProfileSave').onclick=async()=>{
  if(busy||!isAdmin())return;const name=$('cfgProfileName').value.trim();
  if(!name){$('cfgProfileName').reportValidity();$('cfgProfileName').focus();return;}
  busy=true;const button=$('cfgCreateProfileSave');button.disabled=true;
  try{const created=await api.create(name,profile);profile=created.role;draft=null;accessError=tx('Perfil creado. Personaliza sus módulos y asígnalo en Usuarios.');render(viewId);}
  catch(e){$('cfgAccessStatus').textContent=tx(e.code==='23505'?'Ya existe un perfil con este nombre.':'No se pudo crear el perfil. Reintenta.');}
  finally{busy=false;button.disabled=false;}
 };
 if($('cfgAccessRetry'))$('cfgAccessRetry').onclick=async()=>{try{await api.load()}catch(_){}render(viewId)};
 if($('cfgProfile'))$('cfgProfile').onchange=()=>{profile=$('cfgProfile').value;draft=null;accessError='';render(viewId)};
 s.querySelectorAll('[data-role-module]').forEach(input=>input.onchange=()=>{if(input.checked)draft.delete(input.dataset.roleModule);else draft.add(input.dataset.roleModule);accessError='';});
 if($('cfgResetProfile'))$('cfgResetProfile').onclick=()=>{draft=new Set();accessError=tx('Guarda para aplicar los permisos predeterminados.');render(viewId)};
 if($('cfgSaveProfile'))$('cfgSaveProfile').onclick=async()=>{
  if(busy||!isAdmin())return;busy=true;
  s.querySelectorAll('#cfgProfile,[data-role-module],#cfgSaveProfile,#cfgResetProfile,[data-mod]').forEach(el=>el.disabled=true);
  $('cfgAccessStatus').textContent=tx('Guardando…');
  try{
   // Hidden legacy quote/request routes follow the visible quote module.
   if(draft.has('quotes'))draft.add('billing');else draft.delete('billing');
   // Las pestañas declaradas (los pedidos) siguen a su módulo: el servidor comprueba cada clave.
   for(const m of window.ArcModules.registry.filter(x=>x.tabOf)){if(draft.has(m.tabOf))draft.add(m.id);else draft.delete(m.id);}
   await api.save(profile,[...draft],draftVersion);draft=null;
   accessError=tx('Permisos guardados para todos los usuarios de este perfil.');
  }catch(e){
   if(String(e.message).includes('ACCESS_STALE')){await api.load().catch(()=>{});draft=null;accessError=tx('Otro administrador cambió estos permisos. Revisa la versión actual antes de guardar.');}
   else accessError=tx('No se pudieron guardar los permisos. Tus cambios no se han aplicado.');
  }finally{busy=false;render(viewId)}
 };
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
let dialogEl=null;
function selectSection(id,focus=false){
 const el=dialogEl;if(!el)return;
 const tabs=[...el.querySelectorAll('[data-cfg-tab]')],tab=tabs.find(t=>t.dataset.cfgTab===id)||tabs[0];if(!tab)return;
 const pane=SECTIONS.find(s=>s.id===tab.dataset.cfgTab).pane;
 tabs.forEach(t=>{const on=t===tab;t.setAttribute('aria-selected',String(on));t.tabIndex=on?0:-1});
 el.querySelectorAll('[data-cfg-pane]').forEach(p=>{const on=p.dataset.cfgPane===pane;p.hidden=!on;if(on)p.setAttribute('aria-labelledby',tab.id)});
 const host=el.querySelector(`[data-cfg-pane="${pane}"] [data-cfg-host]`);
 if(host&&!host.dataset.cfgMounted){host.dataset.cfgMounted='1';PANES[pane]?.(host)}
 // La ficha de la empresa es una: cada apartado enseña sólo sus tarjetas.
 el.querySelector('[data-cfg-pane="company"]')?.setAttribute('data-co-view',tab.dataset.cfgTab);
 el.querySelector('.cfgPanes').scrollTop=0;
 if(focus)tab.focus();
}
function openDialog(section='language'){
 const admin=isAdmin(),items=SECTIONS.filter(s=>!s.admin||admin);
 if(dialogEl?.open){selectSection(section);return dialogEl}
 // Una ventana que se está cerrando (su «close» llega después) no se reutiliza.
 dialogEl?.remove();dialogEl=null;
 const icon=s=>window.ArcUI.icons[s.icon]||s.icon;
 const el=document.createElement('dialog');el.className='cfgDialog';el.id='arcSettingsDialog';el.setAttribute('aria-labelledby','cfgDialogTitle');
 // Con la ventana abierta, si la cuenta deja de ser administradora se cierra (ver gama:auth-change).
 if(admin)el.dataset.admin='';
 document.body.appendChild(el);dialogEl=el;
 el.innerHTML=`<div class="cfgDialogHead"><h2 id="cfgDialogTitle">${live('Configuración')}</h2><button type="button" class="arcButton arcIconBtn" data-cfg-close data-gi-aria-label=aeccae342e4b aria-label="Cerrar"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18"/></svg></button></div>`
  +`<div class="cfgDialogBody"><nav class="cfgSide" data-gi-aria-label=f0cdf1e7ad9d aria-label="Apartados de la configuración"><div class="cfgSideList" role="tablist" aria-orientation="vertical">`
  +items.map(s=>`<button type="button" role="tab" id="cfgTab-${s.id}" data-cfg-tab="${s.id}" aria-controls="cfgPane-${s.pane}" aria-selected="false" tabindex="-1"><span class="cfgSideIcon" aria-hidden="true"><svg viewBox="0 0 24 24">${icon(s)}</svg></span>${live(s.label)}</button>`).join('')
  +`</div></nav><div class="cfgPanes"><div role="tabpanel" id="cfgPane-language" data-cfg-pane="language" tabindex="0" hidden>${PREFERENCES}</div>`
  +[...new Set(items.map(s=>s.pane))].filter(p=>HOSTS[p]).map(p=>`<div role="tabpanel" id="cfgPane-${p}" data-cfg-pane="${p}" tabindex="0" hidden><div id="${HOSTS[p]}" data-cfg-host data-gi-ignore></div></div>`).join('')
  +'</div></div>';
 const list=el.querySelector('[role=tablist]');
 // Este menú tiene su propio teclado (vertical en el ordenador, en fila en el teléfono) y
 // tres apartados comparten el panel de la empresa: el comportamiento genérico no se aplica.
 list.__arcTabs=true;window.ArcUI.mount(el);
 list.addEventListener('click',e=>{const t=e.target.closest('[data-cfg-tab]');if(t)selectSection(t.dataset.cfgTab)});
 // Flechas arriba y abajo en el menú lateral; izquierda y derecha cuando, en el teléfono, se pone en fila.
 list.addEventListener('keydown',e=>{const tabs=[...list.querySelectorAll('[data-cfg-tab]')],i=tabs.indexOf(document.activeElement);if(i<0)return;const n=tabs.length,next={ArrowDown:(i+1)%n,ArrowRight:(i+1)%n,ArrowUp:(i+n-1)%n,ArrowLeft:(i+n-1)%n,Home:0,End:n-1}[e.key];if(next==null)return;e.preventDefault();selectSection(tabs[next].dataset.cfgTab,true)});
 el.querySelector('[data-cfg-close]').onclick=()=>el.close();
 // La ficha de la empresa se guarda entera: si falta algo de otro apartado, se va a él.
 el.addEventListener('invalid',e=>{const part=e.target.closest?.('[data-co-section]')?.dataset.coSection,pane=el.querySelector('[data-cfg-pane="company"]');if(part&&pane&&pane.dataset.coView!==part)selectSection(part)},true);
 const back=document.activeElement;
 el.addEventListener('close',()=>{el.remove();if(dialogEl!==el)return;dialogEl=null;(document.getElementById('arcSettings')||back)?.focus?.()},{once:true});
 el.showModal();
 selectSection(items.some(s=>s.id===section)?section:'language',true);
 window.GamaI18n?.mount();
 return el;
}
// open('fiscal'), open('references')…: la ventana en ese apartado. Los accesos siguen siendo una página.
function open(id='settings'){
 if(id!=='access-settings')return openDialog(SECTIONS.some(s=>s.id===id)?id:'language');
 if(!isAdmin()){window.gamaToast?.(window.GamaI18n?.t('Acceso denegado para este perfil.')||'Acceso denegado para este perfil.');return false}
 draft=null;accessError='';
 css();
 render(id);
 window.ArcRouter.show(id);
 document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));
 window.scrollTo({top:0,behavior:'smooth'});
 // Se relee por si otro administrador cambió algo desde otro dispositivo.
 Promise.all([window.GamaModules.load(),window.GamaRoleAccess.load()]).then(()=>{if(!busy)render(id)}).catch(()=>{if(!busy)render(id)});
}

window.GamaSettings={open,render,openDialog};
window.GamaOpenSettings=()=>openDialog();
window.GamaOpenAccessSettings=()=>open('access-settings');
window.addEventListener('gama:auth-change',e=>{if(!isAdmin())$('access-settings')?.replaceChildren();if(dialogEl?.open&&(e.detail?.event==='SIGNED_OUT'||!role()||(dialogEl.dataset.admin!=null&&!isAdmin())))dialogEl.close()});
})();
