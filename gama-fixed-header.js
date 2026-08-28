/* GAMA — stable header + guaranteed navigation/logout controls */
(function(){
'use strict';

function showMainMenu(){
  try{
    if(typeof window.showTab==='function'){
      try{ window.showTab('mainmenu',null); }catch(e){}
      try{ window.showTab('dashboard',null); }catch(e){}
    }
    var sections=document.querySelectorAll('section');
    sections.forEach(function(s){s.classList.remove('active');});
    var mm=document.getElementById('mainmenu');
    if(mm){
      var target=mm.closest('section')||mm;
      target.classList.add('active');
      target.style.display='block';
      mm.style.display='block';
    }
    window.scrollTo(0,0);
  }catch(e){ console.warn('[GAMA] main menu navigation failed',e); }
}

async function forceLogout(){
  if(!confirm('¿Quieres cerrar la sesión de tu cuenta GAMA?')) return;
  try{
    if(window.GamaCloud && typeof window.GamaCloud.signOut==='function'){
      await window.GamaCloud.signOut();
    }
  }catch(e){ console.warn('[GAMA] signOut failed',e); }
  try{ localStorage.removeItem('gama_session_v1'); }catch(e){}
  location.reload();
}

function ensureStyles(){
  if(document.getElementById('gamaFixedHeaderStyle'))return;
  var s=document.createElement('style');
  s.id='gamaFixedHeaderStyle';
  s.textContent=`
header.gamaHeader{position:sticky!important;top:0!important;z-index:5000!important;isolation:isolate!important}
header.gamaHeader .headIcon.plus,header.gamaHeader #globalBack,header.gamaHeader .gamaHomeButton{display:none!important}
header.gamaHeader .backHome{display:inline-flex!important;align-items:center!important;gap:6px!important;cursor:pointer!important}
header.gamaHeader .headActions{display:flex!important;align-items:center!important;gap:6px!important;min-width:0!important}
#gamaActiveAccount{display:inline-flex!important;visibility:visible!important;opacity:1!important;min-width:0!important;overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important}
#gamaLogoutBtn,#gamaVisibleLogout{display:inline-flex!important;visibility:visible!important;opacity:1!important;align-items:center!important;justify-content:center!important;flex:0 0 auto!important;min-width:118px!important;height:40px!important;padding:8px 13px!important;background:#FFF0EC!important;color:#C94F45!important;border:1px solid #F4D3CD!important;border-radius:10px!important;font-size:13px!important;font-weight:800!important;cursor:pointer!important;white-space:nowrap!important}
#gamaVisibleLogout:hover,#gamaLogoutBtn:hover{background:#FFE5DF!important}
#gamaModuleBackBar{display:flex!important;align-items:center!important;gap:10px!important;margin:0 auto!important;max-width:1250px!important;padding:10px 14px 4px!important;background:transparent!important}
#gamaModuleBack{display:inline-flex!important;align-items:center!important;gap:7px!important;border:0!important;background:#E8F5F6!important;color:#087C8B!important;border-radius:10px!important;padding:9px 13px!important;font-size:14px!important;font-weight:800!important;cursor:pointer!important;box-shadow:none!important}
#gamaModuleBack:hover{background:#DDF0F2!important}
@media(max-width:700px){
 header.gamaHeader{height:auto!important;min-height:116px!important;padding:8px 12px 10px!important}
 header.gamaHeader .brandMobile{min-width:0!important}
 header.gamaHeader .headActions{width:100%!important;position:static!important;transform:none!important;justify-content:flex-end!important;flex-wrap:nowrap!important}
 #gamaActiveAccount{flex:1 1 auto!important;max-width:none!important;font-size:11px!important;padding:7px 9px!important}
 #gamaLogoutBtn,#gamaVisibleLogout{flex:0 0 auto!important;min-width:112px!important;height:38px!important;font-size:12px!important;padding:7px 9px!important}
 #gamaModuleBackBar{padding:8px 12px 3px!important}
 #gamaModuleBack{width:100%!important;justify-content:center!important;font-size:14px!important}
}
`;
  document.head.appendChild(s);
}

function ensureHeaderControls(){
  var h=document.querySelector('header.gamaHeader');
  if(!h)return;
  ensureStyles();
  var actions=h.querySelector('.headActions');
  if(!actions){actions=document.createElement('div');actions.className='headActions';h.appendChild(actions)}

  var account=document.getElementById('gamaActiveAccount');
  if(account){account.style.display='inline-flex';account.style.visibility='visible';account.style.opacity='1';}

  var logout=document.getElementById('gamaLogoutBtn');
  if(logout){
    logout.textContent='Cerrar sesión';
    logout.title='Cerrar sesión';
    logout.setAttribute('aria-label','Cerrar sesión');
    logout.style.display='inline-flex';
    logout.style.visibility='visible';
    logout.style.opacity='1';
  }else if(!document.getElementById('gamaVisibleLogout')){
    logout=document.createElement('button');
    logout.id='gamaVisibleLogout';
    logout.type='button';
    logout.textContent='Cerrar sesión';
    logout.title='Cerrar sesión';
    logout.setAttribute('aria-label','Cerrar sesión');
    logout.onclick=forceLogout;
    actions.appendChild(logout);
  }
}

function ensureBackControl(){
  ensureStyles();
  var bar=document.getElementById('gamaModuleBackBar');
  if(!bar){
    bar=document.createElement('div');
    bar.id='gamaModuleBackBar';
    var b=document.createElement('button');
    b.id='gamaModuleBack';
    b.type='button';
    b.innerHTML='← <span>Menú principal</span>';
    b.onclick=showMainMenu;
    bar.appendChild(b);
    var h=document.querySelector('header.gamaHeader');
    if(h&&h.parentNode)h.parentNode.insertBefore(bar,h.nextSibling);
    else document.body.insertBefore(bar,document.body.firstChild);
  }
  var main=document.getElementById('mainmenu');
  var mainVisible=!!main && getComputedStyle(main).display!=='none' && main.closest('section.active');
  bar.style.display=mainVisible?'none':'flex';
}

function apply(){
  ensureHeaderControls();
  ensureBackControl();
}

function boot(){
  apply();
  var obs=new MutationObserver(function(){
    ensureHeaderControls();
    ensureBackControl();
  });
  obs.observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['class','style']});
  setTimeout(apply,500);
  setTimeout(apply,1500);
  setTimeout(apply,3000);
}

if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();