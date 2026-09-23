import * as ui from '../ui/components.js';
import * as data from '../data/service.js';
import {legacyProduct} from '../domain/entities.js';
import {escapeHtml as esc,translate as t,format} from '../domain/format.js';
const views=new Map();
const $=id=>document.getElementById(id);
const directoryColumns={
 products:[
  {label:'Foto',decorative:true,html:p=>window.gamaPhotoCell?.(legacyProduct({id:p.id,name:p.name,has_photo:p.hasPhoto}))||''},
  {key:'barcode',label:'Código',sort:'barcode'},{key:'name',label:'Producto',sort:'name'},{key:'brand',label:'Marca'},
  {key:'stock',label:'Stock',numeric:true,sort:'stock'},{label:'Precio compra',value:p=>format.money(p.purchasePrice),numeric:true},
  {label:'Venta A',value:p=>format.money(p.salePrice),numeric:true,sort:'sale_price'},{label:'Venta B',value:p=>format.money(p.salePriceB),numeric:true},
  {label:'IVA',value:p=>format.number(p.taxRate)+' %'},{key:'location',label:'Ubicación'},
  {label:'Proveedor',value:p=>(window.ArcEntities.suppliersCache||[]).find(s=>s.id===p.supplierId)?.name||'—'},
  {label:'Acciones',actions:true,html:p=>ui.button({label:t('Unidades e historial'),attrs:'data-product-controls="'+esc(p.id)+'"'})+' '+(p.active?ui.button({label:t('✏️ Editar'),attrs:'data-edit="'+esc(p.id)+'"'})+' '+ui.button({label:t('🗄️ Archivar'),variant:'danger',attrs:'data-archive="'+esc(p.id)+'"'}):ui.button({label:t('♻️ Restaurar'),attrs:'data-restore="'+esc(p.id)+'"'})+' '+ui.button({label:t('🗑️ Borrar definitivamente'),variant:'danger',attrs:'data-delete="'+esc(p.id)+'"'}))}
 ]
};
/** Product directory. Customers and suppliers are listed together in Contactos (gama-contacts.js). */
export function directory(entity,filter='') {
  if(entity!=='products')return;
  if(!window.gamaAccessAllowed?.('products')){views.get(entity)?.dispose();views.delete(entity);return;}
  const key='products',host=$('productsTable');if(!host)return;
  const prior=views.get(entity);
  if(prior?.host===host&&host.firstElementChild){prior.refresh(filter);return;}
  prior?.dispose();host.innerHTML='<div data-arc-archive></div><div data-arc-directory></div>';
  let rows=new Map(),lastFilter=filter,lastArchived;
  const grid=ui.dataTable(host.querySelector('[data-arc-directory]'),{columns:directoryColumns[entity],initial:{search:filter},source:async request=>{
    const archived=window.GamaArchive.mode(key)==='archived';lastArchived=archived;
    const result=await data.page(entity,{...request,archived});rows=new Map(result.items.map(x=>[x.id,x]));
    const other=await window.GamaCloud.list(entity,{select:'id',count:'exact',head:true,eq:{active:archived}});if(other.error)throw other.error;
    host.querySelector('[data-arc-archive]').innerHTML=window.GamaArchive.tabs(key,archived?other.count:result.total,archived?result.total:other.count);
    return result;
  },actions:{'data-product-controls':id=>window.ArchitectProductsControls.open(id),'data-edit':id=>{const row=rows.get(id);if(row)window.editProduct(row.barcode,row.id);},'data-archive':id=>{const row=rows.get(id);if(row)window.deleteProduct(row.barcode);},'data-restore':id=>window.restoreProduct(id),'data-delete':id=>window.purgeProduct(id)}});
  const onChange=e=>{if(e.detail?.table===entity)grid.refresh();};window.addEventListener('gama:data-change',onChange);
  const view={host,refresh(search){const archived=window.GamaArchive.mode(key)==='archived';const changed=search!==lastFilter||archived!==lastArchived;lastFilter=search;grid.refresh(changed?{page:0,search}:{});},dispose(){grid.dispose();window.removeEventListener('gama:data-change',onChange);}};
  window.GamaArchive.register(key,()=>grid.refresh({page:0}));views.set(entity,view);
}
