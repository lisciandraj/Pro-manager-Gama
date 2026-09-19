/* Company cockpit: one authorized server snapshot, one shared period. */
(function(){'use strict';
const $=id=>document.getElementById(id),t=s=>window.GamaI18n?.t(s)||s,E=s=>window.ArcUI.esc(s),allowed=id=>!!window.gamaAccessAllowed?.(id);
const moduleDef=id=>window.ArcModules?.registry?.find(m=>m.id===id);
const locale=()=>window.GamaI18n?.locale||'fr-FR';
const date=s=>s?new Date(s+'T12:00:00Z').toLocaleDateString(locale(),{timeZone:'UTC',day:'2-digit',month:'2-digit',year:'numeric'}):'—';
const day=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
const shift=(s,n)=>{const d=new Date(s+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10)};
const num=v=>v==null?'—':Number(v).toLocaleString(locale(),{maximumFractionDigits:1});
const money=(v,currency=snapshot?.currency)=>v==null?'—':window.GamaCurrency.format(v,currency||undefined);
const active=()=>$('dashboard')?.classList.contains('active')&&allowed('dashboard');
let snapshot=null,generation=0,updated=0,inflight=null,abort=null,range={preset:'month',from:day().slice(0,8)+'01',to:day()};
let showAll=false;
const definitions=[
 ['payments','Ventas y cobros',[['current.net','Facturado sin impuestos','money','period'],['current.collected','Cobros confirmados','money','period'],['receivable','Pendiente de cobro','money'],['overdue','Cobros vencidos','money']]],
 ['sales-orders','Pedidos de clientes',[['current','Pedidos confirmados','number','period'],['to_ship','Pedidos por expedir'],['drafts','Borradores']]],
 ['quotes','Presupuestos',[['waiting','Presupuestos por responder'],['accepted','Presupuestos aceptados']]],
 ['crm','CRM',[['pipeline','Oportunidades abiertas','money'],['open','Oportunidades en curso'],['late','Actividades atrasadas']]],
 ['warehouses','Existencias',[['out','Referencias sin disponibilidad'],['low','Bajo el mínimo de stock']]],
 ['gamaPurchasesV14','Compras',[['open','Pedidos por recibir'],['late','Recepciones atrasadas'],['current','Pedidos de compra','number','period']]],
 ['tms','Entregas / TMS',[['pending','Entregas pendientes'],['late','Entregas atrasadas'],['delivered','Entregas realizadas','number','period']]],
 ['fleet','Gestión de flota',[['active','Vehículos activos'],['documents_due','Documentos vencidos o próximos'],['fuel','Combustible','money','period'],['maintenance','Mantenimiento','money','period']]],
 ['projects','Proyectos',[['active','Proyectos activos'],['late','Proyectos atrasados'],['late_tasks','Tareas atrasadas']]],
 ['hr','Recursos Humanos',[['active','Empleados activos'],['absent','Personas ausentes hoy'],['pending','Ausencias por aprobar']]],
 ['sav','Servicio posventa',[['open','Reclamaciones abiertas'],['late','Reclamaciones atrasadas'],['unassigned','Sin responsable'],['resolved','Reclamaciones resueltas','number','period']]],
 ['returns','Devoluciones',[['open','Devoluciones por cerrar'],['current','Devoluciones creadas','number','period']]],
 ['documents','Documentos',[['active','Documentos activos'],['expired','Documentos vencidos'],['expiring','Vencen en 30 días']]],
 ['knowledge','Knowledge · Base de conocimientos',[['articles','Artículos disponibles'],['updated','Artículos actualizados','number','period']]],
 ['clients','Clientes',[['active','Clientes activos'],['new','Nuevos clientes','number','period']]],
 ['suppliers','Proveedores',[['active','Proveedores activos']]],
 ['products','Productos',[['active','Productos activos']]]
];
const alertDefs=[
 ['payments','overdue_count','Relanzar los cobros vencidos','danger'],
 ['tms','late','Resolver las entregas atrasadas','danger'],
 ['warehouses','out','Revisar las referencias sin disponibilidad','danger'],
 ['sav','late','Atender las reclamaciones atrasadas','danger'],
 ['accounting','overdue_count','Revisar los pagos a proveedores','danger'],
 ['projects','late_tasks','Desbloquear las tareas atrasadas','danger'],
 ['documents','expired','Renovar los documentos vencidos','danger'],
 ['gamaPurchasesV14','late','Relanzar las recepciones atrasadas','warning'],
 ['fleet','documents_due','Revisar los documentos de los vehículos','warning'],
 ['crm','late','Realizar las actividades comerciales','warning'],
 ['sales-orders','to_ship','Preparar los pedidos pendientes','warning'],
 ['quotes','waiting','Dar seguimiento a los presupuestos','warning'],
 ['sav','unassigned','Asignar un responsable SAV','warning'],
 ['hr','pending','Revisar las solicitudes de ausencia','warning'],
 ['documents','expiring','Anticipar los vencimientos documentales','warning'],
 ['returns','open','Tratar las devoluciones abiertas','warning']
];
const valueAt=(object,path)=>path.split('.').reduce((v,k)=>v?.[k],object);
const icon=id=>{const name=moduleDef(id)?.icon||'chart';return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true">${window.ArcUI.icons?.[name]||''}</svg>`};
const go=(id,label,extra='')=>`<button type="button" class="arcButton secondary" data-ad-open="${E(id)}" ${extra}>${E(t(label))} <span aria-hidden="true">→</span></button>`;
function shell(){
 if($('ad-workspace'))return;
 const host=$('dashboard');if(!host)return;host.setAttribute('aria-label',t('Panel de control'));
 host.innerHTML=window.ArcUI.header({title:t('Panel de control'),lead:t('Los números clave, las prioridades y una visión de toda la empresa.')})+`<div id="ad-workspace" class="adWorkspace"><form id="ad-period" class="arcPanel adPeriod"><label class="arcField">${E(t('Periodo de análisis'))}<select id="ad-preset" data-gama-nofind>${[['month','Este mes'],['previous-month','Mes anterior'],['30','Últimos 30 días'],['year','Este año'],['custom','Personalizado']].map(([v,l])=>`<option value="${v}">${E(t(l))}</option>`).join('')}</select></label><label class="arcField">${E(t('Desde'))}<input id="ad-from" type="date" required></label><label class="arcField">${E(t('Hasta'))}<input id="ad-to" type="date" required></label><div class="adPeriodActions"><button type="submit" class="arcButton primary">${E(t('Aplicar'))}</button><button type="button" class="arcButton secondary" id="ad-refresh">${E(t('Actualizar'))}</button></div><p id="ad-period-error" class="arcFormError" role="alert"></p></form><div id="ad-content" aria-live="polite"></div></div>`;
 const form=$('ad-period');$('ad-preset').onchange=()=>preset($('ad-preset').value);
 for(const id of ['ad-from','ad-to'])$(id).onchange=()=>{$('ad-preset').value='custom'};
 form.onsubmit=e=>{e.preventDefault();const from=$('ad-from').value,to=$('ad-to').value;
  if(!from||!to||from>to||to>day()||(new Date(to)-new Date(from))/86400000>730){$('ad-period-error').textContent=t('Elige un periodo válido de hasta dos años, sin fechas futuras.');return}
  range={preset:$('ad-preset').value,from,to};refresh(true);
 };
 $('ad-refresh').onclick=()=>refresh(true);
 host.addEventListener('click',click);syncForm();window.ArcUI.mount(host);
}
function syncForm(){if(!$('ad-period'))return;$('ad-preset').value=range.preset;$('ad-from').value=range.from;$('ad-to').value=range.to;$('ad-from').max=day();$('ad-to').max=day()}
function preset(p){let to=day(),from=to.slice(0,8)+'01';if(p==='custom')return;if(p==='previous-month'){to=shift(from,-1);from=to.slice(0,8)+'01'}if(p==='30')from=shift(to,-29);if(p==='year')from=to.slice(0,4)+'-01-01';range={preset:p,from,to};syncForm();refresh(true)}
function comparison(now,previous){if(now==null||previous==null)return t('Comparación no disponible');if(previous===0)return now===0?t('Sin variación'):t('Sin base de comparación');const pct=(now-previous)/Math.abs(previous)*100;return `${pct>0?'+':''}${num(pct)} % · ${t('periodo anterior')}`}
function metric(id,label,amount,detail,previous,format='money',field=''){return `<button type="button" class="arcPanel adMetric" data-ad-open="${E(id)}" data-ad-metric="${E(field)}"><span class="adMetricLabel">${icon(id)}${E(t(label))}</span><strong>${E(format==='money'?money(amount):num(amount))}</strong><small>${E(t(detail))}</small>${previous!==undefined?`<span class="adDelta">${E(comparison(amount,previous))}</span>`:''}<span class="adMetricArrow" aria-hidden="true">↗</span></button>`}
function render(){
 if(!snapshot||!active())return;shell();const s=snapshot.sections,p=snapshot.period,has=id=>Object.hasOwn(s,id)&&allowed(id);
 const unavailable=(snapshot.unavailable||[]).filter(id=>allowed(id)),modules=Object.keys(s).filter(allowed),cards=[];
 if(has('payments')){cards.push(metric('payments','Facturado sin impuestos',s.payments?.current.net,'Antes de abonos · periodo',s.payments?.previous.net??null,'money','net'));
  cards.push(metric('payments','Cobros confirmados',s.payments?.current.collected,'Impuestos incluidos · periodo',s.payments?.previous.collected??null,'money','collected'));
  cards.push(metric('payments','Pendiente de cobro',s.payments?.receivable,'Saldo de facturas · hoy',undefined,'money','receivable'))}
 if(has('sales-orders'))cards.push(metric('sales-orders','Pedidos confirmados',s['sales-orders']?.current,'Creados en el periodo',s['sales-orders']?.previous??null,'number','orders'));
 if(!has('payments')){if(has('warehouses'))cards.push(metric('warehouses','Referencias sin disponibilidad',s.warehouses?.out,'Stock disponible · hoy',undefined,'number','out'));
 if(has('tms'))cards.push(metric('tms','Entregas realizadas',s.tms?.delivered,'Periodo seleccionado',undefined,'number','delivered'));
 if(has('sales-orders'))cards.push(metric('sales-orders','Pedidos por expedir',s['sales-orders']?.to_ship,'Situación actual',undefined,'number','to_ship'))}
 const alerts=alertDefs.filter(([id,key])=>has(id)&&Number(s[id]?.[key])>0),visible=showAll?alerts:alerts.slice(0,6);
 $('ad-content').innerHTML=`<div class="adMeta"><span>${E(date(p.from))} — ${E(date(p.to))} <small>· ${E(t('Comparación'))} ${E(date(p.previous_from))} — ${E(date(p.previous_to))}</small></span><span>${E(t('Actualizado'))} ${E(new Date(snapshot.generated_at).toLocaleTimeString(locale(),{hour:'2-digit',minute:'2-digit'}))}</span></div>
 ${unavailable.length?`<p class="adNotice" role="alert">${E(t('Datos parciales. Fuentes no disponibles:'))} ${unavailable.map(id=>E(t(moduleDef(id)?.label||id))).join(', ')}. ${E(t('Actualiza para reintentar.'))}</p>`:''}
 <div class="adMetrics">${cards.join('')}</div>
 <article class="arcPanel adPriorities"><div class="adHeading"><div><h2>${E(t('Prioridades de hoy'))}</h2><p>${E(t('Los pendientes actuales no cambian con el periodo de análisis.'))}</p></div><span class="adDate">${E(date(snapshot.today))}</span></div><div class="adAlertGrid">${visible.map(([id,key,label,tone])=>`<button type="button" class="adAlert" data-ad-open="${E(id)}" data-ad-focus="${E(key)}" data-tone="${tone}"><span class="adAlertCount">${E(num(s[id][key]))}</span><span><strong>${E(t(label))}</strong><small>${E(t(moduleDef(id)?.label||id))}</small></span><span aria-hidden="true">→</span></button>`).join('')||`<p class="adEmpty">${E(t(unavailable.length?'No hay alertas en los datos disponibles.':'No hay prioridades detectadas en los módulos disponibles.'))}</p>`}</div><div class="arcToolbar">${alerts.length>6?`<button type="button" class="arcButton ghost" id="ad-all-alerts">${E(t(showAll?'Ver menos':'Ver todas las prioridades'))} (${num(alerts.length)})</button>`:''}${allowed('operations')?go('operations','Control comercial y logístico'):''}</div></article>
 ${has('payments')?financial(s.payments):''}${has('accounting')?accounting(s.accounting):''}
 <div class="adHeading"><div><h2>${E(t('La empresa por actividad'))}</h2><p>${E(t('Situación actual. Los valores marcados «Periodo» siguen las fechas seleccionadas.'))}</p></div><span class="adDate">${num(modules.length-unavailable.length)} ${E(t('fuentes conectadas'))}</span></div>
 <div class="adModuleGrid">${definitions.filter(([id])=>has(id)).map(([id,label,metrics])=>`<article class="arcPanel adModule" data-ad-source="${E(id)}"><div class="adModuleHead"><span class="adModuleIcon">${icon(id)}</span><h3>${E(t(label))}</h3></div>${s[id]==null?`<p class="adEmpty">${E(t('Datos no disponibles'))}</p>`:`<dl>${metrics.map(([key,label,type,scope])=>`<div><dt>${E(t(label))}${scope?` <small>${E(t('Periodo'))}</small>`:''}</dt><dd>${E(type==='money'?money(valueAt(s[id],key)):num(valueAt(s[id],key)))}</dd></div>`).join('')}</dl>`}${go(id,'Abrir módulo')}</article>`).join('')}</div>
 <details class="arcPanel adMethod"><summary>${E(t('Cómo leer estos indicadores'))}</summary><p>${E(t('La facturación incluye las facturas internas y externas válidas una sola vez, antes de abonos. Los cobros incluyen solo pagos confirmados. El pendiente de cobro descuenta pagos y abonos.'))}</p><p>${E(t('Las fechas siguen la zona horaria de la empresa: Ecuador. La comparación usa el intervalo anterior con el mismo número de días.'))}</p><p>${E(t('Los saldos, retrasos y existencias son actuales; no reconstruyen una situación histórica. Solo se muestran los datos permitidos por tu perfil.'))}</p><p>${E(t('Los módulos de configuración y las herramientas de apoyo no generan indicadores adicionales.'))}</p></details>`;
 $('ad-all-alerts')?.addEventListener('click',()=>{showAll=!showAll;render();$('ad-all-alerts')?.focus()});window.ArcUI.mount($('ad-content'));
}
function financial(data){if(!data)return '';
 const p=snapshot.period,rows=data.trend||[],max=Math.max(...rows.flatMap(r=>[r.invoiced,r.collected]),1),width=760,height=210,left=16,plot=728,step=plot/Math.max(rows.length,1),bar=Math.min(24,step*.36),ticks=Math.max(1,Math.ceil(rows.length/7));
 const chart=rows.length&&rows.some(r=>r.invoiced||r.collected)?`<div class="adChartScroll" tabindex="0" role="region" aria-label="${E(t('Evolución de facturas y cobros'))}"><svg class="adChart" viewBox="0 0 ${width} 250" role="img" aria-labelledby="ad-chart-title ad-chart-desc"><title id="ad-chart-title">${E(t('Evolución de facturas y cobros'))}</title><desc id="ad-chart-desc">${E(t('Impuestos incluidos. Los importes exactos están en la tabla de datos.'))}</desc>${[0,.5,1].map(v=>`<line x1="${left}" y1="${height-v*170}" x2="744" y2="${height-v*170}" class="adGridLine"/><text x="${left}" y="${height-v*170-7}" class="adChartText">${E(money(max*v))}</text>`).join('')}${rows.map((r,i)=>{const x=left+i*step+step/2;return `<g><title>${E(date(r.from))} — ${E(date(r.to))}: ${E(t('Facturas'))} ${E(money(r.invoiced))}; ${E(t('Cobros'))} ${E(money(r.collected))}</title><rect x="${x-bar-1}" y="${height-r.invoiced/max*170}" width="${bar}" height="${r.invoiced/max*170}" rx="2" class="adBarInvoice"/><rect x="${x+1}" y="${height-r.collected/max*170}" width="${bar}" height="${r.collected/max*170}" rx="2" class="adBarCash"/>${i%ticks===0?`<text x="${x}" y="237" text-anchor="middle" class="adChartText">${E(date(r.from).slice(0,-5))}</text>`:''}</g>`}).join('')}</svg></div>`:`<p class="adEmpty">${E(t('No hay facturas ni cobros en este periodo.'))}</p>`;
 return `<div class="adAnalysis"><article class="arcPanel"><div class="adHeading"><div><h2>${E(t('Facturación y cobros'))}</h2><p>${E(t('Impuestos incluidos · periodo seleccionado'))}</p></div></div><div class="adLegend"><span><i class="adBarInvoice"></i>${E(t('Facturas'))}: <b>${E(money(data.current.total))}</b></span><span><i class="adBarCash"></i>${E(t('Cobros'))}: <b>${E(money(data.current.collected))}</b></span></div>${chart}<details class="adChartData"><summary>${E(t('Ver los datos del gráfico'))}</summary>${window.ArcUI.table({columns:[{key:'from',label:t('Desde'),value:r=>date(r.from)},{key:'to',label:t('Hasta'),value:r=>date(r.to)},{key:'invoiced',label:t('Facturas'),value:r=>money(r.invoiced)},{key:'collected',label:t('Cobros'),value:r=>money(r.collected)}],items:rows})}</details></article>
 <article class="arcPanel adCustomers"><h2>${E(t('Principales clientes'))}</h2><p>${E(t('Facturado sin impuestos · periodo seleccionado'))}</p><ol>${(data.customers||[]).map((r,i)=>`<li><span class="adRank">${i+1}</span><span>${E(r.name||t('Cliente'))}</span><strong>${E(money(r.amount))}</strong></li>`).join('')||`<li class="adEmpty">${E(t('Sin facturas en este periodo.'))}</li>`}</ol>${go('payments','Ver facturas y cobros')}</article></div>`;
}
function accounting(data){if(!data)return `<p class="adNotice">${E(t('Contabilidad'))} · ${E(t('Datos no disponibles'))}</p>`;
 const amounts=list=>list?.length?list.map(r=>`<span>${E(money(r.amount,r.currency))}</span>`).join(''):'—';
 return `<article class="arcPanel adFinance"><div class="adHeading"><div><h2>${E(t('Tesorería y compromisos'))}</h2><p>${E(t('Saldos actuales y gastos registrados en el periodo.'))}</p></div>${go('accounting','Abrir contabilidad','data-ad-focus="overview"')}</div><div class="adFinanceGrid"><div><span>${E(t('Saldo registrado de las cuentas'))}</span><strong>${amounts(data.accounts)}</strong><small>${E(t('Por moneda · no es un saldo bancario conciliado'))}</small></div><div><span>${E(t('Pendiente de pago a proveedores'))}</span><strong>${E(money(data.payable))}</strong><small>${E(t('Vencido'))}: ${E(money(data.overdue))}</small></div><div><span>${E(t('Gastos contabilizados'))}</span><strong>${amounts(data.expenses)}</strong><small>${E(t('Impuestos incluidos · periodo seleccionado'))}</small></div></div><p class="adFootnote">${E(t('El saldo registrado recoge saldos iniciales, cobros, pagos y gastos asignados a cuentas. Los reembolsos sin cuenta asociada no están incluidos. No equivale al beneficio.'))}</p></article>`;
}
async function click(e){const b=e.target.closest('[data-ad-open]');if(!b||!allowed(b.dataset.adOpen))return;const id=b.dataset.adOpen,focus=b.dataset.adFocus;b.disabled=true;try{
 if(id==='payments'&&window.GamaPayments)await window.GamaPayments.open({status:focus==='overdue_count'?'overdue':b.dataset.adMetric==='receivable'?'open':'all'});
 else if(id==='accounting'&&window.GamaAccounting)await window.GamaAccounting.open({section:focus==='overdue_count'?'payables':'overview'});
 else if(id==='documents'&&window.GamaDocuments)await window.GamaDocuments.open({filter:focus==='expired'?'expired':focus==='expiring'?'expiring':'active'});
 else if(id==='sav'&&window.GamaService)await window.GamaService.open({filter:focus==='late'?'late':focus==='unassigned'?'unassigned':'open'});
 else await window.ArcRouter.open(id);
 }catch(_){window.gamaToast?.(t('No se ha podido abrir el módulo. Vuelve a intentarlo.'))}finally{b.disabled=false}}
async function refresh(force=false){
 if(!active())return;shell();if(!force&&(inflight||snapshot&&Date.now()-updated<60000))return;
 const token=++generation;abort?.abort();abort=new AbortController();const controller=abort,signal=controller.signal;
 if(force){snapshot=null;updated=0}$('ad-period-error').textContent='';syncForm();$('ad-content').setAttribute('aria-busy','true');$('ad-content').innerHTML=`<p class="arcPanel adEmpty" role="status">${E(t('Cargando los datos de la empresa…'))}</p>`;
 let timer;const run=(async()=>{
  try{await window.GamaCloudReady;const c=await window.GamaCloud.db();if(token!==generation)return;
   const session=(await window.GamaCloud.getSession()).data?.session;if(!session)throw Error('AUTH_REQUIRED');
   let query=c.rpc('gama_company_dashboard',{p_from:range.from,p_to:range.to});if(query.abortSignal)query=query.abortSignal(signal);
   const r=await Promise.race([query,new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(Error('TIMEOUT'))},20000)})]);
   if(r.error)throw r.error;if(!r.data||!r.data.sections||!r.data.period||r.data.user_id!==session.user.id)throw Error('INVALID_DASHBOARD');
   if(token!==generation||!active())return;snapshot=r.data;updated=Date.now();render();
  }catch(error){if(token!==generation||!active())return;console.warn('[dashboard]',error.code||error.message);snapshot=null;$('ad-content').innerHTML=`<div class="arcPanel adNotice" role="alert"><p>${E(t('No se han podido cargar los indicadores. Actualiza para reintentar.'))}</p><button type="button" class="arcButton secondary" id="ad-retry">${E(t('Reintentar'))}</button></div>`;$('ad-retry').onclick=()=>refresh(true);
  }finally{clearTimeout(timer);if(token===generation){inflight=null;$('ad-content')?.removeAttribute('aria-busy')}}
 })();inflight=run;await run;
}
function invalidate(){generation++;abort?.abort();inflight=null;snapshot=null;updated=0;showAll=false;$('ad-content')?.replaceChildren();if(active())refresh(true)}
window.ArchitectDashboard={refresh};
window.addEventListener('arc:route-change',e=>{if(e.detail?.id==='dashboard')refresh()});
window.addEventListener('arc:route-leave',e=>{if(e.detail?.id==='dashboard'){generation++;abort?.abort();inflight=null;updated=0}});
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event!=='TOKEN_REFRESHED')invalidate()});
window.addEventListener('gama:modules-change',invalidate);
window.addEventListener('gama:language-change',()=>{const host=$('dashboard');host?.removeEventListener('click',click);host?.replaceChildren();if(active()){shell();if(snapshot)render();else refresh(true)}});
window.addEventListener('gama:currency-change',()=>{if(snapshot)render()});
window.addEventListener('focus',()=>refresh());
})();
