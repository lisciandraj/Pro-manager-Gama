/* GAMA header logo: uses the exact logo supplied by the user. */
(function(){
  const SRC='gama-logo-header.jpg?v=1';
  function apply(){
    const box=document.querySelector('.gamaProLogo');
    if(!box) return;
    const img=document.createElement('img');
    img.src=SRC;
    img.alt='GAMA';
    img.decoding='async';
    img.style.cssText='width:50px;height:50px;object-fit:contain;display:block;border-radius:0;background:#fff';
    box.replaceChildren(img);
  }
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',apply,{once:true}); else apply();
  new MutationObserver(apply).observe(document.documentElement,{childList:true,subtree:true});
})();
