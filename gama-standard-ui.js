/* GAMA — Cabecera estándar para todos los módulos */
(function(){
  'use strict';
  const STYLE='gamaStandardUIStyleV3';
  const SKIP=new Set(['mainmenu','login','loginSection','auth','gamaPurchasesV14']);
  const TITLES={
    products:['📦 Productos','Gestión de productos, precios y existencias'],
    clients:['👥 Clientes','Gestión de clientes y contactos'],
    suppliers:['🏭 Proveedores','Gestión de proveedores y condiciones de compra'],
    stock:['📊 Inventario','Control de existencias y movimientos'],
    movements:['🔄 Movimientos','Entradas, salidas y ajustes de inventario'],
    billing:['🧾 Facturación','Facturas, ventas y cobros'],
    audit:['🔎 Auditoría','Historial de operaciones y trazabilidad'],
    excel:['📥 Importar Excel','Importación de productos, clientes y proveedores'],
    settings:['⚙️ Configuración','Configuración de GAMA Stock Manager']
  };

  function menu(){
    document.querySelectorAll('section').forEach(s=>{s.classList.remove('active');s.style.display='none'});
    const m=document.getElementById('mainmenu');
    if(m){m.removeAttribute('hidden');m.style.display='block';m.classList.add('active')}
    document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));
    window.scrollTo({top:0,behavior:'smooth'});
  }

  function addStyles(){
    if(document.getElementById(STYLE))return;
    const s=document.createElement('style');
    s.id=STYLE;
    s.textContent=`
      /* Le bouton de retour global est supprimé : le retour se fait depuis la carte du module. */
      #globalBack{display:none!important}
      .gamaStdHeader{display:flex!important;align-items:center!important;justify-content:space-between!important;gap:16px!important;margin:0 0 14px!important;padding:18px 20px!important;background:#fff!important;border:1px solid #E2E8EC!important;border-radius:15px!important;box-shadow:0 3px 16px #1732460d!important}
      .gamaStdKicker{font-size:10px!important;font-weight:850!important;letter-spacing:2px!important;color:#087C8B!important;text-transform:uppercase!important;margin-bottom:4px!important}
      .gamaStdHeader h2{margin:0!important;font-size:27px!important;line-height:1.15!important;color:#18324A!important;font-weight:800!important}
      .gamaStdHeader p{margin:6px 0 0!important;color:#71808A!important;font-size:15px!important;line-height:1.35!important}
      .gamaStdActions{display:flex!important;gap:8px!important;align-items:center!important;flex-shrink:0!important}
      .gamaStdBack{display:inline-flex!important;align-items:center!important;justify-content:center!important;gap:6px!important;white-space:nowrap!important;background:#EEF3F4!important;color:#18324A!important;border:1px solid #DCE5E8!important;border-radius:10px!important;padding:11px 15px!important;font-weight:750!important;cursor:pointer!important;min-height:44px!important}
      .gamaStdBack:hover{background:#E3ECEE!important}
      @media(max-width:700px){.gamaStdHeader{align-items:stretch!important;flex-direction:column!important;padding:15px!important}.gamaStdHeader h2{font-size:23px!important}.gamaStdHeader p{font-size:13px!important}.gamaStdActions{width:100%!important}.gamaStdBack{width:100%!important}}
    `;
    document.head.appendChild(s);
  }

  function titleFor(section){
    const id=(section.id||'').toLowerCase();
    if(TITLES[id])return TITLES[id];
    const h=section.querySelector('h1,h2,h3');
    let title=h?.textContent?.trim()||'Módulo';
    title=title.replace(/^(Nuevo|Nueva|Gestionar|Gestión de)\s+/i,'');
    return [title,'Gestión de GAMA Stock Manager'];
  }

  function directStandardHeader(sec){
    return sec.querySelector(':scope > .gamaStdHeader, :scope > [data-gama-standard-header]');
  }

  function directOwnHeader(sec){
    return sec.querySelector(':scope > .gp14Head');
  }

  function removeGlobalBack(){
    const b=document.getElementById('globalBack');
    if(b)b.remove();
  }

  function addStandardHeader(sec){
    if(directStandardHeader(sec))return;
    if(directOwnHeader(sec)){
      const existing=directOwnHeader(sec);
      if(!existing.querySelector('.gamaStdBack')){
        const actions=existing.querySelector('.gp14TopActions')||existing;
        const b=document.createElement('button');
        b.type='button';
        b.className='gamaStdBack';
        b.textContent='← Volver al menú';
        b.setAttribute('aria-label','Volver al menú');
        b.onclick=menu;
        actions.appendChild(b);
      }
      return;
    }

    const title=titleFor(sec);
    const header=document.createElement('div');
    header.className='gamaStdHeader';
    header.setAttribute('data-gama-standard-header','1');
    header.innerHTML='<div><div class="gamaStdKicker">GAMA STOCK MANAGER</div><h2>'+escapeHtml(title[0])+'</h2><p>'+escapeHtml(title[1])+'</p></div><div class="gamaStdActions"><button type="button" class="gamaStdBack" aria-label="Volver al menú">← Volver al menú</button></div>';
    header.querySelector('button').onclick=menu;
    sec.insertBefore(header,sec.firstChild);
  }

  function standardize(){
    addStyles();
    removeGlobalBack();

    document.querySelectorAll('section').forEach(sec=>{
      if(SKIP.has(sec.id))return;
      addStandardHeader(sec);
    });
  }

  function escapeHtml(v){
    return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  }

  function boot(){
    standardize();
    new MutationObserver(standardize).observe(document.body,{childList:true,subtree:true});
  }

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});
  else boot();
  window.gamaStandardBackToMenu=menu;
})();