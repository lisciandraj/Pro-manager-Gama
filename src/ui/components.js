import {escapeHtml as esc, translate as t, errorMessage, format} from '../domain/format.js';
let sequence=0;
const attr=(key,value)=>value==null || value===false?'':value===true?' '+key:' '+key+'="'+esc(value)+'"';
const attributes=values=>Object.entries(values).map(([key,value])=>attr(key,value)).join('');
/** `attrs` and `html` accept trusted module markup only, never raw database content. */
export function button({label='',variant='secondary',id,type='button',disabled=false,attrs='',className=''}={}) {
  if(!['primary','secondary','ghost','danger','success'].includes(variant))variant='secondary';
  return `<button${attributes({id,type,disabled})} class="arcButton ${variant} ${esc(className)}" ${attrs}>${esc(label)}</button>`;
}
export function field({id='arc-field-'+(++sequence),key,name=key,label='',type='text',value='',required=false,readOnly=false,disabled=false,min,max,step,maxLength,options=[],help='',error='',attrs='',className=''}={}) {
  const errorId=id+'-error',helpId=id+'-help';
  const props=attributes({id,name,required,readonly:readOnly,disabled,min,max,step,maxlength:maxLength,'aria-invalid':error?'true':null,'aria-describedby':error?errorId:help?helpId:null});
  let control;
  if(type==='select'||type==='multi') {
    const values=(Array.isArray(value)?value:[value]).map(String);
    control=`<select${props}${type==='multi'?' multiple':''} ${attrs}>${type==='select'?'<option value="">—</option>':''}${options.map(o=>`<option value="${esc(o.value ?? o.id)}"${values.includes(String(o.value ?? o.id))?' selected':''}>${esc(o.label ?? o.name)}</option>`).join('')}</select>`;
  }else if(type==='textarea')control=`<textarea${props} ${attrs}>${esc(value)}</textarea>`;
  else control=`<input${props} type="${esc(type)}"${type==='checkbox'?value?' checked':'':' value="'+esc(value)+'"'} ${attrs}>`;
  return `<label class="arcField ${esc(className)}" for="${esc(id)}"><span>${esc(t(label))}${required?' *':''}</span>${control}${help?`<small id="${esc(helpId)}">${esc(t(help))}</small>`:''}<small id="${esc(errorId)}" class="arcFieldError"${error?'':' hidden'}>${esc(t(error))}</small></label>`;
}
export function panel(html,{className='',id,accent}={}) {return `<div${attributes({id,'data-accent':accent})} class="arcPanel ${esc(className)}">${html}</div>`;}
export function toolbar(html,{className=''}={}) {return `<div class="arcToolbar ${esc(className)}">${html}</div>`;}
/** El emoji que abría algunos títulos —📦, 👥, 🚚— lo sustituye el icono del
 *  módulo, el mismo que lleva su tarjeta en el menú. Se quita aquí y no en cada
 *  módulo para que ninguno se quede a medias; el catálogo de traducción guarda
 *  sus entradas por el texto sin adorno, así que «📦 Productos» y «Productos»
 *  resuelven a la misma fila. */
const stripIcon=text=>{try{return String(text).replace(/^[^\p{L}\p{N}]+/u,'')||String(text);}catch(_){return String(text);}};

export function header({title='Módulo',lead='',module=''}={}) {
  return `<div class="gamaStdHeader arcPageHeader" data-gama-standard-header="1"><span class="gamaStdIcon" data-arc-icon-slot${module?' data-arc-module="'+esc(module)+'"':''} aria-hidden="true"></span><div class="gamaStdText"><div class="gamaStdKicker">COCO ERP</div><h2>${esc(stripIcon(title))}</h2>${lead?'<p>'+esc(lead)+'</p>':''}</div><div class="gamaStdActions">${button({label:t('← Volver al menú'),className:'gamaStdBack',attrs:'aria-label="'+esc(t('Volver al menú'))+'"'})}</div></div>`;
}

/** Pinta en la cabecera el icono del módulo, con su acento: el mismo dibujo y
 *  el mismo color que la tarjeta del menú, pedidos a la misma fuente. La
 *  sección que la contiene lleva el identificador del módulo —lo cumplen
 *  treinta y cinco de los treinta y siete—, así que basta con preguntárselo al
 *  registro; el `id` explícito gana cuando quien llama ya lo sabe. */
