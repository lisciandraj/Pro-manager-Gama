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
 return `<label class="cfgModuleTile" for="${esc(key)}"><span class="cfgTileTop"><span class="cfgTileIcon gamaF2Icon" data-arc-fam="${esc(definition.accent||'cyan')}" aria-hidden="true"><svg viewBox="0 0 24 24">${icon}</svg></span><input id="${esc(key)}" type="checkbox" ${scope==='profile'?'data-role-module':'data-mod'}="${esc(m.id)}" ${on?'checked':''} ${disabled?'disabled':''} aria-labelledby="${esc(key)}-name" aria-describedby="${esc(key)}-desc${detail?' '+esc(key)+'-state':''}"></span><b id="${esc(key)}-name" data-gi-live>${esc(label)}</b><span id="${esc(key)}-desc" class="cfgTileDesc" data-gi-live>${esc(definition.description||'')}</span>${detail?`<small id="${esc(key)}-state" class="cfgTileState">${live(detail)}</small>`:''}</label>`;
}
function profilePanel(){
 const api=window.GamaRoleAccess;
 if(!api?.isReady())return `<div class="arcPanel card"><p role="alert">${live('No se pudieron cargar los permisos. Reintenta para configurarlos.')}</p><button class="arcButton" id="cfgAccessRetry">${live('Reintentar')}</button></div>`;
 if(draft===null){const saved=api.snapshot(profile);draft=new Set(saved.disabled_modules);draftVersion=saved.version;}
 const mods=window.ArcModules.registry.filter(m=>m.menu);
 const rows=mods.map(m=>{
  const compatible=api.base(profile,m.id),locked=api.locked(profile,m.id),on=compatible&&!draft.has(m.id);
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
 const access=id==='access-settings';
 css();
 const s=section(id);
 if(access&&!isAdmin()){window.ArcUI.render(s,'');return}
 const head=window.GamaUI.header({
  title:access?'🔐 Parámetros de acceso':'⚙️ Configuración',
  lead:access?'Configura los módulos de la empresa y los accesos de cada perfil.':isAdmin()?'Configura tu empresa, sus documentos y el idioma de la aplicación.':'Personaliza el idioma de la aplicación.'
 });

 const preferences='<div class="arcPanel card"><h3 data-gi-live data-gi=a44204ce1a2f>Idioma de la aplicación</h3><p data-gi-live data-gi=0527a0d7acec>El idioma se guarda en este dispositivo.</p><div id="gamaSettingsLanguage"></div></div>';
 if(!access){
  window.ArcUI.render(s,head+preferences+(isAdmin()?'<div id="coCompany" data-gi-ignore></div><div id="cfgReferences" data-gi-ignore></div>':''));
  window.GamaUI.bindBack(s);
  window.GamaI18n?.mount();
  if(isAdmin()){window.GamaCompany?.mount($('coCompany'));window.GamaReferences?.mountConfig($('cfgReferences'));}
  return;
 }

 const mods=window.GamaModules.list();
 const activos=mods.filter(m=>m.enabled).length;
 const rows=mods.map(m=>moduleTile(m,{scope:'module',on:m.enabled,disabled:m.locked,detail:m.locked?'Disponible permanentemente.':''})).join('');

 window.ArcUI.render(s,head+profilePanel()+`<details open class="arcPanel card"><summary>${live('Activación general de módulos')}</summary>
  <h3 data-gi=ba8656559345>Módulos de la aplicación</h3>
  <div class="cfgCount">${activos} de ${mods.length} activos</div>
  <div id="cfgMsg" class="cfgMsg"></div>
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
   await api.save(profile,[...draft],draftVersion);draft=null;
   accessError=tx('Permisos guardados para todos los usuarios de este perfil.');
  }catch(e){
   if(String(e.message).includes('ACCESS_STALE')){await api.load().catch(()=>{});draft=null;accessError=tx('Otro administrador cambió estos permisos. Revisa la versión actual antes de guardar.');}
   else accessError=tx('No se pudieron guardar los permisos. Tus cambios no se han aplicado.');
  }finally{busy=false;render(viewId)}
 };
 s.querySelectorAll('[data-mod]').forEach(input=>{
  input.onchange=async()=>{
   if(busy||!isAdmin()){input.checked=!input.checked;return}
   const id=input.dataset.mod,on=input.checked;
   busy=true;input.disabled=true;msg('Guardando…');
   try{
    await window.GamaModules.setEnabled(id,on);
    msg(on?'Módulo activado.':'Módulo desactivado. Ya no aparece para nadie.');
    render(viewId);
   }catch(e){
    // Se devuelve el interruptor a donde estaba: dejarlo movido haría creer
    // que el cambio se guardó.
    input.checked=!on;
    console.warn('[GAMA Configuración]',e);
    msg('No se pudo guardar: '+(e&&(e.message||e.details)||e),true);
   }finally{busy=false;input.disabled=false}
  };
 });
}

function open(id='settings'){
 id=id==='access-settings'?'access-settings':'settings';
 if(id==='access-settings'&&!isAdmin()){window.gamaToast?.(window.GamaI18n?.t('Acceso denegado para este perfil.')||'Acceso denegado para este perfil.');return false}
 if(id==='access-settings'){draft=null;accessError='';}
 css();
 render(id);
 window.ArcRouter.show(id);
 document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));
 window.scrollTo({top:0,behavior:'smooth'});
 // Se relee por si otro administrador cambió algo desde otro dispositivo.
 if(id==='access-settings'){Promise.all([window.GamaModules.load(),window.GamaRoleAccess.load()]).then(()=>{if(!busy)render(id)}).catch(()=>{if(!busy)render(id)});}
}

window.GamaSettings={open,render};
window.GamaOpenSettings=()=>open('settings');
window.GamaOpenAccessSettings=()=>open('access-settings');
window.addEventListener('gama:auth-change',()=>{if(!isAdmin())$('access-settings')?.replaceChildren()});
})();
