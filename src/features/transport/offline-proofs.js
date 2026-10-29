/* Device-local outbox, scoped to the authenticated account. The server is authoritative. */
(function(){'use strict';const U=window.ArcUI,E=U.esc,T=s=>window.GamaI18n?.t?.(s)||s,t=(es,fr,en)=>({fr,en}[window.GamaI18n?.locale?.slice(0,2)]||es);let pending=null,captures=Promise.resolve();
const ACTIVE='coco-tms-offline-actor',TTL=48*3600000;
const open=()=>new Promise((resolve,reject)=>{const r=indexedDB.open('architect-proof-outbox',2);r.onupgradeneeded=()=>{if(!r.result.objectStoreNames.contains('proofs'))r.result.createObjectStore('proofs',{keyPath:'request_key'});if(!r.result.objectStoreNames.contains('routes'))r.result.createObjectStore('routes',{keyPath:'actor_id'})};r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)});
async function rawTx(mode,fn,store='proofs'){const db=await open();try{return await new Promise((resolve,reject)=>{const transaction=db.transaction(store,mode),r=fn(transaction.objectStore(store));let result;r.onsuccess=()=>{result=r.result};transaction.oncomplete=()=>resolve(result);transaction.onerror=()=>reject(transaction.error);transaction.onabort=()=>reject(transaction.error)})}finally{db.close()}}
async function vault(){if(!window.CocoOfflineVault)await window.ArcLoadScript('coco-offline-vault.js');return window.CocoOfflineVault}
async function tx(mode,fn,store='proofs'){
 const op=fn({get:id=>({kind:'get',id}),getAll:()=>({kind:'all'}),put:value=>({kind:'put',value}),delete:id=>({kind:'delete',id})});
 const id=navigator.onLine?(await window.GamaCloud.getSession()).data?.session?.user?.id:localStorage.getItem(ACTIVE);
 if(!id)throw Error('AUTH_REQUIRED');const v=await vault();
 if(op.kind==='delete')return rawTx(mode,s=>s.delete(op.id),store);
 if(op.kind==='put'){if((op.value.actor||op.value.actor_id)!==id)throw Error('AUTH_CHANGED');const sealed=await v.seal(op.value,store);return rawTx(mode,s=>s.put(sealed),store)}
 // Read legacy values only for their owner, then migrate them before returning.
 const decode=async row=>{if(!row)return row;if((row.actor||row.actor_id)!==id)throw Error('AUTH_CHANGED');if(store==='routes'&&Date.now()>(row.expires_at||Date.parse(row.downloaded_at)+TTL)){await rawTx('readwrite',s=>s.delete(row.actor_id),store);return undefined}const value=await v.unseal(row,store,id);if(row.version!==1){const sealed=await v.seal(value,store);await rawTx('readwrite',s=>s.put(sealed),store)}return value};
 if(op.kind==='get')return decode(await rawTx('readonly',s=>s.get(op.id),store));
 const all=await rawTx('readonly',s=>s.getAll(),store),result=[];for(const row of all)if((row.actor||row.actor_id)===id){const value=await decode(row);if(value)result.push(value)}return result;
}
async function purgeRoutes(){const all=await rawTx('readonly',s=>s.getAll(),'routes');for(const row of all)await rawTx('readwrite',s=>s.delete(row.actor_id),'routes')}
async function beforeLogout(){const current=await window.GamaCloud.getSession();if(!current.data?.session?.user?.id){window.CocoOfflineVault?.lock();await purgeRoutes();return}await captures.catch(()=>{});const queue=await rows();if(queue.length&&!confirm(t('Hay pruebas pendientes cifradas. Se conservarán para tu próxima conexión. ¿Cerrar sesión?','Des preuves chiffrées sont en attente. Elles seront conservées pour votre prochaine connexion. Fermer la session ?','Encrypted proofs are pending. They will remain for your next online sign-in. Sign out?')))throw Error('LOGOUT_CANCELLED');await purgeRoutes();(await vault()).lock()}
async function cleanupExpired(){const all=await rawTx('readonly',s=>s.getAll(),'routes');for(const row of all)if(Date.now()>(row.expires_at||Date.parse(row.downloaded_at)+TTL))await rawTx('readwrite',s=>s.delete(row.actor_id),'routes')}
async function actor(){
 if(!navigator.onLine){const id=localStorage.getItem(ACTIVE);if(!id||!(await vault()).unlocked(id))throw Error('OFFLINE_UNLOCK_REQUIRED');const cache=id&&await tx('readonly',s=>s.get(id),'routes');if(cache&&Date.now()-Date.parse(cache.downloaded_at)<TTL)return id;throw Error('OFFLINE_ROUTE_EXPIRED')}
 const r=await window.GamaCloud.getSession();if(r.error)throw r.error;const id=r.data?.session?.user?.id;if(!id)throw Error('AUTH_REQUIRED');return id;
}
async function rows(){const id=await actor();return (await tx('readonly',s=>s.getAll())).filter(r=>r.actor===id).sort((a,b)=>a.created_at.localeCompare(b.created_at))}
async function cacheBundle(bundle){if(!bundle?.actor_id)throw Error('AUTH_REQUIRED');if(navigator.onLine&&await actor()!==bundle.actor_id)throw Error('AUTH_CHANGED');const old=await tx('readonly',s=>s.get(bundle.actor_id),'routes');if(old?.documents&&!bundle.documents){bundle.documents=old.documents;bundle.prepared_at=old.prepared_at;bundle.prepared_versions=old.prepared_versions;bundle.document_errors=old.document_errors;}await tx('readwrite',s=>s.put(bundle),'routes');localStorage.setItem(ACTIVE,bundle.actor_id);return bundle}
async function bundle(){
 if(navigator.onLine){await flush();return cacheBundle(await window.ArcData.rpc('gama_tms_execution',{p_action:'bundle',p_data:{}}))}
 const id=await actor(),saved=await tx('readonly',s=>s.get(id),'routes');if(!saved)throw Error('OFFLINE_ROUTE_REQUIRED');return {...saved,offline:true};
}
async function updateCached(id,context){if(await actor()!==id)throw Error('AUTH_CHANGED');const data=await tx('readonly',s=>s.get(id),'routes');if(!data)return;const item=data.deliveries.find(d=>d.id===context.delivery.id);if(item){Object.assign(item,context.delivery,{execution:context});await tx('readwrite',s=>s.put(data),'routes')}}
async function storeProofFile(id){const client=await window.GamaCloud.db();const result=await client.functions.invoke('tms-proof-files',{body:{proof_id:id}});if(result.error||result.data?.error)throw result.error||Error(result.data.error);return result.data}
async function flush(){if(!navigator.onLine)return [];if(pending)return pending;pending=(async()=>{const id=await actor(),queue=await rows(),errors=[],blocked=new Set();
 for(const item of queue){if(item.actor!==id||await actor()!==id)break;const delivery=item.payload.delivery_id;if(blocked.has(delivery))continue;
  try{const context=item.action?await window.ArcData.rpc('gama_tms_execution',{p_action:item.action,p_data:item.payload}):await window.ArcData.rpc('gama_tms_capture',{p_data:item.payload});
   if(item.action&&context?.delivery){await updateCached(id,context);const dependent=queue.find(j=>j.depends_on===item.request_key);if(dependent){dependent.payload.version=context.delivery.version;delete dependent.depends_on;await tx('readwrite',s=>s.put(dependent))}}
   if(item.action==='receive'&&context?.attempts){const attempt=context.attempts.find(a=>a.request_key===item.request_key);for(const proof of attempt?.proofs||[])storeProofFile(proof.id).catch(()=>{})}
   await tx('readwrite',s=>s.delete(item.request_key));window.dispatchEvent(new Event('gama:sales-change'));
  }catch(e){item.error=window.ArcErrors.message(e);item.error_code=e.message;errors.push(item);blocked.add(delivery);await tx('readwrite',s=>s.put(item))}
 }return errors})();try{return await pending}finally{pending=null;window.dispatchEvent(new Event('architect:proof-outbox-change'))}}
async function captureNow(payload,action=null){const id=await actor(),queue=await rows(),prior=queue.find(r=>r.action===action&&r.payload.delivery_id===payload.delivery_id&&JSON.stringify({...r.payload,request_key:undefined})===JSON.stringify({...payload,request_key:undefined}));let job=prior;
 if(!job){if(queue.length>=100)throw Error('Sincroniza las capturas pendientes antes de añadir otra.');const request_key=payload.request_key||crypto.randomUUID(),previous=queue.findLast(r=>r.payload.delivery_id===payload.delivery_id);job={request_key,actor:id,action,depends_on:previous?.request_key,created_at:new Date().toISOString(),payload:{...payload,request_key}};if(await actor()!==id)throw Error('AUTH_CHANGED');await tx('readwrite',s=>s.put(job))}
 if(navigator.onLine)await flush();else window.dispatchEvent(new Event('architect:proof-outbox-change'));
 const remaining=await rows();return {queued:remaining.some(r=>r.request_key===job.request_key),request_key:job.request_key};
}
function capture(payload,action=null){const task=captures.catch(()=>{}).then(()=>captureNow(payload,action));captures=task;return task}
const preparations=new Map();
async function prepare(data,{force=false}={}){
 if(!navigator.onLine)throw Error('Conéctate para descargar la ruta.');
 const id=await actor();if(data.actor_id!==id)throw Error('AUTH_CHANGED');
 if(preparations.has(id))return preparations.get(id);
 const job=(async()=>{
  const saved=await tx('readonly',s=>s.get(id),'routes');
  if(!force&&saved?.prepared_at&&Date.now()-Date.parse(saved.prepared_at)<15*60000&&JSON.stringify(saved.prepared_versions)===JSON.stringify(data.routes.map(r=>[r.id,r.version])))return saved;
  if(!('serviceWorker' in navigator))throw Error('Este navegador no permite preparar el modo sin conexión.');
  await navigator.serviceWorker.register('sw.js');const reg=await navigator.serviceWorker.ready;
  const urls=['tms-driver.html','architect-core.js','architect-assets.js','architect-tokens.css','architect-base.css','architect-components.css','coco-style-tms-module.css','coco-workspace.css','gama-supabase.js','gama-i18n.js','gama-i18n-server.js','gama-i18n-catalog.js','architect-offline-proofs.js','coco-offline-vault.js','gama-tms-execution.js','coco-tms-gps.js','gama-tms-driver-ui.js','gama-tms-driver.js','gama-tms-delivery-operations.js','gama-sri-documents.js','gama-pdf.js','gama-pdf-template.js','assets/vendor/jspdf-4.2.1.umd.min.js','assets/vendor/supabase-2.115.0.js'].map(f=>window.ArcAssets?.[f]||f);
  await new Promise((resolve,reject)=>{const channel=new MessageChannel(),timer=setTimeout(()=>{channel.port1.close();reject(Error('OFFLINE_CACHE_FAILED'))},30000);channel.port1.onmessage=e=>{clearTimeout(timer);channel.port1.close();e.data.ok?resolve():reject(Error(e.data.error||'OFFLINE_CACHE_FAILED'))};reg.active.postMessage({type:'COCO_PRECACHE_DRIVER',urls},[channel.port2])});
  const documents={},errors=[];
  for(const r of data.routes){try{
   const doc=await window.ArcData.rpc('gama_tms_dispatch',{p_action:'driver_documents',p_data:{route_id:r.id}});
   documents[r.id]={...doc,saved_at:new Date().toISOString()};
   if(doc.guide?.status==='authorized'){
    await window.ArcLoadScript('gama-sri-documents.js');const link=await window.GamaSriDocuments.edge('download',doc.guide.id,'06','ride'),response=await fetch(link.url,{credentials:'omit',cache:'no-store'});
    if(!response.ok)throw Error('DOCUMENT_DOWNLOAD_FAILED');const blob=await response.blob();if(blob.size>20*1024*1024||!blob.type.includes('pdf'))throw Error('DOCUMENT_DOWNLOAD_FAILED');documents[r.id].guide_blob=blob;
   }else errors.push((r.erp_reference||r.reference||r.id)+': '+(doc.guide?.status||'SRI pendiente'));
  }catch(e){errors.push((r.erp_reference||r.reference||r.id)+': '+e.message)}}
  if(await actor()!==id)throw Error('AUTH_CHANGED');
  const current=await tx('readonly',s=>s.get(id),'routes');
  const output={...current,documents,document_errors:errors,prepared_at:new Date().toISOString(),prepared_versions:data.routes.map(r=>[r.id,r.version])};await cacheBundle(output);await navigator.storage?.persist?.();return output;
 })();preparations.set(id,job);try{return await job}finally{preparations.delete(id)}
}
async function download(){return prepare(await bundle(),{force:true})}
async function documents(routeId){const id=await actor(),data=await tx('readonly',s=>s.get(id),'routes');return data?.documents?.[routeId]}
async function guide(routeId){const docs=await documents(routeId);if(docs?.guide_blob){const url=URL.createObjectURL(docs.guide_blob),a=document.createElement('a');a.href=url;a.download='guia-SRI-'+routeId+'.pdf';a.click();setTimeout(()=>URL.revokeObjectURL(url),30000);return}if(!navigator.onLine)throw Error('La guía autorizada no está descargada en este dispositivo.');await window.ArcLoadScript('gama-sri-documents.js');return window.GamaSriDocuments.guide(routeId)}
async function reviewConflict(job){
 if(!navigator.onLine)throw Error('Conéctate para comparar con el servidor.');
 const current=await window.ArcData.rpc('gama_tms_execution',{p_action:'context',p_data:{delivery_id:job.payload.delivery_id}});
 const dialog=U.dialog({title:'Revisar captura pendiente',saveLabel:'Aplicar a la versión actual',error:e=>window.CocoTmsExecution?.error(e)||window.ArcErrors.message(e),body:`<p data-gi=f504700398ad>La entrega cambió desde la captura. Compara los saldos antes de confirmar.</p>${U.table({columns:[{key:'name',label:'Producto'},{key:'remaining',label:'Saldo actual'},{label:'Capturado',value:l=>{const p=job.payload.lines?.find(x=>x.id===l.id);return p?`${p.accepted} ${T('aceptadas')} / ${p.refused} ${T('rechazadas')} / ${p.missing} ${T('faltantes')} / ${p.deferred} ${T('reprogramadas')}`:'—'}}],items:current.lines})}<p>${E(T('Estado actual'))}: ${E(T(current.delivery.status))} · ${E(job.payload.reason||'')}</p>`,onSave:async()=>{
  if(job.action==='receive'&&(job.payload.lines.some(l=>{const actual=current.lines.find(x=>x.id===l.id);return !actual||Number(actual.remaining)!==l.accepted+l.refused+l.missing+l.deferred})||current.lines.filter(l=>+l.remaining>0).length!==job.payload.lines.length))throw Error('Los saldos ya no coinciden. Conserva la captura y solicita revisión al despachador.');
  if(await actor()!==job.actor)throw Error('AUTH_CHANGED');
  job.payload.version=current.delivery.version;delete job.error;delete job.error_code;await tx('readwrite',s=>s.put(job));await flush();
 }});return dialog;
}
async function outbox(){try{const queue=await rows(),d=U.dialog({title:t('Pruebas pendientes en este dispositivo','Preuves en attente sur cet appareil','Pending proofs on this device'),saveLabel:t('Cerrar','Fermer','Close'),body:`<p>${t('Estas capturas aún no están confirmadas por el servidor. Consérvalas en este dispositivo hasta sincronizar.','Ces captures ne sont pas encore confirmées par le serveur. Conservez-les sur cet appareil jusqu’à leur synchronisation.','These captures are not yet confirmed by the server. Keep them on this device until synchronized.')}</p><button type=button class="arcButton primary" data-proof-retry>${t('Reintentar sincronización','Réessayer la synchronisation','Retry sync')}</button>${U.table({columns:[{key:'created_at',label:t('Fecha','Date','Date')},{label:t('Entrega','Livraison','Delivery'),value:r=>r.payload.reference||r.payload.delivery_id},{label:t('Tipo','Type','Type'),value:r=>r.action?T({receive:'Recepción',arrive:'Llegada',notes:'Notas'}[r.action]||r.action):r.payload.complete?t('Firma y entrega','Signature et réception','Signature and receipt'):t('Foto','Photo','Photo')},{label:t('Última respuesta','Dernière réponse','Last response'),value:r=>r.error_code?window.CocoTmsExecution?.error({message:r.error_code})||T(r.error):T(r.error||'')},{label:'',actions:true,html:r=>`<button type=button data-proof-review="${E(r.request_key)}">${t('Ver captura','Voir la capture','View capture')}</button>${r.error_code==='DELIVERY_STALE'?`<button type=button data-proof-conflict="${E(r.request_key)}">${E(T('Revisar conflicto'))}</button>`:''}` }],items:queue})}`,onSave:async()=>{}});d.dataset.proofOutbox='';d.dataset.giIgnore='';d.querySelectorAll('[data-proof-conflict]').forEach(b=>b.onclick=()=>reviewConflict(queue.find(j=>j.request_key===b.dataset.proofConflict)).catch(e=>d.querySelector('[role=alert]').textContent=window.ArcErrors.message(e)));d.querySelector('[data-proof-retry]').onclick=async e=>{e.target.disabled=true;try{await flush();d.close();await outbox()}catch(error){d.querySelector('[role=alert]').textContent=window.ArcErrors.message(error);e.target.disabled=false}};d.querySelectorAll('[data-proof-review]').forEach(b=>b.onclick=()=>{const job=queue.find(r=>r.request_key===b.dataset.proofReview);const v=U.dialog({title:t('Captura conservada','Capture conservée','Retained capture'),saveLabel:t('Cerrar','Fermer','Close'),body:`<p>${E(job.payload.reference||job.payload.delivery_id)} · ${E(job.payload.occurred_at||job.payload.captured_at)}</p>${job.payload.photo?`<img alt="${E(T('Foto'))}" style="max-width:100%" src="${E(job.payload.photo)}">`:''}${job.payload.signature?`<img alt="${E(T('Firma'))}" style="max-width:100%" src="${E(job.payload.signature)}">`:''}`,onSave:async()=>{}});v.dataset.proofOutbox=''})}catch(e){alert(window.ArcErrors.message(e))}}
window.ArchitectOfflineProofs={capture,flush,rows,open:outbox,bundle,cacheBundle,updateCached,download,prepare,documents,guide,actor,beforeLogout};window.addEventListener('online',()=>flush().catch(()=>{}));window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='SIGNED_OUT'){localStorage.removeItem(ACTIVE);window.CocoOfflineVault?.lock();purgeRoutes().catch(()=>{});document.querySelectorAll('[data-proof-outbox]').forEach(d=>{d.close();d.remove()});window.dispatchEvent(new Event('coco:offline-locked'))}else if(e.detail?.session?.user?.id&&localStorage.getItem(ACTIVE)!==e.detail.session.user.id){localStorage.removeItem(ACTIVE);window.CocoOfflineVault?.lock();document.querySelectorAll('[data-proof-outbox]').forEach(d=>{d.close();d.remove()})}});
cleanupExpired().catch(()=>{});
})();
