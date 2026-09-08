/* GAMA — Análisis de ventas dentro del Panel de control.

   Esto era un módulo aparte, «Informe de ventas», con su propia pantalla y su
   propio selector de periodo (30 / 90 días / todo). Convivía con un Panel de
   control que analizaba lo mismo con OTRO selector —año y mes— y con una
   tarjeta «Top productos» que decía casi lo mismo que «Más vendidos por
   ingresos». Dos pantallas, dos periodos y dos cifras que podían no coincidir
   para responder a la misma pregunta.

   Ahora hay una sola pantalla de análisis. Este archivo aporta lo que el panel
   no sabía calcular —el margen y los más vendidos por cantidad— y lo hace para
   el periodo que marca el propio panel, así que todo lo que se ve en pantalla
   habla del mismo intervalo.

   La diferencia de origen importa: el panel se dibuja con db.invoices, el
   espejo local, mientras que estos paneles consultan la nube, porque el margen
   necesita el precio de compra de cada producto y las líneas de factura, que
   el espejo no guarda. */
(function(){
'use strict';
if(window.GamaSalesReport)return;

const $=id=>document.getElementById(id);
const C=()=>window.GamaCloud;
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=n=>'$'+Number(n||0).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});
const sessionRole=()=>{try{return JSON.parse(localStorage.getItem('gama_session_v1')||'{}').role||''}catch(e){return ''}};
const canView=()=>['admin','commercial'].includes(sessionRole());

/* Evita que dos repintados seguidos —cambiar de año y de mes al vuelo— se
   pisen y deje en pantalla el resultado del más lento. */
let peticion=0;

function style(){
 if($('srCss'))return;
 const s=document.createElement('style');s.id='srCss';
 s.textContent=`.srRow{display:flex;justify-content:space-between;align-items:center;gap:8px;padding:9px 0;border-bottom:1px solid #edf1f2;font-size:12px}
.srRow:last-child{border-bottom:0}
.srRank{display:inline-flex;align-items:center;justify-content:center;width:22px;height:22px;border-radius:999px;background:#eef7f8;color:#087c8b;font-weight:800;font-size:11px;margin-right:8px}
.srEmpty{text-align:center;padding:20px;color:#71808a;font-size:12px}
.srNote{margin-top:10px;font-size:11px;color:#81909a}`;
 document.head.appendChild(s);
}

/* El periodo del panel (año + mes) traducido a un intervalo de fechas. */
function rango(year,month){
 const y=Number(year)||new Date().getFullYear();
 if(month==='all'||month===''||month==null){
  return {desde:new Date(y,0,1),hasta:new Date(y,11,31,23,59,59,999)};
 }
 const m=Number(month);
 return {desde:new Date(y,m,1),hasta:new Date(y,m+1,0,23,59,59,999)};
}

function lista(hostId,filas,sub){
 const host=$(hostId);if(!host)return;
 host.innerHTML=filas.length
  ? filas.map((r,i)=>`<div class="srRow"><span><span class="srRank">${i+1}</span><b>${esc(r.name)}</b></span><span>${sub(r)}</span></div>`).join('')
  : '<div class="srEmpty">Sin ventas en este periodo.</div>';
}
function cargando(){
 ['srByQty','srByRevenue'].forEach(id=>{const h=$(id);if(h)h.innerHTML='<div class="srEmpty"><span class="gamaSpin"></span>Cargando…</div>'});
}
function error(txt){
 ['srByQty','srByRevenue'].forEach(id=>{const h=$(id);if(h)h.innerHTML='<div class="srEmpty">'+esc(txt)+'</div>'});
 const m=$('dashMargin');if(m)m.textContent='—';
}

/* Rellena los paneles de análisis del Panel de control para el periodo dado.
   Lo llama renderDashboard(); si la pantalla no está montada, no hace nada. */
async function render(year,month){
 if(!$('srByQty'))return;
 style();
 if(!canView()){error('Tu perfil no puede ver el análisis de ventas.');return}
 if(!C()){error('Sin conexión con GAMA Cloud.');return}

 const mio=++peticion;
 cargando();
 try{
  const {desde,hasta}=rango(year,month);
  const pr=await C().list('products',{select:'id,name,price_a,active',order:'name',ascending:true});
  if(pr.error)throw pr.error;
  const productos=new Map((pr.data||[]).map(p=>[String(p.id),p]));

  const ir=await C().list('invoices',{select:'id',order:'issue_date',ascending:false,
    gte:{issue_date:desde.toISOString()},lte:{issue_date:hasta.toISOString()}});
  if(ir.error)throw ir.error;
  const ids=(ir.data||[]).map(i=>i.id);

  let lineas=[];
  if(ids.length){
   const lr=await C().list('invoice_lines',{in:{invoice_id:ids}});
   if(lr.error)throw lr.error;
   lineas=lr.data||[];
  }
  // Otro repintado llegó después: el suyo manda.
  if(mio!==peticion)return;

  const porProducto=new Map();
  let margenTotal=0;
  lineas.forEach(l=>{
   const p=productos.get(String(l.product_id));
   const qty=Number(l.quantity||0),precio=Number(l.unit_price||0),ingreso=qty*precio;
   const costo=p?Number(p.price_a||0):0,margen=(precio-costo)*qty;
   margenTotal+=margen;
   const k=String(l.product_id);
   if(!porProducto.has(k))porProducto.set(k,{name:p?.name||'Producto eliminado',qty:0,revenue:0,margin:0});
   const r=porProducto.get(k);r.qty+=qty;r.revenue+=ingreso;r.margin+=margen;
  });

  const m=$('dashMargin');if(m)m.textContent=money(margenTotal);
  const filas=[...porProducto.values()];
  lista('srByQty',[...filas].sort((a,b)=>b.qty-a.qty).slice(0,10),r=>`${r.qty} uds · ${money(r.revenue)}`);
  lista('srByRevenue',[...filas].sort((a,b)=>b.revenue-a.revenue).slice(0,10),r=>`${money(r.revenue)} · margen ${money(r.margin)}`);
 }catch(e){
  if(mio!==peticion)return;
  console.error('[GAMA Análisis de ventas]',e);
  error('No se pudo cargar el análisis: '+(e.message||e));
 }
}

window.GamaSalesReport={render};
})();
