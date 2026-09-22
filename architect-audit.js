/* Pista de auditoría: sólo las acciones importantes, dichas con palabras de
   negocio —movimientos de stock, cobros y pagos, facturas, validaciones y
   accesos—, con quién y cuándo. Qué cuenta y quién lo ve lo decide el
   servidor (gama_audit_trail); el registro técnico fila a fila sigue en la
   base para quien lo necesite, pero ya no llena esta pantalla. */
(function(){'use strict';
const U=window.ArcUI,E=U.esc,$=id=>document.getElementById(id);
const T=s=>window.GamaI18n?.t?.(s)||s,tr=s=>`<span data-gi-live>${E(s)}</span>`;
const KINDS=[['','Todo'],['stock','Movimientos de stock'],['payment','Cobros y pagos'],['invoice','Facturas'],['validation','Validaciones'],['access','Accesos']];
const LIMIT=50,EXPORT_MAX=5000;
let filters={kind:'',from:'',to:'',actor:'',search:''},offset=0,request=0,people=null,typing=null;
const admin=()=>{try{return ['admin','administrador'].includes(JSON.parse(localStorage.getItem('gama_session_v1')||'{}').role)}catch(_){return false}};
const when=v=>v?new Date(v).toLocaleString(window.GamaI18n?.language==='en'?'en-GB':window.GamaI18n?.language==='fr'?'fr-FR':'es-EC',{dateStyle:'short',timeStyle:'short'}):'';
const qty=v=>(Number(v)>0?'+':'')+Number(v).toLocaleString(undefined,{maximumFractionDigits:3});
const figure=r=>r.amount!=null?window.GamaCurrency.format(r.amount):r.quantity!=null?qty(r.quantity):'—';
const rpc=f=>window.ArcData.rpc('gama_audit_trail',{p_filters:f});

async function staff(){
 if(people)return people;
 try{const r=await window.ArcData.all('profiles',{select:'id,full_name,email',order:'full_name'});people=(r.data||[]).map(p=>({id:p.id,name:p.full_name||p.email||p.id}))}catch(_){people=[]}
 return people;
}
async function mount(){
 const s=$('audit');if(!s||!admin())return;
 const list=await staff();if(!s.isConnected)return;
 U.render(s,window.GamaUI.header({title:'Auditoría',lead:'Stock, cobros y pagos, facturas, validaciones y accesos.',module:'audit'})
  +`<div class="arcPanel atPanel"><div class="gdfTabs" role="tablist" aria-label="${E(T('Tipo de acción'))}">${KINDS.map(([k,l])=>`<button type="button" role="tab" class="gdfTab" data-at-kind="${k}" aria-selected="${filters.kind===k}">${tr(l)}</button>`).join('')}</div>`
  +`<div class="atFilters"><label class="atSearch">${tr('Buscar')}<input id="atSearch" type="search" value="${E(filters.search)}" autocomplete="off"></label>`
  +`<label>${tr('Desde')}<input id="atFrom" type="date" value="${E(filters.from)}"></label><label>${tr('Hasta')}<input id="atTo" type="date" value="${E(filters.to)}"></label>`
  +`<label>${tr('Persona')}<select id="atActor"><option value="">${E(T('Todas'))}</option>${list.map(p=>`<option value="${E(p.id)}"${p.id===filters.actor?' selected':''}>${E(p.name)}</option>`).join('')}</select></label>`
  +`<button type="button" class="arcButton secondary" id="atExport">${tr('Exportar CSV')}</button></div>`
  +`<p class="gsHint" id="atStatus" role="status"></p><div id="atRows"></div>`
  +`<div class="arcToolbar atPager"><button type="button" class="arcButton secondary" id="atPrev">${tr('Anterior')}</button><span id="atPage"></span><button type="button" class="arcButton secondary" id="atNext">${tr('Siguiente')}</button></div></div>`);
 window.GamaUI.bindBack(s);
 const again=()=>{offset=0;load()};
 s.querySelectorAll('[data-at-kind]').forEach(b=>b.onclick=()=>{filters.kind=b.dataset.atKind;s.querySelectorAll('[data-at-kind]').forEach(x=>x.setAttribute('aria-selected',String(x===b)));again()});
 $('atSearch').oninput=e=>{clearTimeout(typing);typing=setTimeout(()=>{filters.search=e.target.value.trim();again()},300)};
 for(const [id,key] of [['atFrom','from'],['atTo','to'],['atActor','actor']])$(id).onchange=e=>{filters[key]=e.target.value;again()};
 $('atPrev').onclick=()=>{offset=Math.max(0,offset-LIMIT);load()};
 $('atNext').onclick=()=>{offset+=LIMIT;load()};
 $('atExport').onclick=()=>exportCsv().catch(e=>{$('atStatus').textContent=window.ArcErrors.message(e)});
 window.dispatchEvent(new CustomEvent('arc:module-rendered',{detail:{id:'audit'}}));
 await load();
}
async function load(){
 const token=++request,status=$('atStatus');if(!status)return;
 status.textContent=T('Cargando…');
 try{
  const r=await rpc({...filters,offset,limit:LIMIT});if(token!==request||!$('atRows'))return;
  const items=r.items||[];
  status.textContent=items.length?'':T('Ninguna acción coincide con el filtro.');
  U.render($('atRows'),items.length?U.table({className:'atTable',columns:[
   {label:T('Fecha'),value:x=>when(x.at)},
   {label:T('Acción'),html:x=>`<span class="atKind" data-kind="${E(x.kind)}">${tr(x.label)}</span>`},
   {label:T('Detalle'),value:x=>x.detail||''},
   {label:T('Referencia'),value:x=>x.reference||'—'},
   {label:T('Importe / cantidad'),numeric:true,value:figure},
   {label:T('Quién'),value:x=>x.actor||T('Sistema')}],items}):'');
  $('atPrev').disabled=offset===0;$('atNext').disabled=!r.has_more;
  $('atPage').textContent=items.length?`${offset+1}–${offset+items.length}`:'';
 }catch(e){if(token===request&&status.isConnected)status.textContent=window.ArcErrors.message(e)}
}
async function exportCsv(){
 await window.ArchitectAccessControls.requireAction('audit','export');
 const rows=[];for(let at=0;at<EXPORT_MAX;at+=200){const r=await rpc({...filters,offset:at,limit:200});rows.push(...(r.items||[]));if(!r.has_more)break}
 const cell=v=>'"'+String(v??'').replace(/"/g,'""')+'"';
 const csv=[[T('Fecha'),T('Tipo'),T('Acción'),T('Detalle'),T('Referencia'),T('Importe'),T('Cantidad'),T('Quién')].map(cell).join(';'),
  ...rows.map(x=>[x.at,T(KINDS.find(k=>k[0]===x.kind)?.[1]||x.kind),T(x.label),x.detail,x.reference,x.amount,x.quantity,x.actor].map(cell).join(';'))].join('\r\n');
 const url=URL.createObjectURL(new Blob(['﻿'+csv],{type:'text/csv;charset=utf-8'})),a=document.createElement('a');
 a.href=url;a.download='architect-auditoria.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),30000);
 $('atStatus').textContent=T('Exportación lista.');
}
window.addEventListener('arc:route-change',e=>{if(e.detail.id==='audit')mount()});
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;request++;people=null;const s=$('audit');if(s)s.replaceChildren()});
window.addEventListener('gama:language-change',()=>{if($('audit')?.classList.contains('active'))mount()});
window.ArchitectAudit={mount,load};
})();
