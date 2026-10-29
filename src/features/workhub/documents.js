/* Channel-scoped CRDT editor. Only the owned validator creates text checkpoints.
   Unsaved states stay in this tab's memory and are erased on account changes. */
(function(){'use strict';
 const U=window.ArcUI,E=U.esc,Y=window.CocoCRDT,$=id=>document.getElementById(id);
 const words={
  fr:{content:'Texte du document',save:'Enregistrer',saved:'Toutes les modifications sont enregistrées.',dirty:'Modifications locales non enregistrées.',saving:'Enregistrement…',retry:'Réessayer',export:'Exporter le texte',versions:'Versions enregistrées',emptyVersions:'Aucune version enregistrée.',version:'Version',close:'Fermer',back:'Retour aux documents',rename:'Renommer',name:'Titre',archive:'Archiver',restore:'Réactiver',archived:'Document archivé : lecture seule.',archiveAsk:'Archiver ce document ? Les versions et les liens sont conservés.',restoreAsk:'Réactiver ce document pour reprendre les modifications ?',confirm:'Confirmer',error:'L’enregistrement a échoué. Le texte reste dans cet onglet ; réessayez ou exportez-le.',denied:'Ce document n’est plus accessible avec vos droits.',large:'Ce document dépasse la taille prise en charge. Exportez le texte et créez un nouveau document.',intro:'Document partagé avec les membres du canal. Le texte se synchronise lorsque cet écran reste ouvert.',loading:'Chargement du document…',unsaved:'Des modifications ne sont pas encore enregistrées.',older:'Versions précédentes',next:'Suivantes',preview:'Consulter',latest:'Dernière modification',versionText:'Texte de la version enregistrée',copyHint:'Pour récupérer un passage, consultez une version puis copiez le texte voulu dans le document actuel.'},
  es:{content:'Texto del documento',save:'Guardar',saved:'Todos los cambios están guardados.',dirty:'Cambios locales sin guardar.',saving:'Guardando…',retry:'Reintentar',export:'Exportar texto',versions:'Versiones guardadas',emptyVersions:'No hay versiones guardadas.',version:'Versión',close:'Cerrar',back:'Volver a documentos',rename:'Renombrar',name:'Título',archive:'Archivar',restore:'Reactivar',archived:'Documento archivado: solo lectura.',archiveAsk:'¿Archivar este documento? Se conservan las versiones y los vínculos.',restoreAsk:'¿Reactivar este documento para seguir editando?',confirm:'Confirmar',error:'No se pudo guardar. El texto sigue en esta pestaña; reintenta o expórtalo.',denied:'Este documento ya no está disponible con tus permisos.',large:'El documento supera el tamaño admitido. Exporta el texto y crea un documento nuevo.',intro:'Documento compartido con los miembros del canal. El texto se sincroniza mientras esta pantalla permanece abierta.',loading:'Cargando documento…',unsaved:'Todavía hay cambios sin guardar.',older:'Versiones anteriores',next:'Siguientes',preview:'Consultar',latest:'Último cambio',versionText:'Texto de la versión guardada',copyHint:'Para recuperar un fragmento, consulta una versión y copia el texto al documento actual.'},
  en:{content:'Document text',save:'Save',saved:'All changes are saved.',dirty:'Unsaved local changes.',saving:'Saving…',retry:'Retry',export:'Export text',versions:'Saved versions',emptyVersions:'No saved versions.',version:'Version',close:'Close',back:'Back to documents',rename:'Rename',name:'Title',archive:'Archive',restore:'Reactivate',archived:'Archived document: read only.',archiveAsk:'Archive this document? Versions and links will be kept.',restoreAsk:'Reactivate this document to continue editing?',confirm:'Confirm',error:'Could not save. Your text remains in this tab; retry or export it.',denied:'This document is no longer available with your permissions.',large:'The document exceeds the supported size. Export the text and create another document.',intro:'Shared with channel members. Text synchronizes while this screen stays open.',loading:'Loading document…',unsaved:'Some changes have not been saved.',older:'Earlier versions',next:'Next',preview:'View',latest:'Last change',versionText:'Saved version text',copyHint:'To recover a passage, view a version and copy the text you need into the current document.'}
 };
 const t=k=>(words[window.GamaI18n?.language]||words.es)[k]||k;
 const allowed=()=>!!window.gamaAccessAllowed?.('workhub')&&window.GamaModules?.enabled('workhub')!==false;
 const button=(key,attrs='',primary=false)=>U.button({label:t(key),variant:primary?'primary':'secondary',attrs});
 const encode=bytes=>{let s='';for(let i=0;i<bytes.length;i+=8192)s+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(s);};
 const decode=s=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
 const drafts=new Map();let epoch=0,session=null;
 const valid=s=>session===s&&s.epoch===epoch&&allowed()&&s.isCurrent()&&!!$('workhub')?.classList.contains('active');
 const date=v=>new Date(v).toLocaleString(window.GamaI18n?.locale||'es-EC',{dateStyle:'medium',timeStyle:'short'});
 const rpc=(action,data)=>window.ArcData.rpc('coco_workhub_documents',{p_action:action,p_data:data});
 function status(s,error=s.error){if(!valid(s))return;const host=$('whDocStatus');if(!host)return;host.textContent=error||(s.meta.archived?t('archived')+(s.dirty?' '+t('dirty'):''):t(s.busy?'saving':s.dirty?'dirty':'saved'));host.setAttribute('role',error?'alert':'status');$('whDocSave').disabled=s.busy||!s.dirty||s.meta.archived;$('whDocArchive').disabled=s.busy||!s.meta.archived&&s.dirty;}
 function pause({erase=false}={}){
  const s=session;session=null;epoch++;
  if(s){clearTimeout(s.saveTimer);clearTimeout(s.pollTimer);s.controller?.abort();if(!erase&&s.doc&&s.dirty)drafts.set(s.id,{state:encode(Y.encodeStateAsUpdate(s.doc)),batch:s.batch,edit:s.edit});s.doc?.destroy();}
  if(erase)drafts.clear();$('workhub')?.classList.remove('whEditingDocument');if($('whDetail'))$('whDetail').hidden=false;
  document.querySelectorAll('[data-workhub-document-dialog]').forEach(d=>d.close());
 }
 function revoked(s){if(!valid(s))return;drafts.delete(s.id);pause({erase:true});U.render($('whList'),'<p class="whEmpty" role="alert">'+E(t('denied'))+'</p>');$('whDetail')?.replaceChildren();}
 function handle(s,e){if(!valid(s))return;if(/FORBIDDEN|AUTH_|MODULE_DISABLED|AUTH_CHANGED/.test(e.message||''))return revoked(s);s.error=/TOO_LARGE|PAYLOAD_TOO_LARGE/.test(e.message||'')?t('large'):t('error');status(s,s.error);}
 function apply(s,record){
  const input=$('whDocText'),focus=document.activeElement===input,text=s.doc.getText('body');
  const start=Y.createRelativePositionFromTypeIndex(text,Math.min(input?.selectionStart||0,text.length)),end=Y.createRelativePositionFromTypeIndex(text,Math.min(input?.selectionEnd||0,text.length));
  if(record.state)Y.applyUpdate(s.doc,decode(record.state),'remote');
  s.meta=record;
  if(input){const value=text.toString();if(input.value!==value)input.value=value;input.readOnly=record.archived;if(focus){const a=Y.createAbsolutePositionFromRelativePosition(start,s.doc),b=Y.createAbsolutePositionFromRelativePosition(end,s.doc);input.setSelectionRange(a?.index||0,b?.index||0);}}
  $('whDocHeading').textContent=record.title;$('whDocVersion').textContent=t('version')+' '+record.version+' · '+t('latest')+' '+date(record.updated_at);status(s);
 }
 function edit(s,value){
  const text=s.doc.getText('body'),old=text.toString();if(old===value)return;
  let start=0,suffix=0;while(start<old.length&&start<value.length&&old[start]===value[start])start++;
  while(suffix<old.length-start&&suffix<value.length-start&&old[old.length-1-suffix]===value[value.length-1-suffix])suffix++;
  s.doc.transact(()=>{if(old.length-start-suffix)text.delete(start,old.length-start-suffix);if(value.length-start-suffix)text.insert(start,value.slice(start,value.length-suffix));},'local');
 }
 async function send(s,batch){
  await window.GamaCloudReady;const r=await window.GamaCloud.getSession(),token=r.data?.session?.access_token;
  if(!token||!valid(s))throw Error('AUTH_REQUIRED');s.controller=new AbortController();
  const response=await fetch(window.GamaCloud.url+'/functions/v1/coco-workhub-documents',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({document_id:s.id,request_key:batch.key,update:batch.state}),signal:AbortSignal.any([s.controller.signal,AbortSignal.timeout(45000)])});
  const data=await response.json();if(!response.ok)throw Error(data.error||'WORKHUB_DOCUMENT_UNAVAILABLE');return data;
 }
 function schedule(s){clearTimeout(s.saveTimer);if(!valid(s)||s.meta.archived)return;s.firstDirty||=Date.now();s.saveTimer=setTimeout(()=>flush(s),Math.max(0,Math.min(1500,10000-(Date.now()-s.firstDirty))));}
 async function flush(s=session){
  if(!s||!valid(s)||s.busy||!s.dirty||s.meta.archived)return;
  clearTimeout(s.saveTimer);s.busy=true;s.error=null;s.batch||={key:crypto.randomUUID(),state:encode(Y.encodeStateAsUpdate(s.doc)),edit:s.edit};const batch=s.batch;status(s);
  try{const saved=await send(s,batch);if(!valid(s))return;apply(s,saved);s.batch=null;s.dirty=s.edit>batch.edit;s.firstDirty=s.dirty?Date.now():0;if(!s.dirty)drafts.delete(s.id);if(s.dirty)schedule(s);}
  catch(e){handle(s,e);}finally{if(valid(s)){s.busy=false;status(s,s.error||undefined);}}
 }
 function watch(s){clearTimeout(s.pollTimer);if(!valid(s))return;s.pollTimer=setTimeout(async()=>{try{
  if(document.visibilityState==='visible'&&!s.busy){const current=await rpc('read',{id:s.id});if(!valid(s))return;if(current.version!==s.meta.version||current.archived!==s.meta.archived)apply(s,current);}
 }catch(e){handle(s,e);}finally{if(valid(s))watch(s);}},2000);}
 function exportText(text,title){const a=document.createElement('a'),url=URL.createObjectURL(new Blob([text],{type:'text/markdown;charset=utf-8'}));a.href=url;a.download=(title.replace(/[^\p{L}\p{N} _-]/gu,'').slice(0,100)||'document')+'.md';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
 function dialog(options){const d=U.dialog({...options,error:e=>/FORBIDDEN/.test(e.message||'')?t('denied'):t('error')});d.dataset.workhubDocumentDialog='';d.dataset.giIgnore='';return d;}
 async function versions(s,offset=0){try{const r=await rpc('versions',{id:s.id,limit:10,offset});if(!valid(s))return;const d=dialog({title:t('versions'),saveLabel:t('close'),body:`<p>${E(t('copyHint'))}</p><div class="whDocVersions">${r.rows.length?r.rows.map((v,i)=>`<button class="arcButton secondary" type="button" data-wh-version="${i}">${E(t('version')+' '+v.version+' · '+date(v.created_at))}</button>`).join(''):`<p>${E(t('emptyVersions'))}</p>`}</div><div class="whActions">${offset?button('older','data-wh-version-prev'):''}${r.rows.length===10?button('next','data-wh-version-next'):''}</div><label>${E(t('versionText'))}<textarea rows="12" readonly data-wh-version-text></textarea></label>`,onSave:async()=>{}});
  const show=i=>d.querySelector('[data-wh-version-text]').value=r.rows[i]?.body||'';show(0);d.querySelectorAll('[data-wh-version]').forEach(b=>b.onclick=()=>show(Number(b.dataset.whVersion)));
  d.querySelector('[data-wh-version-prev]')?.addEventListener('click',()=>{d.close();versions(s,offset-10)});d.querySelector('[data-wh-version-next]')?.addEventListener('click',()=>{d.close();versions(s,offset+10)});
 }catch(e){handle(s,e);}}
 function rename(s){dialog({title:t('rename'),saveLabel:t('save'),body:U.field({key:'title',label:t('name'),value:s.meta.title,required:true,maxLength:200}),onSave:async d=>{const saved=await rpc('metadata',{id:s.id,version:s.meta.version,title:new FormData(d.querySelector('form')).get('title')});if(valid(s))apply(s,saved);}});}
 function archive(s){dialog({title:t(s.meta.archived?'restore':'archive'),saveLabel:t('confirm'),body:'<p>'+E(t(s.meta.archived?'restoreAsk':'archiveAsk'))+'</p>',onSave:async()=>{const saved=await rpc('metadata',{id:s.id,version:s.meta.version,archived:!s.meta.archived});if(valid(s)){apply(s,saved);$('whDocArchive').textContent=t(saved.archived?'restore':'archive');}}});}
 async function mount({id,onBack,isCurrent=()=>true}){
  if(!isCurrent())return;pause();if(!allowed())return;const s={id,epoch,doc:null,meta:{},dirty:false,busy:false,edit:0,batch:null,onBack,isCurrent};session=s;
  $('workhub').classList.add('whEditingDocument');$('whDetail').hidden=true;$('whControls').replaceChildren();$('whList').textContent=t('loading');
  try{const record=await rpc('read',{id});if(!valid(s))return;
   s.doc=new Y.Doc();s.doc.getText('body');if(record.state)Y.applyUpdate(s.doc,decode(record.state),'remote');const draft=drafts.get(id);
   if(draft){Y.applyUpdate(s.doc,decode(draft.state),'remote');s.dirty=true;s.batch=draft.batch;s.edit=draft.edit;}
   s.meta=record;
   U.render($('whList'),`<div class="whDocEditor"><div class="whActions">${button('back','id="whDocBack"')}${button('save','id="whDocSave"',true)}${button('export','id="whDocExport"')}${button('versions','id="whDocVersions"')}${button('rename','id="whDocRename"')}${button(record.archived?'restore':'archive','id="whDocArchive"')}</div><h2 id="whDocHeading"></h2><p class="whHint">${E(t('intro'))}</p><p id="whDocVersion" class="whHint"></p><p id="whDocStatus" role="status"></p><label>${E(t('content'))}<textarea id="whDocText" rows="20" spellcheck="true" maxlength="100000"></textarea></label></div>`);
   $('whDocText').value=s.doc.getText('body').toString();apply(s,record);
   s.doc.on('update',(_update,origin)=>{if(origin!=='local'||!valid(s))return;s.edit++;s.dirty=true;s.error=null;status(s);schedule(s);});
   $('whDocText').oninput=()=>edit(s,$('whDocText').value);$('whDocSave').onclick=()=>flush(s);$('whDocExport').onclick=()=>exportText(s.doc.getText('body').toString(),s.meta.title);
   $('whDocVersions').onclick=()=>versions(s);$('whDocRename').onclick=()=>rename(s);$('whDocArchive').onclick=()=>archive(s);$('whDocBack').onclick=()=>{pause();onBack?.();};
   if(s.dirty&&!s.meta.archived)schedule(s);watch(s);
  }catch(e){if(valid(s)){if(/FORBIDDEN|AUTH_/.test(e.message||''))return revoked(s);$('whList').replaceChildren();const b=document.createElement('button');b.className='arcButton secondary';b.textContent=t('retry');b.onclick=()=>mount({id,onBack,isCurrent});$('whList').append(b);}}
 }
 function clear(){pause({erase:true});}
 window.addEventListener('beforeunload',e=>{if(session?.dirty||drafts.size){e.preventDefault();e.returnValue='';}});
 window.addEventListener('arc:route-leave',e=>{if(e.detail?.id==='workhub')pause();});
 window.addEventListener('gama:auth-change',e=>{if(e.detail?.event!=='TOKEN_REFRESHED')clear();});
 window.addEventListener('gama:modules-change',()=>{if(!allowed())clear();});
 window.addEventListener('storage',e=>{if(e.key==='gama_session_v1')clear();});
 window.CocoWorkhubDocs={mount,pause,clear,active:()=>!!session,open:async id=>{await window.CocoWorkhub.open();return window.CocoWorkhub.openDocument(id);}};
})();
