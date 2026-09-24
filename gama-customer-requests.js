/* GAMA — Solicitudes de clientes */
(function(){'use strict';
const C=()=>window.GamaCloud,esc=window.ArcUI.esc;
const money=v=>Number(v||0).toLocaleString('es-EC',{style:'currency',currency:'USD',minimumFractionDigits:2,maximumFractionDigits:2});
const role=()=>{try{return JSON.parse(localStorage.getItem('gama_session_v1')||'null')?.role||''}catch(_){return ''}};
let requests=[],customers=[],products=[],page=0,totalCount=0,searchTimer=null,generation=0;
const PAGE_SIZE=20;
function isSearching(){return (document.getElementById('crSearch')?.value||'').trim().length>0}
function staff(){return ['admin','commercial','administrador','comercial'].includes(role())&&!!window.gamaAccessAllowed?.('customer-requests')}
function css(){ /* Styles are compiled in architect-components.css. */ }
function ensure(){
 css();const sec=document.getElementById('gqRequests');if(!sec)return null;
 if(sec.dataset.ready)return sec;sec.dataset.ready='1';
 window.ArcUI.render(sec,'<div class="cr"><div class="crTools"><input id="crSearch" data-gi-placeholder=aaf1a355cf20 placeholder="Buscar por cliente, correo o número…"><span class="badge" id="crCount"></span><button class="arcButton secondary" id="crRefresh" data-gi-live data-gi=fe5f6628c7b5>Actualizar</button></div><div id="crRows"></div><div id="crPager" class="crPager"></div><div id="crDetail"></div></div>');
 document.getElementById('crRefresh').onclick=()=>load();
 document.getElementById('crSearch').oninput=()=>{clearTimeout(searchTimer);searchTimer=setTimeout(()=>{page=0;load()},300)};
 return sec;
}
async function load(){if(!C()||!staff())return;const root=ensure();if(!root)return;const token=++generation;const rows=document.getElementById('crRows');if(rows)window.ArcUI.render(rows,'<div class="crEmpty"><span class="gamaSpin"></span>Sincronizando con la nube…</div>');const q=(document.getElementById('crSearch')?.value||'').trim();try{
  const cr=await C().list('customers',{order:'name',ascending:true});if(cr.error)throw cr.error;customers=cr.data||[];
  const pr=await C().list('products',{select:'id,name,reference,barcode,category,sale_price,tax_rate,stock,active',order:'name',ascending:true});if(pr.error)throw pr.error;products=pr.data||[];
  let rowsData=[];
  if(q){
    const ql=q.toLowerCase();
    const matchIds=customers.filter(c=>[c.name,c.identification,c.email].some(v=>String(v||'').toLowerCase().includes(ql))).map(x=>x.id);
    const queries=[C().list('customer_requests',{ilike:{requester_name:'%'+q+'%'},order:'created_at',ascending:false,limit:200}),C().list('customer_requests',{ilike:{requester_email:'%'+q+'%'},order:'created_at',ascending:false,limit:200})];
    if(matchIds.length)queries.push(C().list('customer_requests',{in:{customer_id:matchIds},order:'created_at',ascending:false,limit:200}));
    const results=await Promise.all(queries);
    for(const r of results)if(r.error)throw r.error;
    const byId=new Map();results.forEach(r=>(r.data||[]).forEach(x=>byId.set(String(x.id),x)));
    rowsData=[...byId.values()].sort((a,b)=>new Date(b.created_at)-new Date(a.created_at));
    totalCount=rowsData.length;
  }else{
    const rr=await C().list('customer_requests',{order:'created_at',ascending:false,range:[page*PAGE_SIZE,page*PAGE_SIZE+PAGE_SIZE-1],count:'exact'});if(rr.error)throw rr.error;
    rowsData=rr.data||[];totalCount=rr.count||0;
  }
  if(token!==generation||!root.isConnected||!staff())return;requests=rowsData;render()
}catch(e){console.error('[GAMA Requests]',e);if(rows&&root.isConnected&&token===generation)window.ArcUI.render(rows,'<div class="crEmpty crErr" data-gi=1ad05f5bd7a7>No se pudieron cargar las solicitudes. Verifica las políticas RLS.</div>')}}
const customer=id=>customers.find(x=>String(x.id)===String(id)),product=id=>products.find(x=>String(x.id)===String(id));
const clientName=r=>customer(r.customer_id)?.name||r.requester_name||'Cliente no vinculado',clientEmail=r=>customer(r.customer_id)?.email||r.requester_email||'';
const statusLabel=x=>({pending:'Pendiente',accepted:'Aceptada',invoiced:'Convertida en presupuesto',rejected:'Rechazada',cancelled:'Cancelada'}[x]||x||'Pendiente');
function renderPager(){const host=document.getElementById('crPager');if(!host)return;if(isSearching()||!totalCount){window.ArcUI.render(host,'');return}const from=page*PAGE_SIZE+1,to=Math.min(totalCount,(page+1)*PAGE_SIZE);window.ArcUI.render(host,`<span>${from}–${to} de ${totalCount}</span><span><button class="arcButton secondary" type="button" id="crPrev" ${page<=0?'disabled':''}>‹ Anterior</button> <button class="arcButton secondary" type="button" id="crNext" ${to>=totalCount?'disabled':''}>Siguiente ›</button></span>`);document.getElementById('crPrev').onclick=()=>{if(page>0){page--;load()}};document.getElementById('crNext').onclick=()=>{if(to<totalCount){page++;load()}}}
function render(){if(!ensure())return;const arr=requests;document.getElementById('crCount').textContent=totalCount+' solicitud'+(totalCount===1?'':'es');const host=document.getElementById('crRows');if(!host)return;window.ArcUI.render(host,arr.length?`<div class="crTable"><table class="arcTable"><thead><tr><th data-gi=213b026e9aa4>Solicitud</th><th data-gi=93b2a9ef782c>Fecha</th><th data-gi=f851d9a83ab0>Cliente</th><th data-gi=98e5acddb6c4>Estado</th><th data-gi=4c65f6bb0d0c>Total sin IVA</th><th></th></tr></thead><tbody>${arr.map(r=>`<tr><td><span class="crNum">${esc(r.dossier_reference||String(r.id).slice(0,8).toUpperCase())}</span></td><td>${esc(r.created_at?new Date(r.created_at).toLocaleString('es-EC'):'-')}</td><td><b>${esc(clientName(r))}</b><br><small>${esc(clientEmail(r))}</small></td><td><span class="crStatus ${esc(r.status)}">${esc(statusLabel(r.status))}</span></td><td><b>${money(r.total)}</b></td><td><button class="arcButton secondary" data-cr-open="${esc(r.id)}" data-gi=426234e72a5b>Detalle</button></td></tr>`).join('')}</tbody></table></div>`:`<div class="crEmpty" data-gi-live>${isSearching()?'Sin resultados para tu búsqueda.':'No hay solicitudes de clientes.'}</div>`);host.querySelectorAll('[data-cr-open]').forEach(b=>b.onclick=()=>detail(b.dataset.crOpen));renderPager()}
async function detail(id){if(!staff()||!ensure())return;const r=requests.find(x=>String(x.id)===String(id));if(!r)return;const host=document.getElementById('crDetail');window.ArcUI.render(host,'<div class="crDetail"><span class="gamaSpin"></span>Cargando detalle…</div>');try{const lr=await C().list('customer_request_lines',{eq:{request_id:r.id},order:'created_at',ascending:true});if(lr.error)throw lr.error;const lines=lr.data||[];if(!host.isConnected||!staff())return;window.ArcUI.render(host,`<div class="crDetail"><div class="crDetailHead"><div><b><span data-gi=213b026e9aa4>Solicitud </span>${esc(r.dossier_reference||String(r.id).slice(0,8).toUpperCase())}</b><div class="muted">${esc(r.created_at?new Date(r.created_at).toLocaleString('es-EC'):'')}</div></div><button class="arcButton secondary" id="crCloseDetail" type="button" data-gi=aeccae342e4b>Cerrar</button></div><div class="crNote"><b data-gi=07dc559c3d74>Cliente:</b> ${esc(clientName(r))}${clientEmail(r)?' · '+esc(clientEmail(r)):''}</div>${r.notes?`<div class="crNote"><b data-gi=ba87b30324c7>Comentario:</b> ${esc(r.notes)}</div>`:''}<div class="crLines"><table class="arcTable"><thead><tr><th data-gi=77b9238931ed>Producto</th><th data-gi=4805b9ed5d23>Cant.</th><th data-gi=2e4385b6057f>Precio</th><th data-gi=ba6da46c5e1c>IVA</th><th data-gi=4c65f6bb0d0c>Total sin IVA</th></tr></thead><tbody>${lines.map(x=>`<tr><td><b>${esc(product(x.product_id)?.name||'Producto')}</b><small>${esc(product(x.product_id)?.reference||'')}</small></td><td>${esc(x.quantity)}</td><td>${money(x.unit_price)}</td><td>${esc(x.tax_rate)}%</td><td>${money(x.line_total)}</td></tr>`).join('')}</tbody></table><div class="crTotal"><span data-gi=e4a2d805310b>Total solicitado sin IVA</span><span>${money(r.total)}</span></div></div><div class="crActions">${r.invoice_id?'<button class="arcButton primary" id="crInvoiceLink" data-gi-live data-gi=66fe2768d8fe>Ver presupuesto</button>':!['cancelled','rejected'].includes(r.status)?'<button class="arcButton primary" id="crInvoice" data-gi-live data-gi=b71aae8ecd0b>Crear presupuesto</button><button class="arcButton danger" id="crCancel" data-gi=bb9dbb406dcb>Cancelar</button>':''}</div><div id="crDetailMsg" class="crMsg"></div></div>`);document.getElementById('crCloseDetail').onclick=()=>window.ArcUI.render(host,'');document.getElementById('crCancel')?.addEventListener('click',()=>setStatus(r,'cancelled'));for(const key of ['crInvoice','crInvoiceLink'])document.getElementById(key)?.addEventListener('click',async e=>{const button=e.currentTarget;button.disabled=true;try{await window.GamaQuotes.fromRequest(r.id)}catch(error){const msg=document.getElementById('crDetailMsg');if(msg)msg.textContent=error.message||String(error);else alert(error.message||String(error))}finally{button.disabled=false}})}catch(e){window.ArcUI.render(host,'<div class="crDetail crErr">Error: '+esc(e.message||e)+'</div>')}}
async function setStatus(r,status){try{const x=await C().update('customer_requests',r.id,{status});if(x.error)throw x.error;r.status=status;render();detail(r.id)}catch(e){const m=document.getElementById('crDetailMsg');if(m){m.className='crMsg crErr';m.textContent='Error: '+(e.message||e)}}}
async function mount(host,id=null){
 if(!staff())return;
 clearTimeout(searchTimer);++generation;window.ArcUI.render(host,'<div id="gqRequests"></div>');ensure();await load();
 if(!host.isConnected||!document.getElementById('gqRequests')||!staff())return;
 if(id){const result=await C().list('customer_requests',{eq:{id},limit:1});if(result.error)throw result.error;if(!result.data?.[0])throw Error('Solicitud no disponible.');if(!requests.some(x=>x.id===id))requests.push(result.data[0]);await detail(id)}
}
window.GamaCustomerRequests={mount};
window.GamaOpenCustomerRequests=()=>window.GamaQuotes?.openRequests();
window.GamaOpenCustomerRequest=id=>window.GamaQuotes?.openRequests(id);
window.addEventListener('gama:auth-change',()=>{++generation;requests=[];customers=[];products=[];document.getElementById('gqRequests')?.remove()});
})();
