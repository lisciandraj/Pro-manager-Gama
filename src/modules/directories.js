import * as ui from '../ui/components.js';
import * as data from '../data/service.js';
import {supplierFields,supplierToRow,legacyProduct} from '../domain/entities.js';
import {escapeHtml as esc,translate as t,format,errorMessage} from '../domain/format.js';
const views=new Map();
const $=id=>document.getElementById(id);
const call=async promise=>{const r=await promise;if(r.error)throw r.error;return r.data;};
export function suppliers(host) {
  views.get('suppliers')?.dispose();
  host.innerHTML=`<div class="gamaPMGrid"><div class="arcPanel gamaPMForm"><h3 id="supFormTitle">${esc(t('Nuevo proveedor'))}</h3><form id="supForm" class="arcForm"><div class="arcFormGrid">${supplierFields.map(field=>ui.field(field)).join('')}</div>${ui.toolbar(ui.button({id:'supSave',type:'submit',variant:'primary',label:t('＋ Guardar proveedor')})+ui.button({id:'supClear',label:t('Limpiar')}))}<p id="supMsg" role="alert" class="arcFormError"></p></form></div><div class="arcPanel gamaPMForm"><h3>${esc(t('Proveedores registrados'))}</h3>${ui.field({id:'supSearch',type:'search',label:'Buscar por nombre, ciudad, contacto...'})}<div id="supList"><div id="supArchive"></div><div id="supDataTable"></div></div></div></div>`;
  let editing=null,rows=new Map();
  const form=$('supForm');
  const reset=()=>{editing=null;form.reset();$('supFormTitle').textContent=t('Nuevo proveedor');$('supMsg').textContent='';};
  $('supClear').onclick=reset;
  const columns=[{key:'name',label:'Proveedor',sort:'name'}, {key:'taxId',label:'RUC / identificación',sort:'tax_id'}, {key:'contactName',label:'Persona de contacto'}, {key:'phone',label:'Teléfono'}, {key:'email',label:'Email'}, {key:'city',label:'Ciudad',sort:'city'}, {key:'address',label:'Dirección'}, {key:'notes',label:'Información clave'}, {label:'Acciones',actions:true,html:s=>s.active?ui.button({label:t('✏️ Editar'),attrs:'data-edit="'+esc(s.id)+'"'})+' '+ui.button({label:t('🗄️ Archivar'),variant:'danger',attrs:'data-del="'+esc(s.id)+'"'}):ui.button({label:t('♻️ Restaurar'),attrs:'data-restore="'+esc(s.id)+'"'})+' '+ui.button({label:t('🗑️ Borrar'),variant:'danger',attrs:'data-purge="'+esc(s.id)+'"'})}];
  const refresh=async()=>{data.invalidate('suppliers');await grid.refresh({page:0});window.dispatchEvent(new CustomEvent('gama:data-change',{detail:{table:'suppliers'}}));};
  const mutate=async(id,operation)=>{
    const supplier=rows.get(id);if(!supplier)return;
    if(operation==='archive'&&!window.confirm(t('¿Archivar al proveedor «')+supplier.name+'»?'))return;
    if(operation==='delete'&&!window.confirm(t('¿Borrar definitivamente a «')+supplier.name+'»?'))return;
    try{await call(operation==='delete'?window.GamaCloud.remove('suppliers',id):window.GamaCloud.update('suppliers',id,{active:operation==='restore'}));await refresh();}
    catch(e){$('supMsg').textContent=window.GamaArchive?.friendlyError(e,'supplier')||errorMessage(e);}
  };
  const grid=ui.dataTable($('supDataTable'),{columns,searchInput:$('supSearch'),source:async request=>{
    const archived=window.GamaArchive.mode('suppliersDir')==='archived';
    const result=await data.page('suppliers',{...request,archived});rows=new Map(result.items.map(s=>[s.id,s]));
    const count=await window.GamaCloud.list('suppliers',{select:'id',count:'exact',head:true,eq:{active:archived}});if(count.error)throw count.error;
    $('supArchive').innerHTML=window.GamaArchive.tabs('suppliersDir',archived?count.count:result.total,archived?result.total:count.count);
    return result;
  },actions:{'data-del':id=>mutate(id,'archive'),'data-restore':id=>mutate(id,'restore'),'data-purge':id=>mutate(id,'delete'),'data-edit':id=>{editing=rows.get(id);if(!editing)return;for(const f of supplierFields)$(f.id).value=editing[f.key]||'';$('supFormTitle').textContent=t('Editar proveedor');$('supName').focus();}}});
  window.GamaArchive.register('suppliersDir',()=>grid.refresh({page:0}));
  const formApi=ui.bindForm(form,async()=>{
    const value=Object.fromEntries(supplierFields.map(f=>[f.key,$(f.id).value.trim()]));
    if(!value.name)throw Error(t('El nombre del proveedor es obligatorio.'));
    const payload=supplierToRow({...editing,...value,active:editing?.active!==false});
    // Country fields are not on this form; leave their database defaults intact.
    if(!editing)for(const key of ['country','province','postal_code'])delete payload[key];
    await call(editing?window.GamaCloud.update('suppliers',editing.id,payload):window.GamaCloud.insert('suppliers',payload));reset();await refresh();
  });
  const view={dispose(){grid.dispose();formApi.dispose();}};views.set('suppliers',view);ui.mount(host);return()=>view.dispose();
}
const directoryColumns={
 products:[
  {label:'Foto',decorative:true,html:p=>window.gamaPhotoCell?.(legacyProduct({id:p.id,name:p.name,has_photo:p.hasPhoto}))||''},
  {key:'barcode',label:'Código',sort:'barcode'},{key:'name',label:'Producto',sort:'name'},{key:'brand',label:'Marca'},
  {key:'stock',label:'Stock',numeric:true,sort:'stock'},{label:'Precio compra',value:p=>format.money(p.purchasePrice),numeric:true},
  {label:'Venta A',value:p=>format.money(p.salePrice),numeric:true,sort:'sale_price'},{label:'Venta B',value:p=>format.money(p.salePriceB),numeric:true},
  {label:'IVA',value:p=>format.number(p.taxRate)+' %'},{key:'location',label:'Ubicación'},
  {label:'Proveedor',value:p=>(window.ArcEntities.suppliersCache||[]).find(s=>s.id===p.supplierId)?.name||'—'},
  {label:'Acciones',actions:true,html:p=>p.active?ui.button({label:t('✏️ Editar'),attrs:'data-edit="'+esc(p.id)+'"'})+' '+ui.button({label:t('🗄️ Archivar'),variant:'danger',attrs:'data-archive="'+esc(p.id)+'"'}):ui.button({label:t('♻️ Restaurar'),attrs:'data-restore="'+esc(p.id)+'"'})+' '+ui.button({label:t('🗑️ Borrar definitivamente'),variant:'danger',attrs:'data-delete="'+esc(p.id)+'"'})}
 ],
 customers:[{key:'name',label:'Cliente',sort:'name'},{key:'taxId',label:'Identificación',sort:'identification'},{key:'category',label:'Categoría'},{key:'address',label:'Dirección'},{key:'city',label:'Ciudad'},{key:'phone',label:'Teléfono'},{key:'email',label:'Email'},
  {label:'Acciones',actions:true,html:c=>c.active?ui.button({label:t('✏️ Editar'),attrs:'data-edit="'+esc(c.id)+'"'})+' '+ui.button({label:t('🗄️ Archivar'),variant:'danger',attrs:'data-archive="'+esc(c.id)+'"'}):ui.button({label:t('♻️ Restaurar'),attrs:'data-restore="'+esc(c.id)+'"'})+' '+ui.button({label:t('🗑️ Borrar definitivamente'),variant:'danger',attrs:'data-delete="'+esc(c.id)+'"'})}]
};
export function directory(entity,filter='') {
  const key=entity==='customers'?'clients':entity,host=$(key==='clients'?'clientsTable':'productsTable');if(!host)return;
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
  },actions:{'data-edit':id=>{const row=rows.get(id);if(row)entity==='products'?window.editProduct(row.barcode,row.id):window.editClient(row.taxId);},'data-archive':id=>{const row=rows.get(id);if(row)entity==='products'?window.deleteProduct(row.barcode):window.deleteClient(row.taxId);},'data-restore':id=>entity==='products'?window.restoreProduct(id):window.restoreClient(id),'data-delete':id=>entity==='products'?window.purgeProduct(id):window.purgeClient(id)}});
  const onChange=e=>{if(e.detail?.table===entity)grid.refresh();};window.addEventListener('gama:data-change',onChange);
  const view={host,refresh(search){const archived=window.GamaArchive.mode(key)==='archived';const changed=search!==lastFilter||archived!==lastArchived;lastFilter=search;grid.refresh(changed?{page:0,search}:{});},dispose(){grid.dispose();window.removeEventListener('gama:data-change',onChange);}};
  window.GamaArchive.register(key,()=>grid.refresh({page:0}));views.set(entity,view);
}