export function headerIcon(root,id='') {
  const scope=root && root.querySelectorAll?root:document;
  const slots=scope.querySelectorAll('.gamaStdIcon[data-arc-icon-slot]');
  if(!slots.length)return;
  const modules=globalThis.ArcModules, icons=globalThis.ArcUI?.icons;
  if(!modules||!icons)return;
  let pending=false;
  slots.forEach(slot=>{
    const section=slot.closest('section[id]');
    const key=slot.dataset.arcModule || id || SECTION_ALIAS[section?.id] || section?.id || '';
    if(!key){pending=true;return;}
    const definition=modules.get(key);
    const drawing=definition && icons[definition.icon];
    if(!drawing)return;
    slot.dataset.arcFam=definition.accent||'cyan';
    slot.innerHTML='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true">'+drawing+'</svg>';
    delete slot.dataset.arcIconSlot;
  });
  /* Una cabecera atada antes de colgarla de su sección todavía no sabe de qué
     módulo es: se reintenta cuando ya esté puesta. */
  if(pending && !headerIcon.retrying){headerIcon.retrying=true;
    setTimeout(()=>{headerIcon.retrying=false;headerIcon(document);},0);}
}

/** La única pantalla cuyo `id` no es el de su módulo. */
const SECTION_ALIAS={'gama-tms-section':'tms'};

export function badge(status,label=status,{className='',tone='neutral'}={}) {return `<span class="arcStatusBadge ${esc(className)}" data-s="${esc(status)}" data-tone="${esc(tone)}">${esc(t(label))}</span>`;}
export function kpi({label,value,help='',className=''}={}) {return `<div class="arcKpi ${esc(className)}"><span>${esc(label)}</span><strong>${esc(value ?? '—')}</strong>${help?'<small>'+esc(help)+'</small>':''}</div>`;}
export function form(fields,{id='arc-form-'+(++sequence),values={},submitLabel=t('Guardar')}={}) {
  return `<form id="${esc(id)}" class="arcForm"><div class="arcFormGrid">${fields.map(f=>field({...f,value:values[f.key] ?? ''})).join('')}</div><p class="arcFormError" role="alert"></p>${button({type:'submit',variant:'primary',label:submitLabel})}</form>`;
}
export function bindForm(el,onSubmit,{error=errorMessage,onSuccess}={}) {
  if(el.__arcForm)return el.__arcForm;
  let pending=false;
  const submit=async event=>{
    event.preventDefault();if(pending || !el.reportValidity())return;
    pending=true;el.setAttribute('aria-busy','true');
    const controls=[...el.querySelectorAll('button,input[type=submit]')], previous=controls.map(c=>c.disabled);
    controls.forEach(c=>c.disabled=true);
    const message=el.querySelector('[role=alert]');if(message)message.textContent='';
    try{await onSubmit(el,new FormData(el));await onSuccess?.();}
    catch(e){if(message){message.textContent=error(e);message.tabIndex=-1;message.focus();}else throw e;}
    finally{pending=false;el.removeAttribute('aria-busy');controls.forEach((c,i)=>c.disabled=previous[i]);}
  };
  el.addEventListener('submit',submit);
  const api={get pending(){return pending;},dispose(){el.removeEventListener('submit',submit);delete el.__arcForm;}};
  el.__arcForm=api;return api;
}
export function guard(action) {
  let pending;
  return function(...args) {
    if(pending)return pending;
    pending=Promise.resolve().then(()=>action.apply(this,args)).finally(()=>{pending=undefined;});
    return pending;
  };
}
export function dialog({title,body='',saveLabel=t('Guardar'),onSave,error=errorMessage,className='',ids={}}) {
  const el=document.createElement('dialog'),lastFocus=document.activeElement;
  const titleId='arc-dialog-title-'+(++sequence);
  el.className='arcDialog '+className;el.setAttribute('aria-labelledby',titleId);
  el.innerHTML=`<form class="arcForm"><h2 id="${titleId}">${esc(title)}</h2>${body}<p class="arcFormError gsError" role="alert"${attr('id',ids.error)}></p><div class="arcToolbar gsActions">${button({id:ids.close,label:t('Volver'),attrs:'data-arc-dialog-close'})}${button({id:ids.save,type:'submit',variant:'primary',label:saveLabel})}</div></form>`;
  document.body.appendChild(el);
  let formApi;
  const close=()=>{if(formApi?.pending)return;el.close();};
  const remove=()=>{formApi?.dispose();el.remove();if(lastFocus?.isConnected)lastFocus.focus();};
  el.querySelector('[data-arc-dialog-close]').onclick=close;
  el.addEventListener('cancel',e=>{if(formApi?.pending)e.preventDefault();});
  el.addEventListener('close',remove,{once:true});
  formApi=bindForm(el.querySelector('form'),()=>onSave(el),{error,onSuccess:()=>{el.close();}});
  el.showModal();mount(el);return el;
}
export function confirm({title=t('Confirmar'),message,confirmLabel=t('Confirmar'),variant='danger'}={}) {
  return new Promise(resolve=>{
    let accepted=false;
    const el=dialog({title,body:'<p>'+esc(message)+'</p>',saveLabel:confirmLabel,onSave:()=>{accepted=true;}});
    const save=el.querySelector('[type=submit]');save.classList.remove('primary');save.classList.add(variant);
    el.addEventListener('close',()=>resolve(accepted),{once:true});
  });
}
export function tabs(items,active,{label='Navegación',className=''}={}) {return `<div class="arcTabs ${esc(className)}" role="tablist" aria-label="${esc(t(label))}">${items.map(item=>`<button class="arcButton secondary" role="tab" type="button" data-arc-tab="${esc(item.id)}" aria-selected="${item.id===active}" tabindex="${item.id===active?0:-1}"${attr('aria-controls',item.panelId)}>${esc(t(item.label))}</button>`).join('')}</div>`;}
export function bindTabs(root,onChange) {
  root.querySelectorAll('[role=tablist]').forEach(list=>{
    if(list.__arcTabs)return;list.__arcTabs=true;
    const choose=tab=>{list.querySelectorAll('[role=tab]').forEach(n=>{n.setAttribute('aria-selected',String(n===tab));n.tabIndex=n===tab?0:-1;const p=document.getElementById(n.getAttribute('aria-controls'));if(p)p.hidden=n!==tab;});tab.focus();onChange?.(tab.dataset.arcTab);};
    list.addEventListener('click',e=>{const tab=e.target.closest('[role=tab]');if(tab)choose(tab);});
    list.addEventListener('keydown',e=>{const choices=[...list.querySelectorAll('[role=tab]:not(:disabled)')],index=choices.indexOf(document.activeElement);if(index<0)return;const next={ArrowRight:(index+1)%choices.length,ArrowLeft:(index+choices.length-1)%choices.length,Home:0,End:choices.length-1}[e.key];if(next!=null){e.preventDefault();choose(choices[next]);}});
  });
}
/* Ventana con un menú lateral de apartados, abierta desde la barra superior
   (Configuración, Notificaciones). Cada apartado enseña su panel —varios pueden
   compartir uno— y `onSelect` carga lo que necesite. El menú tiene su propio
   teclado (flechas, Inicio, Fin) y, en el teléfono, se pone en fila. Ir a otra
   pantalla cierra la ventana: lo que se acaba de abrir queda a la vista. */
