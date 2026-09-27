(function(){
'use strict';const U=window.ArcUI,E=U.esc,F=U.field,t=(es,fr,en)=>({fr,en}[window.GamaI18n?.language]||es);let epoch=0;
const lookup=code=>window.ArcData.rpc('gama_barcode_lookup',{p_code:code});
const kind=k=>({item:t('Artículo','Article','Item'),pack:t('Embalaje','Conditionnement','Pack'),parcel:t('Bulto','Colis','Parcel')}[k]||k);
const description=r=>kind(r.kind)+' · '+r.name+(r.kind==='pack'?' · '+r.label+' = '+r.factor+' '+r.base_unit:'');
const dlg=o=>{const d=U.dialog(o);d.dataset.barcodeControls='';d.dataset.giIgnore='';return d};
async function identify(){const d=dlg({title:t('Identificar un código','Identifier un code','Identify a code'),body:F({key:'code',id:'identifyCode',label:t('Código','Code','Code'),required:true})+'<div data-barcode-result role=status></div>',saveLabel:t('Buscar','Chercher','Find'),onSave:async el=>{const r=await lookup(new FormData(el.querySelector('form')).get('code'));dlg({title:kind(r.kind),saveLabel:t('Cerrar','Fermer','Close'),body:'<p><strong>'+E(r.code)+'</strong></p><p>'+E(description(r))+'</p>',onSave:async()=>{}})}});return d}
function encoded(code){
 if(/^\d{13}$/.test(code)){const [bits,label]=window.eanBits(code);return {bits,label}}
 if(code!==code.toUpperCase())throw Error(t('Code 39 requiere mayúsculas. Corrige el código registrado antes de imprimir.','Le Code 39 exige des majuscules. Corrigez le code enregistré avant impression.','Code 39 requires uppercase. Correct the registered code before printing.'));
 return {bits:window.code39Bits(code),label:code};
}
async function batch(){let token=epoch;const d=dlg({title:t('Etiquetas por lote','Étiquettes par lot','Batch labels'),saveLabel:t('Descargar PDF','Télécharger le PDF','Download PDF'),body:`<p>${t('Una línea por código: código; copias. Se identifican artículos, embalajes y bultos. Máximo 200 etiquetas.','Une ligne par code : code ; exemplaires. Les articles, conditionnements et colis sont identifiés. Maximum 200 étiquettes.','One line per code: code; copies. Items, packs and parcels are identified. Maximum 200 labels.')}</p>`+F({key:'codes',label:t('Códigos y copias','Codes et exemplaires','Codes and copies'),type:'textarea',required:true})+F({key:'template',label:t('Formato','Format','Format'),type:'select',value:'small',options:[{id:'small',name:'A4 · 3 × 7 · 63 × 38 mm'},{id:'large',name:'A4 · 2 × 5 · 95 × 54 mm'}],required:true}),onSave:async el=>{
 await window.ArchitectAccessControls.requireAction('barcode','export');
 const data=Object.fromEntries(new FormData(el.querySelector('form'))),requests=data.codes.split(/\r?\n/).map(s=>s.trim()).filter(Boolean).map(s=>{const parts=s.split(';').map(s=>s.trim()),copies=parts.length===1?1:Number(parts[1]);if(parts.length>2||!parts[0]||!Number.isInteger(copies)||copies<1)throw Error(t('Formato inválido: código; copias.','Format invalide : code ; exemplaires.','Invalid format: code; copies.'));return {code:parts[0],copies}});
 if(!requests.length||requests.reduce((n,r)=>n+r.copies,0)>200)throw Error(t('Máximo 200 etiquetas.','Maximum 200 étiquettes.','Maximum 200 labels.'));
 const cache=new Map(),labels=[];for(const row of requests){let item=cache.get(row.code);if(!item){item=await lookup(row.code);cache.set(row.code,item)}const entry={...item,...encoded(item.code)};for(let i=0;i<row.copies;i++)labels.push(entry)}
 if(token!==epoch)throw Error('AUTH_CHANGED');
 const doc=new window.jspdf.jsPDF(),small=data.template==='small',cols=small?3:2,rows=small?7:5,w=small?63:95,h=small?38:54,gap=small?3:4,perPage=cols*rows;
 labels.forEach((r,i)=>{if(i&&i%perPage===0)doc.addPage();const k=i%perPage,x=8+(k%cols)*(w+gap),y=10+Math.floor(k/cols)*h;doc.setTextColor(0);doc.setDrawColor(180);doc.rect(x,y,w,h-2);doc.setFontSize(8);doc.text(doc.splitTextToSize(description(r),w-8).slice(0,2),x+4,y+5);const barY=y+(small?14:20),barH=small?13:20,narrow=(w-10)/r.bits.length;if(narrow<.18)throw Error(t('Código demasiado largo para este formato. Elige una etiqueta mayor.','Code trop long pour ce format. Choisissez une étiquette plus grande.','Code is too long for this format. Choose a larger label.'));doc.setFillColor(0);for(let b=0;b<r.bits.length;b++)if(r.bits[b]==='1')doc.rect(x+5+b*narrow,barY,narrow,barH,'F');doc.setFontSize(8);doc.text(r.label,x+w/2,barY+barH+5,{align:'center'})});
 await window.GamaPdf.save(doc,'architect-labels.pdf');
 }});return d}
// Stock commands share the inventory APIs: no browser-side stock mutation.
const B=(label,attrs='',variant='secondary')=>U.button({label,attrs,variant});
const stockAllowed=()=>window.ArchitectStockControls?.allowed()&&window.gamaAccessAllowed?.('barcode');
let scanGeneration=0;
function mountStock(){
 const section=document.getElementById('barcode');if(!section)return;
 document.getElementById('barcodeStock')?.remove();scanGeneration++;
 if(!stockAllowed())return;
 const host=document.createElement('div');host.id='barcodeStock';host.className='arcPanel card';host.dataset.giIgnore='';section.insertBefore(host,document.getElementById('barcodeType')?.closest('.arcPanel')||null);
 U.render(host,`<h3>${t('Escanear y mover productos','Scanner et déplacer des produits','Scan and move products')}</h3><p>${t('Escanea un artículo o embalaje, indica la cantidad y elige un traslado o un consumo.','Scanne un article ou un conditionnement, saisis la quantité et choisis un transfert ou une consommation.','Scan an item or pack, enter the quantity and choose a transfer or consumption.')}</p><form data-stock-scan><div class="scanner">${F({key:'code',id:'barcodeStockCode',label:t('Código de barras / referencia','Code-barres / référence','Barcode / reference'),required:true,maxLength:180,attrs:'autocomplete="off"'})}${B(t('Escanear','Scanner','Scan'),'data-stock-camera style="align-self:end"')}</div>${U.button({label:t('Buscar producto','Rechercher le produit','Find product'),type:'submit',variant:'primary'})}</form><p data-stock-message role="status"></p><div data-stock-product></div>`);
 const input=host.querySelector('input'),result=host.querySelector('[data-stock-product]'),message=host.querySelector('[data-stock-message]');
 const identity=epoch;let searching=false;
 const alive=token=>host.isConnected&&identity===epoch&&token===scanGeneration&&stockAllowed();
 input.addEventListener('input',()=>{scanGeneration++;result.replaceChildren();message.textContent=''});
 host.querySelector('[data-stock-camera]').onclick=()=>window.startGamaScan('barcodeStockCode');
 input.addEventListener('gama:barcode-scanned',()=>search());
 host.querySelector('form').onsubmit=e=>{e.preventDefault();search()};
 async function search(){
  if(searching||!input.value.trim())return;
  searching=true;const token=++scanGeneration,code=input.value.trim();result.replaceChildren();message.textContent=t('Buscando…','Recherche…','Searching…');
  try{
   const item=await lookup(code);if(!alive(token))return;
   if(!['item','pack'].includes(item.kind))throw Error(t('Este código corresponde a un bulto. Escanea el artículo o su embalaje.','Ce code correspond à un colis. Scanne l’article ou son conditionnement.','This is a parcel code. Scan the item or its pack.'));
   const data=await Promise.all([
    window.ArcData.all('warehouse_locations',{eq:{active:true},order:'code'}),
    window.ArcData.all('warehouses',{eq:{active:true},select:'id,name'}),
    window.ArcData.all('stock_quants',{eq:{product_id:item.product_id},select:'location_id,quantity,reserved_quantity'})
   ]);
   for(const r of data)if(r.error)throw r.error;if(!alive(token))return;
   const [locations,warehouses,quants]=data.map(r=>r.data);
   const available=l=>{const q=quants.find(q=>q.location_id===l.id);return Number(q?.quantity||0)-Number(q?.reserved_quantity||0)};
   const active=locations.filter(l=>warehouses.some(w=>w.id===l.warehouse_id));
   const label=l=>(warehouses.find(w=>w.id===l.warehouse_id)?.name||'')+' · '+l.code+' · '+l.name;
   const sources=active.filter(l=>available(l)>0),factor=Number(item.factor||1);
   if(!Number.isFinite(factor)||factor<=0)throw Error('INVALID_QUANTITY');
   message.textContent=description(item);
   if(!sources.length){message.textContent+=' · '+t('Sin stock disponible.','Aucun stock disponible.','No available stock.');return}
   U.render(result,`<form data-stock-command><div class="arcFormGrid">`+
    F({key:'source',label:t('Origen','Origine','Source'),type:'select',required:true,value:sources.length===1?sources[0].id:'',options:sources.map(l=>({id:l.id,name:label(l)+' · '+available(l)+' '+(item.base_unit||'unit')}))})+
    F({key:'quantity',label:item.kind==='pack'?t('Cantidad de embalajes','Nombre de conditionnements','Number of packs'):t('Cantidad','Quantité','Quantity'),type:'number',required:true,min:.001,max:999999999,step:.001,value:1})+
    F({key:'operation',label:t('Operación','Opération','Operation'),type:'select',required:true,value:'transfer',options:[{id:'transfer',name:t('Transferencia','Transfert','Transfer')},...window.ArchitectStockControls.consumptionKinds().map(([id,name])=>({id,name}))]})+
    F({key:'destination',label:t('Destino: zona / estantería','Destination : zone / étagère','Destination: zone / shelf'),type:'select',required:true})+
    `</div><p data-stock-quantity role="status"></p><p data-stock-error role="alert"></p>${U.button({label:t('Continuar','Continuer','Continue'),type:'submit',variant:'primary'})}</form>`);
   const get=k=>result.querySelector(`[name="${k}"]`),form=result.querySelector('form'),err=result.querySelector('[data-stock-error]');let opening=false;
   function destinations(){const previous=get('destination').value;get('destination').innerHTML='<option value="">—</option>'+active.filter(l=>l.type!=='warehouse'&&l.id!==get('source').value).map(l=>`<option value="${E(l.id)}">${E(label(l))}</option>`).join('');get('destination').value=previous===get('source').value?'':previous;preview()}
   function preview(){const base=Number(get('quantity').value)*factor;result.querySelector('[data-stock-quantity]').textContent=t('Cantidad en unidades de base: ','Quantité en unités de base : ','Quantity in base units: ')+Number(base.toFixed(3))+' '+(item.base_unit||'unit');const transfer=get('operation').value==='transfer';get('destination').closest('label').hidden=!transfer;get('destination').closest('label').style.display=transfer?'':'none';get('destination').disabled=!transfer}
   get('source').onchange=destinations;get('quantity').oninput=preview;get('operation').onchange=preview;destinations();
   form.onsubmit=async e=>{
    e.preventDefault();if(opening||!alive(token))return;err.textContent='';
    try{
     const quantity=Number(get('quantity').value)*factor,source=active.find(l=>l.id===get('source').value),operation=get('operation').value;
     if(!Number.isFinite(quantity)||quantity<=0||quantity>999999999||Math.abs(quantity*1000-Math.round(quantity*1000))>.0001)throw Error(t('Cantidad inválida (máximo tres decimales en unidades de base).','Quantité invalide (trois décimales maximum en unités de base).','Invalid quantity (at most three decimals in base units).'));
     if(!source||quantity>available(source))throw Error(t('Stock disponible insuficiente en el origen.','Stock disponible insuffisant à l’origine.','Insufficient available stock at source.'));
     opening=true;
     const done=outcome=>{if(alive(token)){result.replaceChildren();input.value='';message.textContent=outcome?.status==='pending'?t('Consumo enviado para validación. El stock no ha cambiado.','Consommation envoyée pour validation. Le stock n’a pas changé.','Consumption sent for approval. Stock has not changed.'):t('Operación registrada. Puedes escanear otro producto.','Opération enregistrée. Tu peux scanner un autre produit.','Operation recorded. You can scan another product.');input.focus()}};
     if(operation!=='transfer'){
      const d=await window.ArchitectStockControls.consume({product_id:item.product_id,location_id:source.id,quantity:Number(quantity.toFixed(3)),kind:operation},done);
      if(!alive(token)){d?.close();return}
      d?.addEventListener('close',()=>{opening=false},{once:true});
     }else{
      const destination=active.find(l=>l.id===get('destination').value&&l.id!==source.id);if(!destination)throw Error('LOCATION_NOT_FOUND');
      let committed=false;
      const d=dlg({title:t('Confirmar transferencia','Confirmer le transfert','Confirm transfer'),body:`<p><strong>${E(item.name)}</strong> · ${E(quantity)} ${E(item.base_unit||'unit')}</p><p>${E(label(source))} → ${E(label(destination))}</p>`+F({key:'comment',label:t('Comentario (opcional)','Commentaire (facultatif)','Comment (optional)'),type:'textarea',maxLength:2000}),onSave:async el=>{
       if(!alive(token))throw Error('AUTH_CHANGED');if(committed)return;
       await window.ArcData.rpc('gama_stock_transfer',{p_product_id:item.product_id,p_source_location_id:source.id,p_destination_location_id:destination.id,p_quantity:Number(quantity.toFixed(3)),p_reason:'Transferencia por código de barras',p_comment:String(new FormData(el.querySelector('form')).get('comment')||'').trim()||null});
       committed=true;window.ArcData.invalidate();window.dispatchEvent(new CustomEvent('gama:stock-cloud-change'));done();
      }});d.addEventListener('close',()=>{opening=false},{once:true});
     }
    }catch(e){opening=false;if(alive(token))err.textContent=window.ArcErrors.message(e)}
   };
  }catch(e){if(alive(token))message.textContent=window.ArcErrors.message(e)}finally{searching=false}
 }
}
window.addEventListener('arc:route-change',e=>{if(e.detail?.id==='barcode')mountStock()});
window.addEventListener('gama:language-change',()=>{if(document.getElementById('barcodeStock'))mountStock()});
window.addEventListener('arc:route-leave',e=>{if(e.detail?.id==='barcode'){scanGeneration++;document.getElementById('barcodeStock')?.remove()}});
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;scanGeneration++;document.getElementById('barcodeStock')?.remove()});
window.ArchitectBarcode={lookup,identify,batch,description,mountStock};
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;epoch++;document.querySelectorAll('[data-barcode-controls]').forEach(d=>d.close())});
})();
