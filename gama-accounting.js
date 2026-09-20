/* GAMA — Contabilidad para equipos pequeños.

   La regla del módulo: nada se vuelve a teclear. Las facturas, los cobros, los
   pedidos y los proyectos ya están en GAMA; aquí se leen. Sólo se captura lo
   que no tenía sitio en ninguna pantalla: gastos, facturas de proveedor,
   cuentas de banco y caja, y los asientos que no nacen de un documento.

   Los importes se formatean con GamaCurrency, nunca con un símbolo escrito a
   mano: la divisa es un dato de la empresa, no una constante del código. */
(function(){
'use strict';
if(window.GamaAccounting&&!window.GamaAccounting.__arcLazy)return;
const ID='accounting',$=id=>document.getElementById(id);
const esc=window.ArcUI.esc;
const tr=s=>`<span data-gi-live>${esc(s)}</span>`;
const money=v=>window.GamaCurrency.format(v);
const num=(v,d)=>window.GamaCurrency.number(v,d);
const pct=v=>v==null?'—':num(v,1)+' %';
const allowed=()=>!!window.gamaAccessAllowed?.(ID);
const day=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
const monthStart=()=>day().slice(0,8)+'01';

const SECTIONS=[
 ['overview','Vista general'],['sales','Ventas'],['purchases','Compras'],['expenses','Gastos'],
 ['payments','Pagos'],['cash','Banco y caja'],['receivables','Cuentas por cobrar'],
 ['payables','Cuentas por pagar'],['ledger','Contabilidad'],['taxes','Impuestos'],
 ['reports','Informes'],['periods','Cierres'],['config','Parámetros']
];
/* Lo que ve un perfil comercial: su lado del negocio, sin libro mayor ni tesorería. */
const COMMERCIAL=new Set(['overview','sales','receivables','reports']);
const STATUS={pending:'No pagada',partial:'Pago parcial',paid:'Pagada',overdue:'Vencida',
 cancelled:'Anulada',missing_terms:'Plazo por configurar',awaiting_delivery:'Entrega pendiente',
 due_soon:'Próxima a vencer',draft:'Borrador',posted:'Contabilizada',reversed:'Contrapasada',
 open:'Abierto',closed:'Cerrado',matched:'Conciliado',unmatched:'Sin conciliar',ignored:'Ignorado'};
const ERRORS={ROLE_NOT_ALLOWED:'Tu perfil no tiene acceso a esta parte de Contabilidad.',
 NOT_ALLOWED:'No tienes permiso para esta acción. Pídelo en Parámetros de acceso.',
 PERIOD_CLOSED:'El periodo contable está cerrado. Un administrador puede reabrirlo.',
 ENTRY_UNBALANCED:'El asiento no cuadra: el total del debe debe igualar al del haber.',
 ENTRY_EMPTY:'El asiento no tiene importes.',
 ENTRY_POSTED_IMMUTABLE:'Un asiento contabilizado no se modifica ni se borra: se contrapasa.',
 ENTRY_NOT_POSTED:'Sólo se contrapasa un asiento contabilizado.',
 EXPENSE_POSTED:'El gasto ya está contabilizado. Anúlalo para corregirlo.',
 AMOUNT_EXCEEDS_BALANCE:'El importe supera el saldo pendiente de la factura.',
 CANCEL_PAYMENTS_FIRST:'Anula primero los pagos registrados de esta factura.',
 DRAFT_ENTRIES_REMAIN:'Hay asientos en borrador en el periodo. Contabilízalos o elimínalos antes de cerrar.',
 REASON_REQUIRED:'Indica el motivo.',FILE_TOO_LARGE:'El archivo supera el tamaño permitido.',
 TOO_MANY_FILES:'Máximo cuatro justificantes por gasto.',
 INVOICE_CANCELLED:'La factura está anulada.',INVALID_PERIOD:'El periodo seleccionado no es válido.'};

let generation=0,section='overview',rights=null,scope='none',state={};

function err(e){const s=String(e?.message||e);
 for(const[k,v]of Object.entries(ERRORS)){if(s.includes(k))return v;if(s===v)return v}
 return 'No se pudo completar la operación. Actualiza e inténtalo de nuevo.'}
async function rpc(action,data={}){
 if(!allowed())throw Error('ROLE_NOT_ALLOWED');
 await window.GamaCloudReady;
 const c=await GamaCloud.db();
 const r=await window.ArcData.rawRpc('gama_accounting_action',{p_action:action,p_data:data});
 if(r.error)throw Error(err(r.error));
 if(r.data==null)throw Error('EMPTY');
 return r.data;
}
async function mutate(action,data){const r=await rpc(action,data);
 window.dispatchEvent(new CustomEvent('gama:accounting-change'));return r}

function css(){ /* Styles are compiled in architect-components.css. */ }
function shell(){
 css();let s=$(ID);
 if(!s){s=document.createElement('section');s.id=ID;(document.querySelector('.wrap')||document.body).appendChild(s)}
 window.ArcUI.render(s,GamaUI.header({title:'Contabilidad',lead:'Lo que vendes, lo que gastas, lo que te deben y tu tesorería.'})
  +'<nav class="gaNav" id="gaNav"></nav><div id="gaMain" aria-live="polite"></div>');
 GamaUI.bindBack(s);window.showTab?.(ID);
 return s;
}
function nav(){
 const host=$('gaNav');if(!host)return;
 const visible=SECTIONS.filter(([k])=>scope==='all'||COMMERCIAL.has(k));
 window.ArcUI.render(host,visible.map(([k,label])=>`<button type="button" data-gi-live data-ga-section="${k}" class="arcButton ${section===k?'on':''}" aria-current="${section===k?'page':'false'}">${esc(label)}</button>`).join(''));
 host.querySelectorAll('[data-ga-section]').forEach(b=>b.onclick=()=>go(b.dataset.gaSection));
}
function busy(){window.ArcUI.render($('gaMain'),`<p class="arcPanel gaCard">${tr('Cargando…')}</p>`)}
function fail(e,retry){
 window.ArcUI.render($('gaMain'),`<div class="arcPanel gaCard"><p class="gaError" role="alert">${esc(err(e))}</p>
 <button class="arcButton secondary" id="gaRetry">${tr('Actualizar')}</button></div>`);
 $('gaRetry').onclick=retry;
}
function badge(s){return `<span class="arcStatusBadge gaBadge" data-s="${esc(s)}">${tr(STATUS[s]||s)}</span>`}
function kpi(label,value,hint,cls){
 return `<div class="arcPanel gaCard"><small>${tr(label)}</small><strong>${esc(value)}</strong>${hint?`<em class="${cls||''}">${esc(hint)}</em>`:''}</div>`;
}
function trend(current,previous){
 const a=Number(current||0),b=Number(previous||0);
 if(!b)return{text:'',cls:''};
 const d=(a-b)/Math.abs(b)*100;
 return{text:(d>=0?'+':'')+num(d,1)+' % vs '+'mes anterior',cls:d>=0?'gaUp':'gaDown'};
}
async function go(next){
 if(next)section=next;
 if(scope!=='all'&&!COMMERCIAL.has(section))section='overview';
 nav();
 const token=++generation;busy();
 try{
  const view=VIEWS[section];
  const data=await view.load();
  if(token!==generation||!allowed())return;
  window.ArcUI.render($('gaMain'),view.render(data));
  view.bind?.(data);
 }catch(e){if(token===generation)fail(e,()=>go())}
}
async function open(options={}){
 if(!allowed())return;
 state={};section=options.section||'overview';
 shell();
 try{
  const d=await rpc('overview');rights=d.rights;scope=d.scope;
  window.GamaCurrency.set(d.currency);
  /* El libro se pone al día al entrar: las facturas y cobros que los módulos
     comerciales han creado desde la última visita se contabilizan solos. */
  if(rights?.create)rpc('sync').catch(()=>{});
  state.overview=d;
 }catch(e){nav();fail(e,()=>open(options));return}
 return go(section);
}

/* ------------------------------------------------------------------ vistas */
const VIEWS={};

VIEWS.overview={
 load:async()=>state.overview||rpc('overview'),
 render(d){
  state.overview=d;
  const rev=trend(d.revenue.month,d.revenue.previous),exp=trend(d.expense.month,d.expense.previous);
  const resultMonth=Number(d.revenue.month)-Number(d.expense.month);
  const resultYear=Number(d.revenue.year)-Number(d.expense.year);
  const margin=Number(d.revenue.year)>0?resultYear/Number(d.revenue.year)*100:null;
  const c=d.customers,s=d.suppliers,t=d.treasury,x=d.taxes;
  return `<div class="arcPanel gaCard"><h3>${tr('Resultado del mes')}</h3>
   <div class="gaKpis">
    ${kpi('Ingresos del mes',money(d.revenue.month),rev.text,rev.cls)}
    ${kpi('Gastos del mes',money(d.expense.month),exp.text,exp.cls)}
    ${kpi('Resultado del mes',money(resultMonth),resultMonth>=0?'Beneficio':'Pérdida',resultMonth>=0?'gaUp':'gaDown')}
    ${kpi('Resultado del año',money(resultYear),margin==null?'':'Margen '+pct(margin))}
   </div>
   <p class="gaHint">${tr('Ingresos sin impuestos. Gastos: gastos contabilizados y facturas de proveedor, sin impuestos.')}</p></div>

   ${t?`<div class="arcPanel gaCard"><h3>${tr('Tesorería')}</h3>
   <div class="gaKpis">
    ${kpi('Saldo de las cuentas',money(t.balance))}
    ${kpi('Entradas del mes',money(t.inflow))}
    ${kpi('Salidas del mes',money(t.outflow))}
    ${kpi('Variación del mes',money(Number(t.inflow)-Number(t.outflow)),'',Number(t.inflow)-Number(t.outflow)>=0?'gaUp':'gaDown')}
   </div>
   ${t.accounts.length?`<div class="gaScroll"><table class="arcTable gaTable"><thead><tr>
    <th>${tr('Cuenta')}</th><th>${tr('Tipo')}</th><th class="gaNum">${tr('Saldo')}</th><th class="gaNum">${tr('Sin conciliar')}</th></tr></thead><tbody>
    ${t.accounts.map(a=>`<tr><td><b>${esc(a.name)}</b>${a.bank_name?'<br>'+esc(a.bank_name):''}</td>
     <td>${tr({bank:'Banco',cash:'Caja',card:'Tarjeta'}[a.kind]||a.kind)}</td>
     <td class="gaNum"><b>${money(a.current_balance)}</b></td>
     <td class="gaNum">${Number(a.unmatched)||'—'}</td></tr>`).join('')}</tbody></table></div>`
    :`<p class="gaHint">${tr('Todavía no hay cuentas de banco o caja. Créalas en Banco y caja.')}</p>`}</div>`:''}

   <div class="arcPanel gaCard"><h3>${tr('Clientes')}</h3>
   <div class="gaKpis">
    ${kpi('Facturado',money(c.invoiced))}
    ${kpi('Cobrado',money(c.collected))}
    ${kpi('Pendiente de cobro',money(c.outstanding))}
    ${kpi('Vencido',money(c.overdue),num(c.overdue_count,0)+' facturas',Number(c.overdue)>0?'gaDown':'')}
   </div>
   <p class="gaHint">${tr('Retraso medio de pago')} : <b>${esc(num(c.avg_delay,1))}</b> ${tr('días')}</p>
   <div class="gaActions"><button class="arcButton secondary" data-ga-go="receivables">${tr('Ver cuentas por cobrar')}</button></div></div>

   ${s?`<div class="arcPanel gaCard"><h3>${tr('Proveedores')}</h3>
   <div class="gaKpis">
    ${kpi('Pendiente de pago',money(s.outstanding))}
    ${kpi('Vence en 30 días',money(s.due_30))}
    ${kpi('Vencido',money(s.overdue),num(s.overdue_count,0)+' facturas',Number(s.overdue)>0?'gaDown':'')}
   </div>
   <div class="gaActions"><button class="arcButton secondary" data-ga-go="payables">${tr('Ver cuentas por pagar')}</button></div></div>`:''}

   ${x?`<div class="arcPanel gaCard"><h3>${tr('Impuestos del periodo')}</h3>
   <div class="gaKpis">
    ${kpi('Impuesto recaudado',money(x.collected))}
    ${kpi('Impuesto deducible',money(x.deductible))}
    ${kpi('Saldo estimado',money(Number(x.collected)-Number(x.deductible)))}
   </div>
   <p class="gaHint">${tr('Estimación interna a partir de tus documentos. No es una declaración fiscal ni sustituye al software legal de tu país.')}</p></div>`:''}

   ${d.expense.categories&&d.expense.categories.length?`<div class="arcPanel gaCard"><h3>${tr('Principales gastos del año')}</h3>
   ${d.expense.categories.map(k=>`<p>${esc(k.name)} · <b>${money(k.amount)}</b>
    <span class="gaBar"><i style="width:${Math.max(2,Math.round(Number(k.amount)/Number(d.expense.categories[0].amount||1)*100))}%"></i></span></p>`).join('')}</div>`:''}

   ${d.alerts&&d.alerts.unmatched!=null?`<div class="arcPanel gaCard"><h3>${tr('Puntos de atención')}</h3>
    <p>${tr('Movimientos bancarios sin conciliar')} : <b>${esc(num(d.alerts.unmatched,0))}</b></p>
    <p>${tr('Gastos sin justificante')} : <b>${esc(num(d.alerts.no_receipt,0))}</b></p>
    <p>${tr('Asientos descuadrados')} : <b>${esc(num(d.alerts.unbalanced,0))}</b></p>
    <p class="gaHint">${tr('Estas alertas también aparecen en el Centro de acción de Architect.')}</p></div>`:''}`;
 },
 bind(){document.querySelectorAll('[data-ga-go]').forEach(b=>b.onclick=()=>go(b.dataset.gaGo))}
};

function agingBlock(a){
 const cells=[['Sin vencer',a.current],['1–30 días',a.d30],['31–60 días',a.d60],['61–90 días',a.d90],['Más de 90 días',a.older]];
 return `<div class="gaAging">${cells.map(([l,v])=>`<div><small>${tr(l)}</small><b>${money(v)}</b></div>`).join('')}</div>`;
}
function filters(opts){
 return `<div class="gaTools">
  <label>${tr('Buscar')}<input id="gaSearch" value="${esc(state.search||'')}"></label>
  ${opts.status?`<label>${tr('Estado')}<select id="gaStatus">${opts.status.map(([k,v])=>`<option value="${k}" ${state.status===k?'selected':''} data-gi-live>${esc(v)}</option>`).join('')}</select></label>`:''}
  ${opts.dates?`<label>${tr('Desde')}<input id="gaFrom" type="date" value="${esc(state.from||monthStart())}"></label>
  <label>${tr('Hasta')}<input id="gaTo" type="date" value="${esc(state.to||day())}"></label>`:''}
  <button class="arcButton primary" id="gaApply">${tr('Aplicar')}</button>
  ${rights?.export?`<button class="arcButton secondary" id="gaExport">${tr('Exportar')}</button>`:''}</div>`;
}
function bindFilters(reload,rows,name){
 const apply=()=>{state.search=$('gaSearch')?.value||'';state.status=$('gaStatus')?.value||state.status;
  state.from=$('gaFrom')?.value||state.from;state.to=$('gaTo')?.value||state.to;state.offset=0;reload()};
 $('gaApply')?.addEventListener('click',apply);
 $('gaSearch')?.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();apply()}});
 $('gaExport')?.addEventListener('click',()=>exportRows(rows(),name));
}

