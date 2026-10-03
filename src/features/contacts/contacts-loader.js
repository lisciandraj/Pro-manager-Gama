/* Preserve legacy contact routes while loading the workspace on demand. */
(function(){'use strict';
const load=()=>window.ArcLoadScript('gama-contacts-workspace.js');
window.GamaContacts=Object.fromEntries(['open','edit','refresh','create'].map(k=>[k,async(...args)=>{await load();return window.GamaContacts[k](...args)}]));
window.ArcRouter.onEnter('contacts',()=>{if(!document.getElementById('contacts')){const s=document.createElement('section');s.id='contacts';(document.querySelector('.wrap')||document.body).appendChild(s)}load().catch(e=>window.gamaToast?.(e.message))});
})();
