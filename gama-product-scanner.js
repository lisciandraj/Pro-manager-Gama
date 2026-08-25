/* GAMA V10 — dedicated product creation barcode scanner */
(function(){
'use strict';
const ORANGE='#F47A2A';
let overlay=null,stream=null,raf=0,readerControls=null;
function css(){
 if(document.getElementById('gamaProductScannerStyle'))return;
 const s=document.createElement('style');s.id='gamaProductScannerStyle';s.textContent=`
 .gamaScanOrange,.gamaPhoneScanBtn{background:${ORANGE}!important;color:#fff!important;border-color:${ORANGE}!important;box-shadow:0 3px 10px rgba(244,122,42,.20)!important}
 .gamaScanOrange:active,.gamaPhoneScanBtn:active{transform:scale(.98)}
 #gamaProductScanner{position:fixed;inset:0;z-index:100001;background:#08181f;color:#fff;display:flex;flex-direction:column;padding:18px;box-sizing:border-box;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
 #gamaProductScanner .gpsh{display:flex;align-items:center;justify-content:space-between;margin-bottom:12px}
 #gamaProductScanner .gpsv{position:relative;flex:1;overflow:hidden;border-radius:18px;background:#000}
 #gamaProductScanner video{width:100%;height:100%;object-fit:cover}
 #gamaProductScanner .gpsf{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:min(80vw,430px);height:175px;border:3px solid #37c98f;border-radius:18px;box-shadow:0 0 0 9999px rgba(0,0,0,.28)}
 #gamaProductScanner .gpsstatus{text-align:center;font-weight:700;font-size:14px;padding:14px 4px 4px}
 #gamaProductScanner .gpsclose{border:0;background:#fff;color:#173246;border-radius:12px;padding:10px 14px;font-weight:800}
 `;document.head.appendChild(s);
}
function dedupeProductButtons(){
 const input=document.getElementById('pBarcode');
 if(!input)return;
 const scanner=input.closest('.scanner')||input.parentElement;
 if(!scanner)return;
 const keep=[...scanner.querySelectorAll('button')].find(b=>/escane|scanner/i.test(b.textContent||''));
 if(keep)keep.classList.add('gamaScanOrange');
 /* Remove any second scanner button injected into the Products card by an older helper. */
 const productSection=document.getElementById('products');
 if(!productSection)return;
 const all=[...productSection.querySelectorAll('button')].filter(b=>/escane|scanner/i.test(b.textContent||''));
 all.forEach(b=>{if(b!==keep)b.remove()});
}
function setBarcode(value){
 const v=String(value??'').trim();if(!v)return false;
 const input=document.getElementById('pBarcode');if(!input)return false;
 const setter=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value')?.set;
 const apply=()=>{const el=document.getElementById('pBarcode');if(el){if(setter)setter.call(el,v);else el.value=v}};
 apply();
 try{input.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:v}))}catch(e){input.dispatchEvent(new Event('input',{bubbles:true}))}
 input.dispatchEvent(new Event('change',{bubbles:true}));
 setTimeout(apply,0);setTimeout(apply,100);setTimeout(apply,300);
 try{input.focus({preventScroll:true})}catch(e){try{input.focus()}catch(_) {}}
 return true;
}
function close(){if(raf)cancelAnimationFrame(raf);raf=0;if(readerControls){try{readerControls.stop()}catch(e){}readerControls=null}if(stream){stream.getTracks().forEach(t=>{try{t.stop()}catch(e){}});stream=null}if(overlay){overlay.remove();overlay=null}}
function loadZXing(){return new Promise((resolve,reject)=>{if(window.ZXingBrowser)return resolve(window.ZXingBrowser);const s=document.createElement('script');s.src='https://unpkg.com/@zxing/browser@0.2.1';s.onload=()=>window.ZXingBrowser?resolve(window.ZXingBrowser):reject(Error('ZXing no disponible'));s.onerror=()=>reject(Error('No se pudo cargar el lector'));document.head.appendChild(s)})}
async function nativeScan(video,status){
 if(!('BarcodeDetector'in window))return false;
 try{let fs=['ean_13','ean_8','upc_a','upc_e','code_128','code_39','code_93','itf','qr_code','data_matrix'];const supported=await BarcodeDetector.getSupportedFormats();fs=fs.filter(x=>supported.includes(x));if(!fs.length)return false;const detector=new BarcodeDetector({formats:fs});const loop=async()=>{if(!overlay)return;try{if(video.readyState>=2){const found=await detector.detect(video);const code=found?.[0]?.rawValue;if(code){setBarcode(code);close();return}}}catch(e){}raf=requestAnimationFrame(loop)};status.textContent='Apunte la cámara al código de barras';raf=requestAnimationFrame(loop);return true}catch(e){return false}
}
async function openProductScanner(){
 dedupeProductButtons();close();css();
 overlay=document.createElement('div');overlay.id='gamaProductScanner';overlay.innerHTML='<div class="gpsh"><strong>Escanear código de barras</strong><button class="gpsclose" type="button">Cerrar</button></div><div class="gpsv"><video playsinline autoplay muted></video><div class="gpsf"></div></div><div class="gpsstatus">Activando cámara…</div>';
 document.body.appendChild(overlay);overlay.querySelector('.gpsclose').onclick=close;
 const video=overlay.querySelector('video'),status=overlay.querySelector('.gpsstatus');
 try{if(!navigator.mediaDevices?.getUserMedia)throw Error('camera');stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'},width:{ideal:1280},height:{ideal:720}},audio:false});video.srcObject=stream;await video.play();if(await nativeScan(video,status))return;status.textContent='Preparando lector…';const ZX=await loadZXing();const r=new ZX.BrowserMultiFormatReader();readerControls=await r.decodeFromStream(stream,video,result=>{const code=result?.getText?.()||result?.text||result?.rawValue||'';if(code){setBarcode(code);close()}});status.textContent='Apunte la cámara al código de barras';}catch(e){status.textContent=e?.name==='NotAllowedError'?'Permita el acceso a la cámara en Safari.':'No se pudo activar el lector.'}
}
window.startProductBarcodeScan=openProductScanner;
function bind(){css();dedupeProductButtons();document.querySelectorAll('button').forEach(b=>{const t=(b.textContent||'').toLowerCase();if(t.includes('escane')||t.includes('scanner'))b.classList.add('gamaScanOrange')})}
function boot(){bind();new MutationObserver(()=>bind()).observe(document.body,{subtree:true,childList:true})}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
