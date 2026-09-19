/* GAMA — personal language configuration and administrator access settings.
   Module writes remain protected by the existing app_modules RLS policy. */
(function(){
'use strict';
if(window.GamaSettings)return;

const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const role=()=>{try{return JSON.parse(localStorage.getItem('gama_session_v1')||'null')?.role||''}catch(e){return ''}};
const isAdmin=()=>role()==='admin'||role()==='administrador';

let busy=false;

function msg(t,err){const m=$('cfgMsg');if(!m)return;m.textContent=t||'';m.className='cfgMsg'+(t?(err?' cfgErr':' cfgOk'):'')}

function section(id='settings'){
 let s=$(id);
 if(!s){s=document.createElement('section');s.id=id;(document.querySelector('.wrap')||document.body).appendChild(s)}
 return s;
}
function css(){
 if($('cfgCss'))return;
 const s=document.createElement('style');s.id='cfgCss';
 s.textContent=`:is(#settings,#access-settings){display:none}
:is(#settings,#access-settings) .cfgList{display:grid;gap:9px}
:is(#settings,#access-settings) .cfgRow{display:flex;align-items:center;justify-content:space-between;gap:14px;padding:13px 15px;border:1px solid var(--arc-surface-3);border-radius:12px;background:#fff}
:is(#settings,#access-settings) .cfgRow.off{background:var(--arc-surface-2);border-style:dashed}
:is(#settings,#access-settings) .cfgRow b{display:block;font-size:14px;color:var(--arc-text)}
:is(#settings,#access-settings) .cfgRow small{display:block;color:var(--arc-text-subtle);font-size:11px;margin-top:2px}
:is(#settings,#access-settings) .cfgRow.off b{color:var(--arc-text-subtle)}
/* Interruptor: una casilla de verdad debajo, para que funcione con teclado y
   con lector de pantalla; lo redondo es sólo la pintura. */
:is(#settings,#access-settings) .cfgSwitch{position:relative;flex-shrink:0;width:52px;height:30px}
:is(#settings,#access-settings) .cfgSwitch input{position:absolute;inset:0;width:100%;height:100%;margin:0;opacity:0;cursor:pointer;z-index:2}
:is(#settings,#access-settings) .cfgSwitch i{position:absolute;inset:0;border-radius:999px;background:var(--arc-line);transition:background .15s}
:is(#settings,#access-settings) .cfgSwitch i:after{content:'';position:absolute;top:3px;left:3px;width:24px;height:24px;border-radius:50%;background:#fff;box-shadow:0 1px 3px rgba(18,37,60,.20);transition:transform .15s}
:is(#settings,#access-settings) .cfgSwitch input:checked + i{background:var(--arc-accent-600)}
:is(#settings,#access-settings) .cfgSwitch input:checked + i:after{transform:translateX(22px)}
:is(#settings,#access-settings) .cfgSwitch input:disabled{cursor:not-allowed}
:is(#settings,#access-settings) .cfgSwitch input:disabled + i{opacity:.5}
:is(#settings,#access-settings) .cfgSwitch input:focus-visible + i{outline:3px solid var(--arc-accent-600);outline-offset:2px}
:is(#settings,#access-settings) .cfgMsg{margin:12px 0;font-size:13px;min-height:18px}
:is(#settings,#access-settings) .cfgMsg.cfgOk{color:var(--arc-success)}:is(#settings,#access-settings) .cfgMsg.cfgErr{color:var(--arc-danger);font-weight:700}
:is(#settings,#access-settings) .cfgDenied{padding:26px;text-align:center;color:var(--arc-text-muted)}
:is(#settings,#access-settings) .cfgCount{color:var(--arc-text-muted);font-size:12px;margin-bottom:12px}`;
 document.head.appendChild(s);
}

function render(id='settings'){
 const access=id==='access-settings';
 css();
 const s=section(id);
 if(access&&!isAdmin()){s.innerHTML='';return}
 const head=window.GamaUI.header({
  title:access?'🔐 Parámetros de acceso':'⚙️ Configuración',
  lead:access?'Activa o desactiva los módulos de Architect.':'Personaliza el idioma de la aplicación.'
 });

 const preferences='<div class="card"><h3 data-gi-live data-gi=a44204ce1a2f>Idioma de la aplicación</h3><p data-gi-live data-gi=0527a0d7acec>El idioma se guarda en este dispositivo.</p><div id="gamaSettingsLanguage"></div></div>';
 if(!access){
  s.innerHTML=head+preferences;
  window.GamaUI.bindBack(s);
  window.GamaI18n?.mount();
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

 s.innerHTML=head+`<div class="card">
  <h3 data-gi=ba8656559345>Módulos de la aplicación</h3>
  <div class="cfgCount">${activos} de ${mods.length} activos</div>
  <div id="cfgMsg" class="cfgMsg"></div>
  <div class="cfgList">${rows}</div>
 </div>`;
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
 document.querySelectorAll('section').forEach(x=>{
  const on=x.id===id;
  x.classList.toggle('active',on);
  x.style.setProperty('display',on?'block':'none','important');
  if(on)x.removeAttribute('hidden');
 });
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
