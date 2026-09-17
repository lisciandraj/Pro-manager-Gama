/* GAMA — one money formatter for the whole application.

   Every module used to carry its own `money()` with the currency written into
   it, so changing the company currency meant editing a dozen files and missing
   some. The amount and the currency are data; how they read is this function's
   job, and only this function's.

   The code comes from company_settings in the cloud. It is cached in
   localStorage so the first paint after a reload shows the right symbol instead
   of flashing the default, and every module repaints on gama:currency-change. */
(function(){
'use strict';
if(window.GamaCurrency)return;
const KEY='gama_company_currency_v1';
let currency='USD';
try{const saved=localStorage.getItem(KEY);if(/^[A-Z]{3}$/.test(saved||''))currency=saved}catch(e){}
const locale=()=>window.GamaI18n?.locale||'es-EC';

/* narrowSymbol keeps «$2.500,00» in Ecuador and «€2.500,00» if the company
   switches to euros, instead of the bare ISO code some locales fall back to. */
function format(amount,code){
 const iso=/^[A-Z]{3}$/.test(code||'')?code:currency;
 const value=Number(amount);
 const safe=Number.isFinite(value)?value:0;
 const options={style:'currency',currency:iso,minimumFractionDigits:2,maximumFractionDigits:2};
 try{return safe.toLocaleString(locale(),{...options,currencyDisplay:'narrowSymbol'})}
 catch(e){}
 try{return safe.toLocaleString(locale(),options)}
 catch(e){return iso+' '+safe.toFixed(2)}
}
/* Amounts without a currency: quantities, rates, counts. Same locale rules. */
function number(value,digits){
 const safe=Number.isFinite(Number(value))?Number(value):0;
 return safe.toLocaleString(locale(),{maximumFractionDigits:digits==null?2:digits});
}
function set(code){
 if(!/^[A-Z]{3}$/.test(code||'')||code===currency)return currency;
 currency=code;
 try{localStorage.setItem(KEY,code)}catch(e){}
 window.dispatchEvent(new CustomEvent('gama:currency-change',{detail:{currency}}));
 return currency;
}
async function load(){
 try{
  await window.GamaCloudReady;
  const r=await window.GamaCloud.list('company_settings',{select:'currency,country',limit:1});
  if(!r.error&&r.data&&r.data[0]&&r.data[0].currency)set(r.data[0].currency);
 }catch(e){/* Offline keeps the cached code; a wrong symbol beats a blank screen. */}
 return currency;
}
/* The bare symbol, for the PDF generators that lay text out column by column
   and cannot take a formatted string. Derived from the locale, never a table. */
function symbol(code){
 const iso=/^[A-Z]{3}$/.test(code||'')?code:currency;
 try{return format(0,iso).replace(/[\s\u00a0]/g,'').replace(/[\d.,]/g,'')||iso}
 catch(e){return iso}
}
window.GamaCurrency={format,formatCurrency:format,number,symbol,get:()=>currency,set,load};
/* The short name modules call. Kept on window so a module needs no import. */
window.formatCurrency=format;
if(window.GamaCloudReady)window.GamaCloudReady.then(load).catch(()=>{});
else window.addEventListener('gama:cloud-script-loaded',()=>{window.GamaCloudReady&&window.GamaCloudReady.then(load).catch(()=>{})},{once:true});
})();