VIEWS.receivables={
 load:()=>rpc('receivables',{status:state.status||'open',search:state.search||'',offset:state.offset||0,limit:50}),
 render(d){
  state.rows=d.rows;
  return `<div class="arcPanel gaCard"><h3>${tr('¿Quién nos debe dinero?')}</h3>
   ${filters({status:[['open','Pendientes'],['all','Todas'],['overdue','Vencidas'],['partial','Pago parcial'],['paid','Pagadas']]})}
   <div class="gaKpis">${kpi('Facturado',money(d.metrics.total))}${kpi('Cobrado',money(d.metrics.paid))}
    ${kpi('Pendiente',money(d.metrics.balance))}${kpi('Vencido',money(d.metrics.overdue),'',Number(d.metrics.overdue)>0?'gaDown':'')}</div>
   <h3>${tr('Balance de antigüedad')}</h3>${agingBlock(d.aging)}
   <div class="gaScroll"><table class="arcTable gaTable"><thead><tr>
    ${['Cliente','Factura','Fecha','Vencimiento','Total','Pagado','Pendiente','Retraso','Estado'].map(h=>`<th class="${['Total','Pagado','Pendiente','Retraso'].includes(h)?'gaNum':''}">${tr(h)}</th>`).join('')}
    </tr></thead><tbody>${d.rows.map(r=>`<tr>
     <td><b>${esc(r.customer_name)}</b></td>
     <td>${esc(r.number)}${r.external_number?'<br><small>'+esc(r.external_number)+'</small>':''}</td>
     <td>${esc(r.issue_date||'—')}</td><td>${esc(r.due_date||'—')}</td>
     <td class="gaNum">${money(r.total)}</td><td class="gaNum">${money(r.paid)}</td>
     <td class="gaNum"><b>${money(r.balance)}</b></td>
     <td class="gaNum">${r.days_remaining!=null&&r.days_remaining<0?esc(num(-r.days_remaining,0))+' '+tr('días'):'—'}</td>
     <td>${badge(r.payment_status)}</td></tr>`).join('')||`<tr><td colspan="9">${tr('No hay facturas para este filtro.')}</td></tr>`}
   </tbody></table></div>
   <p class="gaHint">${tr('Los cobros se registran en Pagos de clientes; aquí se consultan y se agrupan por antigüedad.')}</p></div>`;
 },
 bind(){bindFilters(()=>go(),()=>state.rows,'cuentas-por-cobrar')}
};

VIEWS.payables={
 load:()=>rpc('payables',{status:state.status||'open',search:state.search||'',offset:state.offset||0,limit:50}),
 render(d){
  state.rows=d.rows;
  return `<div class="arcPanel gaCard"><h3>${tr('¿A quién debemos dinero?')}</h3>
   ${filters({status:[['open','Pendientes'],['all','Todas'],['overdue','Vencidas'],['partial','Pago parcial'],['paid','Pagadas']]})}
   <div class="gaKpis">${kpi('Facturado',money(d.metrics.total))}${kpi('Pagado',money(d.metrics.paid))}
    ${kpi('Pendiente',money(d.metrics.balance))}${kpi('Vencido',money(d.metrics.overdue),'',Number(d.metrics.overdue)>0?'gaDown':'')}</div>
   <h3>${tr('Balance de antigüedad')}</h3>${agingBlock(d.aging)}
   <div class="gaScroll"><table class="arcTable gaTable"><thead><tr>
    ${['Proveedor','Factura','Fecha','Vencimiento','Total','Pagado','Pendiente','Estado','Acciones'].map(h=>`<th class="${['Total','Pagado','Pendiente'].includes(h)?'gaNum':''}">${tr(h)}</th>`).join('')}
    </tr></thead><tbody>${d.rows.map(r=>`<tr>
     <td><b>${esc(r.supplier_name)}</b></td><td>${r.erp_reference?'<b>'+esc(r.erp_reference)+'</b><br>':''}${esc(r.number)}</td>
     <td>${esc(r.issue_date)}</td><td>${esc(r.due_date||'—')}</td>
     <td class="gaNum">${money(r.total)}</td><td class="gaNum">${money(r.paid)}</td>
     <td class="gaNum"><b>${money(r.balance)}</b></td><td>${badge(r.payment_status)}</td>
     <td>${rights?.create&&Number(r.balance)>0&&r.status!=='cancelled'?`<button class="arcButton secondary" data-ga-pay="${esc(r.id)}">${tr('Registrar pago')}</button>`:''}</td>
    </tr>`).join('')||`<tr><td colspan="9">${tr('No hay facturas de proveedor para este filtro.')}</td></tr>`}
   </tbody></table></div></div>`;
 },
 bind(){bindFilters(()=>go(),()=>state.rows,'cuentas-por-pagar');
  document.querySelectorAll('[data-ga-pay]').forEach(b=>b.onclick=()=>supplierPaymentForm(state.rows.find(r=>r.id===b.dataset.gaPay)))}
};

