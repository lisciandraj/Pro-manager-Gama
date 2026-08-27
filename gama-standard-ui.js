/* GAMA — Interfaz estándar para todos los módulos */
(function(){'use strict';
  const STYLE='gamaStandardUIStyle';
  function menu(){
    document.querySelectorAll('section').forEach(s=>{s.classList.remove('active');s.style.display='none'});
    const m=document.getElementById('mainmenu');
    if(m){m.removeAttribute('hidden');m.style.display='block';m.classList.add('active')}
    document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));
    window.scrollTo({top:0,behavior:'smooth'});
  }
  function addStyles(){if(document.getElementById(STYLE))return;const s=document.createElement('style');s.id=STYLE;s.textContent=`
    .gamaStdHeader{display:flex!important;align-items:center!important;justify-content:space-between!important;gap:12px!important;margin:0 0 14px!important;padding:16px 18px!important;background:#fff!important;border:1px solid #E2E8EC!important;border-radius:14px!important;box-shadow:0 3px 16px #1732460d!important}
    .gamaStdHeader h2{margin:0!important;font-size:24px!important;color:#173246!important}.gamaStdHeader p{margin:4px 0 0!important;color:#71808A!important;font-size:13px!important}
    .gamaStdBack{display:inline-flex!important;align-items:center!important;justify-content:center!important;gap:6px!important;white-space:nowrap!important;background:#EEF3F4!important;color:#173246!important;border:1px solid #DCE5E8!important;border-radius:9px!important;padding:10px 13px!important;font-weight:750!important;cursor:pointer!important;min-height:42px!important}
    .gamaStdBack:hover{background:#E3ECEE!important}.gamaStdContent{width:100%!important}
    @media(max-width:700px){.gamaStdHeader{align-items:flex-start!important;flex-direction:column!important;padding:13px!important}.gamaStdHeader h2{font-size:21px!important}.gamaStdBack{width:100%!important}}
  `;document.head.appendChild(s)}
  function titleFor(section){if(section.id==='gamaPurchasesV14')return ['🛒 Compras','Pedidos a proveedores, recepciones e inventario'];const h=section.querySelector('h1,h2');return [h?.textContent?.trim()||'Módulo','Gestión de GAMA Stock Manager']}
  function standardize(){
    addStyles();
    document.querySelectorAll('section').forEach(sec=>{
      if(sec.id==='mainmenu'||sec.dataset.gamaStandard==='1')return;
      sec.dataset.gamaStandard='1';
      const first=sec.firstElementChild;
      if(!first)return;
      const title=titleFor(sec);
      const header=document.createElement('div');header.className='gamaStdHeader';
      header.innerHTML='<div><h2>'+title[0]+'</h2><p>'+title[1]+'</p></div><button type="button" class="gamaStdBack" aria-label="Volver al menú">← Volver al menú</button>';
      header.querySelector('button').onclick=menu;
      sec.insertBefore(header,first);
    });
  }
  function boot(){standardize();new MutationObserver(standardize).observe(document.body,{childList:true,subtree:true});}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
  window.gamaStandardBackToMenu=menu;
})();