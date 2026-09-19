/* GAMA — local, opt-in UI localisation. Business values and form values are never translated.
   Static labels are marked at source; dynamic presentation nodes opt in with data-gi-live.
   No network translator, prototype patches, HTML replacement or screen re-rendering. */
(function(){
'use strict';
if(window.GamaI18n)return;
const KEY='gama_language_v1',languages=['es','fr','en'],catalog=window.GamaI18nCatalog||{};
const bySource=new Map(Object.entries(catalog).map(([key,row])=>[row[0],{key,row}]));
let language='es';try{const saved=localStorage.getItem(KEY);if(languages.includes(saved))language=saved}catch(_){}
const normalize=s=>String(s??'').replace(/\s+/g,' ').trim();
const escapeRE=s=>s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
const patterns=[...bySource.values()].filter(x=>/\{\d+\}/.test(x.row[0])).map(x=>({...x,re:new RegExp('^'+x.row[0].split(/(\{\d+\})/).map(s=>/^\{\d+\}$/.test(s)?'([\\d.,\\s]+)':escapeRE(s)).join('')+'$')}));
const prefixes=[...bySource.values()].filter(x=>x.row[0].length>5&&!x.row[0].includes('{')).sort((a,b)=>b.row[0].length-a.row[0].length);
function translated(row){return row[languages.indexOf(language)]}
function t(value){
 const text=String(value??''),clean=normalize(text);if(language==='es')return text;
 let result=bySource.get(clean);if(result)return (text.match(/^\s*/)?.[0]||'')+translated(result.row)+(text.match(/\s*$/)?.[0]||'');
 const parts=clean.match(/^([^\p{L}\p{N}]*)(.*?)([\s:·*….!?—]*)$/u);
 if(parts){result=bySource.get(parts[2]+parts[3]);if(result)return parts[1]+translated(result.row);result=bySource.get(parts[2]);if(result)return parts[1]+translated(result.row)+parts[3]}
 const counted=clean.match(/^(.*?) (\([\d.,]+\))$/);if(counted&&bySource.has(counted[1]))return t(counted[1])+' '+counted[2];
 if(parts&&parts[1]){const body=parts[2]+parts[3],next=t(body);if(next!==body)return parts[1]+next}
 for(const p of patterns){const m=p.re.exec(clean);if(m)return translated(p.row).replace(/\{(\d+)\}/g,(_,i)=>m[Number(i)+1])}
 for(const p of prefixes){for(const delimiter of [': ',' : ',' · ']){const start=p.row[0]+delimiter;if(clean.startsWith(start)){const rest=clean.slice(start.length);return translated(p.row)+delimiter+(/^No se pudo/.test(p.row[0])?t(rest):rest)}}}
 return text;
}
const textState=new WeakMap(),attributeState=new WeakMap();
function replaceText(node,source){
 const next=t(source);textState.set(node,{source,last:next});if(node.nodeValue!==next)node.nodeValue=next;
}
function localize(el){
 if(!el||el.nodeType!==1||el.closest('[translate="no"], [data-gi-ignore],script,style,textarea,[contenteditable="true"]'))return;
 const ids=(el.getAttribute('data-gi')||'').split(' '),live=el.hasAttribute('data-gi-live');
 const known=ids.map(id=>catalog[id]).filter(Boolean);
 if(live||known.length){
  // An option without an explicit value otherwise changes submitted data with its label.
  if(el.tagName==='OPTION'&&!el.hasAttribute('value'))el.setAttribute('value',el.value);
  for(const node of el.childNodes){if(node.nodeType!==3)continue;
   const previous=textState.get(node),current=node.nodeValue;
   const source=previous&&current===previous.last?previous.source:current;
   if(live||known.some(row=>row[0]===normalize(source)))replaceText(node,source);
  }
 }
 for(const attr of ['placeholder','title','aria-label']){
  const marker=el.getAttribute('data-gi-'+attr),row=catalog[marker];if(!row&&marker!=='live')continue;
  let states=attributeState.get(el);if(!states){states={};attributeState.set(el,states)}
  const old=states[attr],value=el.getAttribute(attr),source=old&&old.last===value?old.source:value;
  if(row&&normalize(source)!==row[0])continue;
  const next=t(source);states[attr]={source,last:next};if(value!==next)el.setAttribute(attr,next);
 }
}
const selector='[data-gi],[data-gi-live],[data-gi-placeholder],[data-gi-title],[data-gi-aria-label]';
// These are presentation-only hosts. Do not add business-data containers here.
const liveSelectors=[
 ...['crmLeadFiltro','crmLStatus','crmLPriority','crmCCat','crmATipo','crmAKind','crmAAncla','crmAStatus','crmAPri','crmKFiltro','crmKTipo','crmKRol','crmOTipo','crmOPri'].map(id=>'#'+id+' option'),
 '.gamaF2Title','.gamaF2Section','#mainmenu > h2','#mainmenu > p','#gamaF2Vacio',
 '.gamaSideGroup','.gamaSideLink > span','.aclRole',
 '.gamaStdText h2','.gamaStdText h1','.gamaStdText p','.gamaStdKicker',
 '.gsBadge','.gqBadge','.crmEstado','.tmsBadge','.gamaPagerInfo',
 '.goKpi > span','.goKpi > small','.gamaToastTexto',
 '#gamaF2Buscar','#aclLogout','#gamaCloudAdminBtn','#gamaCloudLoginBtn',
 '.tmsTabs button','.gsTabs button','.crmTabs button','.hrTabs button','.gamaArcTabs button',
 '#ccCount','#cuCount','#giaCount','#crCount','.hrTabs button','.hrCard > h3','#giCopyStatus', '#gqMessage','#gsMessage','#gsFormError','#glMessage',
 '#crmMsg','#hrMsg','#cfgMsg','#gp14Msg','#gp14DetailMsg','#supMsg',
 '#gamaPhoneScanner .status','#gamaPhoneScanner .help','#gamaPhoneScanner .retry',
 '.gsDialog h2','.gsError','[role="alert"]','#cuStatus','#ccStatus','.gamaFindHint'
].join(',');
function prepare(root){
 if(root.nodeType!==1)return;
 const nodes=[...(root.matches(liveSelectors)?[root]:[]),...root.querySelectorAll(liveSelectors)];
 for(const el of nodes)if(!el.hasAttribute('data-gi-live'))el.setAttribute('data-gi-live','');
 for(const el of root.querySelectorAll('.gamaFindBox'))for(const attr of ['placeholder','aria-label'])el.setAttribute('data-gi-'+attr,'live');
 // Dynamic search field is created by the menu using DOM properties.
 const search=document.getElementById('gamaF2Buscar');if(search){
  for(const [attr,source] of [['placeholder','Buscar un módulo…'],['aria-label','Buscar un módulo']]){
   const key=bySource.get(source)?.key;if(key)search.setAttribute('data-gi-'+attr,key);
  }
 }
}
function scan(root){
 if(!root||root.nodeType!==1)return;prepare(root);localize(root);root.querySelectorAll(selector).forEach(localize);
}
let observer,scheduled=false;const pending=new Set();
function flush(){scheduled=false;const roots=[...pending];pending.clear();for(const root of roots)if(root.isConnected)scan(root);mount()}
function queue(root){if(root?.nodeType!==1)return;pending.add(root);if(!scheduled){scheduled=true;queueMicrotask(flush)}}
const flags={
 fr:'<path fill="#fff" d="M0 0h30v20H0z"/><path fill="#002654" d="M0 0h10v20H0z"/><path fill="#ed2939" d="M20 0h10v20H20z"/>',
 en:'<path fill="#012169" d="M0 0h30v20H0z"/><path stroke="#fff" stroke-width="5" d="m0 0 30 20M30 0 0 20"/><path stroke="#c8102e" stroke-width="2" d="m0 0 30 20M30 0 0 20"/><path stroke="#fff" stroke-width="8" d="M15 0v20M0 10h30"/><path stroke="#c8102e" stroke-width="4" d="M15 0v20M0 10h30"/>',
 es:'<path fill="#aa151b" d="M0 0h30v20H0z"/><path fill="#f1bf00" d="M0 5h30v10H0z"/>'
};
function mount(){
 const host=document.querySelector('#gamaCloudLogin .box')||document.getElementById('gamaSettingsLanguage');if(!host)return;
 let bar=document.getElementById('gamaLanguagePicker');if(!bar){
  bar=document.createElement('div');bar.id='gamaLanguagePicker';bar.setAttribute('role','group');bar.setAttribute('aria-label','Language / Langue / Idioma');bar.setAttribute('translate','no');
  for(const [code,flag,label] of [['fr','🇫🇷','Français'],['en','🇬🇧','English'],['es','🇪🇸','Español']]){
   const b=document.createElement('button');b.type='button';b.dataset.language=code;b.lang=code;b.title=label;b.setAttribute('aria-label',label);b.innerHTML='<svg viewBox="0 0 30 20" width="30" height="20" aria-hidden="true" focusable="false">'+flags[code]+'</svg><span>'+label+'</span>';b.onclick=()=>setLanguage(code);bar.appendChild(b);
  }host.appendChild(bar);
 }
 if(bar.parentElement!==host)host.appendChild(bar);
 for(const b of bar.children){const selected=b.dataset.language===language;if(b.getAttribute('aria-pressed')!==String(selected))b.setAttribute('aria-pressed',String(selected))}
}
function setLanguage(code){
 if(!languages.includes(code))return false;
 language=code;try{localStorage.setItem(KEY,code)}catch(_){}
 document.documentElement.lang=code;scan(document.body);mount();
 window.dispatchEvent(new CustomEvent('gama:language-change',{detail:{language:code}}));
 return true;
}
function boot(){
 document.documentElement.lang=language;
 const s=document.createElement('style');s.id='gamaLanguageCss';
 document.head.appendChild(s);scan(document.body);mount();
 observer=new MutationObserver(records=>{for(const r of records){
  if(r.type==='childList'){if(r.removedNodes.length)queue(r.target);for(const n of r.addedNodes)queue(n.nodeType===1?n:n.parentElement)}
  else queue(r.target.nodeType===3?r.target.parentElement:r.target);
 }});
 observer.observe(document.body,{childList:true,characterData:true,subtree:true,attributes:true,attributeFilter:['placeholder','title','aria-label']});
 window.addEventListener('storage',e=>{if(e.key===KEY&&languages.includes(e.newValue)&&e.newValue!==language)setLanguage(e.newValue)});
}
// Dialog messages use the same reviewed catalogue; typed defaults and answers stay untouched.
for(const name of ['confirm','prompt']){const native=window[name]?.bind(window);if(native)window[name]=(message,...args)=>native(t(message),...args)}
window.GamaI18n={t,setLanguage,scan,mount,get language(){return language},get locale(){return {es:'es-EC',fr:'fr-FR',en:'en-GB'}[language]}};
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