/* ------------------------------------------------------------------ gastos */
const METHODS={transfer:'Transferencia',cash:'Efectivo',card:'Tarjeta',check:'Cheque',other:'Otro'};
function options(list,selected,labelKey){
 return list.map(o=>`<option value="${esc(o.id)}" ${String(selected)===String(o.id)?'selected':''}>${esc(o[labelKey||'name'])}</option>`).join('');
}
function field(label,html){return `<label>${tr(label)}${html}</label>`}

VIEWS.expenses={
 async load(){
  const [d,accounts]=await Promise.all([
   rpc('expenses',{from:state.from||monthStart(),to:state.to||day(),search:state.search||'',offset:0,limit:50}),
   rpc('accounts')]);
  return {...d,accounts:accounts.rows};
 },
 render(d){
  state.rows=d.rows;state.categories=d.categories;state.accounts=d.accounts;
  return `<div class="arcPanel gaCard"><h3>${tr('Gastos')}</h3>
   ${filters({dates:true})}
   <div class="gaKpis">${kpi('Gastos contabilizados del periodo',money(d.sum))}${kpi('Registros',num(d.total,0))}</div>
   ${rights?.create?`<div class="gaActions"><button class="arcButton primary" id="gaNewExpense">${tr('Registrar un gasto')}</button></div>`:''}
   <div class="gaScroll"><table class="arcTable gaTable"><thead><tr>
    ${['Referencia','Fecha','Proveedor','Categoría','Descripción','Importe','Justificante','Estado','Acciones'].map(h=>`<th class="${h==='Importe'?'gaNum':''}">${tr(h)}</th>`).join('')}
    </tr></thead><tbody>${d.rows.map(r=>`<tr>
     <td><b>${esc(r.reference)}</b></td><td>${esc(r.expense_date)}</td>
     <td>${esc(r.supplier_name||'—')}</td><td>${esc(r.category_name||'—')}</td>
     <td>${esc(r.description)}</td><td class="gaNum"><b>${money(r.amount_total)}</b></td>
     <td>${r.has_receipt?'✓':`<span class="gaError">${tr('Falta')}</span>`}</td>
     <td>${badge(r.status)}</td>
     <td><div class="gaActions">
      <button class="arcButton secondary" data-ga-receipt="${esc(r.id)}">${tr('Justificante')}</button>
      ${rights?.validate&&r.status==='draft'?`<button class="arcButton primary" data-ga-post="${esc(r.id)}">${tr('Contabilizar')}</button>`:''}
      ${rights?.edit&&r.status==='draft'?`<button class="arcButton secondary" data-ga-edit="${esc(r.id)}">${tr('Editar')}</button>`:''}
      ${rights?.validate&&r.status==='posted'?`<button class="arcButton secondary" data-ga-cancel="${esc(r.id)}">${tr('Anular')}</button>`:''}
     </div></td></tr>`).join('')||`<tr><td colspan="9">${tr('No hay gastos en este periodo.')}</td></tr>`}
   </tbody></table></div>
   <p class="gaHint">${tr('Un gasto en borrador puede editarse o eliminarse. Una vez contabilizado sólo se anula, y la anulación contrapasa su asiento.')}</p></div>`;
 },
 bind(){
  bindFilters(()=>go(),()=>state.rows,'gastos');
  $('gaNewExpense')?.addEventListener('click',()=>expenseForm(null));
  document.querySelectorAll('[data-ga-edit]').forEach(b=>b.onclick=()=>expenseForm(state.rows.find(r=>r.id===b.dataset.gaEdit)));
  document.querySelectorAll('[data-ga-post]').forEach(b=>b.onclick=()=>act(b,()=>mutate('expense_post',{id:b.dataset.gaPost}).then(()=>go())));
  document.querySelectorAll('[data-ga-cancel]').forEach(b=>b.onclick=()=>reasonForm('Anular el gasto',r=>mutate('expense_cancel',{id:b.dataset.gaCancel,reason:r}).then(()=>go())));
  document.querySelectorAll('[data-ga-receipt]').forEach(b=>b.onclick=()=>receiptForm(b.dataset.gaReceipt));
 }
};
async function act(b,fn){b.disabled=true;try{await fn()}catch(e){window.gamaToast?.(err(e));b.disabled=false}}
function reasonForm(title,save){
 GamaSales.modal(title,`<label class="gsField">${tr('Motivo')}<textarea id="gaReason" required minlength="3" maxlength="2000"></textarea></label>
 <p class="gaHint">${tr('El motivo queda en el historial de auditoría.')}</p>`,'Confirmar',
  async el=>{const r=el.querySelector('#gaReason').value.trim();if(r.length<3)throw Error('REASON_REQUIRED');await save(r)});
}
function expenseForm(row){
 const key=crypto.randomUUID(),cats=state.categories||[],accs=(state.accounts||[]).filter(a=>a.active);
 GamaSales.modal(row?'Editar el gasto':'Registrar un gasto',`<div class="gaGrid">
  ${field('Fecha',`<input id="gaDate" type="date" required max="${day()}" value="${esc(row?.expense_date||day())}">`)}
  ${field('Categoría',`<select id="gaCategory"><option value="">—</option>${options(cats,row?.category_id)}</select>`)}
  ${field('Importe sin impuestos',`<input id="gaUntaxed" type="number" required min="0" step="0.01" value="${esc(row?.amount_untaxed??'')}">`)}
  ${field('Impuesto',`<input id="gaTax" type="number" min="0" step="0.01" value="${esc(row?.tax_amount??0)}">`)}
  ${field('Importe total',`<input id="gaTotal" type="number" required min="0.01" step="0.01" value="${esc(row?.amount_total??'')}">`)}
  ${field('Medio de pago',`<select id="gaMethod"><option value="">—</option>${Object.entries(METHODS).map(([k,v])=>`<option value="${k}" ${row?.payment_method===k?'selected':''} data-gi-live>${esc(v)}</option>`).join('')}</select>`)}
  ${field('Cuenta de banco o caja',`<select id="gaAccount"><option value="">—</option>${options(accs,row?.financial_account_id)}</select>`)}
 </div>
 <label class="gsField">${tr('Descripción')}<input id="gaDescription" required maxlength="500" value="${esc(row?.description||'')}"></label>
 <label class="gsField">${tr('Comentario')}<textarea id="gaNotes" maxlength="2000">${esc(row?.notes||'')}</textarea></label>
 <p class="gaHint">${tr('El total se calcula solo desde el importe sin impuestos y el impuesto; puedes corregirlo.')}</p>`,
  row?'Guardar':'Registrar',async el=>{
   const v=id=>el.querySelector('#'+id).value;
   await mutate('expense_save',{id:row?.id||null,request_key:row?null:key,expense_date:v('gaDate'),
    category_id:v('gaCategory'),description:v('gaDescription'),amount_untaxed:Number(v('gaUntaxed')),
    tax_amount:Number(v('gaTax')||0),amount_total:Number(v('gaTotal')),payment_method:v('gaMethod'),
    financial_account_id:v('gaAccount'),notes:v('gaNotes')});
   await go();
  });
 const recalc=()=>{const u=Number($('gaUntaxed').value||0),t=Number($('gaTax').value||0);
  if(u>0)$('gaTotal').value=(u+t).toFixed(2)};
 $('gaUntaxed').oninput=recalc;$('gaTax').oninput=recalc;
}
async function receiptForm(id){
 let list=[];
 try{list=await rpc('expense_receipts',{expense_id:id})}catch(e){}
 const el=GamaSales.modal('Justificantes del gasto',
  `<div id="gaFiles">${list.map(f=>`<p><button type="button" class="arcButton secondary" data-ga-file="${esc(f.id)}">${esc(f.filename)}</button></p>`).join('')||`<p>${tr('Todavía no hay justificantes.')}</p>`}</div>
   ${rights?.create?`<label class="gsField">${tr('Añadir PDF, JPG, PNG o WebP (máximo 2 MB)')}
   <input id="gaFile" type="file" accept="application/pdf,image/png,image/jpeg,image/webp"></label>`:''}`,
  rights?.create?'Añadir':'Cerrar',async form=>{
   const input=form.querySelector('#gaFile'),file=input?.files?.[0];
   if(!file)return;
   if(file.size>2000000)throw Error('FILE_TOO_LARGE');
   const data=await new Promise((res,rej)=>{const r=new FileReader();r.onload=()=>res(r.result);r.onerror=rej;r.readAsDataURL(file)});
   await mutate('expense_receipt',{expense_id:id,filename:file.name,mime_type:file.type,data_url:data});
   await go();
  });
 el.querySelectorAll('[data-ga-file]').forEach(b=>b.onclick=async()=>{
  try{const f=await rpc('expense_receipt_get',{id:b.dataset.gaFile});
   const w=window.open();if(w)w.document.write(`<iframe src="${f.data_url}" style="border:0;width:100%;height:100%"></iframe>`);
  }catch(e){window.gamaToast?.(err(e))}});
}

