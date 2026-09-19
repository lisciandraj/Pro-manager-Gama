/* Personal module order: account-owned cloud storage, pointer and keyboard sorting. */
(function(){
'use strict';
const words={move:['Déplacer ce module','Move this module','Mover este módulo'],hint:['Glissez les tuiles pour placer vos favoris en premier. Au clavier : Alt + flèches.','Drag tiles to put your favorites first. Keyboard: Alt + arrows.','Arrastra las tarjetas para colocar tus favoritos primero. Teclado: Alt + flechas.'],saved:['Ordre enregistré','Order saved','Orden guardado'],saving:['Enregistrement…','Saving…','Guardando…'],error:['Ordre non synchronisé. Réessayez.','Order not synchronized. Try again.','Orden no sincronizado. Inténtalo de nuevo.'],retry:['Réessayer','Retry','Reintentar']};
const t=k=>words[k][{fr:0,en:1,es:2}[window.GamaI18n?.language||'es']??2];
let grid,user=null,order=[],epoch=0,revision=0,queue=Promise.resolve(),drag=null,blockClick=false,loading=null;
const cards=()=>grid?[...grid.querySelectorAll('.gamaF2Card')]:[];
const visible=()=>cards().filter(c=>c.getClientRects().length);
const key=()=>user?'architect_home_order_v1:'+user:null;
function cache(){try{if(key())localStorage.setItem(key(),JSON.stringify(order))}catch(_){}}
function apply(){if(!grid)return;const byId=new Map(cards().map(c=>[c.dataset.gamaModule,c]));for(const id of [...new Set(order)]){const c=byId.get(id);if(c){grid.append(c);byId.delete(id)}}for(const c of byId.values())grid.append(c);const empty=grid.querySelector('#gamaF2Vacio');if(empty)grid.append(empty)}
async function rpc(data={}){await window.GamaCloudReady;const c=await window.GamaCloud.db(),r=await window.ArcData.rawRpc('gama_home_order',data);if(r.error)throw r.error;if(!r.data?.user_id)throw Error('AUTH_REQUIRED');return r.data}
function status(kind){const el=document.getElementById('arcOrderStatus');if(!el)return;el.replaceChildren(document.createTextNode(t(kind)));if(kind==='error'){const b=document.createElement('button');b.type='button';b.className='ghost';b.textContent=t('retry');b.onclick=save;el.append(b)}}
async function load(){if(loading)return loading;const e=epoch,r=revision;loading=rpc().then(data=>{if(e!==epoch)return;user=data.user_id;if(r===revision){order=Array.isArray(data.module_order)?data.module_order:[];cache();apply()}return user}).catch(()=>null).finally(()=>{if(e===epoch)loading=null});return loading}
function save(){order=cards().map(c=>c.dataset.gamaModule);revision++;cache();status('saving');const snapshot=[...order],e=epoch,r=revision;queue=queue.catch(()=>{}).then(async()=>{if(e!==epoch)return;if(!user)await load();if(e!==epoch)return;try{if(!user)throw Error('AUTH_REQUIRED');await rpc({p_order:snapshot,p_user:user});if(e===epoch&&r===revision){cache();status('saved')}}catch(_){if(e===epoch&&r===revision)status('error')}})}
function target(x,y,source){const el=document.elementFromPoint(x,y)?.closest('.gamaF2Card');if(!el||el===source||el.parentNode!==grid)return;const b=el.getBoundingClientRect();const after=y>b.top+b.height*.7||(y>b.top+b.height*.3&&x>b.left+b.width/2);grid.insertBefore(source,after?el.nextSibling:el)}
function finish(cancel=false){if(!drag)return;const d=drag;drag=null;if(d.pointer!=null&&document.body.hasPointerCapture(d.pointer))document.body.releasePointerCapture(d.pointer);d.card.classList.remove('arcDragging');if(cancel){order=d.before;apply()}else if(d.moved)save();blockClick=d.moved;setTimeout(()=>blockClick=false,0)}
function mount(host){grid=host;const hint=document.createElement('p');hint.id='arcOrderHint';hint.className='arcOrderHint';hint.textContent=t('hint');const live=document.createElement('span');live.id='arcOrderStatus';live.setAttribute('role','status');hint.append(live);host.before(hint);
 for(const card of cards()){
  card.draggable=true;
  const handle=document.createElement('span');handle.className='arcDragHandle';handle.textContent='⠿';handle.title=t('move');handle.setAttribute('aria-hidden','true');card.append(handle);card.setAttribute('aria-describedby','arcOrderHint');
  card.addEventListener('click',e=>{if(blockClick||e.target.closest('.arcDragHandle')){e.preventDefault();e.stopImmediatePropagation()}},true);
  card.addEventListener('dragstart',e=>{drag={card,before:cards().map(c=>c.dataset.gamaModule),moved:false};card.classList.add('arcDragging');e.dataTransfer.effectAllowed='move';e.dataTransfer.setData('text/plain',card.dataset.gamaModule)});
  card.addEventListener('dragend',()=>finish(true));
  handle.addEventListener('pointerdown',e=>{if(e.button!==0)return;e.preventDefault();drag={card,before:cards().map(c=>c.dataset.gamaModule),moved:false,x:e.clientX,y:e.clientY,pointer:e.pointerId};document.body.setPointerCapture(e.pointerId)});
  card.addEventListener('keydown',e=>{if(e.key==='Escape'){finish(true);return}if(!e.altKey||!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key))return;e.preventDefault();const list=visible(),i=list.indexOf(card),delta=['ArrowLeft','ArrowUp'].includes(e.key)?-1:1,j=i+delta;if(j<0||j>=list.length)return;grid.insertBefore(card,delta>0?list[j].nextSibling:list[j]);card.focus();save()});
 }
 host.addEventListener('dragover',e=>{if(!drag)return;e.preventDefault();e.dataTransfer.dropEffect='move';drag.moved=true;target(e.clientX,e.clientY,drag.card)});
 host.addEventListener('drop',e=>{if(!drag)return;e.preventDefault();finish()});apply();load();
}
document.addEventListener('pointermove',e=>{if(!drag||drag.pointer!==e.pointerId)return;if(Math.hypot(e.clientX-drag.x,e.clientY-drag.y)<6&&!drag.moved)return;drag.moved=true;drag.card.classList.add('arcDragging');target(e.clientX,e.clientY,drag.card);if(e.clientY<100)window.scrollBy(0,-22);else if(e.clientY>innerHeight-70)window.scrollBy(0,22)});
document.addEventListener('pointerup',e=>{if(drag?.pointer===e.pointerId)finish()});
document.addEventListener('pointercancel',e=>{if(drag?.pointer===e.pointerId)finish(true)});
document.addEventListener('keydown',e=>{if(e.key==='Escape')finish(true)});
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;epoch++;revision++;user=null;order=[];loading=null;queue=Promise.resolve();finish(true);if(grid){const defaults=window.GamaMenu?.items||[];const ranks=['dashboard','assistant-ia','crm','quotes','sales-orders','tms','payments','returns','gamaPurchasesV14','suppliers','products','warehouses','projects','hr','knowledge','accounting','clients','settings'];order=[...defaults].sort((a,b)=>(ranks.indexOf(a[1])<0?100:ranks.indexOf(a[1]))-(ranks.indexOf(b[1])<0?100:ranks.indexOf(b[1]))).map(x=>x[1]);apply()}if(e.detail?.event!=='SIGNED_OUT')load()});
window.addEventListener('gama:language-change',()=>{const h=document.getElementById('arcOrderHint');if(h){h.firstChild.textContent=t('hint');document.getElementById('arcOrderStatus').replaceChildren()}for(const c of cards())c.querySelector('.arcDragHandle').title=t('move')});
window.addEventListener('gama:cloud-script-loaded',()=>load());
window.ArchitectHomeOrder={mount};
})();
