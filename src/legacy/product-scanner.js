(function(){
  function cleanup(){
    const section=document.getElementById("products");
    if(!section)return;
    const input=document.getElementById("pBarcode");
    const box=input?.closest(".scanner");
    const buttons=[...section.querySelectorAll("button")].filter(b=>/escane|scanner/i.test((b.textContent||"")));
    if(!buttons.length)return;
    const keep=(box&&[...box.querySelectorAll("button")].find(b=>/escane|scanner/i.test(b.textContent||"")))||buttons[0];
    buttons.forEach(b=>{if(b!==keep)b.remove()});
    keep.classList.add("gamaPhoneScanBtn");
    keep.type="button";
    if(!keep.dataset.gamaScannerBound){
      keep.dataset.gamaScannerBound="1";
      keep.addEventListener("click",function(e){e.preventDefault();e.stopImmediatePropagation();if(window.startGamaScan)window.startGamaScan("pBarcode");},true);
    }
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",cleanup,{once:true});else cleanup();
  for(const event of ['arc:route-change','arc:module-rendered'])window.addEventListener(event,e=>{if(e.detail?.id==='products')cleanup()});
})();