/* ------------------------------------------------------ compras y proveedores */
VIEWS.purchases={
 async load(){
  const [d,accounts]=await Promise.all([rpc('supplier_invoices',{search:state.search||'',offset:0,limit:50}),rpc('accounts')]);
  return {...d,accounts:accounts.rows};
 },
 render(d){
  state.rows=d.rows;state.suppliers=d.suppliers;state.accounts=d.accounts;
  return `<div class="arcPanel gaCard"><h3>${tr('Facturas de proveedor')}</h3>
   ${filters({})}
   ${rights?.create?`<div class="gaActions"><button class="arcButton primary" id="gaNewBill">${tr('Registrar una factura de proveedor')}</button></div>`:''}
   <div class="gaScroll"><table class="arcTable gaTable"><thead><tr>
    ${['Proveedor','Factura','Fecha','Vencimiento','Total','Pagado','Pendiente','Estado','Acciones'].map(h=>`<th class="${['Total','Pagado','Pendiente'].includes(h)?'gaNum':''}">${tr(h)}</th>`).join('')}
    </tr></thead><tbody>${d.rows.map(r=>`<tr>
     <td><b>${esc(r.supplier_name)}</b></td><td>${r.erp_reference?'<b>'+esc(r.erp_reference)+'</b><br>':''}${esc(r.number)}</td>
     <td>${esc(r.issue_date)}</td><td>${esc(r.due_date||'—')}</td>
     <td class="gaNum">${money(r.total)}</td><td class="gaNum">${money(r.paid)}</td>
     <td class="gaNum"><b>${money(r.balance)}</b></td><td>${badge(r.payment_status)}</td>
     <td><div class="gaActions">
      ${rights?.create&&Number(r.balance)>0&&r.status!=='cancelled'?`<button class="arcButton primary" data-ga-pay="${esc(r.id)}">${tr('Registrar pago')}</button>`:''}
      ${rights?.validate&&r.status!=='cancelled'&&Number(r.paid)===0?`<button class="arcButton secondary" data-ga-void="${esc(r.id)}">${tr('Anular')}</button>`:''}
     </div></td></tr>`).join('')||`<tr><td colspan="9">${tr('No hay facturas de proveedor registradas.')}</td></tr>`}
   </tbody></table></div>
   <p class="gaHint">${tr('Los pedidos de compra siguen en el módulo Compras. Aquí se registra la factura recibida y su pago, que es lo que mueve la tesorería.')}</p></div>`;
 },
 bind(){
  bindFilters(()=>go(),()=>state.rows,'facturas-proveedor');
  $('gaNewBill')?.addEventListener('click',()=>billForm());
  document.querySelectorAll('[data-ga-pay]').forEach(b=>b.onclick=()=>supplierPaymentForm(state.rows.find(r=>r.id===b.dataset.gaPay)));
  document.querySelectorAll('[data-ga-void]').forEach(b=>b.onclick=()=>reasonForm('Anular la factura',r=>mutate('supplier_invoice_cancel',{id:b.dataset.gaVoid,reason:r}).then(()=>go())));
 }
};
function billForm(){
 const key=crypto.randomUUID(),sup=state.suppliers||[];
 GamaSales.modal('Registrar una factura de proveedor',`<div class="gaGrid">
  ${field('Proveedor',`<select id="gaSupplier" required><option value="">—</option>${options(sup)}</select>`)}
  ${field('Número de la factura',`<input id="gaNumber" required maxlength="80">`)}
  ${field('Fecha',`<input id="gaDate" type="date" required value="${day()}">`)}
  ${field('Plazo de pago (días)',`<input id="gaTerms" type="number" min="0" max="3650" value="30">`)}
  ${field('Base imponible',`<input id="gaSubtotal" type="number" required min="0" step="0.01">`)}
  ${field('Impuesto',`<input id="gaTaxAmount" type="number" min="0" step="0.01" value="0">`)}
  ${field('Total',`<input id="gaTotal" type="number" required min="0.01" step="0.01">`)}
 </div><label class="gsField">${tr('Comentario')}<textarea id="gaNotes" maxlength="2000"></textarea></label>
 <p class="gaHint">${tr('Al guardar se crea el asiento en el diario de compras y la factura aparece en cuentas por pagar.')}</p>`,
  'Registrar',async el=>{
   const v=id=>el.querySelector('#'+id).value;
   if(!v('gaSupplier'))throw Error('Selecciona un proveedor.');
   await mutate('supplier_invoice_save',{request_key:key,supplier_id:v('gaSupplier'),number:v('gaNumber'),
    issue_date:v('gaDate'),payment_terms_days:v('gaTerms'),subtotal:Number(v('gaSubtotal')),
    tax:Number(v('gaTaxAmount')||0),total:Number(v('gaTotal')),notes:v('gaNotes')});
   await go();
  });
 const recalc=()=>{const s=Number($('gaSubtotal').value||0),t=Number($('gaTaxAmount').value||0);
  if(s>0)$('gaTotal').value=(s+t).toFixed(2)};
 $('gaSubtotal').oninput=recalc;$('gaTaxAmount').oninput=recalc;
}
function supplierPaymentForm(row){
 if(!row)return;
 const key=crypto.randomUUID(),accs=(state.accounts||[]).filter(a=>a.active);
 GamaSales.modal('Registrar un pago a proveedor',
  `<p><b>${esc(row.supplier_name)}</b> · ${esc(row.number)}<br>${tr('Pendiente')} : <b>${money(row.balance)}</b></p>
   <div class="gaGrid">
   ${field('Importe',`<input id="gaAmount" type="number" required min="0.01" max="${esc(row.balance)}" step="0.01" value="${Number(row.balance).toFixed(2)}">`)}
   ${field('Fecha',`<input id="gaDate" type="date" required max="${day()}" value="${day()}">`)}
   ${field('Medio',`<select id="gaMethod">${Object.entries(METHODS).map(([k,v])=>`<option value="${k}" data-gi-live>${esc(v)}</option>`).join('')}</select>`)}
   ${field('Cuenta de banco o caja',`<select id="gaAccount"><option value="">—</option>${options(accs)}</select>`)}
   ${field('Referencia',`<input id="gaReference" maxlength="180">`)}
  </div>`,'Guardar el pago',async el=>{
   const v=id=>el.querySelector('#'+id).value;
   await mutate('supplier_payment',{request_key:key,supplier_invoice_id:row.id,amount:Number(v('gaAmount')),
    paid_at:v('gaDate'),method:v('gaMethod'),financial_account_id:v('gaAccount'),reference:v('gaReference')});
   await go();
  });
}

/* ------------------------------------------------------------------ ventas */
VIEWS.sales={
 load:()=>rpc('report_revenue',{from:state.from||day().slice(0,4)+'-01-01',to:state.to||day()}),
 render(d){
  state.rows=d.by_customer;
  const top=(list,title)=>`<div class="arcPanel gaCard"><h3>${tr(title)}</h3>${list.length?`<div class="gaScroll">
   <table class="arcTable gaTable"><thead><tr><th>${tr('Concepto')}</th><th class="gaNum">${tr('Importe')}</th></tr></thead>
   <tbody>${list.map(r=>`<tr><td>${esc(r.key||'—')}</td><td class="gaNum"><b>${money(r.amount)}</b></td></tr>`).join('')}</tbody></table></div>`
   :`<p class="gaHint">${tr('No hay datos en este periodo.')}</p>`}</div>`;
  const total=d.by_month.reduce((a,r)=>a+Number(r.amount||0),0);
  return `<div class="arcPanel gaCard"><h3>${tr('Cifra de negocio')}</h3>${filters({dates:true})}
   <div class="gaKpis">${kpi('Total del periodo',money(total))}${kpi('Meses con actividad',num(d.by_month.length,0))}</div>
   <p class="gaHint">${tr('Importes sin impuestos, desde las facturas registradas. Las anuladas y rechazadas no cuentan.')}</p></div>
   ${top(d.by_month.map(r=>({key:r.key,amount:r.amount})),'Por mes')}
   ${top(d.by_customer,'Por cliente')}
   ${top(d.by_product,'Por producto')}`;
 },
 bind(){bindFilters(()=>go(),()=>state.rows,'cifra-de-negocio')}
};

/* ------------------------------------------------------------------ pagos */
VIEWS.payments={
 async load(){
  const [rec,pay]=await Promise.all([
   rpc('receivables',{status:'all',search:state.search||'',limit:25}),
   rpc('payables',{status:'all',search:state.search||'',limit:25})]);
  return {rec,pay};
 },
 render(d){
  state.rows=d.rec.rows;
  return `<div class="arcPanel gaCard"><h3>${tr('Cobros y pagos')}</h3>${filters({})}
   <div class="gaKpis">
    ${kpi('Cobrado de clientes',money(d.rec.metrics.paid))}
    ${kpi('Pendiente de cobro',money(d.rec.metrics.balance))}
    ${kpi('Pagado a proveedores',money(d.pay.metrics.paid))}
    ${kpi('Pendiente de pago',money(d.pay.metrics.balance))}
   </div>
   <p class="gaHint">${tr('Los cobros de clientes se registran en Pagos de clientes y los pagos a proveedores en Compras. Esta pantalla los reúne para ver el saldo neto.')}</p>
   <div class="gaActions">
    ${window.gamaAccessAllowed?.('payments')?`<button class="arcButton secondary" id="gaOpenPayments">${tr('Ir a Pagos de clientes')}</button>`:''}
    <button class="arcButton secondary" data-ga-go="payables">${tr('Ver cuentas por pagar')}</button></div></div>`;
 },
 bind(){
  bindFilters(()=>go(),()=>state.rows,'pagos');
  $('gaOpenPayments')?.addEventListener('click',()=>window.GamaPayments?.open());
  document.querySelectorAll('[data-ga-go]').forEach(b=>b.onclick=()=>go(b.dataset.gaGo));
 }
};

