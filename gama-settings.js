/* GAMA — Configuración: qué módulos se ven en la aplicación.

   Sólo para administradores. La comprobación que de verdad manda no está aquí
   sino en la base: la política RLS de app_modules deja escribir únicamente al
   perfil «administrador». Lo de esta pantalla es no enseñar interruptores a
   quien la base va a rechazar de todas formas.

   Configuración no puede apagarse a sí misma (GamaModules la marca como
   `locked`): es la única pantalla desde la que se vuelve a encender lo demás,
   así que apagarla dejaría la aplicación sin salida. Por eso aparece en la
   lista con el interruptor fijo en «Activo» y una nota que lo explica. */
(function(){
'use strict';
if(window.GamaSettings)return;

const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const role=()=>{try{return JSON.parse(localStorage.getItem('gama_session_v1')||'null')?.role||''}catch(e){return ''}};
const isAdmin=()=>role()==='admin'||role()==='administrador';

let busy=false;

function msg(t,err){const m=$('cfgMsg');if(!m)return;m.textContent=t||'';m.className='cfgMsg'+(t?(err?' cfgErr':' cfgOk'):'')}

function section(){
 let s=$('settings');
 if(!s){s=document.createElement('section');s.id='settings';(document.querySelector('.wrap')||document.body).appendChild(s)}
 return s;
}
function css(){
 if($('cfgCss'))return;
 const s=document.createElement('style');s.id='cfgCss';
 s.textContent=`#settings{display:none}
#settings .cfgList{display:grid;gap:9px}
#settings .cfgRow{display:flex;align-items:center;justify-content:space-between;gap:14px;padding:13px 15px;border:1px solid #e4ebee;border-radius:12px;background:#fff}
#settings .cfgRow.off{background:#fbfcfc;border-style:dashed}
#settings .cfgRow b{display:block;font-size:14px;color:#18324a}
#settings .cfgRow small{display:block;color:#81909a;font-size:11px;margin-top:2px}
#settings .cfgRow.off b{color:#8c99a3}
/* Interruptor: una casilla de verdad debajo, para que funcione con teclado y
   con lector de pantalla; lo redondo es sólo la pintura. */
#settings .cfgSwitch{position:relative;flex-shrink:0;width:52px;height:30px}
#settings .cfgSwitch input{position:absolute;inset:0;width:100%;height:100%;margin:0;opacity:0;cursor:pointer;z-index:2}
#settings .cfgSwitch i{position:absolute;inset:0;border-radius:999px;background:#cfd9de;transition:background .15s}
#settings .cfgSwitch i:after{content:'';position:absolute;top:3px;left:3px;width:24px;height:24px;border-radius:50%;background:#fff;box-shadow:0 1px 3px #17324633;transition:transform .15s}
#settings .cfgSwitch input:checked + i{background:#087c8b}
#settings .cfgSwitch input:checked + i:after{transform:translateX(22px)}
#settings .cfgSwitch input:disabled{cursor:not-allowed}
#settings .cfgSwitch input:disabled + i{opacity:.5}
#settings .cfgSwitch input:focus-visible + i{outline:3px solid #087c8b;outline-offset:2px}
#settings .cfgMsg{margin:12px 0;font-size:13px;min-height:18px}
#settings .cfgMsg.cfgOk{color:#138a69}#settings .cfgMsg.cfgErr{color:#c94f45;font-weight:700}
#settings .cfgDenied{padding:26px;text-align:center;color:#71808a}
#settings .cfgCount{color:#71808a;font-size:12px;margin-bottom:12px}`;
 document.head.appendChild(s);
}

function render(){
 css();
 const s=section();
 const head=window.GamaUI.header({
  title:'⚙️ Configuración',
  lead:'Activa o desactiva los módulos de GAMA.'
 });

 if(!isAdmin()){
  s.innerHTML=head+'<div class="card"><div class="cfgDenied">Esta pantalla es sólo para administradores.<br>Pide a un administrador que cambie los módulos activos.</div></div>';
  window.GamaUI.bindBack(s);
  return;
 }

 const mods=window.GamaModules.list();
 const activos=mods.filter(m=>m.enabled).length;
 const rows=mods.map(m=>`
  <div class="cfgRow ${m.enabled?'':'off'}">
   <div>
    <b>${esc(m.label)}</b>
    <small>${m.locked?'Siempre activo: es la pantalla desde la que se encienden los demás.'
                     :(m.enabled?'Visible para todos los usuarios con permiso.':'Oculto para todos los usuarios.')}</small>
   </div>
   <label class="cfgSwitch">
    <input type="checkbox" data-mod="${esc(m.id)}" ${m.enabled?'checked':''} ${m.locked?'disabled':''}
           aria-label="${m.enabled?'Desactivar':'Activar'} ${esc(m.label)}">
    <i></i>
   </label>
  </div>`).join('');

 s.innerHTML=head+`<div class="card">
  <h3>Módulos de la aplicación</h3>
  <div class="cfgCount">${activos} de ${mods.length} activos</div>
  <div id="cfgMsg" class="cfgMsg"></div>
  <div class="cfgList">${rows}</div>
 </div>`;
 bind();
}

function bind(){
 const s=section();
 window.GamaUI.bindBack(s);
 s.querySelectorAll('[data-mod]').forEach(input=>{
  input.onchange=async()=>{
   if(busy){input.checked=!input.checked;return}
   const id=input.dataset.mod,on=input.checked;
   busy=true;input.disabled=true;msg('Guardando…');
   try{
    await window.GamaModules.setEnabled(id,on);
    msg(on?'Módulo activado.':'Módulo desactivado. Ya no aparece para nadie.');
    render();
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

function open(){
 css();
 render();
 document.querySelectorAll('section').forEach(x=>{
  const on=x.id==='settings';
  x.classList.toggle('active',on);
  x.style.setProperty('display',on?'block':'none','important');
  if(on)x.removeAttribute('hidden');
 });
 document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));
 window.scrollTo({top:0,behavior:'smooth'});
 // Se relee por si otro administrador cambió algo desde otro dispositivo.
 window.GamaModules.load().then(render).catch(()=>{});
}

window.GamaSettings={open,render};
window.GamaOpenSettings=open;
})();
