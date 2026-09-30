/* Small private-session portrait cache. Photos remain protected by the existing HR RLS. */
(function(){
'use strict';
if(window.GamaEmployeePhotos)return;
const MAX_DATA=120000;
let uid=null,photo='',requestedUid=null,requestVersion=0,sessionVersion=0;
const valid=value=>typeof value==='string'&&value.length<=MAX_DATA&&/^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/]+={0,2}$/.test(value)?value:'';
const initials=name=>String(name||'').trim().split(/\s+/).filter(Boolean).map(x=>[...x][0]).slice(0,2).join('').toUpperCase();
const labels={es:{label:'Foto del empleado',help:'JPG, PNG o WebP. Se recorta al centro y se comprime automáticamente.',remove:'Quitar foto',type:'Elige una imagen JPG, PNG o WebP.',size:'La imagen no debe superar 10 MB.',invalid:'No se pudo leer esta imagen.'},fr:{label:'Photo de l’employé',help:'JPG, PNG ou WebP. Recadrage centré et compression automatiques.',remove:'Retirer la photo',type:'Choisis une image JPG, PNG ou WebP.',size:'L’image ne doit pas dépasser 10 Mo.',invalid:'Impossible de lire cette image.'},en:{label:'Employee photo',help:'JPG, PNG or WebP. Automatically cropped to the centre and compressed.',remove:'Remove photo',type:'Choose a JPG, PNG or WebP image.',size:'The image must be no larger than 10 MB.',invalid:'This image could not be read.'}};
const t=k=>(labels[window.GamaI18n?.language]||labels.es)[k];
function paint(el,name,value){
 if(!el)return;
 const src=valid(value),text=initials(name),key=src+'|'+text;
 if(el.dataset.portraitKey===key)return;
 el.dataset.portraitKey=key;el.replaceChildren();
 if(!src){el.textContent=text;return}
 const img=document.createElement('img');img.alt='';img.decoding='async';
 img.onerror=()=>{if(el.contains(img)){el.replaceChildren();el.textContent=text}};
 img.src=src;el.append(img);
}
function render(){paint(document.getElementById('arcAvatar'),document.getElementById('arcUserName')?.textContent||'',photo)}
async function refresh(force=false){
 const epoch=sessionVersion,cloud=window.GamaCloud;if(!cloud)return;
 try{
  const result=await cloud.getSession();if(epoch!==sessionVersion)return;
  const next=result?.data?.session?.user?.id||null;
  if(next!==uid){uid=next;photo='';requestedUid=null;requestVersion++;render()}
  if(!uid||(requestedUid===uid&&!force))return;
  const request=++requestVersion,owner=uid;requestedUid=uid;
  const r=await cloud.list('hr_employees',{select:'id,profile_id,photo_data',eq:{profile_id:uid,active:true},limit:1});
  if(request!==requestVersion||epoch!==sessionVersion||owner!==uid)return;
  photo=r.error?'':valid(r.data?.[0]?.photo_data);render();
 }catch(_){/* Keep initials on network/schema errors; the shell must stay usable. */}
}
async function compress(file){
 if(!/^image\/(jpeg|png|webp)$/.test(file?.type||''))throw Error(t('type'));
 if(file.size>10*1024*1024)throw Error(t('size'));
 const url=URL.createObjectURL(file);
 try{
  const img=await new Promise((resolve,reject)=>{const i=new Image();i.onload=()=>resolve(i);i.onerror=()=>reject(Error(t('invalid')));i.src=url});
  const side=Math.min(img.naturalWidth,img.naturalHeight);if(!side)throw Error(t('invalid'));
  const canvas=document.createElement('canvas');canvas.width=256;canvas.height=256;
  const ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,256,256);
  ctx.drawImage(img,(img.naturalWidth-side)/2,(img.naturalHeight-side)/2,side,side,0,0,256,256);
  let data=canvas.toDataURL('image/jpeg',.82);if(data.length>MAX_DATA)data=canvas.toDataURL('image/jpeg',.6);
  if(!valid(data))throw Error(t('size'));return data;
 }finally{URL.revokeObjectURL(url)}
}
window.GamaEmployeePhotos={valid,initials,paint,refresh,compress,t,render};
window.addEventListener('gama:auth-change',e=>{
 sessionVersion++;requestVersion++;requestedUid=null;
 if(e.detail?.event==='SIGNED_OUT'||(e.detail?.session?.user?.id&&e.detail.session.user.id!==uid)){uid=null;photo='';render()}
 if(e.detail?.event!=='SIGNED_OUT')refresh();
});
window.addEventListener('gama:profile-ready',()=>refresh());
window.addEventListener('gama:employee-photo-change',()=>refresh(true));
window.GamaCloudReady?.then(()=>refresh());
})();
