/* GAMA V14 — Achats + commandes fournisseurs + réception + stock automatique */
(function(){
  'use strict';
  const MOD='gamaPurchasesV14';
  let orders=[], lines=[], products=[], suppliers=[];
  let loading=false, selectedId=null, draft=[];
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const C=()=>window.GamaCloud;
  const $=id=>document.getElementById(id);
  const sessionRole=()=>{try{return JSON.parse(localStorage.getItem('gama_session_v1')||'{}').role||''}catch(e){return ''}};
  const canOrder=()=>['admin','commercial'].includes(sessionRole());
  const canReceive=()=>['admin','magasinier'].includes(sessionRole());
  const money=n=>new Intl.NumberFormat('fr-FR',{minimumFractionDigits:2,maximumFractionDigits:2}).format(Number(n||0));
  const date=d=>d?new Date(d).toLocaleDateString('fr-FR'):'';
  const roleLabel=r=>r==='admin'?'Administrateur':r==='commercial'?'Commercial':r==='magasinier'?'Magasinier':'Utilisateur';
  const statusLabel=s=>({draft:'Brouillon',sent:'Commandée',partial:'Réception partielle',received:'Réceptionnée',cancelled:'Annulée'}[s]||s);
  const statusClass=s=>({draft:'gp14Draft',sent:'gp14Sent',partial:'gp14Partial',received:'gp14Received',cancelled:'gp14Cancelled'}[s]||'gp14Draft');
  function wait(){if(!window.GamaCloud||!window.GamaCloudReady)return setTimeout(wait,250);window.GamaCloudReady.then(boot).catch(e=>console.warn('[GAMA Achats]',e));}
  function inject(){
    if($('gamaPurchasesV14'))return;
    const s=document.createElement('section');s.id='gamaPurchasesV14';s.innerHTML=`
      <div class="gp14Head card"><div><div class="gp14Kicker">GAMA STOCK MANAGER</div><h2>🛒 Achats</h2><p>Commandes fournisseurs, réceptions et stock en temps réel.</p></div><button class="secondary" id="gp14Refresh">↻ Actualiser</button></div>
      <div class="gp14Kpis">
        <div><span>Commandes</span><b id="gp14KOrders">0</b></div><div><span>À recevoir</span><b id="gp14KToReceive">0</b></div><div><span>Réceptions partielles</span><b id="gp14KPartial">0</b></div><div><span>Réceptionnées</span><b id="gp14KReceived">0</b></div><div><span>Total achats</span><b id="gp14KTotal">0,00 €</b></div>
      </div>
      <div class="gp14Grid">
        <div class="card gp14Form"><div class="gp14Title"><h3>Nouvelle commande fournisseur</h3><span class="gp14Role" id="gp14Role"></span></div>
          <label>Fournisseur *</label><select id="gp14Supplier"><option value="">Sélectionner un fournisseur…</option></select>
          <div class="row"><div><label>Date prévue</label><input id="gp14Expected" type="date"></div><div><label>Référence fournisseur</label><input id="gp14SupplierRef" placeholder="N° de commande fournisseur"></div></div>
          <label>Produit *</label><select id="gp14Product"><option value="">Sélectionner un produit…</option></select>
          <div class="row"><div><label>Quantité</label><input id="gp14Qty" type="number" min="0.01" step="0.01" value="1"></div><div><label>Prix d'achat unitaire</label><input id="gp14Cost" type="number" min="0" step="0.01" value="0"></div></div>
          <button class="secondary gp14Full" id="gp14Add">＋ Ajouter le produit</button>
          <div id="gp14Draft" class="gp14DraftBox"></div>
          <label>Notes</label><textarea id="gp14Notes" placeholder="Transport, conditions, informations fournisseur…"></textarea>
          <div class="actions"><button class="secondary" id="gp14Clear">Effacer</button><button class="primary" id="gp14Save">Créer la commande</button></div>
          <div id="gp14Msg" class="gp14Msg"></div>
        </div>
        <div class="card"><div class="gp14ListHead"><div><h3>Commandes fournisseurs</h3><small>Le stock n'augmente qu'au moment de la réception.</small></div><select id="gp14Filter"><option value="all">Toutes</option><option value="draft">Brouillons</option><option value="sent">Commandées</option><option value="partial">Réception partielle</option><option value="received">Réceptionnées</option><option value="cancelled">Annulées</option></select></div><div id="gp14Orders"></div></div>
      </div>
      <div class="card gp14Detail" id="gp14Detail" style="display:none"></div>`;
    (document.querySelector('.wrap')||document.body).appendChild(s);style();bind();
  }
  function style(){if($('gp14Css'))return;const s=document.createElement('style');s.id='gp14Css';s.textContent=`
    #gamaPurchasesV14{display:none}.gp14Head{display:flex;justify-content:space-between;align-items:center}.gp14Kicker{font-size:10px;font-weight:850;letter-spacing:1.2px;color:#087c8b}.gp14Head h2{margin:4px 0;font-size:28px}.gp14Head p{margin:0;color:#71808a}.gp14Kpis{display:grid;grid-template-columns:repeat(5,1fr);gap:10px;margin:12px 0}.gp14Kpis>div{background:#fff;border:1px solid #e2e8ec;border-radius:13px;padding:13px}.gp14Kpis span{display:block;color:#71808a;font-size:11px;font-weight:700}.gp14Kpis b{display:block;margin-top:6px;font-size:21px;color:#18324a}.gp14Grid{display:grid;grid-template-columns:.9fr 1.3fr;gap:12px}.gp14Form{position:relative}.gp14Title,.gp14ListHead,.gp14DetailHead{display:flex;justify-content:space-between;align-items:center;gap:10px}.gp14Title h3,.gp14ListHead h3{margin:0}.gp14Role{font-size:10px;padding:5px 8px;border-radius:999px;background:#eef7f8;color:#087c8b;font-weight:800}.gp14Full{width:100%;margin-bottom:10px}.gp14DraftBox{margin:8px 0}.gp14DraftLine{display:grid;grid-template-columns:1fr 65px 90px 30px;gap:7px;align-items:center;border-bottom:1px solid #edf1f2;padding:8px 0;font-size:12px}.gp14DraftLine small{display:block;color:#71808a}.gp14X{padding:5px;background:#fff0ec;color:#c94f45}.gp14ListHead small{display:block;color:#71808a;margin-top:3px}.gp14ListHead select{width:auto;min-width:150px;padding:9px}.gp14Order{border:1px solid #e2e8ec;border-radius:12px;padding:12px;margin-top:9px;cursor:pointer}.gp14Order:hover{border-color:#087c8b}.gp14OrderTop{display:flex;justify-content:space-between;gap:10px}.gp14OrderTop b{color:#18324a}.gp14Status{display:inline-block;padding:4px 8px;border-radius:999px;font-size:10px;font-weight:800}.gp14Draft{background:#eef3f4;color:#63717c}.gp14Sent{background:#e8f2ff;color:#2362a5}.gp14Partial{background:#fff6df;color:#a16b00}.gp14Received{background:#e7f6f0;color:#138a69}.gp14Cancelled{background:#fff0ec;color:#c94f45}.gp14Meta{display:flex;justify-content:space-between;gap:8px;color:#71808a;font-size:11px;margin-top:6px}.gp14Meta b{color:#18324a}.gp14Detail{margin-top:12px}.gp14DetailHead h3{margin:0}.gp14ReceiveLine{display:grid;grid-template-columns:1.6fr 85px 95px 105px;gap:8px;align-items:center;border-bottom:1px solid #edf1f2;padding:11px 0}.gp14ReceiveLine small{display:block;color:#71808a}.gp14ReceiveLine input{padding:8px}.gp14Locked{padding:10px;border-radius:9px;background:#f7f9fa;color:#71808a;font-size:12px}.gp14Actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:12px}.gp14Msg{margin-top:9px;font-size:12px;color:#c94f45}.gp14Ok{color:#138a69}.gp14Info{background:#f1f8f9;border-left:4px solid #087c8b;padding:10px;border-radius:8px;font-size:12px;margin:10px 0}.gp14Warn{background:#fff6df;border-left:4px solid #b66a18;padding:10px;border-radius:8px;font-size:12px;margin:10px 0}@media(max-width:800px){.gp14Grid{grid-template-columns:1fr}.gp14Kpis{grid-template-columns:1fr 1fr}.gp14Kpis>div:last-child{grid-column:span 2}.gp14Head{align-items:flex-start}.gp14Head h2{font-size:23px}.gp14OrderTop,.gp14Meta{flex-direction:column}.gp14ReceiveLine{grid-template-columns:1fr 75px 85px 95px}.gp14ListHead{align-items:flex-start;flex-direction:column}.gp14ListHead select{width:100%}}`;document.head.appendChild(s)}
  function bind(){
    $('gp14Refresh').onclick=load;$('gp14Filter').onchange=renderOrders;$('gp14Add').onclick=addDraft;$('gp14Save').onclick=saveOrder;$('gp14Clear').onclick=clearForm;$('gp14Product').onchange=()=>{const p=products.find(x=>x.id===$('gp14Product').value);if(p)$('gp14Cost').value=Number(p.purchase_price||0).toFixed(2)};
  }
  function show(){inject();document.querySelectorAll('section').forEach(s=>{s.classList.remove('active');if(s.id==='gamaPurchasesV14')s.style.display='block';else if(s.id!=='gama-excel-import-section')s.style.display='none'});const sec=$('gamaPurchasesV14');sec.classList.add('active');document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));const tab=$('gamaPurchasesV14Tab');if(tab)tab.classList.add('active');load();window.scrollTo({top:0,behavior:'smooth'})}
  window.gamaShowPurchases=show;
  function installTab(){const host=document.querySelector('.tabs');if(!host||$('gamaPurchasesV14Tab'))return;const b=document.createElement('button');b.id='gamaPurchasesV14Tab';b.type='button';b.className='tab';b.innerHTML='🛒<span>Achats</span>';b.onclick=show;host.appendChild(b)}
  function populate(){
    const ss=$('gp14Supplier'),ps=$('gp14Product');if(!ss||!ps)return;
    ss.innerHTML='<option value="">Sélectionner un fournisseur…</option>'+suppliers.filter(x=>x.active!==false).map(x=>`<option value="${x.id}">${esc(x.name)}${x.tax_id?' — '+esc(x.tax_id):''}</option>`).join('');
    ps.innerHTML='<option value="">Sélectionner un produit…</option>'+products.filter(x=>x.active!==false).map(x=>`<option value="${x.id}">${esc(x.name)}${x.barcode?' — '+esc(x.barcode):''}</option>`).join('');
    $('gp14Role').textContent=roleLabel(sessionRole());
  }
  function addDraft(){
    if(!canOrder())return alert('Votre profil ne peut pas créer de commandes fournisseurs.');
    const pid=$('gp14Product').value,q=Number($('gp14Qty').value),cost=Number($('gp14Cost').value);if(!pid||!Number.isFinite(q)||q<=0||!Number.isFinite(cost)||cost<0)return alert('Produit, quantité et prix d’achat sont obligatoires.');
    const p=products.find(x=>x.id===pid);const old=draft.find(x=>x.product_id===pid);if(old){old.quantity+=q;old.unit_cost=cost}else draft.push({product_id:pid,quantity:q,unit_cost:cost});renderDraft();$('gp14Product').value='';$('gp14Qty').value='1';$('gp14Cost').value=p?Number(p.purchase_price||0).toFixed(2):'0';
  }
  function renderDraft(){const h=$('gp14Draft');if(!draft.length){h.innerHTML='<div class="muted">Aucun produit dans la commande.</div>';return}h.innerHTML=draft.map((l,i)=>{const p=products.find(x=>x.id===l.product_id);return `<div class="gp14DraftLine"><div><b>${esc(p?.name||'Produit')}</b><small>${esc(p?.reference||p?.barcode||'')}</small></div><span>${l.quantity}</span><span>${money(l.quantity*l.unit_cost)} €</span><button class="gp14X" onclick="window.gamaRemovePurchaseLineV14(${i})">×</button></div>`}).join('')}
  window.gamaRemovePurchaseLineV14=i=>{draft.splice(i,1);renderDraft()};
  function nextNumber(){let max=0;orders.forEach(o=>{const m=String(o.order_number||'').match(/(\d+)$/);if(m)max=Math.max(max,Number(m[1]))});return 'OC-'+String(max+1).padStart(6,'0')}
  async function saveOrder(){
    if(!canOrder())return alert('Votre profil ne peut pas créer de commandes fournisseurs.');
    const sid=$('gp14Supplier').value;if(!sid)return alert('Sélectionnez un fournisseur.');if(!draft.length)return alert('Ajoutez au moins un produit.');
    const subtotal=draft.reduce((a,l)=>a+l.quantity*l.unit_cost,0);const session=(await C().getSession()).data?.session;const row={supplier_id:sid,order_number:nextNumber(),order_date:new Date().toISOString(),expected_date:$('gp14Expected').value?new Date($('gp14Expected').value+'T12:00:00').toISOString():null,status:'draft',notes:[$('gp14SupplierRef').value.trim()?('Réf. fournisseur: '+$('gp14SupplierRef').value.trim()):'', $('gp14Notes').value.trim()].filter(Boolean).join(' | ')||null,subtotal,tax:0,total:subtotal,created_by:session?.user?.id||null};
    const r=await C().insert('purchase_orders',row);if(r.error)return msg(r.error.message);const po=r.data;if(!po)return msg('La commande n’a pas pu être créée.');
    for(const l of draft){const x=await C().insert('purchase_order_lines',{purchase_order_id:po.id,product_id:l.product_id,quantity:l.quantity,received_quantity:0,unit_cost:l.unit_cost,tax_rate:0,line_total:l.quantity*l.unit_cost});if(x.error){await C().remove('purchase_orders',po.id);return msg('Erreur sur une ligne: '+x.error.message)}}
    msg('Commande fournisseur créée. Le stock reste inchangé jusqu’à la réception.',true);clearForm();await load();
  }
  function msg(t,ok){const m=$('gp14Msg');m.textContent=t;m.className='gp14Msg '+(ok?'gp14Ok':'')}
  function clearForm(){$('gp14Supplier').value='';$('gp14Expected').value='';$('gp14SupplierRef').value='';$('gp14Product').value='';$('gp14Qty').value='1';$('gp14Cost').value='0';$('gp14Notes').value='';draft=[];renderDraft();msg('')}
  async function load(){
    if(loading||!C())return;loading=true;try{const [a,b,c,d]=await Promise.all([C().list('purchase_orders',{order:'created_at',ascending:false}),C().list('purchase_order_lines',{order:'created_at',ascending:true}),C().list('products',{order:'name',ascending:true}),C().list('suppliers',{order:'name',ascending:true})]);const e=a.error||b.error||c.error||d.error;if(e)throw e;orders=a.data||[];lines=b.data||[];products=c.data||[];suppliers=d.data||[];populate();renderDraft();renderKpis();renderOrders();if(selectedId)openOrder(selectedId)}catch(e){msg('Impossible de charger les achats: '+(e.message||e))}finally{loading=false}}
  function renderKpis(){const toReceive=orders.filter(o=>['sent','partial'].includes(o.status)).length;const total=orders.reduce((a,o)=>a+Number(o.total||0),0);$('gp14KOrders').textContent=orders.length;$('gp14KToReceive').textContent=toReceive;$('gp14KPartial').textContent=orders.filter(o=>o.status==='partial').length;$('gp14KReceived').textContent=orders.filter(o=>o.status==='received').length;$('gp14KTotal').textContent=money(total)+' €'}
  function supplierName(id){return suppliers.find(s=>s.id===id)?.name||'Fournisseur'}
  function renderOrders(){const f=$('gp14Filter').value,h=$('gp14Orders');const list=orders.filter(o=>f==='all'||o.status===f);if(!list.length){h.innerHTML='<div class="muted" style="padding:15px">Aucune commande pour ce filtre.</div>';return}h.innerHTML=list.map(o=>`<div class="gp14Order" onclick="window.gamaOpenPurchaseV14('${o.id}')"><div class="gp14OrderTop"><b>${esc(o.order_number)}</b><span class="gp14Status ${statusClass(o.status)}">${statusLabel(o.status)}</span></div><div>${esc(supplierName(o.supplier_id))}</div><div class="gp14Meta"><span>${date(o.order_date)}</span><span>${o.expected_date?'Prévue: '+date(o.expected_date):'Pas de date prévue'}</span><b>${money(o.total)} €</b></div></div>`).join('')}
  window.gamaOpenPurchaseV14=openOrder;
  async function openOrder(id){selectedId=id;const o=orders.find(x=>x.id===id);if(!o)return;const ls=lines.filter(x=>x.purchase_order_id===id);const d=$('gp14Detail');d.style.display='block';const canRecv=canReceive()&&['sent','partial'].includes(o.status);const allReceived=ls.length>0&&ls.every(l=>Number(l.received_quantity)>=Number(l.quantity));d.innerHTML=`<div class="gp14DetailHead"><div><h3>Commande ${esc(o.order_number)}</h3><div class="muted">${esc(supplierName(o.supplier_id))} · ${statusLabel(o.status)}</div></div><button class="secondary" onclick="window.gamaClosePurchaseV14()">Fermer</button></div><div class="gp14Info">Une réception validée crée automatiquement un mouvement <b>Entrée</b>, augmente le stock et enregistre le prix d’achat de la ligne.</div>${ls.map(l=>{const p=products.find(x=>x.id===l.product_id);const pending=Math.max(0,Number(l.quantity)-Number(l.received_quantity));return `<div class="gp14ReceiveLine"><div><b>${esc(p?.name||'Produit')}</b><small>Commandé: ${l.quantity} · Reçu: ${l.received_quantity} · Reste: ${pending}</small></div><span>${money(l.unit_cost)} €</span><span>${pending?'<input id="gp14Recv_'+l.id+'" type="number" min="0" max="'+pending+'" step="0.01" value="'+pending+'" '+(canRecv?'':'disabled')+'>':'<span class="gp14Status gp14Received">Complet</span>'}</span><span>${money(Number(l.quantity)*Number(l.unit_cost))} €</span></div>`}).join('')}${o.notes?`<div class="gp14Warn">${esc(o.notes)}</div>`:''}<label>Commentaire de réception</label><textarea id="gp14ReceiveComment" placeholder="Bon de livraison, lot, transport, anomalie…" ${canRecv?'':'disabled'}></textarea><div class="gp14Actions">${o.status==='draft'&&canOrder()?`<button class="primary" onclick="window.gamaSendPurchaseV14('${o.id}')">✓ Marquer comme commandée</button>`:''}${canRecv?`<button class="success" onclick="window.gamaReceivePurchaseV14('${o.id}')">📦 Enregistrer la réception</button>`:''}${o.status==='sent'&&canOrder()?`<button class="danger" onclick="window.gamaCancelPurchaseV14('${o.id}')">Annuler la commande</button>`:''}${allReceived?'<span class="gp14Locked">Toutes les quantités ont déjà été réceptionnées.</span>':''}</div><div id="gp14DetailMsg" class="gp14Msg"></div>`}
  window.gamaClosePurchaseV14=()=>{selectedId=null;$('gp14Detail').style.display='none'};
  async function sendOrder(id){if(!canOrder())return alert('Votre profil ne peut pas modifier le statut des commandes.');const o=orders.find(x=>x.id===id);if(!o||o.status!=='draft')return;const r=await C().update('purchase_orders',id,{status:'sent',updated_at:new Date().toISOString()});if(r.error)return detailMsg(r.error.message);await load()}
  window.gamaSendPurchaseV14=sendOrder;
  async function cancelOrder(id){if(!canOrder())return alert('Votre profil ne peut pas annuler les commandes.');if(!confirm('Annuler cette commande fournisseur ?'))return;const o=orders.find(x=>x.id===id);if(!o||o.status!=='sent')return;const r=await C().update('purchase_orders',id,{status:'cancelled',updated_at:new Date().toISOString()});if(r.error)return detailMsg(r.error.message);await load()}
  window.gamaCancelPurchaseV14=cancelOrder;
  function detailMsg(t,ok){const m=$('gp14DetailMsg');if(!m)return;m.textContent=t;m.className='gp14Msg '+(ok?'gp14Ok':'')}
  async function receive(id){
    if(!canReceive())return alert('Votre profil ne peut pas réceptionner les marchandises.');const o=orders.find(x=>x.id===id);if(!o||!['sent','partial'].includes(o.status))return;
    const ls=lines.filter(x=>x.purchase_order_id===id);const payload=[];for(const l of ls){const pending=Math.max(0,Number(l.quantity)-Number(l.received_quantity));if(!pending)continue;const input=$('gp14Recv_'+l.id);const q=Number(input?.value||0);if(q<0||q>pending)return detailMsg('Une quantité de réception est invalide.');if(q>0)payload.push({line_id:l.id,quantity:q})}
    if(!payload.length)return detailMsg('Saisissez au moins une quantité à réceptionner.');
    const comment=$('gp14ReceiveComment')?.value.trim()||null;const c=C();const r=await c.db().rpc('gama_receive_purchase',{p_purchase_order_id:id,p_lines:payload,p_comment:comment});if(r.error){detailMsg(mapRpcError(r.error.message));return}
    detailMsg('Réception enregistrée : stock mis à jour automatiquement.',true);await load();
  }
  window.gamaReceivePurchaseV14=receive;
  function mapRpcError(e){const m=String(e||'');if(m.includes('RECEIPT_EXCEEDS_ORDERED'))return 'La quantité reçue dépasse la quantité commandée.';if(m.includes('PURCHASE_ORDER_CANCELLED'))return 'Cette commande est annulée.';if(m.includes('FORBIDDEN'))return 'Votre profil n’a pas le droit de réceptionner.';if(m.includes('PURCHASE_ORDER_NOT_FOUND'))return 'Commande introuvable.';return 'Réception impossible : '+m}
  function subscribe(){['purchase_orders','purchase_order_lines','stock_movements','products'].forEach(t=>{try{C().subscribe(t,()=>{if(!loading)load()})}catch(e){}})}
  async function boot(){if(window[MOD])return;window[MOD]=true;try{inject();installTab();await load();subscribe()}catch(e){console.warn('[GAMA Achats V14]',e)}}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',wait,{once:true});else wait();
})();