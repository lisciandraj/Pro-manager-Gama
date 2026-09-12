/* GAMA phone barcode scanner — optimized V10 */
(function(){
'use strict';
const ZXING_URL='https://unpkg.com/@zxing/browser@0.2.1/umd/zxing-browser.min.js';
const ZXING_SRI='sha384-HRtzk9lZgkbSgvUyQrnfC/GxiXZgwaNyD7hC9wcXlsBpDhkS80ISl73juef2FRuf';
let overlay=null,stream=null,zxingControls=null,scanning=false,targetId='',generation=0,pendingTimer=null;
function getTarget(id){const e=id&&document.getElementById(id);if(e&&e.tagName==='INPUT')return e;const t=targetId&&document.getElementById(targetId);if(t&&t.tagName==='INPUT')return t;return document.getElementById('moveBarcode')||document.getElementById('invoiceBarcode')||null}
function persistValue(el,value){const v=String(value??'').trim();if(!el||!v)return false;const setter=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value')?.set;if(setter)setter.call(el,v);else el.value=v;try{el.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:v}))}catch(e){el.dispatchEvent(new Event('input',{bubbles:true}))}el.dispatchEvent(new Event('change',{bubbles:true}));try{el.focus({preventScroll:true})}catch(e){}return true}
function updateInfo(el,code){if(typeof window.product!=='function')return;try{const p=window.product(code);const x=el.id==='moveBarcode'?document.getElementById('moveInfo'):el.id==='invoiceBarcode'?document.getElementById('invoiceProductInfo'):null;if(x)x.textContent=el.id==='moveBarcode'?(p?`${p.name} — stock actual: ${p.stock}`:'Producto no encontrado'):(p?`${p.name} — Precio: $${Number(p.price||0).toFixed(2)} — Stock: ${p.stock}`:'Producto no encontrado')}catch(e){}}
function stopTracks(s){s?.getTracks().forEach(t=>{try{t.stop()}catch(_){}})}
function release(){scanning=false;clearTimeout(pendingTimer);pendingTimer=null;if(zxingControls){try{zxingControls.stop()}catch(_){}zxingControls=null}stopTracks(stream);stream=null;const video=overlay?.querySelector('video');if(video){video.pause();video.srcObject=null}}
function close(){generation++;release();overlay?.remove();overlay=null}
function fill(code){const el=getTarget(targetId),v=String(code??'').trim();if(!el||!v)return false;const ok=persistValue(el,v);if(ok)updateInfo(el,v);close();if(ok)el.dispatchEvent(new CustomEvent('gama:barcode-scanned',{bubbles:true,detail:{code:v}}));return ok}
function style(){if(document.getElementById('gamaScannerPhoneStyle'))return;const s=document.createElement('style');s.id='gamaScannerPhoneStyle';s.textContent='.gamaPhoneScanBtn{background:#F47A2A!important;color:#fff!important;border-color:#F47A2A!important}.gamaPhoneScanBtn:active{transform:scale(.98)}#gamaPhoneScanner{padding-bottom:max(18px,env(safe-area-inset-bottom))!important;position:fixed;inset:0;z-index:100000;background:#08181f;display:flex;flex-direction:column;padding:18px;box-sizing:border-box;color:#fff;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}#gamaPhoneScanner .h{display:flex;align-items:center;justify-content:space-between;margin-bottom:12px}#gamaPhoneScanner .title{font-size:18px;font-weight:800}#gamaPhoneScanner .close{border:0;background:#fff;color:#173246;border-radius:12px;padding:10px 14px;font-weight:800}#gamaPhoneScanner .video{position:relative;flex:1;min-height:80px;overflow:hidden;border-radius:18px;background:#000}#gamaPhoneScanner video{width:100%;height:100%;object-fit:cover}#gamaPhoneScanner .frame{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:min(78vw,420px);height:170px;border:3px solid #37c98f;border-radius:18px;box-shadow:0 0 0 9999px rgba(0,0,0,.28)}#gamaPhoneScanner .recovery{display:flex;gap:8px;flex-wrap:wrap;padding-top:12px}#gamaPhoneScanner .recovery button{flex:1;min-height:44px;font-size:16px}#gamaPhoneScanner .help{font-size:14px;margin:10px 0}#gamaPhoneScanner .status{text-align:center;font-size:14px;font-weight:700;padding:14px 6px 6px}';document.head.appendChild(s)}
let zxingLoad=null;
function loadZXing(){if(window.ZXingBrowser)return Promise.resolve(window.ZXingBrowser);if(zxingLoad)return zxingLoad;zxingLoad=new Promise((resolve,reject)=>{const s=document.createElement('script');const timeout=setTimeout(()=>fail(),12000);function fail(){clearTimeout(timeout);s.remove();zxingLoad=null;reject(Error('No se pudo cargar el lector. Comprueba tu conexión.'))}s.src=ZXING_URL;s.integrity=ZXING_SRI;s.crossOrigin='anonymous';s.onload=()=>{clearTimeout(timeout);if(window.ZXingBrowser)resolve(window.ZXingBrowser);else fail()};s.onerror=fail;document.head.appendChild(s)});return zxingLoad}
async function native(video,status,token){if(!('BarcodeDetector'in window))return false;try{const formats=['ean_13','ean_8','upc_a','upc_e','code_128','code_39','code_93','itf','qr_code','data_matrix'];const supported=await BarcodeDetector.getSupportedFormats();if(token!==generation)return true;const usable=formats.filter(x=>supported.includes(x));if(!usable.length)return false;const d=new BarcodeDetector({formats:usable});scanning=true;const loop=async()=>{if(!scanning||token!==generation)return;try{if(video.readyState>=2){const r=await d.detect(video);if(token!==generation)return;const code=r?.[0]?.rawValue;if(code){fill(code);return}}}catch(_){}if(scanning&&token===generation)requestAnimationFrame(loop)};status.textContent='Apunte la cámara al código de barras';requestAnimationFrame(loop);return true}catch(_){return false}}
async function start(id){
 const requested=id||getTarget()?.id||'';close();targetId=requested;style();const el=getTarget(targetId);if(!el)return;targetId=el.id;
 overlay=document.createElement('div');overlay.id='gamaPhoneScanner';overlay.setAttribute('role','dialog');overlay.setAttribute('aria-label','Escanear código de barras');
 overlay.innerHTML='<div class="h"><div class="title">Escanear código de barras</div><button class="close" type="button">Cerrar</button></div><div class="video"><video playsinline webkit-playsinline muted autoplay></video><div class="frame"></div></div><div class="status" role="status" aria-live="polite">Activando cámara…</div><p class="help" hidden></p><a class="diagnostic" href="./camera-check.html" hidden style="color:#fff;padding:8px 0">Probar cámara fuera del ERP</a><div class="diagnosticCode" hidden style="font-size:12px;overflow-wrap:anywhere"></div><div class="recovery"><button type="button" class="retry">Reintentar cámara</button><button type="button" class="manual">Introducir código</button></div>';
 (el.closest('dialog[open]')||document.body).appendChild(overlay);
 const host=overlay,video=host.querySelector('video'),status=host.querySelector('.status'),help=host.querySelector('.help'),retry=host.querySelector('.retry');
 video.muted=true;video.defaultMuted=true;video.playsInline=true;
 host.querySelector('.close').onclick=close;host.querySelector('.manual').onclick=()=>{close();el.focus()};
 async function decode(token){
  if(token!==generation)return;
  if(await native(video,status,token))return;
  status.textContent='Cámara activa. Cargando lector…';const ZX=await loadZXing();if(token!==generation)return;
  const reader=new ZX.BrowserMultiFormatReader();scanning=true;
  const controls=await reader.decodeFromStream(stream,video,result=>{if(token!==generation)return;const code=typeof result==='string'?result:(result?.getText?.()||result?.text||result?.rawValue||'');if(code)fill(code)});
  if(token!==generation){controls?.stop();return}zxingControls=controls;status.textContent='Apunte la cámara al código de barras';
 }
 function failed(e,stage,token){if(token!==generation)return;clearTimeout(pendingTimer);retry.disabled=false;host.querySelector('.diagnostic').hidden=false;const diagnostic=host.querySelector('.diagnosticCode');diagnostic.hidden=false;diagnostic.textContent='Cámara v3 · '+stage+' · '+(e?.name||'Error')+' · '+String(e?.message||'').slice(0,240);
  if(stage==='play'&&e?.name==='NotAllowedError'){
   status.textContent='Cámara autorizada. Toca «Iniciar vídeo» para mostrar la imagen.';retry.textContent='Iniciar vídeo';retry.onclick=()=>play(token);return;
  }
  release();retry.textContent='Reintentar cámara';retry.onclick=acquire;
  if(stage==='camera'&&['NotAllowedError','SecurityError'].includes(e?.name)){
   status.textContent='El navegador no permite acceder a la cámara.';help.hidden=false;help.textContent='En iPhone: abre GAMA en Safari, entra en el menú de la página → ajustes del sitio → Cámara y permite el acceso. Después toca Reintentar cámara. Si lo abres desde el icono de inicio, cierra y vuelve a abrir GAMA tras cambiar el permiso.';
  }else status.textContent=stage==='decoder'?'No se pudo cargar el lector. Comprueba tu conexión y reintenta.':e?.name==='NotFoundError'?'No se encontró una cámara disponible.':e?.name==='NotReadableError'?'La cámara está ocupada. Cierra otras aplicaciones que la utilicen y reintenta.':'No se pudo iniciar la cámara. Reintenta o introduce el código.';
 }
 async function play(token){if(token!==generation)return;retry.disabled=true;let timer;try{await Promise.race([video.play(),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('VIDEO_TIMEOUT')),12000)})])}catch(e){failed(e,'play',token);return}finally{clearTimeout(timer)}if(token!==generation)return;retry.disabled=false;retry.textContent='Reintentar cámara';retry.onclick=acquire;try{await decode(token)}catch(e){failed(e,'decoder',token)}}
 async function acquire(){
  const token=++generation;release();help.hidden=true;host.querySelector('.diagnostic').hidden=true;host.querySelector('.diagnosticCode').hidden=true;retry.disabled=true;retry.textContent='Reintentar cámara';status.textContent='Activando cámara…';
  pendingTimer=setTimeout(()=>{if(token!==generation)return;generation++;release();status.textContent='La cámara no respondió. Acepta el permiso si aparece y vuelve a intentar.';retry.disabled=false},15000);
  try{
   if(!navigator.mediaDevices?.getUserMedia)throw Error('CAMERA_UNAVAILABLE');
   let incoming;
   try{incoming=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'},width:{ideal:1280},height:{ideal:720}},audio:false})}
   catch(e){if(token!==generation)return;if(e?.name!=='OverconstrainedError')throw e;incoming=await navigator.mediaDevices.getUserMedia({video:{facingMode:'environment'},audio:false})}
   if(token!==generation){stopTracks(incoming);return}clearTimeout(pendingTimer);stream=incoming;video.srcObject=stream;
   await play(token);
  }catch(e){failed(e,'camera',token)}
 }
 retry.onclick=acquire;await acquire();
}
window.addEventListener('pagehide',close);
document.addEventListener('visibilitychange',()=>{if(document.hidden&&overlay)close()});
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&overlay)close()});
window.scan=id=>start(id);window.startGamaScan=start;
function bindInitial(){style();document.querySelectorAll('button').forEach(b=>{if(/escane|scanner/i.test(b.textContent||'')){const input=b.closest('.scanner')?.querySelector('input')||getTarget();if(input){b.classList.add('gamaPhoneScanBtn');b.type='button'}}})}
document.addEventListener('click',e=>{const b=e.target.closest?.('button');if(!b||!b.classList.contains('gamaPhoneScanBtn'))return;e.preventDefault();e.stopImmediatePropagation();const input=b.closest('.scanner')?.querySelector('input')||getTarget();if(input)start(input.id)},true);
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',bindInitial,{once:true});else bindInitial();
})();