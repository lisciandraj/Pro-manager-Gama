/* GAMA V10.3 — remove legacy TMS modules and keep client modules */
(()=>{
'use strict';
const TMS_RE=/\bTMS\b|Entregas\s*\/\s*TMS|gamaTMS/i;
function clean(){
  document.querySelectorAll('#mainmenu .gamaF2Card, #mainmenu button, .tabs .tab, nav button, nav a').forEach(el=>{
    const text=(el.textContent||'').replace(/\s+/g,' ').trim();
    const id=(el.id||'')+' '+(el.dataset?.gamaMenuId||'')+' '+(el.getAttribute('data-tab')||'');
    if(TMS_RE.test(text+' '+id)) el.remove();
  });
  document.querySelectorAll('[id*="gamaTMS" i],[class*="gamaTMS" i],[data-gama-menu-id="gamaTMS"]').forEach(el=>el.remove());
  // Remove legacy TMS sections that may have been injected outside the menu.
  document.querySelectorAll('section,div').forEach(el=>{
    if(el.id && /gamaTMS|tms/i.test(el.id)) el.remove();
  });
}
function boot(){clean();new MutationObserver(clean).observe(document.body,{subtree:true,childList:true});setTimeout(clean,250);setTimeout(clean,1000);setTimeout(clean,2500);setTimeout(clean,5000)}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
