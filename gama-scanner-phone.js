/* GAMA phone barcode scanner: real camera scanner with reliable target-field autofill. */
(function(){
'use strict';
const ZXING_URL='https://unpkg.com/@zxing/browser@0.2.1';
let overlay=null, stream=null, zxingControls=null, scanning=false, scanTarget=null;
function norm(v){return (v||'').replace(/\s+/g,' ').trim().toLowerCase();}
function removeInactiveBack(){
 document.querySelectorAll('a,button').forEach(el=>{
   const t=norm(el.textContent);
   if(t==='‹ menú principal'||t==='menu principal'&&/^‹/.test(el.textContent.trim())){
     el.style.display='none';
     el.setAttribute('aria-hidden','true');
   }
 });
}
function findBarcodeInput(preferredButton){
 const local=preferredButton?.closest('.scanner')?.querySelector('input[placeholder*="Código de barras" i],input[name*="barcode" i],input[id*="barcode" i],input');
 if(local)return local;
 return document.querySelector('input[placeholder*="Código de barras" i]')||document.querySelector('input[name*="barcode" i]')||document.querySelector('input[id*="barcode" i]');
}
function ensureUI(){
 if(document.getElementById('gamaScannerPhoneStyle'))return;
 const st=document.createElement('style');st.id='gamaScannerPhoneStyle';st.textContent=`.gamaPhoneScanBtn{background:#128c68!important;color:#fff!important;border-color:#128c68!important;box-shadow:0 3px 10px rgba(18,140,104,.2)!important}.gamaPhoneScanBtn:active{transform:scale(.98)}#gamaPhoneScanner{position:fixed;inset:0;z-index:10000;background:rgba(8,24,31,.96);display:flex;flex-direction:column;padding:18px;box-sizing:border-box;color:#fff}#gamaPhoneScanner .gpsHead{display:flex;align-items:center;justify-content:space-between;margin-bottom:12px}#gamaPhoneScanner .gpsTitle{font-size:18px;font-weight:800}#gamaPhoneScanner .gpsClose{border:0;background:#fff;color:#173246;border-radius:12px;padding:10px 14px;font-weight:800}#gamaPhoneScanner .gpsVideoWrap{position:relative;flex:1;display:flex;align-items:center;justify-content:center;overflow:hidden;border-radius:18px;background:#000}#gamaPhoneScanner video{width:100%;height:100%;object-fit:cover}#gamaPhoneScanner .gpsFrame{position:absolute;width:min(78vw,420px);height:170px;border:3px solid #37c98f;border-radius:18px;box-shadow:0 0 0 9999px rgba(0,0,0,.28)}#gamaPhoneScanner .gpsStatus{text-align:center;font-size:14px;font-weight:700;padding:14px 6px 6px;color:#dce9e8}#gamaPhoneScanner .gpsTorch{margin-top:8px;border:1px solid #4a646c;background:#17343b;color:#fff;border-radius:12px;padding:10px;font-weight:700}`;document.head.appendChild(st);
}
function getButton(){
 return [...document.querySelectorAll('button')].find(b=>norm(b.textContent).includes('escanear'))||null;
}
function fillCode(code){
 const input=scanTarget||findBarcodeInput();
 if(input){
   input.value=String(code).trim();
   input.dispatchEvent(new Event('input',{bubbles:true}));
   input.dispatchEvent(new Event('change',{bubbles:true}));
   input.dispatchEvent(new Event('blur',{bubbles:true}));
   input.focus();
   if(input.id==='invoiceBarcode'){
     const p=window.product?window.product(input.value.trim()):null;
     const info=document.getElementById('invoiceProductInfo');
     if(info)info.textContent=p?`${p.name} — Precio: $${Number(p.price||0).toFixed(2)} — Stock: ${p.stock}`:'Producto no encontrado';
   }else if(input.id==='moveBarcode'){
     const p=window.product?window.product(input.value.trim()):null;
     const info=document.getElementById('moveInfo');
     if(info)info.textContent=p?`${p.name} — stock actual: ${p.stock}`:'Producto no encontrado';
   }
 }
 closeScanner();
}
function closeScanner(){
 scanning=false;
 if(zxingControls){try{zxingControls.stop()}catch(e){}zxingControls=null;}
 if(stream){stream.getTracks().forEach(t=>t.stop());stream=null;}
 if(overlay){overlay.remove();overlay=null;}
}
function loadZXing(){
 return new Promise((resolve,reject)=>{
   if(window.ZXingBrowser)return resolve(window.ZXingBrowser);
   const s=document.createElement('script');s.src=ZXING_URL;s.onload=()=>window.ZXingBrowser?resolve(window.ZXingBrowser):reject(new Error('ZXing no disponible'));s.onerror=()=>reject(new Error('No se pudo cargar el escáner'));document.head.appendChild(s);
 });
}
async function nativeScan(video,status){
 if(!('BarcodeDetector' in window))return false;
 let formats=['ean_13','ean_8','upc_a','upc_e','code_128','code_39','code_93','itf','qr_code','data_matrix'];
 try{const supported=await BarcodeDetector.getSupportedFormats();formats=formats.filter(f=>supported.includes(f));if(!formats.length)return false;}catch(e){return false;}
 const detector=new BarcodeDetector({formats});
 scanning=true;
 const loop=async()=>{
   if(!scanning)return;
   try{if(video.readyState>=2){const codes=await detector.detect(video);if(codes.length&&codes[0].rawValue){fillCode(codes[0].rawValue);return;}}}catch(e){}
   requestAnimationFrame(loop);
 };
 requestAnimationFrame(loop);status.textContent='Apunte la cámara al código de barras';return true;
}
async function startScanner(targetInput){
 if(overlay)closeScanner();
 scanTarget=targetInput||findBarcodeInput();
 ensureUI();
 overlay=document.createElement('div');overlay.id='gamaPhoneScanner';
 overlay.innerHTML='<div class="gpsHead"><div class="gpsTitle">Escanear código de barras</div><button class="gpsClose" type="button">Cerrar</button></div><div class="gpsVideoWrap"><video playsinline muted autoplay></video><div class="gpsFrame"></div></div><div class="gpsStatus">Activando cámara…</div><button class="gpsTorch" type="button" style="display:none">Linterna</button>';
 document.body.appendChild(overlay);
 const video=overlay.querySelector('video'),status=overlay.querySelector('.gpsStatus'),close=overlay.querySelector('.gpsClose'),torch=overlay.querySelector('.gpsTorch');close.onclick=closeScanner;
 try{
   stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'},width:{ideal:1280},height:{ideal:720}},audio:false});
   video.srcObject=stream;await video.play();
   const track=stream.getVideoTracks()[0];const caps=track.getCapabilities?track.getCapabilities():{};
   if(caps.torch){torch.style.display='block';torch.onclick=()=>{track.applyConstraints({advanced:[{torch:!track.__gamaTorch}]}).then(()=>track.__gamaTorch=!track.__gamaTorch).catch(()=>{});};}
   if(await nativeScan(video,status))return;
   status.textContent='Preparando el lector…';
   const ZX=await loadZXing();const reader=new ZX.BrowserMultiFormatReader();scanning=true;
   zxingControls=await reader.decodeFromStream(stream,video,(result)=>{if(result&&result.getText){fillCode(result.getText());}});
   status.textContent='Apunte la cámara al código de barras';
 }catch(err){
   status.textContent=err&&err.name==='NotAllowedError'?'Permita el acceso a la cámara en Safari.':'No se pudo activar la cámara.';
 }
}
function bind(){
 removeInactiveBack();ensureUI();
 const btn=getButton();
 if(btn&&!btn.dataset.gamaPhoneScanner){
   btn.dataset.gamaPhoneScanner='1';btn.classList.add('gamaPhoneScanBtn');
   const clone=btn.cloneNode(true);clone.classList.add('gamaPhoneScanBtn');clone.dataset.gamaPhoneScanner='1';btn.replaceWith(clone);
   clone.addEventListener('click',e=>{
     e.preventDefault();e.stopImmediatePropagation();
     const target=findBarcodeInput(clone);
     startScanner(target);
   },true);
 }
}
function boot(){bind();if(window.showTab&&!window.showTab.__gamaScanner){const old=window.showTab;window.showTab=function(){const r=old.apply(this,arguments);setTimeout(bind,40);return r};window.showTab.__gamaScanner=true;}}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