/* ------------------------------------------------------- banco y caja */
VIEWS.cash={
 async load(){
  const [accounts,bank]=await Promise.all([rpc('accounts'),
   rpc('bank_list',{status:state.status||'unmatched',limit:50})]);
  return {accounts,bank};
 },
 render(d){
  state.accounts=d.accounts.rows;state.chart=d.accounts.chart;state.rows=d.bank.rows;state.bankAccounts=d.bank.accounts;
  const total=d.accounts.rows.filter(a=>a.active).reduce((s,a)=>s+Number(a.current_balance||0),0);
  return `<div class="arcPanel gaCard"><h3>${tr('Cuentas de banco y caja')}</h3>
   <div class="gaKpis">${kpi('Saldo total',money(total))}${kpi('Cuentas activas',num(d.accounts.rows.filter(a=>a.active).length,0))}</div>
   ${rights?.create?`<div class="gaActions"><button class="arcButton primary" id="gaNewAccount">${tr('Añadir una cuenta')}</button></div>`:''}
   <div class="gaScroll"><table class="arcTable gaTable"><thead><tr>
    ${['Nombre','Tipo','Banco','Divisa','Saldo inicial','Saldo actual','Estado','Acciones'].map(h=>`<th class="${h.startsWith('Saldo')?'gaNum':''}">${tr(h)}</th>`).join('')}
   </tr></thead><tbody>${d.accounts.rows.map(a=>`<tr>
    <td><b>${esc(a.name)}</b></td><td>${tr({bank:'Banco',cash:'Caja',card:'Tarjeta'}[a.kind]||a.kind)}</td>
    <td>${esc(a.bank_name||'—')}</td><td>${esc(a.currency)}</td>
    <td class="gaNum">${money(a.opening_balance)}</td><td class="gaNum"><b>${money(a.current_balance)}</b></td>
    <td>${a.active?tr('Activa'):tr('Inactiva')}</td>
    <td><div class="gaActions"><button class="arcButton secondary" data-ga-moves="${esc(a.id)}">${tr('Movimientos')}</button>
     ${rights?.edit?`<button class="arcButton secondary" data-ga-acc="${esc(a.id)}">${tr('Editar')}</button>`:''}</div></td>
   </tr>`).join('')||`<tr><td colspan="8">${tr('Todavía no hay cuentas.')}</td></tr>`}</tbody></table></div>
   <p class="gaHint">${tr('El saldo actual es el saldo inicial más los cobros y menos los pagos y gastos asignados a la cuenta.')}</p></div>

   <div class="arcPanel gaCard"><h3>${tr('Conciliación bancaria')}</h3>
   <div class="gaTools">
    <label>${tr('Estado')}<select id="gaStatus">${[['unmatched','Sin conciliar'],['matched','Conciliados'],['ignored','Ignorados']].map(([k,v])=>`<option value="${k}" ${(state.status||'unmatched')===k?'selected':''} data-gi-live>${esc(v)}</option>`).join('')}</select></label>
    <button class="arcButton primary" id="gaApply">${tr('Aplicar')}</button>
    ${rights?.create?`<button class="arcButton secondary" id="gaImport">${tr('Importar CSV')}</button>`:''}</div>
   <div class="gaScroll"><table class="arcTable gaTable"><thead><tr>
    ${['Fecha','Cuenta','Referencia','Descripción','Importe','Estado','Acciones'].map(h=>`<th class="${h==='Importe'?'gaNum':''}">${tr(h)}</th>`).join('')}
   </tr></thead><tbody>${d.bank.rows.map(t=>`<tr>
    <td>${esc(t.value_date)}</td><td>${esc(t.account_name)}</td><td>${esc(t.reference||'—')}</td>
    <td>${esc(t.description)}</td><td class="gaNum"><b class="${Number(t.amount)>=0?'gaUp':'gaDown'}">${money(t.amount)}</b></td>
    <td>${badge(t.status)}</td>
    <td>${rights?.validate?(t.status==='unmatched'
      ?`<button class="arcButton primary" data-ga-match="${esc(t.id)}">${tr('Conciliar')}</button>`
      :`<button class="arcButton secondary" data-ga-unmatch="${esc(t.id)}">${tr('Deshacer')}</button>`):''}</td>
   </tr>`).join('')||`<tr><td colspan="7">${tr('No hay movimientos con este filtro.')}</td></tr>`}</tbody></table></div>
   <p class="gaHint">${tr('Architect propone correspondencias; nunca concilia solo. Tú validas cada asociación.')}</p></div>`;
 },
 bind(){
  $('gaApply')?.addEventListener('click',()=>{state.status=$('gaStatus').value;go()});
  $('gaNewAccount')?.addEventListener('click',()=>accountForm(null));
  $('gaImport')?.addEventListener('click',()=>importForm());
  document.querySelectorAll('[data-ga-acc]').forEach(b=>b.onclick=()=>accountForm(state.accounts.find(a=>a.id===b.dataset.gaAcc)));
  document.querySelectorAll('[data-ga-moves]').forEach(b=>b.onclick=()=>movements(b.dataset.gaMoves));
  document.querySelectorAll('[data-ga-match]').forEach(b=>b.onclick=()=>matchForm(b.dataset.gaMatch));
  document.querySelectorAll('[data-ga-unmatch]').forEach(b=>b.onclick=()=>act(b,()=>mutate('reconcile_undo',{id:b.dataset.gaUnmatch}).then(()=>go())));
 }
};
function accountForm(row){
 const chart=state.chart||[];
 GamaSales.modal(row?'Editar la cuenta':'Añadir una cuenta',`<div class="gaGrid">
  ${field('Nombre',`<input id="gaName" required maxlength="160" value="${esc(row?.name||'')}">`)}
  ${field('Tipo',`<select id="gaKind">${[['bank','Banco'],['cash','Caja'],['card','Tarjeta']].map(([k,v])=>`<option value="${k}" ${row?.kind===k?'selected':''} data-gi-live>${esc(v)}</option>`).join('')}</select>`)}
  ${field('Banco',`<input id="gaBank" maxlength="160" value="${esc(row?.bank_name||'')}">`)}
  ${field('Saldo inicial',`<input id="gaOpening" type="number" step="0.01" value="${esc(row?.opening_balance??0)}">`)}
  ${field('Cuenta contable',`<select id="gaChart"><option value="">—</option>${chart.map(a=>`<option value="${esc(a.id)}" ${row?.account_id===a.id?'selected':''}>${esc(a.code)} · ${esc(a.name)}</option>`).join('')}</select>`)}
  ${row?field('Estado',`<select id="gaActive"><option value="true" ${row.active?'selected':''} data-gi-live data-gi=69d17ca16834>Activa</option><option value="false" ${row.active?'':'selected'} data-gi-live data-gi=059c89444ff7>Inactiva</option></select>`):''}
 </div>`,'Guardar',async el=>{
  const v=id=>el.querySelector('#'+id)?.value;
  await mutate('account_save',{id:row?.id||null,name:v('gaName'),kind:v('gaKind'),bank_name:v('gaBank'),
   opening_balance:Number(v('gaOpening')||0),account_id:v('gaChart'),active:v('gaActive')!=='false'});
  await go();
 });
}
async function movements(id){
 try{
  const rows=await rpc('account_movements',{id,from:state.from||monthStart(),to:state.to||day()});
  let balance=0;
  GamaSales.modal('Movimientos de la cuenta',`<div class="gaScroll"><table class="arcTable gaTable"><thead><tr>
   ${['Fecha','Referencia','Descripción','Entrada','Salida','Saldo'].map(h=>`<th class="${['Entrada','Salida','Saldo'].includes(h)?'gaNum':''}">${tr(h)}</th>`).join('')}
   </tr></thead><tbody>${[...rows].reverse().map(m=>{balance+=Number(m.in||0)-Number(m.out||0);
    return `<tr><td>${esc(m.date)}</td><td>${esc(m.reference||'—')}</td><td>${esc(m.label||'')}</td>
    <td class="gaNum">${Number(m.in)?money(m.in):'—'}</td><td class="gaNum">${Number(m.out)?money(m.out):'—'}</td>
    <td class="gaNum">${money(balance)}</td></tr>`}).join('')||`<tr><td colspan="6">${tr('Sin movimientos en el periodo.')}</td></tr>`}
   </tbody></table></div>`,'Cerrar',async()=>{});
 }catch(e){window.gamaToast?.(err(e))}
}
/* CSV mínimo: fecha, referencia, descripción, importe. Punto o coma decimal. */
function parseCsv(text){
 const lines=text.split(/\r?\n/).filter(l=>l.trim());
 if(!lines.length)return[];
 const sep=(lines[0].match(/;/g)||[]).length>(lines[0].match(/,/g)||[]).length?';':',';
 const head=lines[0].toLowerCase();
 const start=/fecha|date|importe|amount/.test(head)?1:0;
 const cols=start?lines[0].split(sep).map(h=>h.trim().toLowerCase()):[];
 const at=names=>cols.findIndex(c=>names.some(n=>c.includes(n)));
 const iDate=start?at(['fecha','date']):0,iRef=start?at(['referencia','reference','ref']):1,
  iDesc=start?at(['descripcion','descripción','description','concepto','libelle','libellé']):2,
  iAmt=start?at(['importe','amount','montant','valor']):3;
 return lines.slice(start).map(l=>{
  const c=l.split(sep).map(x=>x.trim().replace(/^"|"$/g,''));
  const raw=(c[iAmt<0?3:iAmt]||'').replace(/\s/g,'').replace(/\.(?=\d{3}\b)/g,'').replace(',','.');
  const amount=Number(raw);
  const date=(c[iDate<0?0:iDate]||'').trim();
  const iso=/^\d{4}-\d{2}-\d{2}$/.test(date)?date
   :/^(\d{2})[\/-](\d{2})[\/-](\d{4})$/.test(date)?date.replace(/^(\d{2})[\/-](\d{2})[\/-](\d{4})$/,'$3-$2-$1'):'';
  return {value_date:iso,reference:c[iRef<0?1:iRef]||'',description:c[iDesc<0?2:iDesc]||'—',amount};
 }).filter(r=>r.value_date&&Number.isFinite(r.amount)&&r.amount!==0);
}
function importForm(){
 const key=crypto.randomUUID(),accs=(state.bankAccounts||[]);
 let parsed=[];
 const el=GamaSales.modal('Importar movimientos bancarios',`<div class="gaGrid">
  ${field('Cuenta',`<select id="gaAccount" required>${options(accs)}</select>`)}
  ${field('Archivo CSV',`<input id="gaCsv" type="file" accept=".csv,text/csv">`)}
 </div><div id="gaPreview"></div>
 <p class="gaHint">${tr('Columnas esperadas: fecha, referencia, descripción e importe. Un importe negativo es una salida. Las líneas ya importadas no se duplican.')}</p>`,
  'Importar',async form=>{
   if(!parsed.length)throw Error('Selecciona un archivo con movimientos válidos.');
   const r=await mutate('bank_import',{request_key:key,financial_account_id:form.querySelector('#gaAccount').value,rows:parsed});
   window.gamaToast?.(GamaI18n?.t?.('Movimientos importados')||'Movimientos importados');
   await go();
  });
 el.querySelector('#gaCsv').onchange=async e=>{
  const file=e.target.files[0];if(!file)return;
  if(file.size>2000000){window.ArcUI.render(el.querySelector('#gaPreview'),`<p class="gaError">${tr('El archivo supera el tamaño permitido.')}</p>`);return}
  parsed=parseCsv(await file.text()).slice(0,1000);
  window.ArcUI.render(el.querySelector('#gaPreview'),parsed.length
   ?`<p>${tr('Líneas detectadas')} : <b>${parsed.length}</b></p><div class="gaScroll"><table class="arcTable gaTable"><tbody>
     ${parsed.slice(0,5).map(r=>`<tr><td>${esc(r.value_date)}</td><td>${esc(r.description)}</td><td class="gaNum">${money(r.amount)}</td></tr>`).join('')}
     </tbody></table></div>`
   :`<p class="gaError">${tr('No se reconoció ninguna línea. Revisa el separador y el formato de la fecha.')}</p>`);
 };
}
async function matchForm(id){
 let suggestions=[];
 try{suggestions=await rpc('reconcile_suggest',{id})}catch(e){}
 const el=GamaSales.modal('Conciliar el movimiento',
  suggestions.length?`<p>${tr('Architect propone estas correspondencias. Elige la correcta; ninguna se aplica sola.')}</p>
   ${suggestions.map(s=>`<p><label><input type="radio" name="gaMatch" value="${esc(s.type)}|${esc(s.id)}">
    <b>${esc(s.label)}</b> · ${money(s.amount)} · ${esc(s.date)}</label></p>`).join('')}
   <p><label><input type="radio" name="gaMatch" value="ignore|"> ${tr('Ignorar este movimiento')}</label></p>`
  :`<p>${tr('No se encontró ninguna correspondencia. Puedes ignorar el movimiento y tratarlo más tarde.')}</p>
   <p><label><input type="radio" name="gaMatch" value="ignore|" checked> ${tr('Ignorar este movimiento')}</label></p>`,
  'Confirmar',async form=>{
   const picked=form.querySelector('input[name=gaMatch]:checked');
   if(!picked)throw Error('Selecciona una opción.');
   const [type,match]=picked.value.split('|');
   await mutate('reconcile',{id,match_type:type,match_id:match||null});
   await go();
  });
}

