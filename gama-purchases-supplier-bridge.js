/* GAMA — bridge legacy/local suppliers into Compras V2 */
(function(){
'use strict';
function looksLikeSupplier(o,forced){
  if(!o||typeof o!=='object'||Array.isArray(o))return false;
  const name=String(o.name||o.nombre||o.razon_social||o.business_name||'').trim();
  if(!name)return false;
  if(o.purchase_price!==undefined||o.sale_price!==undefined||o.barcode!==undefined||o.stock!==undefined)return false;
  if(forced)return true;
  return !!(o.tax_id||o.ruc||o.nif||o.contact_name||o.contacto||o.proveedor||o.supplier||o.company||o.empresa);
}
function normalize(o){return {legacy_id:o.id||null,name:String(o.name||o.nombre||o.razon_social||o.business_name).trim(),tax_id:o.tax_id||o.ruc||o.nif||null,address:o.address||o.direccion||null,city:o.city||o.ciudad||null,province:o.province||o.provincia||null,postal_code:o.postal_code||o.codigo_postal||null,country:o.country||o.pais||null,phone:o.phone||o.telefono||null,email:o.email||null,contact_name:o.contact_name||o.contacto||null,notes:o.notes||o.notas||null,active:o.active!==false};}
function legacySuppliers(){
  const out=[]; const seen=new Set(); const add=(o,forced)=>{if(!looksLikeSupplier(o,forced))return;const s=normalize(o),k=s.name.toLowerCase();if(!seen.has(k)){seen.add(k);out.push(s)}};
  try{
    for(let i=0;i<localStorage.length;i++){
      const key=String(localStorage.key(i)||''), raw=localStorage.getItem(key); if(!raw)continue;
      let v; try{v=JSON.parse(raw)}catch(e){continue}
      const forced=/(supplier|suppliers|proveedor|proveedores|gama_supplier)/i.test(key);
      const arr=Array.isArray(v)?v:(v&&Array.isArray(v.data)?v.data:(v&&Array.isArray(v.suppliers)?v.suppliers:null));
      if(arr)arr.forEach(o=>add(o,forced));
    }
    for(const key of Object.keys(window)){if(!/(supplier|proveedor)/i.test(key))continue;try{const v=window[key];const arr=Array.isArray(v)?v:(v&&Array.isArray(v.data)?v.data:null);if(arr)arr.forEach(o=>add(o,true))}catch(e){}}
  }catch(e){console.warn('[GAMA supplier bridge]',e)}
  return out;
}
async function cloudSupplier(s){
  const C=window.GamaCloud;if(!C)return null;
  try{const r=await C.db();const q=await r.from('suppliers').select('*').eq('name',s.name).limit(1);if(q.data&&q.data[0])return q.data[0];const ins=await C.insert('suppliers',s);if(ins.data)return ins.data}catch(e){console.warn('[GAMA supplier bridge cloud]',e)}
  return null;
}
async function run(){
  const sel=document.getElementById('gp14Supplier');if(!sel)return setTimeout(run,500);
  const legacy=legacySuppliers();
  for(const s of legacy){if(!Array.from(sel.options).some(o=>o.textContent.toLowerCase().startsWith(s.name.toLowerCase()))){const opt=document.createElement('option');opt.value='legacy:'+btoa(unescape(encodeURIComponent(s.name)));opt.textContent=s.name+(s.tax_id?' — '+s.tax_id:'');opt.dataset.legacy=JSON.stringify(s);sel.appendChild(opt)}}
  if(sel.dataset.gamaBridge==='1')return;
  sel.dataset.gamaBridge='1';
  sel.addEventListener('change',async function(){if(!this.value.startsWith('legacy:'))return;const opt=this.options[this.selectedIndex];let s;try{s=JSON.parse(opt.dataset.legacy||'{}')}catch(e){return}const saved=await cloudSupplier(s);if(saved&&saved.id){opt.value=saved.id;opt.dataset.legacy='';this.value=saved.id;this.dispatchEvent(new Event('change',{bubbles:true}))}else alert('No se ha podido sincronizar el proveedor con la nube. Comprueba tu conexión o permisos de Supabase.')});
}
function boot(){run();const mo=new MutationObserver(()=>run());mo.observe(document.body,{childList:true,subtree:true})}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();