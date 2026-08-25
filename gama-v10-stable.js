/* GAMA V10 stable UI - Spanish only, one icon + one label per menu button. */
(function(){
  'use strict';

  let zxingPromise=null;
  window.loadZXing=function(){
    if(window.ZXingBrowser) return Promise.resolve(window.ZXingBrowser);
    if(zxingPromise) return zxingPromise;
    zxingPromise=new Promise(function(resolve,reject){
      var s=document.createElement('script');
      s.src='https://unpkg.com/@zxing/browser@0.2.1';
      s.async=true;
      s.onload=function(){window.ZXingBrowser?resolve(window.ZXingBrowser):reject(new Error('Scanner library unavailable'));};
      s.onerror=function(){reject(new Error('Scanner library unavailable'));};
      document.head.appendChild(s);
    });
    return zxingPromise;
  };

  var ITEMS=[
    ['dashboard','Panel de control','chart'],
    ['products','Productos','cube'],
    ['clients','Clientes','users'],
    ['movement','Entradas / Salidas','move'],
    ['billing','Facturación','invoice'],
    ['stock','Inventario','stock'],
    ['audit','Auditoría','audit'],
    ['suppliers','Proveedores','truck'],
    ['reports','Informes','pie'],
    ['settings','Configuración','gear'],
    ['backup','Copias de seguridad','cloud'],
    ['users','Usuarios','user'],
    ['notifications','Notificaciones','bell'],
    ['tasks','Tareas','task'],
    ['calendar','Agenda','calendar'],
    ['labels','Etiquetas','tag'],
    ['locations','Ubicaciones','pin'],
    ['barcode','Códigos de barras','barcode'],
    ['units','Unidades','ruler'],
    ['support','Ayuda y soporte','headset']
  ];

  var ICONS={
    chart:'<path d="M4 19V10m5 9V5m5 14v-7m5 7V3"/><path d="m4 9 5-4 5 3 6-6"/>',
    cube:'<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9L12 3Z"/><path d="m4 7.5 8 4.5 8-4.5M12 12v9"/>',
    users:'<circle cx="9" cy="8" r="3"/><circle cx="17" cy="9" r="2.5"/><path d="M3 20c.5-4 2.5-6 6-6s5.5 2 6 6M15 14c3 0 5 1.5 6 4"/>',
    move:'<path d="M7 4v16M7 4 4 7m3-3 3 3M17 20V4m0 16-3-3m3 3 3-3"/>',
    invoice:'<path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3Z"/><path d="M9 8h6M9 12h6M9 16h4"/>',
    stock:'<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 8h8M8 12h8M8 16h5"/>',
    audit:'<path d="M12 3 20 6v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3Z"/><path d="m8.5 12 2.2 2.2 4.8-5"/>',
    truck:'<path d="M3 7h11v10H3zM14 10h4l3 3v4h-7z"/><circle cx="7" cy="19" r="2"/><circle cx="18" cy="19" r="2"/>',
    pie:'<path d="M12 3a9 9 0 1 0 9 9h-9V3Z"/><path d="M14 3a7 7 0 0 1 7 7h-7V3Z"/>',
    gear:'<circle cx="12" cy="12" r="3"/><path d="M19 12h2M3 12h2M12 3v2M12 19v2M18 6l-2 2M8 16l-2 2M18 18l-2-2M8 8 6 6"/>',
    cloud:'<path d="M7 18h11a4 4 0 0 0 .5-8 6 6 0 0 0-11.6 1A3.5 3.5 0 0 0 7 18Z"/><path d="M12 12v6m0 0-2-2m2 2 2-2"/>',
    user:'<circle cx="12" cy="8" r="3.5"/><path d="M5 21c0-4 3-6 7-6s7 2 7 6"/>',
    bell:'<path d="M18 9a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9Z"/><path d="M10 21h4"/>',
    task:'<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M8 10l2 2 4-4M8 16h6"/>',
    calendar:'<rect x="4" y="5" width="16" height="16" rx="2"/><path d="M8 3v4m8-4v4M4 10h16"/>',
    tag:'<path d="m4 5 8-2 9 9-8 8-9-9V5Z"/><circle cx="8" cy="8" r="1"/>',
    pin:'<path d="M12 21s7-6 7-11a7 7 0 0 0-14 0c0 5 7 11 7 11Z"/><circle cx="12" cy="10" r="2.5"/>',
    barcode:'<path d="M4 5v14M7 5v14M10 5v14M14 5v14M17 5v14M20 5v14"/>',
    ruler:'<path d="m5 19 14-14 2 2-14 14-2-2Z"/><path d="m8 16 2 2m1-5 2 2m1-5 2 2"/>',
    headset:'<path d="M4 14v-2a8 8 0 0 1 16 0v2"/><path d="M4 14h3v5H5a1 1 0 0 1-1-1v-4Zm16 0h-3v5h2a1 1 0 0 0 1-1v-4Z"/>'
  };

  function styles(){
    if(document.getElementById('gama-clean-menu-v2')) return;
    var s=document.createElement('style');
    s.id='gama-clean-menu-v2';
    s.textContent=''
      +'.gamaLanguage{display:none!important}'
      +'.gamaMenuGrid{display:grid!important;grid-template-columns:repeat(5,minmax(0,1fr));gap:14px;margin-top:14px;width:100%}'
      +'.gamaMenuCard{appearance:none!important;-webkit-appearance:none!important;width:100%!important;min-height:150px!important;padding:18px 10px!important;margin:0!important;background:#fff!important;border:1px solid #e1e9ec!important;border-radius:18px!important;display:flex!important;flex-direction:column!important;align-items:center!important;justify-content:center!important;text-align:center!important;color:#18324a!important;box-shadow:0 4px 16px rgba(24,50,74,.07)!important;cursor:pointer!important}'
      +'.gamaMenuCard:active{transform:scale(.98)!important}'
      +'.gamaMenuIcon{width:64px!important;height:64px!important;border-radius:18px!important;background:#e8f5f6!important;color:#087c8b!important;display:grid!important;place-items:center!important;margin:0 0 13px!important;flex:none!important}'
      +'.gamaMenuCard.orange .gamaMenuIcon{background:#fff0e5!important;color:#f47a2a!important}'
      +'.gamaMenuIcon svg{display:block!important;width:34px!important;height:34px!important;fill:none!important;stroke:currentColor!important;stroke-width:1.9!important;stroke-linecap:round!important;stroke-linejoin:round!important}'
      +'.gamaMenuTitle{display:block!important;font-size:16px!important;font-weight:800!important;line-height:1.2!important;color:#18324a!important}'
      +'@media(max-width:900px){.gamaMenuGrid{grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}}'
      +'@media(max-width:600px){.gamaMenuGrid{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.gamaMenuCard{min-height:142px!important;border-radius:16px!important;padding:15px 8px!important}.gamaMenuIcon{width:58px!important;height:58px!important;border-radius:17px!important;margin-bottom:10px!important}.gamaMenuIcon svg{width:30px!important;height:30px!important}.gamaMenuTitle{font-size:15px!important}}';
    document.head.appendChild(s);
  }

  function spanishOnly(){
    document.documentElement.lang='es';
    try{localStorage.setItem('gama-language','es');}catch(e){}
    document.querySelectorAll('.gamaLanguage').forEach(function(el){el.remove();});
    if(typeof window.translate==='function') window.translate('es');
  }

  function renderMenu(){
    var host=document.getElementById('mainmenu');
    if(!host) return;
    styles();
    spanishOnly();

    // Always rebuild the menu from one clean source. This prevents duplicated icons/text.
    var grid=document.createElement('div');
    grid.className='gamaMenuGrid';
    grid.setAttribute('data-gama-clean','true');

    ITEMS.forEach(function(item,index){
      var button=document.createElement('button');
      button.type='button';
      button.className='gamaMenuCard'+(index%5===1||index%5===4?' orange':'');
      button.setAttribute('data-gama-route',item[0]);

      var icon=document.createElement('span');
      icon.className='gamaMenuIcon';
      icon.setAttribute('aria-hidden','true');
      icon.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true">'+ICONS[item[2]]+'</svg>';

      var title=document.createElement('span');
      title.className='gamaMenuTitle';
      title.textContent=item[1];

      // Exactly one icon and one text label per button.
      button.appendChild(icon);
      button.appendChild(title);

      button.addEventListener('click',function(){
        if(typeof window.showTab==='function') window.showTab(item[0],null);
      });
      grid.appendChild(button);
    });

    host.replaceChildren(grid);
  }

  function boot(){
    spanishOnly();
    renderMenu();
    if(typeof window.showTab==='function' && !window.showTab.__gamaCleanMenu){
      var original=window.showTab;
      var wrapped=function(){
        var result=original.apply(this,arguments);
        setTimeout(function(){spanishOnly();},0);
        return result;
      };
      wrapped.__gamaCleanMenu=true;
      window.showTab=wrapped;
    }
  }

  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',boot,{once:true});
  else boot();
})();
