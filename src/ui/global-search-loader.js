/* The global search engine loads only when the user opens search. */
(function(){'use strict';
const api=window.GamaGlobalSearch;if(!api?.__arcLazy)return;
let intent=0;
const label=()=>({fr:'Rechercher dans Coco ERP…',en:'Search Coco ERP…'}[window.GamaI18n?.language]||'Buscar en Coco ERP…');
api.mount=input=>{
 input.placeholder=label();input.setAttribute('aria-label',label());input.setAttribute('aria-haspopup','dialog');input.setAttribute('autocomplete','off');input.setAttribute('data-gi-ignore','');input.maxLength=160;input.dataset.gamaSearchTrigger='1';
 const open=()=>window.GamaGlobalSearch.open(input.value);
 input.onfocus=open;input.oninput=open;input.onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();open()}};
 const kbd=input.parentElement?.querySelector('kbd');if(kbd)kbd.textContent=/Mac|iPhone|iPad/.test(navigator.platform)?'⌘ K':'Ctrl K';
};
api.open=async(value='')=>{const token=++intent;try{const engine=await window.ArcLoad('global-search');if(token===intent)return engine.open(value)}catch(e){window.gamaToast?.(window.ArcErrors?.message(e)||e.message)}};
api.close=()=>{intent++};
const mount=()=>document.querySelectorAll('#gamaF2Buscar,#arcSearchInput').forEach(input=>window.GamaGlobalSearch.mount(input));mount();
window.addEventListener('gama:language-change',()=>{if(window.GamaGlobalSearch.__arcLazy)mount()});
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event!=='TOKEN_REFRESHED')intent++});
window.addEventListener('gama:modules-change',()=>intent++);
document.addEventListener('keydown',e=>{if(window.GamaGlobalSearch.__arcLazy&&(e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='k'&&!e.altKey){e.preventDefault();api.open()}});
})();