/* ------------------------------------------------------------- contabilidad */
VIEWS.ledger={
 load:()=>rpc('entries',{from:state.from||monthStart(),to:state.to||day(),search:state.search||'',
  journal_id:state.journal||null,limit:60}),
 render(d){
  state.rows=d.rows;state.journals=d.journals;
  return `<div class="arcPanel gaCard"><h3>${tr('Asientos y diarios')}</h3>
   <div class="gaTools">
    <label>${tr('Diario')}<select id="gaJournal"><option value="">${tr('Todos')}</option>
     ${d.journals.map(j=>`<option value="${esc(j.id)}" ${state.journal===j.id?'selected':''}>${esc(j.code)} · ${esc(j.name)}</option>`).join('')}</select></label>
    <label>${tr('Desde')}<input id="gaFrom" type="date" value="${esc(state.from||monthStart())}"></label>
    <label>${tr('Hasta')}<input id="gaTo" type="date" value="${esc(state.to||day())}"></label>
    <label>${tr('Buscar')}<input id="gaSearch" value="${esc(state.search||'')}"></label>
    <button class="arcButton primary" id="gaApply">${tr('Aplicar')}</button>
    ${rights?.export?`<button class="arcButton secondary" id="gaExport">${tr('Exportar')}</button>`:''}
    ${rights?.create?`<button class="arcButton secondary" id="gaNewEntry">${tr('Asiento manual')}</button>`:''}</div>
   ${Number(d.pending)>0?`<p class="gaHint">${tr('Facturas de venta todavía sin asiento')} : <b>${esc(num(d.pending,0))}</b>.
    ${rights?.create?`<button class="arcButton secondary" id="gaSync">${tr('Contabilizar ahora')}</button>`:''}</p>`:''}
   <div class="gaScroll"><table class="arcTable gaTable"><thead><tr>
    ${['Número','Fecha','Diario','Referencia','Concepto','Debe','Haber','Estado','Acciones'].map(h=>`<th class="${['Debe','Haber'].includes(h)?'gaNum':''}">${tr(h)}</th>`).join('')}
   </tr></thead><tbody>${d.rows.map(e=>`<tr>
    <td><b>${esc(e.number)}</b></td><td>${esc(e.entry_date)}</td><td>${esc(e.journal_code)}</td>
    <td>${esc(e.reference||'—')}</td><td>${esc(e.memo||'—')}</td>
    <td class="gaNum">${money(e.total_debit)}</td><td class="gaNum">${money(e.total_credit)}</td>
    <td>${badge(e.status)}${Number(e.total_debit)!==Number(e.total_credit)?`<br><span class="gaError">${tr('Descuadrado')}</span>`:''}</td>
    <td><div class="gaActions"><button class="arcButton secondary" data-ga-lines="${esc(e.id)}">${tr('Detalle')}</button>
     ${rights?.validate&&e.status==='posted'?`<button class="arcButton secondary" data-ga-rev="${esc(e.id)}">${tr('Contrapasar')}</button>`:''}</div></td>
   </tr>`).join('')||`<tr><td colspan="9">${tr('No hay asientos en este periodo.')}</td></tr>`}</tbody></table></div>
   <p class="gaHint">${tr('Todo asiento cumple debe = haber. Un asiento contabilizado no se borra: se contrapasa y ambos quedan en el libro.')}</p></div>`;
 },
 bind(){
  const apply=()=>{state.journal=$('gaJournal').value||null;state.from=$('gaFrom').value;state.to=$('gaTo').value;
   state.search=$('gaSearch').value;go()};
  $('gaApply').onclick=apply;
  $('gaExport')?.addEventListener('click',()=>exportRows(state.rows,'asientos'));
  $('gaNewEntry')?.addEventListener('click',()=>entryForm());
  $('gaSync')?.addEventListener('click',b=>act(b.target,()=>mutate('sync').then(()=>go())));
  document.querySelectorAll('[data-ga-lines]').forEach(b=>b.onclick=()=>entryLines(b.dataset.gaLines));
  document.querySelectorAll('[data-ga-rev]').forEach(b=>b.onclick=()=>reasonForm('Contrapasar el asiento',r=>mutate('entry_reverse',{id:b.dataset.gaRev,reason:r}).then(()=>go())));
 }
};
async function entryLines(id){
 try{
  const lines=await rpc('entry_lines',{id});
  const d=lines.reduce((s,l)=>s+Number(l.debit||0),0),c=lines.reduce((s,l)=>s+Number(l.credit||0),0);
  GamaSales.modal('Detalle del asiento',`<div class="gaScroll"><table class="arcTable gaTable"><thead><tr>
   ${['Cuenta','Concepto','Debe','Haber'].map(h=>`<th class="${['Debe','Haber'].includes(h)?'gaNum':''}">${tr(h)}</th>`).join('')}
   </tr></thead><tbody>${lines.map(l=>`<tr><td><b>${esc(l.code)}</b> ${esc(l.account)}</td><td>${esc(l.label||'')}</td>
    <td class="gaNum">${Number(l.debit)?money(l.debit):'—'}</td><td class="gaNum">${Number(l.credit)?money(l.credit):'—'}</td></tr>`).join('')}
   <tr><td colspan="2"><b>${tr('Total')}</b></td><td class="gaNum"><b>${money(d)}</b></td><td class="gaNum"><b>${money(c)}</b></td></tr>
   </tbody></table></div>`,'Cerrar',async()=>{});
 }catch(e){window.gamaToast?.(err(e))}
}
async function entryForm(){
 let chart=[];
 try{chart=(await rpc('chart')).rows.filter(a=>a.active)}catch(e){}
 const key=crypto.randomUUID(),journals=state.journals||[];
 const row=i=>`<div class="gaGrid" data-ga-line="${i}">
  ${field('Cuenta',`<select class="gaLineAccount"><option value="">—</option>${chart.map(a=>`<option value="${esc(a.id)}">${esc(a.code)} · ${esc(a.name)}</option>`).join('')}</select>`)}
  ${field('Concepto',`<input class="gaLineLabel" maxlength="180">`)}
  ${field('Debe',`<input class="gaLineDebit" type="number" min="0" step="0.01" value="0">`)}
  ${field('Haber',`<input class="gaLineCredit" type="number" min="0" step="0.01" value="0">`)}</div>`;
 const el=GamaSales.modal('Asiento manual',`<div class="gaGrid">
   ${field('Diario',`<select id="gaJournalPick">${journals.filter(j=>j.kind==='misc').concat(journals.filter(j=>j.kind!=='misc')).map(j=>`<option value="${esc(j.code)}">${esc(j.code)} · ${esc(j.name)}</option>`).join('')}</select>`)}
   ${field('Fecha',`<input id="gaDate" type="date" required value="${day()}">`)}
   ${field('Referencia',`<input id="gaReference" maxlength="180">`)}</div>
  <label class="gsField">${tr('Concepto')}<input id="gaMemo" maxlength="300"></label>
  <div id="gaLines">${row(0)}${row(1)}</div>
  <button type="button" class="arcButton secondary" id="gaAddLine">${tr('Añadir una línea')}</button>
  <p class="gaHint" id="gaBalance"></p>`,'Contabilizar',async form=>{
   const lines=[...form.querySelectorAll('[data-ga-line]')].map(r=>({
    account_id:r.querySelector('.gaLineAccount').value,label:r.querySelector('.gaLineLabel').value,
    debit:Number(r.querySelector('.gaLineDebit').value||0),credit:Number(r.querySelector('.gaLineCredit').value||0)}))
    .filter(l=>l.account_id&&(l.debit>0||l.credit>0));
   if(lines.length<2)throw Error('ENTRY_EMPTY');
   await mutate('entry_manual',{request_key:key,journal:form.querySelector('#gaJournalPick').value,
    entry_date:form.querySelector('#gaDate').value,reference:form.querySelector('#gaReference').value,
    memo:form.querySelector('#gaMemo').value,lines});
   await go();
  });
 let count=2;
 const refresh=()=>{
  const rows=[...el.querySelectorAll('[data-ga-line]')];
  const d=rows.reduce((s,r)=>s+Number(r.querySelector('.gaLineDebit').value||0),0);
  const c=rows.reduce((s,r)=>s+Number(r.querySelector('.gaLineCredit').value||0),0);
  const box=el.querySelector('#gaBalance');
  window.ArcUI.render(box,`${tr('Debe')} <b>${money(d)}</b> · ${tr('Haber')} <b>${money(c)}</b> · `
   +(d===c&&d>0?`<b class="gaUp">${GamaI18n?.t?.('Cuadrado')||'Cuadrado'}</b>`:`<b class="gaError">${GamaI18n?.t?.('Descuadrado')||'Descuadrado'}</b>`));
 };
 el.addEventListener('input',refresh);refresh();
 el.querySelector('#gaAddLine').onclick=()=>{el.querySelector('#gaLines').insertAdjacentHTML('beforeend',row(count++));refresh()};
}

