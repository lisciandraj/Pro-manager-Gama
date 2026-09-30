/* Company document helpers. Kept independent of the DOM for validation and tests. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.GamaCompanyCore=api})(typeof window!=='undefined'?window:globalThis,function(){
'use strict';
const defaults={legal_name:'',address:'',tax_id:'',phone:'',email:'',website:'',currency:'USD',country:'EC',logo_data:'',document_primary:'#18324A',document_secondary:'#087C8B',company_version:0,configured:false,localization_country:null};
const hex=v=>/^#[0-9a-f]{6}$/i.test(v||'');
function rgb(value){return hex(value)?[1,3,5].map(i=>parseInt(value.slice(i,i+2),16)):[24,50,74]}
function toHex(v){return '#'+v.map(x=>Math.max(0,Math.min(255,Math.round(x))).toString(16).padStart(2,'0')).join('').toUpperCase()}
function luminance(value){return rgb(value).map(x=>{x/=255;return x<=.04045?x/12.92:((x+.055)/1.055)**2.4}).reduce((s,x,i)=>s+x*[.2126,.7152,.0722][i],0)}
function foreground(value){return luminance(value)>.179?'#0B172A':'#FFFFFF'}
function textColor(value){let c=rgb(value);while((luminance(toHex(c))+.05)>.2333)c=c.map(x=>x*.92);return toHex(c)}
function fit(width,height,boxWidth,boxHeight){const k=Math.min(boxWidth/width,boxHeight/height);return {width:width*k,height:height*k}}
function palette(pixels){
 const bins=new Map();
 for(let i=0;i<pixels.length;i+=4){const c=[pixels[i],pixels[i+1],pixels[i+2]],a=pixels[i+3];if(a<128||Math.min(...c)>242)continue;const key=c.map(x=>Math.round(x/24)).join(':');let b=bins.get(key);if(!b){b={count:0,sum:[0,0,0]};bins.set(key,b)}b.count++;c.forEach((x,j)=>b.sum[j]+=x)}
 const distance=(a,b)=>Math.sqrt(a.reduce((s,x,i)=>s+(x-b[i])**2,0));
 const clusters=[];
 for(const b of [...bins.values()].sort((a,b)=>b.count-a.count)){const c=b.sum.map(x=>x/b.count),near=clusters.find(x=>distance(x.rgb,c)<48);if(near){near.rgb=near.rgb.map((x,i)=>(x*near.count+c[i]*b.count)/(near.count+b.count));near.count+=b.count}else clusters.push({rgb:c,count:b.count})}
 clusters.sort((a,b)=>b.count-a.count);if(!clusters.length)return [defaults.document_primary,defaults.document_secondary];
 const first=clusters[0],second=clusters.find((x,i)=>i&&x.count>=first.count*.025&&distance(x.rgb,first.rgb)>=65);
 return [toHex(first.rgb),second?toHex(second.rgb):toHex(first.rgb.map(x=>x*.55+255*.45))];
}
function validate(profile){
 if(!String(profile.legal_name||'').trim())return 'name_required';
 if(!/^[A-Z]{2}$/.test(profile.country||''))return 'country_invalid';
 if(!/^[A-Z]{3}$/.test(profile.currency||''))return 'currency_invalid';
 if(profile.email&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(profile.email))return 'email_invalid';
 if(profile.website&&!/^https?:\/\/[^\s]+$/i.test(profile.website))return 'website_invalid';
 if(!hex(profile.document_primary)||!hex(profile.document_secondary))return 'color_invalid';
 return null;
}
return {defaults,hex,rgb,toHex,luminance,foreground,textColor,fit,palette,validate};
});
