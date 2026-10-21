/* One shared panel outside the business DOM: refreshing a grid cannot erase it. */
(function(){'use strict';
let session=0,host=null,follow=null;const dialogs=new WeakSet();
const legacy=new Set(['sales-orders','quotes','gamaPurchasesV14','tms','mainmenu']);
function clear(){session++;follow?.dispose();follow=null;host?.remove();host=null;document.querySelector('.arcContent')?.classList.remove('cocoHasModuleHistory')}
async function open(id,root){
 clear();if(!root&&legacy.has(id)||!window.ArcModules?.get(id)||!window.gamaAccessAllowed?.(id))return;
 const token=session;
 try{
  await window.ArcLoadScript('coco-order-followup.js');
  if(token!==session||!window.gamaAccessAllowed?.(id)||root&&!root.isConnected)return;
  const target=root||document.querySelector('.arcContent');if(!target)return;
  const inline=!root&&id==='assistant-ia';
  host=document.createElement(inline?'div':'aside');host.className=root?'cocoSettingsHistory':inline?'cocoGlobalHistory cocoAgentHistory':'cocoGlobalHistory';host.dataset.historyModule=id;target.append(host);
  if(!root&&!inline)target.classList.add('cocoHasModuleHistory');
  const mounted=await window.CocoFollowup.mount(host,{kind:'module',module_id:id},{inline});
  if(token!==session){mounted?.dispose();return}follow=mounted;
 }catch(e){if(token===session&&host){const b=document.createElement('button');b.type='button';b.className='arcButton secondary';b.textContent=window.GamaI18n?.t?.('Reintentar')||'Reintentar';b.onclick=()=>open(id,root);host.replaceChildren(b)}}
}
window.addEventListener('arc:route-leave',clear);
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event!=='TOKEN_REFRESHED')clear()});
window.addEventListener('coco:settings-history',e=>{
 const root=e.detail?.root,dialog=root?.closest('dialog');
 if(root){open(e.detail.id,root);if(dialog&&!dialogs.has(dialog)){dialogs.add(dialog);dialog.addEventListener('close',()=>open(window.ArcRouter.current),{once:true})}}
});
window.CocoModuleHistory={open};
})();