/* ------------------------------------------------------------- impuestos */
VIEWS.taxes={
 load:()=>rpc('taxes',{from:state.from||monthStart(),to:state.to||day()}),
 render(d){
  state.rows=d.rows;
  const balance=Number(d.summary.collected)-Number(d.summary.deductible);
  return `<div class="arcPanel gaCard"><h3>${tr('Resumen de impuestos')}</h3>${filters({dates:true})}
   <div class="gaKpis">${kpi('Impuesto recaudado',money(d.summary.collected))}
    ${kpi('Impuesto deducible',money(d.summary.deductible))}
    ${kpi('Saldo estimado',money(balance),balance>=0?'A pagar':'A favor')}</div>
   <p class="gaHint">${tr('Cálculo interno a partir de tus facturas y gastos. No constituye una declaración fiscal: la presentación oficial se hace con el sistema que exija tu país.')}</p></div>
   <div class="arcPanel gaCard"><h3>${tr('Tipos configurados')}</h3>
   ${rights?.create?`<div class="gaActions"><button class="arcButton primary" id="gaNewTax">${tr('Añadir un tipo')}</button></div>`:''}
   <div class="gaScroll"><table class="arcTable gaTable"><thead><tr>
    ${['Nombre','Código','Tipo','Uso','País','Vigente desde','Estado','Acciones'].map(h=>`<th class="${h==='Tipo'?'gaNum':''}">${tr(h)}</th>`).join('')}
   </tr></thead><tbody>${d.rows.map(t=>`<tr><td><b>${esc(t.name)}</b></td><td>${esc(t.code)}</td>
    <td class="gaNum">${esc(num(t.rate,4))} %</td>
    <td>${tr({collected:'Recaudado',deductible:'Deducible',both:'Ambos'}[t.kind]||t.kind)}</td>
    <td>${esc(t.country||'—')}</td><td>${esc(t.valid_from||'—')}</td>
    <td>${t.active?tr('Activo'):tr('Inactivo')}</td>
    <td>${rights?.edit?`<button class="arcButton secondary" data-ga-tax="${esc(t.id)}">${tr('Editar')}</button>`:''}</td></tr>`).join('')}
   </tbody></table></div>
   <p class="gaHint">${tr('Architect no trae ningún tipo nacional preconfigurado: define aquí los que se aplican a tu empresa y su fecha de entrada en vigor.')}</p></div>`;
 },
 bind(){
  bindFilters(()=>go(),()=>state.rows,'impuestos');
  $('gaNewTax')?.addEventListener('click',()=>taxForm(null));
  document.querySelectorAll('[data-ga-tax]').forEach(b=>b.onclick=()=>taxForm(state.rows.find(t=>t.id===b.dataset.gaTax)));
 }
};
function taxForm(row){
 GamaSales.modal(row?'Editar el tipo':'Añadir un tipo de impuesto',`<div class="gaGrid">
  ${field('Nombre',`<input id="gaName" required maxlength="80" value="${esc(row?.name||'')}">`)}
  ${field('Código',`<input id="gaCode" required maxlength="20" value="${esc(row?.code||'')}" ${row?'readonly':''}>`)}
  ${field('Tipo (%)',`<input id="gaRate" type="number" required min="0" max="99.9999" step="0.0001" value="${esc(row?.rate??'')}">`)}
  ${field('Uso',`<select id="gaKind">${[['both','Ambos'],['collected','Recaudado'],['deductible','Deducible']].map(([k,v])=>`<option value="${k}" ${row?.kind===k?'selected':''} data-gi-live>${esc(v)}</option>`).join('')}</select>`)}
  ${field('País (ISO)',`<input id="gaCountry" maxlength="2" value="${esc(row?.country||'')}">`)}
  ${field('Vigente desde',`<input id="gaValid" type="date" value="${esc(row?.valid_from||'')}">`)}
 </div>`,'Guardar',async el=>{
  const v=id=>el.querySelector('#'+id).value;
  await mutate('tax_save',{id:row?.id||null,name:v('gaName'),code:v('gaCode'),rate:Number(v('gaRate')),
   kind:v('gaKind'),country:v('gaCountry').toUpperCase()||null,valid_from:v('gaValid')||null,active:true});
  await go();
 });
}

/* ------------------------------------------------------------- informes */
VIEWS.reports={
 async load(){
  const from=state.from||monthStart(),to=state.to||day();
  const calls=[rpc('report_pl',{from,to})];
  if(scope==='all')calls.push(rpc('report_balance',{to}),rpc('report_cashflow',{from,to}),rpc('forecast'));
  const [pl,balance,cash,forecast]=await Promise.all(calls);
  return {pl,balance,cash,forecast};
 },
 render(d){
  state.rows=d.pl.rows;
  const group=(rows,type)=>rows.filter(r=>r.type===type);
  const table=(rows,title)=>`<div class="gaScroll"><table class="arcTable gaTable"><thead><tr>
   <th>${tr(title)}</th><th class="gaNum">${tr('Importe')}</th></tr></thead><tbody>
   ${rows.map(r=>`<tr><td><b>${esc(r.code)}</b> ${esc(r.name)}</td><td class="gaNum">${money(r.amount)}</td></tr>`).join('')
    ||`<tr><td colspan="2">${tr('Sin movimientos.')}</td></tr>`}</tbody></table></div>`;
  return `<div class="arcPanel gaCard"><h3>${tr('Cuenta de resultados')}</h3>${filters({dates:true})}
   <div class="gaKpis">${kpi('Productos',money(d.pl.income))}${kpi('Cargas',money(d.pl.expense))}
    ${kpi('Resultado',money(d.pl.result),'',Number(d.pl.result)>=0?'gaUp':'gaDown')}
    ${kpi('Margen',d.pl.margin==null?'—':pct(d.pl.margin))}</div>
   ${table(group(d.pl.rows,'income'),'Productos')}${table(group(d.pl.rows,'expense'),'Cargas')}
   <p class="gaHint">${tr('Calculado desde los asientos contabilizados del periodo.')}</p></div>

   ${d.balance?`<div class="arcPanel gaCard"><h3>${tr('Balance simplificado')} · ${esc(d.balance.as_of)}</h3>
   ${table(group(d.balance.rows,'asset'),'Activo')}
   <p>${tr('Existencias valoradas al precio de compra')} : <b>${money(d.balance.stock)}</b></p>
   ${table(group(d.balance.rows,'liability'),'Pasivo')}
   ${table(group(d.balance.rows,'equity'),'Fondos propios')}
   <p>${tr('Resultado del ejercicio')} : <b>${money(d.balance.result)}</b></p>
   <p class="gaHint">${tr('Balance simplificado de gestión. No sustituye a las cuentas anuales preparadas por tu asesor.')}</p></div>`:''}

   ${d.cash?`<div class="arcPanel gaCard"><h3>${tr('Tesorería del periodo')}</h3>
   <div class="gaScroll"><table class="arcTable gaTable"><thead><tr>
    ${['Mes','Entradas','Salidas','Neto'].map(h=>`<th class="${h==='Mes'?'':'gaNum'}">${tr(h)}</th>`).join('')}
   </tr></thead><tbody>${d.cash.rows.map(r=>`<tr><td>${esc(r.month)}</td>
    <td class="gaNum">${money(r.in)}</td><td class="gaNum">${money(r.out)}</td>
    <td class="gaNum"><b class="${Number(r.net)>=0?'gaUp':'gaDown'}">${money(r.net)}</b></td></tr>`).join('')
    ||`<tr><td colspan="4">${tr('Sin movimientos.')}</td></tr>`}</tbody></table></div></div>`:''}

   ${d.forecast?`<div class="arcPanel gaCard gaForecast"><h3>${tr('Previsión de tesorería')}</h3>
   <p class="gaHint"><b>${tr('Previsión, no un hecho.')}</b> ${tr('Proyecta el saldo actual con las facturas ya emitidas y recibidas. No incluye lo que todavía no está facturado.')}</p>
   <div class="gaKpis">${kpi('Saldo actual',money(d.forecast.balance))}
    ${d.forecast.horizons.map(h=>kpi(h.days+' días (previsión)',
      money(Number(d.forecast.balance)+Number(h.incoming)-Number(h.outgoing)),
      '+'+window.GamaCurrency.format(h.incoming)+' / −'+window.GamaCurrency.format(h.outgoing))).join('')}</div></div>`:''}`;
 },
 bind(){bindFilters(()=>go(),()=>state.rows,'cuenta-de-resultados')}
};

/* ------------------------------------------------------------- cierres */
VIEWS.periods={
 load:()=>rpc('periods'),
 render(d){
  state.rows=d.rows;
  return `<div class="arcPanel gaCard"><h3>${tr('Periodos contables')}</h3>
   ${rights?.close?`<div class="gaTools">
    <label>${tr('Cerrar el mes de')}<input id="gaMonth" type="month" value="${day().slice(0,7)}"></label>
    <button class="arcButton primary" id="gaClose">${tr('Cerrar el periodo')}</button></div>`:''}
   <div class="gaScroll"><table class="arcTable gaTable"><thead><tr>
    ${['Periodo','Asientos','Estado','Cerrado el','Acciones'].map(h=>`<th class="${h==='Asientos'?'gaNum':''}">${tr(h)}</th>`).join('')}
   </tr></thead><tbody>${d.rows.map(p=>`<tr><td><b>${esc(p.period_start)}</b> → ${esc(p.period_end)}</td>
    <td class="gaNum">${esc(num(p.entries,0))}</td><td>${badge(p.status)}</td>
    <td>${esc((p.closed_at||'').slice(0,10)||'—')}</td>
    <td>${rights?.close&&p.status==='closed'?`<button class="arcButton secondary" data-ga-reopen="${esc(p.period_start)}">${tr('Reabrir')}</button>`:''}</td>
   </tr>`).join('')||`<tr><td colspan="5">${tr('Todavía no hay periodos. Se crean solos al contabilizar el primer documento del mes.')}</td></tr>`}
   </tbody></table></div>
   <p class="gaHint">${tr('Un periodo cerrado rechaza cualquier asiento nuevo, modificado o eliminado en esas fechas. Sólo un administrador con permiso de cierre puede reabrirlo, y la reapertura queda en la auditoría.')}</p></div>`;
 },
 bind(){
  $('gaClose')?.addEventListener('click',b=>act(b.target,()=>mutate('period_close',{period_start:$('gaMonth').value+'-01'}).then(()=>go())));
  document.querySelectorAll('[data-ga-reopen]').forEach(b=>b.onclick=()=>reasonForm('Reabrir el periodo',r=>mutate('period_reopen',{period_start:b.dataset.gaReopen,reason:r}).then(()=>go())));
 }
};

