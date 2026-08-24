/* GAMA V10 stable UI layer: Spanish-only, lightweight navigation, lazy scanner, clean menu. */
(function(){
  'use strict';

  let zxingPromise = null;
  window.loadZXing = function(){
    if (window.ZXingBrowser) return Promise.resolve(window.ZXingBrowser);
    if (zxingPromise) return zxingPromise;
    zxingPromise = new Promise((resolve,reject)=>{
      const s=document.createElement('script');
      s.src='https://unpkg.com/@zxing/browser@0.2.1';
      s.async=true;
      s.onload=()=>window.ZXingBrowser?resolve(window.ZXingBrowser):reject(new Error('Scanner library unavailable'));
      s.onerror=()=>reject(new Error('Scanner library could not be loaded'));
      document.head.appendChild(s);
    });
    return zxingPromise;
  };

  const ICONS={
    'Panel de control':'<path d="M4 19V9m5 10V5m5 14v-7m5 7V3"/><path d="M2 19h20"/>',
    'Productos':'<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9L12 3Z"/><path d="m4 7.5 8 4.5 8-4.5M12 12v9"/>',
    'Clientes':'<circle cx="9" cy="8" r="3"/><circle cx="17" cy="9" r="2.5"/><path d="M3 20c.5-4 2.5-6 6-6s5.5 2 6 6M15 14c3 0 5 1.5 6 4"/>',
    'Entradas / Salidas':'<path d="M7 4v16M7 4l-3 3m3-3 3 3M17 20V4m0 16-3-3m3 3 3-3"/>',
    'Facturación':'<path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3Z"/><path d="M9 8h6M9 12h6M9 16h4"/>',
    'Inventario':'<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 8h8M8 12h8M8 16h5"/>',
    'Auditoría':'<path d="M12 3 20 6v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3Z"/><path d="m8.5 12 2.2 2.2 4.8-5"/>',
    'Proveedores':'<path d="M3 7h11v10H3zM14 10h4l3 3v4h-7z"/><circle cx="7" cy="19" r="2"/><circle cx="18" cy="19" r="2"/>',
    'Informes':'<path d="M4 19V5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v14"/><path d="M7 16v-4M12 16V8M17 16v-6"/>',
    'Configuración':'<path d="M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z"/><path d="M4 12H2m20 0h-2M12 4V2m0 20v-2M5 5 3.5 3.5M20.5 20.5 19 19M19 5l1.5-1.5M3.5 20.5 5 19"/>',
    'Copias de seguridad':'<path d="M4 7h16v13H4z"/><path d="M8 7V4h8v3M8 13h8M12 10v6m0 0-2-2m2 2 2-2"/>',
    'Usuarios':'<circle cx="12" cy="8" r="3"/><path d="M5 21c.6-4.5 2.9-7 7-7s6.4 2.5 7 7"/>',
    'Notificaciones':'<path d="M18 9a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/>',
    'Tareas':'<rect x="4" y="4" width="16" height="16" rx="2"/><path d="m8 9 1.5 1.5L12 8M8 14h8M8 17h5"/>',
    'Agenda':'<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M8 3v4M16 3v4M4 9h16M8 13h3M8 16h5"/>',
    'Etiquetas':'<path d="M4 5h9l7 7-8 8-8-8V5Z"/><circle cx="8" cy="9" r="1.3"/>',
    'Ubicaciones':'<path d="M12 21s7-6.1 7-11a7 7 0 1 0-14 0c0 4.9 7 11 7 11Z"/><circle cx="12" cy="10" r="2.5"/>',
    'Códigos de barras':'<path d="M4 5v14M7 5v14M10 5v14M14 5v14M17 5v14M20 5v14"/>',
    'Unidades':'<path d="M4 7h16M4 12h10M4 17h16"/><circle cx="17" cy="12" r="2"/>',
    'Ayuda y soporte':'<circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.6 2.6 0 1 1 4.5 1.8c-1.2 1.2-2 1.5-2 3M12 17h.01"/>'
  };

  const MENU_LABELS=Object.keys(ICONS);

  function spanishOnly(){
    try{localStorage.setItem('gama-language','es');}catch(e){}
    document.documentElement.lang='es';
    document.querySelectorAll('.gamaLanguage').forEach(el=>el.remove());
    if(window.translate) window.translate('es');
    document.querySelectorAll('.gamaLanguage').forEach(el=>el.remove());
  }

  function addMenuStyles(){
    if(document.getElementById('gama-clean-menu-style')) return;
    const st=document.createElement('style');
    st.id='gama-clean-menu-style';
    st.textContent=`
      .gamaMenuCard{position:relative!important;display:flex!important;flex-direction:column!important;align-items:center!important;justify-content:center!important;text-align:center!important;min-height:152px!important;padding:20px 14px!important;background:#fff!important;border:1px solid #E3EBEE!important;border-radius:20px!important;color:#18324A!important;box-shadow:0 5px 18px rgba(24,50,74,.07)!important;transition:transform .16s ease,box-shadow .16s ease,border-color .16s ease!important;overflow:hidden!important}
      .gamaMenuCard:hover{transform:translateY(-2px)!important;box-shadow:0 9px 24px rgba(24,50,74,.10)!important;border-color:#C9DDE1!important}
      .gamaMenuIcon{width:68px;height:68px;border-radius:20px;background:#EAF5F6;display:grid;place-items:center;margin-bottom:13px;color:#087C8B;flex:0 0 auto}
      .gamaMenuIcon svg{width:34px;height:34px;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}
      .gamaMenuCard.gamaMenuOrange .gamaMenuIcon{background:#FFF0E5;color:#F47A2A}
      .gamaMenuTitle{font-size:18px;font-weight:800;line-height:1.15;color:#18324A}
      .gamaMenuSub{margin-top:7px;font-size:12px;font-weight:600;color:#7A8892;line-height:1.2}
      @media(max-width:700px){.gamaMenuCard{min-height:138px!important;border-radius:18px!important;padding:16px 10px!important}.gamaMenuIcon{width:58px;height:58px;border-radius:18px;margin-bottom:10px}.gamaMenuIcon svg{width:29px;height:29px}.gamaMenuTitle{font-size:16px}.gamaMenuSub{font-size:11px}}
      .gamaLanguage{display:none!important}
    `;
    document.head.appendChild(st);
  }

  function cleanLabel(text){return (text||'').replace(/\s+/g,' ').trim();}

  function decorateMenu(){
    addMenuStyles();
    const sections=[...document.querySelectorAll('section')];
    const menuSection=sections.find(s=>MENU_LABELS.some(k=>cleanLabel(s.textContent).includes(k)) && cleanLabel(s.textContent).length>40);
    if(!menuSection) return;
    const candidates=[...menuSection.querySelectorAll('button,a,[role="button"]')];
    const seen=new Set();
    for(const el of candidates){
      if(el.dataset.gamaMenuDecorated) continue;
      const text=cleanLabel(el.textContent);
      const key=MENU_LABELS.find(k=>text.includes(k));
      if(!key || seen.has(key)) continue;
      seen.add(key);
      el.dataset.gamaMenuDecorated='1';
      el.classList.add('gamaMenuCard');
      if(key==='Facturación'||key==='Inventario'||key==='Configuración') el.classList.add('gamaMenuOrange');
      const icon=document.createElement('span');
      icon.className='gamaMenuIcon';
      icon.setAttribute('aria-hidden','true');
      icon.innerHTML='<svg viewBox="0 0 24 24">'+ICONS[key]+'</svg>';
      el.insertBefore(icon,el.firstChild);
      const title=document.createElement('span');
      title.className='gamaMenuTitle';
      title.textContent=key;
      el.appendChild(title);
      const sub=cleanLabel(text.replace(key,''));
      if(sub){const small=document.createElement('span');small.className='gamaMenuSub';small.textContent=sub;el.appendChild(small)}
      [...el.childNodes].filter(n=>n.nodeType===3 && cleanLabel(n.textContent)===key).forEach(n=>n.remove());
    }
  }

  function boot(){
    spanishOnly();
    decorateMenu();
    if(window.showTab && !window.showTab.__gamaStableSpanish){
      const original=window.showTab;
      const wrapped=function(){
        const result=original.apply(this,arguments);
        requestAnimationFrame(()=>{spanishOnly();decorateMenu();});
        return result;
      };
      wrapped.__gamaStableSpanish=true;
      window.showTab=wrapped;
    }
    window.addEventListener('error',e=>console.warn('[GAMA]',e.message));
  }

  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',boot,{once:true});
  else boot();
})();
