/* GAMA — header stable + navigation module stable */
(function(){
'use strict';
function goMainMenu(){
  try{
    if(typeof window.showTab==='function'){
      window.showTab('mainmenu',null);
      window.scrollTo(0,0);
      return;
    }
  }catch(e){}
  document.querySelectorAll('section').forEach(function(sec){sec.classList.remove('active');sec.style.display='none'});
  var main=document.getElementById('mainmenu');
  if(main){main.classList.add('active');main.style.display='block'}
  window.scrollTo(0,0);
}
function bindBackButtons(){
  document.querySelectorAll('.backHome').forEach(function(btn){
    if(btn.dataset.gamaBackBound==='1')return;
    btn.dataset.gamaBackBound='1';
    btn.type='button';
    btn.removeAttribute('href');
    btn.addEventListener('click',function(e){
      e.preventDefault();
      e.stopImmediatePropagation();
      goMainMenu();
    },true);
  });
}
function ensureLogout(){
  var h=document.querySelector('header.gamaHeader');
  if(!h)return;
  var a=h.querySelector('.headActions');
  if(!a){a=document.createElement('div');a.className='headActions';h.appendChild(a)}
  var b=document.getElementById('gamaLogoutBtn');
  if(!b){
    b=document.createElement('button');
    b.id='gamaLogoutBtn';
    b.type='button';
    b.textContent='Cerrar sesión';
    b.title='Cerrar sesión';
    b.setAttribute('aria-label','Cerrar sesión');
    b.onclick=function(){
      if(!confirm('¿Quieres cerrar la sesión de tu cuenta GAMA?'))return;
      var done=function(){try{localStorage.removeItem('gama_session_v1')}catch(e){}location.reload()};
      try{
        if(window.GamaCloud&&typeof window.GamaCloud.signOut==='function')Promise.resolve(window.GamaCloud.signOut()).then(done).catch(done);
        else done();
      }catch(e){done()}
    };
    a.appendChild(b);
  }
  b.textContent='Cerrar sesión';
  b.style.setProperty('display','inline-flex','important');
  b.style.setProperty('visibility','visible','important');
  b.style.setProperty('opacity','1','important');
}
function apply(){
  if(!document.getElementById('gamaFixedHeaderStyle')){
    const s=document.createElement('style');
    s.id='gamaFixedHeaderStyle';
    s.textContent=`
header.gamaHeader{position:sticky!important;top:0!important;z-index:5000!important;isolation:isolate!important}
header.gamaHeader .headIcon.plus,header.gamaHeader #globalBack,header.gamaHeader .gamaHomeButton{display:none!important}
header.gamaHeader .backHome{display:inline-flex!important;visibility:visible!important;align-items:center!important;gap:6px!important;margin:0 0 14px 2px!important;padding:9px 12px!important;background:#EEF7F8!important;border:1px solid #D7EAED!important;border-radius:10px!important;color:#087C8B!important;font-size:15px!important;font-weight:800!important;cursor:pointer!important}
header.gamaHeader #gamaLogoutBtn{display:inline-flex!important;visibility:visible!important;opacity:1!important;align-items:center!important;justify-content:center!important;flex:0 0 auto!important;min-width:118px!important;height:40px!important;padding:8px 13px!important;background:#FFF0EC!important;color:#C94F45!important;border:1px solid #F4D3CD!important;border-radius:10px!important;font-size:13px!important;font-weight:800!important;cursor:pointer!important;white-space:nowrap!important}
header.gamaHeader .headActions{display:flex!important;align-items:center!important;gap:6px!important;min-width:0!important}
header.gamaHeader #gamaActiveAccount{min-width:0!important;max-width:360px!important;overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important}
@media(max-width:700px){
 header.gamaHeader{height:auto!important;min-height:116px!important;padding:8px 12px 10px!important}
 header.gamaHeader .brandMobile{min-width:0!important}
 header.gamaHeader .headActions{width:auto!important;justify-content:flex-end!important;gap:5px!important}
 header.gamaHeader #gamaActiveAccount{flex:1 1 auto!important;max-width:none!important;font-size:11px!important;padding:7px 9px!important}
 header.gamaHeader #gamaLogoutBtn{flex:0 0 auto!important;min-width:112px!important;width:auto!important;height:38px!important;font-size:12px!important;padding:7px 9px!important}
 .backHome{font-size:15px!important;margin-bottom:12px!important}
}
`;
    document.head.appendChild(s);
  }
  bindBackButtons();
  ensureLogout();
  if(!window.__gamaHeaderObserver){
    window.__gamaHeaderObserver=new MutationObserver(function(){bindBackButtons();ensureLogout()});
    if(document.body)window.__gamaHeaderObserver.observe(document.body,{childList:true,subtree:true});
  }
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',apply,{once:true});else apply();
})();