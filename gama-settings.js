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
  lead:access?'Activa o desactiva los módulos de Architect.':isAdmin()?'Configura tu empresa, sus documentos y el idioma de la aplicación.':'Personaliza el idioma de la aplicación.'
 });

 const preferences='<div class="arcPanel card"><h3 data-gi-live data-gi=a44204ce1a2f>Idioma de la aplicación</h3><p data-gi-live data-gi=0527a0d7acec>El idioma se guarda en este dispositivo.</p><div id="gamaSettingsLanguage"></div></div>';
 if(!access){
  window.ArcUI.render(s,head+preferences+(isAdmin()?'<div id="coCompany" data-gi-ignore></div>':''));
  window.GamaUI.bindBack(s);
  window.GamaI18n?.mount();
  if(isAdmin())window.GamaCompany?.mount($('coCompany'));
  return;
 }

 const mods=window.GamaModules.list();
 const activos=mods.filter(m=>m.enabled).length;
 const rows=mods.map(m=>`
  <div class="cfgRow ${m.enabled?'':'off'}">
   <div>
    <b data-gi-live>${esc(m.label)}</b>
    <small data-gi-live>${m.locked?'Disponible permanentemente.'
                     :(m.enabled?'Visible para todos los usuarios con permiso.':'Oculto para todos los usuarios.')}</small>
   </div>
   <label class="cfgSwitch">
    <input type="checkbox" data-gi-live data-mod="${esc(m.id)}" ${m.enabled?'checked':''} ${m.locked?'disabled':''}
           aria-label="${m.enabled?'Desactivar':'Activar'} ${esc(m.label)}">
    <i></i>
   </label>
  </div>`).join('');

 window.ArcUI.render(s,head+`<div class="arcPanel card">
  <h3 data-gi=ba8656559345>Módulos de la aplicación</h3>
  <div class="cfgCount">${activos} de ${mods.length} activos</div>
  <div id="cfgMsg" class="cfgMsg"></div>
  <div class="cfgList">${rows}</div>
 </div>`);
 window.GamaI18n?.mount();
 bind(id);
}

function bind(viewId){
 const s=section(viewId);
 window.GamaUI.bindBack(s);
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
 css();
 render(id);
 window.ArcRouter.show(id);
 document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));
 window.scrollTo({top:0,behavior:'smooth'});
 // Se relee por si otro administrador cambió algo desde otro dispositivo.
 if(id==='access-settings')window.GamaModules.load().then(()=>render(id)).catch(()=>{});
}

window.GamaSettings={open,render};
window.GamaOpenSettings=()=>open('settings');
window.GamaOpenAccessSettings=()=>open('access-settings');
window.addEventListener('gama:auth-change',()=>{if(!isAdmin())$('access-settings')?.replaceChildren()});
})();
