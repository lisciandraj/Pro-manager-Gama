/* GAMA — barra superior estable y simple */
(function(){
'use strict';
function apply(){
 const h=document.querySelector('header.gamaHeader');
 if(!h)return;
 if(!document.getElementById('gamaTopBarFix')){
  const s=document.createElement('style');
  s.id='gamaTopBarFix';
  s.textContent=`
   header.gamaHeader{position:sticky!important;top:0!important;z-index:5000!important;display:grid!important;grid-template-columns:minmax(0,1fr) auto!important;align-items:center!important;gap:8px 12px!important;height:auto!important;min-height:76px!important;padding:9px 14px!important}
   header.gamaHeader .brandMobile{grid-column:1;grid-row:1;min-width:0!important}
   header.gamaHeader .headIcon.plus,header.gamaHeader #globalBack,header.gamaHeader .backHome{display:none!important}
   header.gamaHeader .headActions{grid-column:2;grid-row:1;display:flex!important;align-items:center!important;gap:7px!important;position:static!important;margin:0!important}
   header.gamaHeader .gamaHeaderTools{grid-column:1 / -1;grid-row:2;display:flex!important;align-items:center!important;justify-content:flex-end!important;gap:7px!important;width:100%!important}
   header.gamaHeader #gamaACLUser{display:none!important}
   header.gamaHeader #gamaActiveAccount{position:static!important;display:inline-flex!important;max-width:calc(100vw - 160px)!important;overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important;margin:0!important;transform:none!important}
   header.gamaHeader #gamaCloudAdminBtn{position:static!important;display:inline-flex!important;max-width:135px!important;overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important;margin:0!important;transform:none!important}
   .gamaHomeButton{display:inline-flex!important;align-items:center!important;justify-content:center!important;width:48px!important;height:48px!important;border:0!important;border-radius:12px!important;background:#138A69!important;color:#fff!important;font-size:25px!important;font-weight:800!important;cursor:pointer!important;flex:0 0 48px!important;box-shadow:0 2px 8px #138A6930!important}
   @media(max-width:700px){
    header.gamaHeader{grid-template-columns:1fr auto!important;grid-template-rows:auto auto!important;min-height:116px!important;padding:8px 12px!important}
    header.gamaHeader .brandMobile{grid-column:1 / -1!important;grid-row:1!important}
    header.gamaHeader .headActions{grid-column:2!important;grid-row:1!important;display:none!important}
    header.gamaHeader .gamaHeaderTools{grid-column:1 / -1!important;grid-row:2!important;justify-content:flex-end!important}
    header.gamaHeader #gamaActiveAccount{max-width:calc(100vw - 155px)!important;font-size:11px!important;padding:7px 9px!important}
    header.gamaHeader #gamaCloudAdminBtn{max-width:125px!important;font-size:11px!important;padding:8px 9px!important}
    .gamaHomeButton{width:44px!important;height:44px!important;flex-basis:44px!important}
   }
  `;
  document.head.appendChild(s);
 }
 let tools=h.querySelector('.gamaHeaderTools');
 if(!tools){tools=document.createElement('div');tools.className='gamaHeaderTools';h.appendChild(tools)}
 const account=document.getElementById('gamaActiveAccount');
 const cloud=document.getElementById('gamaCloudAdminBtn');
 if(account&&account.parentElement!==tools)tools.appendChild(account);
 if(cloud&&cloud.parentElement!==tools)tools.appendChild(cloud);
 let home=h.querySelector('.gamaHomeButton');
 if(!home){
  home=document.createElement('button');
  home.type='button';home.className='gamaHomeButton';home.title='Volver al menú principal';home.setAttribute('aria-label','Volver al menú principal');home.textContent='⌂';
  home.onclick=function(){
   document.querySelectorAll('section').forEach(x=>{x.classList.remove('active');x.style.removeProperty('display');x.removeAttribute('hidden')});
   const m=document.getElementById('mainmenu');
   if(m){m.classList.add('active');m.style.setProperty('display','block','important');m.removeAttribute('hidden');}
   window.scrollTo({top:0,behavior:'smooth'});
  };
  const brand=h.querySelector('.brandMobile');
  if(brand)brand.parentNode.insertBefore(home,brand.nextSibling);else h.appendChild(home);
 }
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',apply,{once:true});else apply();
})();