/* ------------------------------------------------------------- parámetros */
VIEWS.config={
 async load(){
  const calls=[rpc('settings'),rpc('chart'),rpc('categories')];
  if(rights?.close)calls.push(rpc('permissions'));
  const [settings,chart,categories,permissions]=await Promise.all(calls);
  return {settings,chart,categories,permissions:permissions||[]};
 },
 render(d){
  state.chart=d.chart.rows;state.rows=d.chart.rows;state.permissions=d.permissions;
  const pick=(id,label,selected)=>field(label,`<select id="${id}">${d.settings.accounts.map(a=>`<option value="${esc(a.id)}" ${a.id===selected?'selected':''}>${esc(a.code)} · ${esc(a.name)}</option>`).join('')}</select>`);
  return `<div class="arcPanel gaCard"><h3>${tr('Empresa')}</h3><div class="gaGrid">
   ${field('Divisa (ISO 4217)',`<input id="gaCurrency" maxlength="3" value="${esc(d.settings.currency)}" ${rights?.edit?'':'readonly'}>`)}
   ${field('País (ISO)',`<input id="gaCountry" maxlength="2" value="${esc(d.settings.country)}" ${rights?.edit&&!d.settings.localization_country?'':'readonly'}>`)}
   ${field('Primer mes del ejercicio',`<input id="gaFiscal" type="number" min="1" max="12" value="${esc(d.settings.fiscal_year_start_month)}" ${rights?.edit?'':'readonly'}>`)}
   </div>
   <p class="gaHint">${tr('La divisa se aplica a todo Architect: pantallas, informes y documentos PDF.')}</p>
   <h3>${tr('Cuentas de los asientos automáticos')}</h3><div class="gaGrid">
   ${pick('gaRecv','Clientes',d.settings.receivable_account_id)}
   ${pick('gaPay','Proveedores',d.settings.payable_account_id)}
   ${pick('gaSales','Ventas',d.settings.sales_account_id)}
   ${pick('gaPurch','Compras',d.settings.purchase_account_id)}
   ${pick('gaTaxC','Impuesto recaudado',d.settings.tax_collected_account_id)}
   ${pick('gaTaxD','Impuesto deducible',d.settings.tax_deductible_account_id)}</div>
   ${rights?.edit?`<div class="gaActions"><button class="arcButton primary" id="gaSaveSettings">${tr('Guardar')}</button></div>`:''}</div>

   <div class="arcPanel gaCard"><h3>${tr('Plan contable')}</h3>
   ${rights?.create?`<div class="gaActions"><button class="arcButton primary" id="gaNewAccountLine">${tr('Añadir una cuenta')}</button></div>`:''}
   <div class="gaScroll"><table class="arcTable gaTable"><thead><tr>
    ${['Número','Nombre','Tipo','Estado','Acciones'].map(h=>`<th>${tr(h)}</th>`).join('')}
   </tr></thead><tbody>${d.chart.rows.map(a=>`<tr><td><b>${esc(a.code)}</b></td><td>${esc(a.name)}</td>
    <td>${tr({asset:'Activo',liability:'Pasivo',equity:'Fondos propios',income:'Productos',expense:'Cargas'}[a.type]||a.type)}</td>
    <td>${a.active?tr('Activa'):tr('Inactiva')}</td>
    <td>${rights?.edit?`<button class="arcButton secondary" data-ga-chart="${esc(a.id)}">${tr('Editar')}</button>`:''}</td></tr>`).join('')}
   </tbody></table></div>
   <p class="gaHint">${tr('La localización inicial se configura en Configuración → Empresa. Puedes adaptar las cuentas y los impuestos en Contabilidad.')}</p></div>

   ${d.permissions.length?`<div class="arcPanel gaCard"><h3>${tr('Permisos de Contabilidad')}</h3>
   <div class="gaScroll"><table class="arcTable gaTable"><thead><tr>
    ${['Usuario','Perfil','Consultar','Crear','Modificar','Eliminar','Validar','Exportar','Cerrar',''].map(h=>`<th>${tr(h)}</th>`).join('')}
   </tr></thead><tbody>${d.permissions.map(p=>{const r=p.rights||{};
    const cell=(k,def)=>`<td><input type="checkbox" data-ga-perm="${esc(p.profile_id)}" data-key="${k}" ${(r[k]??def)?'checked':''}></td>`;
    const admin=p.role==='administrador';
    return `<tr><td><b>${esc(p.name||p.email||'—')}</b></td><td>${esc(p.role)}</td>
    ${cell('can_view',admin||p.role==='comercial')}${cell('can_create',admin)}${cell('can_edit',admin)}
    ${cell('can_delete',admin)}${cell('can_validate',admin)}${cell('can_export',admin||p.role==='comercial')}${cell('can_close',admin)}
    <td><button class="arcButton secondary" data-ga-perm-save="${esc(p.profile_id)}">${tr('Guardar')}</button></td></tr>`}).join('')}
   </tbody></table></div>
   <p class="gaHint">${tr('Sin fila propia, cada perfil usa su valor por defecto: el administrador todo, el comercial consulta y exporta su lado comercial, el resto nada.')}</p></div>`:''}`;
 },
 bind(){
  $('gaSaveSettings')?.addEventListener('click',b=>act(b.target,async()=>{
   await mutate('settings_save',{currency:$('gaCurrency').value.toUpperCase(),country:$('gaCountry').value.toUpperCase(),
    fiscal_year_start_month:Number($('gaFiscal').value),receivable_account_id:$('gaRecv').value,
    payable_account_id:$('gaPay').value,sales_account_id:$('gaSales').value,purchase_account_id:$('gaPurch').value,
    tax_collected_account_id:$('gaTaxC').value,tax_deductible_account_id:$('gaTaxD').value});
   window.GamaCurrency.set($('gaCurrency').value.toUpperCase());
   await go();
  }));
  $('gaNewAccountLine')?.addEventListener('click',()=>chartForm(null));
  document.querySelectorAll('[data-ga-chart]').forEach(b=>b.onclick=()=>chartForm(state.chart.find(a=>a.id===b.dataset.gaChart)));
  document.querySelectorAll('[data-ga-perm-save]').forEach(b=>b.onclick=()=>act(b,async()=>{
   const id=b.dataset.gaPermSave,payload={profile_id:id};
   document.querySelectorAll(`[data-ga-perm="${id}"]`).forEach(c=>payload[c.dataset.key]=c.checked);
   await mutate('permission_save',payload);
   window.gamaToast?.(GamaI18n?.t?.('Permisos guardados')||'Permisos guardados');
  }));
 }
};
function chartForm(row){
 GamaSales.modal(row?'Editar la cuenta':'Añadir una cuenta',`<div class="gaGrid">
  ${field('Número',`<input id="gaCode" required maxlength="20" value="${esc(row?.code||'')}">`)}
  ${field('Nombre',`<input id="gaName" required maxlength="160" value="${esc(row?.name||'')}">`)}
  ${field('Tipo',`<select id="gaType" ${row?.is_system?'disabled':''}>${[['asset','Activo'],['liability','Pasivo'],['equity','Fondos propios'],['income','Productos'],['expense','Cargas']].map(([k,v])=>`<option value="${k}" ${row?.type===k?'selected':''} data-gi-live>${esc(v)}</option>`).join('')}</select>`)}
  ${row?field('Estado',`<select id="gaActive"><option value="true" ${row.active?'selected':''} data-gi-live data-gi=69d17ca16834>Activa</option><option value="false" ${row.active?'':'selected'} data-gi-live data-gi=059c89444ff7>Inactiva</option></select>`):''}
 </div>${row?.is_system?`<p class="gaHint">${tr('Cuenta usada por los asientos automáticos: puede renombrarse y renumerarse, pero no cambia de tipo.')}</p>`:''}`,
  'Guardar',async el=>{
   const v=id=>el.querySelector('#'+id)?.value;
   await mutate('chart_save',{id:row?.id||null,code:v('gaCode'),name:v('gaName'),
    type:v('gaType')||row?.type,active:v('gaActive')!=='false'});
   await go();
  });
}

/* ------------------------------------------------------------- exportación */
/* Un CSV con separador de punto y coma: Excel lo abre de doble clic en las tres
   lenguas y no hace falta ninguna librería. El export respeta el filtro activo. */
function exportRows(rows,name){
 if(!rows||!rows.length){window.gamaToast?.(GamaI18n?.t?.('No hay nada que exportar.')||'No hay nada que exportar.');return}
 const keys=[...rows.reduce((s,r)=>{Object.keys(r).forEach(k=>typeof r[k]!=='object'&&s.add(k));return s},new Set())];
 const cell=v=>v==null?'':/[";\n]/.test(String(v))?'"'+String(v).replace(/"/g,'""')+'"':String(v);
 const csv='﻿'+[keys.join(';'),...rows.map(r=>keys.map(k=>cell(r[k])).join(';'))].join('\n');
 const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'}));
 const a=document.createElement('a');a.href=url;a.download=`Architect-${name}-${day()}.csv`;
 document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),4000);
}

window.addEventListener('gama:currency-change',()=>{if($(ID)?.classList.contains('active'))go()});
window.GamaAccounting={open,rpc,SECTIONS};
})();
