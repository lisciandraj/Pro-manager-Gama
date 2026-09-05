/* GAMA — Informe de ventas: productos más vendidos y márgenes */
(function(){
'use strict';
const $=id=>document.getElementById(id);
const C=()=>window.GamaCloud;
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=n=>'$'+Number(n||0).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});
const sessionRole=()=>{try{return JSON.parse(localStorage.getItem('gama_session_v1')||'{}').role||''}catch(e){return ''}};
const canView=()=>['admin','commercial'].includes(sessionRole());
let range='30';
function goMenu(){document.querySelectorAll('section').forEach(s=>{s.classList.remove('active');s.style.display='none'});const m=$('mainmenu');if(m){m.removeAttribute('hidden');m.style.display='block';m.classList.add('active')}document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));window.scrollTo({top:0,behavior:'smooth'})}
function inject(){if($('gamaSalesReport'))return;const s=document.createElement('section');s.id='gamaSalesReport';s.innerHTML=`
<div class="srHead card"><div><div class="srKicker">GAMA STOCK MANAGER</div><h2>📈 Informe de ventas</h2><p>Productos más vendidos y márgenes estimados.</p></div><div class="srActions"><button class="secondary" id="srMenu">← Volver al menú</button><button class="secondary" id="srRefresh">↻ Actualizar</button></div></div>
<div class="card"><label>Periodo</label><select id="srRange"><option value="30">Últimos 30 días</option><option value="90">Últimos 90 días</option><option value="all">Todo el historial</option></select></div>
<div class="srKpis"><div><span>Ventas totales</span><b id="srKSales">$0,00</b></div><div><span>Unidades vendidas</span><b id="srKUnits">0</b></div><div><span>Margen estimado</span><b id="srKMargin">$0,00</b></div></div>
<div class="srGrid">
<div class="card"><h3>🏆 Más vendidos por cantidad</h3><div id="srByQty"><div class="srEmpty"><span class="gamaSpin"></span>Cargando…</div></div></div>
<div class="card"><h3>💰 Más vendidos por ingresos</h3><div id="srByRevenue"></div></div>
</div>
<p class="srNote muted">El margen se estima con el precio de compra actual de cada producto; no refleja el costo histórico exacto en la fecha de cada venta.</p>`;
(document.querySelector('.wrap')||document.body).appendChild(s);style();bind()}
function style(){if($('srCss'))return;const s=document.createElement('style');s.id='srCss';s.textContent=`#gamaSalesReport{display:none}.srHead{display:flex;justify-content:space-between;align-items:center;gap:12px}.srKicker{font-size:10px;font-weight:850;letter-spacing:1.2px;color:#087c8b}.srHead h2{margin:4px 0;font-size:28px}.srHead p{margin:0;color:#71808a}.srActions{display:flex;gap:8px;flex-wrap:wrap}.srKpis{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin:12px 0}.srKpis>div{background:#fff;border:1px solid #e2e8ec;border-radius:13px;padding:13px}.srKpis span{display:block;color:#71808a;font-size:11px;font-weight:700}.srKpis b{display:block;margin-top:6px;font-size:21px;color:#18324a}.srGrid{display:grid;grid-template-columns:1fr 1fr;gap:12px}.srRow{display:flex;justify-content:space-between;align-items:center;gap:8px;padding:9px 0;border-bottom:1px solid #edf1f2;font-size:12px}.srRow:last-child{border-bottom:0}.srRank{display:inline-flex;align-items:center;justify-content:center;width:22px;height:22px;border-radius:999px;background:#eef7f8;color:#087c8b;font-weight:800;font-size:11px;margin-right:8px}.srEmpty{text-align:center;padding:20px;color:#71808a}.srNote{margin-top:10px;font-size:11px}@media(max-width:800px){.srGrid{grid-template-columns:1fr}.srKpis{grid-template-columns:1fr}.srHead{align-items:flex-start;flex-direction:column;gap:10px}}`;document.head.appendChild(s)}
function bind(){$('srMenu').onclick=goMenu;$('srRefresh').onclick=load;$('srRange').onchange=()=>{range=$('srRange').value;load()}}
function show(){inject();document.querySelectorAll('section').forEach(s=>{s.classList.remove('active');s.style.display='none'});const sec=$('gamaSalesReport');sec.classList.add('active');sec.style.display='block';document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));load();window.scrollTo({top:0,behavior:'smooth'})}
window.gamaShowSalesReport=show;
function rangeStart(){if(range==='all')return null;const d=new Date();d.setDate(d.getDate()-Number(range));return d.toISOString()}
function renderList(hostId,rows,sub){const host=$(hostId);if(!host)return;host.innerHTML=rows.length?rows.map((r,i)=>`<div class="srRow"><span><span class="srRank">${i+1}</span><b>${esc(r.name)}</b></span><span>${sub(r)}</span></div>`).join(''):'<div class="srEmpty">Sin ventas en este periodo.</div>'}
async function load(){if(!canView())return;inject();const a=$('srByQty');if(a)a.innerHTML='<div class="srEmpty"><span class="gamaSpin"></span>Cargando…</div>';try{
  const pr=await C().list('products',{order:'name',ascending:true});if(pr.error)throw pr.error;
  const productMap=new Map((pr.data||[]).map(p=>[String(p.id),p]));
  const start=rangeStart();
  const invOpts={select:'id',order:'issue_date',ascending:false};
  if(start)invOpts.gte={issue_date:start};
  const ir=await C().list('invoices',invOpts);if(ir.error)throw ir.error;
  const invoiceIds=(ir.data||[]).map(i=>i.id);
  let lineRows=[];
  if(invoiceIds.length){const lr=await C().list('invoice_lines',{in:{invoice_id:invoiceIds}});if(lr.error)throw lr.error;lineRows=lr.data||[]}
  const byProduct=new Map();
  let totalSales=0,totalUnits=0,totalMargin=0;
  lineRows.forEach(l=>{
    const p=productMap.get(String(l.product_id));
    const qty=Number(l.quantity||0),unitPrice=Number(l.unit_price||0),revenue=qty*unitPrice;
    const cost=p?Number(p.purchase_price||0):0,margin=(unitPrice-cost)*qty;
    totalSales+=revenue;totalUnits+=qty;totalMargin+=margin;
    const key=String(l.product_id);
    if(!byProduct.has(key))byProduct.set(key,{name:p?.name||'Producto eliminado',qty:0,revenue:0,margin:0});
    const row=byProduct.get(key);row.qty+=qty;row.revenue+=revenue;row.margin+=margin;
  });
  $('srKSales').textContent=money(totalSales);$('srKUnits').textContent=totalUnits;$('srKMargin').textContent=money(totalMargin);
  const rows=[...byProduct.values()];
  renderList('srByQty',[...rows].sort((x,y)=>y.qty-x.qty).slice(0,10),r=>`${r.qty} uds · ${money(r.revenue)}`);
  renderList('srByRevenue',[...rows].sort((x,y)=>y.revenue-x.revenue).slice(0,10),r=>`${money(r.revenue)} · margen ${money(r.margin)}`);
}catch(e){console.error('[GAMA Sales Report]',e);if(a)a.innerHTML='<div class="srEmpty">No se pudo cargar el informe: '+esc(e.message||e)+'</div>'}}
})();
