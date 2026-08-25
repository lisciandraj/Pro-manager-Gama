/* GAMA phone barcode scanner — V8 */
(function(){
'use strict';
const ZXING_URL='https://unpkg.com/@zxing/browser@0.2.1';
let overlay=null,stream=null,zxingControls=null,scanning=false,targetId='';
const norm=v=>(v||'').replace(/\s+/g,' ').trim().toLowerCase();
function getTarget(id){
 if(id){const e=document.getElementById(id);if(e&&e.tagName==='INPUT')return e;}
 if(targetId){const e=document.getElementById(targetId);if(e&&e.tagName==='INPUT')return e;}
 return document.getElementById('moveBarcode')||document.getElementById('invoiceBarcode')||null;
}
function persistValue(el,value){
 const v=String(value??'').trim();if(!el||!v)return false;
 const setter=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value')?.set;
 const apply=()=>{const cur=document.getElementById(el.id)||el;if(setter)setter.call(cur,v);else cur.value=v;};
 apply();
 try{el.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:v}))}catch(e){el.dispatchEvent(new Event('input',{bubbles:true}))}
 el.dispatchEvent(new Event('change',{bubbles:true}));
 setTimeout(apply,0);setTimeout(apply,100);setTimeout(apply,300);
 try{el.focus({preventScroll:true})}catch(e){try{el.focus()}catch(_) {}}
 return true;
}
function updateInfo(el,code){
 if(typeof window.product!=='function')return;
 try{const p=window.product(code);
  if(el.id==='moveBarcode'){const x=document.getElementById('moveInfo');if(x)x.textContent=p?`${p.name} — stock actual: ${p.stock}`:'Producto no encontrado';}
  if(el.id==='invoiceBarcode'){const x=document.getElementById('invoiceProductInfo');if(x)x.textContent=p?`${p.name} — Precio: $${Number(p.price||0).toFixed(2)} — Stock: ${p.stock}`:'Producto no encontrado';}
 }catch(e){}
}
function fill(code){const el=getTarget(targetId),v=String(code??'').trim();if(!el||!v)return false;const ok=persistValue(el,v);if(ok)updateInfo(el,v);close();return ok;}
function close(){scanning=false;if(zxingControls){try{zxingControls.stop()}catch(e){}zxingControls=null}if(stream){stream.getTracks().forEach(t=>{try{t.stop()}catch(e){}});stream=null}if(overlay){overlay.remove();overlay=null}}
function style(){if(document.getElementById('gamaScannerPhoneStyle'))return;const s=document.createElement('style');s.id='gamaScannerPhoneStyle';s.textContent='.gamaPhoneScanBtn{background:#F47A2A!important;color:#fff!important;border-color:#F47A2A!important}.gamaPhoneScanBtn:active{transform:scale(.98)}#gamaPhoneScanner{position:fixed;inset:0;z-index:100000;background:#08181f;display:flex;flex-direction:column;padding:18px;box-sizing:border-box;color:#fff;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}#gamaPhoneScanner .h{display:flex;align-items:center;justify-content:space-between;margin-bottom:12px}#gamaPhoneScanner .title{font-size:18px;font-weight:800}#gamaPhoneScanner .close{border:0;background:#fff;color:#173246;border-radius:12px;padding:10px 14px;font-weight:800}#gamaPhoneScanner .video{position:relative;flex:1;overflow:hidden;border-radius:18px;background:#000}#gamaPhoneScanner video{width:100%;height:100%;object-fit:cover}#gamaPhoneScanner .frame{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:min(78vw,420px);height:170px;border:3px solid #37c98f;border-radius:18px;box-shadow:0 0 0 9999px rgba(0,0,0,.28)}#gamaPhoneScanner .status{text-align:center;font-size:14px;font-weight:700;padding:14px 6px 6px}';document.head.appendChild(s)}
function loadZXing(){return new Promise((resolve,reject)=>{if(window.ZXingBrowser)return resolve(window.ZXingBrowser);const s=document.createElement('script');s.src=ZXING_URL;s.onload=()=>window.ZXingBrowser?resolve(window.ZXingBrowser):reject(Error('ZXing no disponible'));s.onerror=()=>reject(Error('No se pudo cargar el escáner'));document.head.appendChild(s)})}
async function native(video,status){if(!('BarcodeDetector'in window))return false;let fs=['ean_13','ean_8','upc_a','upc_e','code_128','code_39','code_93','itf','qr_code','data_matrix'];try{const sup=await BarcodeDetector.getSupportedFormats();fs=fs.filter(x=>sup.includes(x));if(!fs.length)return false;const d=new BarcodeDetector({formats:fs});scanning=true;const loop=async()=>{if(!scanning)return;try{if(video.readyState>=2){const r=await d.detect(video);const code=r?.[0]?.rawValue;if(code){fill(code);return}}}catch(e){}requestAnimationFrame(loop)};status.textContent='Apunte la cámara al código de barras';requestAnimationFrame(loop);return true}catch(e){return false}}
async function start(id){
 targetId=id||getTarget()?.id||'';close();style();const el=getTarget(targetId);if(!el)return;targetId=el.id;
 overlay=document.createElement('div');overlay.id='gamaPhoneScanner';overlay.innerHTML='<div class="h"><div class="title">Escanear código de barras</div><button class="close" type="button">Cerrar</button></div><div class="video"><video playsinline muted autoplay></video><div class="frame"></div></div><div class="status">Activando cámara…</div>';document.body.appendChild(overlay);overlay.querySelector('.close').onclick=close;
 const video=overlay.querySelector('video'),status=overlay.querySelector('.status');
 try{if(!navigator.mediaDevices?.getUserMedia)throw Error('camera');stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'},width:{ideal:1280},height:{ideal:720}},audio:false});video.srcObject=stream;await video.play();if(await native(video,status))return;const ZX=await loadZXing();const reader=new ZX.BrowserMultiFormatReader();scanning=true;zxingControls=await reader.decodeFromStream(stream,video,result=>{const code=typeof result==='string'?result:(result?.getText?.()||result?.text||result?.rawValue||'');if(code)fill(code)});status.textContent='Apunte la cámara al código de barras';}catch(e){status.textContent=e?.name==='NotAllowedError'?'Permita el acceso a la cámara en Safari.':'No se pudo activar el lector.'}
}
function scan(id){start(id)}
window.scan=scan;window.startGamaScan=start;
function bind(){style();document.querySelectorAll('button').forEach(b=>{if(!norm(b.textContent).includes('escanear'))return;const input=b.closest('.scanner')?.querySelector('input')||getTarget();if(!input)return;b.classList.add('gamaPhoneScanBtn');b.type='button';if(!b.dataset.gamaScannerBound){b.dataset.gamaScannerBound='1';b.addEventListener('click',e=>{e.preventDefault();e.stopImmediatePropagation();start(input.id)},true)}})}
function boot(){bind();new MutationObserver(()=>bind()).observe(document.body,{subtree:true,childList:true})}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
