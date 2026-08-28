/* GAMA V10 — main menu: single source, 8 functional modules, no observers */
(function(){
'use strict';

const ITEMS=[
  ['Panel de control','dashboard','chart','teal'],
  ['Productos','products','cube','orange'],
  ['Clientes','clients','users','teal'],
  ['Entradas / Salidas','movement','move','orange'],
  ['Facturación','billing','invoice','orange'],
  ['Inventario','stock','stock','teal'],
  ['Auditoría','audit','audit','orange'],
  ['Proveedores','suppliers','truck','teal']
];

const ICONS={
 chart:'<path d="M4 19V10m5 9V6m5 13v-8m5 8V3"/><path d="m4 9 5-4 5 3 6-6"/>',
 cube:'<path d="m12 3 8 4.5v9L12 21l-8-4.5v-9L12 3Z"/><path d="m4 7.5 8 4.5 8-4.5M12 12v9"/>',
 users:'<circle cx="9" cy="8" r="3"/><circle cx="17" cy="9" r="2.5"/><path d="M3 20c.5-4 2.5-6 6-6s5.5 2 6 6M15 14c3 0 5 1.5 6 4"/>',
 move:'<path d="M7 4v16M17 20V4M4 7l3-3 3 3M14 17l3 3 3-3"/>',
 invoice:'<path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3Z"/><path d="M9 8h6M9 12h6M9 16h4"/>',
 stock:'<path d="M4 7h16v13H4zM7 4h10v3H7zM8 11h8M8 15h5"/>',
 audit:'<path d="M12 3 20 6v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3Z"/><path d="m8.5 12 2.2 2.2 4.8-5"/>',
 truck:'<path d="M3 7h11v10H3zM14 10h4l3 3v4h-7z"/><circle cx="7" cy="19" r="2"/><circle cx="18" cy="19" r="2"/>'
};

function openItem(id){
  if(typeof window.showTab==='function') window.showTab(id,null);
}

function render(){
  const host=document.getElementById('mainmenu');
  if(!host) return;
  host.replaceChildren();

  const intro=document.createElement('div');
  intro.className='menuIntro';
  intro.innerHTML='<div><h2>Menú principal</h2><p>Accede rápidamente a todas las funciones de GAMA Stock Manager.</p></div><span class="onlineBadge"><i></i> En línea</span>';

  const grid=document.createElement('div');
  grid.className='appGrid';

  ITEMS.forEach(([label,id,icon,tone])=>{
    const b=document.createElement('button');
    b.type='button';
    b.className='appTile';
    b.innerHTML='<span class="appIcon '+tone+'"><svg viewBox="0 0 24 24">'+ICONS[icon]+'</svg></span><b></b>';
    b.querySelector('b').textContent=label;
    b.addEventListener('click',()=>openItem(id));
    grid.appendChild(b);
  });

  const footer=document.createElement('div');
  footer.className='menuFooter';
  footer.innerHTML='<span><i></i> Sistema local activo</span><small>GAMA Stock Manager V10</small>';
  host.append(intro,grid,footer);
}

function boot(){
  render();
}

if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',boot,{once:true});
else boot();

window.GAMA_MODULES={open:openItem,list:()=>ITEMS.map(x=>({label:x[0],id:x[1]}))};
})();
