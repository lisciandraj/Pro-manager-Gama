/* GAMA V10 stability layer: one-time boot, lazy scanner loading, safe navigation. */
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

  function installLanguageSelector(){
    const actions=document.querySelector('.headActions');
    if(!actions || actions.querySelector('.gamaLanguage')) return;
    const select=document.createElement('select');
    select.className='gamaLanguage';
    select.setAttribute('aria-label','Language');
    select.innerHTML='<option value="fr">FR</option><option value="es">ES</option><option value="en">EN</option>';
    select.value=localStorage.getItem('gama-language')||'fr';
    select.onchange=()=>window.translate?.(select.value);
    actions.insertBefore(select,actions.firstChild);
    const st=document.createElement('style');
    st.textContent='.gamaLanguage{height:38px;min-width:64px;border:1px solid #e1e8ec;border-radius:10px;background:#fff;color:#173246;font-weight:700;padding:0 7px}@media(max-width:520px){.gamaLanguage{height:34px;min-width:58px;font-size:11px}}';
    document.head.appendChild(st);
  }

  function boot(){
    installLanguageSelector();
    if(window.translate) window.translate(localStorage.getItem('gama-language')||'fr');
    if(window.showTab && !window.showTab.__gamaStable){
      const original=window.showTab;
      const wrapped=function(){
        const result=original.apply(this,arguments);
        requestAnimationFrame(()=>{
          installLanguageSelector();
          if(window.translate) window.translate(localStorage.getItem('gama-language')||'fr');
        });
        return result;
      };
      wrapped.__gamaStable=true;
      window.showTab=wrapped;
    }
  }

  window.addEventListener('error',e=>console.warn('[GAMA]',e.message));
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',boot,{once:true});
  else boot();
})();
