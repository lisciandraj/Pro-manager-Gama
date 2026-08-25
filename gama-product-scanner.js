/* GAMA V10 — product creation scanner + page navigation cleanup */
(function(){
'use strict';
const ORANGE='#F47A2A';
function css(){
 if(document.getElementById('gamaProductScannerStyle'))return;
 const s=document.createElement('style');s.id='gamaProductScannerStyle';s.textContent=`
 .gamaScanOrange,.gamaPhoneScanBtn{background:${ORANGE}!important;color:#fff!important;border-color:${ORANGE}!important;box-shadow:0 3px 10px rgba(244,122,42,.20)!important}
 .gamaScanOrange:active,.gamaPhoneScanBtn:active{transform:scale(.98)}
 .gamaProductScanRow{display:grid;grid-template-columns:1fr auto;gap:7px;align-items:end}
 .gamaProductScanBtn{height:46px;white-space:nowrap}
 @media(max-width:700px){.gamaProductScanRow{grid-template-columns:1fr auto}.gamaProductScanBtn{padding:11px 12px}}
 `;document.head.appendChild(s);
}
function removeBack(){
 document.querySelectorAll('.pageBack').forEach(x=>x.remove());
 // Remove any remaining legacy back button pointing to main menu.
 document.querySelectorAll('button').forEach(b=>{
  const t=(b.textContent||'').replace(/\s+/g,' ').trim().toLowerCase();
  if(t==='‹ menú principal'||t==='menu principal'||t.includes('‹ menú principal'))b.remove();
 });
}
function productButton(){
 if(document.getElementById('gamaProductScanBtn'))return;
 const input=document.getElementById('pBarcode');if(!input)return;
 const wrap=input.parentElement;
 if(!wrap)return;
 const row=document.createElement('div');row.className='gamaProductScanRow';
 wrap.parentNode.insertBefore(row,wrap);row.appendChild(wrap);
 const b=document.createElement('button');b.id='gamaProductScanBtn';b.type='button';b.className='gamaScanOrange gamaProductScanBtn';b.textContent='📷 Escanear';
 b.onclick=()=>{
  if(typeof window.startGamaScan==='function')window.startGamaScan('pBarcode');
  else if(typeof window.scan==='function')window.scan('pBarcode');
  else alert('Scanner non disponible. Rechargez la page.');
 };
 row.appendChild(b);
}
function bind(){css();removeBack();productButton();
 document.querySelectorAll('button').forEach(b=>{
  const t=(b.textContent||'').toLowerCase();
  if(t.includes('escane')||t.includes('scanner'))b.classList.add('gamaScanOrange');
 });
}
function boot(){bind();new MutationObserver(()=>bind()).observe(document.body,{subtree:true,childList:true});}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