export function sideDialog({id,prefix,title,navLabel,tabs=[],panes=[],opener,onSelect=()=>{},onClose=()=>{}}) {
  const el=document.createElement('dialog');el.className='arcSideDialog';el.id=id;el.setAttribute('aria-labelledby',prefix+'Title');
  el.innerHTML=`<div class="arcSideDialogHead"><h2 id="${esc(prefix)}Title"><span data-gi-live>${esc(title)}</span></h2><button type="button" class="arcButton arcIconBtn" data-side-close aria-label="Cerrar" data-gi-aria-label="live"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18"/></svg></button></div>`
    +`<div class="arcSideDialogBody"><nav class="arcSideNav" aria-label="${esc(navLabel)}" data-gi-aria-label="live"><div class="arcSideList" role="tablist" aria-orientation="vertical"></div></nav>`
    +`<div class="arcSidePanes">${panes.map(p=>`<div role="tabpanel" id="${esc(prefix)}Pane-${esc(p.id)}" data-side-pane="${esc(p.id)}" tabindex="0" hidden>${p.html||''}</div>`).join('')}</div></div>`;
  const list=el.querySelector('[role=tablist]');
  // Su teclado es el de aquí; el genérico de las pestañas no se le aplica.
  list.__arcTabs=true;
  let items=[],selected=null;
  const badge=s=>s.badge?`<span class="arcSideBadge"${s.tone?` data-tone="${esc(s.tone)}"`:''}>${esc(s.badge)}</span>`:'';
  const tab=s=>`<button type="button" role="tab" id="${esc(prefix)}Tab-${esc(s.id)}" data-side-tab="${esc(s.id)}" aria-controls="${esc(prefix)}Pane-${esc(s.pane)}" aria-selected="false" tabindex="-1"><span class="arcSideLabel" data-gi-live>${esc(s.label)}</span>${badge(s)}</button>`;
  const button=id=>[...list.querySelectorAll('[data-side-tab]')].find(b=>b.dataset.sideTab===id);
  const mark=()=>list.querySelectorAll('[data-side-tab]').forEach(b=>{const on=b.dataset.sideTab===selected;b.setAttribute('aria-selected',String(on));b.tabIndex=on?0:-1;});
  // Los recuentos cambian a menudo: si los apartados son los mismos, sólo se tocan sus cifras.
  function setTabs(next) {
    const same=next.length===items.length&&next.every((s,i)=>s.id===items[i].id);items=next;
    if(same){for(const s of next){const b=button(s.id);b.querySelector('.arcSideBadge')?.remove();if(s.badge)b.insertAdjacentHTML('beforeend',badge(s));}return;}
    const focused=list.contains(document.activeElement)?document.activeElement.dataset.sideTab:null;
    list.innerHTML=next.map(tab).join('');window.GamaI18n?.scan?.(list);
    if(selected&&!next.some(s=>s.id===selected))select(next[0]?.id);else mark();
    if(focused)button(focused)?.focus();
  }
  function select(id,{focus=false}={}) {
    const s=items.find(x=>x.id===id)||items[0];if(!s)return;selected=s.id;mark();
    el.querySelectorAll('[data-side-pane]').forEach(p=>{const on=p.dataset.sidePane===s.pane;p.hidden=!on;if(on)p.setAttribute('aria-labelledby',prefix+'Tab-'+s.id);});
    el.querySelector('.arcSidePanes').scrollTop=0;
    if(focus)button(s.id)?.focus();
    onSelect(s);
  }
  list.addEventListener('click',e=>{const b=e.target.closest('[data-side-tab]');if(b)select(b.dataset.sideTab);});
  // Flechas arriba y abajo en el menú lateral; izquierda y derecha cuando, en el teléfono, se pone en fila.
  list.addEventListener('keydown',e=>{const all=[...list.querySelectorAll('[data-side-tab]')],i=all.indexOf(document.activeElement);if(i<0)return;const n=all.length,next={ArrowDown:(i+1)%n,ArrowRight:(i+1)%n,ArrowUp:(i+n-1)%n,ArrowLeft:(i+n-1)%n,Home:0,End:n-1}[e.key];if(next==null)return;e.preventDefault();select(all[next].dataset.sideTab,{focus:true});});
  const close=()=>{if(el.open)el.close();};
  el.querySelector('[data-side-close]').onclick=close;
  window.addEventListener('arc:route-change',close);
  const api={el,select,setTabs,close,get selected(){return selected;}};
  el.addEventListener('close',()=>{window.removeEventListener('arc:route-change',close);el.remove();onClose(api);if(!document.querySelector('dialog[open]'))opener?.focus?.();},{once:true});
  document.body.appendChild(el);setTabs(tabs);mount(el);el.showModal();
  return api;
}
export function table({columns,items,empty=t('No hay resultados.'),className='',rowAttributes=()=>''}) {
  const titleIndex=columns.findIndex(c=>!c.decorative);
  const html=items.length?items.map(item=>`<tr ${rowAttributes(item)}>${columns.map((col,i)=>`<td data-col="${esc(col.decorative||col.actions?'':t(col.label))}"${i===titleIndex?' data-gama-title':''}${col.numeric?' class="arcNumeric"':''}>${col.html?col.html(item):esc(col.value?col.value(item):item[col.key] ?? '')}</td>`).join('')}</tr>`).join(''):`<tr><td colspan="${columns.length}" class="arcEmpty">${esc(empty)}</td></tr>`;
  return `<div class="arcTableWrap gamaTableBox" data-arc-table><table class="arcTable gamaCards ${esc(className)}"><thead><tr data-gama-head>${columns.map(col=>`<th scope="col">${col.sort?`<button type="button" class="arcSort" data-arc-sort="${esc(col.sort)}">${esc(t(col.label))} <span aria-hidden="true">↕</span></button>`:esc(t(col.label))}</th>`).join('')}</tr></thead><tbody>${html}</tbody></table></div>`;
}
export function pager({page=0,pageSize=20,total=0}={}) {
  if(total<=pageSize)return '';
  const pages=Math.max(1,Math.ceil(total/pageSize));
  return `<div class="arcPager gamaPager">${button({label:t('‹ Anterior'),className:'gamaPagerBtn',disabled:page<=0,attrs:'data-arc-page="-1" data-page-prev'})}<span class="gamaPagerInfo" aria-live="polite">${total?page*pageSize+1:0}–${Math.min(total,(page+1)*pageSize)} ${esc(t('de'))} ${total} · ${page+1} / ${pages}</span>${button({label:t('Siguiente ›'),className:'gamaPagerBtn',disabled:page>=pages-1,attrs:'data-arc-page="1" data-page-next'})}</div>`;
}
export function dataTable(host,{columns,source,searchInput,actions={},empty,className='',initial={}}) {
  let disposed=false,generation=0,timer;
  const state={page:0,pageSize:20,search:'',...initial};
  async function refresh(patch={}) {
    Object.assign(state,patch);const token=++generation;host.setAttribute('aria-busy','true');
    if(!host.firstElementChild)host.innerHTML='<p role="status">'+esc(t('Cargando…'))+'</p>';
    try{
      const result=await source({...state});if(disposed||token!==generation||!host.isConnected)return;
      if(result.total>0&&state.page*state.pageSize>=result.total){return refresh({page:Math.max(0,Math.ceil(result.total/state.pageSize)-1)});}
      host.innerHTML=table({columns,items:result.items,empty,className})+pager(result);mount(host);
    }catch(e){if(!disposed&&token===generation){host.innerHTML='<p role="alert">'+esc(errorMessage(e))+'</p>'+button({label:t('Reintentar'),attrs:'data-arc-retry'});}}
    finally{if(token===generation)host.removeAttribute('aria-busy');}
  }
  function click(e){const b=e.target.closest('button');if(!b)return;if(b.hasAttribute('data-arc-page'))refresh({page:Math.max(0,state.page+Number(b.dataset.arcPage))});else if(b.hasAttribute('data-arc-sort'))refresh({page:0,sort:b.dataset.arcSort,ascending:state.sort===b.dataset.arcSort?!state.ascending:true});else if(b.hasAttribute('data-arc-retry'))refresh();else for(const [attribute,callback] of Object.entries(actions)){if(b.hasAttribute(attribute)){callback(b.getAttribute(attribute),b);break;}}}
  const search=()=>{clearTimeout(timer);timer=setTimeout(()=>refresh({page:0,search:searchInput.value}),200);};
  host.addEventListener('click',click);searchInput?.addEventListener('input',search);refresh();
  return {refresh,state,dispose(){disposed=true;++generation;clearTimeout(timer);host.removeEventListener('click',click);searchInput?.removeEventListener('input',search);}};
}
export function documentLines(lines,{currency,quantity='quantity',price='unit_price',tax='tax_rate'}={}) {
  const amounts=lines.reduce((a,l)=>{const sub=Number(l[quantity]||0)*Number(l[price]||0);a.subtotal+=sub;a.tax+=sub*Number(l[tax]||0)/100;return a;},{subtotal:0,tax:0});
  return {...amounts,total:amounts.subtotal+amounts.tax,formattedTotal:format.money(amounts.subtotal+amounts.tax,currency)};
}
/** Explicit render lifecycle, used by the router and module renderers. */
export function mount(root=document) {
  root.querySelectorAll('.gamaStdBack').forEach(b=>{if(!b.__gamaBound){b.__gamaBound=true;b.onclick=()=>window.ArcRouter.show('mainmenu');}});
  root.querySelectorAll('label').forEach(label=>{const control=label.querySelector('input,select,textarea')||(!label.htmlFor&&label.nextElementSibling?.matches('input,select,textarea')?label.nextElementSibling:null);if(control){if(!control.id)control.id='arc-control-'+(++sequence);if(!label.htmlFor)label.htmlFor=control.id;}});
  bindTabs(root);window.GamaTable?.scan?.(root);window.GamaSelectSearch?.scan?.(root);window.gamaApplyAccess?.();window.GamaI18n?.scan?.(root);
}
export function render(element,html) {element.innerHTML=html;mount(element);const section=element.closest('section[id]');if(section)window.dispatchEvent(new CustomEvent('arc:module-rendered',{detail:{id:section.id}}));return html;}
