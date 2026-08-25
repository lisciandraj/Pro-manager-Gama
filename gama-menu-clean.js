/* GAMA clean menu: one icon + one label per button, Spanish only. */
(function(){
  'use strict';
  const ITEMS=[
    ['Panel de control','dashboard','chart'],['Productos','products','cube'],['Clientes','clients','users'],
    ['Entradas / Salidas','movement','move'],['Facturación','billing','invoice'],['Inventario','stock','stock'],
    ['Auditoría','audit','audit'],['Proveedores','suppliers','truck'],['Informes','reports','pie'],
    ['Configuración','settings','gear'],['Copias de seguridad','backup','cloud'],['Usuarios','users','user'],
    ['Notificaciones','notifications','bell'],['Tareas','tasks','task'],['Agenda','calendar','calendar'],
    ['Etiquetas','labels','tag'],['Ubicaciones','locations','pin'],['Códigos de barras','barcode','barcode'],
    ['Unidades','units','ruler'],['Ayuda y soporte','support','help']
  ];
  const ICONS={
    chart:'<path d="M4 19V10m5 9V6m5 13v-8m5 8V3"/><path d="m4 9 5-4 5 3 6-6"/>',
    cube:'<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9L12 3Z"/><path d="m4 7.5 8 4.5 8-4.5M12 12v9"/>',
    users:'<circle cx="9" cy="8" r="3"/><circle cx="17" cy="9" r="2.5"/><path d="M3 20c.5-4 2.5-6 6-6s5.5 2 6 6M15 14c3 0 5 1.5 6 4"/>',
    move:'<path d="M7 4v16M17 20V4M4 7l3-3 3 3M14 17l3 3 3-3"/>',
    invoice:'<path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3Z"/><path d="M9 8h6M9 12h6M9 16h4"/>',
    stock:'<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 8h8M8 12h8M8 16h5"/>',
    audit:'<path d="M12 3 20 6v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3Z"/><path d="m8.5 12 2.2 2.2 4.8-5"/>',
    truck:'<path d="M3 7h11v10H3zM14 10h4l3 3v4h-7z"/><circle cx="7" cy="19" r="2"/><circle cx="18" cy="19" r="2"/>',
    pie:'<path d="M12 3a9 9 0 1 0 9 9h-9V3Z"/><path d="M14 3a7 7 0 0 1 7 7h-7V3Z"/>',
    gear:'<circle cx="12" cy="12" r="3"/><path d="M19 12h2M3 12h2M12 3v2M12 19v2M18 6l-2 2M8 16l-2 2M18 18l-2-2M8 8 6 6"/>',
    cloud:'<path d="M7 18h11a4 4 0 0 0 .5-8 6 6 0 0 0-11.6 1A3.5 3.5 0 0 0 7 18Z"/><path d="M12 12v6m0 0-2-2m2 2 2-2"/>',
    user:'<circle cx="12" cy="8" r="3.5"/><path d="M5 21c0-4 3-6 7-6s7 2 7 6"/>',
    bell:'<path d="M18 9a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9Z"/><path d="M10 21h4"/>',
    task:'<rect x="4" y="4" width="16" height="16" rx="2"/><path d="m8 9 2 2 4-4M8 15h8"/>',
    calendar:'<rect x="4" y="5" width="16" height="15" rx="2"/><path d="M8 3v4M16 3v4M4 9h16"/>',
    tag:'<path d="M4 5h9l7 7-8 8-8-8V5Z"/><circle cx="8" cy="9" r="1.3"/>',
    pin:'<path d="M12 21s7-6 7-11a7 7 0 0 0-14 0c0 5 7 11 7 11Z"/><circle cx="12" cy="10" r="2.5"/>',
    barcode:'<path d="M4 5v14M7 5v14M10 5v14M14 5v14M17 5v14M20 5v14"/>',
    ruler:'<path d="m5 19 14-14 2 2-14 14-2-2Z"/><path d="m8 16 2 2m1-5 2 2m1-5 2 2"/>',
    help:'<circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.6 2.6 0 1 1 4.5 1.8c-1.2 1.2-2 1.5-2 3M12 17h.01"/>'
  };
  function style(){
    if(document.getElementById('gama-clean-menu-css')) return;
    const s=document.createElement('style');s.id='gama-clean-menu-css';
    s.textContent=`#mainmenu .gamaCleanGrid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:16px;padding:12px 18px 24px}#mainmenu .gamaCleanCard{box-sizing:border-box;min-height:160px;padding:18px 10px;border:1px solid #e1e9ec;border-radius:18px;background:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;box-shadow:0 5px 18px rgba(24,50,74,.07);color:#173246;cursor:pointer}#mainmenu .gamaCleanIcon{width:64px;height:64px;border-radius:18px;background:#e8f5f6;color:#087c8b;display:grid;place-items:center;margin-bottom:14px}#mainmenu .gamaCleanCard:nth-child(5n+2) .gamaCleanIcon,#mainmenu .gamaCleanCard:nth-child(5n+5) .gamaCleanIcon{background:#fff0e5;color:#f47a2a}#mainmenu .gamaCleanIcon svg{width:34px;height:34px;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}#mainmenu .gamaCleanTitle{font-size:17px;font-weight:800;line-height:1.2}@media(max-width:900px){#mainmenu .gamaCleanGrid{grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}}@media(max-width:600px){#mainmenu .gamaCleanGrid{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;padding:10px}#mainmenu .gamaCleanCard{min-height:145px;padding:15px 8px;border-radius:16px}#mainmenu .gamaCleanIcon{width:58px;height:58px;border-radius:17px;margin-bottom:10px}#mainmenu .gamaCleanIcon svg{width:30px;height:30px}#mainmenu .gamaCleanTitle{font-size:15px}}`;
    document.head.appendChild(s);
  }
  function render(){
    const host=document.getElementById('mainmenu');if(!host)return;
    style();document.documentElement.lang='es';
    document.querySelectorAll('.gamaLanguage').forEach(e=>e.remove());
    host.replaceChildren();
    const title=document.createElement('h2');title.textContent='Menú principal';title.style.cssText='margin:22px 18px 8px;color:#173246;font-size:28px';
    const desc=document.createElement('p');desc.textContent='Accede rápidamente a todas las funciones de GAMA Stock Manager.';desc.style.cssText='margin:0 18px 14px;color:#7b8891;font-size:14px';
    const grid=document.createElement('div');grid.className='gamaCleanGrid';
    ITEMS.forEach(([label,route,iconName])=>{const b=document.createElement('button');b.type='button';b.className='gamaCleanCard';b.innerHTML='<span class="gamaCleanIcon" aria-hidden="true"><svg viewBox="0 0 24 24">'+ICONS[iconName]+'</svg></span><span class="gamaCleanTitle"></span>';b.querySelector('.gamaCleanTitle').textContent=label;b.addEventListener('click',()=>{if(window.showTab)window.showTab(route,null)});grid.appendChild(b)});
    host.append(title,desc,grid);
  }
  function boot(){render();if(window.showTab&&!window.showTab.__gamaClean){const old=window.showTab;window.showTab=function(){const r=old.apply(this,arguments);if(arguments[0]==='mainmenu')setTimeout(render,0);return r};window.showTab.__gamaClean=true}}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
