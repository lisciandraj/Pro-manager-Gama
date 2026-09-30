/* Precio de venta según la categoría del cliente: A (mayorista) es el precio
   base de la ficha y B el precio al detalle. La categoría C no se resuelve
   aquí: es un precio pactado producto a producto en su tarifa, y quien lo
   tenga cae en este mismo precio A cuando el producto no está en la tarifa. */
window.gamaCategoryPrice=function(p,category){return Number((category==='B'?p&&p.salePriceB:p&&p.price)||0)};
window.gamaQuoteCategory='A';
window.gamaPriceFor=window.gamaPriceFor||function(p){return p?window.gamaCategoryPrice(p,window.gamaQuoteCategory):0};window.gamaHasContractPrice=window.gamaHasContractPrice||function(){return false};
/* Celda de foto. Las listas ya no traen photo_data (1,4 MB por recarga para
   nueve fotos): traen has_photo y aquí se pinta un hueco que GamaPhotos
   rellena en un solo viaje con las fotos de las filas visibles. En modo local,
   sin nube, el producto sí lleva su foto encima y se pinta directamente. */
window.gamaPhotoCell=function(p){
 if(!p)return window.GamaPhotos?window.GamaPhotos.placeholder():'';
 if(p.photo)return '<img class="product-img" loading="lazy" src="'+p.photo+'" alt="">';
 if(p.hasPhoto&&window.GamaPhotos&&p.id){gamaHydratePhotos();return window.GamaPhotos.slot(p.id)}
 return window.GamaPhotos?window.GamaPhotos.placeholder():'';
};
/* Las listas se repintan enteras con innerHTML; se agrupa la hidratación para
   no lanzar una consulta por celda. */
let gamaPhotoTimer=null;
function gamaHydratePhotos(){if(gamaPhotoTimer||!window.GamaPhotos)return;gamaPhotoTimer=setTimeout(()=>{gamaPhotoTimer=null;window.GamaPhotos.hydrate()},0)}
